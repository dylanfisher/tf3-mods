-- DEV ONLY (never upload). Organic Towns dev tools game script (registered by otd.gs.lua). Plain Lua, pre-5.3;
-- exports via data().
--   update          (simulation states) subscribes to the HUD's command event once per load; nothing else.
--   guiHandleEvent  (Main Thread) a HUD command (api.gui.fireGuiScriptEvent): handled or queued by the runner;
--                   returns the status table (fireGuiScriptEvent hands the handler's result back to the HUD).
--   guiUpdate       (Main Thread, same Lua state as the main mod's driver) ticks the runner and pushes the status
--                   to the HUD with api.gui.fireReactEvent (base mission_sim.script.tl does the same).
-- The main mod's modules are loaded lazily on the first call, by ug_require across mods
-- ("square_organic_towns::/organic_towns/..."); a failure (main mod disabled) is logged once as
-- "[SQOT_DEV] LOAD ok=false" and shown in the HUD. Every entry point runs in pcall.

local function gget(k) local ok, v = pcall(function() return _G[k] end) if ok then return v end return nil end -- no rawget here
local req = gget("ug_require") or require
local S = req "square_organic_towns_dev::/organic_towns_dev/otd_shared.lua"

local MAIN = "square_organic_towns::/organic_towns/"
local STATUS_EVERY_US = 500000
local HEARTBEAT_US = 3000000

local subscribed = false
local runner, loadErr, E = nil, nil, nil
local warned = {}
local lastPushUs, lastPushV = -1e18, -1

local function warnOnce(where, err)
	if warned[where] then return end
	warned[where] = true
	log.warning(S.PREFIX .. " ERROR " .. where .. " " .. tostring(err))
end

local function load()
	if runner ~= nil or loadErr ~= nil then return runner end
	local ok, err = pcall(function()
		local D = req(MAIN .. "ot_driver.lua")
		E = req(MAIN .. "ot_engine.lua")
		local deps = {
			D = D, E = E, SV = req(MAIN .. "ot_saved.lua"), OG = req(MAIN .. "ot_graph.lua"),
			PR = req(MAIN .. "ot_proposal.lua"), H = req(MAIN .. "ot_hooks.lua"),
			X = req "square_organic_towns_dev::/organic_towns_dev/otd_engine.lua",
			UN = req "square_organic_towns_dev::/organic_towns_dev/otd_undo.lua",
			ST = req(MAIN .. "ot_style.lua"), I = req(MAIN .. "ot_inputs.lua"), MT = req(MAIN .. "ot_metrics.lua"),
			S = S, L = req "square_organic_towns_dev::/organic_towns_dev/otd_layout.lua",
			SC = req "square_organic_towns_dev::/organic_towns_dev/otd_showcase.lua",
			NM = req(MAIN .. "ot_names.lua"),   -- test stops: the stop themes of the main mod's stop names
		}
		-- roundabout probe: square_roundabouts' pure geometry when that mod is installed (optional)
		deps.RB = req "square_organic_towns_dev::/organic_towns_dev/otd_roundabout.lua"
		deps.ND = req "square_organic_towns_dev::/organic_towns_dev/otd_nodedump.lua"
		deps.SG = req "square_organic_towns_dev::/organic_towns_dev/otd_simgrow.lua"
		deps.A = req(MAIN .. "ot_assess.lua")   -- Simulate: the main driver's cooldowns (raised pace during a run)
		deps.UP = req(MAIN .. "ot_upward.lua")  -- Simulate, Build out: the upward / level-weight gaps (lowered during a run)
		deps.rbGeom, deps.rbWhy = deps.RB.load(req)
		log.message(S.PREFIX .. " ROUNDABOUTS available=" .. tostring(deps.rbGeom ~= nil) .. " why=" .. tostring(deps.rbWhy or "-"))
		local R = req "square_organic_towns_dev::/organic_towns_dev/otd_runner.lua"
		runner = R.new(deps)
		-- whether the main driver shares this Lua state is logged by the runner a few seconds later ("MAIN visible=")
		log.message(S.PREFIX .. " LOAD ok=true")
	end)
	if not ok then
		loadErr = tostring(err)
		log.warning(S.PREFIX .. " LOAD ok=false err=" .. loadErr)
	end
	return runner
end

local script = {}

function script.update(_userParams, state, _dt)
	if subscribed and state:hasEventSubscriptions() then return end
	local ok, err = pcall(function()
		state:subscribeToNoEvents()
		state:subscribeToEvent(S.EV_CMD)
	end)
	subscribed = true
	if not ok then warnOnce("subscribe", err) end
end

function script.guiHandleEvent(_userParams, _state, _guiState, _src, id, name, param)
	if name ~= S.EV_CMD or id ~= S.GUI_ID then return nil end
	local result = nil
	local ok, err = pcall(function()
		if load() == nil then
			result = { loadError = loadErr }
			return
		end
		result = runner:command(param, E.nowUs(), S)
	end)
	if not ok then
		warnOnce("guiHandleEvent", err)
		return { error = tostring(err) }
	end
	return result
end

function script.guiUpdate(_userParams, _state, _guiState)
	local ok, err = pcall(function()
		local r = load()
		if r == nil then
			-- tell the HUD why nothing works (every few seconds)
			local X = nil
			pcall(function() X = req "square_organic_towns_dev::/organic_towns_dev/otd_engine.lua" end)
			local okC, c = pcall(function() return api.type.Clock.new():getTime() end)
			local now = okC and c or 0
			if X and now - lastPushUs > HEARTBEAT_US then
				lastPushUs = now
				X.pushStatus({ loadError = loadErr })
			end
			return
		end
		local now = E.nowUs()
		r:tick(now)
		if (r.version ~= lastPushV and now - lastPushUs > STATUS_EVERY_US) or now - lastPushUs > HEARTBEAT_US then
			lastPushUs, lastPushV = now, r.version
			r.X.pushStatus(r:status())
		end
	end)
	if not ok then warnOnce("guiUpdate", err) end
end

function data()
	return script
end
