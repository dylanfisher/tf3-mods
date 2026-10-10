-- Supply Gaps engine game script (PLAN "Per-save state"): keeps one flag per savegame, whether the
-- overlay was on. State { v = 1, on = boolean } (sg_saved.tl). Absent state = off: a save that never
-- had the mod (or never toggled) has no state, and nothing is written until the player toggles.
-- state:set runs only in handleEvent, only when `on` changes; update never writes state.
-- update only (re)subscribes to our one GUI event, once per load (docs/findings.md "Game-script event
-- subscriptions are saved"); map editor: nothing.
-- Pattern: mods/square_problem_radar/content/radar/radar.script.tl (subscribe, ensureSubscribed,
-- handleSettings, pcall around every entry point). API: .cache/game/base/tealdef/scripts/gamescript.d.tl:40-59.
-- Registered by sg.gs.lua; the GUI sends:
--   api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", "SupplyGaps", "SupplyGaps.setOn", { on = true }))

-- SQPERF (plans/sqperf/README.md): load time of this game-script Lua state, slow update / event calls
-- (> 50 ms, at most one line per section per minute) and, with the "Debug: performance log" mod
-- setting, a 30 s summary. Local counters only; nothing is saved.
local sqperf = ug_require "square_supply_gaps::/sqperf/square_supply_gaps.lua" as SquareSupplyGapsSqPerf
local perf = sqperf.new({ mod = "square_supply_gaps", ctx = "gs", paramKey = "sqperf_log" })
local perfInit = perf:start()

local saved = ug_require "square_supply_gaps::/supply_gaps/sg_saved.tl" as SupplyGapsSaved

local PREFIX <const> = "[SQSG] "

local warned : {string : boolean} = {}

local function warnOnce(key : string, msg : string)
	if warned[key] then return end
	warned[key] = true
	log.warning(PREFIX .. msg)
end

-- Cached once per Lua state (the map editor and a game are separate loads).
local mapEditorCache : boolean = nil

local function isMapEditor() : boolean
	-- src: radar.script.tl isMapEditor; base company_growth.script.tl:74; API engine.d.tl:1807 (getModParams)
	if mapEditorCache == nil then
		local params = api.engine.config.getModParams()
		local base = params ~= nil and params[""] or nil
		mapEditorCache = base ~= nil and base["isMapEditor"] == true
	end
	return mapEditorCache
end

-- Subscriptions are saved with the game; re-subscribe once per load (module-local, so every load
-- starts false). Pattern: subventions.script.tl:375-383 via radar.script.tl subscribe.
local subscribedThisLoad = false

local function ensureSubscribed(state : GameScriptState<SupplyGapsSavedState>)
	if subscribedThisLoad and state:hasEventSubscriptions() then return end
	state:subscribeToNoEvents()
	state:subscribeToEvent(saved.EV_SET_ON)
	subscribedThisLoad = true
end

local function doUpdate(state : GameScriptState<SupplyGapsSavedState>) : any
	if subscribedThisLoad then return end
	if isMapEditor() then return end
	ensureSubscribed(state)
end

local function doHandleEvent(state : GameScriptState<SupplyGapsSavedState>, id : string, name : string, param : any) : any
	if id ~= saved.EVENT_ID or name ~= saved.EV_SET_ON then return end
	if isMapEditor() then return end
	local s, changed, rejected = saved.apply(state:get(), param)
	if rejected ~= nil then
		log.warning(PREFIX .. "ignored " .. name .. ": " .. rejected)
		return
	end
	if changed then
		state:set(s)
		log.message(PREFIX .. "saved on=" .. tostring(s.on))
	end
end

-- Both entry points run their body in one pcall: an error is logged once and never reaches the
-- engine's update / event handling (or a save in progress).
local script : GameScript<SupplyGapsSavedState> = {
	update = function(_userParams : table, state : GameScriptState<SupplyGapsSavedState>, _dt : number) : any
		local t = perf:start()
		local ok, err = pcall(doUpdate, state)
		perf:stop("update", t)
		if not ok then warnOnce("update", "state update failed: " .. tostring(err)) end
	end,

	handleEvent = function(_userParams : table, state : GameScriptState<SupplyGapsSavedState>, _src : string, id : string, name : string, param : any) : any
		local t = perf:start()
		local ok, err = pcall(doHandleEvent, state, id, name, param)
		perf:stop("event", t)
		if not ok then warnOnce("handleEvent", "event '" .. tostring(name) .. "' failed: " .. tostring(err)) end
	end,
}

perf:phase("init", perfInit)

return script
