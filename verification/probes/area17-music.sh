#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"
MUSIC_PROBE_PLATFORM=${MUSIC_PROBE_PLATFORM:-native}
for variant in lua wasm; do
 if [[ $variant == wasm && ${MUSIC_PROBE_REBUILD:-0} == 1 ]]; then
  vf_build "$GAMES_DIR/Area17-wasm.sdd/wasm-src" ""
 fi
 vf_workspace "area17-music-${MUSIC_PROBE_PLATFORM:?}-$variant" stable
 game="$GAMES_DIR/Area-17.sdd"
 [[ $variant != wasm ]] || game="$GAMES_DIR/Area17-wasm.sdd"
 staged=$(vf_stage_game "$game")
 if [[ $variant == wasm && ${MUSIC_PROBE_REBUILD:-0} == 1 ]]; then
  vf_install_modules "$staged" area17_rules_wasm:LuaRules/wasm/area17-rules.wasm area17_ui_wasm:LuaUI/wasm/area17-ui.wasm
 fi
 if [[ ${MUSIC_PROBE_SHORT:-0} == 1 ]]; then
  ffmpeg -v error -y -i "$game/sounds/music.ogg" -t 2 -c:a libvorbis "$staged/sounds/music-short.ogg"
  mv "$staged/sounds/music-short.ogg" "$staged/sounds/music.ogg"
 fi
 cp "$FIXTURES_DIR/area17/music_probe.lua" "$staged/LuaRules/Gadgets/zz_music_probe.lua"
 sed -i '/function addon.Shutdown()/a\ Spring.Echo("[MusicProbe] INTRO SHUTDOWN")' "$staged/luaintro/Addons/music.lua"
 if [[ $variant == lua ]]; then
  sed -i '/Spring.PlaySoundStream(musicFile, VOLUME)$/a\        Spring.Echo("[MusicProbe] LUA START")' "$staged/LuaUI/Widgets/snd_music.lua"
 fi
 vf_link_map "$(scripts/area17-map.sh --dir)"
 vf_start_file "$(vf_launch_script area17 "$variant")"
 vf_config
 vf_config_set Sound 1
 vf_config_set snd_volmaster "${MUSIC_PROBE_MASTER:-0}"
 vf_config_set snd_volmusic 100
 vf_config_set snd_volgeneral 0
 vf_config_set snd_volbattle 0
 vf_config_set snd_volui 0
 vf_config_set snd_volunitreply 0
 vf_graphics area17
 vf_run_visual 20
 vf_save_logs
 vf_require_clean_exit
 grep '\[MusicProbe\]' "$VF_OUT_DIR/last.stdout.txt"
 python3 - "$VF_OUT_DIR/last.stdout.txt" "$VF_OUT_DIR/music.json" "${MUSIC_PROBE_SHORT:-0}" <<'MUSIC_CHECK'
import json,re,sys
from pathlib import Path
text=Path(sys.argv[1]).read_text()
assert '[MusicProbe] INTRO SHUTDOWN' in text, 'intro did not shut down'
assert '[MusicProbe] GAMESTART' in text, 'game did not start'
rows=[tuple(map(float,m)) for m in re.findall(r'\[MusicProbe\] elapsed=([0-9.]+).*?played=([0-9.]+) length=([0-9.]+)',text)]
assert len(rows)>=8, rows
alive=[r for r in rows if r[0]>1 and r[1]>0 and r[2]>0]
assert len(alive)>=4, rows
resets=sum(b[1]<a[1]-.5 for a,b in zip(alive,alive[1:]))
if sys.argv[3]=='1':assert resets>=2 and all(1.8<=r[2]<=2.2 for r in alive), (resets,alive)
else:assert max(r[1] for r in alive)>3, alive
Path(sys.argv[2]).write_text(json.dumps({'active_samples':len(alive),'resets':resets,'samples':rows},indent=2)+'\n')
print('PASS music stream: active samples=%d loop resets=%d' % (len(alive),resets))
MUSIC_CHECK
done
