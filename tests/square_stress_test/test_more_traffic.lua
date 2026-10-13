-- More car traffic (plans/square_stress_test/MORE_TRAFFIC.md, Phase 7a): the car_traffic / town_capacity
-- params, the town building script filter, the personCapacity patch rules, runFn's loadScript modifier
-- around the town building updateFn, and the Traffic tab's Scan with the DRIVE / WALK / LINES split.

local logic

before_each(function()
	reset_modules()
	clear_logs()
	logic = ug_require "square_stress_test::/stress/stress_logic.tl"
end)

local function logs(level, pattern)
	local out = {}
	for _, l in ipairs(log_entries()) do
		if (level == nil or l.level == level) and l.msg:find(pattern, 1, true) then out[#out + 1] = l.msg end
	end
	return out
end

---------------------------------------------------------------------------
-- params -> config

test("PARAM_KEYS lists the two new params", function()
	local set = {}
	for _, k in ipairs(logic.PARAM_KEYS) do set[k] = true end
	ok(set.car_traffic, "car_traffic")
	ok(set.town_capacity, "town_capacity")
end)

test("defaults (missing / index 1 / garbage) write nothing and need no modifier", function()
	for _, p in ipairs({ {}, { car_traffic = 1, town_capacity = 1 }, { car_traffic = 9, town_capacity = "x" } }) do
		local cfg = logic.configFromParams(p)
		eq(cfg.carTrafficMode, nil)
		eq(cfg.townCapacityFactor, 1.0)
		eq(logic.wantsTownBuildingPatch(cfg), false)
	end
	eq(logic.wantsTownBuildingPatch(nil), false)
	eq(logic.townBuildingConfigText(logic.configFromParams({})), "car_traffic=default town_capacity=x1")
end)

test("car_traffic and town_capacity map to their options", function()
	local cfg = logic.configFromParams({ car_traffic = 2 })
	eq(cfg.carTrafficMode.id, "drive_destinations")
	eq(cfg.carTrafficMode.landUses, { "COMMERCIAL", "INDUSTRIAL" })
	eq(cfg.carTrafficMode.disallow, { "WALK", "LINES" })
	eq(logic.wantsTownBuildingPatch(cfg), true)
	cfg = logic.configFromParams({ car_traffic = 3, town_capacity = 2 })
	eq(cfg.carTrafficMode.id, "drive_all")
	eq(cfg.carTrafficMode.landUses, { "RESIDENTIAL", "COMMERCIAL", "INDUSTRIAL" })
	eq(cfg.townCapacityFactor, 2.0)
	eq(logic.townBuildingConfigText(cfg), "car_traffic=drive_all town_capacity=x2")
	cfg = logic.configFromParams({ town_capacity = 3 })
	eq(cfg.townCapacityFactor, 4.0)
	eq(cfg.carTrafficMode, nil)
	eq(logic.wantsTownBuildingPatch(cfg), true)
	eq(logic.CAPACITY_FACTORS, { 1.0, 2.0, 4.0 })
	for _, m in ipairs(logic.CAR_TRAFFIC_MODES) do
		for _, d in ipairs(m.disallow) do ok(d ~= "DRIVE", m.id .. " disallows DRIVE") end
	end
end)

---------------------------------------------------------------------------
-- file name filter

test("isTownBuildingScript: town building scripts yes", function()
	for _, f in ipairs({
		"buildings/a/c1/1x1_01/a_com_l1_1x1_01.script.lua",
		"/buildings/a/c1/1x1_01/a_com_l1_1x1_01.script",
		"res/buildings/b/r2/2x2_01/b_res_l2_2x2_01.script.lua",
		"::/buildings/c/i1/1x2_01/c_ind_l1_1x2_01.script.lua",
		"C:\\Games\\TF3\\base\\content\\buildings\\a\\c1\\1x1_01\\a_com_l1_1x1_01.script.lua",
		"some_mod::/buildings/x/my_house.script.tl",
	}) do
		eq(logic.isTownBuildingScript(f), true, f)
	end
end)

test("isTownBuildingScript: industries, landmarks, .con.lua and other files no", function()
	for _, f in ipairs({
		"buildings/a/c1/1x1_01/a_com_l1_1x1_01.con.lua",
		"buildings/a/c1/1x1_01/a_com_l1_1x1_01.con",
		"industry/coal_mine.script.lua",
		"industries/industryutil.lua",
		"landmarks/eiffel_tower.script.lua",
		"construction/station/rail/train_station.script.lua",
		"assets/buildings_misc/thing.lua",
		"mybuildings/x.script.lua",
		"buildings/townbuildingutil.lua",
		"",
	}) do
		eq(logic.isTownBuildingScript(f), false, f)
	end
	eq(logic.isTownBuildingScript(nil), false)
	eq(logic.isTownBuildingScript(42), false)
end)

---------------------------------------------------------------------------
-- patch rules

local function townResult(landUse, capacity, extra)
	local pc = { type = landUse, capacity = capacity, personNodes = { { 1, 1 } } }
	for k, v in pairs(extra or {}) do pc[k] = v end
	return { townBuilding = { level = 1, width = 1, depth = 1 }, personCapacity = pc, rules = { { capacity = 3 } } }
end

local DEST = { car_traffic = 2 }
local ALL = { car_traffic = 3 }

test("patch: destinations variant only on commercial and industrial buildings", function()
	local cfg = logic.configFromParams(DEST)
	local com, ind, res = townResult("COMMERCIAL", 8), townResult("INDUSTRIAL", 8), townResult("RESIDENTIAL", 8)
	eq(logic.patchTownBuildingResult(com, cfg), true)
	eq(com.personCapacity.disallowedMoveModes, { "WALK", "LINES" })
	eq(logic.patchTownBuildingResult(ind, cfg), true)
	eq(ind.personCapacity.disallowedMoveModes, { "WALK", "LINES" })
	eq(logic.patchTownBuildingResult(res, cfg), false)
	eq(res.personCapacity.disallowedMoveModes, nil)
	eq(com.personCapacity.capacity, 8)       -- capacity untouched at x1
	eq(com.rules, { { capacity = 3 } })      -- cargo rules never touched
end)

test("patch: all variant includes residential buildings", function()
	local res = townResult("RESIDENTIAL", 8)
	eq(logic.patchTownBuildingResult(res, logic.configFromParams(ALL)), true)
	eq(res.personCapacity.disallowedMoveModes, { "WALK", "LINES" })
end)

test("patch: existing disallowed modes are kept, no duplicates, DRIVE never added", function()
	local r = townResult("COMMERCIAL", 8, { disallowedMoveModes = { "LINES", "DRIVE" } })
	eq(logic.patchTownBuildingResult(r, logic.configFromParams(DEST)), true)
	eq(r.personCapacity.disallowedMoveModes, { "LINES", "DRIVE", "WALK" })
	-- already complete: nothing to change
	local done = townResult("COMMERCIAL", 8, { disallowedMoveModes = { "WALK", "LINES" } })
	eq(logic.patchTownBuildingResult(done, logic.configFromParams(DEST)), false)
	eq(done.personCapacity.disallowedMoveModes, { "WALK", "LINES" })
	-- a mode that somehow lists DRIVE still never adds it
	local cfg = logic.configFromParams(DEST)
	cfg.carTrafficMode = { id = "bad", landUses = { "COMMERCIAL" }, disallow = { "DRIVE", "WALK" } }
	local r2 = townResult("COMMERCIAL", 8)
	eq(logic.patchTownBuildingResult(r2, cfg), true)
	eq(r2.personCapacity.disallowedMoveModes, { "WALK" })
end)

test("patch: capacity multiplied and rounded; zero, missing and x1 capacities untouched", function()
	local cfg2 = logic.configFromParams({ town_capacity = 2 })
	local cfg4 = logic.configFromParams({ town_capacity = 3 })
	local r = townResult("RESIDENTIAL", 7)
	eq(logic.patchTownBuildingResult(r, cfg4), true)
	eq(r.personCapacity.capacity, 28)
	eq(r.personCapacity.disallowedMoveModes, nil) -- car traffic default: modes untouched
	local frac = townResult("RESIDENTIAL", 2.6)
	logic.patchTownBuildingResult(frac, cfg2)
	eq(frac.personCapacity.capacity, 5)            -- 5.2 -> 5
	local half = townResult("RESIDENTIAL", 1.25)
	logic.patchTownBuildingResult(half, cfg2)
	eq(half.personCapacity.capacity, 3)            -- 2.5 -> 3
	local zero = townResult("RESIDENTIAL", 0)
	eq(logic.patchTownBuildingResult(zero, cfg4), false)
	eq(zero.personCapacity.capacity, 0)
	local none = townResult("RESIDENTIAL", nil)
	eq(logic.patchTownBuildingResult(none, cfg4), false)
	eq(none.personCapacity.capacity, nil)
	local x1 = townResult("RESIDENTIAL", 7)
	eq(logic.patchTownBuildingResult(x1, logic.configFromParams({})), false)
	eq(x1.personCapacity, townResult("RESIDENTIAL", 7).personCapacity)
end)

test("patch: both options together", function()
	local r = townResult("INDUSTRIAL", 10)
	eq(logic.patchTownBuildingResult(r, logic.configFromParams({ car_traffic = 2, town_capacity = 2 })), true)
	eq(r.personCapacity.capacity, 20)
	eq(r.personCapacity.disallowedMoveModes, { "WALK", "LINES" })
end)

test("patch: non-town-building results untouched; nil-safe", function()
	local cfg = logic.configFromParams({ car_traffic = 3, town_capacity = 3 })
	-- industry-like: personCapacity but no townBuilding
	local industry = { personCapacity = { type = "INDUSTRIAL", capacity = 10, disallowedMoveModes = { "WALK", "DRIVE" } } }
	eq(logic.patchTownBuildingResult(industry, cfg), false)
	eq(industry.personCapacity, { type = "INDUSTRIAL", capacity = 10, disallowedMoveModes = { "WALK", "DRIVE" } })
	-- townBuilding without personCapacity
	local bare = { townBuilding = {} }
	eq(logic.patchTownBuildingResult(bare, cfg), false)
	eq(bare, { townBuilding = {} })
	-- a type that isn't a land use string: capacity still scaled, modes untouched
	local odd = townResult(2, 5)
	eq(logic.patchTownBuildingResult(odd, cfg), true)
	eq(odd.personCapacity.disallowedMoveModes, nil)
	eq(odd.personCapacity.capacity, 20)
	eq(logic.patchTownBuildingResult(nil, cfg), false)
	eq(logic.patchTownBuildingResult(townResult("RESIDENTIAL", 5), nil), false)
	eq(logic.patchTownBuildingResult("x", cfg), false)
	eq(logic.patchTownBuildingResult({ townBuilding = {}, personCapacity = "x" }, cfg), false)
end)

test("townBuildingPatchLine names the file, type, modes and capacity change", function()
	local r = townResult("COMMERCIAL", 8)
	logic.patchTownBuildingResult(r, logic.configFromParams({ car_traffic = 2, town_capacity = 3 }))
	eq(logic.townBuildingPatchLine("buildings/a/x.script.lua", r, 8, 120, 130),
		"[SQST] town_building_patch first=buildings/a/x.script.lua type=COMMERCIAL modes=WALK,LINES capacity=8->32 wrapped=120 seen=130")
	eq(logic.townBuildingPatchLine("f", townResult("RESIDENTIAL", 4), 2, nil, nil),
		"[SQST] town_building_patch first=f type=RESIDENTIAL modes=- capacity=2->4 wrapped=0 seen=0")
	ok(logic.townBuildingPatchLine("f", nil, nil, 1, 1):find("type=nil modes=- capacity=nil->nil", 1, true))
end)

---------------------------------------------------------------------------
-- runFn: the loadScript modifier

local mods, modifiers

local function loadModScript()
	modifiers = {}
	set_global("addModifier", function(kind, fn) modifiers[#modifiers + 1] = { kind = kind, fn = fn } end)
	mods = ug_require "square_stress_test::/mod.script.tl"
end

local function scriptData(landUse, capacity)
	local calls = 0
	local data = {}
	data.updateFn = function(captureParams, params)
		calls = calls + 1
		return townResult(landUse, params and params.capacity or capacity)
	end
	return data, function() return calls end
end

local function loadScriptMods()
	local out = {}
	for _, m in ipairs(modifiers) do if m.kind == "loadScript" then out[#out + 1] = m end end
	return out
end

local function applyAll(fileName, data)
	for _, m in ipairs(loadScriptMods()) do data = m.fn(fileName, data) end
	return data
end

test("runFn: default params register no loadScript modifier and log nothing", function()
	loadModScript()
	mods.runFn({}, {}, { square_stress_test = { car_traffic = 1, town_capacity = 1 } })
	mods.runFn({}, {}, {})
	mods.runFn({}, {}, nil)
	eq(#loadScriptMods(), 0)
	eq(#logs(nil, "[SQST]"), 0)
end)

test("runFn: car_traffic registers the modifier on every call and logs the config line", function()
	loadModScript()
	mods.runFn({}, {}, { square_stress_test = { car_traffic = 2 } })
	eq(#loadScriptMods(), 1)
	eq(logs("message", "[SQST] config"), { "[SQST] config car_traffic=drive_destinations town_capacity=x1 wrapped=0 first=-" })
	mods.runFn({}, {}, { square_stress_test = { town_capacity = 3 } })
	eq(#loadScriptMods(), 2) -- no register-once guard
end)

test("modifier: wraps town building scripts; the result is patched, everything else passes through", function()
	loadModScript()
	mods.runFn({}, {}, { square_stress_test = { car_traffic = 2, town_capacity = 2 } })
	local data, calls = scriptData("COMMERCIAL", 5)
	local orig = data.updateFn
	local out = applyAll("buildings/a/c1/1x1_01/a_com_l1_1x1_01.script.lua", data)
	ok(out == data, "same data table returned")
	ok(out.updateFn ~= orig, "updateFn wrapped")
	local result = out.updateFn({}, { capacity = 6 })
	eq(calls(), 1)
	eq(result.personCapacity.capacity, 12)
	eq(result.personCapacity.disallowedMoveModes, { "WALK", "LINES" })
	-- residential: capacity only (destinations variant)
	local rdata = applyAll("buildings/a/r1/1x1_01/a_res_l1_1x1_01.script.lua", scriptData("RESIDENTIAL", 3))
	local rr = rdata.updateFn({}, { capacity = 3 })
	eq(rr.personCapacity.capacity, 6)
	eq(rr.personCapacity.disallowedMoveModes, nil)
	-- not a town building script: untouched
	local idata, _ = scriptData("INDUSTRIAL", 5)
	local iorig = idata.updateFn
	eq(applyAll("industry/coal_mine.script.lua", idata).updateFn, iorig)
	-- no updateFn / not a table: passed through
	local plain = { other = 1 }
	eq(applyAll("buildings/a/x.script.lua", plain), { other = 1 })
	eq(applyAll("buildings/a/x.script.lua", nil), nil)
	local nested = { townbuilding = { updateFn = function() end } }
	local nfn = nested.townbuilding.updateFn
	eq(applyAll("buildings/transformator_townbuilding.script.tl", nested).townbuilding.updateFn, nfn)
end)

test("modifier: idempotent when registered twice in the same Lua state (patched once)", function()
	loadModScript()
	mods.runFn({}, {}, { square_stress_test = { town_capacity = 3 } })
	mods.runFn({}, {}, { square_stress_test = { town_capacity = 3 } })
	eq(#loadScriptMods(), 2)
	local data = applyAll("buildings/a/x.script.lua", scriptData("RESIDENTIAL", 5))
	eq(data.updateFn({}, { capacity = 5 }).personCapacity.capacity, 20) -- x4, not x16
end)

test("modifier: one wrap line after 3 scripts, one skip line, one patch line per Lua state", function()
	loadModScript()
	mods.runFn({}, {}, { square_stress_test = { car_traffic = 3 } })
	local wrapped = {}
	for i = 1, 5 do
		wrapped[i] = applyAll(string.format("buildings/a/r1/b%d.script.lua", i), scriptData("RESIDENTIAL", 4))
	end
	applyAll("industry/a.script.lua", scriptData("INDUSTRIAL", 4))
	applyAll("industry/b.script.lua", scriptData("INDUSTRIAL", 4))
	eq(logs("message", "town_building_wrap"),
		{ "[SQST] town_building_wrap wrapped=3 seen=3 first=buildings/a/r1/b1.script.lua,buildings/a/r1/b2.script.lua,buildings/a/r1/b3.script.lua" })
	eq(logs("message", "town_building_skip"),
		{ "[SQST] town_building_skip first=industry/a.script.lua (has updateFn, not a town building script)" })
	for i = 1, 5 do wrapped[i].updateFn({}, { capacity = 4 }) end
	eq(logs("message", "town_building_patch"),
		{ "[SQST] town_building_patch first=buildings/a/r1/b1.script.lua type=RESIDENTIAL modes=WALK,LINES capacity=4->4 wrapped=5 seen=7" })
	-- the next load (runFn again) resets the counters; the config line shows what this state had wrapped
	mods.runFn({}, {}, { square_stress_test = { car_traffic = 3 } })
	ok(logs("message", "[SQST] config")[2]:find("wrapped=5 first=buildings/a/r1/b1.script.lua,", 1, true), logs("message", "[SQST] config")[2])
end)

test("wrapper: a patch failure logs one warning and returns the result; the original's errors stay", function()
	loadModScript()
	mods.runFn({}, {}, { square_stress_test = { town_capacity = 2 } })
	local data = { updateFn = function(_c, params)
		if params.boom then error("orig failed") end
		-- capacity is a table: the patch's arithmetic fails
		return { townBuilding = {}, personCapacity = setmetatable({ type = "RESIDENTIAL" }, {
			__index = function(_, k) if k == "capacity" then error("bad capacity read") end end }) }
	end }
	data = applyAll("buildings/a/x.script.lua", data)
	local r1 = data.updateFn({}, {})
	ok(r1 ~= nil and r1.townBuilding ~= nil, "result returned")
	data.updateFn({}, {})
	eq(#logs("warning", "town_building_patch failed"), 1)
	raises(function() data.updateFn({}, { boom = true }) end, "orig failed")
end)

---------------------------------------------------------------------------
-- readout: move-mode split

test("moveSplitText / moveSplitLog / trafficReadout with the split", function()
	local split = { drive = 79, walk = 614, lines = 0 }
	eq(logic.moveSplitText(split), "DRIVE 79 (11%) / WALK 614 (89%) / LINES 0 (0%)")
	eq(logic.moveSplitText({ drive = 0, walk = 0, lines = 0 }), "DRIVE 0 / WALK 0 / LINES 0")
	eq(logic.moveSplitText({ drive = 1500, walk = 500, lines = 0 }), "DRIVE 1.5k (75%) / WALK 500 (25%) / LINES 0 (0%)")
	eq(logic.moveSplitText(nil), nil)
	eq(logic.moveSplitLog(split), "modes=DRIVE:79,WALK:614,LINES:0")
	eq(logic.moveSplitLog(nil), "modes=-")
	eq(logic.trafficReadout(3, 10, 700, 0, 63, split),
		"Lines 3   Vehicles 10   Sim persons 700   Driving now 63\nLast trip mode: DRIVE 79 (11%) / WALK 614 (89%) / LINES 0 (0%)")
	eq(logic.trafficReadout(3, 10, 700, 0, 63), "Lines 3   Vehicles 10   Sim persons 700   Driving now 63")
	eq(logic.trafficReadout(nil, nil, nil, nil, nil, { drive = 1, walk = 1, lines = 2 }),
		"Last trip mode: DRIVE 1 (25%) / WALK 1 (25%) / LINES 2 (50%)")
end)

---------------------------------------------------------------------------
-- Traffic tab Scan (stress_traffic.tl, fake api as in test_clear_traffic.lua)

local T = 0
local FRAME_US = 16667
local sent, persons, order

local CT = {
	SIM_PERSON = "SIM_PERSON", MOVE_PATH = "MOVE_PATH", SIM_PERSON_AT_VEHICLE = "SIM_PERSON_AT_VEHICLE",
	SIM_ENTITY_AT_VEHICLE = "SIM_ENTITY_AT_VEHICLE", TRANSPORT_VEHICLE = "TRANSPORT_VEHICLE",
}

local function fakeApi()
	return {
		type = {
			Clock = { new = function() return { getTime = function() return T end } end },
			ComponentType = CT,
			enum = { MoveMode = { WALK = 0, DRIVE = 1, LINES = 2 } },
		},
		cmd = {
			sendCommand = function(cmd, cb) sent[#sent + 1] = { cmd = cmd, cb = cb } end,
			debug = { makeSimPersonSetStateCmd = function(e, state) return { e = e, state = state } end },
		},
		engine = {
			getEntitiesWithComponent = function(ct)
				if ct == CT.SIM_PERSON then
					local out = {}
					for i, e in ipairs(order) do out[i] = e end
					return out
				end
				if ct == CT.TRANSPORT_VEHICLE then return {} end
				error("Cannot loop over this component type")
			end,
			getComponent = function(e, ct)
				local p = persons[e]
				if p == nil then return nil end
				if ct == CT.SIM_PERSON then return { lastMoveMode = p.mode } end
				if ct == CT.MOVE_PATH then return p.path and {} or nil end
				return nil
			end,
			entityExists = function(e) return persons[e] ~= nil end,
			util = { getPlayer = function() return 7 end },
			system = {
				lineSystem = { getLinesForPlayer = function() return {} end },
				simPersonSystem = { getCount = function() return #order end },
			},
		},
	}
end

local function setupTraffic()
	T, sent, persons, order = 0, {}, {}, {}
	set_global("api", fakeApi())
	local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl"
	rt.notificationsSent = true
	local traffic = ug_require "square_stress_test::/stress/gui/stress_traffic.tl"
	local lines = {}
	local log0 = rt.log
	rt.log = function(msg)
		lines[#lines + 1] = msg
		log0(msg)
	end
	local function frames(n)
		for _ = 1, n do
			T = T + FRAME_US
			rt.tick()
		end
	end
	return rt, traffic, lines, frames
end

local function addPerson(e, mode, path)
	persons[e] = { mode = mode, path = path }
	order[#order + 1] = e
end

test("Scan counts drivers and the move-mode split, sends nothing, logs one traffic_scan line", function()
	local rt, traffic, lines, frames = setupTraffic()
	addPerson(1, 1, true)   -- driving
	addPerson(2, 1, false)  -- DRIVE, at home
	addPerson(3, 0, true)   -- walking
	addPerson(4, 0, false)
	addPerson(5, 2, true)   -- lines
	addPerson(6, 9, true)   -- unknown mode: not counted
	ok(not traffic.readout():find("Last trip", 1, true), traffic.readout())
	traffic.scan()
	frames(4)
	eq(#sent, 0)
	eq(traffic.driving, 1)
	eq(traffic.modes, { drive = 2, walk = 2, lines = 1 })
	eq(#rt.queue.jobs, 0)
	local text = table.concat(lines, "\n")
	ok(text:find("[SQST] traffic_scan scanned=6 drivers=1 sent=0 ok=0 ms=", 1, true), text)
	ok(text:find("modes=DRIVE:2,WALK:2,LINES:1", 1, true), text)
	ok(traffic.readout():find("Driving now 1\nLast trip mode: DRIVE 2 (40%) / WALK 2 (40%) / LINES 1 (20%)", 1, true),
		traffic.readout())
end)

test("Scan ignores Where, and Clear traffic also records the split", function()
	local _rt, traffic, lines, frames = setupTraffic()
	traffic.ui.clearWhere = 2
	addPerson(1, 1, true)
	addPerson(2, 0, true)
	traffic.scan()
	frames(3)
	ok(not table.concat(lines, "\n"):find("where=", 1, true), table.concat(lines, "\n"))
	traffic.ui.clearWhere = 1
	addPerson(3, 1, true)
	traffic.clearTraffic()
	frames(3)
	eq(#sent, 2)
	for _, s in ipairs(sent) do s.cb(s.cmd, true) end
	frames(1)
	eq(traffic.modes, { drive = 2, walk = 1, lines = 0 })
	ok(table.concat(lines, "\n"):find("clear_traffic scanned=3 drivers=2 sent=2 ok=2 ms=%d+ modes=DRIVE:2,WALK:1,LINES:0"),
		table.concat(lines, "\n"))
end)

test("Scan refuses while a cycle runs", function()
	local _rt, traffic, lines, frames = setupTraffic()
	for e = 1, 12000 do addPerson(e, 0, false) end
	traffic.scan()
	frames(1)
	traffic.scan()
	ok(table.concat(lines, "\n"):find("traffic_scan: a scan or clear is still running", 1, true), table.concat(lines, "\n"))
	frames(4)
	eq(traffic.modes, { drive = 0, walk = 12000, lines = 0 })
end)
