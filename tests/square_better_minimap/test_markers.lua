-- minimap_geom industry marker helpers (phase 3): icon choice and pixel layout (pure, no api.*).

local geom = ug_require "square_better_minimap::/minimap/minimap_geom.tl"

local FALLBACK = "::/gui/entity_window/icons/building_industry.tga"
local BOX = geom.boxFromBounds(-1000, -500, 1000, 500) -- 2000 x 1000 m

test("pickIcon prefers the first product icon", function()
	local p, src = geom.pickIcon({ "", "fuel.tga", "plastic.tga" }, { "crude.tga" }, FALLBACK)
	eq(p, "fuel.tga"); eq(src, "output")
end)

test("pickIcon falls back to an input, then the generic icon", function()
	local p, src = geom.pickIcon({}, { "", "grain.tga" }, FALLBACK)
	eq(p, "grain.tga"); eq(src, "input")
	p, src = geom.pickIcon({ "" }, {}, FALLBACK)
	eq(p, FALLBACK); eq(src, "fallback")
	p, src = geom.pickIcon(nil, nil, FALLBACK)
	eq(p, FALLBACK); eq(src, "fallback")
end)

test("markerLayout centres markers on their position (default orientation, +y up)", function()
	local items = {
		{ entity = 7, x = 0, y = 0, icon = "a.tga", name = "Centre" },
		{ entity = 8, x = -500, y = 250, icon = "b.tga", name = "North-west" },
	}
	local out = geom.markerLayout(items, BOX, geom.DEFAULT_ORIENT, 400, 200, 16)
	eq(#out, 2)
	-- sorted top to bottom: north-west (y = +250 -> fy 0.25) first
	eq(out[1].entity, 8); eq(out[1].left, 100 - 8); eq(out[1].top, 50 - 8)
	eq(out[2].entity, 7); eq(out[2].left, 200 - 8); eq(out[2].top, 100 - 8)
	eq(out[2].icon, "a.tga"); eq(out[2].name, "Centre")
	eq(out[2].key, "ind_7_192_92")
end)

test("markerLayout keeps edge markers inside the picture and drops outside ones", function()
	local items = {
		{ entity = 1, x = -1000, y = 500, icon = "x" },   -- top-left corner
		{ entity = 2, x = 1000, y = -500, icon = "x" },   -- bottom-right corner
		{ entity = 3, x = 1500, y = 0, icon = "x" },      -- outside the terrain box
		{ entity = 4, icon = "x" },                       -- no position
	}
	local out = geom.markerLayout(items, BOX, geom.DEFAULT_ORIENT, 400, 200, 16)
	eq(#out, 2)
	eq(out[1].entity, 1); eq(out[1].left, 0); eq(out[1].top, 0)
	eq(out[2].entity, 2); eq(out[2].left, 400 - 16); eq(out[2].top, 200 - 16)
end)

test("markerLayout order is stable and keys change with the position", function()
	local items = {
		{ entity = 5, x = 0, y = 0, icon = "x" },
		{ entity = 3, x = 0, y = 0, icon = "x" },
	}
	local a = geom.markerLayout(items, BOX, geom.DEFAULT_ORIENT, 400, 200, 16)
	eq(a[1].entity, 3); eq(a[2].entity, 5)
	local b = geom.markerLayout(items, BOX, geom.DEFAULT_ORIENT, 600, 300, 18)
	ok(a[1].key ~= b[1].key, "key follows the pixel position")
end)

test("markerLayout with an empty or degenerate picture", function()
	eq(#geom.markerLayout(nil, BOX, nil, 400, 200, 16), 0)
	eq(#geom.markerLayout({ { entity = 1, x = 0, y = 0, icon = "x" } }, BOX, nil, 0, 200, 16), 0)
	-- marker larger than the picture: pinned to 0
	local out = geom.markerLayout({ { entity = 1, x = 0, y = 0, icon = "x" } }, BOX, nil, 10, 10, 16)
	eq(out[1].left, 0); eq(out[1].top, 0)
end)
