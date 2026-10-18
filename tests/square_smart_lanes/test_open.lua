-- square_smart_lanes: open exits (rev 7, PLAN.md "Open exit lanes near stops and close junctions"; sl_cross
-- X.openOf / X.openExits / openExit): an exit road with a street stop within 80 m of a crossroads / T, or whose
-- far end is a junction within 80 m with a choice of ways, lets the far-side turns into it land in every lane
-- the movements beside them in the same phase group leave (a merge, never a crossing); kerb-side turns and
-- straights keep their lanes; nothing qualifies: the connections exactly as before. Also the world's stop
-- read (sl_write world.stops over a fake api), the APPLY field open=, the audit's shared_open and the automatic
-- pass end to end. The tool: test_tool.lua "open exits (tool)".

local Rules = ug_require "square_smart_lanes::/smart_lanes/sl_rules.lua"
local Slip = ug_require "square_smart_lanes::/smart_lanes/sl_slip.lua"
local Cross = ug_require "square_smart_lanes::/smart_lanes/sl_cross.lua"
local Audit = ug_require "square_smart_lanes::/smart_lanes/sl_audit.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_smart_lanes/"
local F = dofile(here .. "fixtures.lua")
local makeGame = assert(loadfile(here .. "fakegame.lua", "t", _ENV))()

local FULL = os.getenv("TEST_FULL") ~= nil
local TPL = { [1] = F.TPL.small, [2] = F.TPL.medium, [3] = F.TPL.large }

