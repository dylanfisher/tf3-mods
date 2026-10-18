-- DEV ONLY (never upload). Organic Towns dev tools: "Node dump" (ported from the probe's NodeDump,
-- mods/square_organic_towns_probe/.../otp_probes_read.lua). Pure: the dev engine (otd_engine.nodeRead) reads a
-- node's edges and BASE_NODE_CONFIG into plain tables; this module annotates every lane connection with what the
-- lane indices mean, so a game- or construction-made junction (e.g. a Roundabouts & Interchanges one-way ring
-- node) shows the engine's pattern next to ours (ot_proposal.junctionConnsDir, derived, unverified).
--
-- LaneConnection lane indices are node-relative: "zero-based, from left to right when looking from the Node to
-- the segment" (api type.d.tl). Looking from the node along an edge that starts there (node0) is the edge's own
-- direction, so node-relative index = edge lane index; for an edge that ends there (node1) the view is reversed:
-- edge lane = n - 1 - index. A lane comes IN to the node when it runs toward it: forward lanes (node0 -> node1)
-- at node1, backward lanes at node0.
--
-- node = { id, x, y, z, dist, edges = { [seg] = { id, n0, n1, template, lanes, forward = {bool per lane,
-- 0-based as the engine's list, stored 1-based} } }, segs = {seg ids in order}, config = bool,
-- conns = { {s0, l0, s1, l1, road, tram} }, crosswalks, userModified, lights }

local ND = {}

ND.RADIUS = 60       -- m: nodes within this distance of the camera point
ND.MAX_NODES = 3

local function short(tpl)
	return tostring(tpl or "?"):match("([^/]+)%.street_template$") or tostring(tpl or "?")
end
ND.short = short

--- Which end of edge e the node is: "node0" | "node1" | "?".
function ND.endOf(e, node)
	if e == nil then return "?" end
	if e.n0 == node then return "node0" end
	if e.n1 == node then return "node1" end
	return "?"
end

--- What node-relative lane `lane` of edge e is at `node`: edge lane index, forward flag, "in" / "out" / "?".
function ND.laneRole(e, node, lane)
	if e == nil or e.lanes == nil then return nil, nil, "?" end
	local at = ND.endOf(e, node)
	local edgeLane = lane
	if at == "node1" then edgeLane = e.lanes - 1 - lane end
	local fwd = e.forward and e.forward[edgeLane + 1]
	if fwd == nil or at == "?" then return edgeLane, fwd, "?" end
	local incoming = (fwd and at == "node1") or (not fwd and at == "node0")
	return edgeLane, fwd, incoming and "in" or "out"
end

--- Lane flags as "BBFF" (one letter per lane, edge order).
function ND.flags(e)
	if e == nil or e.forward == nil then return "?" end
	local s = {}
	for i = 1, e.lanes or #e.forward do s[i] = e.forward[i] == nil and "?" or (e.forward[i] and "F" or "B") end
	return table.concat(s)
end

--- Log field lists for one node: NODEDUMP fields, then one NODECONN field list per connection.
function ND.fields(node)
	local edges = {}
	for _, seg in ipairs(node.segs or {}) do
		local e = node.edges[seg]
		edges[#edges + 1] = string.format("%d:%s:L%s:%s:%s", seg, ND.endOf(e, node.id) == "node1" and "in" or "out",
			tostring(e and e.lanes or "?"), short(e and e.template), ND.flags(e))
	end
	local head = { { "node", node.id }, { "pos", string.format("%.0f,%.0f,%.0f", node.x or 0, node.y or 0, node.z or 0) },
		{ "dist", string.format("%.0f", node.dist or 0) }, { "deg", #(node.segs or {}) }, { "edges", table.concat(edges, ",") },
		{ "config", node.config == true }, { "conns", #(node.conns or {}) }, { "crosswalks", node.crosswalks or "-" },
		{ "userModified", tostring(node.userModified) }, { "lights", tostring(node.lights) } }
	local conns = {}
	for i, c in ipairs(node.conns or {}) do
		local e0, e1 = node.edges[c[1]], node.edges[c[3]]
		local el0, f0, r0 = ND.laneRole(e0, node.id, c[2])
		local el1, f1, r1 = ND.laneRole(e1, node.id, c[4])
		conns[#conns + 1] = { { "node", node.id }, { "i", i }, { "conn", string.format("%d.%d>%d.%d", c[1], c[2], c[3], c[4]) },
			{ "from", string.format("%s:%s:edgeLane%s:%s:%s", ND.endOf(e0, node.id), short(e0 and e0.template), tostring(el0),
				f0 == nil and "?" or (f0 and "F" or "B"), r0) },
			{ "to", string.format("%s:%s:edgeLane%s:%s:%s", ND.endOf(e1, node.id), short(e1 and e1.template), tostring(el1),
				f1 == nil and "?" or (f1 and "F" or "B"), r1) },
			{ "road", c[5] == true }, { "tram", c[6] == true }, { "ok", r0 == "in" and r1 == "out" } }
	end
	return head, conns
end

--- Our pattern for the same node (ot_proposal.junctionConnsDir with the node's segments: one-way edges get
--- "in"/"out" from their end, two-way ones nil) as "s.l>s.l" text, to compare with the engine's in the log.
--- oneWay(e) -> true when the edge's road lanes all run one way.
function ND.ours(node, connsDir)
	local info = {}
	for _, seg in ipairs(node.segs or {}) do
		local e = node.edges[seg]
		local ow = nil
		if e and ND.oneWay(e) then
			-- forward one-way: arriving at node1
			local at = ND.endOf(e, node.id)
			if at == "node1" then ow = "in" elseif at == "node0" then ow = "out" end
		end
		info[seg] = { lanes = e and e.lanes or 4, oneway = ow }
	end
	local out = {}
	for _, c in ipairs(connsDir(node.segs or {}, info)) do out[#out + 1] = string.format("%d.%d>%d.%d", c[1], c[2], c[3], c[4]) end
	return out
end

--- true when every road lane (not the outer two: sidewalks) is forward.
function ND.oneWay(e)
	if e == nil or e.forward == nil or (e.lanes or 0) < 3 then return false end
	for i = 2, e.lanes - 1 do
		if e.forward[i] ~= true then return false end
	end
	return true
end

return ND
