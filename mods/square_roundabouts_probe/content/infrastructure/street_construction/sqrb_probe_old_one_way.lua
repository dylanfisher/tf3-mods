-- DEV ONLY (never upload): geometry of "DEV Probe: pre-1940 one-way" (sqrb_probe_old_one_way.con.lua).
-- Pure (no api.*), unit-tested in tests/square_roundabouts_probe/test_old_one_way.lua. Output in
-- the square_roundabouts geometry format ({lists = {{role, template, halfWidth, edges}}}), so
-- square_roundabouts_result.lua maps it (every node freed, no snap nodes).

local shape = {}

shape.KEYS = { layout = "sqrb_probe_ow_layout", template = "sqrb_probe_ow_template" }
shape.LAYOUT_STRAIGHT, shape.LAYOUT_RING, shape.LAYOUT_RING_ARMS = 1, 2, 3
shape.TEMPLATES = {
	"::/infrastructure/street/constructions/entrance_old_one_way.street_template",
	"::/infrastructure/street/constructions/entrance_new_one_way.street_template",
}
shape.HALF_WIDTH = 5.5 -- sidewalk 3 m + one 5 m lane + sidewalk 3 m
shape.ARM = { template = "::/infrastructure/street/town/town_old_small.street_template", halfWidth = 8 }
shape.RADIUS = 20       -- ring centreline (m)
shape.LENGTH = 40       -- straight: each of the two edges (m)
shape.ARM_LENGTH = 30   -- beyond the ring's outer kerb (m)

local function index(v, n, default)
	v = tonumber(v)
	if v and v == math.floor(v) and v >= 1 and v <= n then return v end
	return default
end

function shape.readParams(params)
	params = params or {}
	return {
		layout = index(params[shape.KEYS.layout], 3, shape.LAYOUT_RING_ARMS),
		template = index(params[shape.KEYS.template], 2, 1),
	}
end

--- {lists} for a spec from readParams.
function shape.build(spec)
	local template = shape.TEMPLATES[spec.template]
	local lists = {}
	if spec.layout == shape.LAYOUT_STRAIGHT then
		local L = shape.LENGTH
		lists[1] = { role = "oneway", template = template, halfWidth = shape.HALF_WIDTH, edges = {
			{ p0 = { -L, 0, 0 }, t0 = { L, 0, 0 }, p1 = { 0, 0, 0 }, t1 = { L, 0, 0 }, tag1 = "sqrb_ow_mid" },
			{ p0 = { 0, 0, 0 }, t0 = { L, 0, 0 }, p1 = { L, 0, 0 }, t1 = { L, 0, 0 }, tag0 = "sqrb_ow_mid" },
		} }
		return { lists = lists }
	end
	-- anticlockwise ring of four quarter arcs (right-hand traffic), Hermite handle 4 tan(theta/4) r
	local r = shape.RADIUS
	local k = 4 * math.tan(math.pi / 8) * r
	local nodes = {}
	for i = 1, 4 do
		local a = (i - 1) * math.pi / 2
		local c, s = math.cos(a), math.sin(a)
		nodes[i] = { pos = { r * c, r * s, 0 }, t = { -k * s, k * c, 0 }, u = { c, s, 0 }, tag = "sqrb_ow_r" .. i }
	end
	local ring = {}
	for i = 1, 4 do
		local a, b = nodes[i], nodes[i % 4 + 1]
		ring[i] = { p0 = a.pos, t0 = a.t, p1 = b.pos, t1 = b.t, tag0 = a.tag, tag1 = b.tag }
	end
	lists[1] = { role = "ring", template = template, halfWidth = shape.HALF_WIDTH, edges = ring }
	if spec.layout == shape.LAYOUT_RING_ARMS then
		local arms = {}
		local len = shape.HALF_WIDTH + shape.ARM_LENGTH
		for i, n in ipairs(nodes) do
			local p1 = { n.pos[1] + n.u[1] * len, n.pos[2] + n.u[2] * len, 0 }
			local t = { n.u[1] * len, n.u[2] * len, 0 }
			arms[i] = { p0 = n.pos, t0 = t, p1 = p1, t1 = t, tag0 = n.tag }
		end
		lists[2] = { role = "arms", template = shape.ARM.template, halfWidth = shape.ARM.halfWidth, edges = arms }
	end
	return { lists = lists }
end

return shape
