-- Organic Towns game script (registered by organic_towns.gs.lua). Plain Lua, pre-5.3; exports via data().
--   update       (simulation states) re-subscribes to our events once per load (subscriptions are saved
--                with the game, findings "Game-script event subscriptions are saved"). Nothing else: no
--                sendCommand (callbacks are disallowed there), no state:get_native (asserts).
--   handleEvent  applies the driver's events to the saved state (ot_saved; idempotent, as it may run in more
--                than one simulation state), and queues new player Road Stops for a landscape stop name
--                (onPostBuildProposal; the driver renames them from guiUpdate).
--   guiUpdate    (Main Thread) ticks the driver with a read-only copy of the saved state. It runs while the game is
--                paused too: the driver reads the game speed and starts nothing then (Driver:gameClock / pausedTick).
--                The copy (state:get()) is taken only when the state's change number moved (ot_saved Reader, 2026-10-20:
--                handleEvent bumps `rev` with every state:set; the number comes from the GAME_SCRIPT component's
--                state_native, the town window card's read), or after the driver sent an event until the copy shows
--                it, else the last copy is passed again. Any error of that read, or a cost check it fails, puts the
--                session back on a full copy every frame (one STATEREAD line).
-- Every entry point runs in pcall and logs a failure once, so a script error never reaches the game loop
-- (a throwing chunk would log "Expected table at path" every tick).

local function gget(k) local ok, v = pcall(function() return _G[k] end) if ok then return v end return nil end -- no rawget here
local req = gget("ug_require") or require
local SV = req "square_organic_towns::/organic_towns/ot_saved.lua"

local EV_POST = "onPostBuildProposal"   -- player builds (landscape stop names: new Road Stops queued, ot_saved.addStops)

