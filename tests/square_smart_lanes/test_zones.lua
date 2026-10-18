-- square_smart_lanes: sl_zones.lua pure helpers (the wiring is in test_script.lua / test_tool.lua "zones").

local Zones = ug_require "square_smart_lanes::/smart_lanes/sl_zones.lua"

test("abAt: inside / outside / on the rim; overlapping zones: the nearest centre relative to its radius", function()
	local list = { { x = 0, y = 0, r = 100, ab = "game" }, { x = 150, y = 0, r = 100, ab = "sl" } }
	eq(Zones.abAt(list, 10, 0), "game")
	eq(Zones.abAt(list, 140, 0), "sl")
	eq(Zones.abAt(list, 100, 0), "sl", "both: 100/100 vs 50/100")
	eq(Zones.abAt(list, 0, 100), "game", "on the rim")
	eq(Zones.abAt(list, 0, 101), nil)
	eq(Zones.abAt(list, 1000, 1000), nil)
end)

test("abAt / nodeAb: nil-safe (no list, no point, broken entries, missing node)", function()
	eq(Zones.abAt(nil, 0, 0), nil)
	eq(Zones.abAt({}, 0, 0), nil)
	eq(Zones.abAt({ { x = 0, y = 0, r = 10, ab = "game" } }, nil, 0), nil)
	eq(Zones.abAt({ "x", { x = 0 }, { x = 0, y = 0, r = 0, ab = "game" }, { x = 0, y = 0, r = 5, ab = "sl" } }, 1, 1), "sl")
	local world = { node = function(n) return n == 1 and { x = 0, y = 0 } or nil end }
	local list = { { x = 0, y = 0, r = 10, ab = "sl_phases" } }
	eq(Zones.nodeAb(list, world, 1), "sl_phases")
	eq(Zones.nodeAb(list, world, 2), nil)
	eq(Zones.nodeAb(nil, world, 1), nil)
	eq(Zones.nodeAb({}, world, 1), nil)
end)

test("validate: cleaned copies (extra keys dropped), fixed by_ab order", function()
	local op, list, run = Zones.validate({ op = "set", run = "s12.3-x_y", zones = { { x = 1, y = 2, r = 3, ab = "sl_phases", junk = "x" } }, junk = 1 })
	eq(op, "set")
	eq(run, "s12.3-x_y")
	eq(list, { { x = 1, y = 2, r = 3, ab = "sl_phases" } })
	eq(Zones.byAbText(list), "game:0,sl:0,sl_phases:1")
	eq(Zones.byAbText(nil), "game:0,sl:0,sl_phases:0")
	eq({ Zones.validate({ op = "clear" }) }, { "clear", {}, "-" })
	eq({ Zones.validate(nil) }, { nil, "not_table" })
end)

test("readSaved: nil when the game script cannot be read; never throws", function()
	eq(Zones.readSaved({}), nil)
	local api = { type = { ComponentType = { GAME_SCRIPT = "GS" } }, engine = {
		system = { gameScriptSystem = { getEntityForGameScript = function() return -1 end } },
		getComponent = function() error("must not be called") end } }
	eq(Zones.readSaved(api), nil)
	api.engine.system.gameScriptSystem.getEntityForGameScript = function() return 5 end
	api.engine.getComponent = function() return { state_native = { find = function() return nil end } } end
	eq(Zones.readSaved(api), {}, "no zones saved")
	api.engine.getComponent = function() return { state_native = { find = function() error("native") end }, state = { zones = { 1 } } } end
	eq(Zones.readSaved(api), { 1 }, "the state copy when state_native fails")
end)

