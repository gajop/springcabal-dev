/* Portable benchmark explorer. No game simulation and no network services. */
'use strict';
const DATA=window.SC_DATA, $=id=>document.getElementById(id), NS='http://www.w3.org/2000/svg';
const state={scene:DATA.scenes[0],comparison:'language',pair:0,worlds:[],frame:300,playing:false,fit:true,profile:null,flame:null,history:[]};
const assets=new Map(), requests=new Map();
window.SC_ASSET=async(key,encoded)=>{
  try{
    const bytes=Uint8Array.from(atob(encoded),c=>c.charCodeAt(0));
    const stream=new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
    const value=JSON.parse(await new Response(stream).text());
    if(value.encoding==='delta-v1'||value.encoding==='delta-v2-centi'){
      const units=new Map(),centi=value.encoding==='delta-v2-centi';value.samples=value.samples.map(([frame,changed,removed,shots])=>{
        for(const id of removed)units.delete(id);for(const row of changed){
          if(centi&&row.length===4){const old=units.get(row[0]),next=[...old];for(let i=0;i<3;i++)next[i+3]+=row[i+1];units.set(row[0],next);}
          else units.set(row[0],row);
        }
        return[frame,[...units.values()].map(row=>centi?row.slice(0,3).concat(row.slice(3).map(v=>v/100)):row),shots];
      });
    }
    assets.set(key,value);requests.get(key)?.resolve(value);
  }catch(error){requests.get(key)?.reject(error);}
};
function loadAsset(asset){
  if(assets.has(asset.key))return Promise.resolve(assets.get(asset.key));
  if(requests.has(asset.key))return requests.get(asset.key).promise;
  let resolve,reject;const promise=new Promise((ok,no)=>{resolve=ok;reject=no;});requests.set(asset.key,{promise,resolve,reject});
  const script=document.createElement('script');script.src=asset.url;script.onerror=()=>reject(Error('Could not load '+asset.url));document.head.append(script);return promise;
}
const fmt=(v,n=3)=>Number.isFinite(v)?v.toFixed(n):'—', pct=v=>Number.isFinite(v)?(v>0?'+':'')+fmt(v,1)+'%':'—', mean=a=>a.length?a.reduce((s,v)=>s+v,0)/a.length:0;
const color=name=>getComputedStyle(document.documentElement).getPropertyValue('--'+name).trim();
function option(select,value,label){const o=document.createElement('option');o.value=value;o.textContent=label;select.append(o);return o;}
function element(tag,attrs={},text){const e=document.createElementNS(NS,tag);for(const[k,v]of Object.entries(attrs))e.setAttribute(k,v);if(text!==undefined)e.textContent=text;return e;}
function svg(id,height){const box=$(id),width=Math.max(220,box.clientWidth);box.replaceChildren();const e=element('svg',{viewBox:`0 0 ${width} ${height}`,width,height,role:'img','aria-label':id.replaceAll('-',' ')});box.append(e);return{e,w:width,h:height};}
function text(e,x,y,label,attrs={}){const t=element('text',{x,y,...attrs},label);e.append(t);return t;}
function line(e,x1,y1,x2,y2,attrs={}){e.append(element('line',{x1,y1,x2,y2,...attrs}));}
function tip(event,label){const t=$('tooltip');t.textContent=label;t.hidden=false;const r=t.getBoundingClientRect();t.style.left=Math.max(8,Math.min(innerWidth-r.width-8,event.clientX+14))+'px';t.style.top=Math.max(8,Math.min(innerHeight-r.height-8,event.clientY+12))+'px';}
function hideTip(){$('tooltip').hidden=true;}
function hit(mark,label){mark.addEventListener('pointermove',e=>tip(e,label));mark.addEventListener('pointerleave',hideTip);mark.append(element('title',{},label));}
function numberTicks(max,n=4){return Array.from({length:n+1},(_,i)=>max*i/n);}
function isLanguage(){return state.comparison.startsWith('language');}
function summary(){return isLanguage()?state.scene[state.comparison]:state.scene.jobs[state.comparison==='jobs1'?'1':'4'];}
function runs(){return(summary()?.run_ids??[]).map(id=>DATA.runs[id]);}
function paired(){const groups=new Map();for(const r of runs()){if(!groups.has(r.repeat))groups.set(r.repeat,[]);groups.get(r.repeat).push(r);}return[...groups.values()].filter(p=>p.length===2&&new Set(p.map(variantOrder)).size===2&&p.every(r=>Number.isFinite(r.window_wall_ms_per_frame)&&(r.trace_frames===undefined||r.trace_frames===600))).sort((a,b)=>a[0].repeat-b[0].repeat).map(p=>p.sort((a,b)=>variantOrder(a)-variantOrder(b)));}
function variantOrder(r){return isLanguage()?(r.backend==='lua'?0:1):(r.rust_jobs==='off'?0:1);}
function names(){return isLanguage()?['Lua','Rust · serial']:['Rust · jobs off','Rust · jobs on'];}
function sceneNote(s){
  const notes={hunted:'Matched f32 math, lifecycle, food ordering and rounded falloff ties. The stress replay matches every recorded unit state and projectile sample.',hunted10:'10× initial scene, cloned after frame 60. Same AI and native pathfinder as normal gameplay.',flove:'350 mushrooms; same tree animation, hover highlighting and outlines in Lua and Rust.',flove10:'3,500 mushrooms plus the initial grove. Same targeting and visual effects; no reduced-effects shortcut.',ttld:'Gameplay view with shadows enabled in both. Matching deterministic lights and RGB targets.',ttld10:'10× initial population, shadows and lights retained in both. Native model streaming and shadow submission remain visible in CPU stacks.',area17:'1,329 initial units; matched scene placement, movement attributes and indexed civilian queries.',area172:'2× initial scene; normal NPC spawning and UFO behavior remain active.',fire1:'GPU curves and billboards in both; one deterministic burn/flame pair. Jobs controls use the Rust CPU particle-update reference (GPU graphics).',fire10:'Ten emitter pairs. GPU default versus Lua GPU renderer; jobs off/on is a separate CPU particle-update reference (GPU graphics).',fire100:'100 pairs, equal budgets, more than 50,000 normal particles. No Rust particle cap. Jobs off/on uses CPU particle updates with GPU graphics.',mycube:'Normal puzzle scene; no artificial unit stress.',partsneeded:'Normal village and wisp scene; cached live rosters in both implementations.'};
  return notes[s.id]+(s.game==='gravitas'?' Work alignment is in progress: upload coalescing, palette caching, expired-record retention and CPU age updates. GPU rendering leaves the jobs switch inactive; the CPU particle-update reference tests jobs while keeping GPU graphics.':'');
}

