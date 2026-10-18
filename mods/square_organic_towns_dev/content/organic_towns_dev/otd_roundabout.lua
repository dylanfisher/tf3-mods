-- DEV ONLY (never upload). Organic Towns: roundabout probe (NEXT_PHASE_BRIEF section 2). Pure: the
-- square_roundabouts geometry module is injected (loaded by the game script with ug_require when that mod is
-- installed; tests load it from mods/square_roundabouts), so tests run it offline.
--
-- What it plans: a small 4-arm roundabout of plain streets (no construction), built by one SimpleProposal:
--   * geometry from square_roundabouts_geometry.lua (`geom.build(geom.readParams{ sqrb_arms = 3 (= 4 arms),
--     sqrb_radius_size = preset })`): a ring of 4 Hermite edges (counter-clockwise = right-hand traffic, the
--     template `town_new_one_way_small`), 4 straight arms (`town_new_small`) of 30 m beyond the ring's kerb, in
--     local coordinates around (0, 0) with arms at 0 / 90 / 180 / 270 deg. We rotate and move it.
--   * placed at a town dead end: arm 0 ends exactly on the dead end's node (joined there with the D3 lane
--     config, as every increment), the ring centre straight ahead along the dead end's street. So the
--     roundabout sits in empty land at the frontier, where the street would continue; findings: rebuilding a
--     live junction would remove town edges (demolishes houses, crash traps around replaced nodes).
--   * ring mode "oneway" (default: the one-way town street ring, counterclockwise for right-hand traffic) or
--     "town" (the ring in the dead end's own two-way town street; the runner's fallback when every one-way size is
--     refused, logged RB FALLBACK).
-- Every new ring/arm node gets a node config (the config-less version crashed the simulation on the third
-- build, Engine.h:323 BaseNodeConfig, 2026-10-11). The one-way ring's nodes take the engine's own one-way ring
-- lane pattern (ot_proposal.junctionConnsDir, docs/findings/roads.md "Junction lane connections"; Showcase v7
-- 2026-10-12: the experimental gate is gone). Every number goes through z0 (findings "Negative zero": the
-- geometry module itself leaves -0 in tangents).

local RB = {}

RB.MOD_ID = "square_roundabouts"
RB.PRESENCE = "square_roundabouts::/square_roundabouts_presence.lua"
RB.GEOM = "square_roundabouts::/infrastructure/street_construction/square_roundabouts_geometry.lua"
RB.SIZES = { 1, 2, 3 }          -- radius presets tried in order: XS 10 m, S 15 m, M 20 m (inner radius)
RB.SIZE_NAMES = { "XS", "S", "M" }
RB.ONEWAY = "::/infrastructure/street/town/town_new_one_way_small.street_template"

local function z0(v)
	if v == 0 then return 0 end
	return v
end

-- pre-5.3 runtime: math.atan2 (5.1/5.2); math.atan(y, x) only as the fallback for the 5.4 test harness
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

local function rot(x, y, c, s)
	return x * c - y * s, x * s + y * c
end

--- Loads the geometry module (req = ug_require): geom or nil, reason. Both the presence file and the module
--- must load (the mod is installed and enabled).
function RB.load(req)
	local okP = pcall(req, RB.PRESENCE)
	if not okP then return nil, "noMod" end
	local okG, geom = pcall(req, RB.GEOM)
	if not okG or type(geom) ~= "table" or type(geom.build) ~= "function" then return nil, "noGeometry:" .. tostring(geom) end
	return geom
end