test("validate: optional id / pair labels kept when well-formed, dropped (not the zone) otherwise", function()
	local op, list = Zones.validate({ op = "set", run = "r1", zones = {
		{ x = 1, y = 2, r = 3, ab = "sl", id = "g3a", pair = "g3" },
		{ x = 4, y = 5, r = 6, ab = "game", id = "g3 b", pair = string.rep("p", 13) },
		{ x = 7, y = 8, r = 9, ab = "sl_phases", id = 12, pair = "" },
		{ x = 1, y = 1, r = 1, ab = "game" } } })
	eq(op, "set")
	eq(list[1], { x = 1, y = 2, r = 3, ab = "sl", id = "g3a", pair = "g3" })
	eq(list[2], { x = 4, y = 5, r = 6, ab = "game" }, "space in id, pair too long")
	eq(list[3], { x = 7, y = 8, r = 9, ab = "sl_phases" }, "number id, empty pair")
	eq(list[4], { x = 1, y = 1, r = 1, ab = "game" }, "an old payload without labels stays valid")
	eq(Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl", id = string.rep("a", 12) } } }) ~= nil, true)
	local _, l2 = Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl", id = string.rep("a", 12) } } })
	eq(l2[1].id, string.rep("a", 12), "12 characters is the limit")
end)

test("validate: sl_fan accepted (fan mode); old payloads (game / sl / sl_phases) unchanged; by_ab adds sl_fan only when present", function()
	local op, list = Zones.validate({ op = "set", run = "f1", zones = {
		{ x = 1, y = 2, r = 3, ab = "sl_fan", id = "g4c", pair = "g4" },
		{ x = 4, y = 5, r = 6, ab = "sl_phases" } } })
	eq(op, "set")
	eq(list[1], { x = 1, y = 2, r = 3, ab = "sl_fan", id = "g4c", pair = "g4" })
	eq(Zones.byAbText(list), "game:0,sl:0,sl_phases:1,sl_fan:1")
	eq(Zones.abAt(list, 1, 2), "sl_fan")
	-- an old payload: the same list and the same by_ab text as before fan mode
	local _, old = Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "game" }, { x = 9, y = 9, r = 3, ab = "sl" },
		{ x = 20, y = 20, r = 3, ab = "sl_phases" } } })
	eq(#old, 3)
	eq(Zones.byAbText(old), "game:1,sl:1,sl_phases:1")
	-- still no free-form modes
	eq({ Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl_fans" } } }) }, { nil, "ab1" })
	eq({ Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "fan" } } }) }, { nil, "ab1" })
end)