function overview(){
  const metric=$('overview-metric').value, rows=DATA.scenes.filter(s=>!s.different_cap), narrow=$('overview-chart').clientWidth<650;
  const rowH=narrow?65:48, top=28,bottom=52,{e,w}=svg('overview-chart',top+rows.length*rowH+bottom);
  const left=narrow?16:250,right=80,x0=left,x1=w-right;
  const values=rows.map(s=>{const p=s.language,rs=p.run_ids.map(id=>DATA.runs[id]),pairs=new Map();for(const r of rs){if(!r.pair_accepted)continue;if(!pairs.has(r.repeat))pairs.set(r.repeat,{});pairs.get(r.repeat)[r.backend]=r;}
    const value=r=>metric==='wall_mean'?r.window_wall_ms_per_frame:r.metrics[metric.startsWith('cpu')?'frame.cpu_us':metric.startsWith('sim')?'sim.elapsed_us':'draw.elapsed_us'][metric.endsWith('p95')?'p95':'p50']/1000;
    const ratios=[...pairs.values()].map(p=>value(p.wasm)/value(p.lua)),ratio=ratios.length?mean(ratios):NaN;
    return{s,p,change:(ratio-1)*100,lo:Number.isFinite(p[metric+'_mean_ratio_95ci_lo'])?(p[metric+'_mean_ratio_95ci_lo']-1)*100:NaN,hi:Number.isFinite(p[metric+'_mean_ratio_95ci_hi'])?(p[metric+'_mean_ratio_95ci_hi']-1)*100:NaN};});
  const lo=Math.min(-5,...values.flatMap(r=>[r.lo,r.change]).filter(Number.isFinite))-5,hi=Math.max(5,...values.flatMap(r=>[r.hi,r.change]).filter(Number.isFinite))+5,scale=x=>x0+(x-lo)/(hi-lo)*(x1-x0);
  for(let i=0;i<=4;i++){const value=lo+(hi-lo)*i/4;line(e,scale(value),top-8,scale(value),top+rows.length*rowH,{class:'grid'});text(e,scale(value),top+rows.length*rowH+19,fmt(value,0)+'%',{'text-anchor':'middle',class:'muted'});}
  line(e,scale(0),top-8,scale(0),top+rows.length*rowH,{class:'zero'});
  values.forEach((r,i)=>{const y=top+i*rowH+(narrow?34:18),g=element('g',{'class':'click-row'});g.append(element('rect',{x:0,y:top+i*rowH-8,width:w,height:rowH,fill:'transparent'}));
    if(narrow){text(g,8,y-17,r.s.title+' · '+r.s.load);}else{text(g,0,y-3,r.s.title);text(g,0,y+13,r.s.load,{class:'muted'});}
    if(Number.isFinite(r.lo)&&Number.isFinite(r.hi)){line(g,scale(r.lo),y,scale(r.hi),y,{stroke:'var(--rust)','stroke-width':2});for(const v of[r.lo,r.hi])line(g,scale(v),y-4,scale(v),y+4,{stroke:'var(--rust)'});}
    if(Number.isFinite(r.change))g.append(element('circle',{cx:scale(r.change),cy:y,r:4.5,fill:'var(--rust)'}));text(g,w-5,y+4,Number.isFinite(r.change)?pct(r.change):'pending',{'text-anchor':'end'});
    hit(g,`${r.s.title} · ${r.s.load}\nMean paired time change ${pct(r.change)}\nBootstrap 95% interval ${pct(r.lo)} to ${pct(r.hi)}\nMedian paired change ${pct(r.p[metric+'_paired_rust_change_pct'])}`);
    g.addEventListener('click',()=>{selectScene(r.s.id);location.hash='lab';});e.append(g);
  });
  text(e,(x0+x1)/2,top+rows.length*rowH+43,'Paired Rust time change (%)',{'text-anchor':'middle'});
}
function repeats(){
  const ps=paired();if(!ps.length){$('repeat-chart').textContent='No completed pair yet.';return;}const {e,w}=svg('repeat-chart',ps.length*39+70),left=60,right=22,top=25,max=Math.max(...ps.flat().map(r=>r.window_wall_ms_per_frame))*1.1,scale=v=>left+v/max*(w-left-right);
  for(const t of numberTicks(max)){line(e,scale(t),top-10,scale(t),top+ps.length*39,{class:'grid'});text(e,scale(t),top+ps.length*39+19,fmt(t,1),{'text-anchor':'middle',class:'muted'});}
  ps.forEach((p,i)=>{const y=top+i*39;const accepted=p.every(r=>r.pair_accepted);text(e,0,y+4,'Pair '+(p[0].repeat+1),{class:'muted'});line(e,scale(p[0].window_wall_ms_per_frame),y,scale(p[1].window_wall_ms_per_frame),y,{stroke:'var(--muted)','stroke-width':1,opacity:accepted?1:.35});p.forEach((r,j)=>{const c=element(j?'rect':'circle',j?{x:scale(r.window_wall_ms_per_frame)-4,y:y-4,width:8,height:8,fill:'var(--rust)',opacity:accepted?1:.3}:{cx:scale(r.window_wall_ms_per_frame),cy:y,r:4,fill:'var(--lua)',opacity:accepted?1:.3});hit(c,`${names()[j]} · pair ${r.repeat+1}\n${fmt(r.window_wall_ms_per_frame)} ms/frame\n${accepted?'Included':'Excluded as a pair'}`);e.append(c);});});
  text(e,left,13,'● '+names()[0],{fill:'var(--lua)'});text(e,w-right,13,'■ '+names()[1],{'text-anchor':'end',fill:'var(--rust)'});text(e,(left+w-right)/2,top+ps.length*39+43,'Whole-frame elapsed mean (ms/frame)',{'text-anchor':'middle'});
}
function optimizationTable(){
  const body=$('optimization-rows'), evidence=$('optimization-evidence');
  body.replaceChildren();evidence.replaceChildren();
  for(const r of DATA.optimization??[]){
    const tr=document.createElement('tr');
    const interval=r.wall_mean_ratio_95ci?.map(v=>pct((v-1)*100)).join(' to ')??'—';
    for(const value of [r.title+' · '+r.load,r.backend==='lua'?'Lua':'Rust',r.adopted===true?'Adopted':r.adopted===false?'Not adopted':'Trial',fmt(r.wall_before_ms)+' → '+fmt(r.wall_after_ms),pct(r.wall_change_pct),interval,fmt(r.sim_before_ms)+' → '+fmt(r.sim_after_ms),fmt(r.draw_before_ms)+' → '+fmt(r.draw_after_ms),r.measured_rounds+' / '+r.planned_rounds]){const td=document.createElement('td');td.textContent=value;tr.append(td);}body.append(tr);
    const details=document.createElement('details'), heading=document.createElement('summary');heading.textContent=r.title+' · '+r.load+' · '+(r.backend==='lua'?'Lua':'Rust');details.append(heading);
    const note=document.createElement('p');note.textContent=r.change;details.append(note);
    const paths=document.createElement('pre');paths.textContent=r.evidence.map((p,i)=>'Round '+(i+1)+'\n'+p.before+'\n'+p.after).join('\n\n');details.append(paths);evidence.append(details);
  }
}

