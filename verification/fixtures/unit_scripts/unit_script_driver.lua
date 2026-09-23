-- Deterministic LuaUI input driver for the unit-script conformance probe.
--
-- This deliberately uses the same LuaUI -> LuaRules message path as the
-- game's real controls.  It is copied into both staged archives, including
-- the WASM archive, so movement is driven by the UI boundary rather than by
-- a runtime-specific synced test gadget.

function widget:GetInfo()
	return {
		name = "Unit Script Conformance Driver",
		desc = "Drives the shared Parts Needed unit-script probe",
		author = "springcabal verification",
		license = "GPL v2 or later",
		layer = 1000000,
		enabled = true,
	}
end

local beginSent = false

function widget:Initialize()
	Spring.Echo("[UnitScriptProbeDriver] LOADED script=LuaUI")
end

-- The WASM UI widget is updated on render ticks, not synced GameFrame ticks.
-- Drive the Lua comparison from the same UI update boundary so the test does
-- not mistake different message delivery cadence for different unit scripts.
function widget:Update()
	if not beginSent then
		beginSent = true
		Spring.Echo("[UnitScriptProbeDriver] BEGIN")
		-- The synced probe schedules every subsequent action at fixed simulation
		-- frames.  The UI is still the entry point, but render cadence cannot
		-- change which pose is sampled in one implementation versus the other.
		Spring.SendLuaRulesMsg("probe_begin")
	end
end
