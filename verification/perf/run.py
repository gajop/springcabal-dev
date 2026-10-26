#!/usr/bin/env python3
# This file is part of the Spring engine (GPL v2 or later), see LICENSE.html
"""Paired Lua/Wasm game measurements with provenance and equivalence checks.

Every result starts diagnostic. A completed process or plausible timing alone
never accepts a language-performance claim. Source checkouts are read-only.
"""
from __future__ import annotations
import argparse
import csv
import fcntl
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import threading
import storage
import time

PROJECT=Path(__file__).resolve().parents[2]
ENGINE=Path(os.environ.get('SPRING_BAR_DIR',PROJECT.parent/'spring-bar'))
COMPARISON_GAMES=('hunted','flove','ttld','area17')
GAMES={
 'mycube':('MyCube.sdd','MyCube-wasm.sdd'),
 'ttld':('ToTheLastDrop.sdd','ToTheLastDrop-wasm.sdd'),
 'hunted':('Hunted.sdd','Hunted-wasm.sdd'),
 'area17':('Area-17.sdd','Area17-wasm.sdd'),
 'gravitas':('Scenario-Editor-Gravitas.sdd','Gravitas-wasm.sdd'),
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
 p=subprocess.run(['git','-C',str(path),'rev-parse','--show-toplevel','HEAD'],capture_output=True,text=True)
 lines=p.stdout.splitlines()
 # Frozen content copies can sit inside this tooling repository. Its parent
 # commit does not identify the copied game; retain the content hashes instead.
 return lines[1] if p.returncode==0 and len(lines)==2 and Path(lines[0]).resolve()==Path(path).resolve() else None
def tree_hash(path):
 h=hashlib.sha256()
 for f in sorted(path.rglob('*')):
  if not f.is_file() or any(x in ('.git','target','wasm-src') for x in f.relative_to(path).parts):continue
  h.update(str(f.relative_to(path)).encode());h.update(bytes.fromhex(sha(f)))
 return h.hexdigest()
def cpu_pressure_path(scope,cgroup_file=Path('/proc/self/cgroup'),root=Path('/sys/fs/cgroup')):
 if scope=='global':return Path('/proc/pressure/cpu')
 unified=[line[3:] for line in cgroup_file.read_text().splitlines() if line.startswith('0::')]
 if len(unified)!=1:raise ValueError('cgroup CPU pressure requires a unified cgroup hierarchy')
 path=root/unified[0].lstrip('/')/'cpu.pressure'
 if not path.is_file():raise ValueError(f'cgroup CPU pressure unavailable: {path}')
 return path
def host(pressure_path=Path('/proc/pressure/cpu')):
 def read(p):
  try:return Path(p).read_text().strip()
  except OSError:return None
 return {'time':datetime.now(timezone.utc).isoformat(),'load':os.getloadavg(),
  'cpu_pressure':read('/proc/pressure/cpu'),
  'contention_cpu_pressure':read(pressure_path),'cpu_pressure_source':str(pressure_path),
  'memory_pressure':read('/proc/pressure/memory'),
  'memory':read('/proc/meminfo'),'cpu_governors':{str(p):read(p) for p in Path('/sys/devices/system/cpu').glob('cpu[0-9]*/cpufreq/scaling_governor')},
  'turbo_disabled':read('/sys/devices/system/cpu/intel_pstate/no_turbo'),
  'cpu_frequencies_khz':{str(p):read(p) for p in Path('/sys/devices/system/cpu').glob('cpu[0-9]*/cpufreq/scaling_cur_freq')},
  'temperatures':{str(p):read(p) for p in Path('/sys/class/thermal').glob('thermal_zone*/temp')}}
def pressure(sample):
 text=sample.get('contention_cpu_pressure',sample.get('cpu_pressure')) or ''
 m=re.search(r'some avg10=([0-9.]+)',text)
 return float(m[1]) if m else math.inf
def pool_width(log):
 wanted=None
 for line in log.splitlines():
  if '[ThreadPool::SetThreadCount][1]' in line:
   match=re.search(r'wanted=(\d+).*\(init=0\)',line)
   wanted=int(match[1]) if match else None
  elif wanted is not None and '[ThreadPool::SetThreadCount][2]' in line:
   match=re.search(r'workers=(\d+)',line)
   if match:return wanted,int(match[1])+1
 return None
def process_memory(pid):
 try:
  status=Path(f'/proc/{pid}/status').read_text()
 except OSError:return None
 result={key:int(value) for key,value in re.findall(r'^(VmRSS|VmHWM):\s+(\d+) kB',status,re.M)}
 try:
  result['cpu']=int(Path(f'/proc/{pid}/stat').read_text().rsplit(')',1)[1].split()[36])
  result['thread_affinities']={p.name:sorted(os.sched_getaffinity(int(p.name))) for p in Path(f'/proc/{pid}/task').iterdir()}
 except (OSError,ProcessLookupError):pass
 return result

def engine_pid(parent,binary):
 pending=[parent]
 while pending:
  pid=pending.pop()
  try:
   if Path(f'/proc/{pid}/exe').resolve()==binary:return pid
   pending.extend(int(x) for x in Path(f'/proc/{pid}/task/{pid}/children').read_text().split())
  except (OSError,ProcessLookupError):continue
 return None

def cpu_list(value,available):
 if not re.fullmatch(r'\d+(?:-\d+)?(?:,\d+(?:-\d+)?)*',value):
  raise ValueError('CPU affinity must be a list such as 0,2,4-6')
 selected=set()
 for part in value.split(','):
  ends=[int(x) for x in part.split('-')];first,last=ends[0],ends[-1]
  if first>last:raise ValueError('CPU affinity ranges must be ascending')
  if last>max(available):raise ValueError('CPU affinity includes unavailable CPUs')
  selected.update(range(first,last+1))
 if not selected.issubset(available):raise ValueError('CPU affinity includes unavailable CPUs')
 return sorted(selected)

def foreign_gpu_processes(text, own_group=None, process_group=os.getpgid):
 """NVIDIA compute clients, plus Spring graphics clients, outside this run."""
 found=[]
 for line in text.splitlines():
  if not line.strip() or line.startswith('#'):continue
  fields=line.split()
  if len(fields)<4 or not fields[1].isdigit():continue
  pid,kind=int(fields[1]),fields[2]
  # Ordinary desktop compositor/browser graphics remain present. A competing
  # compute client or another Spring renderer is a material workload.
  # Xorg/compositor activity can be charged for this run's presentation too.
  # Keep their telemetry, but do not mistake it for an independent benchmark.
  desktop=fields[-1] in ('Xorg','Xwayland','gnome-shell')
  busy_graphics=not desktop and fields[3].isdigit() and int(fields[3])>5
  if 'C' not in kind and not busy_graphics and not re.match(r'(?i)(?:spring|recoil|eglretrace|glretrace)',fields[-1]):continue
  if own_group is not None:
   try:
    if process_group(pid)==own_group:continue
   except ProcessLookupError:continue
  found.append({'pid':pid,'type':kind,'name':fields[-1]})
 return found

def gpu_processes(own_group=None):
 result=subprocess.run(['nvidia-smi','pmon','-c','1','-s','um'],capture_output=True,text=True,timeout=10)
 if result.returncode:raise ValueError('GPU process guard unavailable: '+result.stderr.strip())
 if not result.stdout.startswith('# gpu'):raise ValueError('GPU process guard returned an unrecognized format')
 fields='pstate,clocks.gr,clocks.mem,temperature.gpu,power.draw,utilization.gpu'
 stats=subprocess.run(['nvidia-smi','--query-gpu='+fields,'--format=csv,noheader,nounits'],capture_output=True,text=True,timeout=10)
 if stats.returncode:raise ValueError('GPU clock telemetry unavailable: '+stats.stderr.strip())
 return {'time':datetime.now(timezone.utc).isoformat(),'foreign':foreign_gpu_processes(result.stdout,own_group),
         'pmon':result.stdout,'gpu_metric_fields':fields,'gpu_metrics_csv':stats.stdout}

class GpuMonitor:
 """Keep nvidia-smi's blocking one-second sample off the perf FIFO loop."""
 def __init__(self,own_group,sampler=gpu_processes):
  self.samples=[];self.error=None;self._stop=threading.Event()
  def collect():
   while not self._stop.is_set():
    try:self.samples.append(sampler(own_group))
    except Exception as error:self.error=error;return
    self._stop.wait(.1)
  self._thread=threading.Thread(target=collect,name='perf-gpu-monitor',daemon=True)
  self._thread.start()
 def stop(self):
  self._stop.set();self._thread.join(12)
  if self._thread.is_alive():self.error=TimeoutError('GPU monitor did not finish')

def set_key(text,key,value):
 pattern=rf'(?im)^(\s*){re.escape(key)}\s*=[^;]*;'
 if re.search(pattern,text):return re.sub(pattern,lambda m:f'{m[1]}{key}={value};',text)
 return re.sub(r'(?i)(\[GAME\]\s*\{)',lambda m:m[0]+f'\n    {key}={value};',text,count=1)
def speed(text,value):
 entry=f'\n MinSpeed={value}; MaxSpeed={value};\n'
 text=re.sub(r'(?i)\b(?:MinSpeed|MaxSpeed)\s*=[^;]*;','',text)
 if re.search(r'(?i)\[modoptions\]\s*\{',text):return re.sub(r'(?i)(\[modoptions\]\s*\{)',lambda m:m[0]+entry,text,count=1)
 return text[:text.rfind('}')]+'\n[modoptions] {'+entry+'}\n}\n'
def modoption(text,key,value):
 if re.search(r'(?i)\[modoptions\]\s*\{',text):
  return re.sub(r'(?i)(\[modoptions\]\s*\{)',lambda m:m[0]+f'\n {key}={value};',text,count=1)
 return text[:text.rfind('}')]+f'\n[modoptions] {{{key}={value};}}\n}}\n'
def stage_workload(staged,a):
 if a.unit_multiplier==1 and not a.frame_step and not a.record_world:return
 gadgets=staged/'LuaRules/Gadgets';gadgets.mkdir(parents=True,exist_ok=True)
 shutil.copyfile(PROJECT/'verification/perf/workload.lua',gadgets/'zz_perf_workload.lua')
 if a.record_world:
  shutil.copyfile(PROJECT/'verification/perf/world.lua',gadgets/'perf_world.lua')
 draw=staged/'LuaRules/draw.lua'
 # Keep an existing gadget loader. Some ports intentionally have no Lua
 # unsynced rules; only those need a tiny entry point for frame stepping.
 if not draw.exists() or not re.search(r'luagadgets/gadgets.lua',draw.read_text()):
  draw.write_text('gadget = {}\ngadgetHandler = { IsSyncedCode = function() return false end }\n'
   'VFS.Include("LuaRules/Gadgets/zz_perf_workload.lua", nil, VFS.ZIP_FIRST)\n'
   'if gadget.Initialize then gadget:Initialize() end\n'
   'function Shutdown() if gadget.Shutdown then gadget:Shutdown() end end\n')
def stage_effects(staged,backend,probe):
 # Reuse the fire parity fixture's original Lua emitters/particle classes and
 # the production Rust UI renderer. No scenario, units or gameplay rules run.
 fixture=PROJECT/'verification/fixtures/gravitas'
 for name in ('main','draw'):
  shutil.copyfile(fixture/'fire_probe_rules.lua',staged/f'LuaRules/{name}.lua')
 manifest=staged/'LuaRules/wasm/manifest.txt'
 if manifest.exists():manifest.write_text('')
 if backend=='lua':
  shutil.copyfile(fixture/'fire_probe_ui.lua',staged/'LuaUI/main.lua')
  # The normal Lua launch uses Scenario Editor Gravitas, which already sets
  # this. The effects fixture launches its base archive directly instead.
  info=staged/'modinfo.lua'
  info.write_text(info.read_text().replace('modtype = "1",','modtype = "1",\n onlyLocal = true,'))
 else:shutil.copyfile(probe,staged/'LuaUI/wasm/gravitas-ui.wasm')
def build_effects_probe(games_dir):
 source=games_dir/'Gravitas-wasm.sdd/wasm-src'
 target=PROJECT/'verification/cache/target/gravitas-fire-probe'
 subprocess.run(['cargo','build','-p','gravitas-ui-wasm','--features','fire-probe',
  '--release','--locked','--target','wasm32-unknown-unknown','--target-dir',str(target)],cwd=source,check=True)
 return target/'wasm32-unknown-unknown/release/gravitas_ui_wasm.wasm'
def stage_map(isolation,game):
 maps=PROJECT/'spring-linux/maps'
 if game=='area17':
  source=Path(subprocess.check_output([str(PROJECT/'scripts/area17-map.sh'),'--dir'],text=True).strip())
 else:
  source=maps/{'hunted':'HuntedMap.sdd','flove':'LD34-map.sdd','ttld':'LD43-map.sdd',
   'gravitas':'Gravitas-map.sdd','mycube':'MyCube_v1.sd7','partsneeded':'LD35-map.sdd'}[game]
 (isolation/'maps').mkdir()
 (isolation/'maps'/source.name).symlink_to(source,target_is_directory=source.is_dir())
 return {'path':str(source),'sha256':tree_hash(source) if source.is_dir() else sha(source)}
def rows(path):
 with path.open() as f:return list(csv.DictReader(f))
def percentile(values,p):
 values=sorted(values)
 if not values:return None
 x=(len(values)-1)*p;i=int(x);return values[i]+(values[min(i+1,len(values)-1)]-values[i])*(x-i)
def distribution(values):
 return {name:percentile(values,p) for name,p in [('p50',.5),('p95',.95),('p99',.99),('p999',.999),('max',1.)]}
def draw_window(frame_rows,warmup,stop):
 return [int(r['frame']) for r in frame_rows if r['kind']=='draw' and warmup<=int(r['frame'])<stop]
def confidence(ratios):
 if len(ratios)<5:return None
 rng=random.Random(424242)
 means=[statistics.mean(rng.choices(ratios,k=len(ratios))) for _ in range(2000)]
 return [percentile(means,.025),percentile(means,.975)]
def timed_input(text,warmup,stop):
 # Use the released engine's existing input/echo path. The timestamps bracket
 # complete stepped frames, including main-loop work and buffer swaps that
 # lie outside the simulation/draw CPU scopes. No engine changes are needed.
 actions=[(0,'0: local console 0'),
          (warmup,f'{warmup}: local echo [PerfWindow] begin frame={warmup}'),
          (stop,f'{stop}: local echo [PerfWindow] end frame={stop}')]
 previous=-1
 for line in text.splitlines():
  if line and not line.startswith('#'):
   frame=int(line.split(':',1)[0])
   if frame<0 or frame<previous:raise ValueError('Unordered or invalid input frame')
   previous=frame;actions.append((frame,line))
 return '\n'.join(line for _,line in sorted(actions,key=lambda item:item[0]))+'\n'
def wall_window(log,warmup,stop):
 matches=re.findall(r'\[t=(\d+):(\d+):(\d+\.\d+)\].*\[PerfWindow\] (begin|end) frame=(\d+)',log)
 if len(matches)!=2:raise ValueError('Expected exactly two wall-time window markers')
 times=[]
 for match,expected in zip(matches,(('begin',warmup),('end',stop))):
  hours,minutes,seconds,kind,frame=match
  if (kind,int(frame))!=expected:raise ValueError('Incorrect wall-time window marker')
  times.append(int(hours)*3600+int(minutes)*60+float(seconds))
 elapsed=times[1]-times[0]
 if elapsed<=0:raise ValueError('Nonpositive wall-time window')
 return elapsed
def compare(a,b,labels=('lua','wasm')):
 aa={int(r['frame']):r for r in a if r['kind']=='sim'};bb={int(r['frame']):r for r in b if r['kind']=='sim'}
 frames=sorted(aa.keys() & bb.keys())
 diverged=next((f for f in frames if aa[f]['state_digest']!=bb[f]['state_digest']),None)
 counts=bool(frames) and all(aa[f]['units']==bb[f]['units'] and aa[f]['projectiles']==bb[f]['projectiles'] for f in frames)
 events={}
 for key in ('created','destroyed','weapon_fires','damage_events','commands','cegs','damage_total'):
  if frames and key in aa[frames[0]] and key in bb[frames[0]]:
   events[key]={labels[0]:sum(float(aa[f][key]) for f in frames),labels[1]:sum(float(bb[f][key]) for f in frames)}
 return {'frames':len(frames),'frame_sets_equal':bool(frames) and aa.keys()==bb.keys(),
  'first_state_divergence':diverged,'alive_counters_match':counts,
  'event_totals':events,'e1_complete':False,'reason':'Frame event counters are available; per-definition counts, unit-script equivalence and attribution are still required before acceptance.'}

class VerificationLease:
 """Keep active work serialized, but let other work proceed during idle waits."""
 def __init__(self,path=None):
  path=Path(path or os.environ.get('VF_LOCK_HELD') or os.environ.get('VF_LOCK_FILE') or '/tmp/springcabal-verify.lock')
  self.fd=None;self.inherited=False;self.held=False
  if path.exists():
   expected=path.stat()
   for entry in Path('/proc/self/fd').iterdir():
    try:
     fd=int(entry.name);actual=os.fstat(fd)
    except (OSError,ValueError):continue
    if (actual.st_dev,actual.st_ino)==(expected.st_dev,expected.st_ino):
     self.fd=os.dup(fd);self.inherited=True;break
  if self.fd is None:self.fd=os.open(path,os.O_WRONLY|os.O_CREAT,0o600)
  fcntl.flock(self.fd,fcntl.LOCK_EX);self.held=True
 def release(self):
  if self.held:fcntl.flock(self.fd,fcntl.LOCK_UN);self.held=False
 def try_acquire(self):
  if self.held:return True
  try:fcntl.flock(self.fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
  except BlockingIOError:return False
  self.held=True;return True
 def __enter__(self):return self
 def __exit__(self,*_):
  # Nested callers may continue under their original flock after this exits.
  if self.inherited and not self.held:fcntl.flock(self.fd,fcntl.LOCK_EX)
  os.close(self.fd)

def wait_for_resources(a,pressure_path,deadline,game,lease,host_sample=host,gpu_sample=gpu_processes,now=time.monotonic,sleep=time.sleep):
 before=None;gpu_before=None;quiet_since=None;notice=0;preflight=[]
 if a.wait_for_idle or a.wait_for_gpu_idle:lease.release()
 while True:
  if now()>=deadline:raise TimeoutError('CPU/GPU stayed busy; completed evidence is preserved')
  if not lease.try_acquire():
   quiet_since=None
   if now()-notice>=30:
    print(f'{game}: waiting for verification lock',flush=True);notice=now()
   sleep(1);continue
  before=host_sample(pressure_path)
  gpu_before=gpu_sample() if a.wait_for_gpu_idle else None
  if gpu_before:
   preflight.append(gpu_before)
   if len(preflight)>16:preflight.pop(0)
  cpu_busy=a.wait_for_idle and pressure(before)>5
  gpu_busy=bool(gpu_before and gpu_before['foreign'])
  if cpu_busy or gpu_busy:
   quiet_since=None;lease.release()
  else:
   quiet_since=now() if quiet_since is None else quiet_since
   if not a.wait_for_gpu_idle or now()-quiet_since>=10:break
  if now()-notice>=30:
   print(f'{game}: waiting for CPU/GPU idle (CPU avg10={pressure(before):.2f}, GPU clients={gpu_before["foreign"] if gpu_before else []})',flush=True);notice=now()
  sleep(1)
 return before,gpu_before,preflight

def callback_timers_off(frame_rows):
 # A released engine may ignore the new environment variable. Require its
 # explicit CSV acknowledgement and zero timing counters before using it.
 return bool(frame_rows) and all(r.get('callback_timers') == '0' and
  all(float(r[k]) == 0 for k in ('lua_us', 'wasm_us', 'import_us')) for r in frame_rows)

def run(a):
 with VerificationLease() as lease:return run_locked(a,lease)

def run_locked(a,lease):
 pressure_path=cpu_pressure_path(a.cpu_pressure_scope)
 output=a.output.resolve()
 if output.exists() and any(output.iterdir()):raise ValueError(f'Output must be empty (existing evidence preserved): {output}')
 output.mkdir(parents=True,exist_ok=True)
 engine=a.engine.resolve();binary=engine/('spring-headless' if a.mode=='headless' else 'spring')
 if not binary.is_file():raise ValueError(f'missing engine: {binary}')
 backends=('lua','wasm') if a.backend=='both' else (a.backend,)
 jobs_comparison=a.rust_jobs=='compare'
 variants=[('wasm','off'),('wasm','on')] if jobs_comparison else [(backend,a.rust_jobs) for backend in backends]
 frozen_input=None
 if a.input:
  frozen_input=output/'input.txt'
  shutil.copyfile(a.input,frozen_input)
 effective_input=frozen_input
 if a.frame_step or a.scenario=='effects':
  effective_input=output/'timed-input.txt'
  effective_input.write_text(timed_input(frozen_input.read_text() if frozen_input else '',a.warmup,a.frames))
 stamp={'engine':str(binary),'engine_sha256':sha(binary),'engine_commit':revision(ENGINE),
  'cpu_pressure_source':str(pressure_path),
  'engine_source':str(ENGINE.resolve()),
  'framework_commit':revision(PROJECT),'runner_sha256':sha(Path(__file__)),
  'shared_commit':revision(a.games_dir.parents[1]/'springcabal-rs'),
  'fixtures':{str(p.relative_to(PROJECT)):sha(p) for p in [PROJECT/'verification/perf/workload.lua',
   PROJECT/'verification/perf/world.lua',PROJECT/'verification/perf/sampling.py',
   PROJECT/'verification/fixtures/gravitas/fire_probe_rules.lua',PROJECT/'verification/fixtures/gravitas/fire_probe_ui.lua']},
  'engine_dirty':subprocess.check_output(['git','-C',str(ENGINE),'status','--porcelain'],text=True),
  'input_sha256':sha(frozen_input) if frozen_input else None,
  'effective_input_sha256':sha(effective_input) if effective_input else None,
  'args':{k:str(v) if isinstance(v,Path) else v for k,v in vars(a).items()},'status':'diagnostic'}
 save(output/'provenance.json',stamp)
 probe=build_effects_probe(a.games_dir) if a.scenario=='effects' and 'wasm' in backends else None
 start=time.monotonic();deadline=start+a.max_minutes*60
 results=[]
 games=list(GAMES) if a.game=='all' else list(COMPARISON_GAMES) if a.game=='comparison' else [a.game]
 for game in games:
  pair=[]
  with tempfile.TemporaryDirectory(prefix='spring-perf-'+game+'-') as temp:
   temp=Path(temp);isolation=temp/'isolation';(isolation/'games').mkdir(parents=True)
   save(output/f'{game}-map.json',stage_map(isolation,game))
   if game=='gravitas' and a.scenario!='effects':
    for dependency in ('Gravitas.sdd','Scenario-Editor-Core.sdd'):
     (isolation/'games'/dependency).symlink_to(a.games_dir/dependency,target_is_directory=True)
    (isolation/'projects').symlink_to(PROJECT/'spring-linux/projects',target_is_directory=True)
   scripts={};content={}
   # Choose the exact same map for both versions, including when the port's
   # launch profile names a patched version. Any incompatibility is a failure.
   lua_script=(PROJECT/f'launch/games/{game}/lua.txt').read_text()
   map_name=re.search(r'(?i)\bMapName\s*=([^;]+)',lua_script)[1].strip()
   folders=('Gravitas.sdd','Gravitas-wasm.sdd') if a.scenario=='effects' else GAMES[game]
   for backend,folder in zip(('lua','wasm'),folders):
    if backend not in backends:continue
    source=a.games_dir/folder
    staged=isolation/'games'/folder
    shutil.copytree(source,staged,ignore=shutil.ignore_patterns('.git','target','wasm-src','screenshots','cache'))
    if a.scenario=='effects':stage_effects(staged,backend,probe)
    else:stage_workload(staged,a)
    content[backend]={'commit':revision(source),'content_sha256':tree_hash(staged),
     'modules':{str(p.relative_to(staged)):sha(p) for p in staged.rglob('*.wasm')}}
    content[backend]['jobs_api']=any(b'run-batch-to' in p.read_bytes() for p in staged.rglob('*.wasm'))
    if backend=='wasm' and a.rust_jobs!='off' and not content[backend]['jobs_api']:
     raise ValueError(f'{game}: requested jobs but staged modules do not import the jobs API')
    text=(PROJECT/f'launch/games/{game}/{backend}.txt').read_text()
    if a.scenario=='effects' and backend=='lua':text=set_key(text,'GameType','Gravitas $VERSION')
    text=set_key(set_key(text,'FixedRNGSeed',424242),'MapName',map_name)
    text=set_key(text,'FixedUnsyncedRNGSeed',424242)
    if game=='hunted' and a.scenario=='autonomous':text=modoption(text,'benchmark_no_input',1)
    if game=='ttld':text=modoption(text,'skip_intro',1)
    if game=='flove':text=modoption(text,'skip_tutorial',1)
    for key,value in [('perf_unit_multiplier',a.unit_multiplier),('perf_scale_frame',a.scale_frame),('perf_frame_step',int(a.frame_step)),('perf_sample_frame',a.warmup),('perf_record_every',a.record_every if a.record_world else 0),('perf_record_details',int(a.record_details))]:
     text=modoption(text,key,value)
    if a.scenario=='effects':
     for key,value in [('gallery','ceg'),('fire_perf',1),('fire_perf_emitters',a.effects_multiplier),('fire_renderer',a.fire_renderer),('fire_diagnostic_counts',int(a.diagnostic))]:text=modoption(text,key,value)
    scripts[backend]=speed(text,a.speed)
   save(output/f'{game}-content.json',content)
   clean_pairs=0
   for repeat in range(max(a.repeats,a.clean_pairs)*6 if a.clean_pairs else a.repeats):
    for backend,job_mode in (variants if repeat%2==0 else list(reversed(variants))):
     if time.monotonic()>=deadline:raise TimeoutError('Configured campaign time limit reached; completed evidence is preserved')
     suffix='-'+job_mode if jobs_comparison else ''
     directory=output/f'{game}-{repeat:02d}-{backend}{suffix}';directory.mkdir(exist_ok=True)
     write=directory/'write';write.mkdir(exist_ok=True)
     script=directory/'start.txt'
     with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
     text=modoption(scripts[backend],'rust_jobs',job_mode) if backend=='wasm' else scripts[backend]
     script.write_text(set_key(text,'HostPort',port))
     config=(PROJECT/'launch/springsettings.cfg').read_text()
     extra=PROJECT/f'launch/games/{game}/graphics.cfg'
     if extra.exists():config+='\n'+extra.read_text()
     config+=f'\nFullscreen=0\nXResolutionWindowed=1024\nYResolutionWindowed=736\nVSync=0\nMaxFPS=0\nWorkerThreadCount={a.worker_threads}\nSound=0\nUseFontConfigLib=0\n'
     (directory/'settings.cfg').write_text(config)
     env=os.environ.copy();env.update(SPRING_PERF_LOG=str(directory/'frames.csv'),SPRING_PERF_TIMERS='0' if a.callback_timers=='off' else '1',SPRING_PERF_STOP_FRAME=str(a.frames),
      SPRING_PERF_UNPAUSED='1',SPRING_DATADIR=os.pathsep.join(map(str,[isolation,engine,ENGINE/'cont/base',ENGINE/'cont'])),SPRING_ISOLATED=str(isolation))
     if a.mode!='headless':env['SDL_VIDEODRIVER']='offscreen'
     # Offscreen rendering needs no desktop. Content failures must not leave
     # a modal error dialog on the user's display or hold the run open.
     if a.mode!='headless':env.update(DISPLAY='',WAYLAND_DISPLAY='')
     if effective_input:env['SPRING_PERF_INPUT']=str(effective_input)
     storage.require_space(output,a.min_free_gib)
     before,gpu_before,preflight=wait_for_resources(a,pressure_path,deadline,game,lease)
     storage.require_space(output,a.min_free_gib)
     if a.wait_for_gpu_idle:save(directory/'gpu-preflight.json',preflight)
     if sha(binary)!=stamp['engine_sha256']:
      raise ValueError('Engine binary changed while waiting; use a frozen engine install for this campaign')
     samples=[before];memory=[];gpu_samples=[gpu_before] if gpu_before else [];save(directory/'host-before.json',before)
     command=[str(binary),'--isolation','--isolation-dir',str(isolation),'--write-dir',str(write),'--config',str(directory/'settings.cfg'),str(script)]
     capture=None
     if a.profile:
      from sampling import Capture
      capture=Capture(directory,a.warmup,a.frames)
      command=capture.command(command)
      env.update(SPRING_WASM_JITDUMP='1',JITDUMPDIR=str(directory))
     if a.trace_gl:
      command=[str(a.apitrace),'trace','--api=egl','--output='+str(directory/'opengl.trace'),*command]
     if a.cpu_affinity:
      command=['taskset','--cpu-list',','.join(map(str,a.cpu_affinity)),*command]
     disk_error=None
     launched=time.monotonic()
     with (directory/'engine.log').open('wb') as log:
      process=subprocess.Popen(command,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
      gpu_monitor=GpuMonitor(process.pid) if a.wait_for_gpu_idle else None
      try:
       while process.poll() is None:
        if time.monotonic()>=min(deadline,launched+a.timeout):break
        time.sleep(.02 if capture else .5)
        if capture:capture.poll(directory/'engine.log')
        if not samples or time.monotonic()-samples[-1].get('sample_monotonic',0)>.5:
         if shutil.disk_usage(output).free < 20*1024**3:
          disk_error='Free disk space fell below the 20 GiB emergency floor';break
         sample=host(pressure_path);sample['sample_monotonic']=time.monotonic();samples.append(sample)
         pid=engine_pid(process.pid,binary)
         value=process_memory(pid) if pid else None
         if value:memory.append(value)
      finally:
       if process.poll() is None:
        os.killpg(process.pid,signal.SIGTERM)
        try:process.wait(5)
        except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.wait()
       if gpu_monitor:
        gpu_monitor.stop();gpu_samples.extend(gpu_monitor.samples)
     if capture:capture.finish(directory/'engine.log')
     save(directory/'host-samples.json',samples)
     save(directory/'process-samples.json',memory)
     if a.wait_for_gpu_idle:save(directory/'gpu-processes.json',gpu_samples)
     log=(directory/'engine.log').read_text(errors='replace')
     frame_rows=rows(directory/'frames.csv') if (directory/'frames.csv').exists() else []
     frames=[int(r['frame']) for r in frame_rows if r['kind']=='sim']
     errors=re.findall(r'(?im)^.*(?:Error:|Warning:|Fatal:|Lua.*(?:error|Error)|Core Wasm callin.*failed).*$' ,log)
     errors+=re.findall(r'(?im)^.*\[PerfWorkload\] FAIL.*$',log)
     if disk_error:errors.append(disk_error)
     if gpu_monitor and gpu_monitor.error:errors.append('GPU monitor failed: '+str(gpu_monitor.error))
     if a.cpu_affinity and any(not set(mask).issubset(a.cpu_affinity)
       for sample in memory for mask in sample.get('thread_affinities',{}).values()):
      errors.append('Engine thread affinity escaped the requested CPU set')
     if pool_width(log)!=(a.worker_threads,a.worker_threads):errors.append('Requested ThreadPool width did not initialize')
     if a.unit_multiplier>1 and '[PerfWorkload] scaled ' not in log:errors.append('Unit scaling fixture did not complete')
     if a.scenario=='effects' and f'[FirePerf] emitters={a.effects_multiplier}' not in log:errors.append('Fire effects fixture did not initialize')
     if a.scenario=='effects' and backend=='wasm' and f'[FirePerf] Rust emitters={a.effects_multiplier}' not in log:errors.append('Rust fire renderer probe did not initialize')
     if game=='hunted' and a.scenario=='autonomous' and a.mode!='headless' and '[HuntedBenchmark] mouse_input=off' not in log:
      errors.append('Hunted autonomous fixture did not disable ambient mouse input')
     if game=='ttld' and a.mode!='headless' and 'TTLD intro skipped (skip_intro=1)' not in log:
      errors.append('TTLD gameplay view did not skip the intro')
     if game=='flove' and '[FloveStartup] tutorial skipped frame=4' not in log:
      errors.append('Flove gameplay did not skip the tutorial at frame four')
     renderer=None
     if a.mode!='headless':
      renderer=re.search(r'GL renderer : ([^\n]+)',log)
      if not renderer:errors.append('Offscreen GPU rendering did not initialize')
      elif re.search(r'llvmpipe|softpipe|swrast|SwiftShader|Software Rasterizer',renderer[1],re.I):errors.append('Offscreen GPU rendering selected a software renderer: '+renderer[1])
     rendered=draw_window(frame_rows,a.warmup,a.frames)
     wall_seconds=None
     if (a.frame_step or a.scenario=='effects') and rendered!=list(range(a.warmup,a.frames)):
      errors.append('Frame stepping failed: expected exactly one draw for every measured simulation frame')
     if a.frame_step or a.scenario=='effects':
      try:wall_seconds=wall_window(log,a.warmup,a.frames)
      except ValueError as error:errors.append(str(error))
     if a.callback_timers=='off' and not callback_timers_off(frame_rows):
      errors.append('Engine did not acknowledge disabled callback timers; a timer-control build is required')
     ok=process.returncode==0 and frames==list(range(a.frames+1)) and not errors
     if not ok and frames!=list(range(a.frames+1)):errors.append('Required frame window was not completed; timeout or early exit')
     gpu_contended=any(s['foreign'] for s in gpu_samples)
     contended=any(pressure(s)>5 for s in samples) or gpu_contended
     metrics={}
     for kind in ('sim','draw'):
      for field in ('elapsed_us','lua_us','wasm_us','import_us','lua_calls','wasm_calls','imports'):
       metrics[kind+'.'+field]=distribution([float(r[field]) for r in frame_rows if r['kind']==kind and int(r['frame'])>=a.warmup])
     if a.frame_step or a.scenario=='effects':
      sim={int(r['frame']):float(r['elapsed_us']) for r in frame_rows if r['kind']=='sim' and int(r['frame'])>=a.warmup}
      draw={}
      for row in frame_rows:
       if row['kind']=='draw':draw[int(row['frame'])]=draw.get(int(row['frame']),0)+float(row['elapsed_us'])
      metrics['frame.cpu_us']=distribution([value+draw[frame] for frame,value in sim.items() if frame in draw])
     result={'game':game,'backend':backend,'repeat':repeat,'ok':ok,'errors':errors,'exit':process.returncode,
      'launch_to_exit_seconds':time.monotonic()-launched,'contended':contended,'metrics':metrics,
      'script_sha256':sha(script),'settings_sha256':sha(directory/'settings.cfg'),'status':'diagnostic'}
     result['renderer']=renderer[1] if renderer else None
     result['worker_threads']=a.worker_threads
     result['unit_multiplier']=a.unit_multiplier
     result['effects_multiplier']=a.effects_multiplier
     result['cpu_affinity']=a.cpu_affinity
     result['rust_jobs']=job_mode if backend=='wasm' else 'off'
     result['fire_renderer']=a.fire_renderer if a.scenario=='effects' and backend=='wasm' else None
     result['comparison_kind']='jobs' if jobs_comparison else 'lua-wasm'
     result['jobs_active']=bool(re.search(r'\[GameJobs\].*active ',log))
     result['instrumented']=bool(a.record_world or a.profile or a.trace_gl or a.diagnostic)
     if a.trace_gl:
      trace=directory/'opengl.trace'
      result['opengl_trace']='opengl.trace'
      if not trace.is_file() or trace.stat().st_size==0:
       errors.append('OpenGL trace was not written');result['ok']=False
     result['gpu_process_guard']=a.wait_for_gpu_idle
     result['gpu_quiet_seconds']=10 if a.wait_for_gpu_idle else None
     result['gpu_contended']=gpu_contended
     if a.record_world:
      recording=write/'perf-world.jsonl'
      if not recording.is_file():errors.append('World recording was not written');result['ok']=False
      else:
       result.update(storage.compress_world(recording,directory/'world.jsonl.gz'))
     if capture:result['sampling']=capture.metadata
     result['window_wall_seconds']=wall_seconds
     result['callback_timers']=a.callback_timers
     result['window_wall_ms_per_frame']=wall_seconds*1000/(a.frames-a.warmup) if wall_seconds is not None else None
     result['workload']=[line.split('[PerfWorkload] ',1)[1] for line in log.splitlines() if '[PerfWorkload] ' in line]
     result['custom_particles']=[dict(zip(('frame','normal','distortion'),map(int,row))) for row in
      re.findall(r'\[FireCounts\] frame=(\d+) normal=(\d+) distortion=(\d+)',log)]
     result['rendered_measurement_frames']=len(rendered)
     result['sampled_peak_rss_kib']=max((s.get('VmHWM',s.get('VmRSS',0)) for s in memory),default=None)
     result['population']={field:distribution([float(r[field]) for r in frame_rows if r['kind']=='sim' and int(r['frame'])>=a.warmup]) for field in ('units','projectiles','features','particles')}
     save(directory/'result.json',result);results.append(result);pair.append((job_mode if jobs_comparison else backend,frame_rows))
     save(output/'baseline-status.json',{'status':'diagnostic','complete':False,'runs':len(results),'results':results})
     print(f'{game} {repeat} {backend}{suffix}: {"complete" if ok else "FAILED"}, {len(frames)} sim rows, contended={contended}',flush=True)
    if len(backends)==2 or jobs_comparison:
     labels=('off','on') if jobs_comparison else ('lua','wasm')
     equality=compare(*[[r for r in dict(pair[-2:])[backend] if int(r['frame'])>=a.warmup] for backend in labels],labels=labels);save(output/f'{game}-{repeat:02d}-equivalence.json',equality)
    current=[r for r in results if r['game']==game and r['repeat']==repeat]
    clean_pairs+=int(bool(current) and all(r['ok'] and not r['contended'] for r in current))
    if a.clean_pairs and clean_pairs>=a.clean_pairs and repeat+1>=a.repeats:break
   # Ratios are descriptive even when equal-work acceptance fails. Never
   # silently average work-mismatched runs into a language-performance claim.
   ratios=[]
   for i in range(repeat+1):
    if len(backends)!=2 and not jobs_comparison:break
    key='rust_jobs' if jobs_comparison else 'backend'
    by_backend={r[key]:r for r in results if r['game']==game and r['repeat']==i}
    left,right=('off','on') if jobs_comparison else ('lua','wasm')
    lua,wasm=by_backend[left],by_backend[right]
    x=lua['metrics']['sim.elapsed_us']['p50'];y=wasm['metrics']['sim.elapsed_us']['p50']
    if lua['ok'] and wasm['ok'] and x and y:ratios.append(y/x)
   save(output/f'{game}-summary.json',{'status':'diagnostic','whole_sim_p50_ratio':statistics.mean(ratios) if ratios else None,
    'paired_bootstrap_95ci':confidence(ratios),'acceptance':'pending full E1 counters, contention review, overhead and hot-pair attribution'})
 save(output/'baseline-status.json',{'status':'diagnostic','complete':all(r['ok'] for r in results),'runs':len(results)})
 return 0 if all(r['ok'] for r in results) else 1

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('game',choices=['all','comparison',*GAMES]);p.add_argument('scenario',choices=['autonomous','scripted','effects'],default='autonomous',nargs='?')
 p.add_argument('--engine',type=Path,default=Path(os.environ.get('SPRING_ENGINE_DIR',ENGINE/'build-amd64-linux/install')));p.add_argument('--output',type=Path,required=True)
 p.add_argument('--games-dir',type=Path,default=PROJECT/'spring-linux/games',help='game checkouts to stage (e.g. frozen Git worktrees for before/after measurements)')
 p.add_argument('--clean-pairs',type=int,default=0,help='continue until this many complete uncontended pairs are collected, bounded by max-minutes and six times the requested count')
 p.add_argument('--min-free-gib',type=float,default=40,help='free disk reserve required before each engine launch')
 p.add_argument('--callback-timers',choices=['on','off'],default='on',help='callback/import timer overhead control; off requires a supporting engine, while frame timing and event counters remain active')
 p.add_argument('--backend',choices=['both','lua','wasm'],default='both',help='select one backend for alternating before/after source revisions, or both for Lua/Wasm pairs')
 p.add_argument('--mode',choices=['headless','gpu','realtime'],default='gpu',help='renderer backend; realtime is a legacy GPU alias');p.add_argument('--frames',type=int,default=900);p.add_argument('--warmup',type=int,default=300)
 p.add_argument('--speed',type=float,default=100,help='simulation speed multiplier (default: 100)')
 p.add_argument('--repeats',type=int,default=5);p.add_argument('--timeout',type=float,default=120);p.add_argument('--max-minutes',type=float,default=20);p.add_argument('--input',type=Path)
 p.add_argument('--unit-multiplier',type=int,default=1,help='clone the initial scene N-fold in staged copies only')
 p.add_argument('--scale-frame',type=int,default=60,help='frame at which the initial scene is cloned')
 p.add_argument('--frame-step',action='store_true',help='one simulation step per draw, using the gallery capture mechanism')
 p.add_argument('--effects-multiplier',type=int,default=1,help='Gravitas fire emitter pairs (0 gives the empty renderer baseline)')
 p.add_argument('--fire-renderer',choices=['gpu','cpu'],default='gpu',help='Gravitas Rust effect curves: GPU default or CPU reference for jobs comparison')
 p.add_argument('--worker-threads',type=int,default=1,help='total engine ThreadPool width, including the main thread')
 p.add_argument('--cpu-affinity',help='Linux CPU list for the engine and its threads; useful to hold core type constant on hybrid CPUs')
 p.add_argument('--rust-jobs',choices=['off','on','check','compare'],default='off',help='Rust pure jobs; check validates output, compare alternates off/on pairs')
 p.add_argument('--wait-for-idle',action='store_true',help='wait before each run while CPU pressure exceeds the existing contention threshold')
 p.add_argument('--cpu-pressure-scope',choices=['global','cgroup'],default='global',help='CPU pressure used by the contention guard; both global and selected pressure are recorded')
 p.add_argument('--record-world',action='store_true',help='separate diagnostic run: save observed unit/projectile positions for dots playback (never a timing baseline)')
 p.add_argument('--record-every',type=int,default=6,help='world recording interval in simulation frames')
 p.add_argument('--record-details',action='store_true',help='include exact height, heading, velocity and command queues in diagnostic world recordings')
 p.add_argument('--profile',action='store_true',help='separate diagnostic run: sample CPU stacks with perf only after the warmup marker')
 p.add_argument('--trace-gl',action='store_true',help='separate diagnostic run: capture EGL/OpenGL calls with installed apitrace (never a timing baseline)')
 p.add_argument('--apitrace',default='apitrace',help='apitrace executable for --trace-gl')
 p.add_argument('--diagnostic',action='store_true',help='exclude custom probes (such as screenshot capture) from timing aggregates')
 p.add_argument('--wait-for-gpu-idle',action='store_true',help='NVIDIA: wait for competing compute/Spring graphics clients; exclude pairs if any appear during a run')
 a=p.parse_args()
 if a.cpu_affinity:
  try:a.cpu_affinity=cpu_list(a.cpu_affinity,os.sched_getaffinity(0))
  except ValueError as error:p.error(str(error))
 a.games_dir=a.games_dir.resolve()
 if a.min_free_gib<20:p.error('disk reserve must be at least 20 GiB')
 if a.speed<=0 or a.frames<=a.warmup or a.warmup<0 or a.repeats<1 or a.clean_pairs<0 or a.timeout<=0 or a.max_minutes<=0:p.error('invalid frame window, repeat count or timeout')
 if a.scenario=='scripted' and not a.input:p.error('scripted requires --input')
 if a.unit_multiplier<1 or a.scale_frame<1 or (a.unit_multiplier>1 and a.warmup<=a.scale_frame):p.error('scaling must finish before warmup ends')
 if a.scenario=='effects' and (a.game!='gravitas' or a.unit_multiplier!=1 or a.effects_multiplier<0):p.error('effects supports only Gravitas, without unit scaling')
 if a.mode=='headless' and (a.frame_step or a.scenario=='effects'):p.error('frame stepping and effects require GPU rendering')
 if not 1<=a.worker_threads<=64:p.error('worker-threads must be between 1 and 64')
 if a.rust_jobs=='compare' and a.backend!='wasm':p.error('rust-jobs compare requires --backend wasm')
 if a.record_every<1:p.error('record-every must be positive')
 if a.record_details and not a.record_world:p.error('record-details requires record-world')
 if a.record_world and (a.scenario=='effects' or (not a.frame_step and a.mode!='headless')):
  p.error('world recording requires frame-stepped GPU rendering or headless gameplay diagnostics')
 if a.profile and not (a.frame_step or a.scenario=='effects'):
  p.error('CPU sampling requires frame stepping')
 if a.trace_gl and (a.mode=='headless' or a.profile):
  p.error('OpenGL tracing requires GPU rendering without CPU sampling')
 try:return run(a)
 except (ValueError,TimeoutError,KeyboardInterrupt) as e:print(str(e),file=sys.stderr);return 1
if __name__=='__main__':raise SystemExit(main())
