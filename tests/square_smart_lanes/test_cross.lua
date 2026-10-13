-- square_smart_lanes: crossroads and T-junctions of two-way roads (sl_cross.lua, via sl_slip):
-- the lane allocation per lane count, the exit lane mapping, and on built worlds: every lane
-- connected, every exit lane fed, no two lanes of one approach crossing, no U-turn, the kerb lane
-- of a 3-lane road turning only, both traffic sides.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Lights = ug_require "square_smart_lanes::/smart_lanes/sl_lights.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local TPL = { [1] = F.TPL.small, [2] = F.TPL.medium, [3] = F.TPL.large }

local function rangesText(res)
	local out = {}
	for i = 1, #res do out[#out + 1] = res[i][1] .. "-" .. res[i][2] end
	return table.concat(out, " ")
end

test("allocate: lane counts against exits (kerb turn, straight, far turn)", function()
	local KSF = { "kerb", "straight", "far" }
	eq(rangesText(Cross.allocate(1, KSF)), "1-3", "1 lane: everything")
	eq(rangesText(Cross.allocate(2, KSF)), "1-2 2-3", "2 lanes: kerb+straight, straight+far")
	eq(rangesText(Cross.allocate(3, KSF)), "1-1 2-2 2-3", "3 lanes: kerb only, straight, straight+far")
	eq(rangesText(Cross.allocate(4, KSF)), "1-1 2-2 2-2 2-3", "4 lanes: kerb turn dedicated, far lane shares straight")
	eq(rangesText(Cross.allocate(2, { "kerb", "straight" })), "1-2 2-2", "main road at a T, kerb-side road")
	eq(rangesText(Cross.allocate(2, { "straight", "far" })), "1-1 1-2", "main road at a T, far-side road")
	eq(rangesText(Cross.allocate(3, { "kerb", "straight" })), "1-1 2-2 2-2", "3 lanes at a T: kerb lane turns only")
	eq(rangesText(Cross.allocate(3, { "straight", "far" })), "1-1 1-1 1-2", "3 lanes at a T: far lane straight + far turn")
	eq(rangesText(Cross.allocate(2, { "kerb", "far" })), "1-1 2-2", "side road of a T")
	eq(rangesText(Cross.allocate(3, { "kerb", "far" })), "1-1 2-2 2-2", "3-lane side road: far turn gets the rest")
end)

test("mapLanes: kerb-aligned and far-aligned, folding extra feeders", function()
	local function text(list)
		local out = {}
		for _, p in ipairs(list) do out[#out + 1] = p[1] .. ">" .. p[2] end
		return table.concat(out, " ")
	end
	eq(text(Cross.mapLanes(1, 3, true)), "1>1", "kerb turn into the kerb lane")
	eq(text(Cross.mapLanes(1, 3, false)), "1>3", "far turn into the far lane")
	eq(text(Cross.mapLanes(2, 3, false)), "2>3 1>2", "two straight lanes leave the kerb lane free")
	eq(text(Cross.mapLanes(3, 2, false)), "3>2 2>1 1>1", "extra feeders fold into the kerb lane")
	eq(text(Cross.mapLanes(3, 2, true)), "1>1 2>2 3>2", "extra kerb feeders fold into the far lane")
end)

--- Crossroads at node 1 of a main road (east-west, `main` lanes per direction) and a side road
-- (north-south, `side`); t: no south arm. skew: the side road's angle off 90 degrees.
-- Segments: 11 west, 12 east (drawn from node 1 out), 13 north, 14 south.
local function crossing(main, side, opt)
	opt = opt or {}
	local a = math.rad(90 - (opt.skew or 0))
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 60 * math.cos(a), 60 * math.sin(a) } }
	local segs = { [11] = { 1, 2, TPL[main] }, [12] = { 1, 3, TPL[main] }, [13] = { 1, 4, TPL[side] } }
	if not opt.t then
		nodes[5] = { -60 * math.cos(a), -60 * math.sin(a) }
		segs[14] = { 1, 5, TPL[side] }
	end
	return F.build(nodes, segs, opt.mirror)
end

--- Invariants on a case X view and its road connections. Returns per approach seg:
-- { [lane position] = { exit seg = {exit lane positions} } }.
local function check(v, conns, msg)
	local inPos, outPos = {}, {}
	for _, ap in ipairs(v.approaches) do
		for i, l in ipairs(ap.m) do inPos[ap.seg .. ":" .. l] = i end
		for _, ex in ipairs(ap.exits) do
			for j, l in ipairs(ex.o) do outPos[ex.seg .. ":" .. l] = j end
		end
	end
	local by, fed = {}, {}
	for _, c in ipairs(conns) do
		ok(c.segment0 ~= c.segment1, msg .. " U-turn " .. Rules.connsText({ c }))
		local i, j = inPos[c.segment0 .. ":" .. c.lane0], outPos[c.segment1 .. ":" .. c.lane1]
		ok(i ~= nil and j ~= nil, msg .. " connection outside the lanes " .. Rules.connsText({ c }))
		if i and j then
			by[c.segment0] = by[c.segment0] or {}
			by[c.segment0][i] = by[c.segment0][i] or {}
			local t = by[c.segment0][i]
			t[c.segment1] = t[c.segment1] or {}
			table.insert(t[c.segment1], j)
			fed[c.segment1 .. ":" .. j] = true
		end
	end
	for _, ap in ipairs(v.approaches) do
		local order = {}
		for e, ex in ipairs(ap.exits) do
			order[ex.seg] = e
			for j = 1, #ex.o do ok(fed[ex.seg .. ":" .. j], msg .. " exit " .. ex.seg .. " lane " .. j .. " fed") end
		end
		for i = 1, #ap.m do ok(by[ap.seg] and by[ap.seg][i], msg .. " approach " .. ap.seg .. " lane " .. i .. " connected") end
		-- no crossing within an approach: lane a < b never reaches a later exit, or a farther lane of
		-- the same exit, than b does
		for a = 1, #ap.m do
			for b = a + 1, #ap.m do
				for sa, la in pairs(by[ap.seg] and by[ap.seg][a] or {}) do
					for sb, lb in pairs(by[ap.seg] and by[ap.seg][b] or {}) do
						ok(order[sa] <= order[sb], string.format("%s approach %d: lane %d exit %d after lane %d exit %d", msg, ap.seg, a, sa, b, sb))
						if sa == sb then
							for _, x in ipairs(la) do
								for _, y in ipairs(lb) do
									ok(x <= y, string.format("%s approach %d: lanes %d>%d and %d>%d cross into %d", msg, ap.seg, a, x, b, y, sa))
								end
							end
						end
					end
				end
			end
		end
	end
	return by
end

local function approach(v, seg)
	for _, ap in ipairs(v.approaches) do if ap.seg == seg then return ap end end
end

test("every crossing and T of 1-3 lane roads, both sides, square and skewed: invariants hold", function()
	local n = 0
	for main = 1, 3 do
		for side = 1, 3 do
			for _, t in ipairs({ false, true }) do
				for _, mirror in ipairs({ false, true }) do
					for _, skew in ipairs({ 0, 30 }) do
						local world = crossing(main, side, { t = t, mirror = mirror, skew = skew })
						local msg = string.format("%dx%d%s%s skew %d", main, side, t and " T" or "", mirror and " LHT" or "", skew)
						local r = Slip.plan(world, 1, function() return {} end)
						eq(r.view.kind, "slip", msg .. " handled")
						eq(r.view.case, "X", msg .. " case X")
						eq(r.view.shape, t and "t_junction" or "crossroads", msg .. " shape")
						eq(r.view.side, mirror and "left" or "right", msg .. " side")
						check(r.view, r.conns, msg)
						ok(not Lights.slipNode(r), msg .. " keeps its lights")
						n = n + 1
					end
				end
			end
		end
	end
	eq(n, 72, "cases")
end)

test("3-lane road: the kerb lane only turns towards the kerb, straight leaves the exit's kerb lane to the side road", function()
	for _, mirror in ipairs({ false, true }) do
		local world = crossing(3, 1, { mirror = mirror })
		local r = Slip.plan(world, 1, function() return {} end)
		local by = check(r.view, r.conns, "3x1")
		-- traffic arriving on segment 11 (from the west; mirrored: from the east)
		local ap = approach(r.view, 11)
		eq(ap.exits[1].cat, "kerb", "kerb turn first")
		eq(ap.exits[2].cat, "straight", "then straight")
		eq(ap.exits[3].cat, "far", "then the far turn")
		local kerb, straight, far = ap.exits[1].seg, ap.exits[2].seg, ap.exits[3].seg
		local lane1 = by[11][1]
		ok(lane1[kerb] ~= nil and lane1[straight] == nil and lane1[far] == nil, "kerb lane: kerb turn only")
		ok(by[11][2][straight] ~= nil and by[11][2][kerb] == nil and by[11][2][far] == nil, "middle lane: straight only")
		ok(by[11][3][straight] ~= nil and by[11][3][far] ~= nil, "far lane: straight and far turn")
		eq(table.concat(by[11][2][straight], ","), "2", "middle lane into the exit's middle lane")
		eq(table.concat(by[11][3][straight], ","), "3", "far lane into the exit's far lane")
		-- the exit's kerb lane: fed by the side road turning in on its kerb side, not by straight traffic
		local side = nil
		for _, a in ipairs(r.view.approaches) do
			if a.seg ~= 11 and a.exits[1].seg == straight then side = a end
		end
		ok(side ~= nil and (side.seg == 13 or side.seg == 14), "side approach")
		local turnIn = by[side.seg][1][straight]
		ok(turnIn ~= nil and turnIn[1] == 1, "side road turns into the exit's kerb lane")
	end
end)

test("2x2 crossing: shared lanes, and the summary", function()
	local world = crossing(2, 2)
	local r = Slip.plan(world, 1, function() return {} end)
	check(r.view, r.conns, "2x2")
	eq(Slip.summary(r.view):match("^11:[^;]+"), "11:ks|sf", "west approach: kerb+straight, straight+far")
	eq(Slip.mainLanes(r.view), 2, "main lanes")
	eq(r.status, "apply", "differs from no connections")
	local again = Slip.plan(world, 1, function() return r.conns end)
	eq(again.status, "same", "applied once")
end)

test("not handled: bus lanes, mixed driving sides, 5 roads, tram kept", function()
	local world = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } },
		{ [11] = { 1, 2, F.TPL.medium_bus }, [12] = { 1, 3, F.TPL.medium }, [13] = { 1, 4, F.TPL.small } })
	eq(Slip.classify(world, 1).reason, "bus_lane", "bus lane")
	local nodes, segs = { [1] = { 0, 0 } }, {}
	for i = 1, 5 do
		local a = math.rad(i * 72)
		nodes[i + 1] = { 60 * math.cos(a), 60 * math.sin(a) }
		segs[10 + i] = { 1, i + 1, F.TPL.small }
	end
	eq(Slip.classify(F.build(nodes, segs), 1).reason, "roads_5", "5 roads")
	local tram = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } },
		{ [11] = { 1, 2, F.TPL.small_tram }, [12] = { 1, 3, F.TPL.small_tram }, [13] = { 1, 4, F.TPL.small } })
	local cur = { Rules.conn(11, 1, 12, 2, false, true) }
	local r = Slip.plan(tram, 1, function() return cur end)
	eq(r.view.case, "X", "tram street T handled")
	local kept = false
	for _, c in ipairs(r.conns) do if c.withTram and c.segment0 == 11 and c.segment1 == 12 then kept = true end end
	ok(kept, "tram connection kept")
end)

---------------------------------------------------------------------------
-- One-way roads at a junction (ramp ends, divided roads, one-way streets)

--- Node 1 with roads to the four compass points: spec {east, north, west, south} = template and
-- direction ("out": drawn from node 1 away, "in": drawn towards node 1), nil for no road.
-- Segment ids: 11 east, 12 north, 13 west, 14 south.
local function compass(spec, mirror)
	local pts = { { 60, 0 }, { 0, 60 }, { -60, 0 }, { 0, -60 } }
	local nodes, segs = { [1] = { 0, 0 } }, {}
	for i = 1, 4 do
		local r = spec[i]
		if r then
			nodes[i + 1] = pts[i]
			if r[2] == "in" then segs[10 + i] = { i + 1, 1, r[1] } else segs[10 + i] = { 1, i + 1, r[1] } end
		end
	end
	return F.build(nodes, segs, mirror)
end

local ONE = "BS FV FV FS" -- 2-lane one-way
local ONE1 = "B- FV F-"   -- 1-lane ramp