local function roadSpec(inN, outN)
	local t = { "BS" }
	for _ = 1, inN do t[#t + 1] = "BV" end
	for _ = 1, outN do t[#t + 1] = "FV" end
	t[#t + 1] = "FS"
	return table.concat(t, " ")
end

--- Crossroads (T without 14) at node 1: 11 west, 12 east (main), 13 north (side, `sideLen` m long, default 200),
-- 14 south. opt: t, mirror, main / side (lane specs), lit (true / false / "unknown"), near (the north road ends
-- at a T junction this far: node 4 gets two more roads), plain (the north road passes a plain node at this
-- distance first), stops = { [seg] = { {x, y, param} } } (world.stops; nil: a world without it).
local function build(opt)
	opt = opt or {}
	local L = opt.near or opt.sideLen or 200
	local nodes = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, L } }
	local main, side = opt.main or TPL[2], opt.side or TPL[2]
	local segs = { [11] = { 1, 2, main }, [12] = { 1, 3, main } }
	if opt.plain then
		nodes[6] = { 0, opt.plain }
		segs[13] = { 1, 6, side }
		segs[16] = { 6, 4, side }
	else
		segs[13] = { 1, 4, side }
	end
	if not opt.t then
		nodes[5] = { 0, -60 }
		segs[14] = { 1, 5, side }
	end
	if opt.near then
		nodes[7], nodes[8] = { -60, L }, { 60, L }
		segs[17], segs[18] = { 4, 7, TPL[2] }, { 4, 8, TPL[2] }
		if opt.oneWayOn then segs[18] = { 8, 4, "BS FV FV FS" } end -- one-way into node 4: one way on
	end
	local w = F.build(nodes, segs, opt.mirror)
	if opt.lit ~= nil and opt.lit ~= "unknown" then w.lit = function() return opt.lit end end
	if opt.stops ~= nil then
		local sx = opt.mirror and -1 or 1
		w.stops = function(sid)
			local out = {}
			for _, st in ipairs(opt.stops[sid] or {}) do
				out[#out + 1] = { x = st.x and sx * st.x or nil, y = st.y, param = st.param }
			end
			return out
		end
	end
	return w
end

local function planOf(w) return Slip.plan(w, 1, function() return {} end) end

--- "exit lane positions" (kerb first) per movement "approach>exit", e.g. { ["11>13"] = "1,2" }.
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

local function catsOf(v)
	local cat = {}
	for _, ap in ipairs(v.approaches) do
		for _, ex in ipairs(ap.allExits or ap.exits) do cat[ap.seg .. ">" .. ex.seg] = ex.cat end
	end
	return cat
end

--- Connections of one movement as text (lane pairs), for "unchanged" checks.
local function moveText(conns, a, b)
	local out = {}
	for _, c in ipairs(conns) do
		if c.withRoad and c.segment0 == a and c.segment1 == b then out[#out + 1] = c.lane0 .. ">" .. c.lane1 end
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function logField(r, key)
	return Rules.line("APPLY", Slip.logFields(r)):match(" " .. key .. "=(%S+)")
end

local STOP = function(d) return { [13] = { { x = 8, y = d } } } end

---------------------------------------------------------------------------
-- Detection (X.openOf)

test("openOf: a stop at 79 m opens the exit road, 81 m not; position projected, param, or the segment's far end", function()
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		eq(Cross.openOf(build({ t = true, mirror = mirror, stops = STOP(79) }), 1, 13), "stop", "79 m" .. m)
		eq(Cross.openOf(build({ t = true, mirror = mirror, stops = STOP(81) }), 1, 13), nil, "81 m" .. m)
		eq(Cross.openOf(build({ t = true, mirror = mirror, stops = STOP(25) }), 1, 13), "stop", "25 m" .. m)
		-- no position: the param along the segment (0 at node0 = the junction here)
		eq(Cross.openOf(build({ t = true, mirror = mirror, stops = { [13] = { { param = 0.39 } } } }), 1, 13), "stop", "param 78 m" .. m)
		eq(Cross.openOf(build({ t = true, mirror = mirror, stops = { [13] = { { param = 0.41 } } } }), 1, 13), nil, "param 82 m" .. m)
		-- nothing known: the segment's far end (a 70 m road counts, a 200 m one not)
		eq(Cross.openOf(build({ t = true, mirror = mirror, sideLen = 70, stops = { [13] = { {} } } }), 1, 13), "stop", "unknown on 70 m" .. m)
		eq(Cross.openOf(build({ t = true, mirror = mirror, stops = { [13] = { {} } } }), 1, 13), nil, "unknown on 200 m" .. m)
	end
	-- a stop on a stretch past a plain node: its distance from the junction (40 m + 39 m), and 40 + 41 m not
	eq(Cross.openOf(build({ t = true, plain = 40, stops = { [16] = { { x = 8, y = 79 } } } }), 1, 13), "stop", "past a plain node")
	eq(Cross.openOf(build({ t = true, plain = 40, stops = { [16] = { { x = 8, y = 81 } } } }), 1, 13), nil, "past a plain node, 81 m")
	-- param oriented from the segment's node0: the segment drawn from the far end
	local w = build({ t = true })
	local s = w.seg(13)
	s.node0, s.node1, s.p0, s.p1 = s.node1, s.node0, s.p1, s.p0
	w.stops = function(sid) return sid == 13 and { { param = 0.61 } } or {} end -- 0.39 from the junction
	eq(Cross.stopDist(s, { at = 0, len = 200, from = 1 }, { param = 0.61 }) < 80, true, "reversed param")
	-- a world without stops (fixtures, a failing read) has none
	eq(Cross.openOf(build({ t = true }), 1, 13), nil, "no world.stops")
	local bad = build({ t = true })
	bad.stops = function() error("boom") end
	eq(Cross.openOf(bad, 1, 13), nil, "a failing read")
	-- NaN / inf positions fall back to the far end (no crash)
	eq(Cross.openOf(build({ t = true, stops = { [13] = { { x = 0 / 0, y = 1 / 0 } } } }), 1, 13), nil, "NaN position")
end)

test("openOf: the far end a junction with a choice of ways at 79 m is near, 81 m not; one way on (a merge) not", function()
	for _, mirror in ipairs({ false, true }) do
		local m = mirror and " LHT" or ""
		eq(Cross.openOf(build({ t = true, mirror = mirror, near = 79 }), 1, 13), "near", "79 m" .. m)
		eq(Cross.openOf(build({ t = true, mirror = mirror, near = 81 }), 1, 13), nil, "81 m" .. m)
		eq(Cross.openOf(build({ t = true, mirror = mirror, near = 79, plain = 30 }), 1, 13), "near", "through a plain node" .. m)
		eq(Cross.openOf(build({ t = true, mirror = mirror, near = 60, oneWayOn = true }), 1, 13), nil, "a merge node" .. m)
		-- a stop wins over near (one reason per road)
		eq(Cross.openOf(build({ t = true, mirror = mirror, near = 60, stops = STOP(30) }), 1, 13), "stop", "both" .. m)
	end
	eq(Cross.waysOn(build({ t = true, near = 60 }), 4, 13), 2)
	eq(Cross.waysOn(build({ t = true, near = 60, oneWayOn = true }), 4, 13), 1)
end)

---------------------------------------------------------------------------
-- Lanes

test("T 2x2 with a stop on the side road: the far turn lands in both lanes, the kerb turn and straights keep theirs", function()
	for _, mirror in ipairs({ false, true }) do
		for _, lit in ipairs({ true, false, "unknown" }) do
			local msg = (mirror and "LHT" or "RHT") .. " lit=" .. tostring(lit)
			local base = planOf(build({ t = true, mirror = mirror, lit = lit }))
			local r = planOf(build({ t = true, mirror = mirror, lit = lit, stops = STOP(25) }))
			eq(Cross.summary(r.view), Cross.summary(base.view), msg .. " lane strings")
			eq(logField(r, "open"), "13:stop", msg)
			eq(logField(base, "open"), "-", msg)
			local cat, lanes, old = catsOf(r.view), exitLanes(r.view, r.conns), exitLanes(base.view, base.conns)
			for k, c in pairs(cat) do
				local a, b = k:match("^(%d+)>(%d+)$")
				if b == "13" and c == "far" then
					eq(lanes[k], "1,2", msg .. " far turn into the side road")
					eq(old[k], "2", msg .. " before: the far lane")
				else
					eq(moveText(r.conns, tonumber(a), tonumber(b)), moveText(base.conns, tonumber(a), tonumber(b)), msg .. " " .. k .. " unchanged")
				end
			end
			eq(#r.conns, #base.conns + 1, msg .. " one connection more")
			-- the freed kerb turn stays in the kerb lane: its connections unchanged, no kerbLaneOnly split needed
			local kp = Slip.kerbPairs(r.view)
			eq(kp.kerbLaneOnly, nil, msg)
			for k in pairs(kp) do
				if type(k) == "string" and k:match(">13$") then eq(lanes[k], "1", msg .. " kerb turn " .. k) end
			end
		end
	end
end)

test("crossroads: lit 2x2 / 3x3 far turns fan past the other phase's straight; unlit the straight bounds them", function()
	for _, mirror in ipairs({ false, true }) do
		for _, n in ipairs({ 2, 3 }) do
			local msg = string.format("%s %dx%d", mirror and "LHT" or "RHT", n, n)
			local opt = { mirror = mirror, main = TPL[n], side = TPL[n], lit = true, stops = STOP(40) }
			local r = planOf(build(opt))
			opt.stops = nil
			local base = planOf(build(opt))
			eq(logField(r, "open"), "13:stop", msg)
			local cat, lanes = catsOf(r.view), exitLanes(r.view, r.conns)
			for k, c in pairs(cat) do
				local a, b = k:match("^(%d+)>(%d+)$")
				if b == "13" and c == "far" then
					eq(lanes[k], n == 2 and "1,2" or "1,2,3", msg .. " far turn fans")
				else
					eq(moveText(r.conns, tonumber(a), tonumber(b)), moveText(base.conns, tonumber(a), tonumber(b)), msg .. " " .. k)
				end
			end
			-- unlit: one group, the far turn only down to the lane the opposite straight lands in (2x2: the straight
			-- keeps both lanes, nothing changes; 3x3: the unlit straight in the middle lane, the far turn 2-3)
			opt.lit, opt.stops = false, STOP(40)
			local u = planOf(build(opt))
			opt.stops = nil
			local ub = planOf(build(opt))
			eq(logField(u, "open"), "13:stop", msg .. " unlit still logged")
			if n == 2 then
				eq(Rules.connsText(u.conns), Rules.connsText(ub.conns), msg .. " unlit unchanged")
			else
				local uc, ul = catsOf(u.view), exitLanes(u.view, u.conns)
				for k, c in pairs(uc) do
					if k:match(">13$") then
						eq(ul[k], ({ kerb = "1", straight = "2", far = "2,3" })[c], msg .. " unlit " .. k)
					end
				end
			end
		end
	end
end)

test("near: a short block to the next junction opens the side road (open=13:near); 81 m does not", function()
	for _, mirror in ipairs({ false, true }) do
		local msg = mirror and "LHT" or "RHT"
		local r = planOf(build({ t = true, mirror = mirror, lit = true, near = 50 }))
		eq(logField(r, "open"), "13:near", msg)
		local lanes, cat = exitLanes(r.view, r.conns), catsOf(r.view)
		for k, c in pairs(cat) do
			if k:match(">13$") and c == "far" then eq(lanes[k], "1,2", msg) end
		end
		local far = planOf(build({ t = true, mirror = mirror, lit = true, near = 81 }))
		eq(logField(far, "open"), "-", msg)
		eq(Rules.connsText(far.conns), Rules.connsText(planOf(build({ t = true, mirror = mirror, lit = true, sideLen = 81 })).conns), msg .. " as a dead end")
	end
end)

test("nothing open: no stop, stops past 80 m, no world.stops, dead ends: connections byte-identical", function()
	local P = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 200 }, [5] = { 0, -200 } }
	local n, stride, i = 0, FULL and 1 or 5, 0
	for _, mirror in ipairs({ false, true }) do
		for a = 1, 4 do
			for b = 1, 3 do
				for c = 1, 4 do
					for d = 1, 3 do
						for _, t in ipairs({ true, false }) do
							i = i + 1
							if i % stride == 0 or (a == 2 and b == 2 and c == 2 and d == 2) then
								local segs = { [11] = { 1, 2, roadSpec(a, b) }, [12] = { 1, 3, roadSpec(a, b) }, [13] = { 1, 4, roadSpec(c, d) } }
								if not t then segs[14] = { 1, 5, roadSpec(c, d) } end
								for _, lit in ipairs({ true, false, "unknown" }) do
									local msg = string.format("%s %d+%d / %d+%d%s lit=%s", t and "T" or "X", a, b, c, d, mirror and " LHT" or "", tostring(lit))
									local base = F.build(P, segs, mirror)
									if lit ~= "unknown" then base.lit = function() return lit end end
									local w = F.build(P, segs, mirror)
									if lit ~= "unknown" then w.lit = function() return lit end end
									w.stops = function(sid)
										-- stops beyond 80 m on every road, nothing else
										if sid == 13 or sid == 14 then return { { x = 4, y = (sid == 13 and 1 or -1) * 120 } } end
										return {}
									end
									local rb, rw = planOf(base), planOf(w)
									eq(Rules.connsText(rw.conns), Rules.connsText(rb.conns), msg)
									if rw.view.case == "X" then eq(logField(rw, "open"), "-", msg) end
									n = n + 1
								end
							end
						end
					end
				end
			end
		end
	end
	ok(n >= (FULL and 1728 or 300), "cases " .. n)
end)

--- Invariants of an open plan against the plan without the stop: same lane strings, straights and kerb-side
-- turns unchanged, far turns a superset of their lanes, and within one phase group (lit, game axis model) or
-- among every movement (otherwise) no two movements into one exit cross.
local function checkOpen(r, base, msg)
	local v = r.view
	eq(Cross.summary(v), Cross.summary(base.view), msg .. " lane strings")
	local cat, nl, ol = catsOf(v), exitLanes(v, r.conns), exitLanes(base.view, base.conns)
	for k, c in pairs(cat) do
		local a, b = k:match("^(%d+)>(%d+)$")
		a, b = tonumber(a), tonumber(b)
		if c ~= "far" or not (v.open and v.open[b]) then
			eq(moveText(r.conns, a, b), moveText(base.conns, a, b), msg .. " " .. k .. " unchanged")
		elseif ol[k] then
			for p in ol[k]:gmatch("%d+") do ok(("," .. nl[k] .. ","):find("," .. p .. ",", 1, true), msg .. " " .. k .. " keeps lane " .. p) end
		end
	end
	-- no crossing into an open exit within a group
	local pos, rank = {}, { kerb = 1, straight = 2, far = 3 }
	for _, ap in ipairs(v.approaches) do
		for _, ex in ipairs(ap.allExits or ap.exits) do
			for j, l in ipairs(ex.o) do pos[ex.seg .. ":" .. l] = j end
		end
	end
	local function gid(seg) return v.openGroup and (v.openGroup[seg] or seg) or 0 end
	-- only pairs with a new connection (the rule's own fold may already mix movements where lanes are short)
	local old = {}
	for _, c in ipairs(base.conns) do old[Rules.connsText({ c })] = true end
	for i, c in ipairs(r.conns) do
		for j = i + 1, #r.conns do
			local d = r.conns[j]
			if c.withRoad and d.withRoad and c.segment1 == d.segment1 and c.segment0 ~= d.segment0
				and v.open and v.open[c.segment1] and gid(c.segment0) == gid(d.segment0)
				and not (old[Rules.connsText({ c })] and old[Rules.connsText({ d })]) then
				local rc, rd = rank[cat[c.segment0 .. ">" .. c.segment1]], rank[cat[d.segment0 .. ">" .. d.segment1]]
				local pc, pd = pos[c.segment1 .. ":" .. c.lane1], pos[d.segment1 .. ":" .. d.lane1]
				if rc > rd then pc, pd = pd, pc end
				if rc ~= rd then
					ok(pc <= pd, string.format("%s: %s and %s cross", msg, Rules.connsText({ c }), Rules.connsText({ d })))
				end
			end
		end
	end
end

test("open: every T / X of 1-4 lanes in and 1-3 out, a stop on every road, lit / unlit / unknown: invariants", function()
	local P = { [1] = { 0, 0 }, [2] = { -60, 0 }, [3] = { 60, 0 }, [4] = { 0, 60 }, [5] = { 0, -60 } }
	local n, opened, stride, i = 0, 0, FULL and 1 or 7, 0
	for _, mirror in ipairs({ false, true }) do
		for a = 1, 4 do
			for b = 1, 3 do
				for c = 1, 4 do
					for d = 1, 3 do
						for _, t in ipairs({ true, false }) do
							i = i + 1
							if i % stride == 0 or (a == 1 and b == 1) or (a == 4 and b == 3 and c == 4 and d == 3) then
								local segs = { [11] = { 1, 2, roadSpec(a, b) }, [12] = { 1, 3, roadSpec(a, b) }, [13] = { 1, 4, roadSpec(c, d) } }
								if not t then segs[14] = { 1, 5, roadSpec(c, d) } end
								for _, lit in ipairs({ true, false, "unknown" }) do
									local msg = string.format("%s %d+%d / %d+%d%s lit=%s", t and "T" or "X", a, b, c, d, mirror and " LHT" or "", tostring(lit))
									local base = F.build(P, segs, mirror)
									local w = F.build(P, segs, mirror)
									if lit ~= "unknown" then
										base.lit = function() return lit end
										w.lit = function() return lit end
									end
									w.stops = function() return { { param = 0.5 } } end -- 30 m in on every road
									local rb, rw = planOf(base), planOf(w)
									if rw.view.case == "X" and rw.view.kind == "slip" then
										checkOpen(rw, rb, msg)
										if rw.view.open then opened = opened + 1 end
										if Rules.connsText(rw.conns) ~= Rules.connsText(rb.conns) then
											ok(logField(rw, "open") ~= "-", msg .. " changed only when open")
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
	end
	ok(n > 100, "cases " .. n)
	ok(opened > 50, "opened " .. opened)
end)

test("openExit: far turns widen to the neighbours' boundary lane per group; kerb turns and straights stay", function()
	local function pr(group, seg, lanes, extra)
		local map = {}
		for f, l in ipairs(lanes) do map[f] = { f, l } end
		return { group = group, ap = { seg = seg }, map = map, extra = extra }
	end
	local function text(adds)
		local out = {}
		for _, a in ipairs(adds) do out[#out + 1] = a.pr.ap.seg .. ":" .. a.f .. ">" .. a.lane end
		return table.concat(out, " ")
	end
	-- 2 lanes, kerb 1 + far 2 in one group: far down to 1
	eq(text(Cross.openExit({ pr("kerb", 1, { 1 }), pr("far", 2, { 2 }) }, 2, nil)), "2:1>1")
	-- a straight of the same group into 1-2 bounds the far turn at 2
	eq(text(Cross.openExit({ pr("kerb", 1, { 1 }), pr("straight", 3, { 1, 2 }), pr("far", 2, { 2 }) }, 2, nil)), "")
	-- the straight in another group: far down to 1
	eq(text(Cross.openExit({ pr("kerb", 1, { 1 }), pr("straight", 3, { 1, 2 }), pr("far", 2, { 2 }) }, 2,
		{ [1] = 1, [2] = 1, [3] = 3 })), "2:1>1")
	-- 3 lanes, a 2-feeder far turn alone: its kerb-most feeder takes lane 1
	eq(text(Cross.openExit({ pr("far", 2, { 2, 3 }) }, 3, nil)), "2:1>1")
	-- the kerb turn's fill-in lane (extra) bounds the far turn: kerb 1 (+2 filled), far 3 -> far 2-3
	eq(text(Cross.openExit({ pr("kerb", 1, { 1 }, { { 1, 2 } }), pr("far", 2, { 3 }) }, 3, nil)), "2:1>2")
	-- a far turn at the kerb side of a later far turn of the group widens outward up to it
	eq(text(Cross.openExit({ pr("far", 1, { 1 }), pr("far", 2, { 3 }) }, 3, nil)), "1:1>2 1:1>3")
end)

---------------------------------------------------------------------------
-- Audit

test("audit: an open exit's merges are shared_open (by design), not avoidable shared", function()
	for _, mirror in ipairs({ false, true }) do
		local w = build({ t = true, mirror = mirror, lit = true, stops = STOP(25) })
		local r = planOf(w)
		local res = Audit.audit(w, 1, r.conns, { view = r.view })
		eq(res.counts.shared, nil, "no avoidable shared")
		ok((res.forced.shared_open or 0) >= 1, "shared_open " .. Rules.countsText(res.forced))
		local wb = build({ t = true, mirror = mirror, lit = true })
		local rb = planOf(wb)
		local resb = Audit.audit(wb, 1, rb.conns, { view = rb.view })
		eq(resb.forced.shared_open, nil, "none without a stop")
	end
	eq(Audit.WEAVE_M, Cross.OPEN_M)
	eq(Cross.OPEN_M, 80)
end)

---------------------------------------------------------------------------
-- The game world (sl_write world.stops) and the automatic pass

--- A 2x2 T at node 901 (main 911 west / 912 east, side 913 north, 200 m) beside the probe ring.
local FX_T = {
	world = function()
		return F.merge(F.PROBE_4LANE_MEDIUM.world(), F.build(
			{ [901] = { 0, -800 }, [902] = { -60, -800 }, [903] = { 60, -800 }, [904] = { 0, -600 } },
			{ [911] = { 901, 902, F.TPL.medium }, [912] = { 901, 903, F.TPL.medium }, [913] = { 901, 904, F.TPL.medium } }))
	end,
	conns = F.PROBE_4LANE_MEDIUM.conns,
}

local function tBuild(G)
	local sp = { addedNodes = {}, addedSegments = {}, nodeConfigsToAdd = {}, nodeConfigsToRemove = {} }
	for _, id in ipairs({ 901, 902, 903, 904 }) do sp.addedNodes[#sp.addedNodes + 1] = { entity = id } end
	for _, id in ipairs({ 911, 912, 913 }) do
		local sg = G.world.segs[id]
		sp.addedSegments[#sp.addedSegments + 1] = { entity = id, comp = { node0 = sg.node0, node1 = sg.node1 } }
	end
	return { { proposal = sp, toAdd = {} }, {}, {}, true }
end

local function applyOf(G, node)
	for _, l in ipairs(G.kinds("APPLY")) do
		if l:find("node=" .. node .. " ", 1, true) then return l end
	end
end

test("world.stops: STOP_LEFT / STOP_RIGHT objects with their EDGE_OBJECT position and param; signals ignored", function()
	local Write = ug_require "square_smart_lanes::/smart_lanes/sl_write.lua"
	local G = makeGame(nil, FX_T)
	G.world.segs[913].objects = { { 5001, G.EOT.STOP_RIGHT }, { 5002, G.EOT.SIGNAL }, { 5003, G.EOT.STOP_LEFT } }
	G.edgeObjects[5001] = { param = 0.125, x = 8, y = -775 }
	G.edgeObjects[5003] = { param = 0.5 } -- no transf
	local W = Write.new(G.api, function() end)
	local w = W.makeWorld()
	local st = w.stops(913)
	eq(#st, 2, "two stops, the signal ignored")
	eq({ st[1].param, st[1].x, st[1].y }, { 0.125, 8, -775 })
	eq({ st[2].param, st[2].x }, { 0.5, nil })
	eq(w.stops(911), {}, "no objects")
	eq(w.stops(99999), nil, "no segment")
	eq(Cross.openOf(w, 901, 913), "stop", "25 m in")
	-- without the enum: the objects with a STATION component
	G.api.type.enum.EdgeObjectType = nil
	G.edgeObjects[5002] = nil
	local W2 = Write.new(G.api, function() end)
	eq(#W2.makeWorld().stops(913), 2, "by STATION")
	-- unreadable objects: none
	eq(W2.stopIdsOf({ objects = 5 }), {})
	eq(W2.stopIdsOf({}), {})
end)

test("automatic pass: a stop 25 m into the side road of a lit T: APPLY open=913:stop, the left turn into both lanes", function()
	local function run(withStop)
		local G = makeGame(nil, FX_T)
		G.lights[901] = true
		G.configs[901].trafficLightPreference = G.TLP.YES
		if withStop then
			G.world.segs[913].objects = { { 5001, G.EOT.STOP_RIGHT } }
			G.edgeObjects[5001] = { param = 0.125, x = 8, y = -775 }
		end
		G.gs.update({}, G.state, 0.1)
		G.frames(1)
		G.gs.handleEvent({}, G.state, "", "apply_command", "onPostBuildProposal", tBuild(G))
		G.frames(16)
		return G
	end
	local G, B = run(true), run(false)
	local a, b = applyOf(G, 901), applyOf(B, 901)
	ok(a and a:find(" open=913:stop", 1, true), a)
	ok(b and (b:find(" open=- ", 1, true) or b:sub(-7) == " open=-"), b)
	ok(G.kinds("AUDIT_SUMMARY")[1]:find("shared_open:1", 1, true), G.kinds("AUDIT_SUMMARY")[1])
	-- the far turn (911 west approach turning left into 913 in right-hand traffic) reaches both lanes
	local into = {}
	for _, c in ipairs(G.configs[901].laneConnections) do
		if c.withRoad and c.segment0 == 911 and c.segment1 == 913 then into[#into + 1] = c.lane1 end
	end
	eq(#into, 2, "left turn into both lanes: " .. Rules.connsText(G.configs[901].laneConnections))
	eq(#G.configs[901].laneConnections, #B.configs[901].laneConnections + 1)
	eq(#G.kinds("ERROR"), 0)
end)