function costs(){
  const good=runs().filter(r=>r.pair_accepted);if(!good.length){$('cost-chart').textContent='No accepted pair yet.';return;}const rs=[0,1].map(i=>good.filter(r=>variantOrder(r)===i)),computed=rs.map(group=>{
    const value=k=>mean(group.map(r=>r.means[k]));
    const sim=value('sim_ms'),draw=value('draw_ms');
    return{timerOff:group.length>0&&group.every(r=>r.callback_timers==='off'),total:sim+draw,lua:value('sim_lua_ms')+value('draw_lua_ms'),wasm:value('sim_wasm_ms')+value('draw_wasm_ms'),imports:value('sim_import_ms')+value('draw_import_ms'),segments:[['Simulation scope',sim,'host'],['Drawing scope',draw,'native']]};
  });
  const{e,w}=svg('cost-chart',195),left=8,right=15,max=Math.max(.001,...computed.map(r=>r.total))*1.03,scale=v=>v/max*(w-left-right);
  computed.forEach((r,i)=>{const y=28+i*78;text(e,left,y-8,names()[i]+' · '+fmt(r.total)+' ms');let x=left;for(const[label,value,c]of r.segments){const rect=element('rect',{x,y,width:scale(value),height:23,fill:'var(--'+c+')'});hit(rect,`${names()[i]}\n${label}\n${fmt(value)} ms · ${fmt(value/r.total*100,1)}% of mean sim + draw scope`);e.append(rect);x+=scale(value);}text(e,left,y+43,r.timerOff?'Callback timers disabled':r.wasm?`Dispatch ${fmt(r.wasm)} · imports ${fmt(r.imports)} ms (overlapping)`:`Lua callback scopes ${fmt(r.lua)} ms`,{class:'muted'});});
  $('ceiling').textContent='The dispatch timer excludes direct CUS ticks; total import time includes their imports. These overlapping counters cannot be subtracted to calculate Rust execution time. CPU stacks include execution outside those counters.';
}