test("diamond ramp terminal: off-ramp in and on-ramp out meeting a two-way cross road", function()
	for _, mirror in ipairs({ false, true }) do
		-- cross road east-west; the off-ramp arrives from the south-west, the on-ramp leaves to the south-east
		local world = F.build({ [1] = { 0, 0 }, [2] = { 60, 0 }, [3] = { -60, 0 }, [4] = { -20, -60 }, [5] = { 20, -60 } },
			{ [11] = { 1, 2, F.TPL.medium }, [13] = { 1, 3, F.TPL.medium }, [14] = { 4, 1, ONE1 }, [15] = { 1, 5, ONE1 } }, mirror)
		local r = Slip.plan(world, 1, function() return {} end)
		local msg = mirror and "LHT" or "RHT"
		eq(r.view.case, "X", msg .. " crossing rule")
		eq(r.view.shape, "crossroads", msg)
		check(r.view, r.conns, msg)
		eq(#r.view.approaches, 3, msg .. " the on-ramp is no approach")
		local off = approach(r.view, 14)
		eq(#off.exits, 2, msg .. " off-ramp: both ways along the cross road, not back onto the on-ramp")
		for _, c in ipairs(r.conns) do ok(not (c.segment0 == 14 and c.segment1 == 15), msg .. " no U-turn ramp to ramp") end
	end
end)

test("divided road crossing a two-way road, one-way street crossing and meeting a two-way street", function()
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		-- the carriageway runs north (in from the south, out to the north), the road runs east-west
		local world = compass({ { F.TPL.medium, "out" }, { ONE, "out" }, { F.TPL.medium, "out" }, { ONE, "in" } }, mirror)
		local r = Slip.plan(world, 1, function() return {} end)
		eq(r.view.case, "X", "carriageway crossing" .. m)
		check(r.view, r.conns, "carriageway crossing" .. m)
		eq(#r.view.approaches, 3, "carriageway crossing: three approaches" .. m)
		-- a one-way street ending at a two-way street (T)
		local t = compass({ { F.TPL.medium, "out" }, nil, { F.TPL.medium, "out" }, { ONE, "in" } }, mirror)
		local rt = Slip.plan(t, 1, function() return {} end)
		eq(rt.view.case, "X", "one-way into a T" .. m)
		eq(rt.view.shape, "t_junction", "one-way into a T" .. m)
		check(rt.view, rt.conns, "one-way into a T" .. m)
		-- a two-way street ending at a one-way street (T): the one-way runs straight through
		local t2 = compass({ { ONE, "out" }, nil, { ONE, "in" }, { F.TPL.medium, "out" } }, mirror)
		local r2 = Slip.plan(t2, 1, function() return {} end)
		eq(r2.view.case, "X", "two-way into a one-way street" .. m)
		check(r2.view, r2.conns, "two-way into a one-way street" .. m)
		ok(Rules.line("APPLY", Slip.logFields(r2)):find(" case=X via=one_way_square side=", 1, true), "via" .. m)
	end
end)

test("left alone: a splitter's split node, one-way roads only", function()
	-- a two-way road running on into a one-way pair (splitter island, dual carriageway end)
	local split = F.build({ [1] = { 0, 0 }, [2] = { -50, 0 }, [3] = { 50, 10 }, [4] = { 50, -10 } },
		{ [11] = { 2, 1, F.TPL.medium }, [12] = { 3, 1, ONE }, [13] = { 1, 4, ONE } })
	eq(Slip.classify(split, 1).kind, "none")
	eq(Slip.classify(split, 1).reason, "mixed_one_way")
	-- two one-way streets crossing: no two-way road tells the driving side
	local grid = compass({ { ONE, "out" }, { ONE, "out" }, { ONE, "in" }, { ONE, "in" } })
	eq(Slip.classify(grid, 1).kind, "skip")
end)

test("game-default model: the in-game 2x2 dump (24) and fresh 3x3 crossings (36)", function()
	local world = crossing(2, 2)
	local v = Slip.classify(world, 1)
	local d = Slip.defaultConns(v)
	eq(#d, 24, "2x2")
	-- west approach (11): kerb lane right into both south lanes + straight; far lane left into both north lanes + straight
	local from = {}
	for _, c in ipairs(d) do
		if c.segment0 == 11 then
			local k = c.lane0 .. ">" .. c.segment1
			from[k] = (from[k] or 0) + 1
		end
	end
	local ap = approach(v, 11)
	local kerbLane, farLane = ap.m[1], ap.m[2]
	eq(from[kerbLane .. ">14"], 2, "kerb lane: right turn into both lanes")
	eq(from[kerbLane .. ">12"], 1, "kerb lane: straight")
	eq(from[farLane .. ">13"], 2, "far lane: left turn into both lanes")
	eq(from[farLane .. ">12"], 1, "far lane: straight")
	eq(#Slip.defaultConns(Slip.classify(crossing(3, 3), 1)), 36, "3x3")
	for _, t in ipairs({ false, true }) do
		for main = 1, 3 do
			for side = 1, 3 do
				local vv = Slip.classify(crossing(main, side, { t = t }), 1)
				local conns = Slip.defaultConns(vv)
				local by = {}
				for _, c in ipairs(conns) do by[c.segment0 .. ":" .. c.lane0] = true end
				for _, a in ipairs(vv.approaches) do
					for _, l in ipairs(a.m) do ok(by[a.seg .. ":" .. l], string.format("%dx%d%s lane %d:%d connected", main, side, t and " T" or "", a.seg, l)) end
				end
			end
		end
	end
	eq(Slip.defaultConns(Slip.classify(F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 50, -20 } },
		{ [31] = { 2, 1, "BS BV BV FV FV FS" }, [32] = { 1, 3, "BS BV BV FV FV FS" }, [33] = { 1, 4, "BS FV FV FS" } }), 1)), nil, "slip node: no model")
end)

--- The engine's variant of the default at a 3x3 crossroads (in game 2026-10-12, Showcase g3b node 331872 and
-- node 66527 of 2026-10-11, 36 connections each): at some approaches a turn comes from two lanes. Kerb turn:
-- the kerb lane into the exit's two kerb lanes, the next lane into its far lane; far turn: the lane next to
-- the far lane into the exit's kerb lane, the far lane into the other two. which: { [approach index] =
-- "kerb" | "far" | "both" }.
local function engineVariant(v, which)
	local list = {}
	local drop = {}
	local add = {}
	for i, ap in ipairs(v.approaches) do
		local w = which[i]
		local N = #ap.m
		for _, ex in ipairs(ap.allExits or ap.exits) do
			if #ex.o == 3 and N == 3 and ((ex.cat == "kerb" and (w == "kerb" or w == "both")) or (ex.cat == "far" and (w == "far" or w == "both"))) then
				drop[ap.seg .. ">" .. ex.seg] = true
				if ex.cat == "kerb" then
					add[#add + 1] = Rules.conn(ap.seg, ap.m[1], ex.seg, ex.o[1], true, false)
					add[#add + 1] = Rules.conn(ap.seg, ap.m[1], ex.seg, ex.o[2], true, false)
					add[#add + 1] = Rules.conn(ap.seg, ap.m[2], ex.seg, ex.o[3], true, false)
				else
					add[#add + 1] = Rules.conn(ap.seg, ap.m[2], ex.seg, ex.o[1], true, false)
					add[#add + 1] = Rules.conn(ap.seg, ap.m[3], ex.seg, ex.o[2], true, false)
					add[#add + 1] = Rules.conn(ap.seg, ap.m[3], ex.seg, ex.o[3], true, false)
				end
			end
		end
	end
	for _, c in ipairs(Slip.defaultConns(v)) do
		if not drop[c.segment0 .. ">" .. c.segment1] then list[#list + 1] = c end
	end
	for _, c in ipairs(add) do list[#list + 1] = c end
	return list
end

test("game default per movement: the engine's two-lane turns at a 3x3 still read as the default (both sides, skewed)", function()
	for _, mirror in ipairs({ false, true }) do
		for _, skew in ipairs({ 0, 30 }) do
			local msg = string.format("%s skew %d", mirror and "LHT" or "RHT", skew)
			local v = Slip.classify(crossing(3, 3, { mirror = mirror, skew = skew }), 1)
			eq(v.case, "X", msg)
			local model = Slip.defaultConns(v)
			eq(#model, 36, msg)
			eq(Slip.isDefault(v, model), true, msg .. ": the model itself")
			-- the in-game pattern: one arm splits both turns, two arms one turn each, one arm none
			local var = engineVariant(v, { "both", "kerb", "far" })
			eq(#var, 36, msg .. ": still 36")
			ok(Rules.connsText(var) ~= Rules.connsText(model), msg .. ": lane-level different")
			eq(Slip.isDefault(v, var), true, msg .. ": the engine's variant")
			-- tram-only connections are ignored
			local tram = { Rules.conn(v.approaches[1].seg, v.approaches[1].m[1], v.approaches[2].seg, 1, false, true) }
			for _, c in ipairs(var) do tram[#tram + 1] = c end
			eq(Slip.isDefault(v, tram), true, msg .. ": tram connection ignored")
			-- the rule's lanes, a missing connection, a turn into fewer exit lanes: not the default
			local r = Slip.plan(crossing(3, 3, { mirror = mirror, skew = skew }), 1, function() return model end)
			eq(r.status, "apply", msg)
			eq(Slip.isDefault(r.view, r.conns), false, msg .. ": Smart lanes")
			local less = {}
			for i = 2, #var do less[#less + 1] = var[i] end
			eq(Slip.isDefault(v, less), false, msg .. ": one connection missing")
			local moved = {}
			for i, c in ipairs(var) do moved[i] = c end
			local ap = v.approaches[1]
			for i, c in ipairs(moved) do
				if c.segment0 == ap.seg and c.segment1 ~= ap.exits[1].seg and c.segment1 ~= ap.seg then
					-- the same count, but every connection of this movement into one lane
					moved[i] = Rules.conn(c.segment0, c.lane0, c.segment1, 1, true, false)
				end
			end
			eq(Slip.isDefault(v, moved), false, msg .. ": exit lanes changed")
		end
	end
	eq(Slip.isDefault(Slip.classify(F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 50, -20 } },
		{ [31] = { 2, 1, "BS BV BV FV FV FS" }, [32] = { 1, 3, "BS BV BV FV FV FS" }, [33] = { 1, 4, "BS FV FV FS" } }), 1), {}), nil, "slip node: no model")
end)

test("game default per movement: Smart Lanes' own straight fold never reads as the default", function()
	-- a 3-lane side road meeting a 2-lane road at a T, skewed so it runs straight on: the rule folds the
	-- extra lane at the kerb, the model at the far side; same count and exit lanes per movement
	for _, mirror in ipairs({ false, true }) do
		local world = crossing(2, 3, { t = true, skew = 50, mirror = mirror })
		local v = Slip.classify(world, 1)
		eq(v.case, "X", "skewed T")
		local model = Slip.defaultConns(v)
		local r = Slip.plan(crossing(2, 3, { t = true, skew = 50, mirror = mirror }), 1, function() return model end)
		eq(r.status, "apply", "skewed T")
		ok(Rules.connsText(r.conns) ~= Rules.connsText(model), "lane-level different")
		eq(Slip.isDefault(r.view, r.conns), false, "Smart lanes' straight fold")
		eq(Slip.isDefault(r.view, model), true, "the model")
	end
end)

test("parclo ramp end: the off-ramp never runs straight across onto the on-ramp; one-way streets still do", function()
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		-- cross road east-west; off-ramp in from the north, on-ramp out to the south (straight across)
		local world = compass({ { F.TPL.medium, "out" }, { ONE1, "in" }, { F.TPL.medium, "out" }, { ONE1, "out" } }, mirror)
		local r = Slip.plan(world, 1, function() return {} end)
		eq(r.view.case, "X", "parclo terminal" .. m)
		check(r.view, r.conns, "parclo terminal" .. m)
		for _, c in ipairs(r.conns) do ok(not (c.segment0 == 12 and c.segment1 == 14), "off-ramp onto on-ramp" .. m) end
		eq(#approach(r.view, 12).exits, 2, "off-ramp: left and right only" .. m)
		-- the on-ramp is still reached from the cross road
		local fed = false
		for _, c in ipairs(r.conns) do if c.segment1 == 14 then fed = true end end
		ok(fed, "on-ramp fed from the cross road" .. m)
		-- a one-way town street (sidewalks) crossing a road keeps going straight
		local street = compass({ { F.TPL.medium, "out" }, { ONE, "in" }, { F.TPL.medium, "out" }, { ONE, "out" } }, mirror)
		local rs = Slip.plan(street, 1, function() return {} end)
		local straight = false
		for _, c in ipairs(rs.conns) do if c.segment0 == 12 and c.segment1 == 14 then straight = true end end
		ok(straight, "one-way street straight through" .. m)
	end
end)

---------------------------------------------------------------------------
-- Turns a slip lane serves (sl_cross X.bypasses; in game 2026-10-11: Channelized X)

--- Every outgoing road lane of every road at the centre fed (also exits left to a slip lane).
local function allFed(v, conns, msg)
	local fed = {}
	for _, c in ipairs(conns) do fed[c.segment1 .. ":" .. c.lane1] = true end
	for _, ap in ipairs(v.approaches) do
		for _, ex in ipairs(ap.allExits) do
			for _, l in ipairs(ex.o) do ok(fed[ex.seg .. ":" .. l], msg .. " exit lane " .. ex.seg .. ":" .. l .. " fed") end
		end
	end
end

local function exitSegs(ap)
	local out = {}
	for _, ex in ipairs(ap.exits) do out[#out + 1] = ex.cat .. "=" .. ex.seg end
	return table.concat(out, ",")
end

test("Channelized X centre: the kerb turns are left to the slip lanes, straight and far turns stay", function()
	-- kerb turn of each approach (right-hand frame; mirrored the same segments): east 11 -> north 15,
	-- north 15 -> west 13, west 13 -> south 17, south 17 -> east 11
	local slipTurn = { [11] = 15, [15] = 13, [13] = 17, [17] = 11 }
	local n = 0
	for main = 1, 3 do
		for side = 1, 3 do
			for _, mirror in ipairs({ false, true }) do
				local msg = string.format("%dx%d%s", main, side, mirror and " LHT" or "")
				local W = F.channelX({ main = TPL[main], side = TPL[side], mirror = mirror })
				local r = Slip.plan(W, 1, function() return {} end)
				eq(r.view.case, "X", msg)
				eq(r.view.shape, "crossroads", msg)
				eq(table.concat(r.view.bypassed, ","), "11>15,13>17,15>13,17>11", msg .. " bypassed")
				check(r.view, r.conns, msg)
				allFed(r.view, r.conns, msg)
				for _, ap in ipairs(r.view.approaches) do
					eq(#ap.exits, 2, msg .. " approach " .. ap.seg .. " exits")
					eq(#ap.allExits, 3, msg .. " approach " .. ap.seg .. " all exits")
					eq(ap.exits[1].cat, "straight", msg .. " " .. exitSegs(ap))
					eq(ap.exits[2].cat, "far", msg .. " " .. exitSegs(ap))
				end
				for _, c in ipairs(r.conns) do
					ok(slipTurn[c.segment0] ~= c.segment1, msg .. " no kerb turn at the centre " .. Rules.connsText({ c }))
				end
				ok(Rules.line("APPLY", Slip.logFields(r)):find(" bypass=4", 1, true), msg .. " logged")
				-- the slip nodes stay slip nodes of their own (case B: one slip lane leaves, one joins)
				for _, sn in ipairs({ 2, 3, 4, 8 }) do
					local v = Slip.classify(W, sn)
					eq(v.case, "B", msg .. " slip node " .. sn)
					eq(v.shape, "diverge+merge", msg .. " slip node " .. sn)
				end
				n = n + 1
			end
		end
	end
	eq(n, 18, "cases")
	-- the user's hand edit (2026-10-11): 3 lanes, kerb straight -> kerb lane, middle -> middle, far lane
	-- straight -> far lane and the far turn
	for _, mirror in ipairs({ false, true }) do
		local r = Slip.plan(F.channelX({ main = TPL[3], side = TPL[3], mirror = mirror }), 1, function() return {} end)
		local by = check(r.view, r.conns, "3x3 hand edit")
		local ap = approach(r.view, 11)
		local st, far = ap.exits[1].seg, ap.exits[2].seg
		eq(Cross.summary(r.view):match("^11:[^;]+"), "11:s|s|sf", "summary")
		for i = 1, 3 do eq(table.concat(by[11][i][st], ","), tostring(i), "lane " .. i .. " straight 1:1") end
		ok(by[11][3][far] ~= nil and by[11][2][far] == nil, "far lane: far turn too")
	end
end)

test("Channelized X: mirrored connections; Reset model keeps the game's full default", function()
	for main = 1, 3 do
		local R, L = F.channelX({ main = TPL[main] }), F.channelX({ main = TPL[main], mirror = true })
		local rr = Slip.plan(R, 1, function() return {} end)
		local rl = Slip.plan(L, 1, function() return {} end)
		local mirrored = {}
		for _, c in ipairs(rr.conns) do
			local L0, L1 = #R.seg(c.segment0).lanes, #R.seg(c.segment1).lanes
			mirrored[#mirrored + 1] = Rules.conn(c.segment0, L0 - 1 - c.lane0, c.segment1, L1 - 1 - c.lane1, true, false)
		end
		eq(Rules.connsText(rl.conns), Rules.connsText(mirrored), "main " .. main)
		-- the game-default model has the kerb turns: as many connections as a plain crossroads
		local d = Slip.defaultConns(rr.view)
		eq(#d, #Slip.defaultConns(Slip.classify(crossing(main, 1), 1)), "main " .. main .. " default model")
		local kerb = false
		for _, c in ipairs(d) do if c.segment0 == 11 and c.segment1 == 15 then kerb = true end end
		ok(kerb, "default model: east approach turns right at the centre")
	end
end)

test("Channelized T centre: drops the turns its two slip lanes serve, keeps the rest", function()
	for _, mirror in ipairs({ false, true }) do
		for main = 1, 3 do
			local msg = string.format("T main %d%s", main, mirror and " LHT" or "")
			local r = Slip.plan(F.channelT({ main = TPL[main], mirror = mirror }), 1, function() return {} end)
			eq(r.view.shape, "t_junction", msg)
			eq(table.concat(r.view.bypassed, ","), "11>15,15>13", msg)
			check(r.view, r.conns, msg)
			allFed(r.view, r.conns, msg)
			eq(exitSegs(approach(r.view, 11)), "straight=13", msg .. " east approach: straight only")
			eq(exitSegs(approach(r.view, 15)), "far=11", msg .. " side road: far turn only")
			eq(exitSegs(approach(r.view, 13)), "straight=11,far=15", msg .. " west approach (no slip lane) unchanged")
		end
	end
end)

--- Channelized T with the slip lane 21 (east -> north) replaced: `chain` = plain segments of the
-- one-way road from node 2 to node 4 (default 1), or `elsewhere`: it ends at a junction off the side
-- road (node 30, two two-way roads on; leaving node 2 forwards) instead.
local function channelTVariant(opt)
	local nodes = {
		[1] = { 0, 0 }, [2] = { 40, 0 }, [3] = { -40, 0 }, [4] = { 0, 35 },
		[5] = { 70, 0 }, [6] = { -70, 0 }, [7] = { 0, 65 },
	}
	local slip = F.TPL.one_way_leg
	local segs = {
		[11] = { 1, 2, F.TPL.medium }, [12] = { 2, 5, F.TPL.medium }, [13] = { 1, 3, F.TPL.medium },
		[14] = { 3, 6, F.TPL.medium }, [15] = { 1, 4, F.TPL.small }, [16] = { 4, 7, F.TPL.small },
		[22] = { 4, 3, slip },
	}
	if opt.elsewhere then
		nodes[30], nodes[31], nodes[32] = { 20, 60 }, { 50, 60 }, { 20, 90 }
		segs[21] = { 2, 30, slip }
		segs[25] = { 30, 31, F.TPL.small }
		segs[26] = { 30, 32, F.TPL.small }
	else
		-- the slip lane cut into k segments: plain nodes on a gentle curve from node 2 to node 4
		-- (bulging 5 m out of the corner: it still leaves forwards and cuts the corner)
		local k = opt.chain or 1
		local prev = 2
		for i = 1, k - 1 do
			local t = i / k
			local b = 5 * math.sin(math.pi * t)
			nodes[100 + i] = { 40 * (1 - t) + b, 35 * t + b }
			segs[200 + i] = { prev, 100 + i, slip }
			prev = 100 + i
		end
		segs[21] = { prev, 4, slip }
	end
	return F.build(nodes, segs, opt.mirror)
end

test("bypass: a one-way road leaving upstream that does not reach the exit road is none; caps terminate", function()
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		local r = Slip.plan(channelTVariant({ elsewhere = true, mirror = mirror }), 1, function() return {} end)
		eq(table.concat(r.view.bypassed, ","), "15>13", "elsewhere: only the side road's slip lane" .. m)
		eq(exitSegs(approach(r.view, 11)), "kerb=15,straight=13", "elsewhere: east approach still turns" .. m)
		check(r.view, r.conns, "elsewhere" .. m)
		-- within the slip walk's caps (10 segments): still a bypass; beyond: none (no hang)
		local near = Slip.plan(channelTVariant({ chain = Cross.BYPASS_SLIP.nodes, mirror = mirror }), 1, function() return {} end)
		eq(table.concat(near.view.bypassed, ","), "11>15,15>13", "chain at the cap" .. m)
		local far = Slip.plan(channelTVariant({ chain = Cross.BYPASS_SLIP.nodes + 1, mirror = mirror }), 1, function() return {} end)
		eq(table.concat(far.view.bypassed, ","), "15>13", "chain beyond the cap" .. m)
		check(far.view, far.conns, "chain beyond the cap" .. m)
	end
	-- the per-node budget of one-way roads followed
	local keep = Cross.BYPASS_MAX_ROADS
	Cross.BYPASS_MAX_ROADS = 1
	local one = Slip.classify(F.channelX(), 1)
	Cross.BYPASS_MAX_ROADS = 0
	local none = Slip.classify(F.channelX(), 1)
	Cross.BYPASS_MAX_ROADS = keep
	eq(#one.bypassed, 1, "budget 1")
	eq(#none.bypassed, 0, "budget 0: the full crossing rule")
	-- a one-way loop leaving upstream and coming back to its own node: the walk stops as a loop
	local W = F.build({ [1] = { 0, 0 }, [2] = { 40, 0 }, [3] = { -40, 0 }, [4] = { 0, 40 }, [5] = { 70, 0 },
		[40] = { 50, 20 }, [41] = { 60, 10 } },
		{ [11] = { 1, 2, F.TPL.medium }, [12] = { 2, 5, F.TPL.medium }, [13] = { 1, 3, F.TPL.medium },
			[15] = { 1, 4, F.TPL.small }, [27] = { 2, 40, F.TPL.one_way_leg }, [28] = { 40, 41, F.TPL.one_way_leg },
			[29] = { 41, 2, F.TPL.one_way_leg } })
	local rl = Slip.plan(W, 1, function() return {} end)
	eq(#rl.view.bypassed, 0, "loop: no bypass")
	check(rl.view, rl.conns, "loop")
end)

--- Classifies node n with the bypass guards relaxed (any heading, any length): the fixture's one-way
-- roads do reach the exit roads' junctions, so only the guards keep the turns.
local function unguarded(W, n)
	local d, s = Cross.BYPASS_MAX_DEG, Cross.BYPASS_SHORTCUT
	Cross.BYPASS_MAX_DEG, Cross.BYPASS_SHORTCUT = 180, math.huge
	local ok2, v = pcall(Slip.classify, W, n)
	Cross.BYPASS_MAX_DEG, Cross.BYPASS_SHORTCUT = d, s
	assert(ok2, v)
	return v
end

test("bypass review: a roundabout splitter leg near a crossroads (entry leg = U-turn at the split) is none", function()
	-- crossroads 1; east arm 11 to the split node 2, entry leg 31 (2 -> ring node 20), exit leg 32
	-- (ring node 21 -> 2); the north road 15/16 runs to ring node 20 as well (ring 41-43 one-way).
	-- Traffic arriving at 1 on 11 came out of the exit leg: the entry leg is a U-turn at 2.
	local ONE = F.TPL.one_way_leg
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		local W = F.build({ [1] = { 0, 0 }, [2] = { 40, 0 }, [3] = { -60, 0 }, [4] = { 0, 40 }, [5] = { 0, -60 },
			[20] = { 70, 15 }, [21] = { 70, -15 }, [22] = { 100, 0 } },
			{ [11] = { 1, 2, F.TPL.medium }, [13] = { 1, 3, F.TPL.medium }, [15] = { 1, 4, F.TPL.small },
				[16] = { 4, 20, F.TPL.small }, [17] = { 1, 5, F.TPL.small },
				[31] = { 2, 20, ONE }, [32] = { 21, 2, ONE },
				[41] = { 20, 21, ONE }, [42] = { 21, 22, ONE }, [43] = { 22, 20, ONE } }, mirror)
		eq(#unguarded(W, 1).bypassed, 1, "fixture: unguarded, the entry leg looks like a bypass" .. m)
		local r = Slip.plan(W, 1, function() return {} end)
		eq(r.view.case, "X", "crossroads" .. m)
		eq(#r.view.bypassed, 0, "no bypass through a U-turn" .. m)
		eq(#approach(r.view, 11).exits, 3, "east approach keeps its kerb turn" .. m)
		check(r.view, r.conns, "splitter" .. m)
	end
end)

test("bypass review: one-way streets round the town blocks of a crossroads are no slip lanes", function()
	-- two-way crossroads at 1 (arms 100 m to the junctions 2 east, 3 north, 4 west, 5 south); a one-way
	-- street rings the four blocks (counter-clockwise, plain corner nodes): from each approach's
	-- upstream junction it leaves forwards and ends at the next exit road's junction, as long as the
	-- way through the crossroads (200 m)
	local ONE = F.TPL.one_way_small
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		local nodes = { [1] = { 0, 0 }, [2] = { 100, 0 }, [3] = { 0, 100 }, [4] = { -100, 0 }, [5] = { 0, -100 },
			[6] = { 100, 100 }, [7] = { -100, 100 }, [8] = { -100, -100 }, [9] = { 100, -100 } }
		local segs = { [11] = { 1, 2, F.TPL.medium }, [12] = { 1, 3, F.TPL.medium }, [13] = { 1, 4, F.TPL.medium },
			[14] = { 1, 5, F.TPL.medium } }
		local ring = { 2, 6, 3, 7, 4, 8, 5, 9, 2 }
		for i = 1, #ring - 1 do segs[50 + i] = { ring[i], ring[i + 1], ONE } end
		local W = F.build(nodes, segs, mirror)
		eq(#unguarded(W, 1).bypassed, 4, "fixture: unguarded, the block streets look like bypasses" .. m)
		local r = Slip.plan(W, 1, function() return {} end)
		eq(#r.view.bypassed, 0, "no bypass round a block" .. m)
		for _, ap in ipairs(r.view.approaches) do eq(#ap.exits, 3, "approach " .. ap.seg .. " keeps every turn" .. m) end
		check(r.view, r.conns, "blocks" .. m)
	end
end)

test("bypass review: diamond interchange terminals keep every turn (the highway is no bypass)", function()
	-- carriageways at x = +-10 (east: northbound 61-63, west: southbound 64-66), diverge / merge nodes
	-- at y = -+150; terminals 2 (east) and 3 (west) on the cross road 11-13; ramps 1-lane highway
	local HW = F.TPL.highway_small
	local N, S = { 0, 1 }, { 0, -1 }
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		local W = F.build({ [1] = { -100, 0 }, [2] = { 40, 0 }, [3] = { -40, 0 }, [4] = { 100, 0 },
			[20] = { 10, -300 }, [21] = { 10, -150 }, [22] = { 10, 150 }, [23] = { 10, 300 },
			[30] = { -10, 300 }, [31] = { -10, 150 }, [32] = { -10, -150 }, [33] = { -10, -300 } },
			{ [11] = { 1, 3, F.TPL.medium }, [12] = { 3, 2, F.TPL.medium }, [13] = { 2, 4, F.TPL.medium },
				[61] = { 20, 21, HW }, [62] = { 21, 22, HW }, [63] = { 22, 23, HW },
				[64] = { 30, 31, HW }, [65] = { 31, 32, HW }, [66] = { 32, 33, HW },
				-- ramps leave / join the carriageways tangentially and meet the cross road square
				[71] = { 21, 2, HW, N, N }, [72] = { 2, 22, HW, N, N }, [73] = { 31, 3, HW, S, S }, [74] = { 3, 32, HW, S, S } }, mirror)
		for _, t in ipairs({ 2, 3 }) do
			local r = Slip.plan(W, t, function() return {} end)
			eq(r.view.case, "X", "terminal " .. t .. m)
			eq(#r.view.bypassed, 0, "terminal " .. t .. " no bypass" .. m)
			check(r.view, r.conns, "terminal " .. t .. m)
		end
	end
end)

test("bypass review: Channelized X slip angles 40-80 deg and unequal set-backs are still bypasses", function()
	for _, angle in ipairs({ 40, 50, 65, 80 }) do
		for _, sb in ipairs({ { 40, 35 }, { 60, 30 }, { 30, 55 } }) do
			for _, mirror in ipairs({ false, true }) do
				local msg = string.format("%d deg Lm %d Ls %d%s", angle, sb[1], sb[2], mirror and " LHT" or "")
				local r = Slip.plan(F.channelX({ angle = angle, Lm = sb[1], Ls = sb[2], mirror = mirror }), 1, function() return {} end)
				eq(table.concat(r.view.bypassed, ","), "11>15,13>17,15>13,17>11", msg)
				check(r.view, r.conns, msg)
			end
		end
	end
end)

test("bypass review: cost of a Channelized X centre (printed), reads bounded", function()
	local W = F.channelX({ main = TPL[3], side = TPL[3] })
	local nodeReads, segReads = 0, 0
	local wn, ws = W.node, W.seg
	W.node = function(id) nodeReads = nodeReads + 1 return wn(id) end
	W.seg = function(id) segReads = segReads + 1 return ws(id) end
	Slip.classify(W, 1)
	local withN, withS = nodeReads, segReads
	local keep = Cross.BYPASS_MAX_ROADS
	Cross.BYPASS_MAX_ROADS = 0
	nodeReads, segReads = 0, 0
	Slip.classify(W, 1)
	local baseN, baseS = nodeReads, segReads
	Cross.BYPASS_MAX_ROADS = keep
	W.node, W.seg = wn, ws
	local t0 = os.clock()
	for _ = 1, 200 do Slip.classify(W, 1) end
	local dt = (os.clock() - t0) / 200
	print(string.format("Channelized X centre classify: %.3f ms (%d node / %d seg reads; %d / %d without bypass walks)",
		dt * 1000, withN, withS, baseN, baseS))
	-- 4 walks in + 4 slip walks + 4 exit walks of one segment each here; far below the caps
	ok(withN - baseN <= 40 and withS - baseS <= 200, "bypass reads bounded")
end)

test("bypass review: allocate invariants for 1-6 lanes and every exit list left after bypasses", function()
	local lists = {
		{ "kerb", "straight", "far" }, { "kerb", "straight" }, { "straight", "far" }, { "kerb", "far" },
		{ "straight" }, { "far" }, { "kerb" }, { "straight", "far", "far" }, { "kerb", "kerb", "straight" },
	}
	for _, cats in ipairs(lists) do
		local st = nil
		for i, c in ipairs(cats) do if c == "straight" then st = i end end
		for N = 1, 6 do
			local msg = N .. " lanes " .. table.concat(cats, ",")
			local res = Cross.allocate(N, cats)
			local covered = {}
			for i = 1, N do
				local r = res[i]
				ok(r ~= nil and r[1] <= r[2] and r[1] >= 1 and r[2] <= #cats, msg .. " lane " .. i .. " range")
				if i > 1 then ok(res[i - 1][1] <= r[1] and res[i - 1][2] <= r[2], msg .. " lanes " .. (i - 1) .. "/" .. i .. " uncrossed") end
				for e = r[1], r[2] do covered[e] = true end
			end
			for e = 1, #cats do ok(covered[e], msg .. " exit " .. e .. " served") end
			if N >= 3 and cats[1] == "kerb" and #cats > 1 then eq(res[1][2], 1, msg .. ": kerb lane turns only") end
			if st and N >= 2 and N >= #cats and st >= #cats - 1 then
				-- one far turn at most: straight traffic keeps every lane but the kerb turns'
				for i = 1, N do
					if res[i][1] > 1 or cats[1] ~= "kerb" then ok(res[i][1] <= st and st <= res[i][2] or cats[res[i][1]] == "kerb", msg .. " lane " .. i .. " straight") end
				end
			end
		end
	end
end)

---------------------------------------------------------------------------
-- Shallow ramps (sl_cross X.shallowRamps; in game 2026-10-11): nothing turns across the opposing
-- carriageway into or out of a ramp running alongside the road; terminals keep their turns

local function connsFromTo(conns, a, b)
	local out = {}
	for _, c in ipairs(conns) do
		if c.withRoad and c.segment0 == a and c.segment1 == b then out[#out + 1] = c end
	end
	return out
end

test("shallow ramp with a two-way side road at the node: crossing rule, nothing across into or out of the ramp", function()
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and "LHT" or "RHT"
		-- ramp out (33) peeling off eastbound's kerb side; side road 13 north (the far side)
		local W = F.rampNode({ mirror = mirror, ramps = { { id = 33, leaving = true, tan = -80, far = -20 } },
			extra = { [13] = { 60, 0, 60, F.TPL.medium } } })
		local r = Slip.plan(W, 1, function() return {} end)
		local name = m .. " ramp out"
		eq(r.view.case, "X", name)
		eq(r.view.shape, "crossroads", name)
		eq(table.concat(r.view.shallowBlocked, ","), "12>33", name .. " blocked")
		check(r.view, r.conns, name)
		eq(#connsFromTo(r.conns, 12, 33), 0, name .. ": westbound never turns across into the ramp")
		ok(#connsFromTo(r.conns, 11, 33) > 0, name .. ": eastbound kerb lane into the ramp")
		-- the side road keeps the crossing rule: both ways along the road and into the ramp
		eq(#approach(r.view, 13).exits, 3, name .. ": side road keeps its turns")
		ok(#connsFromTo(r.conns, 13, 11) > 0 and #connsFromTo(r.conns, 13, 12) > 0, name .. ": side road turns")
		-- the eastbound approach keeps straight on and its turn into the side road
		eq(#approach(r.view, 11).exits, 3, name .. ": eastbound exits")
		ok(Rules.line("APPLY", Slip.logFields(r)):find(" shallow=12>33", 1, true), name .. " logged")

		-- ramp in (34) from behind on eastbound's kerb side: joins eastbound only, into its kerb lanes
		local Wi = F.rampNode({ mirror = mirror, ramps = { { id = 34, leaving = false, tan = -100, far = -160 } },
			extra = { [13] = { 60, 0, 60, F.TPL.medium } } })
		local ri = Slip.plan(Wi, 1, function() return {} end)
		name = m .. " ramp in"
		eq(ri.view.case, "X", name)
		check(ri.view, ri.conns, name)
		eq(table.concat(ri.view.shallowBlocked, ","), "34>11,34>13", name .. " blocked: the left turns across")
		local ap = approach(ri.view, 34)
		eq(#ap.exits, 1, name .. ": one exit")
		eq(ap.exits[1].seg, 12, name .. ": its own carriageway")
		eq(#connsFromTo(ri.conns, 34, 11) + #connsFromTo(ri.conns, 34, 13), 0, name .. ": no turn across the road")
		-- into eastbound's kerb lanes (kerb-aligned), as a merge
		local o = approach(ri.view, 11).exits
		local east = nil
		for _, ex in ipairs(o) do if ex.seg == 12 then east = ex end end
		local targets = {}
		for _, c in ipairs(connsFromTo(ri.conns, 34, 12)) do targets[#targets + 1] = c.lane1 end
		table.sort(targets)
		local kerb = { east.o[1], east.o[2] }
		table.sort(kerb)
		eq(table.concat(targets, ","), table.concat(kerb, ","), name .. ": kerb lanes")
		-- the side road (far side) still turns into eastbound and westbound
		eq(#approach(ri.view, 13).exits, 2, name .. ": side road keeps its turns")
	end
end)

test("shallow ramp on the far side (left exit / left merge on a two-way road): kept reachable, logged shallow_kept", function()
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and "LHT" or "RHT"
		-- out to the far side of eastbound at 30 deg: westbound would need a 150 deg hairpin
		local W = F.rampNode({ mirror = mirror, ramps = { { id = 33, leaving = true, tan = 30, far = 30, stub = 4 } } })
		local r = Slip.plan(W, 1, function() return {} end)
		local name = m .. " left exit"
		eq(r.view.case, "X", name)
		eq(r.view.slipReason, "far_side_branch", name)
		-- the far turn across westbound is the ramp's only feed: kept (reachability first)
		eq(#r.view.shallowBlocked, 0, name .. " nothing blocked")
		eq(table.concat(r.view.shallowKept, ","), "11>33", name .. " kept")
		check(r.view, r.conns, name)
		local into = connsFromTo(r.conns, 11, 33)
		ok(#into > 0, name .. ": eastbound reaches the ramp")
		-- only from eastbound's far lane, which also goes straight (the crossing rule's far turn lane)
		local ap = approach(r.view, 11)
		for _, c in ipairs(into) do eq(c.lane0, ap.m[#ap.m], name .. ": far lane into the ramp") end
		eq(#connsFromTo(r.conns, 12, 33), 0, name .. ": westbound never (a 150 deg hairpin)")
		ok(Rules.line("APPLY", Slip.logFields(r)):find(" shallow_kept=11>33", 1, true), name .. " logged")
		ok(Rules.line("APPLY", Slip.logFields(r)):find(" case=X via=far_side_branch side=", 1, true), name .. " via logged")
		-- joining from the far side of eastbound: only onto westbound (no crossing), sharp as it is
		local Wi = F.rampNode({ mirror = mirror, ramps = { { id = 34, leaving = false, tan = 150, far = 150, stub = 4 } } })
		local ri = Slip.plan(Wi, 1, function() return {} end)
		name = m .. " left merge"
		eq(ri.view.case, "X", name)
		check(ri.view, ri.conns, name)
		eq(#connsFromTo(ri.conns, 34, 12), 0, name .. ": never across westbound into eastbound")
		ok(#connsFromTo(ri.conns, 34, 11) > 0, name .. ": onto its own side's carriageway")
		eq(#ri.view.shallowKept, 0, name .. ": the near carriageway is a way on, nothing kept")
	end
end)

test("shallow ramps: Highway Interchange terminals (diamond S / M / L climb edges) keep their left turns", function()
	-- square_roundabouts_highway.lua: a diamond ramp meets the cross road square (tangent along the
	-- highway) and runs one Hermite edge to its gore beside the highway, 7 / 47 / 107 m along the
	-- cross road and 90 / 162 / 270 m along the highway away (S / M / L); its chord over the first 50 m
	-- is 85 / 78 / 80 deg off the cross road. Cross road along x here, the highway along y to the south.
	local HW = F.TPL.highway_small
	for _, size in ipairs({ { 7, 90 }, { 47, 162 }, { 107, 270 } }) do
		for _, mirror in ipairs({ false, true }) do
			local name = string.format("%s diamond %d/%d", mirror and "LHT" or "RHT", size[1], size[2])
			local N, S = { 0, 1 }, { 0, -1 }
			local W = F.build({ [1] = { 0, 0 }, [2] = { -100, 0 }, [3] = { 100, 0 },
				[4] = { -size[1], -size[2] }, [5] = { size[1], -size[2] } },
				{ [11] = { 1, 2, F.TPL.medium }, [12] = { 1, 3, F.TPL.medium },
					[14] = { 4, 1, HW, N, N }, [15] = { 1, 5, HW, S, S } }, mirror)
			local r = Slip.plan(W, 1, function() return {} end)
			eq(r.view.case, "X", name)
			check(r.view, r.conns, name)
			eq(#r.view.shallowBlocked, 0, name .. ": not shallow " .. table.concat(r.view.rampDeg or {}, ","))
			for _, d in ipairs(r.view.rampDeg or {}) do
				ok(tonumber(d:match(":(%d+)$")) >= 75, name .. " chord angle " .. d)
			end
			eq(#approach(r.view, 14).exits, 2, name .. ": off-ramp turns both ways")
			ok(#connsFromTo(r.conns, 11, 15) > 0 and #connsFromTo(r.conns, 12, 15) > 0, name .. ": both directions reach the on-ramp")
		end
	end
end)

test("three two-way roads and a one-way town street (review): a crossroads, keeps its lights, no shallow rule", function()
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and "LHT" or "RHT"
		for _, way in ipairs({ "in", "out" }) do
			local name = m .. " one-way street " .. way
			-- crossroads of medium streets; the south arm is a one-way street (sidewalks: no ramp)
			local W = compass({ { F.TPL.medium, "out" }, { F.TPL.medium, "out" }, { F.TPL.medium, "out" }, { ONE, way } }, mirror)
			local r = Slip.plan(W, 1, function() return {} end)
			eq(r.status, "apply", name)
			eq(r.view.case, "X", name)
			eq(r.view.shape, "crossroads", name)
			eq(r.view.rampDeg, nil, name .. ": no ramp measured")
			eq(#r.view.shallowBlocked, 0, name)
			ok(Lights.keepsLights(r.view.case), name .. ": keeps the game's lights")
			check(r.view, r.conns, name)
			eq(#approach(r.view, 11).exits, way == "out" and 3 or 2, name .. ": east approach exits")
			ok(Rules.line("APPLY", Slip.logFields(r)):find(" case=X via=three_two_way side=", 1, true), name .. " via logged")
		end
		-- a one-way town street peeling off a road alongside it is no ramp (sidewalks): crossing rule, all turns
		local W = F.rampNode({ mirror = mirror, ramps = { { id = 33, leaving = true, tan = -30, far = -20, tpl = F.TPL.one_way_small } },
			extra = { [13] = { 60, 0, 60, F.TPL.medium } } })
		local r = Slip.plan(W, 1, function() return {} end)
		eq(r.view.case, "X", m .. " shallow one-way street")
		eq(r.view.rampDeg, nil, m .. " shallow one-way street: not measured")
		eq(#r.view.shallowBlocked, 0, m .. " shallow one-way street: nothing blocked")
		check(r.view, r.conns, m .. " shallow one-way street")
	end
end)

test("shallow ramp guard: a joining ramp whose every move is blocked keeps them (stubbed shallowRamps)", function()
	-- no real layout blocks every move of a joining ramp (its own carriageway is always a way on), so
	-- X.shallowRamps is stubbed to name a carriageway that is not at the node
	local real = Cross.shallowRamps
	for _, mirror in ipairs({ false, true }) do
		local name = mirror and "LHT" or "RHT"
		Cross.shallowRamps = function()
			return { a = 11, b = 12, measured = { "34:20" }, deg = { [34] = 20 },
				ramps = { [34] = { leaving = false, deg = 20, side = mirror and 1 or -1, from = 11, to = 999, forward = true } },
				sideOf = function() return 0 end }
		end
		local W = F.rampNode({ mirror = mirror, ramps = { { id = 34, leaving = false, tan = -100, far = -160, stub = 4 } },
			extra = { [13] = { 60, 0, 60, F.TPL.medium } } })
		local ok2, v = pcall(Cross.classify, W, 1, (function()
			local roads = {}
			for _, sid in ipairs(W.node(1).segs) do
				local la = Ring.lanesAt(W.seg(sid), 1)
				roads[#roads + 1] = { sid = sid, la = la, twoWay = #la.incoming > 0 and #la.outgoing > 0 }
			end
			return roads
		end)())
		Cross.shallowRamps = real
		ok(ok2, name .. " " .. tostring(v))
		eq(v.kind, "slip", name)
		eq(#approach(v, 34).exits, 3, name .. ": every move kept")
		eq(table.concat(v.shallowKept, ","), "34>11,34>12,34>13", name .. " kept")
		eq(#v.shallowBlocked, 0, name .. " nothing blocked")
		check(v, Cross.roadConns(v), name)
	end
	Cross.shallowRamps = real
end)

---------------------------------------------------------------------------
-- Never squeeze lanes inside a junction (sl_cross X.allocateView; user report 2026-10-11 at
-- square_roundabouts' interchange: "4 lanes turning into 1")

--- Lane spec of a road drawn from node 1 out: `inN` lanes arriving at node 1, `outN` leaving it
-- (0: a one-way road); sidewalks (a town road, no ramp) unless `ramp`.
local function roadSpec(inN, outN, ramp)
	local edge = ramp and "-" or "S"
	local t = { "B" .. edge }
	for _ = 1, inN do t[#t + 1] = "BV" end
	for _ = 1, outN do t[#t + 1] = "FV" end
	t[#t + 1] = "F" .. edge
	return table.concat(t, " ")
end

--- The squeeze metric of a case X view and its connections: per exit road the feeders (incoming
-- lanes) of every movement and the most feeders on one exit lane. Asserts: a movement's block
-- never wider than its exit road unless its approach has more lanes than all its exits (fold);
-- no exit lane fed by two lanes while the exit road has room for every feeder; the most feeders
-- per exit lane never above what the feeders force (ceil(feeders / lanes)); and a road with more
-- feeders than lanes only where every turn block into it is one lane or its approach has no exit
-- with room left. Returns the most feeders on one exit lane over the node.
local function squeezeCheck(v, conns, msg)
	local feed, load = {}, {} -- feed[ap][exit seg] = {lane = true}; load[exit seg:lane] = {in seg:lane = true}
	local width, cat, outLanes = {}, {}, {}
	for _, ap in ipairs(v.approaches) do
		feed[ap.seg] = {}
		for _, ex in ipairs(ap.exits) do
			width[ex.seg], feed[ap.seg][ex.seg], outLanes[ex.seg] = #ex.o, {}, ex.o
			cat[ap.seg .. ">" .. ex.seg] = ex.cat
		end
	end
	for _, c in ipairs(conns) do
		if c.withRoad and feed[c.segment0] and feed[c.segment0][c.segment1] then
			feed[c.segment0][c.segment1][c.lane0] = true
			local k = c.segment1 .. ":" .. c.lane1
			load[k] = load[k] or {}
			load[k][c.segment0 .. ":" .. c.lane0] = true
		end
	end
	local function count(t)
		local n = 0
		for _ in pairs(t) do n = n + 1 end
		return n
	end
	local total, maxLoad = {}, {}
	for _, ap in ipairs(v.approaches) do
		local room = 0
		for _, ex in ipairs(ap.exits) do room = room + #ex.o end
		for _, ex in ipairs(ap.exits) do
			local f = count(feed[ap.seg][ex.seg])
			total[ex.seg] = (total[ex.seg] or 0) + f
			ok(f <= #ex.o or #ap.m > room, string.format("%s: %d lanes of %d into %d-lane exit %d (exits hold %d)", msg, f, ap.seg, #ex.o, ex.seg, room))
		end
	end
	local worst = 1
	for sid, M in pairs(width) do
		local m = 0
		for _, l in ipairs(outLanes[sid]) do m = math.max(m, count(load[sid .. ":" .. l] or {})) end
		maxLoad[sid] = m
		worst = math.max(worst, m)
		local T = total[sid]
		ok(m <= math.max(1, math.ceil(T / M)), string.format("%s exit %d: %d feeders on one lane, %d feeders into %d lanes", msg, sid, m, T, M))
		if T > M then
			-- turn blocks first: a wider turn block into this road only where its approach is stuck
			for _, ap in ipairs(v.approaches) do
				local f = count(feed[ap.seg][sid] or {})
				local c = cat[ap.seg .. ">" .. sid]
				if c and c ~= "straight" and f > 1 then
					for _, ex in ipairs(ap.exits) do
						if ex.seg ~= sid then
							local fy = count(feed[ap.seg][ex.seg])
							ok(fy >= #ex.o or total[ex.seg] >= #ex.o, string.format("%s: %d's %s turn into %d keeps %d lanes while exit %d has room (%d of %d, road %d)",
								msg, ap.seg, c, sid, f, ex.seg, fy, #ex.o, total[ex.seg]))
						end
					end
				end
			end
		end
	end
	return worst, maxLoad
end

--- Lanes of approach `seg` (positions, kerb first) that reach exit road `to`.
local function lanesInto(v, conns, seg, to)
	local ap = approach(v, seg)
	local pos, out = {}, {}
	for i, l in ipairs(ap.m) do pos[l] = i end
	for _, c in ipairs(conns) do
		if c.withRoad and c.segment0 == seg and c.segment1 == to then out[pos[c.lane0]] = true end
	end
	local list = {}
	for i = 1, #ap.m do if out[i] then list[#list + 1] = i end end
	return table.concat(list, ",")
end

--- Summary of the view under the rule on counts alone (X.allocate without caps): what the junction
-- got before the lane counts of the exits capped it.
local function uncappedSummary(v)
	local saved = {}
	for i, ap in ipairs(v.approaches) do
		saved[i] = ap.lanes
		local cats = {}
		for e, ex in ipairs(ap.exits) do cats[e] = ex.cat end
		ap.lanes = Cross.allocate(#ap.m, cats)
	end
	local s = Cross.summary(v)
	for i, ap in ipairs(v.approaches) do ap.lanes = saved[i] end
	return s
end

test("no squeeze: a 4-lane approach whose turn exit has 1 lane turns from 1 lane only", function()
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		-- T: main road 4+4 east-west (11 west, 12 east), side road 1+1 north (13)
		local W = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } },
			{ [11] = { 1, 2, roadSpec(4, 4) }, [12] = { 1, 3, roadSpec(4, 4) }, [13] = { 1, 4, roadSpec(1, 1) } }, mirror)
		local r = Slip.plan(W, 1, function() return {} end)
		check(r.view, r.conns, "T 4+4 / 1+1" .. m)
		squeezeCheck(r.view, r.conns, "T 4+4 / 1+1" .. m)
		for _, seg in ipairs({ 11, 12 }) do
			local into = lanesInto(r.view, r.conns, seg, 13)
			ok(into == "1" or into == "4", "T approach " .. seg .. ": one lane turns into the 1-lane side road, got " .. into .. m)
		end
		-- a 1-lane straight exit: the rule on counts alone sent all 4 lanes straight into it
		-- (s|s|s|sf); now 1 lane goes straight, 3 turn into the 4-lane side road
		local T1 = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } },
			{ [11] = { 1, 2, roadSpec(4, 1) }, [12] = { 1, 3, roadSpec(1, 1) }, [13] = { 1, 4, roadSpec(1, 4) } }, mirror)
		local r1 = Slip.plan(T1, 1, function() return {} end)
		check(r1.view, r1.conns, "T 4 into 1 straight" .. m)
		squeezeCheck(r1.view, r1.conns, "T 4 into 1 straight" .. m)
		eq(#r1.view.squeeze, 0, "T 4 into 1 straight: nothing folded" .. m)
		eq(#lanesInto(r1.view, r1.conns, 11, 12):gsub(",", ""), 1, "T: one lane straight into the 1-lane road" .. m)
		eq(uncappedSummary(r1.view):match("^11:[^;]+"), "11:s|s|s|sf", "before" .. m)
		eq(Cross.summary(r1.view):match("^11:[^;]+"), "11:s|f|f|f", "after" .. m)
		-- crossroads: main 4+4, side roads 1+1: one lane per turn, the rest straight
		local X4 = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } },
			{ [11] = { 1, 2, roadSpec(4, 4) }, [12] = { 1, 3, roadSpec(4, 4) }, [13] = { 1, 4, roadSpec(1, 1) }, [14] = { 1, 5, roadSpec(1, 1) } }, mirror)
		local rx = Slip.plan(X4, 1, function() return {} end)
		check(rx.view, rx.conns, "X 4+4 / 1+1" .. m)
		squeezeCheck(rx.view, rx.conns, "X 4+4 / 1+1" .. m)
		local ap = approach(rx.view, 11)
		eq(Cross.summary(rx.view):match("^11:[^;]+"), "11:k|s|s|sf", "X: kerb lane turns, far lane shares straight" .. m)
		eq(lanesInto(rx.view, rx.conns, 11, ap.exits[1].seg), "1", "X: one lane into the kerb turn" .. m)
		eq(lanesInto(rx.view, rx.conns, 11, ap.exits[3].seg), "4", "X: one lane into the far turn" .. m)
		-- a 4-lane side road (one-way in) whose turn exits have 1 lane each and no straight: folded,
		-- logged; 4 lanes into a 1-lane turn never happens while the other turn has room
		local T3 = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } },
			{ [11] = { 1, 2, roadSpec(1, 3) }, [12] = { 1, 3, roadSpec(1, 1) }, [13] = { 4, 1, F.TPL.one_way_medium } }, mirror)
		local r3 = Slip.plan(T3, 1, function() return {} end)
		check(r3.view, r3.conns, "one-way 4 into 3 + 1" .. m)
		squeezeCheck(r3.view, r3.conns, "one-way 4 into 3 + 1" .. m)
		eq(#r3.view.squeeze, 0, "4 lanes fit 3 + 1 exit lanes" .. m)
	end
end)

--- The user's T-junctions at square_roundabouts' interchange (log 2026-10-12): a two-way 3+3 road
-- (stem), a 4-lane one-way road in and a 4-lane one-way road out (lane counts from the log: default
-- model 19 connections = 4 x 4 + 3). `turned`: the layout rotated by 180 degrees (node 128948).
local function userT(ids, turned, mirror)
	local s = turned and -1 or 1
	local nodes = { [1] = { 0, 0 }, [2] = { -60 * s, 0 }, [3] = { 40 * s, 60 * s }, [4] = { 40 * s, -60 * s } }
	local segs = {
		[ids.stem] = { 1, 2, F.TPL.large },
		[ids.inn] = { 3, 1, F.TPL.one_way_medium },
		[ids.out] = { 1, 4, F.TPL.one_way_medium },
	}
	return F.build(nodes, segs, mirror)
end

test("no squeeze: the user's T-junctions 128660 / 128948 (3-lane stem, 4-lane one-way in and out)", function()
	local layouts = {
		{ node = "128660", ids = { stem = 128641, inn = 128645, out = 128662 }, turned = false,
			before = "128641:k|k|k;128645:k|f|f|f", after = "128641:k|k|k;128645:k|k|k|f" },
		{ node = "128948", ids = { stem = 128652, inn = 128643, out = 128953 }, turned = true,
			before = "128643:k|f|f|f;128652:k|k|k", after = "128643:k|k|k|f;128652:k|k|k" },
	}
	for _, L in ipairs(layouts) do
		for _, mirror in ipairs({ false, true }) do
			local msg = L.node .. (mirror and " LHT" or "")
			local W = userT(L.ids, L.turned, mirror)
			local r = Slip.plan(W, 1, function() return {} end)
			eq(r.view.case, "X", msg)
			eq(r.view.slipReason, "one_way_square", msg .. " via")
			eq(r.view.shape, "t_junction", msg)
			eq(#Slip.defaultConns(r.view), 19, msg .. ": the game's 19 connections, as logged")
			eq(uncappedSummary(r.view), L.before, msg .. ": the rule on counts alone (as logged)")
			eq(Cross.summary(r.view), L.after, msg)
			check(r.view, r.conns, msg)
			local worst = squeezeCheck(r.view, r.conns, msg)
			eq(worst, 1, msg .. ": every exit lane fed by one lane")
			eq(#r.view.squeeze, 0, msg .. ": nothing folded")
			-- the stem's 3 lanes into the out road's kerb lanes 1-3, the one-way's far lane into its lane 4
			local out = approach(r.view, L.ids.inn).exits
			local far = out[#out]
			eq(far.seg, L.ids.out, msg .. ": far turn into the out road")
			eq(lanesInto(r.view, r.conns, L.ids.inn, L.ids.out), "4", msg .. ": one far lane")
			eq(lanesInto(r.view, r.conns, L.ids.inn, L.ids.stem), "1,2,3", msg .. ": three kerb lanes into the stem")
			eq(lanesInto(r.view, r.conns, L.ids.stem, L.ids.out), "1,2,3", msg .. ": the stem turns from every lane")
		end
	end
end)

test("unavoidable squeeze: lanes beyond every exit's lanes fold minimally and are logged", function()
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		-- the user's T with a 2-lane out road and a 1-lane road in: the stem's 3 lanes have only
		-- the out road (2 lanes): 1 lane folded
		local W = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 40, 60 }, [4] = { 40, -60 } },
			{ [11] = { 1, 2, F.TPL.large }, [12] = { 3, 1, F.TPL.one_way_town1 }, [13] = { 1, 4, F.TPL.one_way_small } }, mirror)
		local r = Slip.plan(W, 1, function() return {} end)
		check(r.view, r.conns, "3 into 2" .. m)
		eq(table.concat(r.view.squeeze, ","), "11:1", "3 into 2" .. m)
		ok(Rules.line("APPLY", Slip.logFields(r)):find(" squeeze=11:1", 1, true), "logged" .. m)
		local worst = squeezeCheck(r.view, r.conns, "3 into 2" .. m)
		eq(worst, 2, "3 + 1 feeders into 2 lanes: 2 per lane" .. m)
		-- a 4-lane one-way road ending at a 1+1 road: 2 lanes per 1-lane exit, never 3 + 1
		local T = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } },
			{ [11] = { 1, 2, F.TPL.small }, [12] = { 1, 3, F.TPL.small }, [13] = { 4, 1, F.TPL.one_way_medium } }, mirror)
		local rt = Slip.plan(T, 1, function() return {} end)
		check(rt.view, rt.conns, "4 into 1 + 1" .. m)
		eq(table.concat(rt.view.squeeze, ","), "13:2", "4 into 1 + 1" .. m)
		eq(Cross.summary(rt.view):match("13:[^;]+"), "13:k|k|f|f", "spread over both exits" .. m)
		squeezeCheck(rt.view, rt.conns, "4 into 1 + 1" .. m)
		ok(not Rules.line("APPLY", Slip.logFields(Slip.plan(crossing(2, 2), 1, function() return {} end))):find("squeeze=", 1, true), "2x2: no squeeze")
	end
	-- allocate with caps: blocks capped, the rest by priority, folding only beyond the caps' total
	local KSF = { "kerb", "straight", "far" }
	eq(rangesText(Cross.allocate(4, KSF, { 1, 2, 4 })), "1-1 2-2 2-2 3-3", "straight full: the rest to the far turn, no share")
	eq(rangesText(Cross.allocate(4, KSF, { 3, 1, 1 })), "1-1 1-1 2-2 3-3", "straight and far full: the kerb turn")
	eq(rangesText(Cross.allocate(3, { "straight", "far" }, { 2, 2 })), "1-1 1-1 2-2", "3 lanes, 2-lane straight: no share over its lanes")
	eq(rangesText(Cross.allocate(2, KSF, { 1, 1, 1 })), "1-1 2-3", "2 lanes, 1-lane straight: only the far lane goes straight")
	eq(rangesText(Cross.allocate(2, { "kerb", "straight" }, { 1, 1 })), "1-1 2-2", "2 lanes at a T into a 1-lane road: no share")
	local res, sq = Cross.allocate(5, { "kerb", "far" }, { 1, 2 })
	eq(rangesText(res) .. " / " .. sq, "1-1 2-2 2-2 2-2 2-2 / 2", "5 into 1 + 2: folded at the wider exit, 2 per lane")
end)

--- Exhaustive and sampled worlds: T and X of two-way roads (1-5 lanes in, 1-4 out per arm), and the
-- user's T / a carriageway crossing with one-way roads in (1-5) and out (1-4); both traffic sides.
test("no squeeze, exhaustive: invariants and the most feeders per exit lane over T and X shapes", function()
	local n, worst, shared = 0, 0, 0
	local function run(W, msg)
		local r = Slip.plan(W, 1, function() return {} end)
		if r.view.kind ~= "slip" then return end
		check(r.view, r.conns, msg)
		local w = squeezeCheck(r.view, r.conns, msg)
		worst = math.max(worst, w)
		if w > 1 then shared = shared + 1 end
		n = n + 1
	end
	local P = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } }
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		for a = 1, 5 do
			for b = 1, 4 do
				for c = 1, 5 do
					for d = 1, 4 do
						-- two-way: main a in / b out per arm, side c in / d out; T and X
						for _, t in ipairs({ true, false }) do
							local segs = { [11] = { 1, 2, roadSpec(a, b) }, [12] = { 1, 3, roadSpec(a, b) }, [13] = { 1, 4, roadSpec(c, d) } }
							if not t then segs[14] = { 1, 5, roadSpec(c, d) } end
							run(F.build(P, segs, mirror), string.format("%s %d+%d / %d+%d%s", t and "T" or "X", a, b, c, d, m))
						end
					end
				end
				-- the user's T: stem a in / b out, one-way in c (here: a 1-5 loop reused), out d
				for c = 1, 5 do
					for d = 1, 4 do
						local W = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 40, 60 }, [4] = { 40, -60 } },
							{ [11] = { 1, 2, roadSpec(a, b) }, [12] = { 3, 1, roadSpec(0, c) }, [13] = { 1, 4, roadSpec(0, d) } }, mirror)
						run(W, string.format("user T %d+%d in %d out %d%s", a, b, c, d, m))
						-- a carriageway crossing: two-way a/b east-west, one-way c in from the south, d out north
						local Xc = F.build(P, { [11] = { 1, 2, roadSpec(a, b) }, [12] = { 1, 3, roadSpec(a, b) },
							[13] = { 1, 4, roadSpec(0, d) }, [14] = { 5, 1, roadSpec(0, c) } }, mirror)
						run(Xc, string.format("carriageway X %d+%d in %d out %d%s", a, b, c, d, m))
					end
				end
			end
		end
		-- asymmetric arms (seeded): every arm its own counts
		local seed = 12345
		local function rnd(k)
			seed = (seed * 1103515245 + 12345) % 2147483648
			return 1 + math.floor(seed / 65536) % k
		end
		for i = 1, 400 do
			local segs = {}
			local arms = (i % 2 == 0) and 4 or 3
			for j = 1, arms do segs[10 + j] = { 1, j + 1, roadSpec(rnd(5), rnd(4)) } end
			run(F.build(P, segs, mirror), string.format("random %d%s", i, m))
		end
	end
	print(string.format("%d junctions; most feeders on one exit lane: %d; junctions with a shared exit lane: %d", n, worst, shared))
	ok(n >= 4000, "cases " .. n)
end)

test("squeeze review: X.allocate with caps, every exit list, caps 1-4, 1-7 lanes: ranges, caps, squeeze count", function()
	local lists = {
		{ "kerb", "straight", "far" }, { "kerb", "straight" }, { "straight", "far" }, { "kerb", "far" },
		{ "straight" }, { "far" }, { "kerb" },
	}
	local n = 0
	for _, cats in ipairs(lists) do
		local k = #cats
		local caps = {}
		local function each(e)
			if e > k then
				local total = 0
				for i = 1, k do total = total + caps[i] end
				for N = 1, 7 do
					local msg = N .. " lanes " .. table.concat(cats, ",") .. " caps " .. table.concat(caps, ",")
					local res, sq = Cross.allocate(N, cats, caps)
					local feeds = {}
					for i = 1, N do
						local r = res[i]
						ok(r ~= nil and r[1] >= 1 and r[1] <= r[2] and r[2] <= k, msg .. " lane " .. i .. " range")
						if i > 1 then ok(res[i - 1][1] <= r[1] and res[i - 1][2] <= r[2], msg .. " lanes " .. (i - 1) .. "/" .. i .. " uncrossed") end
						for x = r[1], r[2] do feeds[x] = (feeds[x] or 0) + 1 end
					end
					for x = 1, k do
						ok((feeds[x] or 0) >= 1, msg .. " exit " .. x .. " served")
						if N > 1 and sq == 0 then ok(feeds[x] <= caps[x], msg .. " exit " .. x .. " within its cap") end
					end
					eq(sq, N > 1 and math.max(0, N - total) or 0, msg .. " squeeze")
					if N >= 3 and k > 1 and cats[1] == "kerb" then eq(res[1][2], 1, msg .. ": kerb lane turns only") end
					n = n + 1
				end
				return
			end
			for c = 1, 4 do
				caps[e] = c
				each(e + 1)
			end
		end
		each(1)
	end
	ok(n >= 800, "cases " .. n)
end)

test("squeeze review: allocateView is bounded and deterministic; a cut-short reduction keeps the invariants; cost (printed)", function()
	local calls, real = 0, Cross.allocate
	Cross.allocate = function(...) calls = calls + 1 return real(...) end
	local P = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } }
	local PT = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 40, 60 }, [4] = { 40, -60 } }
	local most, mostAt, nodes = 0, "", 0
	local keep = Cross.MAX_REDUCE
	local function plan(pts, segs, mirror)
		return Slip.plan(F.build(pts, segs, mirror), 1, function() return {} end)
	end
	local function plans(pts, segs, mirror, msg)
		calls = 0
		local r1 = plan(pts, segs, mirror)
		if r1.view.kind ~= "slip" then return end
		nodes = nodes + 1
		local c = calls - #r1.view.approaches
		if c > most then most, mostAt = c, msg end
		local text = Rules.connsText(r1.conns)
		eq(Rules.connsText(plan(pts, segs, mirror).conns), text, msg .. ": same connections run to run")
		-- converged long before the cap: 8 steps give the same result
		Cross.MAX_REDUCE = 8
		eq(Rules.connsText(plan(pts, segs, mirror).conns), text, msg .. ": converged within 8 steps")
		-- the reduction cut short after one step: still valid (no crossing, every lane connected and fed)
		Cross.MAX_REDUCE = 1
		local r3 = plan(pts, segs, mirror)
		Cross.MAX_REDUCE = keep
		check(r3.view, r3.conns, msg .. " (MAX_REDUCE 1)")
	end
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		for a = 2, 5 do
			for b = 1, 4 do
				for c = 1, 5 do
					for d = 1, 4 do
						plans(P, { [11] = { 1, 2, roadSpec(a, b) }, [12] = { 1, 3, roadSpec(a, b) }, [13] = { 1, 4, roadSpec(c, d) },
							[14] = { 1, 5, roadSpec(c, d) } }, mirror, string.format("X %d+%d / %d+%d%s", a, b, c, d, m))
						plans(PT, { [11] = { 1, 2, roadSpec(a, b) }, [12] = { 3, 1, roadSpec(0, c) }, [13] = { 1, 4, roadSpec(0, d) } },
							mirror, string.format("user T %d+%d in %d out %d%s", a, b, c, d, m))
						plans(P, { [11] = { 1, 2, roadSpec(a, b) }, [12] = { 1, 3, roadSpec(c, d) }, [13] = { 1, 4, roadSpec(d + 1, a) },
							[14] = { 1, 5, roadSpec(b, c) } }, mirror, string.format("X asym %d %d %d %d%s", a, b, c, d, m))
					end
				end
			end
		end
	end
	Cross.allocate = real
	print(string.format("allocateView: %d junctions, at most %d re-allocations per node (%s); MAX_REDUCE %d", nodes, most, mostAt, keep))
	ok(most <= 8, "reductions far below the cap: " .. most)
	-- cost: a 4-way of 5-lane roads with 1-lane exits (every approach folds) and with 2- / 3-lane exits
	-- (the most reductions), classify and allocateView alone
	local out = {}
	for _, spec in ipairs({ { 5, 1, 5, 1 }, { 5, 2, 5, 2 }, { 5, 3, 1, 1 }, { 5, 4, 2, 1 } }) do
		local W = F.build(P, { [11] = { 1, 2, roadSpec(spec[1], spec[2]) }, [12] = { 1, 3, roadSpec(spec[1], spec[2]) },
			[13] = { 1, 4, roadSpec(spec[3], spec[4]) }, [14] = { 1, 5, roadSpec(spec[3], spec[4]) } })
		local v = Slip.plan(W, 1, function() return {} end).view
		local t0 = os.clock()
		for _ = 1, 1000 do Cross.allocateView(v) end
		local av = (os.clock() - t0)
		-- before: one uncapped X.allocate per approach (the rule on counts alone)
		t0 = os.clock()
		for _ = 1, 1000 do
			for _, ap in ipairs(v.approaches) do
				local cats = {}
				for e, ex in ipairs(ap.exits) do cats[e] = ex.cat end
				ap.lanes = Cross.allocate(#ap.m, cats)
			end
		end
		local old = (os.clock() - t0)
		t0 = os.clock()
		for _ = 1, 200 do Slip.plan(W, 1, function() return {} end) end
		local pl = (os.clock() - t0) / 200 * 1000
		out[#out + 1] = string.format("%d+%d / %d+%d: allocateView %.4f ms (uncapped loop %.4f ms), plan %.3f ms", spec[1], spec[2], spec[3], spec[4], av, old, pl)
		ok(av < 1, "allocateView well under a millisecond")
	end
	print("cost per node: " .. table.concat(out, "; "))
end)

test("squeeze review: Channelized X / T centres of every lane count: bypasses then caps, invariants hold", function()
	local n, bypassed = 0, 0
	for _, mirror in ipairs({ false, true }) do
		for a = 1, 4 do
			for b = 1, 3 do
				for c = 1, 4 do
					for d = 1, 3 do
						for _, mk in ipairs({ F.channelX, F.channelT }) do
							local W = mk({ main = roadSpec(a, b), side = roadSpec(c, d), mirror = mirror })
							local r = Slip.plan(W, 1, function() return {} end)
							local msg = string.format("%s %d+%d / %d+%d%s", mk == F.channelX and "channel X" or "channel T", a, b, c, d, mirror and " LHT" or "")
							if r.view.case == "X" and r.view.kind == "slip" then
								check(r.view, r.conns, msg)
								allFed(r.view, r.conns, msg)
								squeezeCheck(r.view, r.conns, msg)
								for _, ap in ipairs(r.view.approaches) do
									local f = {}
									for l = 1, #ap.m do
										local rg = ap.lanes[l]
										for e = rg[1], rg[2] do f[e] = true end
									end
									for e = 1, #ap.exits do ok(f[e], msg .. ": approach " .. ap.seg .. " feeds its exit " .. ap.exits[e].seg) end
								end
								if #r.view.bypassed > 0 then bypassed = bypassed + 1 end
								n = n + 1
							end
						end
					end
				end
			end
		end
	end
	print(string.format("%d Channelized centres, %d with bypassed turns", n, bypassed))
	ok(n >= 500 and bypassed >= n / 2, "cases " .. n .. ", bypassed " .. bypassed)
end)

test("ring review follow-up: X.isRamp and Rules.isRampSeg are one test; nil-safe", function()
	local W = F.build({ [1] = { 0, 0 }, [2] = { 60, 0 }, [3] = { 0, 60 }, [4] = { -60, 0 }, [5] = { 0, -60 } },
		{ [11] = { 1, 2, F.TPL.highway_ramp2 }, [12] = { 3, 1, F.TPL.one_way_town1 }, [13] = { 1, 4, F.TPL.small },
			[14] = { 1, 5, F.TPL.highway_small } })
	for sid, want in pairs({ [11] = true, [12] = false, [13] = false, [14] = true }) do
		local s = W.seg(sid)
		local la = Ring.lanesAt(s, 1)
		local r = { sid = sid, la = la, twoWay = #la.incoming > 0 and #la.outgoing > 0 }
		eq(Rules.isRampSeg(W, sid), want, "isRampSeg " .. sid)
		eq(Cross.isRamp(W, r), want, "isRamp " .. sid)
	end
	eq(Rules.isRampSeg(W, 99), false, "missing segment")
	eq(Rules.isRampSeg(W, nil), false, "nil segment id")
	eq(Cross.isRamp(W, { sid = 99, twoWay = false }), false, "missing road")
end)

---------------------------------------------------------------------------
-- Traffic lights decide the extra straight shares (user decision 2026-10-11, "keep where lights exist";
-- sl_cross X.allocateView, X.litOf; TESTING.md Y)

--- world with its lit state: "unknown" leaves world.lit out (fixtures), else world.lit(n) -> lit.
local function withLit(world, lit)
	if lit ~= "unknown" then world.lit = function() return lit end end
	return world
end

--- Distinct incoming lanes (seg:lane) feeding each exit road, from road connections.
local function feedersBySeg(conns)
	local set, n = {}, {}
	for _, c in ipairs(conns) do
		local k = c.segment0 .. ":" .. c.lane0
		set[c.segment1] = set[c.segment1] or {}
		if not set[c.segment1][k] then
			set[c.segment1][k] = true
			n[c.segment1] = (n[c.segment1] or 0) + 1
		end
	end
	return n
end

--- Unlit invariant: no approach keeps an extra straight share into a straight exit road that gets more
-- feeders than it has lanes.
local function noUnlitShare(v, conns, msg)
	local n = feedersBySeg(conns)
	for _, ap in ipairs(v.approaches) do
		if ap.extra ~= nil then
			for _, ex in ipairs(ap.exits) do
				if ex.cat == "straight" then
					ok((n[ex.seg] or 0) <= #ex.o, string.format("%s: approach %d keeps its share into %d (%d feeders, %d lanes)",
						msg, ap.seg, ex.seg, n[ex.seg] or 0, #ex.o))
				end
			end
		end
	end
end

--- Exit lanes fed by more than one approach.
local function sharedLanes(conns)
	local by, k = {}, 0
	for _, c in ipairs(conns) do
		local key = c.segment1 .. ":" .. c.lane1
		by[key] = by[key] or {}
		by[key][c.segment0] = true
	end
	for _, aps in pairs(by) do
		local m = 0
		for _ in pairs(aps) do m = m + 1 end
		if m > 1 then k = k + m - 1 end
	end
	return k
end

local function logged(r, key)
	return Rules.line("APPLY", Slip.logFields(r)):match(" " .. key .. "=(%S+)")
end

test("lights: allocate's extra straight share (third result) and noShare", function()
	local KSF = { "kerb", "straight", "far" }
	local function both(N, cats, caps)
		local res, sq, extra = Cross.allocate(N, cats, caps)
		local res2, sq2, extra2 = Cross.allocate(N, cats, caps, true)
		return rangesText(res), extra, rangesText(res2), extra2, sq, sq2
	end
	local a, e, b, e2 = both(3, KSF)
	eq({ a, e, b, e2 }, { "1-1 2-2 2-3", 3, "1-1 2-2 3-3", nil }, "3 lanes: the far lane's share")
	a, e, b, e2 = both(4, KSF)
	eq({ a, e, b, e2 }, { "1-1 2-2 2-2 2-3", 4, "1-1 2-2 2-2 3-3", nil }, "4 lanes")
	a, e, b, e2 = both(2, { "kerb", "straight" })
	eq({ a, e, b, e2 }, { "1-2 2-2", 1, "1-1 2-2", nil }, "2 lanes at a T: the kerb lane's share")
	a, e, b, e2 = both(2, { "straight", "far" })
	eq({ a, e, b, e2 }, { "1-1 1-2", 2, "1-1 2-2", nil }, "2 lanes at a T: the far lane's share")
	a, e, b, e2 = both(3, { "straight", "far" })
	eq({ a, e, b, e2 }, { "1-1 1-1 1-2", 3, "1-1 1-1 2-2", nil }, "Channelized X approach: s|s|sf / s|s|f")
	-- no extra share: fewer lanes than exits (their own movements share), 1 lane, no straight, a full straight
	a, e, b, e2 = both(2, KSF)
	eq({ a, e, b, e2 }, { "1-2 2-3", nil, "1-2 2-3", nil }, "2 lanes, 3 exits: shared as before")
	a, e, b, e2 = both(1, KSF)
	eq({ a, e, b, e2 }, { "1-3", nil, "1-3", nil }, "1 lane: everything")
	a, e, b, e2 = both(3, { "kerb", "far" })
	eq({ a, e, b, e2 }, { "1-1 2-2 2-2", nil, "1-1 2-2 2-2", nil }, "no straight exit")
	a, e, b, e2 = both(3, { "straight", "far" }, { 2, 2 })
	eq({ a, e, b, e2 }, { "1-1 1-1 2-2", nil, "1-1 1-1 2-2", nil }, "straight full")
	-- every lane count and exit list: noShare equals the shared result without its extra lane
	local lists = { KSF, { "kerb", "straight" }, { "straight", "far" }, { "straight" }, { "kerb", "kerb", "straight", "far" } }
	for N = 1, 6 do
		for _, cats in ipairs(lists) do
			local res, sq, extra = Cross.allocate(N, cats)
			local res2, sq2, extra2 = Cross.allocate(N, cats, nil, true)
			eq(sq, sq2)
			eq(extra2, nil)
			for i = 1, N do
				if i ~= extra then eq(res2[i], res[i], N .. " lane " .. i) end
			end
			if extra ~= nil then
				ok(res[extra][1] < res[extra][2] and res2[extra][1] == res2[extra][2], N .. " extra lane " .. extra .. " back to one exit")
			end
		end
	end
end)

test("lights: lit and unknown keep the shares, unlit drops them; T and X of 1-3 lanes, both sides", function()
	-- unlit summaries where they differ from lit (segments: 11 west, 12 east, 13 north, 14 south)
	local UNLIT = {
		["13X"] = "11:ksf;12:ksf;13:k|s|f;14:k|s|f",
		["21T"] = "11:s|f;12:k|s;13:kf", ["22T"] = "11:s|f;12:k|s;13:k|f", ["23T"] = "11:s|f;12:k|s;13:k|f|f",
		["23X"] = "11:ks|sf;12:ks|sf;13:k|s|f;14:k|s|f",
		["31T"] = "11:s|s|f;12:k|s|s;13:kf", ["31X"] = "11:k|s|f;12:k|s|f;13:ksf;14:ksf",
		["32T"] = "11:s|s|f;12:k|s|s;13:k|f", ["32X"] = "11:k|s|f;12:k|s|f;13:ks|sf;14:ks|sf",
		["33T"] = "11:s|s|f;12:k|s|s;13:k|f|f", ["33X"] = "11:k|s|f;12:k|s|f;13:k|s|f;14:k|s|f",
	}
	local UNSHARED = { ["13X"] = "13,14", ["21T"] = "11,12", ["22T"] = "11,12", ["23T"] = "11,12", ["23X"] = "13,14",
		["31T"] = "11", ["31X"] = "11,12", ["32T"] = "11", ["32X"] = "11,12", ["33T"] = "11", ["33X"] = "11,12,13,14" }
	local n = 0
	for main = 1, 3 do
		for side = 1, 3 do
			for _, t in ipairs({ false, true }) do
				for _, mirror in ipairs({ false, true }) do
					local key = main .. side .. (t and "T" or "X")
					local msg = key .. (mirror and " LHT" or "")
					local function run(lit)
						local w = withLit(crossing(main, side, { t = t, mirror = mirror }), lit)
						local r = Slip.plan(w, 1, function() return {} end)
						check(r.view, r.conns, msg .. " lit=" .. tostring(lit))
						return r
					end
					local u, y, no = run("unknown"), run(true), run(false)
					eq(u.view.lit, nil, msg)
					eq(y.view.lit, true, msg)
					eq(no.view.lit, false, msg)
					eq(logged(u, "lit"), "unknown", msg)
					eq(logged(y, "lit"), "yes", msg)
					eq(logged(no, "lit"), "no", msg)
					-- lit = unknown = the rule as before
					eq(Rules.connsText(y.conns), Rules.connsText(u.conns), msg .. " lit = unknown")
					eq(logged(y, "unshared"), nil, msg)
					eq(logged(u, "unshared"), nil, msg)
					-- unlit: the pinned lanes, no share into an exit road over its lanes, never more shared lanes
					eq(Slip.summary(no.view), UNLIT[key] or Slip.summary(u.view), msg .. " unlit lanes")
					eq(logged(no, "unshared"), UNSHARED[key], msg .. " unshared=")
					eq(table.concat(no.view.unshared, ","), UNSHARED[key] or "", msg)
					noUnlitShare(no.view, no.conns, msg)
					ok(sharedLanes(no.conns) <= sharedLanes(u.conns), msg .. " shared lanes never grow")
					if UNLIT[key] then ok(sharedLanes(no.conns) < sharedLanes(u.conns), msg .. " fewer shared lanes") end
					-- the 2x2 / 1-lane shares between an approach's own movements stay; the Reset model is unchanged
					eq(Rules.connsText(Slip.defaultConns(no.view)), Rules.connsText(Slip.defaultConns(u.view)), msg .. " default model")
					n = n + 1
				end
			end
		end
	end
	eq(n, 36, "cases")
end)

test("lights: the Channelized X / T centre keeps s|s|sf when lit; unlit no shared exit lane where roads allow", function()
	for _, mirror in ipairs({ false, true }) do
		for main = 1, 3 do
			for side = 1, 3 do
				local msg = string.format("X %dx%d%s", main, side, mirror and " LHT" or "")
				local function run(lit)
					local w = withLit(F.channelX({ main = TPL[main], side = TPL[side], mirror = mirror }), lit)
					local r = Slip.plan(w, 1, function() return {} end)
					check(r.view, r.conns, msg .. " lit=" .. tostring(lit))
					allFed(r.view, r.conns, msg .. " lit=" .. tostring(lit))
					eq(table.concat(r.view.bypassed, ","), "11>15,13>17,15>13,17>11", msg .. " bypassed")
					return r
				end
				local u, y, no = run("unknown"), run(true), run(false)
				eq(Rules.connsText(y.conns), Rules.connsText(u.conns), msg .. " lit = unknown")
				noUnlitShare(no.view, no.conns, msg)
				-- 2+ lanes everywhere: every exit lane has one approach feeding it (1-lane roads: forced shares)
				if main >= 2 and side >= 2 then eq(sharedLanes(no.conns), 0, msg .. " unlit: no shared exit lane") end
				ok(sharedLanes(y.conns) > 0, msg .. " lit: the far lane's straight share meets the far turn")
			end
		end
		-- the user's hand edit stays under lights; unlit the far lane turns only
		local function sum(lit)
			return Cross.summary(Slip.plan(withLit(F.channelX({ main = TPL[3], side = TPL[3], mirror = mirror }), lit), 1,
				function() return {} end).view)
		end
		eq(sum(true), "11:s|s|sf;13:s|s|sf;15:s|s|sf;17:s|s|sf", "3x3 lit: the hand edit")
		eq(sum("unknown"), sum(true), "3x3 unknown: as lit")
		eq(sum(false), "11:s|s|f;13:s|s|f;15:s|s|f;17:s|s|f", "3x3 unlit")
		-- Channelized T centre: the west approach (no slip lane) drops its share unlit
		for main = 2, 3 do
			local msg = string.format("T main %d%s", main, mirror and " LHT" or "")
			local rl = Slip.plan(withLit(F.channelT({ main = TPL[main], mirror = mirror }), true), 1, function() return {} end)
			local ru = Slip.plan(withLit(F.channelT({ main = TPL[main], mirror = mirror }), false), 1, function() return {} end)
			check(ru.view, ru.conns, msg)
			allFed(ru.view, ru.conns, msg)
			eq(table.concat(ru.view.unshared, ","), "13", msg)
			eq(Cross.summary(rl.view):match("13:[^;]+"), main == 2 and "13:s|sf" or "13:s|s|sf", msg .. " lit")
			eq(Cross.summary(ru.view):match("13:[^;]+"), main == 2 and "13:s|f" or "13:s|s|f", msg .. " unlit")
			noUnlitShare(ru.view, ru.conns, msg)
		end
	end
end)

test("lights: world.lit is read once per handled crossroads; a failing read is unknown; other cases never read", function()
	local calls = 0
	local w = crossing(3, 3)
	w.memo = {}
	w.lit = function(n)
		calls = calls + 1
		return false
	end
	local r1 = Slip.plan(w, 1, function() return {} end)
	Slip.plan(w, 1, function() return {} end)
	Slip.classify(w, 1)
	eq(calls, 1, "classify memo: one read")
	eq(r1.view.lit, false)
	-- a throwing or odd read is unknown (the rule as before)
	local w2 = crossing(3, 3)
	w2.lit = function() error("boom") end
	local r2 = Slip.plan(w2, 1, function() return {} end)
	eq(r2.view.lit, nil)
	eq(logged(r2, "lit"), "unknown")
	local w3 = crossing(3, 3)
	w3.lit = function() return "yes" end
	eq(Slip.plan(w3, 1, function() return {} end).view.lit, nil)
	-- slip nodes (case B) and skipped crossroads never read the light
	local reads = {}
	local X = F.channelX({ main = TPL[3] })
	X.lit = function(n)
		reads[#reads + 1] = n
		return true
	end
	for _, n in ipairs({ 1, 2, 3, 4, 8 }) do Slip.plan(X, n, function() return {} end) end
	eq(reads, { 1 }, "only the centre (case X)")
	-- an approach folding on its own and an unlit node: the loop stays bounded and deterministic
	local v1 = Slip.plan(withLit(crossing(3, 1, { t = true }), false), 1, function() return {} end)
	local v2 = Slip.plan(withLit(crossing(3, 1, { t = true }), false), 1, function() return {} end)
	eq(Rules.connsText(v1.conns), Rules.connsText(v2.conns), "deterministic")
end)

test("lights: unlit over the exhaustive T / X shapes: invariants, no squeeze, no share into a full exit road", function()
	local n, dropped = 0, 0
	local P = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } }
	for _, mirror in ipairs({ false, true }) do
		for a = 1, 4 do
			for b = 1, 3 do
				for c = 1, 4 do
					for d = 1, 3 do
						for _, t in ipairs({ true, false }) do
							local segs = { [11] = { 1, 2, roadSpec(a, b) }, [12] = { 1, 3, roadSpec(a, b) }, [13] = { 1, 4, roadSpec(c, d) } }
							if not t then segs[14] = { 1, 5, roadSpec(c, d) } end
							local msg = string.format("%s %d+%d / %d+%d%s unlit", t and "T" or "X", a, b, c, d, mirror and " LHT" or "")
							local r = Slip.plan(withLit(F.build(P, segs, mirror), false), 1, function() return {} end)
							if r.view.kind == "slip" then
								check(r.view, r.conns, msg)
								squeezeCheck(r.view, r.conns, msg)
								noUnlitShare(r.view, r.conns, msg)
								local u = Slip.plan(F.build(P, segs, mirror), 1, function() return {} end)
								ok(sharedLanes(r.conns) <= sharedLanes(u.conns), msg .. " shared lanes never grow")
								if #r.view.unshared > 0 then dropped = dropped + 1 end
								n = n + 1
							end
						end
					end
				end
			end
		end
	end
	eq(n, 576, "cases")
	ok(dropped > 100, "shares dropped at " .. dropped .. " nodes")
end)

---------------------------------------------------------------------------
-- Exit-lane fan (sl_exitfan zones only, a measuring mode; PLAN.md "Exit-lane fan (sl_exitfan zones)"): at a lit
-- node every turn fans over the exit lanes its game phase group leaves it, neighbours in one phase share
-- one boundary lane and never cross; the lane strings and the straights stay the rule's.

--- world lit and inside an sl_exitfan zone (world.exitFan); lit = false / "unknown" for the other cases.
local function withFan(world, lit)
	if lit ~= "unknown" then world.lit = function() return lit ~= false end end
	world.exitFan = function() return true end
	return world
end

--- "exit lane positions" per movement "approach>exit" of road connections, e.g. { ["11>13"] = "1,2" }.
local function exitLanes(v, conns)
	local pos = {}
	for _, ap in ipairs(v.approaches) do
		for _, ex in ipairs(ap.allExits or ap.exits) do
			for j, l in ipairs(ex.o) do pos[ex.seg .. ":" .. l] = j end
		end
	end
	local by = {}
	for _, c in ipairs(conns) do
		if c.withRoad then
			local k = c.segment0 .. ">" .. c.segment1
			by[k] = by[k] or {}
			by[k][pos[c.segment1 .. ":" .. c.lane1]] = true
		end
	end
	local out = {}
	for k, set in pairs(by) do
		local l = {}
		for p in pairs(set) do l[#l + 1] = p end
		table.sort(l)
		out[k] = table.concat(l, ",")
	end
	return out
end

--- The category of every movement of a view: { ["a>b"] = "kerb" | "straight" | "far" }.
local function catsOf(v)
	local cat = {}
	for _, ap in ipairs(v.approaches) do
		for _, ex in ipairs(ap.allExits or ap.exits) do cat[ap.seg .. ">" .. ex.seg] = ex.cat end
	end
	return cat
end

--- Same-phase invariant (v.exitFan): two connections of different approaches of one phase group into one
-- exit never cross (the kerb-side movement's lane is never farther out than the far-side one's).
-- Returns the number of exit lanes two movements of one phase share (merges).
local function noPhaseCross(v, conns, msg)
	ok(v.exitFan == true and v.phaseGroup ~= nil, msg .. " exitFan")
	local pos, rank = {}, { kerb = 1, straight = 2, far = 3 }
	for _, ap in ipairs(v.approaches) do
		for _, ex in ipairs(ap.allExits or ap.exits) do
			for j, l in ipairs(ex.o) do pos[ex.seg .. ":" .. l] = j end
		end
	end
	local cat = catsOf(v)
	local merges = {}
	for i, c in ipairs(conns) do
		for j = i + 1, #conns do
			local d = conns[j]
			if c.withRoad and d.withRoad and c.segment1 == d.segment1 and c.segment0 ~= d.segment0
				and v.phaseGroup[c.segment0] == v.phaseGroup[d.segment0] then
				local rc, rd = rank[cat[c.segment0 .. ">" .. c.segment1]], rank[cat[d.segment0 .. ">" .. d.segment1]]
				ok(rc ~= rd, msg .. " two movements of one category into one exit in one phase")
				local pc, pd = pos[c.segment1 .. ":" .. c.lane1], pos[d.segment1 .. ":" .. d.lane1]
				if rc > rd then pc, pd = pd, pc end
				ok(pc <= pd, string.format("%s: %s and %s cross in one phase", msg, Rules.connsText({ c }), Rules.connsText({ d })))
				if pc == pd then merges[c.segment1 .. ":" .. c.lane1] = true end
			end
		end
	end
	local n = 0
	for _ in pairs(merges) do n = n + 1 end
	return n
end

local function planOf(world) return Slip.plan(world, 1, function() return {} end) end

test("exit fan: 2x2 crossroads, kerb turn into both exit lanes, far turn into the far lane (20 connections)", function()
	for _, mirror in ipairs({ false, true }) do
		local msg = mirror and "LHT" or "RHT"
		local r = planOf(withFan(crossing(2, 2, { mirror = mirror })))
		local v = r.view
		eq(v.exitFan, true, msg)
		eq(Cross.summary(v), "11:ks|sf;12:ks|sf;13:ks|sf;14:ks|sf", msg .. " lane strings unchanged")
		check(v, r.conns, msg)
		eq(noPhaseCross(v, r.conns, msg), 4, msg .. " one merge lane per cross-road exit")
		eq(#r.conns, 20, msg .. " 4 x (2 straight + 2 kerb turn + 1 far turn)")
		local cat, lanes = catsOf(v), exitLanes(v, r.conns)
		for k, c in pairs(cat) do eq(lanes[k], c == "far" and "2" or "1,2", msg .. " " .. k .. " " .. c) end
		local kp = Slip.kerbPairs(v)
		eq(kp.kerbLaneOnly, true, msg .. " a freed kerb turn only into the kerb lane")
	end
end)

test("exit fan: 3x3 crossroads keeps k|s|sf and its straights; the turns share the middle exit lane", function()
	for _, mirror in ipairs({ false, true }) do
		for _, skew in ipairs({ 0, 30 }) do
			local msg = string.format("%s skew %d", mirror and "LHT" or "RHT", skew)
			local r = planOf(withFan(crossing(3, 3, { mirror = mirror, skew = skew })))
			local v = r.view
			local base = planOf(withLit(crossing(3, 3, { mirror = mirror, skew = skew }), true))
			eq(Cross.summary(v), Cross.summary(base.view), msg .. " lane strings unchanged")
			eq(Cross.summary(v), "11:k|s|sf;12:k|s|sf;13:k|s|sf;14:k|s|sf", msg)
			check(v, r.conns, msg)
			eq(noPhaseCross(v, r.conns, msg), 4, msg)
			eq(#r.conns, 24, msg .. " 4 x (2 straight + 2 + 2)")
			local cat, lanes, old = catsOf(v), exitLanes(v, r.conns), exitLanes(base.view, base.conns)
			for k, c in pairs(cat) do
				eq(lanes[k], ({ kerb = "1,2", straight = "2,3", far = "2,3" })[c], msg .. " " .. k)
				if c == "straight" then eq(lanes[k], old[k], msg .. " straight as before") end
			end
		end
	end
end)

test("exit fan: T 2x2, the main road's turns share the side road, the side road's turns take every lane", function()
	for _, mirror in ipairs({ false, true }) do
		local msg = mirror and "LHT" or "RHT"
		local r = planOf(withFan(crossing(2, 2, { t = true, mirror = mirror })))
		local v = r.view
		check(v, r.conns, msg)
		noPhaseCross(v, r.conns, msg)
		eq(v.phaseGroup[11], v.phaseGroup[12], msg .. " main road one phase")
		ok(v.phaseGroup[13] ~= v.phaseGroup[11], msg .. " side road its own")
		local cat, lanes = catsOf(v), exitLanes(v, r.conns)
		for k, c in pairs(cat) do
			local want = k:match("^13>") ~= nil and "1,2" or ({ kerb = "1,2", straight = "1,2", far = "2" })[c]
			eq(lanes[k], want, msg .. " " .. k .. " " .. c)
		end
		eq(Cross.summary(v), Cross.summary(planOf(withLit(crossing(2, 2, { t = true, mirror = mirror }), true)).view), msg)
	end
end)

test("exit fan: 3x2 crossroads, fans by exit width, lane strings and straights as before", function()
	for _, mirror in ipairs({ false, true }) do
		local msg = mirror and "LHT" or "RHT"
		local r = planOf(withFan(crossing(3, 2, { mirror = mirror })))
		local base = planOf(withLit(crossing(3, 2, { mirror = mirror }), true))
		local v = r.view
		eq(Cross.summary(v), Cross.summary(base.view), msg)
		check(v, r.conns, msg)
		noPhaseCross(v, r.conns, msg)
		local cat, lanes, old = catsOf(v), exitLanes(v, r.conns), exitLanes(base.view, base.conns)
		for k, c in pairs(cat) do
			local main = k:match("^1[12]>") ~= nil -- a main road approach turns into the 2-lane side road
			if c == "straight" then eq(lanes[k], old[k], msg .. " " .. k .. " straight as before")
			elseif main then eq(lanes[k], c == "kerb" and "1,2" or "2", msg .. " " .. k)
			else eq(lanes[k], c == "kerb" and "1,2" or "2,3", msg .. " " .. k) end
		end
	end
end)

test("exit fan off: outside the zone, unlit and unknown nodes the connections are exactly the rule's", function()
	local P = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } }
	local n = 0
	for _, mirror in ipairs({ false, true }) do
		for a = 1, 4 do
			for b = 1, 3 do
				for c = 1, 4 do
					for d = 1, 3 do
						for _, t in ipairs({ true, false }) do
							local segs = { [11] = { 1, 2, roadSpec(a, b) }, [12] = { 1, 3, roadSpec(a, b) }, [13] = { 1, 4, roadSpec(c, d) } }
							if not t then segs[14] = { 1, 5, roadSpec(c, d) } end
							local msg = string.format("%s %d+%d / %d+%d%s", t and "T" or "X", a, b, c, d, mirror and " LHT" or "")
							for _, lit in ipairs({ true, false, "unknown" }) do
								local base = planOf(withLit(F.build(P, segs, mirror), lit))
								-- a world outside every zone (world.exitFan false), and unlit / unknown inside one
								local w = withLit(F.build(P, segs, mirror), lit)
								w.exitFan = function() return false end
								eq(Rules.connsText(planOf(w).conns), Rules.connsText(base.conns), msg .. " outside lit=" .. tostring(lit))
								if lit ~= true then
									local z = planOf(withFan(F.build(P, segs, mirror), lit))
									eq(Rules.connsText(z.conns), Rules.connsText(base.conns), msg .. " zone lit=" .. tostring(lit))
									if z.view.kind == "slip" then
										eq(z.view.exitFanWhy, lit == false and "unlit" or "lit_unknown", msg)
										eq(Slip.kerbPairs(z.view).kerbLaneOnly, nil, msg)
									end
								end
								n = n + 1
							end
						end
					end
				end
			end
		end
	end
	eq(n, 1728)
	-- off the model inside the zone: a Y whose roads are not straight to each other keeps the rule
	local Y = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 40, 45 }, [4] = { 40, -45 } }
	local ys = { [11] = { 1, 2, TPL[2] }, [12] = { 1, 3, TPL[2] }, [13] = { 1, 4, TPL[2] } }
	local r = planOf(withFan(F.build(Y, ys)))
	if r.view.kind == "slip" then
		eq(r.view.exitFan, false, "Y junction")
		eq(r.view.exitFanWhy, "t_axis", "Y junction")
		eq(Rules.connsText(r.conns), Rules.connsText(planOf(withLit(F.build(Y, ys), true)).conns), "Y junction: the rule")
	end
end)

test("exit fan: every T / X of 1-4 lanes in and 1-3 out, both sides: invariants, no crossing in one phase", function()
	local n = 0
	local P = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } }
	for _, mirror in ipairs({ false, true }) do
		for a = 1, 4 do
			for b = 1, 3 do
				for c = 1, 4 do
					for d = 1, 3 do
						for _, t in ipairs({ true, false }) do
							local segs = { [11] = { 1, 2, roadSpec(a, b) }, [12] = { 1, 3, roadSpec(a, b) }, [13] = { 1, 4, roadSpec(c, d) } }
							if not t then segs[14] = { 1, 5, roadSpec(c, d) } end
							local msg = string.format("%s %d+%d / %d+%d%s exit fan", t and "T" or "X", a, b, c, d, mirror and " LHT" or "")
							local r = planOf(withFan(F.build(P, segs, mirror)))
							if r.view.kind == "slip" then
								local old = planOf(withLit(F.build(P, segs, mirror), true))
								eq(Cross.summary(r.view), Cross.summary(old.view), msg .. " lane strings unchanged")
								check(r.view, r.conns, msg)
								noPhaseCross(r.view, r.conns, msg)
								allFed(r.view, r.conns, msg)
								local cat, nl, ol = catsOf(r.view), exitLanes(r.view, r.conns), exitLanes(old.view, old.conns)
								-- feeders per movement, and the most of any movement per exit road: where a movement
								-- of several feeders shares a phase the fan may fold it rather than cross (compared
								-- only where every movement into the exit has one feeder)
								local fd, most = {}, {}
								for _, cn in ipairs(r.conns) do
									local k = cn.segment0 .. ">" .. cn.segment1
									fd[k] = fd[k] or {}
									fd[k][cn.lane0] = true
								end
								for k, set in pairs(fd) do
									local m = 0
									for _ in pairs(set) do m = m + 1 end
									local e = k:match(">(%d+)$")
									most[e] = math.max(most[e] or 0, m)
								end
								for k, cc in pairs(cat) do
									if nl[k] and ol[k] and most[k:match(">(%d+)$")] == 1 then
										local function cnt(s) return select(2, s:gsub(",", ",")) + 1 end
										if cc == "straight" then
											-- the straight's own lanes as before (a lane it leaves may be filled by it, as before)
											ok(cnt(nl[k]) >= cnt(ol[k]) - 1, msg .. " " .. k)
										else
											ok(cnt(nl[k]) >= cnt(ol[k]), msg .. " " .. k .. " " .. nl[k] .. " vs " .. ol[k])
										end
									end
								end
								n = n + 1
							end
						end
					end
				end
			end
		end
	end
	eq(n, 576, "cases")
end)

test("exit fan: placeExitLit ranges (kerb-side movement first, one shared boundary lane)", function()
	local function place(groups, M)
		local mvs = {}
		for i, g in ipairs(groups) do mvs[i] = { group = g, r = 1, kd = i, ap = { seg = i } } end
		Cross.placeExitLit(mvs, M)
		local out = {}
		for _, mv in ipairs(mvs) do out[#out + 1] = mv.group:sub(1, 1) .. mv.lo .. "-" .. mv.hi end
		return table.concat(out, " ")
	end
	eq(place({ "kerb", "far" }, 1), "k1-1 f1-1")
	eq(place({ "kerb", "far" }, 2), "k1-2 f2-2")
	eq(place({ "kerb", "far" }, 3), "k1-2 f2-3")
	eq(place({ "kerb", "far" }, 4), "k1-3 f3-4")
	eq(place({ "far" }, 3), "f1-3")
	eq(place({ "kerb", "straight", "far" }, 3), "k1-2 s2-3 f3-3")
	eq(place({ "kerb", "straight", "far" }, 2), "k1-1 s1-2 f2-2")
	-- a far block of 2 feeders into 3 lanes: blocks, the far-most feeder takes the spare lane
	local mv = { { group = "far", r = 2, kd = 1, ap = { seg = 1 } } }
	Cross.placeExitLit(mv, 3)
	eq(mv[1].map, { { 1, 1 }, { 2, 2 }, { 2, 3 } })
	-- a 2-feeder turn next to a 1-feeder one on 2 lanes: as many lanes as feeders first (no fold)
	mv = { { group = "kerb", r = 1, kd = 1, ap = { seg = 1 } }, { group = "far", r = 2, kd = 2, ap = { seg = 2 } } }
	Cross.placeExitLit(mv, 2)
	eq({ mv[1].lo, mv[1].hi, mv[2].lo, mv[2].hi }, { 1, 1, 1, 2 })
	-- straight: lane to lane from the far side, as X.mapLanes
	mv = { { group = "straight", r = 2, kd = 1, ap = { seg = 1 } } }
	Cross.placeExitLit(mv, 3)
	eq(mv[1].map, { { 2, 3 }, { 1, 2 } })
end)