--- The roundabout in local coordinates for radius preset `size` (1-based index into the mod's presets):
--- { ring = { {p0, t0, p1, t1, tag0, tag1} }, arms = { same, arm k = index }, radius, R (ring centreline),
--- reach (centre to arm end), ringTemplate, armTemplate } or nil, err.
function RB.localPlan(geom, size)
	local ok, b = pcall(function() return geom.build(geom.readParams({ sqrb_arms = 3, sqrb_radius_size = size })) end)
	if not ok or b == nil then return nil, "build:" .. tostring(b) end
	local ring, arms
	for _, l in ipairs(b.lists or {}) do
		if l.role == "ring" then ring = l elseif l.role == "arms" then arms = l end
	end
	if ring == nil or arms == nil or #arms.edges ~= 4 or #ring.edges < 4 then return nil, "shape" end
	local reach = 0
	for _, e in ipairs(arms.edges) do
		reach = math.max(reach, math.sqrt(e.p1[1] ^ 2 + e.p1[2] ^ 2))
	end
	return { ring = ring.edges, arms = arms.edges, radius = b.radius, R = b.a, reach = reach,
		ringTemplate = ring.template, armTemplate = arms.template }
end

--- World plan: the local plan rotated so arm 0 points from the centre back to the dead end (dx, dy unit, the
--- dead end's outward street direction) and moved so arm 0's end is the dead end at (x, y, z).
--- Returns { centre = {x, y}, nodes = { [tag] = {x, y, z} }, edges = { {tag0, tag1, p0, t0, p1, t1, role} },
--- joinTag } (the arm-0 outer end is tag "join").
function RB.place(lp, x, y, z, dx, dy)
	local cx, cy = x + dx * lp.reach, y + dy * lp.reach
	-- local +x (arm 0) must map to (-dx, -dy)
	local a = atan2(-dy, -dx)
	local c, s = math.cos(a), math.sin(a)
	local out = { centre = { z0(cx), z0(cy) }, nodes = {}, edges = {}, joinTag = "join" }
	local function P(p)
		local rx, ry = rot(p[1], p[2], c, s)
		return { z0(cx + rx), z0(cy + ry), z0(z) }
	end
	local function Tn(t)
		local rx, ry = rot(t[1], t[2], c, s)
		return { z0(rx), z0(ry), 0 }
	end
	for _, e in ipairs(lp.ring) do
		out.nodes[e.tag0] = out.nodes[e.tag0] or P(e.p0)
		out.nodes[e.tag1] = out.nodes[e.tag1] or P(e.p1)
		out.edges[#out.edges + 1] = { tag0 = e.tag0, tag1 = e.tag1, p0 = P(e.p0), t0 = Tn(e.t0), p1 = P(e.p1), t1 = Tn(e.t1),
			role = "ring" }
	end
	for k, e in ipairs(lp.arms) do
		local outer = k == 1 and "join" or ("arm_end_" .. k)
		local p1 = P(e.p1)
		if k == 1 then p1 = { z0(x), z0(y), z0(z) } end   -- exactly on the dead end
		out.nodes[outer] = p1
		out.edges[#out.edges + 1] = { tag0 = e.tag0, tag1 = outer, p0 = P(e.p0), t0 = Tn(e.t0), p1 = p1, t1 = Tn(e.t1),
			role = k == 1 and "join" or "arm" }
	end
	return out
end

--- Proposal spec for ot_engine.proposal from a world plan. info = { deadEnd = node id, deadEdge = its edge id,
--- lanes = its lane count, hasConfig = bool, src = edge to copy (the dead end's), template = its template,
--- ringMode = "oneway" (default) | "town", ringLanes = lane count of the one-way ring template (default 4), junctionConns /
--- junctionConnsDir = ot_proposal's }.
--- Every new node gets a config (docs/findings.md: a script node without BASE_NODE_CONFIG crashed the
--- simulation on the 3rd "Roundabout here", 2026-10-11): ring nodes the engine pattern over ring in, ring out
--- and the arm (two-way ring: junctionConns with each segment's lanes; one-way ring: junctionConnsDir with the
--- ring edges "in"/"out" at the node), the free arm ends an empty one.
--- Returns spec (with spec.roles[entity] = "ring" | "arm" | "join", spec.newConfigs = count of new nodes with a
--- config) or nil, err.
function RB.spec(wp, info)
	if not info.deadEnd or not info.src then return nil, "noDeadEnd" end
	local oneway = info.ringMode ~= "town"
	if oneway and type(info.junctionConnsDir) ~= "function" then return nil, "noJunctionConnsDir" end
	local spec = { nodes = {}, edges = {}, cfgRemove = {}, cfgAdd = {}, joins = { info.deadEnd }, roles = {} }
	local nE = #wp.edges
	local nodeEnt, nextNode = {}, -(nE + 1)
	local tags = {}
	for tag in pairs(wp.nodes) do if tag ~= wp.joinTag then tags[#tags + 1] = tag end end
	table.sort(tags)
	for _, tag in ipairs(tags) do
		nodeEnt[tag] = nextNode
		spec.nodes[#spec.nodes + 1] = { entity = nextNode, pos = wp.nodes[tag] }
		nextNode = nextNode - 1
	end
	nodeEnt[wp.joinTag] = info.deadEnd
	local joinEdge
	local segLanes, segRing = {}, {}
	for i, e in ipairs(wp.edges) do
		local ent = -i
		local override = nil
		if e.role == "ring" and oneway then override = RB.ONEWAY end
		spec.edges[#spec.edges + 1] = { entity = ent, node0 = nodeEnt[e.tag0], node1 = nodeEnt[e.tag1], p0 = e.p0, p1 = e.p1,
			t0 = e.t0, t1 = e.t1, class = e.role == "ring" and "ring" or "small", template = override or info.template,
			src = info.src, override = override, key = "rb:" .. e.role .. ":" .. i }
		spec.roles[ent] = e.role
		if e.role == "join" then joinEdge = ent end
		segLanes[ent] = override and (info.ringLanes or 4) or info.lanes
		segRing[ent] = e.role == "ring"
	end
	-- D3 joint at the dead end: the dead end's edge and the join arm (a copy of it: same lanes)
	local lanes = { [info.deadEdge] = info.lanes, [joinEdge] = info.lanes }
	spec.cfgAdd[1] = { node = info.deadEnd, conns = info.junctionConns({ info.deadEdge, joinEdge }, lanes) }
	if info.hasConfig then spec.cfgRemove[1] = info.deadEnd end
	-- every new node: its segments in edge order
	local touch = {}
	for _, e in ipairs(spec.edges) do
		for _, n in ipairs({ e.node0, e.node1 }) do
			if n < 0 then
				touch[n] = touch[n] or {}
				local t = touch[n]
				t[#t + 1] = e.entity
			end
		end
	end
	spec.newConfigs = 0
	for _, nd in ipairs(spec.nodes) do
		local n = nd.entity
		local segs = touch[n] or {}
		local conns = {}
		if #segs >= 2 then
			if oneway then
				local dir = {}
				for _, s in ipairs(segs) do
					local e = spec.edges[-s]
					local ow = nil
					if segRing[s] then ow = (e.node1 == n) and "in" or "out" end
					dir[s] = { lanes = segLanes[s], oneway = ow }
				end
				conns = info.junctionConnsDir(segs, dir)
			else
				conns = info.junctionConns(segs, segLanes)
			end
		end
		spec.cfgAdd[#spec.cfgAdd + 1] = { node = n, conns = conns }
		spec.newConfigs = spec.newConfigs + 1
	end
	spec.lanes = segLanes
	return spec
end

--- Picks the dead end for a roundabout: from `cands` = { {node, x, y, z, dx, dy, d = distance from the town
--- centre, cls = "main"|"medium"|"small", near = distance to the camera point or nil} }. mode "camera": the one
--- nearest the camera point; "frontier": the farthest from the centre, main / medium streets first (where an
--- arterial continues). Returns the candidate or nil.
function RB.pick(cands, mode)
	local best, bv = nil, nil
	for _, c in ipairs(cands) do
		local v
		if mode == "camera" then v = -(c.near or math.huge)
		else v = (c.d or 0) + ((c.cls == "main" or c.cls == "medium") and 10000 or 0) end
		if bv == nil or v > bv or (v == bv and c.node < best.node) then best, bv = c, v end
	end
	return best
end

return RB
