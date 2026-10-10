-- Supply Gaps per-save state (PLAN "Per-save state"): whether "Show supply gaps" was on when the game
-- was saved. Shared by the engine game script (sg_state.script.tl: apply) and the GUI (sg_window.script.tl:
-- readOn / sendOn / the load decision). The saved state is { v = 1, on = boolean }; absent = off, and it is
-- written only when the player toggles the overlay (never per tick, never on load).
-- Mechanism copied from square_problem_radar (plans/square_problem_radar/PLAN.md): the GUI reads the
-- GAME_SCRIPT component of our game-script entity and sends changes as a scripting event
-- (radar_hud.script.tl readFields / sendEvent; radar.script.tl handleSettings).

local saved : SupplyGapsSaved = {}

saved.VERSION = 1
-- content/supply_gaps/sg.gs.lua; same naming as "square_problem_radar::/radar/radar.gs"
-- (src: .cache/game/mods/release/urbangames_campaign_mission_08/content/mission/mission_story.tl:891).
saved.GS_NAME = "square_supply_gaps::/supply_gaps/sg.gs"
saved.EVENT_ID = "SupplyGaps"
saved.EV_SET_ON = "SupplyGaps.setOn"
saved.LOAD_TRIES = 10

function saved.isOn(raw : any) : boolean
	if type(raw) ~= "table" then return false end
	return (raw as {string : any}).on == true
end

function saved.apply(raw : any, param : any) : SupplyGapsSavedState, boolean, string
	local old = saved.isOn(raw)
	local cur : SupplyGapsSavedState = { v = saved.VERSION, on = old }
	if type(param) ~= "table" or type((param as {string : any}).on) ~= "boolean" then
		return cur, false, "expected { on = boolean }, got " .. tostring(param)
	end
	local on = (param as {string : any}).on as boolean
	if on == old then return cur, false, nil end
	return { v = saved.VERSION, on = on }, true, nil
end

function saved.newLoad() : SupplyGapsSavedLoad
	return { done = false, tries = 0 }
end

function saved.loadStep(load : SupplyGapsSavedLoad, read : boolean) : string
	if load.done then return "done" end
	if read == nil then
		load.tries = load.tries + 1
		if load.tries < saved.LOAD_TRIES then return "wait" end
		load.done = true
		return "off"
	end
	load.done = true
	return read and "on" or "off"
end

--- GUI thread. src: square_problem_radar radar_hud.script.tl readFields (state_native:find, falling back to
--- the `state` copy); base: mission_framework_react.tl:49-51 (GUI reads GAME_SCRIPT state).
function saved.readOn() : boolean
	local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(saved.GS_NAME)
	if entity == nil or entity < 0 then return nil end
	local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<SupplyGapsSavedState>
	if gs == nil then return nil end
	local ok, v = pcall(function() : any
		local native = gs.state_native
		if native == nil then error("no state_native") end
		return native:find("on") as any
	end)
	if ok then return v == true end
	return saved.isOn(gs.state)
end

--- GUI thread. src: radar_hud.script.tl sendEvent; .cache/game/api/tealdef/api/cmd.d.tl:788.
function saved.sendOn(on : boolean)
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", saved.EVENT_ID, saved.EV_SET_ON, { on = on == true }))
end

return saved
