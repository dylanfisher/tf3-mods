-- square_smart_lanes: the junction audit (sl_audit.lua, TESTING.md X). Each finding type on a small fixture
-- (both traffic sides), the standard fixtures under the current rules (no avoidable squeeze / across /
-- ramp_ramp / unfed / dead / u_turn / bypassed_turn / weave; the shared exit lanes the crossroads rule makes
-- on purpose are pinned and reported), nil-safety, the caps, the log fields and the cost.

local Ring = ug_require "square_smart_lanes::/smart_lanes/sl_ring.lua"
local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Audit = ug_require "square_smart_lanes::/smart_lanes/sl_audit.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")

local TPL = { [1] = F.TPL.small, [2] = F.TPL.medium, [3] = F.TPL.large }
local SIDES = { false, true } -- right-hand traffic, left-hand (mirror)

--- Crossroads at node 1: main road west (11) / east (12), side road north (13) / south (14, not with t),
-- `main` / `side` lanes each way (all segments drawn from node 1 out).
local function crossing(main, side, mirror, t)
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 } }
	local segs = { [11] = { 1, 2, TPL[main] }, [12] = { 1, 3, TPL[main] }, [13] = { 1, 4, TPL[side] } }
	if not t then
		nodes[5] = { 0, -60 }
		segs[14] = { 1, 5, TPL[side] }
	end
	return F.build(nodes, segs, mirror)
end

--- The rule's connections at node n (no current connections).
local function plan(w, n)
	local r = Slip.plan(w, n, function() return {} end)
	return r.conns, r.view, r
end

--- Lane k (kerb first) of segment sid at node n: incoming or outgoing, for driving side `side`.
local function lane(w, n, sid, incoming, k, side)
	local la = Ring.lanesAt(w.seg(sid), n)
	return Slip.kerbFirst(incoming and la.incoming or la.outgoing, incoming, side)[k]
end

--- A road connection a:i -> b:j (kerb-first positions) at node n.
local function conn(w, n, side, a, i, b, j)
	return Rules.conn(a, lane(w, n, a, true, i, side), b, lane(w, n, b, false, j, side), true, false)
end