function runTable(){const body=$('run-rows');body.replaceChildren();for(const r of runs()){const tr=document.createElement('tr');const values=[r.repeat+1,names()[variantOrder(r)],fmt(r.window_wall_ms_per_frame),fmt(r.metrics['sim.elapsed_us']?.p50/1000),fmt(r.metrics['draw.elapsed_us']?.p50/1000),fmt(r.population.units.p50,0),fmt(r.metrics['draw.imports']?.p50,0),r.pair_accepted?'yes':'no · '+(r.pair_rejection_reasons?.join(', ')||(r.gpu_contended?'GPU overlap':r.contended?'CPU pressure':'paired exclusion'))];for(const value of values){const td=document.createElement('td');td.textContent=value;tr.append(td);}body.append(tr);}}
let traceToken=0,traceValues=[];
async function traces(){const token=++traceToken,pair=paired().find(p=>p[0].repeat===+$('repeat').value);if(!pair){traceValues=[];$('trace-chart').textContent='No complete paired trace for this selection.';return;}try{const values=await Promise.all(pair.map(r=>loadAsset(r.trace)));if(token!==traceToken)return;traceValues=values;drawTrace();}catch(error){$('trace-chart').textContent=error.message;}}
function drawTrace(){
  if(traceValues.length!==2)return;const metric=$('trace-metric').value,indices={sim:1,draw:2,units:9,projectiles:10};const value=row=>metric==='cpu'?row[1]+row[2]:row[indices[metric]];
  const series=traceValues.map(rows=>rows.map(r=>[r[0],value(r)])),all=series.flat().map(r=>r[1]),{e,w}=svg('trace-chart',260),left=64,right=18,top=25,bottom=46,max=Math.max(...all,0.001)*1.06,x=v=>left+(v-300)/599*(w-left-right),y=v=>260-bottom-v/max*(260-top-bottom);
  e.append(element('rect',{x:left,y:top,width:w-left-right,height:260-top-bottom,class:'frame'}));for(const t of numberTicks(max)){line(e,left,y(t),w-right,y(t),{class:'grid'});text(e,left-8,y(t)+4,fmt(t,max>100?0:1),{'text-anchor':'end',class:'muted'});}
  for(const f of[300,500,700,899])text(e,x(f),237,''+f,{'text-anchor':'middle',class:'muted'});text(e,(left+w-right)/2,257,'Simulation frame',{'text-anchor':'middle'});text(e,10,18,metric==='units'||metric==='projectiles'?'Count':'Time (ms)');
  series.forEach((rows,i)=>{const c=i?'rust':'lua';const path=rows.map((r,j)=>(j?'L':'M')+x(r[0])+','+y(r[1])).join(' ');e.append(element('path',{d:path,stroke:'var(--'+c+')','stroke-width':.8,opacity:.4,fill:'none'}));const smoothed=rows.map((r,j)=>[r[0],mean(rows.slice(Math.max(0,j-7),Math.min(rows.length,j+8)).map(r=>r[1]))]);e.append(element('path',{d:smoothed.map((r,j)=>(j?'L':'M')+x(r[0])+','+y(r[1])).join(' '),stroke:'var(--'+c+')','stroke-width':2,fill:'none'}));text(e,i?w-right:left,14,(i?'■ ':'● ')+names()[i],{'text-anchor':i?'end':'start'});});
  const guide=element('line',{y1:top,y2:260-bottom,stroke:'var(--muted)',visibility:'hidden'});e.append(guide);const overlay=element('rect',{x:left,y:top,width:w-left-right,height:260-top-bottom,fill:'transparent'});overlay.addEventListener('pointermove',event=>{const box=e.getBoundingClientRect(),px=(event.clientX-box.left)*w/box.width,frame=Math.max(300,Math.min(899,Math.round(300+(px-left)/(w-left-right)*599))),i=frame-300;guide.setAttribute('x1',x(frame));guide.setAttribute('x2',x(frame));guide.setAttribute('visibility','visible');tip(event,`Frame ${frame}\n${names()[0]}: ${fmt(series[0][i][1])}${metric==='units'||metric==='projectiles'?'':' ms'}\n${names()[1]}: ${fmt(series[1][i][1])}${metric==='units'||metric==='projectiles'?'':' ms'}`);});overlay.addEventListener('pointerleave',()=>{guide.setAttribute('visibility','hidden');hideTip();});e.append(overlay);
}
async function selectScene(id){state.scene=DATA.scenes.find(s=>s.id===id)??DATA.scenes[0];$('scene').value=state.scene.id;const select=$('comparison');for(const o of select.options)o.disabled=o.value.startsWith('language')?!state.scene[o.value]:!state.scene.jobs[o.value==='jobs1'?'1':'4'];if(select.selectedOptions[0].disabled)select.value='language';state.comparison=select.value;refreshScene();}
function refreshScene(){
  const s=summary(),n=names(),a=s[isLanguage()?'wall_mean_lua_ms':'wall_mean_off_ms'],b=s[isLanguage()?'wall_mean_rust_ms':'wall_mean_on_ms'],change=s[isLanguage()?'wall_mean_paired_rust_change_pct':'wall_mean_paired_jobs_change_pct'];
  const runtime=s.runtime;
  $('scene-runtime').textContent=runtime?`Engine ${runtime.engine_commit??'unknown commit'} · SHA-256 ${runtime.engine_sha256}`:'';
  const repos={hunted:'Hunted',flove:'Flove',ttld:'LD43',area17:'Area-17',gravitas:'Gravitas',mycube:'LD42',partsneeded:'LD35'},sources=$('scene-sources');sources.replaceChildren();
  for(const[backend,label]of[['lua','Lua source'],['wasm','Rust source']]){const commit=s.game_content?.[backend]?.source_commit;if(!commit)continue;if(sources.childNodes.length)sources.append(' · ');const link=document.createElement('a');link.href=`https://github.com/SpringCabal/${repos[state.scene.game]}/tree/${commit}`;link.textContent=`${label} ${commit.slice(0,8)}`;sources.append(link);}
  $('scene-note').textContent=sceneNote(state.scene);$('scene-numbers').replaceChildren();for(const[label,value,sub]of[[n[0],fmt(a)+' ms','median of run window means'],[n[1],fmt(b)+' ms','median of run window means'],['Paired time change',pct(change),`${s.measured_pairs} accepted / ${s.attempted_pairs} pairs`]]){const d=document.createElement('div');const t=document.createElement('span');t.textContent=label;const v=document.createElement('strong');v.textContent=value;const sm=document.createElement('small');sm.textContent=sub;d.append(t,v,sm);$('scene-numbers').append(d);}
  videos();repeats();costs();cpuComparison();runTable();$('repeat').replaceChildren();for(const p of paired())option($('repeat'),p[0].repeat,'Pair '+(p[0].repeat+1)+(p.every(r=>r.pair_accepted)?'':' · excluded'));traces();loadWorlds();selectProfileForScene();
}

