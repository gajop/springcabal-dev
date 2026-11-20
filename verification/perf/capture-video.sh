#!/usr/bin/env bash
# Capture real GPU output with the existing screenshot input action, then encode.
# These instrumented runs are excluded from timing aggregates.
set -euo pipefail
project=$(cd -- "$(dirname -- "$0")/../.." && pwd)
out=${1:?Usage: capture-video.sh OUTPUT [--encode-only] [--case NAME] [--games-dir PATH] [--effects-module PATH] [--worker-threads N]}
shift
mkdir -p "$out"
python3 - "$project" "$(realpath -- "$out")" "$@" <<'PY'
import argparse, json, os
from pathlib import Path
import signal, subprocess, sys
from tempfile import TemporaryDirectory
project, root = map(Path, sys.argv[1:3])
sys.path.insert(0, str(project/'verification/perf'))
from report import read_result
from run import VerificationLease, sha


def terminate(signum, _frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, terminate)


def video_info(path):
    if not path.is_file():
        return None
    probe = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream=width,height,nb_frames,r_frame_rate,duration',
        '-of', 'json', str(path)], capture_output=True, text=True)
    if probe.returncode:
        return None
    streams = json.loads(probe.stdout)['streams']
    if len(streams) == 1 and streams[0].get('nb_frames') == '200' and streams[0].get('r_frame_rate') == '10/1':
        return streams[0]
    return None


def encode_video(frames, video):
    with TemporaryDirectory(prefix=video.stem+'-', dir=root) as scratch:
        scratch = Path(scratch)
        for index, image in enumerate(frames):
            (scratch/f'{index:04d}.png').symlink_to(image.resolve())
        temporary = scratch/'capture.mp4'
        subprocess.run(['ffmpeg', '-v', 'error', '-nostdin', '-framerate', '10',
            '-i', str(scratch/'%04d.png'), '-c:v', 'libx264', '-preset', 'fast',
            '-crf', '20', '-pix_fmt', 'yuv420p', '-movflags', '+faststart',
            str(temporary)], check=True)
        info = video_info(temporary)
        if info is None:
            raise ValueError('Encoded frame count mismatch: '+str(video))
        temporary.replace(video)
    return info


def discard_rejected_frames(directory, game):
    for status in directory.glob(f'{game}-*/result.json'):
        result = read_result(status)
        if result['ok'] and not result['contended']:
            continue
        for image in (status.parent/'write/screenshots').glob('*.png'):
            image.unlink()


p=argparse.ArgumentParser();p.add_argument('--encode-only',action='store_true');p.add_argument('--case',action='append');p.add_argument('--keep-frames',action='store_true',help='retain source PNGs after the MP4 is verified')
p.add_argument('--games-dir',type=Path,default=Path(os.environ.get('VF_GAMES_DIR',str(project/'spring-linux/games'))),help='frozen game roots to record, also accepted through VF_GAMES_DIR')
p.add_argument('--max-minutes',type=int,default=30,help='resource-wait limit for each capture')
p.add_argument('--effects-module',type=Path,help='frozen Gravitas fire probe used by the matching timing campaign')
p.add_argument('--worker-threads',type=int,default=1,help='worker count from the matching timing campaign')
a=p.parse_args(sys.argv[3:])
if a.worker_threads < 1:p.error('worker-threads must be positive')
manifest=root/'videos.json'
cases=[]
for game, scene, prefix in [('hunted','autonomous','hunted'),('flove','scripted','flove-combat'),('ttld','scripted','ttld-shadows'),('area17','autonomous','area17')]:
    for mult in ([1,2] if game=='area17' else [1,10]):
        name=f'{prefix}-{mult}x';options=['--unit-multiplier',str(mult)]
        if scene=='scripted':options+=['--input',str(project/'verification/perf/scenarios'/('flove-mushrooms.txt' if game=='flove' else 'ttld-shadows.txt'))]
        cases.append((name,game,scene,options))
