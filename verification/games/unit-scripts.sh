#!/usr/bin/env bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib/common.sh"

LUA_GAME_DIR="$GAMES_DIR/PartsNeeded.sdd"
WASM_GAME_DIR="$GAMES_DIR/PartsNeeded-wasm.sdd"
MAP_DIR="$MAPS_DIR/LD35-map.sdd"
MAP_NAME='LD35 map 0.1'
LUA_GAME_NAME='Parts Needed $VERSION'
WASM_GAME_NAME='Parts Needed WASM 0.1.0-wasm'
SOURCE_ROOT="$WASM_GAME_DIR/wasm-src"
PROBE="$FIXTURES_DIR/unit_scripts/unit_script_probe.lua"
DRIVER="$FIXTURES_DIR/unit_scripts/unit_script_driver.lua"
ASSEMBLY="$FIXTURES_DIR/unit_scripts/unit_script_assemble.lua"
NO_END="$FIXTURES_DIR/unit_scripts/unit_script_no_end.lua"
COMPARE="$VERIFICATION_ROOT/unit-scripts/compare.py"
SOURCE_COMPARE="$VERIFICATION_ROOT/unit-scripts/compare_source.py"
# Sample every simulation frame through the form switch and gait. The two
# deterministic form changes are delivered by different gadget boundaries in
# Lua and Core Wasm, so their same-frame samples can observe one side before
# the change and the other after it. Sample the completed transition on the
# following frame; all stable animation frames remain densely checked.
SAMPLE_FRAMES=$(seq -s, 10 42),$(seq -s, 44 88),$(seq -s, 90 170)
PROBE_PIECES='Body,Head,Eyes,Ears,Mouth,Nose,ArmL,ArmR,ForeArmL,ForeArmR,HandL,HandR,ThighL,ThighR,CrusL,CrusR,FootL,FootR,Hair1,Hair2,Hair3,Hair4'

unit_scripts_start() {
	local game=${1:?game name}
	vf_start_inline <<EOS
[GAME]
{
[team0] { startposx=2000; startposz=2000; allyteam=0; teamleader=0; }
[allyteam0] { numallies=0; }
[player0] { team=0; spectator=0; name=unit-script-probe; }
[modoptions] { probe_unit=wisp; probe_frames=$SAMPLE_FRAMES; probe_pieces=$PROBE_PIECES; probe_info_pieces=Body; unit_script_probe=1; }
minspeed=100; maxspeed=100; ishost=1; hostip=127.0.0.1; gamemode=0; numteams=1; numusers=1; numplayers=1; myplayernum=0; myplayername=unit-script-probe; hostport=8452; startpostype=0; gamestartdelay=0;
gametype=$game; mapname=$MAP_NAME;
}
EOS
}

unit_scripts_run_one() {
	local label=${1:?label} archive=${2:?archive} game=${3:?game} seconds=${4:-25}
	VF_OUT_DIR="$VERIFICATION_ROOT/out/unit-scripts-partsneeded-$label"
	vf_workspace "unit-scripts-partsneeded-$label"
	local staged
	staged=$(vf_stage_game "$archive")
	if [[ $label == wasm ]]; then
		vf_install_modules "$staged" \
			partsneeded_rules_wasm:LuaRules/wasm/partsneeded-rules.wasm \
			partsneeded_ui_wasm:LuaUI/wasm/partsneeded-ui.wasm
	fi
	mkdir -p "$staged/LuaRules/Gadgets"
	cp "$PROBE" "$staged/LuaRules/Gadgets/unit_script_probe.lua"
	if [[ $label == lua ]]; then
		# The WASM archive has the equivalent deterministic assembly gadget in
		# its Rust rules module when built with unit-script-probe. Loading this
		# Lua fixture there as well would assemble the same body twice and give
		# the two runtimes different pre-switch animation history.
		cp "$ASSEMBLY" "$staged/LuaRules/Gadgets/unit_script_assemble.lua"
	fi
	# Keep the LuaUI boundary identical in both runs. The WASM archive normally
	# ships a Rust UI module, but legacy LuaUI widgets are also active and are
	# the game's actual input boundary.
	mkdir -p "$staged/LuaUI/Widgets"
	cp "$DRIVER" "$staged/LuaUI/Widgets/unit_script_driver.lua"
	if [[ $label == lua ]]; then
		cp "$NO_END" "$staged/LuaRules/Gadgets/game_end.lua"
	fi
	vf_link_map "$MAP_DIR"
	vf_link_game "$staged"
	unit_scripts_start "$game"
	vf_config
	vf_run_visual "$seconds" 1280x720x24
	vf_save_logs
	vf_forbid 'Fatal:|Wasm.*(trap|error|Error)|CallIn.*(error|Error)|panic|\[UnitScriptProbe\] ERROR' \
		"$label unit-script probe contains a runtime failure"
	grep -qF '[UnitScriptProbe] DONE' "$VF_OUT_DIR/last.combined.txt" ||
		vf_die "$label unit-script probe did not complete"
	cp "$VF_OUT_DIR/last.combined.txt" "$VF_OUT_DIR/trace.log"
	vf_keep_workspace_unless
}

# Compares the Lua animation tables with table-driven Rust gait tables.  That
# layout (rules-synced/src/unit_scripts/) only ever existed in an unfinished
# split of unit_scripts.rs; the committed port uses plain Turn() calls.  The
# trace comparison (partsneeded mode) checks the engine result either way.
partsneeded_source() {
	[[ -d $LUA_GAME_DIR && -d $WASM_GAME_DIR ]] || vf_die 'Parts Needed archives are missing'
	if [[ ! -d $SOURCE_ROOT/rules-synced/src/unit_scripts ]]; then
		echo 'SKIP  unit-script source comparison: no table-driven rules-synced/src/unit_scripts/ in this checkout'
		return 0
	fi
	python3 "$SOURCE_COMPARE" \
		"$LUA_GAME_DIR/Scripts/animations" \
		"$SOURCE_ROOT/rules-synced/src/unit_scripts"
}

partsneeded_unit_scripts() {
	local seconds=${1:-25}
	vf_cleanup_on_exit
	[[ -f $PROBE ]] || vf_die "unit-script probe is missing: $PROBE"
	[[ -d $MAP_DIR ]] || vf_die "map archive is missing: $MAP_DIR"
	partsneeded_source

	# Build the real shipped WASM modules, without the integration feature. The
	# probe itself is the only test gadget in these runs, so Lua and WASM receive
	# the same observation schedule and no synthetic gameplay is injected.
	vf_build "$SOURCE_ROOT" unit-script-probe
	unit_scripts_run_one lua "$LUA_GAME_DIR" "$LUA_GAME_NAME" "$seconds"
	unit_scripts_run_one wasm "$WASM_GAME_DIR" "$WASM_GAME_NAME" "$seconds"

	python3 "$COMPARE" \
		"$VERIFICATION_ROOT/out/unit-scripts-partsneeded-lua/trace.log" \
		"$VERIFICATION_ROOT/out/unit-scripts-partsneeded-wasm/trace.log"
	echo '>>> Parts Needed Lua/WASM unit-script verification passed <<<'
}

case "${1:-partsneeded}" in
	source) partsneeded_source ;;
	partsneeded) partsneeded_unit_scripts "${2:-}" ;;
	*) vf_die 'usage: unit-scripts.sh [source|partsneeded]' ;;
esac