local function without(list, pred)
	local out = {}
	for _, c in ipairs(list) do if not pred(c) then out[#out + 1] = c end end
	return out
end

local function sideOf(mirror) return mirror and "left" or "right" end
local function tag(mirror) return mirror and " (left-hand)" or "" end

---------------------------------------------------------------------------
-- Each finding

test("squeeze: two lanes of one approach into one exit lane with room elsewhere; a lane drop is forced", function()
	for _, m in ipairs(SIDES) do
		local w = crossing(2, 2, m)
		local conns, v = plan(w, 1)
		eq(Audit.audit(w, 1, conns, { view = v }).counts.squeeze, nil, "the rule" .. tag(m))
		-- west approach: both lanes straight into the east road's kerb lane
		local bad = without(conns, function(c) return c.segment0 == 11 and c.segment1 == 12 end)
		bad[#bad + 1] = conn(w, 1, sideOf(m), 11, 1, 12, 1)
		bad[#bad + 1] = conn(w, 1, sideOf(m), 11, 2, 12, 1)
		local res = Audit.audit(w, 1, bad, { view = v })
		eq(res.counts.squeeze, 1, "avoidable" .. tag(m))
		ok(table.concat(res.detail, ","):find("squeeze:12", 1, true), table.concat(res.detail, ","))
		-- a road narrowing 3 -> 2: the drop folds one lane, forced
		local d = F.build({ [1] = { 0, 0 }, [2] = { -80, 0 }, [3] = { 80, 0 } },
			{ [21] = { 2, 1, F.TPL.large }, [22] = { 1, 3, F.TPL.medium } }, m)
		local dc, dv = plan(d, 1)
		eq(dv.case, "D")
		local dr = Audit.audit(d, 1, dc, { view = dv })
		eq(dr.counts.squeeze, nil, "lane drop" .. tag(m))
		eq(dr.forced.squeeze, 1, "lane drop forced" .. tag(m))
		eq(dr.total, 0)
	end
end)

test("shared: avoidable where the exit road has a lane per movement; forced where it has not", function()
	for _, m in ipairs(SIDES) do
		-- 2x2 T: the rule lets the main road's lane next to the straight exit go straight too, so it
		-- shares an exit lane with the side road's turn (by design: through traffic keeps both lanes)
		local w = crossing(2, 2, m, true)
		local conns, v = plan(w, 1)
		local res = Audit.audit(w, 1, conns, { view = v })
		eq(res.counts.shared, 2, "rule" .. tag(m))
		ok(table.concat(res.detail, ","):find("shared:12:fs", 1, true), table.concat(res.detail, ","))
		-- the west approach's far lane turns only: east exit lane 2 no longer shared
		local farLane = lane(w, 1, 11, true, 2, sideOf(m))
		local fewer = without(conns, function(c) return c.segment0 == 11 and c.lane0 == farLane and c.segment1 == 12 end)
		local r2 = Audit.audit(w, 1, fewer, { view = v })
		eq(r2.counts.shared, 1, "edited" .. tag(m))
		ok(not table.concat(r2.detail, ","):find("shared:12", 1, true), table.concat(r2.detail, ","))
		-- 1+1 crossroads: three movements into every 1-lane exit, forced
		local w1 = crossing(1, 1, m)
		local c1, v1 = plan(w1, 1)
		local r1 = Audit.audit(w1, 1, c1, { view = v1 })
		eq(r1.counts.shared, nil, "1+1" .. tag(m))
		eq(r1.forced.shared, 8, "1+1 forced" .. tag(m))
	end
end)

test("across: a move over the opposing carriageway into a shallow ramp", function()
	for _, m in ipairs(SIDES) do
		local w = F.rampNode({ mirror = m, ramps = { { id = 33, leaving = true, tan = -80, far = -20 },
			{ id = 34, leaving = false, tan = -100, far = -160 } } })
		local conns, v = plan(w, 1)
		eq(Audit.audit(w, 1, conns, { view = v }).counts.across, nil, "the rule" .. tag(m))
		-- the westbound approach (from 12) turns across the eastbound carriageway into the off-ramp 33
		local more = { table.unpack(conns) }
		more[#more + 1] = conn(w, 1, sideOf(m), 12, 3, 33, 1)
		local res = Audit.audit(w, 1, more, { view = v })
		eq(res.counts.across, 1, tag(m))
		ok(table.concat(res.detail, ","):find("across:12>33", 1, true), table.concat(res.detail, ","))
		-- a move the crossing rule kept (view.shallowKept: the exit road's only feed) is never across
		local kv = setmetatable({ shallowKept = { "12>33" } }, { __index = v })
		eq(Audit.audit(w, 1, more, { view = kv }).counts.across, nil, "kept" .. tag(m))
	end
end)

test("ramp_ramp: an off-ramp straight across onto the on-ramp while the road is there", function()
	for _, m in ipairs(SIDES) do
		local w = F.rampNode({ mirror = m, ramps = { { id = 33, leaving = true, tan = 90, far = 90 },
			{ id = 34, leaving = false, tan = -90, far = -90 } } })
		local conns, v = plan(w, 1)
		eq(v.case, "X", "a terminal: the crossing rule")
		local res = Audit.audit(w, 1, conns, { view = v })
		eq(res.counts.ramp_ramp, nil, "the rule never leads a ramp into a ramp" .. tag(m))
		local more = { table.unpack(conns) }
		more[#more + 1] = conn(w, 1, sideOf(m), 34, 1, 33, 1)
		local r2 = Audit.audit(w, 1, more, { view = v })
		eq(r2.counts.ramp_ramp, 1, tag(m))
		ok(table.concat(r2.detail, ","):find("ramp_ramp:34>33", 1, true))
	end
end)

test("u_turn: back onto its own segment, or a turn sharper than 135 deg", function()
	for _, m in ipairs(SIDES) do
		local w = crossing(2, 2, m)
		local conns, v = plan(w, 1)
		eq(Audit.audit(w, 1, conns, { view = v }).counts.u_turn, nil)
		local more = { table.unpack(conns) }
		more[#more + 1] = conn(w, 1, sideOf(m), 11, 2, 11, 2)
		eq(Audit.audit(w, 1, more, { view = v }).counts.u_turn, 1, "same segment" .. tag(m))
		-- a road leaving 10 m beside the west road: arriving from the west, a 170 deg turn
		local s = F.build({ [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { -60, 10 } },
			{ [11] = { 1, 2, F.TPL.medium }, [12] = { 1, 3, F.TPL.medium }, [13] = { 1, 4, F.TPL.small } }, m)
		local sc = { conn(s, 1, sideOf(m), 11, 1, 12, 1), conn(s, 1, sideOf(m), 11, 2, 13, 1) }
		local res = Audit.audit(s, 1, sc, {})
		eq(res.counts.u_turn, 1, "sharp" .. tag(m))
		ok(table.concat(res.detail, ","):find("u_turn:11>13", 1, true))
	end
end)

test("unfed and dead: lanes without a connection where a road could feed / take them", function()
	for _, m in ipairs(SIDES) do
		local w = crossing(2, 2, m)
		local conns, v = plan(w, 1)
		local res = Audit.audit(w, 1, conns, { view = v })
		eq(res.counts.unfed, nil)
		eq(res.counts.dead, nil)
		local r1 = Audit.audit(w, 1, without(conns, function(c) return c.segment0 == 11 end), { view = v })
		eq(r1.counts.dead, 2, "west approach has no connection" .. tag(m))
		local r2 = Audit.audit(w, 1, without(conns, function(c) return c.segment1 == 12 end), { view = v })
		eq(r2.counts.unfed, 2, "nothing into the east road" .. tag(m))
	end
	-- a dead end (one road) is never audited
	local d = F.build({ [1] = { 0, 0 }, [2] = { 60, 0 } }, { [11] = { 1, 2, F.TPL.medium } })
	eq(Audit.audit(d, 1, {}, {}).skipped, "dead_end")
end)

test("bypassed_turn: the game's default at a Channelized X centre turns where the slip lanes do", function()
	for _, m in ipairs(SIDES) do
		local w = F.channelX({ mirror = m })
		local conns, v = plan(w, 1)
		eq(#v.bypassed, 4, "four kerb turns go by the slip lanes")
		eq(Audit.audit(w, 1, conns, { view = v }).counts.bypassed_turn, nil, "the rule" .. tag(m))
		local res = Audit.audit(w, 1, Cross.defaultConns(v), { view = v })
		eq(res.counts.bypassed_turn, 4, "game default" .. tag(m))
		-- no view, no bypass map: not judged
		eq(Audit.audit(w, 1, Cross.defaultConns(v), {}).counts.bypassed_turn, nil)
	end
end)

--- Two 2x2 crossroads A (node 1) and B (node 2) `gap` m apart on the main road (segment 12 between them).
local function twoCrossings(gap, mirror)
	local nodes = { [1] = { 0, 0 }, [2] = { gap, 0 }, [3] = { -60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 },
		[6] = { gap + 60, 0 }, [7] = { gap, 60 }, [8] = { gap, -60 } }
	local segs = { [11] = { 1, 3, F.TPL.medium }, [12] = { 1, 2, F.TPL.medium }, [13] = { 1, 4, F.TPL.medium },
		[14] = { 1, 5, F.TPL.medium }, [21] = { 2, 6, F.TPL.medium }, [23] = { 2, 7, F.TPL.medium },
		[24] = { 2, 8, F.TPL.medium } }
	return F.build(nodes, segs, mirror)
end

test("weave (heuristic): a turn into a 60 m link whose lanes then split at the next crossroads", function()
	for _, m in ipairs(SIDES) do
		local w = twoCrossings(60, m)
		local ca, va = plan(w, 1)
		local cb = plan(w, 2)
		local planned = { [1] = ca, [2] = cb }
		local calls = 0
		local res = Audit.audit(w, 1, ca, { view = va, connsOf = function(J)
			calls = calls + 1
			return planned[J]
		end })
		-- the rule feeds every lane of the link: the turns' misses at B are forced by the lanes the other
		-- movements into the link take (no free lane next to them)
		ok((res.forced.weave or 0) >= 2, "both turns into the link miss a turn at B" .. tag(m))
		eq(res.counts.weave, nil, "forced, not avoidable" .. tag(m))
		eq(calls, 1, "one look-ahead: the only short exit road")
		-- only the kerb turn from the south (14) into the link, on its kerb lane: the far lane is free, and
		-- from it B's far turn is reached (avoidable: the turn could fan out into it)
		local kerbIn = without(ca, function(c) return c.segment1 == 12 end)
		kerbIn[#kerbIn + 1] = conn(w, 1, sideOf(m), 14, 1, 12, 1)
		local ra = Audit.audit(w, 1, kerbIn, { view = va, connsOf = function(J) return planned[J] end })
		eq(ra.counts.weave, 1, "avoidable: the free far lane reaches B's far turn" .. tag(m))
		eq(ra.forced.weave, nil, tag(m))
		ok(table.concat(ra.detail, ","):find("weave:14>12@2", 1, true), table.concat(ra.detail, ","))
		-- connsFirst (the automatic pass): the same finding, the plan asked before J's roads are read
		local rf = Audit.audit(w, 1, ca, { view = va, connsFirst = true, connsOf = function(J) return planned[J] end })
		eq(rf.forced.weave, res.forced.weave, "connsFirst" .. tag(m))
		local reads = 0
		local rw = setmetatable({ node = function(id)
			if id == 2 then reads = reads + 1 end
			return w.node(id)
		end }, { __index = w })
		Audit.audit(rw, 1, ca, { view = va, connsFirst = true, connsOf = function() return nil end })
		eq(reads, 0, "connsFirst: a junction outside the plan is not read" .. tag(m))
		-- 200 m apart: room to change lanes
		local far = twoCrossings(200, m)
		local fa, fv = plan(far, 1)
		local fb = plan(far, 2)
		local rfar = Audit.audit(far, 1, fa, { view = fv, connsOf = function(J) return J == 2 and fb or nil end })
		eq(rfar.counts.weave, nil)
		eq(rfar.forced.weave, nil)
		-- unknown connections at B: not judged
		local ru = Audit.audit(w, 1, ca, { view = va, connsOf = function() return nil end })
		eq(ru.counts.weave, nil)
		eq(ru.forced.weave, nil)
	end
end)

test("lights: a slip node or a ring arm junction that still has a light; crossroads keep theirs", function()
	local w = F.channelT()
	local c2, v2 = plan(w, 2)
	eq(v2.case, "B")
	local lit = function() return { light = true } end
	eq(Audit.audit(w, 2, c2, { view = v2, lightsOf = lit }).counts.lights, 1)
	eq(Audit.audit(w, 2, c2, { view = v2, lightsOf = function() return { light = false } end }).counts.lights, nil)
	local c1, v1 = plan(w, 1)
	eq(Audit.audit(w, 1, c1, { view = v1, lightsOf = lit }).counts.lights, nil, "the centre T keeps its lights")
	local rw = F.PROBE_2LANE_SMALL.world()
	local ring = Ring.findRing(rw, 17955)
	local rv = Ring.nodeView(rw, ring, 17955)
	local res = Audit.audit(rw, 17955, Rules.twoLaneConns(rv, { turbo = false }), { view = rv, ring = ring, lightsOf = lit })
	eq(res.counts.lights, 1)
	eq(res.case, "ring")
	eq(res.shape, "arm")
end)

test("bad: a connection naming a segment or lane the node does not have", function()
	local w = crossing(2, 2)
	local conns, v = plan(w, 1)
	local more = { table.unpack(conns) }
	more[#more + 1] = Rules.conn(999, 1, 12, 3, true, false)
	more[#more + 1] = Rules.conn(11, 0, 12, 3, true, false) -- lane 0 is the sidewalk
	local res = Audit.audit(w, 1, more, { view = v })
	eq(res.counts.bad, 2)
	-- tram-only connections are not road connections
	local tram = { table.unpack(conns) }
	tram[#tram + 1] = Rules.conn(999, 1, 12, 3, false, true)
	eq(Audit.audit(w, 1, tram, { view = v }).counts.bad, nil)
end)

---------------------------------------------------------------------------
-- Standard fixtures under the current rules

--- Plans every node of `ids` (slip rule, no current connections) and audits each with its planned
-- connections; the weave look-ahead sees the planned connections of the other nodes.
local function auditPlanned(w, ids)
	local planned, out = {}, {}
	for _, n in ipairs(ids) do
		local r = Slip.plan(w, n, function() return {} end)
		if r.conns then planned[n] = r end
	end
	for _, n in ipairs(ids) do
		local r = planned[n]
		if r then
			out[#out + 1] = Audit.audit(w, n, r.conns, { view = r.view,
				connsOf = function(J) return planned[J] and planned[J].conns end })
		end
	end
	return out
end

-- Findings the current rules must never produce on the standard fixtures.
local NEVER = { "squeeze", "across", "ramp_ramp", "u_turn", "unfed", "dead", "bypassed_turn", "weave", "bad", "lights" }

local function checkNever(results, label)
	for _, res in ipairs(results) do
		ok(res.skipped == nil, label .. " node " .. res.node .. " skipped " .. tostring(res.skipped))
		for _, k in ipairs(NEVER) do
			eq(res.counts[k], nil, label .. " node " .. res.node .. " " .. k .. ": " .. table.concat(res.detail, ","))
		end
	end
end

local function sharedOf(results)
	local t = {}
	for _, res in ipairs(results) do t[#t + 1] = res.node .. "=" .. (res.counts.shared or 0) end
	return table.concat(t, " ")
end

test("standard fixtures: Channelized T / X, slip nodes and lane look-aheads have no avoidable finding", function()
	for _, m in ipairs(SIDES) do
		local t = auditPlanned(F.channelT({ mirror = m }), { 1, 2, 3, 4 })
		checkNever(t, "channel T" .. tag(m))
		-- the centre T: the main road's lane next to the straight exit shares with the far turn (by design)
		eq(sharedOf(t), "1=1 2=0 3=0 4=0", "channel T" .. tag(m))
		for _, main in ipairs({ F.TPL.medium, F.TPL.large }) do
			local x = auditPlanned(F.channelX({ main = main, mirror = m }), { 1, 2, 3, 4, 8 })
			checkNever(x, "channel X" .. tag(m))
			eq(sharedOf(x), "1=2 2=0 3=0 4=0 8=0", "channel X" .. tag(m))
		end
		local one3, one2 = "B- FV FV FV F-", "B- FV FV F-"
		local ml = auditPlanned(F.mergeLine({ mirror = m, ramp = F.RAMP2, up = { { one3, 120 }, { one2, 150 } },
			down = { { one3, 100 }, { one2, 200 } } }), { 1, 101, 201 })
		checkNever(ml, "merge line" .. tag(m))
		-- 101 / 201 (one-way lane changes far from a two-way road: no driving side) are not planned
		eq(sharedOf(ml), "1=0")
		local dl = auditPlanned(F.divergeLine({ mirror = m, up = { { one3, 150 }, { one2, 150 } }, down = { { one2, 200 } } }),
			{ 1, 101 })
		checkNever(dl, "diverge line" .. tag(m))
		eq(sharedOf(dl), "1=0")
	end
end)

test("standard fixtures: crossroads and T-junctions of 1-3 lanes; the shared lanes the rule makes on purpose", function()
	-- shared (avoidable by the audit's measure) per main x side lanes: the rule's 2-lane "the lane next to
	-- the straight exit goes straight too" and 3-lane "the far lane goes straight too" make the straight
	-- movement share an exit lane with a turn (detail ks / fs) where the exit road had a lane for each
	-- (TESTING.md X: reported for the user's decision, not hidden). 1-lane roads: all forced. 23T: the side
	-- road's 3 lanes have 2 share-free exit lanes, so one share is forced (the audit's per-approach excess).
	local expect = {
		["11X"] = 0, ["11T"] = 0, ["12X"] = 0, ["12T"] = 0, ["13X"] = 2, ["13T"] = 0,
		["21X"] = 0, ["21T"] = 2, ["22X"] = 0, ["22T"] = 2, ["23X"] = 2, ["23T"] = 2,
		["31X"] = 2, ["31T"] = 1, ["32X"] = 2, ["32T"] = 1, ["33X"] = 4, ["33T"] = 2,
	}
	for _, m in ipairs(SIDES) do
		for main = 1, 3 do
			for side = 1, 3 do
				for _, t in ipairs({ false, true }) do
					local key = main .. side .. (t and "T" or "X")
					local res = auditPlanned(crossing(main, side, m, t), { 1 })
					checkNever(res, key .. tag(m))
					eq(res[1].counts.shared or 0, expect[key], key .. tag(m) .. ": " .. table.concat(res[1].detail, ","))
				end
			end
		end
	end
end)

test("standard fixtures: ramp nodes on a two-way road", function()
	for _, m in ipairs(SIDES) do
		-- shallow ramps leaving / joining a 3+3 road (crossing rule, shallow rule)
		local r1 = auditPlanned(F.rampNode({ mirror = m, ramps = { { id = 33, leaving = true, tan = -80, far = -20 },
			{ id = 34, leaving = false, tan = -100, far = -160 } } }), { 1 })
		checkNever(r1, "ramp node" .. tag(m))
		-- the joining ramp's 2 lanes share the east road's lane 2 with the through road's 2 straight lanes
		-- (ks), although the through road could give its kerb lanes to the off-ramp (reported)
		eq(r1[1].counts.shared, 1, table.concat(r1[1].detail, ","))
		-- a ramp leaving (case B diverge), a ramp joining (case B merge)
		for _, rp in ipairs({ { id = 33, leaving = true, tan = -30, far = -30 }, { id = 34, leaving = false, tan = -150, far = -150 } }) do
			local r = auditPlanned(F.rampNode({ mirror = m, ramps = { rp } }), { 1 })
			checkNever(r, "ramp " .. rp.id .. tag(m))
			eq(r[1].counts.shared, nil)
		end
		-- a diamond terminal (ramps at right angles)
		local d = auditPlanned(F.rampNode({ mirror = m, ramps = { { id = 33, leaving = true, tan = 90, far = 90 },
			{ id = 34, leaving = false, tan = -90, far = -90 } } }), { 1 })
		checkNever(d, "terminal" .. tag(m))
	end
end)

test("standard fixtures: roundabouts (interchange ring with its ramp entry, probe rings): nothing avoidable", function()
	local function ringAudit(w, start)
		local ring = Ring.findRing(w, start)
		local seeds = {}
		for _, n in ipairs(ring.nodes) do seeds[n] = true end
		local p = Rules.planRing(w, ring, seeds, "two_lane", function() return {} end)
		local planned, out = {}, {}
		for _, r in ipairs(p.nodes) do planned[r.node] = r.conns end
		for _, r in ipairs(p.nodes) do
			if r.conns and r.view.kind == "arm" then
				out[#out + 1] = Audit.audit(w, r.node, r.conns, { view = r.view, ring = ring,
					connsOf = function(J) return planned[J] end })
			end
		end
		return out
	end
	for _, m in ipairs(SIDES) do
		for _, dir in ipairs({ "ccw", "cw" }) do
			local res = ringAudit(F.interchange({ dir = dir, mirror = m }), 1)
			eq(#res, 4, "two town arms, the on-ramp, the off-ramp")
			checkNever(res, "interchange " .. dir .. tag(m))
			for _, x in ipairs(res) do
				eq(x.counts.shared, nil, "ring give-way is forced")
				if x.shape == "entry" then eq(x.forced.squeeze, 1, "the ramp's own lane: circulating lanes zip (forced)") end
			end
		end
	end
	for _, fx in ipairs({ F.PROBE_2LANE_SMALL, F.PROBE_2LANE_MEDIUM, F.PROBE_4LANE_MEDIUM }) do
		local w = fx.world()
		local first = next(w.nodes)
		local ids = {}
		for id in pairs(w.nodes) do ids[#ids + 1] = id end
		table.sort(ids)
		local res = ringAudit(w, ids[1] == first and ids[1] or ids[1])
		eq(#res, 4)
		checkNever(res, "probe ring")
		for _, x in ipairs(res) do eq(x.counts.shared, nil) end
	end
end)

---------------------------------------------------------------------------
-- Safety and bounds

test("nil-safe: no world, missing nodes and segments, junk connections, throwing callbacks", function()
	eq(Audit.audit(nil, 1, {}).skipped, "no_world")
	eq(Audit.audit(crossing(2, 2), "x", {}).skipped, "no_world")
	eq(Audit.audit(crossing(2, 2), 77, {}).skipped, "no_node")
	-- a bulldozed segment still listed at the node
	local w = crossing(2, 2)
	local conns, v = plan(w, 1)
	w.segs[12] = nil
	eq(Audit.audit(w, 1, conns, { view = v }).skipped, "no_seg")
	-- junk connections, no view, no connections at all
	local w2 = crossing(2, 2)
	local junk = { 1, "x", false, {}, { withRoad = true }, { withRoad = true, segment0 = 11, lane0 = "a", segment1 = 12, lane1 = nil } }
	local res = Audit.audit(w2, 1, junk, nil)
	eq(res.skipped, nil)
	eq(res.counts.bad, 2)
	local r0 = Audit.audit(w2, 1, nil, nil)
	eq(r0.counts.dead, 8, "4 approaches x 2 lanes")
	eq(r0.counts.unfed, 8)
	-- throwing callbacks are caught inside
	local c2, v2 = plan(w2, 1)
	local boom = function() error("boom") end
	local r3 = Audit.audit(w2, 1, c2, { view = v2, connsOf = boom, lightsOf = boom })
	eq(r3.counts.weave, nil)
	eq(r3.counts.lights, nil)
	-- a world that throws: A.safe returns nil, err (the callers log it)
	local bad = { node = function() error("gone") end, seg = function() error("gone") end }
	local r4, e = Audit.safe(bad, 1, {}, {})
	eq(r4, nil)
	ok(tostring(e):find("gone", 1, true))
	-- summary of a failed and a skipped audit
	local sum = Audit.addTo(Audit.addTo(Audit.newSum(), nil), { skipped = "no_node", counts = {}, forced = {}, total = 0 })
	eq(sum.failed, 1)
	eq(sum.audited, 0)
end)

test("bounded: road and connection caps, one look-ahead per exit road", function()
	-- 7 roads: not audited
	local nodes, segs = { [1] = { 0, 0 } }, {}
	for k = 1, 7 do
		local a = 2 * math.pi * k / 7
		nodes[1 + k] = { 60 * math.cos(a), 60 * math.sin(a) }
		segs[10 + k] = { 1, 1 + k, F.TPL.small }
	end
	eq(Audit.audit(F.build(nodes, segs), 1, {}, {}).skipped, "roads")
	-- 100 000 connections: only MAX_CONNS looked at
	local w = crossing(2, 2)
	local conns, v = plan(w, 1)
	local many = {}
	for k = 1, 100000 do many[k] = conns[(k - 1) % #conns + 1] end
	local t0 = os.clock()
	local res = Audit.audit(w, 1, many, { view = v })
	ok(os.clock() - t0 < 0.5, "capped")
	eq(res.skipped, nil)
	-- look-aheads: at most one per exit road of the node (4 at a crossroads whose arms all end in junctions)
	local calls = 0
	local grid = F.build({ [1] = { 0, 0 }, [2] = { -50, 0 }, [3] = { 50, 0 }, [4] = { 0, 50 }, [5] = { 0, -50 },
		[6] = { -50, 50 }, [7] = { -50, -50 }, [8] = { 50, 50 }, [9] = { 50, -50 } },
		{ [11] = { 1, 2, F.TPL.medium }, [12] = { 1, 3, F.TPL.medium }, [13] = { 1, 4, F.TPL.medium }, [14] = { 1, 5, F.TPL.medium },
		[21] = { 2, 6, F.TPL.small }, [22] = { 2, 7, F.TPL.small }, [23] = { 3, 8, F.TPL.small }, [24] = { 3, 9, F.TPL.small },
		[25] = { 4, 6, F.TPL.small }, [26] = { 4, 8, F.TPL.small }, [27] = { 5, 7, F.TPL.small }, [28] = { 5, 9, F.TPL.small } })
	local gc, gv = plan(grid, 1)
	Audit.audit(grid, 1, gc, { view = gv, connsOf = function() calls = calls + 1 return {} end })
	eq(calls, 4)
end)

test("log fields: AUDIT and AUDIT_SUMMARY lines", function()
	local w = crossing(2, 2)
	local conns, v = plan(w, 1)
	local more = { table.unpack(conns) }
	more[#more + 1] = conn(w, 1, "right", 11, 2, 11, 2)
	local res = Audit.audit(w, 1, more, { view = v })
	local line = Rules.line("AUDIT", Audit.fields(res, { { "src", "auto" }, { "job", 3 } }))
	eq(line, "[SQRL] AUDIT node=1 case=X shape=crossroads findings=u_turn:1 forced=shared:9 detail=u_turn:11>11 src=auto job=3")
	local sum = Audit.addTo(Audit.addTo(Audit.newSum(), res), Audit.audit(w, 1, conns, { view = v }))
	eq(Rules.line("AUDIT_SUMMARY", Audit.summaryFields(sum, { { "src", "auto" } })),
		"[SQRL] AUDIT_SUMMARY src=auto audited=2 flagged=1 findings=u_turn:1 forced=shared:17")
end)

test("perf: audit of 160 Channelized X centres and of the 160-node mixed set (printed)", function()
	local xs = {}
	for k = 1, 160 do xs[k] = F.shift(F.channelX({ main = F.TPL.large, mirror = k % 2 == 0 }), 1000 * k, 400 * k, 0) end
	local plans = {}
	for k, w in ipairs(xs) do
		local n = 1000 * k + 1
		plans[k] = { w = w, n = n, conns = plan(w, n) }
		plans[k].view = Slip.classify(w, n)
	end
	local t0 = os.clock()
	local found = 0
	for _, p in ipairs(plans) do
		local res = Audit.audit(p.w, p.n, p.conns, { view = p.view, connsOf = function() return nil end })
		found = found + res.total
	end
	local ms = (os.clock() - t0) * 1000
	print(string.format("audit of 160 Channelized X centres: %.1f ms (%.3f ms per junction), findings %d", ms, ms / 160, found))
	ok(ms / 160 < 2, "well under 2 ms per junction offline")
end)

---------------------------------------------------------------------------
-- Traffic lights (user decision 2026-10-11, "keep where lights exist"; TESTING.md Y)

local function withLit(w, lit)
	if lit ~= "unknown" then w.lit = function() return lit end end
	return w
end

test("lights: the rule's straight shares are shared_lit (by design) at lit crossroads; unlit they are gone", function()
	-- unknown: as before (the standard fixtures' expectation); lit: every one of them by design;
	-- unlit: the rule dropped them. What stays at 3x3 T unlit is the side road's 2-lane far turn next to
	-- the main road's 2 straight lanes: no extra share, avoidable only by taking a straight lane from the
	-- main road (11: s|f|f), which the rule never does. At 2x3 T the same share is forced (the side road's
	-- 3 lanes have 2 share-free exit lanes: the audit's per-approach excess), so it is not counted there
	local unknown = {
		["13X"] = 2, ["21T"] = 2, ["22T"] = 2, ["23X"] = 2, ["23T"] = 2,
		["31X"] = 2, ["31T"] = 1, ["32X"] = 2, ["32T"] = 1, ["33X"] = 4, ["33T"] = 2,
	}
	local unlit = { ["33T"] = 1 }
	for _, m in ipairs(SIDES) do
		for main = 1, 3 do
			for side = 1, 3 do
				for _, t in ipairs({ false, true }) do
					local key = main .. side .. (t and "T" or "X")
					local function run(lit)
						local res = auditPlanned(withLit(crossing(main, side, m, t), lit), { 1 })[1]
						checkNever({ res }, key .. tag(m) .. " lit=" .. tostring(lit))
						return res
					end
					local u, y, no = run("unknown"), run(true), run(false)
					local msg = key .. tag(m)
					eq(u.counts.shared or 0, unknown[key] or 0, msg .. " unknown: " .. table.concat(u.detail, ","))
					eq(u.forced.shared_lit, nil, msg .. " unknown: never by design")
					eq(y.counts.shared, nil, msg .. " lit: nothing avoidable")
					eq(y.forced.shared_lit, unknown[key], msg .. " lit: the same lanes, by design")
					eq(y.forced.shared, u.forced.shared, msg .. " forced shares unchanged")
					eq(y.total, 0, msg .. " lit: no AUDIT line")
					eq(no.counts.shared, unlit[key], msg .. " unlit: " .. table.concat(no.detail, ","))
					eq(no.forced.shared_lit, nil, msg .. " unlit: never by design")
				end
			end
		end
	end
end)

test("lights: Channelized T / X centres: shared_lit when lit, no avoidable shared when unlit", function()
	for _, m in ipairs(SIDES) do
		local function centre(fx, lit) return auditPlanned(withLit(fx, lit), { 1 })[1] end
		local tl, tu = centre(F.channelT({ mirror = m }), true), centre(F.channelT({ mirror = m }), false)
		eq({ tl.counts.shared, tl.forced.shared_lit }, { nil, 1 }, "channel T lit" .. tag(m))
		eq({ tu.counts.shared, tu.forced.shared_lit }, { nil, nil }, "channel T unlit" .. tag(m))
		for _, main in ipairs({ F.TPL.medium, F.TPL.large }) do
			local xl, xu = centre(F.channelX({ main = main, mirror = m }), true), centre(F.channelX({ main = main, mirror = m }), false)
			eq({ xl.counts.shared, xl.forced.shared_lit }, { nil, 2 }, "channel X lit" .. tag(m))
			eq({ xu.counts.shared, xu.forced.shared_lit }, { nil, nil }, "channel X unlit" .. tag(m))
			checkNever({ xl, xu }, "channel X" .. tag(m))
		end
	end
end)

test("lights: at a lit crossroads only lanes a straight movement shares are by design; turn + turn stays shared", function()
	for _, m in ipairs(SIDES) do
		local side = sideOf(m)
		local w = withLit(crossing(3, 3, m), true)
		local conns, v = plan(w, 1)
		local res = Audit.audit(w, 1, conns, { view = v })
		eq(res.forced.shared_lit, 4, "3x3 lit" .. tag(m))
		eq(res.counts.shared, nil)
		-- north's far turn also into east's kerb lane, which the south kerb turn feeds: two turns, one lane
		local extra = {}
		for _, c in ipairs(conns) do extra[#extra + 1] = c end
		extra[#extra + 1] = conn(w, 1, side, 13, 3, 12, 1)
		local res2 = Audit.audit(w, 1, extra, { view = v })
		eq(res2.counts.shared, 1, "turn + turn" .. tag(m) .. ": " .. table.concat(res2.detail, ","))
		eq(res2.forced.shared_lit, 4, "the straight shares still by design" .. tag(m))
		-- shared_lit is logged under forced=, never a reason for a line
		local line = Rules.line("AUDIT", Audit.fields(res))
		ok(line:find("forced=shared_lit:4", 1, true), line)
		ok(line:find("findings=- ", 1, true), line)
		-- a T-junction's or a slip node's view without lit: as before
		local wT = crossing(2, 2, m, true)
		local cT, vT = plan(wT, 1)
		eq(Audit.audit(wT, 1, cT, { view = vT }).counts.shared, 2, "2x2 T unknown" .. tag(m))
	end
end)

test("lights: 2x3 T unlit, the side road's far turn sharing with the straight is forced (per-approach excess)", function()
	for _, m in ipairs(SIDES) do
		local side = sideOf(m)
		local w = withLit(crossing(2, 3, m, true), false)
		local conns, v = plan(w, 1)
		local res = Audit.audit(w, 1, conns, { view = v })
		-- the side road (13) has 3 lanes, its exits 11 / 12 (2 lanes each) have 1 lane left each beside
		-- the main road's straight: one share is forced, no matter where
		eq({ res.counts.shared, res.forced.shared, res.forced.shared_lit }, { nil, 1, nil }, "2x3 T unlit" .. tag(m))
		-- a second share at the other exit is not forgiven too: the excess pays for one share only
		local extra = {}
		for _, c in ipairs(conns) do extra[#extra + 1] = c end
		extra[#extra + 1] = conn(w, 1, side, 13, 2, 11, 2)
		local res2 = Audit.audit(w, 1, extra, { view = v })
		eq({ res2.counts.shared, res2.forced.shared }, { 1, 1 }, "two shares, one forced" .. tag(m) .. ": "
			.. table.concat(res2.detail, ","))
		-- 3x3 T unlit: avoidable (a main road straight lane less would free it), still counted
		local w3 = withLit(crossing(3, 3, m, true), false)
		local c3, v3 = plan(w3, 1)
		eq(Audit.audit(w3, 1, c3, { view = v3 }).counts.shared, 1, "3x3 T unlit" .. tag(m))
	end
end)

---------------------------------------------------------------------------
-- Showcase run 2026-10-12 (Stress Test Showcase, every square_roundabouts type, auto pass): the findings
-- that were the audit's misjudgement, now forced / by design or gone

--- Plans the whole ring through `start` (two_lane, every junction a seed) and audits each arm junction.
local function ringAuditAll(w, start)
	local ring = Ring.findRing(w, start)
	local seeds = {}
	for _, n in ipairs(ring.nodes) do seeds[n] = true end
	local p = Rules.planRing(w, ring, seeds, "two_lane", function() return {} end)
	local planned, out = {}, {}
	for _, r in ipairs(p.nodes) do planned[r.node] = r.conns end
	for _, r in ipairs(p.nodes) do
		if r.conns and r.view.kind == "arm" then
			out[#out + 1] = Audit.audit(w, r.node, r.conns, { view = r.view, ring = ring,
				connsOf = function(J) return planned[J] end })
		end
	end
	return out, p, ring
end

test("showcase: a ring of highway road (no sidewalks) is no ramp; ring arms have no ramp_ramp", function()
	-- in game: nodes 122611 / 123239 (Roundabout Interchange rings), 15 per Magic Roundabout:
	-- ramp_ramp:<ringIn>><ringOut>, the circulating move, at every two-way arm junction
	for _, m in ipairs(SIDES) do
		for _, dir in ipairs({ "ccw", "cw" }) do
			local w = F.interchange({ dir = dir, mirror = m, ringTpl = "highway_ramp2" })
			local ring = Ring.findRing(w, 1)
			ok(Rules.isRampSeg(w, ring.segs and ring.segs[1] or next(ring.segSet)), "ring segments look like ramps")
			local res = ringAuditAll(w, 1)
			eq(#res, 4, "two town arms, the on-ramp, the off-ramp")
			local arms = 0
			for _, x in ipairs(res) do
				if x.shape == "arm" then arms = arms + 1 end
				eq(x.counts.ramp_ramp, nil, "node " .. x.node .. " " .. dir .. tag(m) .. ": " .. table.concat(x.detail, ","))
			end
			eq(arms, 2, dir .. tag(m))
			checkNever(res, "highway ring " .. dir .. tag(m))
		end
	end
	-- without the ring (a plain audit of the node) the same move still reads as ramp_ramp: the ring is
	-- what tells them apart
	local w = F.interchange({ ringTpl = "highway_ramp2" })
	local ring = Ring.findRing(w, 1)
	local v = Ring.nodeView(w, ring, 1)
	eq(v.kind, "arm")
	local conns = Rules.twoLaneConns(v, { turbo = false })
	eq(Audit.audit(w, 1, conns, { view = v }).counts.ramp_ramp, 1)
	eq(Audit.audit(w, 1, conns, { view = v, ring = ring }).counts.ramp_ramp, nil)
end)

test("showcase: turbo ring with splitter arms: the ring-out outer lane after an exit is a turbo_gap", function()
	-- in game: ring 8330 (4 lanes, 6 splitter arms) and 2-lane rings: unfed:<ringOut> at every exit node
	for _, m in ipairs(SIDES) do
		for _, dir in ipairs({ "ccw", "cw" }) do
			local w = F.ring({ dir = dir, mirror = m, arms = { { splitter = true }, { splitter = true }, { splitter = true } } })
			local res, p = ringAuditAll(w, 1)
			ok(p.turbo, "fresh ring, 2-lane exit legs: turbo " .. tostring(p.turboReason))
			local exits = 0
			for _, x in ipairs(res) do
				if x.shape == "exit" then
					exits = exits + 1
					eq(x.forced.turbo_gap, 1, "node " .. x.node .. tag(m))
				else
					eq(x.forced.turbo_gap, nil, "entry node " .. x.node .. tag(m))
				end
			end
			eq(exits, 3)
			checkNever(res, "turbo splitter ring " .. dir .. tag(m))
			-- the same exit node with the outer lane also continuing (not turbo): nothing left empty
			local ring = Ring.findRing(w, 1)
			for _, n in ipairs(ring.nodes) do
				local v = Ring.nodeView(w, ring, n)
				if v.kind == "arm" and #v.e == 0 then
					local r = Audit.audit(w, n, Rules.twoLaneConns(v, { turbo = false }), { view = v, ring = ring })
					eq(r.forced.turbo_gap, nil)
					eq(r.counts.unfed, nil)
					-- an outer ring-out lane left empty although the outer ring-in lane continues: still unfed
					local cut = without(Rules.twoLaneConns(v, { turbo = false }), function(c)
						return c.segment1 == v.ringOut and c.lane1 == v.o_out[1]
					end)
					cut[#cut + 1] = Rules.conn(v.ringIn, v.o_in[1], v.ringOut, v.o_out[2], true, false)
					local r2 = Audit.audit(w, n, cut, { view = v, ring = ring })
					eq(r2.counts.unfed, 1, "node " .. n .. tag(m))
					eq(r2.forced.turbo_gap, nil)
				end
			end
		end
	end
end)

--- T-junction at node 1 (main road 11 east / 13 west, side road 15 north to node 4) with a slip lane
-- from each main road arm to node 4 (21 east -> north, kerb turn of westbound traffic; 25 west -> north,
-- far turn of eastbound traffic): both turns into the side road have a slip lane (in game: T-junctions
-- 117874 / 123825, the slips joining the side road at the next crossroads).
local function twoSlipT(mirror)
	local a = math.rad(40)
	local ca, sa = math.cos(a), math.sin(a)
	local main, side, slip = F.TPL.large, F.TPL.medium, F.TPL.one_way_leg
	local nodes = { [1] = { 0, 0 }, [2] = { 40, 0 }, [3] = { -40, 0 }, [4] = { 0, 35 },
		[5] = { 70, 0 }, [6] = { -70, 0 }, [7] = { 0, 65 } }
	local segs = {
		[11] = { 1, 2, main }, [12] = { 2, 5, main }, [13] = { 1, 3, main }, [14] = { 3, 6, main },
		[15] = { 1, 4, side }, [16] = { 4, 7, side },
		[21] = { 2, 4, slip, { -ca, sa }, { -sa, ca } }, -- east -> north
		[25] = { 3, 4, slip, { ca, sa }, { sa, ca } },   -- west -> north
	}
	return F.build(nodes, segs, mirror)
end

test("showcase: both turns into a side road have slip lanes: kept by the rule, no bypassed_turn", function()
	for _, m in ipairs(SIDES) do
		local w = twoSlipT(m)
		local conns, v = plan(w, 1)
		eq(v.case, "X")
		ok(v.bypassMap[11] and v.bypassMap[11][15], "east approach: bypassed" .. tag(m))
		ok(v.bypassMap[13] and v.bypassMap[13][15], "west approach: bypassed" .. tag(m))
		eq(#v.bypassed, 0, "the side road's only feeds: both kept" .. tag(m))
		local res = Audit.audit(w, 1, conns, { view = v })
		eq(res.counts.bypassed_turn, nil, tag(m) .. ": " .. table.concat(res.detail, ","))
		eq(res.counts.unfed, nil)
		-- the game's default at the channelized X still has its bypassed turns (another feed is kept)
		local cx = F.channelX({ mirror = m })
		local _, vx = plan(cx, 1)
		eq(Audit.audit(cx, 1, Cross.defaultConns(vx), { view = vx }).counts.bypassed_turn, 4, tag(m))
	end
end)

test("bypassed_turn: an approach whose every exit is a bypassed turn keeps them (sl_cross dropBypassed)", function()
	for _, m in ipairs(SIDES) do
		local w = twoSlipT(m)
		local conns, v = plan(w, 1)
		-- the side road's two turns also had slip lanes: the rule never drops every exit of an approach
		v.bypassMap[15] = { [11] = true, [13] = true }
		local res = Audit.audit(w, 1, conns, { view = v })
		eq(res.counts.bypassed_turn, nil, tag(m) .. ": " .. table.concat(res.detail, ","))
		-- with a non-bypassed exit left to it, one bypassed turn is a finding again
		v.bypassMap[15] = { [11] = true }
		eq(Audit.audit(w, 1, conns, { view = v }).counts.bypassed_turn, 1, tag(m))
	end
end)

test("showcase: 3-lane town grid crossroads 60 m apart: the weave is forced, none avoidable", function()
	-- in game: 1957 grid crossroads and T-junctions, weave:16 / 15 / 14 per crossroads (k|s|sf approaches)
	for _, m in ipairs(SIDES) do
		local nodes = { [1] = { 0, 0 }, [2] = { 60, 0 }, [3] = { -60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 },
			[6] = { 120, 0 }, [7] = { 60, 60 }, [8] = { 60, -60 } }
		local L = F.TPL.large
		local segs = { [11] = { 1, 3, L }, [12] = { 1, 2, L }, [13] = { 1, 4, L }, [14] = { 1, 5, L },
			[21] = { 2, 6, L }, [23] = { 2, 7, L }, [24] = { 2, 8, L } }
		local w = F.build(nodes, segs, m)
		local res = auditPlanned(w, { 1, 2 })
		for _, r in ipairs(res) do
			eq(r.counts.weave, nil, "node " .. r.node .. tag(m) .. ": " .. table.concat(r.detail, ","))
			-- into the link: kerb turn (kerb lane, a turn lane at the other end) misses 2, straight 1, far 1
			eq(r.forced.weave, 4, "node " .. r.node .. tag(m))
		end
	end
end)

test("exit fan (sl_exitfan zones): the fan's shares are shared_lit, no avoidable finding; a share within one phase beyond the boundary lane counts", function()
	for _, m in ipairs(SIDES) do
		for main = 1, 3 do
			for side = 1, 3 do
				for _, t in ipairs({ false, true }) do
					local key = main .. side .. (t and "T" or "X") .. tag(m)
					local w = crossing(main, side, m, t)
					w.lit = function() return true end
					w.exitFan = function() return true end
					local res = auditPlanned(w, { 1 })[1]
					checkNever({ res }, key)
					eq(res.counts.shared, nil, key .. " shared: " .. table.concat(res.detail, ","))
					eq(res.counts.unfed, nil, key)
					eq(res.counts.dead, nil, key)
					eq(res.total, 0, key .. " no AUDIT line: " .. table.concat(res.detail, ","))
				end
			end
		end
	end
	-- a crossing made by hand inside one phase: both 2x2 turns of the A-C phase into every lane of exit 13
	local w = crossing(2, 2, false, false)
	w.lit = function() return true end
	w.exitFan = function() return true end
	local conns, v = plan(w, 1)
	local extra = {}
	for _, c in ipairs(conns) do extra[#extra + 1] = c end
	local function addAll(a, b)
		for _, l0 in ipairs(Ring.lanesAt(w.seg(a), 1).incoming) do
			for _, l1 in ipairs(Ring.lanesAt(w.seg(b), 1).outgoing) do
				local dup = false
				for _, c in ipairs(extra) do
					if c.segment0 == a and c.lane0 == l0 and c.segment1 == b and c.lane1 == l1 then dup = true end
				end
				if not dup then extra[#extra + 1] = Rules.conn(a, l0, b, l1, true, false) end
			end
		end
	end
	addAll(11, 13)
	addAll(12, 13)
	local res = Audit.audit(w, 1, extra, { view = v })
	ok((res.counts.shared or 0) > 0, "a share within one phase beyond the boundary lane: " .. table.concat(res.detail, ","))
end)