test("validate: sl_lock accepted (free kerb turn locked); by_ab adds sl_lock only when present, after sl_fan", function()
	local op, list = Zones.validate({ op = "set", run = "k1", zones = {
		{ x = 1, y = 2, r = 3, ab = "sl_lock", id = "g4e", pair = "g4" },
		{ x = 4, y = 5, r = 6, ab = "sl" } } })
	eq(op, "set")
	eq(list[1], { x = 1, y = 2, r = 3, ab = "sl_lock", id = "g4e", pair = "g4" })
	eq(Zones.byAbText(list), "game:0,sl:1,sl_phases:0,sl_lock:1")
	eq(Zones.abAt(list, 1, 2), "sl_lock")
	local _, both = Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl_lock" }, { x = 9, y = 9, r = 3, ab = "sl_fan" },
		{ x = 20, y = 20, r = 3, ab = "game" } } })
	eq(Zones.byAbText(both), "game:1,sl:0,sl_phases:0,sl_fan:1,sl_lock:1")
	eq({ Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl_locked" } } }) }, { nil, "ab1" })
end)

test("validate: sl_exitfan accepted (exit-lane fan); by_ab adds sl_exitfan only when present, after sl_lock", function()
	local op, list = Zones.validate({ op = "set", run = "r1", zones = {
		{ x = 1, y = 2, r = 3, ab = "sl_exitfan", id = "g5f", pair = "g5" },
		{ x = 9, y = 9, r = 3, ab = "sl" } } })
	eq(op, "set")
	eq(list[1], { x = 1, y = 2, r = 3, ab = "sl_exitfan", id = "g5f", pair = "g5" })
	eq(Zones.byAbText(list), "game:0,sl:1,sl_phases:0,sl_exitfan:1")
	eq(Zones.abAt(list, 1, 2), "sl_exitfan")
	local _, all = Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl_exitfan" }, { x = 9, y = 9, r = 3, ab = "sl_lock" },
		{ x = 20, y = 20, r = 3, ab = "sl_fan" }, { x = 30, y = 30, r = 3, ab = "game" } } })
	eq(Zones.byAbText(all), "game:1,sl:0,sl_phases:0,sl_fan:1,sl_lock:1,sl_exitfan:1")
	eq({ Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl_exit_fan" } } }) }, { nil, "ab1" })
	-- older payloads: the line stays as before
	local _, old = Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl" } } })
	eq(Zones.byAbText(old), "game:0,sl:1,sl_phases:0")
end)

test("world.exitFan: a list frozen into the world (the automatic pass's job zones) wins over W.zones", function()
	local Write = ug_require "square_smart_lanes::/smart_lanes/sl_write.lua"
	local CT = { BASE_NODE = "BN", BASE_EDGE = "BE", BASE_NODE_CONFIG = "BNC" }
	local api = {
		type = { ComponentType = CT, enum = {} },
		engine = {
			getComponent = function(e, ct)
				if ct == CT.BASE_NODE and e == 7 then return { position = { x = 10, y = 20, z = 0 } } end
				return nil
			end,
			system = { streetSystem = { getNodeStreetSegments = function() return {} end } },
		},
	}
	local W = Write.new(api, function() end)
	local fan = { { x = 10, y = 20, r = 50, ab = "sl_exitfan" } }
	local sl = { { x = 10, y = 20, r = 50, ab = "sl" } }
	eq(W.makeWorld().exitFan(7), false, "no zones")
	W.zones = fan
	local live = W.makeWorld()
	eq(live.exitFan(7), true, "W.zones")
	eq(live.exitFan(8), false, "no node")
	local frozen = W.makeWorld()
	frozen.zones = fan
	W.zones = sl -- the mirror changes mid-job
	eq(frozen.exitFan(7), true, "the job's zones stay")
	eq(live.exitFan(7), false, "an unfrozen world reads W.zones at the call")
	local none = W.makeWorld()
	none.zones = {}
	W.zones = fan
	eq(none.exitFan(7), false, "a job without zones stays without")
end)

test("validate: sl_keeplights accepted (SL-1); by_ab adds sl_keeplights only when present, after sl_exitfan", function()
	local op, list = Zones.validate({ op = "set", run = "b1", zones = {
		{ x = 1, y = 2, r = 3, ab = "sl_keeplights", id = "g1f", pair = "g1" }, { x = 9, y = 9, r = 3, ab = "sl" } } })
	eq(op, "set")
	eq(list[1], { x = 1, y = 2, r = 3, ab = "sl_keeplights", id = "g1f", pair = "g1" })
	eq(Zones.byAbText(list), "game:0,sl:1,sl_phases:0,sl_keeplights:1")
	local _, all = Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl_keeplights" }, { x = 9, y = 9, r = 3, ab = "sl_exitfan" },
		{ x = 20, y = 20, r = 3, ab = "sl_lock" }, { x = 30, y = 30, r = 3, ab = "sl_fan" }, { x = 40, y = 40, r = 3, ab = "game" } } })
	eq(Zones.byAbText(all), "game:1,sl:0,sl_phases:0,sl_fan:1,sl_lock:1,sl_exitfan:1,sl_keeplights:1")
	eq({ table.unpack(Zones.AB, 1, 7) }, { "game", "sl", "sl_phases", "sl_fan", "sl_lock", "sl_exitfan", "sl_keeplights" })
end)

test("zoneAt / idOf (SL-3): the zone record a point lies in and its id label", function()
	local list = { { x = 0, y = 0, r = 10, ab = "sl", id = "g1b" }, { x = 5, y = 0, r = 10, ab = "game" }, { x = 100, y = 0, r = 5, ab = "sl", id = "bad id" } }
	eq(Zones.zoneAt(list, -3, 0), list[1])
	eq(Zones.zoneAt(list, 6, 0), list[2], "nearest centre relative to its radius")
	eq(Zones.abAt(list, 6, 0), "game")
	eq(Zones.zoneAt(list, 50, 50), nil)
	eq(Zones.idOf(list[1]), "g1b")
	eq(Zones.idOf(list[2]), nil, "no id")
	eq(Zones.idOf(list[3]), nil, "a malformed label is no id")
	eq(Zones.idOf(nil), nil)
	eq(Zones.runOf("r-1.2"), "r-1.2")
	eq(Zones.runOf("has space"), nil)
	eq(Zones.runOf(42), "42")
end)

