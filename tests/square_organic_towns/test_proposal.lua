-- ot_proposal: increment -> proposal spec (sources, D3 joint, config rule, -0).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local PR = ug_require(F.DIR .. "ot_proposal.lua")

local NEW_SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local NEW_LARGE = "::/infrastructure/street/town/town_new_large.street_template"
local OLD_SMALL = "::/infrastructure/street/town/town_old_small.street_template"

--- Two new edges from existing dead end 500 (its edge 900): 500 -> -3 -> -4; the second one a main street.
local function inc2(z)
	z = z or 0
	return {
		nodes = { { entity = -3, x = 100, y = 0, z = z }, { entity = -4, x = 200, y = 0, z = z } },
		edges = {
			{ entity = -1, node0 = 500, node1 = -3, p0 = { 0, 0, 5 }, p1 = { 100, 0, z }, t0 = { 100, 0, z - 5 },
				t1 = { 100, 0, z - 5 }, class = "small", template = NEW_SMALL, key = "h0:0" },
			{ entity = -2, node0 = -3, node1 = -4, p0 = { 100, 0, z }, p1 = { 200, 0, z }, t0 = { 100, 0, 0 },
				t1 = { 100, 0, 0 }, class = "main", template = NEW_LARGE, key = "h1:0" },
		},
		joins = { { node = 500, edge = -1 } },
	}
end

local function info(hasConfig)
	return {
		nodes = { [500] = { hasConfig = hasConfig, edges = { 900 }, lanes = 4, src = 900, template = OLD_SMALL } },
		sources = { [NEW_SMALL] = 901 },
		fallback = 902,
	}
end