let worldToken=0,worldBounds=null;
async function loadWorlds(){
  const token=++worldToken;state.playing=false;$('play').textContent='Play';state.worlds=[];worldBounds=null;$('world-legend').replaceChildren();
  const wanted=isLanguage()?[['lua','off'],['wasm','off']]:[['wasm','off'],['wasm','on']];
  const width=isLanguage()?(runs()[0]?.worker_threads??1):4;
  const available=wanted.map(([backend,jobs])=>DATA.recordings.find(r=>r.scene===state.scene.id&&r.backend===backend&&r.jobs===jobs&&r.worker_threads===width&&matchesGame(r,backend)));
  const isFire=state.scene.game==='gravitas';$('worlds').hidden=isFire;$('fire-videos').hidden=!(DATA.videos??[]).some(v=>v.scene===state.scene.id);
  for(const id of['play','frame','fit','speed'])$(id).disabled=isFire||available.some(r=>!r);
  if(available.some(r=>!r)){$('world-status').textContent=isFire?'Fire uses the GPU-rendered clips below.':'No recording matching this engine and game revision yet. Jobs playback uses pool-four captures; timing charts retain the selected pool width.';drawWorlds();return;}
  $('world-status').textContent='Loading observed world states…';
  try{const recordings=await Promise.all(available.map(loadAsset));if(token!==worldToken)return;state.worlds=recordings;state.frame=+$('frame').value;worldBounds=bounds(recordings);$('world-status').textContent=state.comparison==='jobs1'?'Playback shows pool-four jobs captures; the timing charts above use pool one.':'Actual observed units and projectiles. Hover a unit for its definition, team and health.';worldLegend();drawWorlds();}catch(error){$('world-status').textContent=error.message;}
}
function unpack(world,row){return row.length>=7?row:[row[0],world.units[row[0]][0],world.units[row[0]][1],row[1],row[2],row[3],world.units[row[0]][2]];}
function bounds(worlds){let minX=Infinity,minZ=Infinity,maxX=-Infinity,maxZ=-Infinity;for(const world of worlds)for(const sample of world.samples)for(const row of sample[1]){const u=unpack(world,row);minX=Math.min(minX,u[3]);maxX=Math.max(maxX,u[3]);minZ=Math.min(minZ,u[4]);maxZ=Math.max(maxZ,u[4]);}if(!Number.isFinite(minX))return[0,0,worlds[0].header.map[0],worlds[0].header.map[1]];const pad=Math.max(80,(maxX-minX)*.04,(maxZ-minZ)*.04);return[minX-pad,minZ-pad,maxX+pad,maxZ+pad];}
function snapshot(world,frame){let i=Math.floor(frame/world.header.sample_frames);i=Math.min(i,world.samples.length-1);while(i>0&&world.samples[i][0]>frame)i--;const a=world.samples[i],b=world.samples[Math.min(i+1,world.samples.length-1)],t=b[0]===a[0]?0:(frame-a[0])/(b[0]-a[0]);const future=new Map(b[1].map(r=>[r[0],unpack(world,r)]));return{frame:a[0],units:a[1].map(row=>{const u=[...unpack(world,row)],v=future.get(u[0]);if(v){u[3]+=(v[3]-u[3])*t;u[4]+=(v[4]-u[4])*t;}return u;}),shots:a[2]};}
function teamColor(world,team){const c=world.header.teams[team]??[.7,.7,.7];return`rgb(${c.map(x=>Math.round(70+185*x)).join(',')})`;}
function drawWorlds(){
  $('frame-value').textContent=Math.round(state.frame);for(let i=0;i<2;i++){const id=i?'right':'left',canvas=$('world-'+id),rect=canvas.getBoundingClientRect(),w=Math.max(280,rect.width),h=w/1.3,dpr=devicePixelRatio||1;canvas.width=w*dpr;canvas.height=h*dpr;const ctx=canvas.getContext('2d');ctx.scale(dpr,dpr);ctx.fillStyle='#101b27';ctx.fillRect(0,0,w,h);$('world-'+id+'-title').textContent=names()[i];const world=state.worlds[i];if(!world){$('world-'+id+'-count').textContent='';continue;}
    const b=state.fit?worldBounds:[0,0,...world.header.map],scale=Math.min((w-24)/(b[2]-b[0]),(h-24)/(b[3]-b[1])),ox=(w-(b[2]-b[0])*scale)/2,oz=(h-(b[3]-b[1])*scale)/2,x=v=>ox+(v-b[0])*scale,z=v=>oz+(v-b[1])*scale;
    ctx.strokeStyle='#304252';ctx.lineWidth=.6;for(let q=0;q<=4;q++){const xx=w*q/4,zz=h*q/4;ctx.beginPath();ctx.moveTo(xx,0);ctx.lineTo(xx,h);ctx.moveTo(0,zz);ctx.lineTo(w,zz);ctx.stroke();}
    const sample=snapshot(world,state.frame);const points=[];for(const u of sample.units){const px=x(u[3]),pz=z(u[4]),r=sample.units.length>3000?1.8:sample.units.length>1000?2.2:3.2;ctx.fillStyle=teamColor(world,u[2]);ctx.beginPath();const shape=u[1]%4;if(shape===0)ctx.rect(px-r,pz-r,r*2,r*2);else if(shape===1)ctx.arc(px,pz,r,0,Math.PI*2);else if(shape===2){ctx.moveTo(px,pz-r*1.4);ctx.lineTo(px+r*1.3,pz+r);ctx.lineTo(px-r*1.3,pz+r);ctx.closePath();}else{ctx.moveTo(px,pz-r*1.4);ctx.lineTo(px+r*1.3,pz);ctx.lineTo(px,pz+r*1.4);ctx.lineTo(px-r*1.3,pz);ctx.closePath();}ctx.fill();points.push({x:px,z:pz,u});}
    ctx.strokeStyle='#fff0a8';ctx.lineWidth=1;for(const p of sample.shots){const px=x(p[1]),pz=z(p[2]);ctx.beginPath();ctx.moveTo(px-2,pz);ctx.lineTo(px+2,pz);ctx.moveTo(px,pz-2);ctx.lineTo(px,pz+2);ctx.stroke();}
    $('world-'+id+'-count').textContent=`${sample.units.length.toLocaleString()} units · ${sample.shots.length.toLocaleString()} sampled projectiles · ${(state.frame/30).toFixed(1)} simulated seconds`;
    canvas.onpointermove=event=>{const r=canvas.getBoundingClientRect(),px=(event.clientX-r.left)*w/r.width,pz=(event.clientY-r.top)*h/r.height;let nearest=null,distance=12;for(const p of points){const d=Math.hypot(px-p.x,pz-p.z);if(d<distance){distance=d;nearest=p;}}if(nearest){const u=nearest.u;tip(event,`${world.header.defs[u[1]]?.title||world.header.defs[u[1]]?.name||u[1]} · unit ${u[0]}\nTeam ${u[2]} · health ${fmt(u[5],0)} / ${fmt(u[6],0)}\nx ${fmt(u[3],1)}, z ${fmt(u[4],1)}`);}else hideTip();};canvas.onpointerleave=hideTip;
  }
}
function worldLegend(){const box=$('world-legend');box.replaceChildren();const world=state.worlds[0];if(!world)return;for(const team of Object.keys(world.header.teams)){const s=document.createElement('span'),dot=document.createElement('i');dot.style.background=teamColor(world,team);s.append(dot,document.createTextNode('Team '+team));box.append(s);}const used=new Set();for(const sample of world.samples)for(const row of sample[1])used.add(unpack(world,row)[1]);const shapes=['□','○','△','◇'];for(const id of[...used].sort((a,b)=>a-b)){const s=document.createElement('span');s.textContent=shapes[id%4]+' '+(world.header.defs[id]?.title||world.header.defs[id]?.name||id);box.append(s);}}
let lastAnimation=0;function animate(t){if(state.playing&&state.worlds.length){const dt=Math.min(.1,(t-lastAnimation)/1000);state.frame+=dt*30*+$('speed').value;if(state.frame>=900){state.frame=900;state.playing=false;$('play').textContent='Play';}$('frame').value=Math.round(state.frame);drawWorlds();}lastAnimation=t;requestAnimationFrame(animate);}

