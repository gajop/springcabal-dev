#!/usr/bin/env bash
# Capture real GPU output with the existing screenshot input action, then encode.
# These instrumented runs are excluded from timing aggregates.
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/../.." && pwd)
out=${1:?Usage: capture-video.sh OUTPUT [--encode-only] [--case NAME]}
shift
mkdir -p "$out"
python3 - "$project" "$(realpath -- "$out")" "$@" <<'PY'
import argparse, hashlib, json
from pathlib import Path
import subprocess, sys
project, root = map(Path, sys.argv[1:3])
p=argparse.ArgumentParser();p.add_argument('--encode-only',action='store_true');p.add_argument('--case',action='append');p.add_argument('--keep-frames',action='store_true',help='retain source PNGs after the MP4 is verified')
a=p.parse_args(sys.argv[3:])
manifest=root/'videos.json'
clips=json.loads(manifest.read_text()) if manifest.exists() else []
cases=[]
for game, scene, prefix in [('hunted','autonomous','hunted'),('flove','scripted','flove-combat'),('ttld','scripted','ttld-shadows'),('area17','autonomous','area17')]:
    for mult in ([1,2] if game=='area17' else [1,10]):
        name=f'{prefix}-{mult}x';options=['--unit-multiplier',str(mult)]
        if scene=='scripted':options+=['--input',str(project/'verification/perf/scenarios'/('flove-mushrooms.txt' if game=='flove' else 'ttld-shadows.txt'))]
        cases.append((name,game,scene,options))
for count in [1,10,100]:cases.append((f'fire-{count}','gravitas','effects',['--effects-multiplier',str(count)]))
for game in ['mycube','partsneeded']:cases.append((f'{game}-1x',game,'autonomous',[]))
for name,game,scene,options in cases:
    if a.case and name not in a.case:continue
    directory=root/name
    if not a.encode_only:
        if directory.exists():raise ValueError(f'Evidence already exists: {directory}; use --encode-only or a new output directory')
        # Keep all original combat/shadow controls, and add only screenshots.
        original=''
        if '--input' in options:
            i=options.index('--input');original=Path(options[i+1]).read_text();del options[i:i+2]
        requests=root/(name+'-input.txt')
        requests.write_text(original+'\n'+''.join(f'{f}: local screenshot png\n' for f in range(300,900,3)))
        subprocess.run([str(project/'verification/verify'),'perf',game,scene,'--mode','gpu','--frame-step','--diagnostic','--repeats','1',
            '--worker-threads','1','--cpu-affinity','0,2,4,6,8,10,12,14','--timeout','300','--max-minutes','30',
            '--input',str(requests),'--output',str(directory),*options],check=True)
    for backend in ['lua','wasm']:
        run=directory/f'{game}-00-{backend}'
        result=json.loads((run/'result.json').read_text())
        if not result['ok'] or result['renderer']!='NVIDIA GeForce GTX 1660 Ti/PCIe/SSE2':raise ValueError('Incomplete GPU capture: '+str(run))
        frames=sorted((run/'write/screenshots').glob('*.png'))
        key=f'{name}-{backend}';video=root/(key+'.mp4');sequence=root/(key+'-sequence')
        if len(frames)!=200 and not (a.encode_only and not frames and video.is_file()):raise ValueError(f'Expected 200 PNGs, found {len(frames)} in {run}')
        if frames:sequence.mkdir(exist_ok=True)
        for i,image in enumerate(frames):
            link=sequence/f'{i:04d}.png'
            if not link.exists():link.symlink_to(image.resolve())
        video=root/(key+'.mp4')
        if not video.exists():
            subprocess.run(['flock','/tmp/springcabal-verify.lock','ffmpeg','-v','error','-nostdin','-framerate','10','-i',str(sequence/'%04d.png'),'-c:v','libx264',
                '-preset','fast','-crf','20','-pix_fmt','yuv420p','-movflags','+faststart',str(video)],check=True)
        info=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_entries','stream=width,height,nb_frames,r_frame_rate,duration','-of','json',str(video)],text=True))
        if info['streams'][0]['nb_frames']!='200':raise ValueError('Encoded frame count mismatch')
        clip={'case':name,'backend':backend,'file':video.name,'label':('Lua' if backend=='lua' else 'Rust · serial')+' · '+name,
            'url':'videos/'+video.name,'renderer':result['renderer'],'sha256':hashlib.sha256(video.read_bytes()).hexdigest(),
            'capture_requests':{'first_frame':300,'last_frame':897,'interval':3},'video':info['streams'][0],'source':str(run)}
        clips=[c for c in clips if (c['case'],c['backend'])!=(name,backend)]+[clip]
        manifest.write_text(json.dumps(clips,indent=2)+'\n')
        if not a.keep_frames:
            for image in frames:image.unlink()
            if sequence.exists():
                for image in sequence.glob('*.png'):
                    if image.is_symlink():image.unlink()
                if not any(sequence.iterdir()):sequence.rmdir()
PY
