-- Better Auto Vehicle Renamer game script (bavr.gs.lua registers it): thin glue from the engine to bavr_game.lua,
-- which holds the logic (PLAN.md "Phase 2"). update and handleEvent run on the simulation threads, in several Lua
-- states; each has its own engine (module local) and they share only the game-script state (state:get / set).
-- Exports through data() (docs/findings/game-scripts.md ".script.lua exports via data()").

-- SQPERF (plans/sqperf/README.md): sections update / get / step / set / event, counter renamed; first = the first
-- state read (full validate) and the first slice of each Lua state.
local sqperf = ug_require "square_better_auto_vehicle_renamer::/sqperf/square_better_auto_vehicle_renamer.lua"
local perf = sqperf.new({ mod = "square_better_auto_vehicle_renamer", ctx = "gs", paramKey = "sqperf_log",
	first = { "get", "step" } })
local perfInit = perf:start()

local Game = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_game.lua"
local Reader = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_reader.lua"

local E = Game.newEngine()
local env = nil

--- The engine's side of bavr_game.lua's env, made on the first call (api is complete by then).
local function makeEnv()
	local engine, util = api.engine, api.engine.util
	local CT = api.type.ComponentType
	local function world() return util.getWorld() end
	return {
		now = function()
			local gt = engine.getComponent(world(), CT.GAME_TIME)
			return gt ~= nil and gt.gameTime or nil
		end,
		speedup = function()
			local gs = engine.getComponent(world(), CT.GAME_SPEED)
			return gs ~= nil and gs.speedup or nil
		end,
		params = function() return api.engine.config.getModParams() end,
		log = function(line) log.message(line) end,
		send = function(id, name)
			-- re-checked right before the command: a vehicle sold since the slice is skipped
			if engine.entityExists(id) then api.cmd.sendCommand(api.cmd.makeEntitySetNameCmd(id, name)) end
		end,
		reader = Reader.new(api),
		perf = perf,
		tr = type(_) == "function" and _ or nil,
		-- wall clock for the init line's "same load" test (bavr_game.lua firstOfLoad); called inside pcall
		realTime = (type(os) == "table" and type(os.time) == "function") and os.time or nil,
	}
end

local function doUpdate(state, dt)
	if env == nil then env = makeEnv() end
	Game.update(E, env, state, dt)
end

local function doEvent(state, id, name, param)
	if env == nil then env = makeEnv() end
	Game.handleEvent(E, env, state, id, name, param)
end

local function fail(where, e)
	if env ~= nil then
		Game.error(E, env, where, e)
	else
		pcall(function() log.message("[SQFN] error where=" .. where .. " err=" .. tostring(e)) end)
	end
end

function data()
	return {
		update = function(_userParams, state, dt)
			local ok, e = pcall(doUpdate, state, dt)
			if not ok then fail("update", e) end
		end,
		handleEvent = function(_userParams, state, _src, id, name, param)
			local ok, e = pcall(doEvent, state, id, name, param)
			if not ok then fail("handleEvent", e) end
		end,
	}
end

perf:phase("init", perfInit)
