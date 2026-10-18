-- otd_roundabout: square_roundabouts' pure geometry reused for a 4-arm roundabout at a town dead end.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns_dev/"
local RB_DIR = here .. "../../mods/square_roundabouts/content"
local MAIN_DIR = here .. "../../mods/square_organic_towns/content"
local cache = {}
local function req(path)
	if cache[path] ~= nil then return cache[path] end
	local mod, rel = path:match("^([%w_]+)::(/.*)$")
	local dir = mod == "square_roundabouts" and RB_DIR or (mod == "square_organic_towns" and MAIN_DIR) or nil
	if dir == nil then error("module not found: " .. path) end
	local env = setmetatable({ ug_require = req }, { __index = _ENV })
	local m = assert(loadfile(dir .. rel, "t", env))()
	cache[path] = m
	return m
end
local RB = ug_require "/organic_towns_dev/otd_roundabout.lua"
local PR = req "square_organic_towns::/organic_towns/ot_proposal.lua"

local function d(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end

test("load: the presence file and the geometry module of square_roundabouts", function()
	local geom = RB.load(req)
	ok(geom ~= nil and geom.build ~= nil)
	local none, why = RB.load(function() error("missing") end)
	eq(none, nil)
	eq(why, "noMod")
end)

test("local plan: 4 ring edges (one-way small) and 4 arms; sizes grow", function()
	local geom = RB.load(req)
	local last = 0
	for i, size in ipairs(RB.SIZES) do
		local lp = assert(RB.localPlan(geom, size))
		eq(#lp.ring, 4)
		eq(#lp.arms, 4)
		eq(lp.ringTemplate, RB.ONEWAY)
		ok(lp.reach > last, RB.SIZE_NAMES[i] .. " reach " .. lp.reach)
		last = lp.reach
	end
end)

local SMALL = "::/infrastructure/street/town/town_new_small.street_template"

local function specFor(wp, mode, lanes, ringLanes)
	return RB.spec(wp, { deadEnd = 77, deadEdge = 900, lanes = lanes or 4, hasConfig = true, src = 900, template = SMALL,
		ringMode = mode, ringLanes = ringLanes, junctionConns = PR.junctionConns,
		junctionConnsDir = PR.junctionConnsDir })
end

--- Lane count of every segment of a spec (the dead end's edge 900 included).
local function lanesOf(spec, deadLanes)
	return function(seg)
		if seg == 900 then return deadLanes or 4 end
		return spec.lanes[seg]
	end
end

test("place + spec: arm 0 ends on the dead end, ring ahead, D3 joint valid, every new node has a config, no -0", function()
	local geom = RB.load(req)
	local lp = assert(RB.localPlan(geom, 2))
	-- dead end at (500, 300) whose street runs out toward +y rotated 30 deg
	local a = math.rad(120)
	local dx, dy = math.cos(a), math.sin(a)
	local wp = RB.place(lp, 500, 300, 5, dx, dy)
	near(d(wp.centre, { 500 + dx * lp.reach, 300 + dy * lp.reach }), 0, 1e-6)
	eq(wp.nodes.join, { 500, 300, 5 })
	for _, mode in ipairs({ "oneway", "town" }) do
		local spec = assert(specFor(wp, mode))
		eq(#spec.edges, 8)
		eq(#spec.nodes, 7, "4 ring nodes + 3 free arm ends")
		eq(spec.cfgRemove, { 77 })
		eq(#spec.cfgAdd, 8, "the joined dead end + every new node (crash: script nodes without a config)")
		eq(spec.newConfigs, 7)
		eq(spec.cfgAdd[1].node, 77)
		eq(#spec.cfgAdd[1].conns, 2, "straight joint: both directions")
		ok(PR.noNegativeZero(spec))
		local joins, rings, overrides = 0, 0, 0
		for _, e in ipairs(spec.edges) do
			if e.node0 == 77 or e.node1 == 77 then joins = joins + 1 end
			if spec.roles[e.entity] == "ring" then rings = rings + 1 end
			if e.override then overrides = overrides + 1 end
			ok(e.src == 900)
		end
		eq(joins, 1)
		eq(rings, 4)
		eq(overrides, mode == "oneway" and 4 or 0)
		local okL, bad = PR.checkLanes(spec, lanesOf(spec))
		ok(okL, mode .. " lanes " .. tostring(bad[1] and bad[1].seg))
		-- ring nodes: 3 segments -> connections; arm ends: an empty config
		local byNode = {}
		for _, c in ipairs(spec.cfgAdd) do byNode[c.node] = c end
		local ringNodes, ends = 0, 0
		for _, nd in ipairs(spec.nodes) do
			local c = byNode[nd.entity]
			ok(c ~= nil, "config for node " .. nd.entity)
			if #c.conns == 0 then ends = ends + 1 else ringNodes = ringNodes + 1 end
		end
		eq(ringNodes, 4)
		eq(ends, 3)
		-- two-way ring: the engine pattern (6 per 3-way node); one-way: ring in -> ring out (2), ring in -> arm (1),
		-- arm -> ring out (both ring lanes: 2), as the engine's own node (Node dump 2026-10-11)
		for _, nd in ipairs(spec.nodes) do
			local c = byNode[nd.entity]
			if #c.conns > 0 then eq(#c.conns, mode == "town" and 6 or 5, mode .. " node " .. nd.entity) end
		end
	end
	-- ring edges keep the geometry's radius around the centre
	for _, e in ipairs(wp.edges) do
		if e.role == "ring" then near(d(e.p0, wp.centre), lp.R, 1e-6) end
	end
end)

test("ring direction: consecutive ring edges chain node1 -> node0 (forward = the one-way travel direction)", function()
	local geom = RB.load(req)
	local wp = RB.place(assert(RB.localPlan(geom, 1)), 0, 0, 0, 1, 0)
	local spec = assert(specFor(wp, "oneway"))
	local starts, ends = {}, {}
	for _, e in ipairs(spec.edges) do
		if spec.roles[e.entity] == "ring" then
			starts[e.node0] = (starts[e.node0] or 0) + 1
			ends[e.node1] = (ends[e.node1] or 0) + 1
		end
	end
	for n, k in pairs(starts) do
		eq(k, 1, "one ring edge leaves " .. n)
		eq(ends[n], 1, "one ring edge arrives at " .. n)
	end
end)

test("one-way ring node pattern: in-ring -> out-ring (both lanes), in-ring -> arm out, arm in -> out-ring", function()
	local geom = RB.load(req)
	local wp = RB.place(assert(RB.localPlan(geom, 2)), 0, 0, 0, 1, 0)
	local spec = assert(specFor(wp, "oneway"))
	for _, c in ipairs(spec.cfgAdd) do
		if c.node < 0 and #c.conns > 0 then
			local rin, rout, arm
			for _, e in ipairs(spec.edges) do
				if e.node0 == c.node or e.node1 == c.node then
					if spec.roles[e.entity] == "ring" then
						if e.node1 == c.node then rin = e.entity else rout = e.entity end
					else arm = e.entity end
				end
			end
			ok(rin and rout and arm)
			local set = {}
			for _, cn in ipairs(c.conns) do set[string.format("%d.%d>%d.%d", cn[1], cn[2], cn[3], cn[4])] = true end
			-- node-relative: arriving one-way in {1, 2} (outer first), leaving out {2, 1}; arm in {1}, out {2}
			ok(set[rin .. ".1>" .. rout .. ".2"] and set[rin .. ".2>" .. rout .. ".1"], "ring through, both lanes")
			ok(set[rin .. ".1>" .. arm .. ".2"], "ring -> arm on the outer lane")
			ok(set[arm .. ".1>" .. rout .. ".2"], "arm -> ring on the outer lane")
			for _, cn in ipairs(c.conns) do
				ok(cn[3] ~= rin, "nothing into the arriving ring edge")
				ok(cn[1] ~= rout, "nothing out of the leaving ring edge")
			end
		end
	end
end)

test("one-way ring needs no toggle; 6-lane arms and a 4-lane ring keep valid lanes and the engine pattern", function()
	local geom = RB.load(req)
	local wp = RB.place(assert(RB.localPlan(geom, 2)), 0, 0, 0, 1, 0)
	ok(specFor(wp, "oneway"), "one-way by default, no experimental gate")
	ok(specFor(wp, "town"), "the two-way ring (fallback)")
	for _, mode in ipairs({ "town", "oneway" }) do
		local spec = assert(specFor(wp, mode, 6))
		ok(PR.checkLanes(spec, lanesOf(spec, 6)), mode .. " with 6-lane arms")
	end
	for _, lanes in ipairs({ 4, 6 }) do
		local spec = assert(specFor(wp, "oneway", lanes, 6))
		ok(PR.checkLanes(spec, lanesOf(spec, lanes)), "4-lane ring, arms " .. lanes)
		for _, c in ipairs(spec.cfgAdd) do
			if c.node < 0 and #c.conns > 0 then
				local rin, rout, arm
				for _, e in ipairs(spec.edges) do
					if e.node0 == c.node or e.node1 == c.node then
						if spec.roles[e.entity] == "ring" then
							if e.node1 == c.node then rin = e.entity else rout = e.entity end
						else arm = e.entity end
					end
				end
				for _, cn in ipairs(c.conns) do
					if cn[1] == rin and cn[3] == arm then eq(cn[2], 1, "only the outermost ring lane exits") end
					if cn[1] == rin and cn[3] == rout then eq(cn[4], 5 - cn[2], "ring lanes continue in their own lane") end
				end
			end
		end
	end
end)

test("invariant: every roundabout spec (both rings x 3 sizes x headings) configures every new node", function()
	local geom = RB.load(req)
	for _, size in ipairs(RB.SIZES) do
		local lp = assert(RB.localPlan(geom, size))
		for k = 0, 7 do
			local a = k * math.pi / 4
			local wp = RB.place(lp, 100 * k, -50 * k, 3, math.cos(a), math.sin(a))
			for _, mode in ipairs({ "town", "oneway" }) do
				for _, lanes in ipairs({ 4, 6 }) do
					local spec = assert(specFor(wp, mode, lanes))
					local cfg = {}
					for _, c in ipairs(spec.cfgAdd) do cfg[c.node] = true end
					for _, e in ipairs(spec.edges) do
						for _, n in ipairs({ e.node0, e.node1 }) do
							if n < 0 then ok(cfg[n], string.format("size %d %s node %d", size, mode, n)) end
						end
					end
					for _, nd in ipairs(spec.nodes) do ok(cfg[nd.entity]) end
					ok(PR.checkLanes(spec, lanesOf(spec, lanes)))
					ok(PR.noNegativeZero(spec))
				end
			end
		end
	end
end)

test("pick: camera nearest, or the farthest frontier dead end on a main street", function()
	local c = {
		{ node = 1, d = 300, cls = "small", near = 50 },
		{ node = 2, d = 500, cls = "small", near = 900 },
		{ node = 3, d = 350, cls = "medium", near = 400 },
	}
	eq(RB.pick(c, "camera").node, 1)
	eq(RB.pick(c, "frontier").node, 3)
	eq(RB.pick({}, "camera"), nil)
end)

local ND = ug_require "/organic_towns_dev/otd_nodedump.lua"

test("node dump: lane roles from edge end + forward flags; our pattern compared", function()
	-- a one-way ring node 5: ring edge 10 arrives (node1), ring edge 11 leaves (node0), arm 12 two-way leaves
	local node = { id = 5, x = 0, y = 0, z = 0, dist = 3, segs = { 10, 11, 12 }, config = true, crosswalks = 1,
		edges = {
			[10] = { id = 10, n0 = 4, n1 = 5, lanes = 4, template = "x/town_new_one_way_small.street_template",
				forward = { true, true, true, false } },
			[11] = { id = 11, n0 = 5, n1 = 6, lanes = 4, template = "x/town_new_one_way_small.street_template",
				forward = { true, true, true, false } },
			[12] = { id = 12, n0 = 5, n1 = 7, lanes = 4, template = "x/town_new_small.street_template",
				forward = { false, false, true, true } },
		},
		conns = { { 10, 1, 11, 2, true, false }, { 12, 1, 11, 2, true, false }, { 11, 1, 12, 2, true, false } } }
	-- arriving one-way: node lane 1 = edge lane 2 (forward) -> in
	local el, fwd, role = ND.laneRole(node.edges[10], 5, 1)
	eq(el, 2); eq(fwd, true); eq(role, "in")
	-- leaving one-way: node lane 2 = edge lane 2, forward -> out
	el, fwd, role = ND.laneRole(node.edges[11], 5, 2)
	eq(el, 2); eq(role, "out")
	-- two-way leaving: node lane 1 = edge lane 1 backward -> in; lane 2 forward -> out
	eq(select(3, ND.laneRole(node.edges[12], 5, 1)), "in")
	eq(select(3, ND.laneRole(node.edges[12], 5, 2)), "out")
	ok(ND.oneWay(node.edges[10]) and not ND.oneWay(node.edges[12]))
	local head, conns = ND.fields(node)
	eq(#conns, 3)
	local text = {}
	for _, f in ipairs(head) do text[#text + 1] = f[1] .. "=" .. tostring(f[2]) end
	ok(table.concat(text, " "):find("deg=3", 1, true))
	local last = conns[3]
	local okF
	for _, f in ipairs(last) do if f[1] == "ok" then okF = f[2] end end
	eq(okF, false, "11.1 is an outgoing lane: a connection from it is flagged")
	local ours = ND.ours(node, PR.junctionConnsDir)
	local set = {}
	for _, c in ipairs(ours) do set[c] = true end
	ok(set["10.1>11.2"] and set["10.2>11.1"] and set["10.1>12.2"] and set["12.1>11.2"] and set["12.1>11.1"],
		table.concat(ours, ","))
	eq(#ours, 5)
end)