let profileToken=0;
function profileName(p){const s=DATA.scenes.find(s=>s.id===p.scene);return`${s.title} · ${s.load} · ${p.backend==='lua'?'Lua':'Rust · '+(p.fire_renderer==='cpu'?'CPU particle updates · GPU graphics · ':'')+'jobs '+p.jobs} · pool ${p.worker_threads??'?'}`;}
function matchingEffects(asset,expected){return state.scene.game!=='gravitas'||(JSON.stringify(asset.effects_fixtures)===JSON.stringify(expected?.effects_fixtures)&&asset.effects_probe_sha256===expected?.effects_probe_sha256);}
function matchingProfiles(backend,jobs){const width=runs()[0]?.worker_threads??(state.comparison.endsWith('4')?4:1),fire=state.scene.game==='gravitas'&&!isLanguage()?'cpu':'gpu',engine=summary()?.runtime?.engine_sha256,content=summary()?.game_content?.[backend]?.content_sha256,timers=runs()[0]?.callback_timers??'on';return DATA.profiles.filter(p=>p.scene===state.scene.id&&p.backend===backend&&p.jobs===jobs&&p.worker_threads===width&&(p.fire_renderer??'gpu')===fire&&p.engine_sha256===engine&&p.content_sha256===content&&p.callback_timers===timers&&matchingEffects(p,summary()?.game_content?.[backend]));}
function cpuComparison(){
  const variants=isLanguage()?[['lua','off'],['wasm','off']]:[['wasm','off'],['wasm','on']],candidates=variants.map(v=>matchingProfiles(...v));
  const left=candidates[0].find(a=>a.cpu_costs&&candidates[1].some(b=>b.cpu_costs&&a.pair_key===b.pair_key)),right=left&&candidates[1].find(b=>b.cpu_costs&&b.pair_key===left.pair_key),body=$('cpu-cost-rows'),leaves=$('cpu-leaves');
  body.replaceChildren();leaves.replaceChildren();names().forEach((n,i)=>$('cpu-'+(i?'right':'left')+'-label').textContent=n);
  if(!left||!right){$('cpu-cost-note').textContent='A complete pair of CPU captures matching this comparison is pending.';return;}
  $('cpu-cost-note').textContent='Separate clean CPU captures from one alternating pair, matching the engine, game code, renderer and worker count above. Approximate sampled CPU ms per rendered step; driver time includes CPU waits. These values do not replace timing-run frame times.';
  const a=left.cpu_costs,b=right.cpu_costs,categories=[...new Set([...Object.keys(a.categories),...Object.keys(b.categories)])].sort((x,y)=>(b.categories[y]??0)+(a.categories[y]??0)-(b.categories[x]??0)-(a.categories[x]??0));
  for(const[label,x,y]of[['Main thread total',a.main_ms,b.main_ms],...categories.map(k=>[k,a.categories[k]??0,b.categories[k]??0]),['Other threads · sum',a.other_threads_ms,b.other_threads_ms]]){const tr=document.createElement('tr');for(const value of[label,fmt(x),fmt(y),(y-x>0?'+':'')+fmt(y-x)]){const td=document.createElement('td');td.textContent=value;tr.append(td);}body.append(tr);}
  for(const p of[left,right]){const box=document.createElement('div'),button=document.createElement('button'),list=document.createElement('pre');button.textContent='Inspect '+profileName(p);button.onclick=()=>{$('profile').value=p.key;loadProfile();location.hash='profiles';};list.textContent=p.cpu_costs.leaves.map(r=>fmt(r.ms)+' ms  '+r.name).join('\n');box.append(button,list);leaves.append(box);}
}
function selectProfileForScene(){const preferred=matchingProfiles('wasm',isLanguage()?'off':'on')[0];if(preferred){$('profile').value=preferred.key;loadProfile();}else{++profileToken;state.profile=null;state.flame=null;state.history=[];$('profile').value='';$('thread').replaceChildren();for(const id of ['flame','flame-detail','profile-categories','profile-leaves'])$(id).replaceChildren();$('profile-meta').textContent='No sampled capture matching this comparison’s renderer, jobs, worker count, engine, game code and timers yet.';}}
async function loadProfile(){const token=++profileToken,entry=DATA.profiles.find(p=>p.key===$('profile').value);if(!entry){$('profile-meta').textContent='No sampled capture for this selection.';return;}try{const p=await loadAsset(entry);if(token!==profileToken)return;state.profile=p;state.history=[];$('thread').replaceChildren();const threads=[...p.threads].sort((a,b)=>b.weight-a.weight);for(const t of threads)option($('thread'),t.name,t.name+' · '+fmt(t.weight/1e6,0)+' sampled CPU ms');const main=threads.find(t=>t.name.includes('recoil-main'));if(main)$('thread').value=main.name;$('profile-meta').textContent=`${profileName(entry)} · ${p.samples.toLocaleString()} stack samples · ${p.run.renderer} · pool ${p.run.worker_threads} · timers ${p.run.callback_timers??'on'} · engine ${(p.runtime?.engine_commit??'unknown').slice(0,12)}${p.run.contended?' · CPU pressure flagged; diagnostic only':''}`;selectThread();}catch(error){$('profile-meta').textContent=error.message;}}
function selectThread(){state.flame=state.profile?.threads.find(t=>t.name===$('thread').value);state.history=[];drawFlame();profileCategories();}
function nodeName(n){return n.name==='[unknown]'?'[unresolved] '+n.dso:n.name;}
function drawFlame(){
  const root=state.flame;if(!root)return;const box=$('flame'),w=Math.max(280,box.clientWidth),nodes=[];function layout(n,x,width,depth){if(width<.7||depth>60)return;nodes.push({n,x,width,depth});let next=x;for(const child of n.children){const cw=width*child.weight/n.weight;layout(child,next,cw,depth+1);next+=cw;}}layout(root,0,w,0);const height=(Math.max(...nodes.map(n=>n.depth))+1)*23,e=element('svg',{viewBox:`0 0 ${w} ${height}`,height,role:'img','aria-label':'Sampled CPU flame graph, click blocks to zoom'});box.replaceChildren(e);const query=$('flame-search').value.toLowerCase();for(const{n,x,width,depth}of nodes){const label=nodeName(n),hash=[...label].reduce((h,c)=>(h*31+c.charCodeAt(0))>>>0,0),rect=element('rect',{x,y:height-(depth+1)*23,width,height:22,fill:query&&label.toLowerCase().includes(query)?'#d8a7ef':`hsl(${18+hash%45} 72% ${58+hash%16}%)`});const info=`${label}\n${fmt(n.weight/root.weight*100,2)}% of selected stack · ${fmt(n.weight/1e6)} sampled CPU ms\nSelf ${fmt((n.self||0)/1e6)} ms · ${n.dso||'thread total'}`;rect.append(element('title',{},info));rect.onpointermove=()=>{$('flame-detail').textContent=info;};rect.onclick=()=>{state.history.push(root);state.flame=n;drawFlame();};e.append(rect);if(width>45)text(e,x+4,height-depth*23-7,label.slice(0,Math.max(0,Math.floor((width-8)/6.6))));}$('flame-back').disabled=!state.history.length;$('flame-detail').textContent=`${nodeName(root)} · ${fmt(root.weight/1e6)} sampled CPU ms · click to zoom`;}