test("junctionConns: the engine's pattern (every ordered pair, in lane i -> out lane m+1-i, no sidewalks)", function()
	local c = PR.junctionConns({ 10, 11, 12 }, 4)
	eq(#c, 6, "3-way node of a 2-lane street: 6 entries (probe Node dump)")
	eq(c[1], { 10, 1, 11, 2, true })
	eq(c[2], { 10, 1, 12, 2, true })
	eq(c[3], { 11, 1, 10, 2, true })
	local straight = PR.junctionConns({ 10, -1 }, 4)
	eq(straight, { { 10, 1, -1, 2, true }, { -1, 1, 10, 2, true } }, "straight joint: A.1>B.2 and B.1>A.2")
	local wide = PR.junctionConns({ 1, 2 }, 6)   -- 4 road lanes
	eq(wide, { { 1, 1, 2, 4, true }, { 1, 2, 2, 3, true }, { 2, 1, 1, 4, true }, { 2, 2, 1, 3, true } })
end)

test("build: the joining edge copies the dead end's edge; others copy by template or override", function()
	local spec = assert(PR.build(inc2(), info(true)))
	eq(#spec.edges, 2)
	local e1, e2 = spec.edges[1], spec.edges[2]
	eq(e1.src, 900, "joins copy the dead end's own edge (same lanes at the joint)")
	eq(e1.template, OLD_SMALL)
	eq(e1.override, nil)
	eq(e2.src, 902, "no town edge with the large template: fallback edge ...")
	eq(e2.override, NEW_LARGE, "... with the template overridden")
	eq(e1.key, "h0:0")
	eq(#spec.nodes, 2)
	eq(spec.nodes[1], { entity = -3, pos = { 100, 0, 0 } })
	local inc = inc2()
	inc.edges[2].template = NEW_SMALL
	local s2 = assert(PR.build(inc, info(true)))
	eq(s2.edges[2].src, 901)
	eq(s2.edges[2].override, nil)
end)

test("build: D3 joint config; the node is removed first only when it has a BASE_NODE_CONFIG", function()
	local spec = assert(PR.build(inc2(), info(true)))
	eq(spec.cfgRemove, { 500 })
	eq(#spec.cfgAdd, 3, "the joint plus both new nodes")
	eq(spec.cfgAdd[1].node, 500)
	eq(spec.cfgAdd[1].conns, { { 900, 1, -1, 2, true }, { -1, 1, 900, 2, true } })
	eq(spec.joins, { 500 })
	-- a node without config (one the mod built): refused unless allowed, and then add-only
	local s, why = PR.build(inc2(), info(false))
	eq(s, nil)
	eq(why, "noConfig:500")
	local inf = info(false)
	inf.allowNoConfig = true
	local s2 = assert(PR.build(inc2(), inf))
	eq(s2.cfgRemove, {}, "never remove a config that doesn't exist (Engine.cpp:693 crash)")
	eq(#s2.cfgAdd, 3)
end)

test("build: several new edges at one dead end all go into its config", function()
	local inc = inc2()
	inc.nodes[#inc.nodes + 1] = { entity = -6, x = 0, y = 100, z = 0 }
	inc.edges[#inc.edges + 1] = { entity = -5, node0 = -6, node1 = 500, p0 = { 0, 100, 0 }, p1 = { 0, 0, 5 },
		t0 = { 0, -100, 5 }, t1 = { 0, -100, 5 }, class = "small", template = NEW_SMALL, key = "v0:0" }
	local spec = assert(PR.build(inc, info(true)))
	eq(spec.cfgAdd[1].node, 500)
	eq(#spec.cfgAdd[1].conns, 6, "3 segments x 2 others x 1 lane")
	eq(spec.edges[3].src, 900)
end)

test("build refuses: unknown join node, bad lanes, no source, empty", function()
	local inf = info(true)
	inf.nodes = {}
	local s, why = PR.build(inc2(), inf)
	eq(s, nil)
	eq(why, "unknownNode:500")
	inf = info(true)
	inf.nodes[500].lanes = 3
	s, why = PR.build(inc2(), inf)
	eq(why, "lanes:500:3")
	inf = info(true)
	inf.fallback = nil
	s, why = PR.build(inc2(), inf)
	eq(why, "noSource")
	s, why = PR.build({ nodes = {}, edges = {}, joins = {} }, info(true))
	eq(why, "empty")
end)

test("build: every new node gets an engine-pattern config (a 1-edge node an empty one)", function()
	local spec = assert(PR.build(inc2(), info(true)))
	local byNode = {}
	for _, c in ipairs(spec.cfgAdd) do byNode[c.node] = c end
	for _, nd in ipairs(spec.nodes) do ok(byNode[nd.entity] ~= nil, "config for new node " .. nd.entity) end
	for _, n in ipairs(spec.cfgRemove) do ok(n > 0, "only existing nodes are removed") end
end)

test("build: every -0 in positions and tangents becomes +0", function()
	local inc = inc2(-0.0)
	inc.edges[2].t0 = { 100, -0.0, -0.0 }
	inc.edges[2].t1 = { -0.0, 100, -0.0 }
	inc.nodes[1].y = -0.0
	local spec = assert(PR.build(inc, info(true)))
	ok(PR.noNegativeZero(spec))
	ok(1 / spec.edges[2].t0[2] > 0)
	ok(1 / spec.nodes[1].pos[2] > 0)
	local bad = { nodes = { { entity = -1, pos = { 0, -0.0, 0 } } }, edges = {} }
	ok(not PR.noNegativeZero(bad))
end)

test("summary names the joins and the removed configs", function()
	local spec = assert(PR.build(inc2(), info(true)))
	eq(PR.summary(spec), "edges=2 nodes=2 joins=500 cfgRemove=500 cfgAdd=3 override=1")
end)

test("junctionConns: mixed widths use each street's own lanes", function()
	local c = PR.junctionConns({ 1, 2 }, { [1] = 4, [2] = 6 })
	-- 4 lanes: 2 road lanes (half 1); 6 lanes: 4 road lanes (half 2) -> one connection each way
	eq(c, { { 1, 1, 2, 4, true }, { 2, 1, 1, 2, true } })
	for _, x in ipairs(PR.junctionConns({ 1, 2, 3 }, { [1] = 4, [2] = 6, [3] = 8 })) do
		local lanes = ({ 4, 6, 8 })[x[3]]
		ok(x[4] >= 1 and x[4] <= lanes - 2, "lane index inside the target street")
	end
end)

test("build: every lane index is valid for its segment (templates x eras x joins x overrides)", function()
	local sizes = { "xsmall", "small", "medium", "large" }
	local lanesBy = { xsmall = 4, small = 4, medium = 6, large = 8 }
	local function path(era, size) return "::/infrastructure/street/town/town_" .. era .. "_" .. size .. ".street_template" end
	local n = 0
	for _, era in ipairs({ "old", "new" }) do
		for _, deadSize in ipairs(sizes) do
			for _, aSize in ipairs(sizes) do
				for _, bSize in ipairs(sizes) do
					for _, overrideMode in ipairs({ "source", "override", "overrideNoRes" }) do
						-- dead end 500 (edge 900, deadSize) and dead end 600 (edge 910, a different size): edge -1 joins
						-- 500, -2 continues to new node -5, -3 joins -5 to 600 (an edge between a new node and a
						-- second existing node), -4 a branch at -5 (a 3-way new node with three widths)
						local A, B = path(era, aSize), path(era, bSize)
						local other = sizes[(#deadSize % 4) + 1]
						local inc = {
							nodes = { { entity = -5, x = 100, y = 0, z = 0 }, { entity = -6, x = 100, y = 100, z = 0 } },
							edges = {
								{ entity = -1, node0 = 500, node1 = -5, p0 = { 0, 0, 0 }, p1 = { 100, 0, 0 }, t0 = { 100, 0, 0 }, t1 = { 100, 0, 0 }, class = "small", template = A, key = "a" },
								{ entity = -3, node0 = -5, node1 = 600, p0 = { 100, 0, 0 }, p1 = { 200, 0, 0 }, t0 = { 100, 0, 0 }, t1 = { 100, 0, 0 }, class = "main", template = B, key = "b" },
								{ entity = -4, node0 = -5, node1 = -6, p0 = { 100, 0, 0 }, p1 = { 100, 100, 0 }, t0 = { 0, 100, 0 }, t1 = { 0, 100, 0 }, class = "medium", template = B, key = "c" },
								{ entity = -2, node0 = -6, node1 = 500, p0 = { 100, 100, 0 }, p1 = { 0, 0, 0 }, t0 = { -100, -100, 0 }, t1 = { -100, -100, 0 }, class = "small", template = A, key = "d" },
							},
							joins = {},
						}
						local inf = {
							nodes = {
								[500] = { hasConfig = true, edges = { 900 }, lanes = lanesBy[deadSize], src = 900, template = path(era, deadSize) },
								[600] = { hasConfig = true, edges = { 910 }, lanes = lanesBy[other], src = 910, template = path(era, other) },
							},
							sources = overrideMode == "source" and { [A] = 920, [B] = 921 } or {},
							fallback = 902,
							edgeLanes = { [920] = lanesBy[aSize], [921] = lanesBy[bSize], [902] = 4 },
							templateLanes = overrideMode == "override" and { [A] = lanesBy[aSize], [B] = lanesBy[bSize] } or nil,
						}
						local spec, why = PR.build(inc, inf)
						ok(spec ~= nil, "built: " .. tostring(why))
						local lanes = spec.lanes
						for _, c in ipairs(spec.cfgAdd) do
							for _, cn in ipairs(c.conns) do
								for k = 0, 1 do
									local seg, lane = cn[1 + 2 * k], cn[2 + 2 * k]
									local L = lanes[seg]
									ok(L ~= nil and lane >= 1 and lane <= L - 2,
										string.format("%s %s/%s/%s %s: node %s seg %s lane %s of %s", era, deadSize, aSize, bSize,
											overrideMode, c.node, seg, lane, tostring(L)))
									n = n + 1
								end
							end
						end
						-- the edges' lane counts are their own street's (the join edges copy the dead end; §73: a narrower
						-- town street joining a medium / large dead end keeps its own)
						local function joined(mine, dead)
							return PR.narrowJoin(path(era, mine), path(era, dead)) and lanesBy[mine] or lanesBy[dead]
						end
						eq(lanes[-1], joined(aSize, deadSize))
						eq(lanes[-3], joined(bSize, other))
						eq(lanes[-4], lanesBy[bSize])
					end
				end
			end
		end
	end
	ok(n > 1000, "checked " .. n .. " lane references")
end)

test("checkLanes catches an index past the segment's lanes (the showcase's '6 >= 4')", function()
	local spec = { cfgAdd = { { node = 1, conns = { { 10, 1, 11, 6, true } } } } }
	local okL, bad = PR.checkLanes(spec, function(seg) return seg == 11 and 4 or 8 end)
	eq(okL, false)
	eq(bad[1].seg, 11)
	eq(PR.pathLanes("::/infrastructure/street/town/town_old_medium.street_template"), 6)
	eq(PR.pathLanes("::/infrastructure/street/town/town_new_xsmall.street_template"), 4)
	eq(PR.pathLanes("x"), nil)
end)

test("junctionConnsDir: equals junctionConns on two-way nodes (lane mixes); one-way segments in / out", function()
	for _, mix in ipairs({ { 4, 4, 4 }, { 4, 6 }, { 6, 8, 4, 4 }, { 8, 8 }, { 6, 4, 6 } }) do
		local segs, lanes, info = {}, {}, {}
		for i, n in ipairs(mix) do
			segs[i] = i % 2 == 0 and -i or 100 + i
			lanes[segs[i]] = n
			info[segs[i]] = { lanes = n }
		end
		eq(PR.junctionConnsDir(segs, info), PR.junctionConns(segs, lanes), table.concat(mix, "/"))
	end
	local ins, outs = PR.laneSets(4, "in")
	eq(ins, { 1, 2 }); eq(outs, {})
	ins, outs = PR.laneSets(4, "out")
	eq(ins, {}); eq(outs, { 2, 1 })
	ins, outs = PR.laneSets(6)
	eq(ins, { 1, 2 }); eq(outs, { 4, 3 })
	-- a one-way ring node: 10 arrives, 11 leaves, 12 is a two-way arm
	local c = PR.junctionConnsDir({ 10, 11, 12 }, { [10] = { lanes = 4, oneway = "in" }, [11] = { lanes = 4, oneway = "out" },
		[12] = { lanes = 4 } })
	eq(c, { { 10, 1, 11, 2, true }, { 10, 2, 11, 1, true }, { 10, 1, 12, 2, true }, { 12, 1, 11, 2, true },
		{ 12, 1, 11, 1, true } })
end)

-- Invariant (crash 2026-10-11: script nodes without BASE_NODE_CONFIG crashed the simulation): every new node of
-- every spec the main path builds has a config entry, every lane index exists, over real planner increments
-- (several styles and terrains, joins at existing nodes of any degree).
test("invariant: every new node of every main-path spec gets a config (planner increments, many styles)", function()
	local OG = ug_require(F.DIR .. "ot_graph.lua")
	local core = ug_require(F.DIR .. "ot_core.lua")
	local specs, nodes = 0, 0
	for _, id in ipairs({ "NA_GRID", "NA_SUBURB", "EU_ORGANIC", "EU_EXTENSION", "MED_HILL", "JP_DENSE", "NORDIC" }) do
		for _, sampler in ipairs({ F.flat, F.hill }) do
			local style, stats = F.style({ forceStyle = id, townId = 11, year = 1960 }, sampler)
			local g = OG.new()
			for k = 1, 5 do
				local inc = core.planIncrement(g, style, { terrain = sampler, stats = stats, join = "any" })
				if #inc.edges == 0 then break end
				local inf = { nodes = {}, sources = {}, fallback = 902 }
				for _, j in ipairs(inc.joins) do
					local edges = {}
					for _, eid in ipairs(g.adj[j.node] or {}) do edges[#edges + 1] = eid end
					inf.nodes[j.node] = { hasConfig = true, edges = edges, lanes = 4, src = edges[1] or 902, template = NEW_SMALL }
				end
				local spec, err = PR.build(inc, inf)
				ok(spec ~= nil, id .. " " .. tostring(err))
				if spec then
					specs = specs + 1
					local cfg = {}
					for _, c in ipairs(spec.cfgAdd) do cfg[c.node] = true end
					for _, e in ipairs(spec.edges) do
						for _, n in ipairs({ e.node0, e.node1 }) do
							if n < 0 then ok(cfg[n], id .. " new node " .. n .. " without a config") end
						end
					end
					for _, nd in ipairs(spec.nodes) do
						nodes = nodes + 1
						ok(cfg[nd.entity], id .. " spec node " .. nd.entity)
					end
					ok(PR.checkLanes(spec, function(seg) return spec.lanes[seg] or 4 end))
				end
				OG.apply(g, inc, k)
			end
		end
	end
	ok(specs >= 30 and nodes > 100, specs .. " specs, " .. nodes .. " new nodes")
end)

test("junctionConnsDir: an arm entering a one-way ring may take every ring lane (engine node dump)", function()
	-- ring in 141512 (one-way, 4 lanes), ring out 141509 (one-way), arm 141513 (two-way small); node 6635
	local info = { [1] = { lanes = 4, oneway = "in" }, [2] = { lanes = 4, oneway = "out" }, [3] = { lanes = 4 } }
	local got = PR.junctionConnsDir({ 1, 2, 3 }, info)
	local set = {}
	for _, c in ipairs(got) do set[c[1] .. "." .. c[2] .. ">" .. c[3] .. "." .. c[4]] = true end
	for _, k in ipairs({ "1.1>2.2", "1.2>2.1", "1.1>3.2", "3.1>2.1", "3.1>2.2" }) do ok(set[k], "engine conn " .. k) end
	eq(#got, 5)
end)

test("junctionConnsDir: the engine's one-way ring pattern with wide arms and 4-lane rings (findings roads.md)", function()
	local function set(list)
		local out = {}
		for _, c in ipairs(list) do out[c[1] .. "." .. c[2] .. ">" .. c[3] .. "." .. c[4]] = true end
		return out
	end
	-- 2-lane ring (4 incl. sidewalks), 6-lane arm (2 lanes each way: in {1, 2}, out {4, 3})
	local c = PR.junctionConnsDir({ 1, 2, 3 }, { [1] = { lanes = 4, oneway = "in" }, [2] = { lanes = 4, oneway = "out" },
		[3] = { lanes = 6 } })
	local s = set(c)
	ok(s["1.1>3.4"] and s["1.1>3.3"], "the outermost ring lane exits into every arm exit lane")
	ok(not s["1.2>3.4"] and not s["1.2>3.3"], "the inner ring lane does not exit")
	ok(s["1.1>2.2"] and s["1.2>2.1"], "ring lanes continue in their own lane")
	ok(s["3.1>2.2"] and s["3.2>2.1"], "right entry lane -> outer ring lane, left -> inner")
	eq(#c, 6)
	-- 4-lane ring (6 incl. sidewalks: in {1..4}, out {4..1}), small arm: the entry lane fans over all ring lanes
	c = PR.junctionConnsDir({ 1, 2, 3 }, { [1] = { lanes = 6, oneway = "in" }, [2] = { lanes = 6, oneway = "out" },
		[3] = { lanes = 4 } })
	s = set(c)
	for k = 1, 4 do ok(s["1." .. k .. ">2." .. (5 - k)], "ring lane " .. k .. " continues") end
	ok(s["1.1>3.2"] and not s["1.2>3.2"], "only the outer ring lane exits")
	for j = 1, 4 do ok(s["3.1>2." .. j], "entry fans to ring lane " .. j) end
	eq(#c, 4 + 1 + 4)
	-- 4-lane ring, 6-lane arm: right entry lane -> the two outer ring lanes, left -> the two inner ones
	c = PR.junctionConnsDir({ 1, 2, 3 }, { [1] = { lanes = 6, oneway = "in" }, [2] = { lanes = 6, oneway = "out" },
		[3] = { lanes = 6 } })
	s = set(c)
	ok(s["3.1>2.4"] and s["3.1>2.3"] and s["3.2>2.2"] and s["3.2>2.1"])
	ok(not s["3.1>2.1"] and not s["3.2>2.4"])
	-- nothing the wrong way round the ring
	for _, x in ipairs(c) do
		ok(x[3] ~= 1, "nothing into the arriving ring edge")
		ok(x[1] ~= 2, "nothing out of the leaving ring edge")
		ok(x[2] >= 1 and x[2] <= 4 and x[4] >= 1, "lane indices exist")
	end
end)

-- Left-hand traffic (user report 2026-10-20 with the Left Hand Traffic mod `left_hand_traffic_1`: misaligned junction
-- lane connections; the mod reverses `forward` of every two-way street template's road lanes).
test("leftHandFrom: the driving side from a template's road lanes", function()
	eq(PR.leftHandFrom({ false, true }), false, "base town_*_small: backward on the left")
	eq(PR.leftHandFrom({ false, false, false, true, true, true }), false, "base town_new_large")
	eq(PR.leftHandFrom({ true, false }), true, "Left Hand Traffic mod: flipped")
	eq(PR.leftHandFrom({ true, true, false, false }), true)
	eq(PR.leftHandFrom({ true, true }), nil, "one-way: no side")
	eq(PR.leftHandFrom({}), nil)
	eq(PR.leftHandFrom(nil), nil)
end)

test("junctionConns leftHand: the mirror image of the right-hand pattern (each street's own lanes)", function()
	eq(PR.junctionConns({ 10, -1 }, 4, true), { { 10, 2, -1, 1, true }, { -1, 2, 10, 1, true } },
		"straight joint: in lane 2 (right half from the node) -> out lane 1")
	eq(PR.junctionConns({ 1, 2 }, { [1] = 4, [2] = 6 }, true), { { 1, 2, 2, 1, true }, { 2, 4, 1, 1, true } })
	local mixes = { 4, { [1] = 4, [2] = 6, [3] = 8 }, { [1] = 8, [2] = 4, [3] = 6 }, 8 }
	for _, lanes in ipairs(mixes) do
		local function m(s) return (type(lanes) == "table" and lanes[s] or lanes) - 2 end
		local r, l = PR.junctionConns({ 1, 2, 3 }, lanes), PR.junctionConns({ 1, 2, 3 }, lanes, true)
		eq(#l, #r)
		for i, x in ipairs(r) do
			eq(l[i], { x[1], m(x[1]) + 1 - x[2], x[3], m(x[3]) + 1 - x[4], true }, "lane k -> m + 1 - k on both sides")
			ok(l[i][2] > m(x[1]) / 2 and l[i][4] <= m(x[3]) / 2, "in from the right half, out to the left half")
		end
	end
end)

test("build leftHand: every node config mirrored; one-way edges refused", function()
	local inf = info(true)
	local r = assert(PR.build(inc2(), inf))
	inf.leftHand = true
	local l = assert(PR.build(inc2(), inf))
	eq(#l.cfgAdd, #r.cfgAdd)
	for i, c in ipairs(l.cfgAdd) do
		eq(c.node, r.cfgAdd[i].node)
		eq(#c.conns, #r.cfgAdd[i].conns)
		for k, x in ipairs(c.conns) do
			local y = r.cfgAdd[i].conns[k]
			eq({ x[1], x[3] }, { y[1], y[3] })
			ok(x[2] ~= y[2] or x[4] ~= y[4], "a different lane pair than right-hand traffic")
		end
	end
	local inc = inc2()
	inc.edges[2].oneway = true
	local spec, why = PR.build(inc, inf)
	eq(spec, nil)
	eq(why, "leftHandOneway")
end)