test("validate: ring layout variants accepted; by_ab lists them after sl_keeplights in their order, each only when present", function()
	local zs = {}
	for i, ab in ipairs({ "sl_rmid", "sl_rsplit", "sl_rspread", "sl_rspiral", "sl_r2exit", "sl_rout1", "sl_rmatch", "sl_rturbo", "sl_keeplights", "sl" }) do
		zs[i] = { x = i * 10, y = 0, r = 3, ab = ab }
	end
	local op, list = Zones.validate({ op = "set", run = "rv", zones = zs })
	eq(op, "set")
	eq(Zones.byAbText(list), "game:0,sl:1,sl_phases:0,sl_keeplights:1,sl_rturbo:1,sl_rmatch:1,sl_rout1:1,sl_r2exit:1,sl_rspiral:1,sl_rspread:1,sl_rsplit:1,sl_rmid:1")
	local _, two = Zones.validate({ op = "set", zones = { { x = 1, y = 1, r = 3, ab = "sl_rspiral" }, { x = 9, y = 9, r = 3, ab = "sl_rspiral" } } })
	eq(Zones.byAbText(two), "game:0,sl:0,sl_phases:0,sl_rspiral:2")
	eq({ table.unpack(Zones.AB, 8, 15) }, { "sl_rturbo", "sl_rmatch", "sl_rout1", "sl_r2exit", "sl_rspiral", "sl_rspread", "sl_rsplit", "sl_rmid" })
	for i = 8, #Zones.AB do local ab = Zones.AB[i]; ok(#ab <= 12 and ab:match("^[%w_]+$") ~= nil, ab) end
end)

test("validate: sl_classic refused (the classic patterns are gone, PLAN.md \"No classic fallback\"); a saved sl_classic zone counts nowhere in by_ab", function()
	eq({ Zones.validate({ op = "set", zones = { { x = 9, y = 9, r = 3, ab = "sl_phases" }, { x = 1, y = 2, r = 3, ab = "sl_classic" } } }) },
		{ nil, "ab2" })
	for _, ab in ipairs(Zones.AB) do ok(ab ~= "sl_classic", ab) end
	eq(Zones.byAbText({ { ab = "sl_phases" }, { ab = "sl_classic" } }), "game:0,sl:0,sl_phases:1")
	-- a zone saved before (an older save) matches no mode: abAt still returns its ab, nothing plans for it
	eq(Zones.abAt({ { x = 0, y = 0, r = 10, ab = "sl_classic" } }, 1, 1), "sl_classic")
end)

test("validate: sl_auto accepted (axis plan + Keep timing adjusted, step B); by_ab adds it only when present, last", function()
	local _, list = Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl_auto", id = "g1t", pair = "g1" },
		{ x = 9, y = 9, r = 3, ab = "sl_phases" }, { x = 20, y = 9, r = 3, ab = "sl_rmid" } } })
	eq(#list, 3)
	eq(list[1], { x = 1, y = 2, r = 3, ab = "sl_auto", id = "g1t", pair = "g1" })
	eq(Zones.byAbText(list), "game:0,sl:0,sl_phases:1,sl_rmid:1,sl_auto:1")
	eq(Zones.byAbText({ { ab = "sl_phases" } }), "game:0,sl:0,sl_phases:1", "unchanged for senders that send no sl_auto")
	eq(Zones.AB[16], "sl_auto")
end)

test("validate: sl_rmid2 / sl_rturbo_in accepted (ring lane use); by_ab adds them only when present, after sl_auto", function()
	local _, list = Zones.validate({ op = "set", zones = { { x = 1, y = 2, r = 3, ab = "sl_rturbo_in", id = "r4i", pair = "r4" },
		{ x = 9, y = 9, r = 3, ab = "sl_rmid2", id = "r2m", pair = "r2" }, { x = 20, y = 9, r = 3, ab = "sl_rturbo" },
		{ x = 30, y = 9, r = 3, ab = "sl_auto" } } })
	eq(#list, 4)
	eq(list[1], { x = 1, y = 2, r = 3, ab = "sl_rturbo_in", id = "r4i", pair = "r4" })
	eq(Zones.byAbText(list), "game:0,sl:0,sl_phases:0,sl_rturbo:1,sl_auto:1,sl_rmid2:1,sl_rturbo_in:1")
	eq({ Zones.AB[#Zones.AB - 1], Zones.AB[#Zones.AB] }, { "sl_rmid2", "sl_rturbo_in" })
	for _, ab in ipairs({ "sl_rmid2", "sl_rturbo_in" }) do ok(#ab <= 12 and ab:match("^[%w_]+$") ~= nil, ab) end
end)
