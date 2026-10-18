-- Organic Towns: planner increment -> proposal spec (pure). ot_engine turns the spec into api objects
-- (SimpleProposal) without further decisions, so every rule lives here and is tested offline.
--
-- Rules (docs/findings.md "Organic Towns probe", HANDOFF "What is proven in game"):
--   * Every new edge copies BASE_EDGE / BASE_EDGE_STREET of an existing town street edge (`src`): one with the
--     wanted template when the town has one, else any town street with the template overridden (`override`:
--     roadTemplate, laneConfigs and roadStyle from the template resource, as Stress Test's street from scratch).
--   * An edge that ends at an existing dead end copies that dead end's own edge (same lanes and template), so
--     the joint gets one lane layout.
--   * Joint (D3): plain join (the new edge names the existing node) plus a full node config in the engine
--     pattern: for every ordered pair of different segments at the node, incoming road lane i -> outgoing
--     lane m + 1 - i (m road lanes, sidewalks excluded; indices count from the node), withRoad.
--     The node goes into nodeConfigsToRemove ONLY if it has a BASE_NODE_CONFIG (removing a missing config
--     asserts Engine.cpp:693 and crashes). Nodes without a config (nodes a script built) are not joined at
--     all unless `allowNoConfig` (off until verified in game).
--   * Every number goes through z0 (no -0: docs/findings.md "Negative zero").
--
-- spec = { nodes = { { entity, pos = {x, y, z} } },
--          edges = { { entity, node0, node1, p0, p1, t0, t1, class, template, src, override = path|nil,
--                      key } },
--          cfgRemove = { node id }, cfgAdd = { { node, conns = { { seg0, lane0, seg1, lane1, withRoad } } } },
--          joins = { node id } }
-- Segment ids in conns: existing edge ids (> 0) or the new edge's entity (< 0, as in the SimpleProposal).

local G = ug_require "square_organic_towns::/organic_towns/ot_geom.lua"

local M = {}

local z0 = G.z0

local function v3(v)
	return { z0(v[1] or 0), z0(v[2] or 0), z0(v[3] or 0) }
end

--- Lane connections at a junction of `segs` (all with nLanes lanes including the two sidewalks), as the
--- engine writes them: every ordered pair of different segments, incoming road lane i (1..m/2) -> outgoing
--- lane m + 1 - i. Entries { seg0, lane0, seg1, lane1, true }. (Probe Node dump 2026-10-11: a game-made
--- 3-way node of town_new_small had exactly these 6 entries; the probe's D3 joint with them shows no
--- dead-end sign.)
--- nLanes is one count for all segments, or a table { [segment] = count } (streets of different widths at one
--- node: each side uses its own lanes, connecting min(halfA, halfB) lanes per pair).
function M.junctionConns(segs, nLanes)
	local function m(seg)
		local n = type(nLanes) == "table" and nLanes[seg] or nLanes
		return (tonumber(n) or 4) - 2
	end
	local out = {}
	for _, a in ipairs(segs) do
		for _, b in ipairs(segs) do
			if a ~= b then
				local mb = m(b)
				local half = math.min(math.floor(m(a) / 2), math.floor(mb / 2))
				for i = 1, half do out[#out + 1] = { a, i, b, mb + 1 - i, true } end
			end
		end
	end
	return out
end

--- Incoming and outgoing road lanes of one segment at a node, outer lane first, in node-relative indices
--- (LaneConnection: "zero-based, from left to right when looking from the Node to the segment", type.d.tl).
--- lanes = count incl. the two sidewalks; oneway = nil (two-way: the left half comes in, the right half goes
--- out), "in" (a one-way street arriving at the node: every road lane comes in) or "out" (leaving: every road
--- lane goes out). Two-way m road lanes, h = m/2: in {1..h}, out {m, m-1, ..., m-h+1} (the engine's own
--- pattern pairs in[k] with out[k]: outer with outer). One-way arriving: looking from the node, the travel
--- direction's right (outer) lane is on the left, so in {1..m}; leaving: out {m, ..., 1}.
function M.laneSets(lanes, oneway)
	local m = (tonumber(lanes) or 4) - 2
	local ins, outs = {}, {}
	if oneway == "in" then
		for i = 1, m do ins[#ins + 1] = i end
	elseif oneway == "out" then
		for i = m, 1, -1 do outs[#outs + 1] = i end
	else
		local h = math.floor(m / 2)
		for i = 1, h do ins[#ins + 1] = i end
		for i = m, m - h + 1, -1 do outs[#outs + 1] = i end
	end
	return ins, outs
end

--- Lane connections at a junction whose segments may be one-way (a one-way roundabout ring), in the engine's own
--- one-way ring pattern (docs/findings/roads.md "Junction lane connections": node dumps of square_roundabouts'
--- rings, 2 and 4 ring lanes; Node dump 2026-10-11 of a 2-lane ring node). info[seg] = { lanes = count incl.
--- sidewalks, oneway = nil | "in" | "out" (relative to this node: "in" when the one-way segment's forward lanes
--- end here, i.e. the node is its node1) }. Lane sets per segment: M.laneSets (outer lane first).
---   two-way -> two-way    in[k] -> out[k] (exactly M.junctionConns)
---   ring in -> ring out   every ring lane continues in its own lane: in[k] -> out[k]
---   ring in -> arm        only the outermost ring lane exits, into every exit lane of the arm
---   arm -> ring out       the entry lanes fan out over the ring lanes: right (outer) entry lane -> the outer ring
---                         lanes, left -> the inner ones (every ring lane gets one entry lane, every entry lane
---                         at least one ring lane)
---   ring in -> ring in, ring out -> anything: nothing (wrong way)
--- Indices count the sidewalks (road lanes 1..m), so every index exists on its segment (mixed widths too).
function M.junctionConnsDir(segs, info)
	local sets = {}
	for _, s in ipairs(segs) do
		local i = info[s] or {}
		local ins, outs = M.laneSets(i.lanes, i.oneway)
		sets[s] = { ins = ins, outs = outs, oneway = i.oneway }
	end
	local out = {}
	for _, a in ipairs(segs) do
		for _, b in ipairs(segs) do
			if a ~= b then
				local ia, ob = sets[a].ins, sets[b].outs
				local owA, owB = sets[a].oneway, sets[b].oneway
				if #ia == 0 or #ob == 0 then
					-- (an arriving one-way edge has no out lanes, a leaving one no in lanes)
				elseif owA and not owB then
					-- ring -> arm: the outermost ring lane only, into every exit lane
					for _, o in ipairs(ob) do out[#out + 1] = { a, ia[1], b, o, true } end
				elseif owB and not owA then
					-- arm -> ring: fan, outer entry lanes to outer ring lanes
					local na, nb = #ia, #ob
					local seen = {}
					local function add(k, j)
						local key = k * 1000 + j
						if not seen[key] then
							seen[key] = true
							out[#out + 1] = { a, ia[k], b, ob[j], true }
						end
					end
					local pairsList = {}
					for j = 1, nb do pairsList[#pairsList + 1] = { math.min(na, math.ceil(j * na / nb)), j } end
					for k = 1, na do pairsList[#pairsList + 1] = { k, math.min(nb, math.ceil(k * nb / na)) } end
					table.sort(pairsList, function(p, q)
						if p[1] ~= q[1] then return p[1] < q[1] end
						return p[2] < q[2]
					end)
					for _, pq in ipairs(pairsList) do add(pq[1], pq[2]) end
				else
					for k = 1, math.min(#ia, #ob) do out[#out + 1] = { a, ia[k], b, ob[k], true } end
				end
			end
		end
	end
	return out
end

--- Builds the spec. info = {
---   nodes = { [existing node id] = { hasConfig = bool, edges = { existing street edge ids at the node },
---             lanes = lane count of its edge incl. sidewalks, src = its edge id, template = its template } },
---   sources = { [template path] = edge id },   town street edges to copy per template
---   fallback = edge id,                        any town street edge (template overridden)
---   allowNoConfig = bool,
---   lock = bool,                               every new edge roadDevelopmentLocked (dev lock probe)
---   lockKeys = { [plan edge key] = true },     these new edges locked (shaped towns' arm / rim streets)
---   unlockKeys = { [plan edge key] = true } }  these new edges never locked (§67 valve stubs; not forest lanes)
--- Returns spec or nil, reason.
--- Lane count (incl. sidewalks) of a base town template from its path: xsmall/small 4, medium 6, large 8
--- (base/content/infrastructure/street/town/*.street_template.lua laneConfigs), or nil.
M.SIZE_LANES = { xsmall = 4, small = 4, medium = 6, large = 8 }
function M.pathLanes(path)
	if type(path) ~= "string" then return nil end
	-- (tree-lined variants, ot_entry: `town_*_<size>_trees` has the plain template's lanes)
	local size = path:match("town_%a+_(%a+)%.street_template$") or path:match("town_%a+_(%a+)_trees%.street_template$")
	-- (forest lanes, ot_lane R2: `country_{old,new}_small` has 4 lane configs like the small town street: two edge lanes
	-- and two road lanes, docs/findings/towns.md)
	if size == nil and path:find("country_%a+_small%.street_template$") then return 4 end
	-- (one-way rings, ot_ring 2026-10-14: `town_new_one_way_small` has 4 lane configs, two sidewalks and two forward
	-- road lanes, base/content/infrastructure/street/town/town_new_one_way_small.street_template.lua)
	if size == nil and path:find("town_%a+_one_way_small%.street_template$") then return 4 end
	return size and M.SIZE_LANES[size] or nil
end

local function validLanes(n)
	n = tonumber(n)
	if n == nil or n < 4 or n % 2 ~= 0 then return nil end
	return n
end

--- Every lane connection of a spec names a lane its segment has: { ok, bad = { {node, seg, lane, lanes} } }.
--- lanesOf(seg) = the segment's lane count incl. sidewalks (existing edge ids and new entities). Indices are
--- 0-based (laneConfigs), road lanes only (never the sidewalks 0 and n-1). The engine asserts
--- lane_config_util.cpp:364 GetLaneOffset ("6 >= 4") on an index past the segment's lanes (showcase 2026-10-11).
function M.checkLanes(spec, lanesOf)
	local bad = {}
	for _, c in ipairs(spec.cfgAdd or {}) do
		for _, cn in ipairs(c.conns) do
			for k = 0, 1 do
				local seg, lane = cn[1 + 2 * k], cn[2 + 2 * k]
				local n = lanesOf(seg)
				if n == nil or lane < 1 or lane > n - 2 then bad[#bad + 1] = { node = c.node, seg = seg, lane = lane, lanes = n } end
			end
		end
	end
	return #bad == 0, bad
end

function M.build(inc, info)
	info = info or {}
	local nodesInfo = info.nodes or {}
	local spec = { nodes = {}, edges = {}, cfgRemove = {}, cfgAdd = {}, joins = {} }
	if inc == nil or #inc.edges == 0 then return nil, "empty" end

	-- joins: which new edges touch which existing node
	local touching, order = {}, {}
	for _, e in ipairs(inc.edges) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if n > 0 then
				if touching[n] == nil then touching[n] = {}; order[#order + 1] = n end
				local t = touching[n]
				t[#t + 1] = e.entity
			end
		end
	end
	for _, n in ipairs(order) do
		local ni = nodesInfo[n]
		if ni == nil then return nil, "unknownNode:" .. n end
		if not ni.hasConfig and not info.allowNoConfig then return nil, "noConfig:" .. n end
		local lanes = tonumber(ni.lanes) or 0
		if lanes < 4 or lanes % 2 ~= 0 then return nil, "lanes:" .. n .. ":" .. lanes end
		if ni.src == nil then return nil, "noSrc:" .. n end
	end

	local edgeLanesNew = {}
	for _, nd in ipairs(inc.nodes) do
		spec.nodes[#spec.nodes + 1] = { entity = nd.entity, pos = v3({ nd.x, nd.y, nd.z }) }
	end
	for _, e in ipairs(inc.edges) do
		local src, template, override
		local joinNode = (e.node0 > 0 and e.node0) or (e.node1 > 0 and e.node1) or nil
		if joinNode then
			local ni = nodesInfo[joinNode]
			src, template = ni.src, ni.template
			-- a wide through street starting at a narrower dead end (ot_core.hierarchy `wideJoin`): the joint edge
			-- takes its own template (the node config pairs each street's own lanes, as at any mixed junction)
			if e.wideJoin and e.template and e.template ~= ni.template and M.pathLanes(e.template) then
				template, override = e.template, e.template
			end
		else
			template = e.template
			src = template and info.sources and info.sources[template] or nil
			if src == nil then
				src = info.fallback
				override = template
			end
		end
		if src == nil then return nil, "noSource" end
		-- forest lanes (ot_lane, R2): an edge between two new nodes in the forest takes the era's country template, locked
		-- (no houses); never a joined edge (it copies its dead end's town street)
		local lane = (not joinNode and type(e.forestLane) == "string") and e.forestLane or nil
		if lane then template, override = lane, lane end
		-- tree-lined entries (ot_entry, later-ideas phase): an entry edge takes the `_trees` variant of its template with the
		-- template's default decorations (decor "template"); an edge continuing from a tree-lined dead end without the flag
		-- goes back to the plain template and no decorations (decor "none": its copy source carries the tree row)
		local decor = nil
		if lane then
			decor = "none"
		elseif e.trees and type(template) == "string" and not template:find("_trees", 1, true) then
			local head, size = template:match("^(.*town_%a+_)(%a+)%.street_template$")
			if head and (size == "small" or size == "medium" or size == "large") then
				template = head .. size .. "_trees.street_template"
				override, decor = template, "template"
			end
		elseif type(template) == "string" and template:find("_trees%.street_template$") then
			template = template:gsub("_trees%.street_template$", ".street_template")
			override, decor = template, "none"
		end
		if decor == nil and joinNode and not e.trees and type(nodesInfo[joinNode].template) == "string"
			and nodesInfo[joinNode].template:find("_trees%.street_template$") then
			decor = "none"
		end
		-- the new edge's own lane count: its copy source's, or the overriding template's (known from the
		-- resource, else from the path); never a guess from another street
		local lanes
		if joinNode and not override then lanes = nodesInfo[joinNode].lanes
		elseif override then lanes = (info.templateLanes and info.templateLanes[override]) or M.pathLanes(override)
		else lanes = (info.edgeLanes and info.edgeLanes[src]) or M.pathLanes(template) end
		edgeLanesNew[e.entity] = validLanes(lanes)
		spec.edges[#spec.edges + 1] = { entity = e.entity, node0 = e.node0, node1 = e.node1, p0 = v3(e.p0),
			p1 = v3(e.p1), t0 = v3(e.t0), t1 = v3(e.t1), class = e.class, template = template, src = src,
			override = override, key = e.key, decor = decor,
			-- (§67 valve stub, info.unlockKeys: that one street of a locked build stays unlocked; never a forest lane)
			locked = ((info.lock == true or lane ~= nil or (info.lockKeys ~= nil and e.key ~= nil and info.lockKeys[e.key] == true))
				and not (lane == nil and info.unlockKeys ~= nil and e.key ~= nil and info.unlockKeys[e.key] == true)) or nil,
			forestLane = lane ~= nil or nil,
			-- a river bridge edge (ot_bridge): the bridge type index (info.bridgeType), else nil
			bridge = (e.bridge and info.bridgeType) or nil }
		if e.bridge and info.bridgeType == nil then return nil, "noBridgeType" end
	end

	-- lane count per segment at every node: existing edges their own (info.nodes[n].edgeLanes, else the joined
	-- dead end's edge: a dead end has one), new edges theirs; unknown -> 4, the smallest town street (indices
	-- 1..2 exist on every street, so an unknown never asserts)
	local existingLanes = {}
	for _, n in ipairs(order) do
		local ni = nodesInfo[n]
		for _, id in ipairs(ni.edges or {}) do
			existingLanes[id] = validLanes(ni.edgeLanes and ni.edgeLanes[id]) or (id == ni.src and validLanes(ni.lanes))
				or existingLanes[id]
		end
		if ni.src then existingLanes[ni.src] = existingLanes[ni.src] or validLanes(ni.lanes) end
	end
	local function lanesOfSeg(seg)
		if seg < 0 then return edgeLanesNew[seg] or 4 end
		return existingLanes[seg] or 4
	end
	local lanesOf = setmetatable({}, { __index = function(_, seg) return lanesOfSeg(seg) end })

	for _, n in ipairs(order) do
		local ni = nodesInfo[n]
		local segs = {}
		local existing = {}
		for _, id in ipairs(ni.edges or {}) do existing[#existing + 1] = id end
		table.sort(existing)
		for _, id in ipairs(existing) do segs[#segs + 1] = id end
		for _, ent in ipairs(touching[n]) do segs[#segs + 1] = ent end
		spec.cfgAdd[#spec.cfgAdd + 1] = { node = n, conns = M.junctionConns(segs, lanesOf) }
		if ni.hasConfig then spec.cfgRemove[#spec.cfgRemove + 1] = n end
		spec.joins[#spec.joins + 1] = n
	end

	-- Every new node gets a config in the engine pattern too (a 1-edge node an empty one), as the probe's
	-- builds that worked (autoConfigs on). A Grow-now build without them crashed the simulation thread
	-- (Engine.h:323 GetComponentDataIndex, BaseNodeConfig on a new entity; 2026-10-11).
	local newTouch, newOrder = {}, {}
	for _, e in ipairs(inc.edges) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if n < 0 then
				if newTouch[n] == nil then newTouch[n] = {}; newOrder[#newOrder + 1] = n end
				local t = newTouch[n]
				t[#t + 1] = e.entity
			end
		end
	end
	-- (one-way ring edges, ot_ring 2026-10-14: a node with a one-way segment takes the engine's one-way ring pattern,
	-- junctionConnsDir: "in" where the one-way edge's forward lanes end at the node (its node1), "out" where they start)
	local oneway = {}
	for _, e in ipairs(inc.edges) do if e.oneway then oneway[e.entity] = e end end
	for _, n in ipairs(newOrder) do
		local segs = newTouch[n]
		local conns = {}
		if #segs >= 2 then
			local dirNode = false
			for _, s in ipairs(segs) do if oneway[s] then dirNode = true end end
			if dirNode then
				local info2 = {}
				for _, s in ipairs(segs) do
					local oe = oneway[s]
					info2[s] = { lanes = lanesOfSeg(s), oneway = oe and ((oe.node1 == n) and "in" or "out") or nil }
				end
				conns = M.junctionConnsDir(segs, info2)
			else
				conns = M.junctionConns(segs, lanesOf)
			end
		end
		spec.cfgAdd[#spec.cfgAdd + 1] = { node = n, conns = conns }
	end
	spec.lanes = {}
	for _, e in ipairs(spec.edges) do spec.lanes[e.entity] = lanesOfSeg(e.entity) end
	for id, v in pairs(existingLanes) do spec.lanes[id] = v end
	local okL, bad = M.checkLanes(spec, lanesOfSeg)
	if not okL then
		local b = bad[1]
		return nil, string.format("laneIndex:%s:%s:%s/%s", tostring(b.node), tostring(b.seg), tostring(b.lane), tostring(b.lanes))
	end
	return spec
end

--- The increment reduced to its edge number `i` (dev diagnosis: pre-check each edge alone): that edge as
--- entity -1, its new end nodes as -2 / -3, joins at its existing nodes (ot_plan's shapes).
function M.single(inc, i)
	local e = inc.edges[i]
	if e == nil then return nil end
	local out = { nodes = {}, edges = {}, joins = {}, dropped = {} }
	local map = {}
	local nextId = -2
	for _, n in ipairs({ e.node0, e.node1 }) do
		if n < 0 and map[n] == nil then
			for _, nd in ipairs(inc.nodes) do
				if nd.entity == n then
					map[n] = nextId
					out.nodes[#out.nodes + 1] = { entity = nextId, x = nd.x, y = nd.y, z = nd.z }
					nextId = nextId - 1
				end
			end
		end
	end
	local function ref(n) if n < 0 then return map[n] end return n end
	local copy = {}
	for k, v in pairs(e) do copy[k] = v end
	copy.entity, copy.node0, copy.node1 = -1, ref(e.node0), ref(e.node1)
	out.edges[1] = copy
	for _, n in ipairs({ e.node0, e.node1 }) do
		if n > 0 then out.joins[#out.joins + 1] = { node = n, edge = -1 } end
	end
	out.stats = { edges = 1, nodes = #out.nodes, length = e.length or 0 }
	return out
end

--- true when no number in the spec is -0.
function M.noNegativeZero(spec)
	local function bad(v) return v == 0 and 1 / v < 0 end
	for _, n in ipairs(spec.nodes) do
		for k = 1, 3 do if bad(n.pos[k]) then return false end end
	end
	for _, e in ipairs(spec.edges) do
		for _, v in ipairs({ e.p0, e.p1, e.t0, e.t1 }) do
			for k = 1, 3 do if bad(v[k]) then return false end end
		end
	end
	return true
end

--- A short text of a spec for the log line written before sending.
function M.summary(spec)
	local over = 0
	local trees = 0
	for _, e in ipairs(spec.edges) do
		if e.override then over = over + 1 end
		if e.decor == "template" then trees = trees + 1 end
	end
	return string.format("edges=%d nodes=%d joins=%s cfgRemove=%s cfgAdd=%d override=%d", #spec.edges, #spec.nodes,
		table.concat(spec.joins, ","), table.concat(spec.cfgRemove, ","), #spec.cfgAdd, over)
		.. (trees > 0 and string.format(" trees=%d", trees) or "")
end

return M
