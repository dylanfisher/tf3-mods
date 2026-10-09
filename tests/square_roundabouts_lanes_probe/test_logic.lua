-- square_roundabouts_lanes_probe: pure logic (lanes_logic.lua) and the script's wiring with a fake api.

local L = ug_require "/sqrb_lanes/lanes_logic.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_lanes_probe/"
local MOD_ROOT = here .. "../../mods/square_roundabouts_lanes_probe/"

local function conn(s0, l0, s1, l1, road, tram)
	return { segment0 = s0, lane0 = l0, segment1 = s1, lane1 = l1, withRoad = road ~= false, withTram = tram == true }
end

test("mod params: 1-based indices, default Off", function()
	eq(L.fromModParams(nil).write, false)
	eq(L.fromModParams({ sqrb_lanes_write = 2 }).write, true)
	eq(L.fromModParams({ sqrb_lanes_write = 1 }).write, false)
	eq(L.fromModParams({ sqrb_lanes_write = 7 }).write, false)
	eq(L.fromModParams({ sqrb_lanes_write = 1.5 }).write, false)
end)

test("mod.json param matches KEYS / VALUES / DEFAULTS and keeps the experiment off", function()
	local f = assert(io.open(MOD_ROOT .. "mod.json", "r"))
	local s = f:read("a")
	f:close()
	ok(s:find('"key": "' .. L.KEYS.write .. '"', 1, true), "key")
	ok(s:find('"values": %["Off", "On"%]'), "values")
	ok(s:find('"defaultIndex": 0', 1, true), "default Off")
	eq(L.DEFAULTS.write, 1)
	ok(s:find('"severityRemove": "None"', 1, true))
end)