# Additional production-fire controls are explicit; ordinary capture-all
# continues to use the shipping game roots without a synthetic fire input.
if a.case and any(name.startswith('ttld-burning-') for name in a.case):
    expected=project/'verification/fixtures/ttld/production_fire.lua'
    for backend in ['ToTheLastDrop.sdd','ToTheLastDrop-wasm.sdd']:
        staged=a.games_dir/backend/'LuaRules/Gadgets/zz_perf_production_fire.lua'
        if not staged.is_file() or staged.read_bytes()!=expected.read_bytes():raise ValueError('Production-fire capture requires the recorded frozen public-input fixture: '+str(staged))
    for mult in [1,10]:
        cases.append((f'ttld-burning-{mult}x','ttld','scripted',['--unit-multiplier',str(mult),'--input',str(project/'verification/perf/scenarios/ttld-shadows.txt')]))
for count in [1,10,100]:cases.append((f'fire-{count}','gravitas','effects',['--effects-multiplier',str(count)]))
for game in ['mycube','partsneeded']:cases.append((f'{game}-1x',game,'autonomous',[]))
unknown=set(a.case or ())-{name for name, *_ in cases}
if unknown:p.error('unknown capture case: '+', '.join(sorted(unknown)))
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
        if scene=='effects' and a.effects_module:options+=['--effects-module',str(a.effects_module.resolve())]
        try:
            subprocess.run([str(project/'verification/verify'),'perf',game,scene,'--mode','gpu','--callback-timers','off','--frame-step','--diagnostic','--repeats','1',
                '--wait-for-idle','--wait-for-gpu-idle','--clean-pairs','1',
                '--worker-threads',str(a.worker_threads),'--cpu-affinity','0,2,4,6,8,10,12,14','--timeout','300','--max-minutes',str(a.max_minutes),
                '--input',str(requests),'--output',str(directory),'--games-dir',str(a.games_dir.resolve()),*options],check=True)
        except subprocess.CalledProcessError:
            if not a.keep_frames:
                with VerificationLease():
                    discard_rejected_frames(directory, game)
            raise

    with VerificationLease():
        if not a.keep_frames:
            discard_rejected_frames(directory, game)
        pairs = {}
        for status in sorted(directory.glob(f'{game}-*/result.json')):
            result = read_result(status)
            if (result['ok'] and not result['contended'] and result.get('instrumented')
                    and result['renderer'] == 'NVIDIA GeForce GTX 1660 Ti/PCIe/SSE2'):
                pairs.setdefault(result['repeat'], []).append((status.parent, result))
        pair = next((runs for _, runs in sorted(pairs.items())
                     if len(runs) == 2 and {result['backend'] for _, result in runs} == {'lua', 'wasm'}), None)
        if pair is None:
            raise ValueError('No clean complete NVIDIA capture pair: '+str(directory))

        clips = json.loads(manifest.read_text()) if manifest.exists() else []
        previous = {clip['backend']: clip for clip in clips if clip['case'] == name}
        new_clips = []
        used_frames = []
        for run_path, result in pair:
            backend = result['backend']
            frames = sorted((run_path/'write/screenshots').glob('*.png'))
            video = root/f'{name}-{backend}.mp4'
            info = video_info(video) if a.encode_only else None
            receipt = previous.get(backend)
            if info is not None and receipt:
                if Path(receipt['source']).resolve() != run_path.resolve() or sha(video) != receipt['sha256']:
                    info = None
            if info is None:
                if len(frames) != 200:
                    raise ValueError(f'Expected 200 PNGs to encode {video}, found {len(frames)} in {run_path}')
                info = encode_video(frames, video)
            new_clips.append({'case':name,'backend':backend,'file':video.name,'label':('Lua' if backend=='lua' else 'Rust · serial')+' · '+name,
                'url':'videos/'+video.name,'renderer':result['renderer'],'sha256':sha(video),
                'capture_requests':{'first_frame':300,'last_frame':897,'interval':3},'video':info,'source':str(run_path)})
            used_frames.extend(frames)
        clips = [clip for clip in clips if clip['case'] != name] + new_clips
        temporary_manifest = manifest.with_suffix('.json.new')
        temporary_manifest.write_text(json.dumps(clips,indent=2)+'\n')
        temporary_manifest.replace(manifest)
        if not a.keep_frames:
            for image in used_frames:
                image.unlink()
PY
