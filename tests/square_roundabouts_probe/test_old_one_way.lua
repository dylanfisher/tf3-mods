-- DEV construction "DEV Probe: pre-1940 one-way" (TESTING.md 11.2): params, geometry, result.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_probe/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local rb = H.loadRoundabouts()
H.rbRequire("square_roundabouts::/infrastructure/street_construction/square_roundabouts_result.lua")
local shape = ug_require "/infrastructure/street_construction/sqrb_probe_old_one_way.lua"
local geomInfo = ug_require "/probe/probe_geom.lua"
local CACHE = here .. "../../.cache/game/base/content"

local function exists(path)
	local f = io.open(path, "r")
	if f then f:close() return true end
	return false
end

test("con.lua: every year, DEV ONLY name, params match readParams defaults", function()
	ug_require "/infrastructure/street_construction/sqrb_probe_old_one_way.con.lua"
	local d = data()
	eq(d.availability, { yearFrom = 0, yearTo = 0 })
	ok(d.description.name:find("NOT FOR UPLOAD", 1, true))
	local p = {}
	for _, x in ipairs(d.params) do
		ok(x.key:sub(1, 11) == "sqrb_probe_", x.key)
		p[x.key] = x.defaultIndex
	end
	eq(shape.readParams(p), shape.readParams({}))
	eq(d.updateScript.fileName, "sqrb_probe_old_one_way.script@updateFn")
end)

test("every layout x template: sane, all nodes freed, templates exist in the base game", function()
	ug_require "/infrastructure/street_construction/sqrb_probe_old_one_way.script.lua"
	local update = data().updateFn
	for layout = 1, 3 do
		for template = 1, 2 do
			local p = { [shape.KEYS.layout] = layout, [shape.KEYS.template] = template }
			local built = shape.build(shape.readParams(p))
			eq(geomInfo.insane(built.lists), nil)
			local res = update({}, p)
			eq(#res.edgeLists, layout == 3 and 2 or 1)
			for _, el in ipairs(res.edgeLists) do
				eq(el.snapNodes, {})
				eq(#el.freeNodes, #el.edges)
				local rel = el.params.type:gsub("^::", "")
				if exists(CACHE .. "/infrastructure/street/town/town_old_small.street_template.lua") then
					ok(exists(CACHE .. rel .. ".lua"), rel)
				end
			end
			eq(res.edgeLists[1].params.type, shape.TEMPLATES[template])
		end
	end
	-- the ring runs anticlockwise and its arms start on the ring's tagged nodes
	local b = shape.build(shape.readParams({}))
	local e = b.lists[1].edges[1]
	ok(e.p0[1] > 0 and e.p1[2] > 0, "first quarter: east -> north")
	for i, a in ipairs(b.lists[2].edges) do eq(a.tag0, b.lists[1].edges[i].tag0) end
	ok(rb.geom ~= nil)
end)