--- Landscape or generated stop names on? (the "Town and stop names" setting, Act on not Off, never in the map editor, and a
--- base name list when runFn's config is visible here; unknown: queued anyway, the driver decides). Until 2026-10-14 only
--- "landscape" queued stops, so with Generated names no new stop was renamed (run 2026-10-14_0613_sqot: 0 STOPNAME).
local function stopsWanted()
	local PA = req "square_organic_towns::/organic_towns/ot_params.lua"
	local NM = req "square_organic_towns::/organic_towns/ot_names.lua"
	local okP, all = pcall(api.engine.config.getModParams)
	if not okP or type(all) ~= "table" then return false end
	local o = PA.parse(all[PA.MOD_ID], all)
	if o.mapEditor or o.actOn == "off" or (o.townNames ~= "landscape" and o.townNames ~= "generated") then return false end
	local cfg = gget("SQOT_CONFIG")
	if type(cfg) == "table" and cfg.nameList ~= nil and NM.basePath(cfg.nameList) == nil then return false end
	return true
end

local subscribed = false
local warned = {}
local driver = nil

local function warnOnce(where, err)
	if warned[where] then return end
	warned[where] = true
	log.warning("[SQOT] ERROR " .. where .. " " .. tostring(err))
end

local script = {}

function script.update(_userParams, state, _dt)
	if subscribed and state:hasEventSubscriptions() then return end
	local ok, err = pcall(function()
		state:subscribeToNoEvents()
		state:subscribeToEvent(SV.EV_INIT)
		state:subscribeToEvent(SV.EV_FRAME)
		state:subscribeToEvent(SV.EV_SAT)
		state:subscribeToEvent(SV.EV_BRIDGE)
		state:subscribeToEvent(SV.EV_NAMES)
		state:subscribeToEvent(SV.EV_STOPS)
		state:subscribeToEvent(SV.EV_LEAD)
		state:subscribeToEvent(SV.EV_WORKS)
		state:subscribeToEvent(SV.EV_STOPBASE)
		state:subscribeToEvent(SV.EV_LEVELS)
		state:subscribeToEvent(SV.EV_LEVELBASE)
		state:subscribeToEvent(SV.EV_PACE)
		state:subscribeToEvent(SV.EV_CHARS)
		state:subscribeToEvent(SV.EV_DENSE)
		state:subscribeToEvent(SV.EV_PAIR)
		state:subscribeToEvent(SV.EV_RCI)
		state:subscribeToEvent(SV.EV_GLOCK)
		state:subscribeToEvent(SV.EV_UI)
		state:subscribeToEvent(SV.EV_PROV)
		state:subscribeToEvent(EV_POST)
	end)
	subscribed = true
	if not ok then warnOnce("subscribe", err) end
end

function script.handleEvent(_userParams, state, _src, id, name, param)
	if id == "apply_command" and name == EV_POST then
		-- (no command here: build events can't send them; the queue goes through the saved state)
		local ok, err = pcall(function()
			local E = req "square_organic_towns::/organic_towns/ot_engine.lua"
			local found = E.collectStops(param)
			if #found == 0 or not stopsWanted() then return end
			local s, changed = SV.addStops(state:get(), found, E.osTime())
			if changed then state:set(SV.bumpRev(s)) end
		end)
		if not ok then warnOnce("stops", err) end
		return
	end
	if id ~= SV.EVENT_ID then return end
	local ok, err = pcall(function()
		local s, changed
		if name == SV.EV_INIT then
			s, changed = SV.applyInit(state:get(), param)
		elseif name == SV.EV_FRAME then
			s, changed = SV.applyFrame(state:get(), param)
		elseif name == SV.EV_SAT then
			s, changed = SV.applySat(state:get(), param)
		elseif name == SV.EV_BRIDGE then
			s, changed = SV.applyBridge(state:get(), param)
		elseif name == SV.EV_NAMES then
			s, changed = SV.applyNames(state:get(), param)
		elseif name == SV.EV_STOPS then
			s, changed = SV.applyStopsDone(state:get(), param)
		elseif name == SV.EV_LEAD then
			s, changed = SV.applyLead(state:get(), param)
		elseif name == SV.EV_WORKS then
			s, changed = SV.applyWorks(state:get(), param)
		elseif name == SV.EV_STOPBASE then
			s, changed = SV.applyStopBase(state:get(), param)
		elseif name == SV.EV_LEVELS then
			s, changed = SV.applyLevels(state:get(), param)
		elseif name == SV.EV_LEVELBASE then
			s, changed = SV.applyLevelBase(state:get(), param)
		elseif name == SV.EV_PACE then
			s, changed = SV.applyPace(state:get(), param)
		elseif name == SV.EV_CHARS then
			s, changed = SV.applyChars(state:get(), param)
		elseif name == SV.EV_DENSE then
			s, changed = SV.applyDense(state:get(), param)
		elseif name == SV.EV_PAIR then
			s, changed = SV.applyPair(state:get(), param)
		elseif name == SV.EV_RCI then
			s, changed = SV.applyRci(state:get(), param)
		elseif name == SV.EV_GLOCK then
			s, changed = SV.applyGlock(state:get(), param)
		elseif name == SV.EV_UI then
			s, changed = SV.applyUi(state:get(), param)
		elseif name == SV.EV_PROV then
			s, changed = SV.applyProv(state:get(), param)
		end
		if changed then state:set(SV.bumpRev(s)) end
	end)
	if not ok then warnOnce("handleEvent", err) end
end

local dead = false
local reader = nil

--- The saved change number through the GAME_SCRIPT component's state_native (Main Thread; the town window card and the
--- console lookup read the same way, findings game-scripts.md). Errors when there is no state to read (the reader then
--- stays on full copies for the session).
local function readRev()
	local e = api.engine.system.gameScriptSystem.getEntityForGameScript(SV.GS_NAME)
	if e == nil or e < 0 then error("no game script entity") end
	local gs = api.engine.getComponent(e, api.type.ComponentType.GAME_SCRIPT)
	if gs == nil then error("no GAME_SCRIPT component") end
	local st = gs.state_native
	if st == nil then error("no state_native") end
	return st:find(SV.REV_KEY)
end

function script.guiUpdate(_userParams, state, _guiState)
	if dead then return end
	local ok, err = pcall(function()
		if driver == nil then
			local E = req "square_organic_towns::/organic_towns/ot_engine.lua"
			local D = req "square_organic_towns::/organic_towns/ot_driver.lua"
			driver = D.new(E)
			-- dev tools (square_organic_towns_dev, same Lua state) read the instance; nothing else does
			local H = req "square_organic_towns::/organic_towns/ot_hooks.lua"
			H.main = driver
		end
		-- (frame cost, 2026-10-14: every tick timed, state:get() apart; one TICKCOST line per window, Driver:costNote)
		-- (2026-10-20: the whole copy only when the saved change number moved, ot_saved Reader; TICKCOST getN / stateMode)
		local nowUs = driver.E.nowUs
		if reader == nil then reader = SV.newReader() end
		local t0 = nowUs()
		local getFull = function() return state:get() end
		local okRd, saved, full, why = pcall(reader.read, reader, getFull, readRev, nowUs)
		if not okRd then   -- (never expected: the old path for the session)
			why = reader:fallBack("reader: " .. tostring(saved))
			local okG, v = pcall(getFull)
			saved, full = okG and v or nil, true
		end
		local t1 = nowUs()
		if why ~= nil then log.warning("[SQOT] STATEREAD mode=get reason=" .. tostring(why)) end
		local at = driver:costStage()
		local sent = driver.E.sentN
		driver:tick(t1, saved)
		local t2 = nowUs()
		if driver.E.sentN ~= sent then reader:expect(t2) end   -- (its own changes: copied again until they show)
		if at == "idle" then at = driver:costStage() end
		pcall(driver.costNote, driver, t2, t2 - t0, t1 - t0, at, full, reader.mode, reader.miss)
	end)
	if not ok then
		warnOnce("guiUpdate", err)
		if driver == nil then dead = true end   -- the modules failed to load: stay quiet from now on
	end
end

function data()
	return script
end
