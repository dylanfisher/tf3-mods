-- Footprints from the real square_roundabouts geometry and from an updateFn result.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_showcase/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local combos = ug_require "/showcase/sc_combos.lua"
local footprint = ug_require "/showcase/sc_footprint.lua"

local ENTRIES = H.entries()
local function byId(id) for _, e in ipairs(ENTRIES) do if e.id == id then return e end end end

test("module file from the updateScript name", function()
	eq(footprint.moduleFile("square_roundabouts.script@updateFn"), "square_roundabouts_geometry.lua")
	eq(footprint.moduleFile("square_roundabouts_magic.script@updateFn"), "square_roundabouts_magic.lua")
	eq(footprint.moduleFile("square_roundabouts::/infrastructure/street_construction/square_roundabouts_highway.script@updateFn"), "square_roundabouts_highway.lua")
	eq(footprint.moduleFile("other.script@updateFn"), nil)
	eq(footprint.moduleFile(nil), nil)
end)

test("a straight edge and the margin", function()
	-- a 20 m wide street: 10 m half width + KERB on every side
	local fp = footprint.fromLists({ { template = "t20", edges = { { p0 = { -50, 0, 0 }, p1 = { 50, 0, 0 }, t0 = { 100, 0, 0 }, t1 = { 100, 0, 0 } } } } },
		{ widthOf = function(t) return t == "t20" and 20 or nil end })
	local g = 10 + footprint.KERB
	near(fp.w, 100 + 2 * g, 1e-9)
	near(fp.h, 2 * g, 1e-9)
	near(fp.cx, 0, 1e-9)
	-- an unknown template: DEFAULT_WIDTH; a raised street: its earth slope; a bridge: none
	local u = footprint.fromLists({ { template = "?", edges = { { p0 = { 0, 0, 0 }, p1 = { 10, 0, 0 }, t0 = { 10, 0, 0 }, t1 = { 10, 0, 0 } } } } }, {})
	near(u.h, footprint.DEFAULT_WIDTH + 2 * footprint.KERB, 1e-9)
	local raised = { p0 = { 0, 0, 8 }, p1 = { 10, 0, 8 }, t0 = { 10, 0, 0 }, t1 = { 10, 0, 0 } }
	local e = footprint.fromLists({ { template = "t20", edges = { raised } } }, { widthOf = function() return 20 end })
	near(e.h, 2 * (g + footprint.SLOPE * 8), 1e-9)
	local b = footprint.fromLists({ { template = "t20", bridge = true, edges = { raised } } }, { widthOf = function() return 20 end })
	near(b.h, 2 * g, 1e-9)
	-- the floor
	local tiny = footprint.fromLists({ { template = "t2", edges = { { p0 = { 0, 0, 0 }, p1 = { 10, 0, 0 }, t0 = { 10, 0, 0 }, t1 = { 10, 0, 0 } } } } }, { widthOf = function() return 2 end })
	near(tiny.h, 2 * footprint.MIN_GROW, 1e-9)
	local bad, err = footprint.fromLists({ { edges = { { p0 = { 0 / 0, 0, 0 }, p1 = { 1, 0, 0 }, t0 = { 1, 0, 0 }, t1 = { 1, 0, 0 } } } } }, 0)
	eq(bad, nil)
	ok(err:find("finite"))
	eq((footprint.fromLists({}, 0)), nil)
end)

test("every entry's default combo has a finite footprint from its geometry", function()
	for _, e in ipairs(ENTRIES) do
		local fp, err = footprint.measure(combos.make(e, combos.defaults(e)), H.rbRequire, H.FP_OPTS, 400)
		eq(err, nil, e.id)
		eq(fp.source, "geometry", e.id)
		ok(fp.w > 40 and fp.h > 40 and fp.w < 1100 and fp.h < 1100, e.id .. string.format(" %.0fx%.0f", fp.w, fp.h))
	end
end)

test("sizes vary: Parclo Scale L is much bigger than Magic XS", function()
	local magic, parclo = byId("magic"), byId("parclo")
	local m = combos.make(magic, combos.defaults(magic)) -- XS is the default
	local pv = combos.defaults(parclo)
	for i, p in ipairs(parclo.params) do if p.key:find("scale", 1, true) then pv[i] = p.n end end
	local fm = footprint.measure(m, H.rbRequire, H.FP_OPTS, 400)
	local fpL = footprint.measure(combos.make(parclo, pv), H.rbRequire, H.FP_OPTS, 400)
	ok(fpL.w * fpL.h > 10 * fm.w * fm.h, string.format("%.0fx%.0f vs %.0fx%.0f", fpL.w, fpL.h, fm.w, fm.h))
end)

test("the updateFn result gives the same footprint as the geometry (the game's path)", function()
	local result = H.rbRequire("square_roundabouts::/infrastructure/street_construction/square_roundabouts_result.lua")
	for _, e in ipairs(ENTRIES) do
		local c = combos.make(e, combos.defaults(e))
		local built = footprint.build(e, c.params, H.rbRequire)
		local a = footprint.fromLists(footprint.listsOfBuilt(built), H.FP_OPTS)
		local b = footprint.fromResult(result.build(built), H.FP_OPTS)
		eq(b.source, "updateFn")
		for _, k in ipairs({ "minX", "maxX", "minY", "maxY" }) do near(a[k], b[k], 1e-6, e.id .. " " .. k) end
	end
end)

test("street widths are read from the game's templates (when extracted)", function()
	local w = H.widthOf("::/infrastructure/street/town/town_new_small.street_template")
	if w == nil then print("skipped: .cache/game missing (make docs)") return end
	eq(w, 16)
	eq(H.widthOf("::/infrastructure/street/country/country_new_large.street_template"), 30)
	-- the margin follows the roads: a Magic XS with town small arms is smaller than with country large
	local magic = byId("magic")
	local v = combos.defaults(magic)
	local small = footprint.measure(combos.make(magic, v), H.rbRequire, H.FP_OPTS, 400)
	for i, p in ipairs(magic.params) do if p.key:find("arm_type", 1, true) then v[i] = 6 end end
	local large = footprint.measure(combos.make(magic, v), H.rbRequire, H.FP_OPTS, 400)
	ok(large.w > small.w, string.format("%.0f > %.0f", large.w, small.w))
end)

test("unknown script: the fallback box and an error", function()
	local e = { id = "x", script = "foo.script@updateFn", params = {} }
	local fp, err = footprint.measure(combos.make(e, {}), H.rbRequire, H.FP_OPTS, 300)
	eq(fp.source, "fallback")
	near(fp.w, 300, 1e-9)
	ok(err)
end)