test("line format round-trips and never contains spaces in values", function()
	local text = L.line("NODE", { { "node", 12 }, { "file", "a b\tc" }, { "ok", true }, { "x", nil } })
	eq(text, "[SQRB-LANES] NODE node=12 file=a_b_c ok=true x=nil")
	local kind, f, order = L.parse("2026 INFO " .. text)
	eq(kind, "NODE")
	eq(f.file, "a_b_c")
	eq(order, { "node", "file", "ok", "x" })
	eq(L.parse("[SQRB_PROBE] R x=1"), nil)
	eq(#L.clean(string.rep("x", 400)), 160)
end)

test("entries by file name", function()
	eq(L.entryOf("/infrastructure/street_construction/square_roundabouts.con"), "main")
	eq(L.entryOf("/infrastructure/street_construction/square_roundabouts_magic.con"), "magic")
	eq(L.entryOf("/infrastructure/street_construction/square_roundabouts_channel.con"), "channel")
	eq(L.entryOf("/infrastructure/street_construction/square_roundabouts_interchange.con"), "interchange")
	eq(L.entryOf("infrastructure/street_construction/roundabout.con"), "vanilla")
	eq(L.entryOf("/infrastructure/street_construction/sqrb_probe_old_one_way.con"), nil)
	eq(L.entryOf("station/rail/modular_station/modular_station.con"), nil)
	eq(L.entryOf(nil), nil)
end)

test("ring templates and short names", function()
	ok(L.isRingTemplate("standard/town_new_one_way_small.lua"))
	ok(L.isRingTemplate("town_new_one_way_medium_tram_electrified"))
	ok(L.isRingTemplate("highway_new_small"))
	ok(not L.isRingTemplate("town_new_small"))
	ok(not L.isRingTemplate("town_new_one_way_xsmall"))
	ok(not L.isRingTemplate(nil))
	eq(L.shortTemplate("::/streets/standard/town_new_small.lua"), "town_new_small")
end)

test("connection text is sorted and stable", function()
	local a = { conn(5, 1, 7, 0), conn(3, 0, 7, 1, true, true) }
	eq(L.connText(a[1]), "5:1>7:0:R-")
	eq(L.connsText(a), "3:0>7:1:RT,5:1>7:0:R-")
	eq(L.connsText({ a[2], a[1] }), L.connsText(a))
	eq(L.connsText(nil), "")
end)

test("lanes text", function()
	local lanes = {
		{ forward = false, width = 3, offset = -4.5, transportModes = { [1] = true, [2] = false } },
		{ forward = true, width = 3.5, offset = 1.75, transportModes = { car = true, bus = true } },
	}
	eq(L.lanesText(lanes), "B:3:-4.5:1,F:3.5:1.8:bus+car")
end)

test("search circle from bbox, transf fallback, clamped", function()
	local x, y, r, src = L.searchCircle({ min = { x = -30, y = -40 }, max = { x = 30, y = 40 } }, nil)
	eq(src, "bbox")
	near(x, 0)
	near(y, 0)
	near(r, 50 + L.RADIUS_MARGIN)
	local t = {}
	for i = 1, 16 do t[i] = 0 end
	t[13], t[14], t[15] = 100, 200, 5
	x, y, r, src = L.searchCircle(nil, t)
	eq({ x, y, r, src }, { 100, 200, L.RADIUS_DEFAULT, "transf" })
	_, _, r = L.searchCircle({ min = { x = 0, y = 0 }, max = { x = 2, y = 2 } }, nil)
	eq(r, L.RADIUS_MIN)
	_, _, r = L.searchCircle({ min = { x = 0, y = 0 }, max = { x = 2000, y = 2000 } }, nil)
	eq(r, L.RADIUS_MAX)
	eq(L.searchCircle(nil, nil), nil)
end)

test("params text keeps sqrb_ keys only", function()
	eq(L.paramsText({ sqrb_lanes = 2, sqrb_arms = 3, seed = 9, paramX = 1, sqrb_t = { 1 } }), "sqrb_arms:3,sqrb_lanes:2")
	eq(L.paramsText(nil), "")
end)

test("shape and id lists", function()
	eq(L.shapeText({ {}, {}, {}, true }), "1:table,2:table,3:table,4:boolean")
	eq(L.idsText({ 1, 2, 3 }, 2), "1,2...(3)")
	eq(L.count(nil), 0)
end)

-- A 2-lane ring node: ring in = 10, ring out = 11, two-way arm = 20.
local function ringNode(node, lanes)
	local conns = {}
	for l = 0, lanes - 1 do
		conns[#conns + 1] = conn(10, l, 11, l)  -- ring through
		conns[#conns + 1] = conn(10, l, 20, 1)  -- ring -> arm (outbound lane of the arm)
	end
	conns[#conns + 1] = conn(20, 0, 11, 0)        -- arm -> ring
	return {
		node = node,
		segs = { { id = 10, tpl = "town_new_one_way_small" }, { id = 11, tpl = "town_new_one_way_small" },
			{ id = 20, tpl = "town_new_small" } },
		conns = conns,
	}
end

test("experiment: removes ring->arm connections of the highest incoming lane", function()
	local c = L.chooseExperiment({ ringNode(50, 2) })
	eq(c.node, 50)
	eq(c.lane0, 1)
	eq(c.ringIn, 10)
	eq(c.arm, 20)
	eq(L.connsText(c.remove), "10:1>20:1:R-")
	eq(#c.keep, 4)
	-- keep + remove = everything, nothing else touched
	local all = {}
	for _, x in ipairs(c.keep) do all[#all + 1] = x end
	for _, x in ipairs(c.remove) do all[#all + 1] = x end
	eq(L.connsText(all), L.connsText(ringNode(50, 2).conns))
end)

test("experiment: lowest node id wins, 1-lane rings and non-ring nodes are skipped", function()
	local plain = { node = 1, segs = { { id = 1, tpl = "town_new_small" }, { id = 2, tpl = "town_new_small" },
		{ id = 3, tpl = "town_new_small" } }, conns = { conn(1, 0, 2, 0), conn(1, 1, 3, 0) } }
	eq(L.chooseExperiment({ ringNode(80, 2), plain, ringNode(60, 4) }).node, 60)
	eq(L.chooseExperiment({ ringNode(60, 4) }).lane0, 3)
	local c, why = L.chooseExperiment({ ringNode(70, 1), plain })
	eq(c, nil)
	ok(why:find("1-lane", 1, true))
	eq(L.chooseExperiment({}), nil)
end)

test("experiment: tram-only connections are never removed", function()
	local n = ringNode(50, 2)
	n.conns[#n.conns + 1] = conn(10, 1, 20, 0, false, true)
	local c = L.chooseExperiment({ n })
	eq(L.connsText(c.remove), "10:1>20:1:R-")
end)

test("userModified mode alternates per write", function()
	eq({ L.userModifiedMode(1), L.userModifiedMode(2), L.userModifiedMode(3) }, { "set_true", "keep", "set_true" })
end)

test("fallback circle around added nodes", function()
	local x, y, r = L.circleFromPoints({ { x = 0, y = 0 }, { x = 100, y = 0 }, { x = 50, y = 40 } })
	near(x, 50)
	near(y, 20)
	ok(r > 50 and r < 80)
	eq(L.circleFromPoints({}), nil)
end)
