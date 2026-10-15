#!/usr/bin/env python3
# This file is part of the Spring engine (GPL v2 or later), see LICENSE.html
"""Paired Lua/Wasm game measurements with provenance and equivalence checks.

Every result starts diagnostic. A completed process or plausible timing alone
never accepts a language-performance claim. Source checkouts are read-only.
"""
from __future__ import annotations
import argparse
import csv
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import shutil
import socket
import statistics
import subprocess
import sys
import tempfile
import time

PROJECT=Path(__file__).resolve().parents[2]
ENGINE=PROJECT.parent/'spring-bar'
GAMES={
 'mycube':('MyCube.sdd','MyCube-wasm.sdd'),
 'ttld':('ToTheLastDrop.sdd','ToTheLastDrop-wasm.sdd'),
 'hunted':('Hunted.sdd','Hunted-wasm.sdd'),
 'area17':('Area-17.sdd','Area17-wasm.sdd'),
 'gravitas':('Gravitas.sdd','Gravitas-wasm.sdd'),
 'flove':('Flove.sdd','Flove-wasm.sdd'),
 'partsneeded':('PartsNeeded.sdd','PartsNeeded-wasm.sdd'),
}

def save(path,value):path.write_text(json.dumps(value,indent=2)+'\n')
def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for chunk in iter(lambda:f.read(1<<20),b''):h.update(chunk)
 return h.hexdigest()
def revision(path):
 p=subprocess.run(['git','-C',str(path),'rev-parse','HEAD'],capture_output=True,text=True)
 return p.stdout.strip() if p.returncode==0 else None
def tree_hash(path):
 h=hashlib.sha256()
 for f in sorted(path.rglob('*')):
  if not f.is_file() or any(x in ('.git','target','wasm-src') for x in f.relative_to(path).parts):continue
  h.update(str(f.relative_to(path)).encode());h.update(bytes.fromhex(sha(f)))
 return h.hexdigest()
def host():
 def read(p):
  try:return Path(p).read_text().strip()
  except OSError:return None
 return {'time':datetime.now(timezone.utc).isoformat(),'load':os.getloadavg(),
  'cpu_pressure':read('/proc/pressure/cpu'),'memory_pressure':read('/proc/pressure/memory'),
  'memory':read('/proc/meminfo'),'cpu_governors':{str(p):read(p) for p in Path('/sys/devices/system/cpu').glob('cpu[0-9]*/cpufreq/scaling_governor')},
  'turbo_disabled':read('/sys/devices/system/cpu/intel_pstate/no_turbo'),
  'temperatures':{str(p):read(p) for p in Path('/sys/class/thermal').glob('thermal_zone*/temp')}}
def pressure(sample):
 text=sample.get('cpu_pressure') or ''
 m=re.search(r'some avg10=([0-9.]+)',text)
 return float(m[1]) if m else math.inf

def set_key(text,key,value):
 pattern=rf'(?im)^(\s*){re.escape(key)}\s*=[^;]*;'
 if re.search(pattern,text):return re.sub(pattern,lambda m:f'{m[1]}{key}={value};',text)
 return re.sub(r'(?i)(\[GAME\]\s*\{)',lambda m:m[0]+f'\n    {key}={value};',text,count=1)
def speed(text,value):
 entry=f'\n MinSpeed={value}; MaxSpeed={value};\n'
 text=re.sub(r'(?i)\b(?:MinSpeed|MaxSpeed)\s*=[^;]*;','',text)
 if re.search(r'(?i)\[modoptions\]\s*\{',text):return re.sub(r'(?i)(\[modoptions\]\s*\{)',lambda m:m[0]+entry,text,count=1)
 return text[:text.rfind('}')]+'\n[modoptions] {'+entry+'}\n}\n'
def rows(path):
 with path.open() as f:return list(csv.DictReader(f))
def percentile(values,p):
 values=sorted(values)
 if not values:return None
 x=(len(values)-1)*p;i=int(x);return values[i]+(values[min(i+1,len(values)-1)]-values[i])*(x-i)
def distribution(values):
 return {name:percentile(values,p) for name,p in [('p50',.5),('p95',.95),('p99',.99),('p999',.999),('max',1.)]}
def confidence(ratios):
 if len(ratios)<5:return None
 rng=random.Random(424242)
 means=[statistics.mean(rng.choices(ratios,k=len(ratios))) for _ in range(2000)]
 return [percentile(means,.025),percentile(means,.975)]