function profileCategories(){const p=state.profile,thread=$('thread').value,root=p.threads.find(t=>t.name===thread);if(!root)return;const cats=p.categories.filter(c=>c.thread===thread).sort((a,b)=>b.weight-a.weight),{e,w}=svg('profile-categories',cats.length*39+38),narrow=w<450,left=narrow?8:190,right=48,scale=v=>left+(w-left-right)*v/root.weight;cats.forEach((c,i)=>{const y=20+i*39;text(e,narrow?8:0,y-7,c.category==='Graphics driver (CPU)'?'CPU time in graphics driver':c.category,{class:'muted'});const rect=element('rect',{x:left,y:y-1,width:scale(c.weight)-left,height:10,fill:'var(--host)'});e.append(rect);text(e,w-2,y+9,fmt(c.weight/root.weight*100,1)+'%',{'text-anchor':'end'});});const body=$('profile-leaves');body.replaceChildren();for(const item of p.leaves.filter(l=>l.thread===thread).slice(0,16)){const tr=document.createElement('tr'),td=document.createElement('td'),sm=document.createElement('small');td.textContent=item.name;sm.textContent=item.dso;td.append(sm);const value=document.createElement('td');value.textContent=fmt(item.weight/root.weight*100,2)+'%';tr.append(td,value);body.append(tr);}}


