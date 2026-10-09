-- DEV ONLY (never upload): Roundabouts placement probe, game-script functions.
-- Registered by probe.gs.lua. Everything runs in guiUpdate on the GUI thread (the thread the
-- one known makeProposalData caller uses: a construction tool, overpass_probe.script.tl:3748).
-- The engine-thread update is a no-op; the script keeps no game-script state, so nothing is
-- written to the savegame.
--
-- Flow: on the first guiUpdate read the mod params (probe_config.lua). If "Run the probe" is On,
-- wait "Start delay" seconds, then expand the chosen subset (probe_grid.lua) and evaluate
-- "Combos per update" combos per guiUpdate (probe_runner.lua + probe_engine.lua), logging one
-- [SQRB_PROBE] line per combo to stdout.txt. Runs once per game load. Search subsets (Phase 4)
-- first check that the sqrb_dev_* overrides reach the engine (engine:devCheck), then ask about
-- one candidate per engine call (probe_runner.lua, T and S lines).
--
-- Exports through data(): a .script.lua that returns a table fails in game with
-- "Expected table at path".

local MOD = "square_roundabouts_probe::/probe/"
local grid = ug_require(MOD .. "probe_grid.lua")
local config = ug_require(MOD .. "probe_config.lua")
local runnerMod = ug_require(MOD .. "probe_runner.lua")
local engineMod = ug_require(MOD .. "probe_engine.lua")

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

local function clock()
	local ok, t = pcall(os.clock)
	if ok and type(t) == "number" then return t end
	return nil
end

local function readModParams()
	local ok, all = pcall(api.engine.config.getModParams)
	if ok and type(all) == "table" then return all[config.MOD_ID], all end
	return nil, nil
end

local function isMapEditor(all)
	local g = all and all[""]
	return type(g) == "table" and g.isMapEditor == true
end

local function begin()
	local raw, all = readModParams()
	local cfg = config.fromModParams(raw)
	S.cfg = cfg
	if not cfg.run then
		out(grid.PREFIX .. " INFO disabled (mod setting 'Run the probe' is Off)")
		S.phase = "done"
		return
	end
	out(grid.PREFIX .. " INFO DEV ONLY probe loaded: " .. config.describe(cfg) ..
		(isMapEditor(all) and " (map editor)" or "") .. "; starting in " .. cfg.delay .. " s")
	S.t0 = now()
	S.phase = "wait"
end

local function launch()
	local cfg = S.cfg
	local eng = engineMod.new(cfg, out)
	if not eng:setup() then
		out(grid.PREFIX .. " ERROR nothing to probe; stopping")
		S.phase = "done"
		return
	end
	local okExpand, combos = pcall(grid.expand, cfg.subset)
	if not okExpand then
		out(grid.PREFIX .. " ERROR bad subset '" .. tostring(cfg.subset) .. "': " .. grid.clean(combos))
		S.phase = "done"
		return
	end
	local searching = false
	for _, c in ipairs(combos) do
		if c.search then searching = true break end
	end
	if searching and not eng:devCheck() then
		S.phase = "done"
		return
	end
	S.runner = runnerMod.new({
		combos = combos,
		subset = cfg.subset,
		header = eng:header(),
		logOk = cfg.logOk,
		progressEvery = config.PROGRESS_EVERY,
		deps = {
			evaluate = function(combo) return eng:evaluate(combo) end,
			log = out,
			now = now,
			clock = clock,
			collect = function() collectgarbage("collect") end,
			skip = function(job) return eng:skip(job) end,
			ship = function(job) return eng:ship(job) end,
		},
	})
	S.phase = "run"
end

local function body()
	S.updates = S.updates + 1
	if S.phase == "done" then return end
	if S.phase == "init" then begin() return end
	if S.phase == "wait" then
		if now() - S.t0 < S.cfg.delay then return end
		launch()
		return
	end
	if S.phase == "run" and S.runner:step(S.cfg.batch) then
		S.phase = "done"
	end
end

function data()
return {
	update = function(_userParams, _state, _dt) end,
	guiUpdate = function(_userParams, _state, _guiState)
		if S.phase == "done" then return end
		local ok, err = pcall(body)
		if not ok then
			out(grid.PREFIX .. " ERROR probe stopped: " .. grid.clean(err))
			S.phase = "done"
		end
	end,
}
end