def compare(a,b):
 aa={int(r['frame']):r for r in a if r['kind']=='sim'};bb={int(r['frame']):r for r in b if r['kind']=='sim'}
 frames=sorted(aa.keys() & bb.keys())
 diverged=next((f for f in frames if aa[f]['state_digest']!=bb[f]['state_digest']),None)
 counts=all(aa[f]['units']==bb[f]['units'] and aa[f]['projectiles']==bb[f]['projectiles'] for f in frames)
 events={}
 for key in ('created','destroyed','weapon_fires','damage_events','commands','cegs','damage_total'):
  if frames and key in aa[frames[0]] and key in bb[frames[0]]:
   events[key]={'lua':sum(float(aa[f][key]) for f in frames),'wasm':sum(float(bb[f][key]) for f in frames)}
 return {'frames':len(frames),'frame_sets_equal':aa.keys()==bb.keys(),
  'first_state_divergence':diverged,'alive_counters_match':counts,
  'event_totals':events,'e1_complete':False,'reason':'Frame event counters are available; per-definition counts, unit-script equivalence and attribution are still required before acceptance.'}

def run(a):
 output=a.output.resolve();output.mkdir(parents=True,exist_ok=True)
 engine=a.engine.resolve();binary=engine/('spring-headless' if a.mode=='headless' else 'spring')
 if not binary.is_file():raise ValueError(f'missing engine: {binary}')
 stamp={'engine':str(binary),'engine_sha256':sha(binary),'engine_commit':revision(ENGINE),
  'engine_dirty':subprocess.check_output(['git','-C',str(ENGINE),'status','--porcelain'],text=True),
  'args':{k:str(v) if isinstance(v,Path) else v for k,v in vars(a).items()},'status':'diagnostic'}
 save(output/'provenance.json',stamp)
 start=time.monotonic();deadline=start+a.max_minutes*60
 results=[]
 games=list(GAMES) if a.game=='all' else [a.game]
 for game in games:
  pair=[]
  with tempfile.TemporaryDirectory(prefix='spring-perf-'+game+'-') as temp:
   temp=Path(temp);isolation=temp/'isolation';(isolation/'games').mkdir(parents=True)
   (isolation/'maps').symlink_to(PROJECT/'spring-linux/maps',target_is_directory=True)
   scripts={};content={}
   # Choose the exact same map for both versions, including when the port's
   # launch profile names a patched version. Any incompatibility is a failure.
   lua_script=(PROJECT/f'launch/games/{game}/lua.txt').read_text()
   map_name=re.search(r'(?i)\bMapName\s*=([^;]+)',lua_script)[1].strip()
   for backend,folder in zip(('lua','wasm'),GAMES[game]):
    source=PROJECT/'spring-linux/games'/folder
    staged=isolation/'games'/folder
    shutil.copytree(source,staged,ignore=shutil.ignore_patterns('.git','target','wasm-src','screenshots','cache'))
    content[backend]={'commit':revision(source),'content_sha256':tree_hash(staged),
     'modules':{str(p.relative_to(staged)):sha(p) for p in staged.rglob('*.wasm')}}
    text=(PROJECT/f'launch/games/{game}/{backend}.txt').read_text()
    text=set_key(set_key(text,'FixedRNGSeed',424242),'MapName',map_name)
    text=set_key(text,'FixedUnsyncedRNGSeed',424242)
    scripts[backend]=speed(text,100 if a.mode=='headless' else 1)
   save(output/f'{game}-content.json',content)
   for repeat in range(a.repeats):
    for backend in ('lua','wasm'):
     if time.monotonic()>=deadline:raise TimeoutError('Configured campaign time limit reached; completed evidence is preserved')
     directory=output/f'{game}-{repeat:02d}-{backend}';directory.mkdir(exist_ok=True)
     write=directory/'write';write.mkdir(exist_ok=True)
     script=directory/'start.txt'
     with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
     script.write_text(set_key(scripts[backend],'HostPort',port))
     config=(PROJECT/'launch/springsettings.cfg').read_text()
     extra=PROJECT/f'launch/games/{game}/graphics.cfg'
     if extra.exists():config+='\n'+extra.read_text()
     config+='\nFullscreen=0\nXResolutionWindowed=1024\nYResolutionWindowed=736\nVSync=0\nMaxFPS=0\nWorkerThreadCount=1\nSound=0\nUseFontConfigLib=0\n'
     (directory/'settings.cfg').write_text(config)
     env=os.environ.copy();env.update(SPRING_PERF_LOG=str(directory/'frames.csv'),SPRING_PERF_STOP_FRAME=str(a.frames),
      SPRING_PERF_UNPAUSED='1',SPRING_DATADIR=os.pathsep.join(map(str,[isolation,engine,ENGINE/'cont/base',ENGINE/'cont'])),SPRING_ISOLATED=str(isolation))
     if a.mode!='headless':env['SDL_VIDEODRIVER']='offscreen'
     if a.input:env['SPRING_PERF_INPUT']=str(a.input.resolve())
     before=host();samples=[before];save(directory/'host-before.json',before)
     command=[str(binary),'--isolation','--isolation-dir',str(isolation),'--write-dir',str(write),'--config',str(directory/'settings.cfg'),str(script)]
     launched=time.monotonic()
     with (directory/'engine.log').open('wb') as log:
      process=subprocess.Popen(command,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
      try:
       while process.poll() is None:
        if time.monotonic()>=min(deadline,launched+a.timeout):break
        time.sleep(.5);samples.append(host())
      finally:
       if process.poll() is None:
        process.terminate()
        try:process.wait(5)
        except subprocess.TimeoutExpired:process.kill();process.wait()
     save(directory/'host-samples.json',samples)
     log=(directory/'engine.log').read_text(errors='replace')
     frame_rows=rows(directory/'frames.csv') if (directory/'frames.csv').exists() else []
     frames=[int(r['frame']) for r in frame_rows if r['kind']=='sim']
     errors=re.findall(r'(?im)^.*(?:Error:|Warning:|Lua.*(?:error|Error)|Core Wasm callin.*failed).*$' ,log)
     if a.mode!='headless':
      renderer=re.search(r'GL renderer : ([^\n]+)',log)
      if not renderer:errors.append('Offscreen GPU rendering did not initialize')
      elif re.search(r'llvmpipe|softpipe|swrast|SwiftShader|Software Rasterizer',renderer[1],re.I):errors.append('Offscreen GPU rendering selected a software renderer: '+renderer[1])
     ok=process.returncode==0 and frames==list(range(a.frames+1)) and not errors
     if not ok and frames!=list(range(a.frames+1)):errors.append('Required frame window was not completed; timeout or early exit')
     contended=any(pressure(s)>5 for s in samples)
     metrics={}
     for kind in ('sim','draw'):
      for field in ('elapsed_us','lua_us','wasm_us','import_us'):
       metrics[kind+'.'+field]=distribution([float(r[field]) for r in frame_rows if r['kind']==kind and int(r['frame'])>=a.warmup])
     result={'game':game,'backend':backend,'repeat':repeat,'ok':ok,'errors':errors,'exit':process.returncode,
      'launch_to_exit_seconds':time.monotonic()-launched,'contended':contended,'metrics':metrics,
      'script_sha256':sha(script),'settings_sha256':sha(directory/'settings.cfg'),'status':'diagnostic'}
     save(directory/'result.json',result);results.append(result);pair.append((backend,frame_rows))
     save(output/'baseline-status.json',{'status':'diagnostic','complete':False,'runs':len(results),'results':results})
     print(f'{game} {repeat} {backend}: {"complete" if ok else "FAILED"}, {len(frames)} sim rows, contended={contended}',flush=True)
    equality=compare(pair[-2][1],pair[-1][1]);save(output/f'{game}-{repeat:02d}-equivalence.json',equality)
   # Ratios are descriptive even when equal-work acceptance fails. Never
   # silently average work-mismatched runs into a language-performance claim.
   ratios=[]
   for i in range(a.repeats):
    lua,wasm=[r for r in results if r['game']==game and r['repeat']==i]
    x=lua['metrics']['sim.elapsed_us']['p50'];y=wasm['metrics']['sim.elapsed_us']['p50']
    if x and y:ratios.append(y/x)
   save(output/f'{game}-summary.json',{'status':'diagnostic','whole_sim_p50_ratio':statistics.mean(ratios) if ratios else None,
    'paired_bootstrap_95ci':confidence(ratios),'acceptance':'pending full E1 counters, contention review, overhead and hot-pair attribution'})
 save(output/'baseline-status.json',{'status':'diagnostic','complete':all(r['ok'] for r in results),'runs':len(results)})
 return 0 if all(r['ok'] for r in results) else 1

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('game',choices=['all',*GAMES]);p.add_argument('scenario',choices=['autonomous','scripted'],default='autonomous',nargs='?')
 p.add_argument('--engine',type=Path,default=ENGINE/'build-amd64-linux/install');p.add_argument('--output',type=Path,required=True)
 p.add_argument('--mode',choices=['headless','realtime'],default='realtime');p.add_argument('--frames',type=int,default=900);p.add_argument('--warmup',type=int,default=300)
 p.add_argument('--repeats',type=int,default=5);p.add_argument('--timeout',type=float,default=120);p.add_argument('--max-minutes',type=float,default=20);p.add_argument('--input',type=Path)
 a=p.parse_args()
 if a.frames<=a.warmup or a.warmup<0 or a.repeats<1 or a.timeout<=0 or a.max_minutes<=0:p.error('invalid frame window, repeat count or timeout')
 if a.scenario=='scripted' and not a.input:p.error('scripted requires --input')
 try:return run(a)
 except (ValueError,TimeoutError,KeyboardInterrupt) as e:print(str(e),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
