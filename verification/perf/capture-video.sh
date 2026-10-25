#!/usr/bin/env bash
# The existing screenshot input action captures the actual GPU fire fixture.
# PNG capture and CPU sampling make these diagnostic runs, never timing baselines.
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/../.." && pwd)
out=${1:?Usage: capture-video.sh /absolute/output [--encode-only]}
mkdir -p "$out"
out=$(realpath -- "$out")
if [[ "${2:-}" != --encode-only ]]; then
python3 - "$out/input.txt" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(''.join(f'{f}: local screenshot png\n' for f in range(300, 900, 3)))
PY
common=(gravitas effects --frame-step --diagnostic --repeats 1 --worker-threads 4
    --effects-multiplier 10 --input "$out/input.txt" --cpu-pressure-scope cgroup
    --timeout 300 --max-minutes 20)
"$project/verification/verify" perf "${common[@]}" --output "$out/serial"
"$project/verification/verify" perf "${common[@]}" --output "$out/jobs" --backend wasm --rust-jobs on
fi
python3 - "$out" <<'PY'
import hashlib, json
from pathlib import Path
import subprocess, sys
root=Path(sys.argv[1]); clips=[]
for case, run, name, label in [
    ('serial','gravitas-00-lua','fire10-lua','Lua · 10 emitter pairs'),
    ('serial','gravitas-00-wasm','fire10-rust','Rust · serial · 10 emitter pairs'),
    ('jobs','gravitas-00-wasm','fire10-rust-jobs','Rust · jobs on · 10 emitter pairs')]:
    directory=root/case/run
    result=json.loads((directory/'result.json').read_text())
    if not result['ok'] or result['renderer']!='NVIDIA GeForce GTX 1660 Ti/PCIe/SSE2':
        raise ValueError('Incomplete GPU video capture: '+str(directory))
    frames=sorted((directory/'write/screenshots').glob('*.png'))
    if len(frames)!=200:raise ValueError(f'Expected 200 PNGs, found {len(frames)} in {directory}')
    sequence=root/(name+'-sequence');sequence.mkdir(exist_ok=True)
    for i, image in enumerate(frames):
        link=sequence/f'{i:04d}.png'
        if not link.exists():link.symlink_to(image)
    video=root/(name+'.mp4')
    if not video.exists():
        subprocess.run(['ffmpeg','-v','error','-nostdin','-framerate','10','-i',str(sequence/'%04d.png'),
            '-c:v','libx264','-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],check=True)
    info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries',
        'stream=width,height,nb_frames,r_frame_rate,duration','-of','json',str(video)],text=True))
    if info['streams'][0]['nb_frames']!='200':raise ValueError('Encoded frame count mismatch')
    clips.append({'file':video.name,'label':label,'url':'videos/'+video.name,
        'renderer':result['renderer'],'sha256':hashlib.sha256(video.read_bytes()).hexdigest(),
        'capture_requests':{'first_frame':300,'last_frame':897,'interval':3},
        'video':info['streams'][0], 'source':str(directory)})
(root/'videos.json').write_text(json.dumps(clips,indent=2)+'\n')
PY