function matchesGame(asset,backend){const expected=summary()?.game_content?.[backend];return !!expected&&asset.engine_sha256===summary()?.runtime?.engine_sha256&&!!asset.source_commit&&asset.source_commit===expected.source_commit&&Object.keys(asset.modules).length===Object.keys(expected.modules).length&&Object.keys(asset.modules).every(k=>asset.modules[k]===expected.modules[k])&&matchingEffects(asset,expected);}
function videos(){const clips=(DATA.videos??[]).filter(v=>v.scene===state.scene.id&&matchesGame(v,v.backend));$('video-grid').replaceChildren();for(const clip of clips){const f=document.createElement('figure'),caption=document.createElement('figcaption'),video=document.createElement('video');caption.textContent=clip.label;video.src=clip.url;video.controls=true;video.preload='metadata';video.playsInline=true;f.append(caption,video);$('video-grid').append(f);}if(!clips.length){const p=document.createElement('p');p.textContent='No rendered clips matching this engine and game revision yet.';$('video-grid').append(p);}}
function overviewTable(){
  const body=$('overview-rows');body.replaceChildren();
  for(const scene of DATA.scenes){
    const r=scene.language,tr=document.createElement('tr');tr.className='click-row';
    const cells=[scene.title+' · '+scene.load,fmt(r.wall_mean_lua_ms),fmt(r.wall_mean_rust_ms),pct(r.wall_mean_paired_rust_change_pct),
      fmt(r.sim_p50_lua_ms)+' / '+fmt(r.sim_p50_rust_ms),fmt(r.draw_p50_lua_ms)+' / '+fmt(r.draw_p50_rust_ms),
      fmt(r.lua_units_p50,0)+' / '+fmt(r.wasm_units_p50,0),r.measured_pairs+' / 5'];
    for(const value of cells){const td=document.createElement('td');td.textContent=value;tr.append(td);}
    tr.onclick=()=>{selectScene(scene.id);location.hash='lab';};body.append(tr);
  }
}
for(const s of DATA.scenes)option($('scene'),s.id,s.title+' · '+s.load);
for(const p of DATA.profiles)option($('profile'),p.key,profileName(p));
$('scene').onchange=()=>selectScene($('scene').value);$('comparison').onchange=()=>{state.comparison=$('comparison').value;refreshScene();};$('overview-metric').onchange=overview;$('repeat').onchange=traces;$('trace-metric').onchange=drawTrace;
$('frame').oninput=()=>{state.frame=+$('frame').value;drawWorlds();};$('play').onclick=()=>{if(state.frame>=900)state.frame=0;state.playing=!state.playing;$('play').textContent=state.playing?'Pause':'Play';};$('fit').onclick=()=>{state.fit=!state.fit;drawWorlds();};
$('profile').onchange=loadProfile;$('thread').onchange=selectThread;$('flame-back').onclick=()=>{state.flame=state.history.pop()??state.flame;drawFlame();};$('flame-reset').onclick=selectThread;$('flame-search').oninput=drawFlame;
$('theme').onclick=()=>{document.documentElement.dataset.theme=document.documentElement.dataset.theme==='dark'?'light':'dark';};
$('video-play').onclick=()=>{const videos=[...$('video-grid').querySelectorAll('video')],play=videos.some(v=>v.paused);for(const v of videos){if(play){v.currentTime=videos[0].currentTime;v.play().catch(()=>{});}else v.pause();}};
$('identities').textContent=JSON.stringify(DATA.audit,null,2);
let resizeTimer;new ResizeObserver(()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(()=>{overview();repeats();costs();drawTrace();drawWorlds();if(state.profile){drawFlame();profileCategories();}},100);}).observe(document.querySelector('main'));
$('campaign-status').textContent=`Snapshot ${DATA.audit.generated_at??'unknown time'} · ${DATA.audit.primary_scenes_at_five_pairs??'—'} / ${DATA.scenes.length} primary scenes have five clean pairs · callback timers ${(DATA.audit.callback_timers??[]).join(', ')||'pending'}.`;
$('total-runs').textContent=DATA.audit.runs;$('accepted-pairs').textContent=DATA.audit.accepted_pairs+' / '+DATA.audit.attempted_pairs;videos();optimizationTable();overviewTable();overview();selectScene(DATA.scenes[0].id);requestAnimationFrame(animate);
