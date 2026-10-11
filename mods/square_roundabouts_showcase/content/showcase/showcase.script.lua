-- DEV ONLY (never upload): Roundabouts Showcase, game-script functions (registered by showcase.gs.lua).
-- Everything runs in guiUpdate on the GUI thread; the engine-thread update is a no-op and the script
-- keeps no game-script state, so nothing is written to the savegame except what Build mode builds.
--
-- Flow: on the first guiUpdate read the mod params (sc_config.lua). If "Run" is On, wait
-- "Start delay" seconds, resolve the entries and read their params (sc_engine.lua), then one runner
-- step per guiUpdate (sc_runner.lua): enumerate, measure, layout, plan + preview, build (Build mode
-- only), summary. Runs once per game load.
--
-- Exports through data(): a .script.lua that returns a table fails in game with
-- "Expected table at path".

local MOD = "square_roundabouts_showcase::/showcase/"
local config = ug_require(MOD .. "sc_config.lua")
local runnerMod = ug_require(MOD .. "sc_runner.lua")
local engineMod = ug_require(MOD .. "sc_engine.lua")

-- GUI-thread module state (not game-script state): one run per Lua state, i.e. per game load.
local S = { phase = "init", updates = 0 }

local function out(line)
	if log and log.message then log.message(line) else print(line) end
end

local function now()
	local ok, t = pcall(os.time)
	if ok and type(t) == "number" then return t end
	return S.updates / 30 -- assumption: about 30 GUI updates per second
end

local function begin()
	local okP, all = pcall(api.engine.config.getModParams)
	local raw = okP and type(all) == "table" and all[config.MOD_ID] or nil
	local cfg = config.fromModParams(raw)
	S.cfg = cfg
	if not cfg.run then
		out(config.PREFIX .. " INFO disabled (mod setting 'Run' is Off)")
		S.phase = "done"
		return
	end
	local editor = okP and type(all) == "table" and type(all[""]) == "table" and all[""].isMapEditor == true
	out(runnerMod.line("START", { { "settings", config.describe(cfg) }, { "mapEditor", editor },
		{ "startsIn", cfg.delay } }))
	S.t0 = now()
	S.phase = "wait"
end

local function launch()
	local eng = engineMod.new(S.cfg, out)
	local entries = eng:setup()
	if #entries == 0 then
		out(config.PREFIX .. " ERROR no construction found; stopping")
		S.phase = "done"
		return
	end
	local cx, cy = eng:centre()
	S.runner = runnerMod.new({
		cfg = S.cfg,
		entries = entries,
		centre = { cx, cy },
		deps = {
			log = out,
			now = now,
			measure = function(combo) return eng:measure(combo) end,
			check = function(p) return eng:check(p) end,
			send = function(p, done) return eng:send(p, done) end,
			clock = function()
				local ok, t = pcall(os.clock)
				if ok and type(t) == "number" then return t end
				return now()
			end,
		},
	})
	S.phase = "run"
end

local function body()
	S.updates = S.updates + 1
	if S.phase == "init" then begin() return end
	if S.phase == "wait" then
		if now() - S.t0 < S.cfg.delay then return end
		launch()
		return
	end
	if S.phase == "run" and S.runner:step() then S.phase = "done" end
end

function data()
return {
	update = function(_userParams, _state, _dt) end,
	guiUpdate = function(_userParams, _state, _guiState)
		if S.phase == "done" then return end
		local ok, err = pcall(body)
		if not ok then
			out(config.PREFIX .. " ERROR showcase stopped: " .. runnerMod.clean(err))
			S.phase = "done"
		end
	end,
}
end
