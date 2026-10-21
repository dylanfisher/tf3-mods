-- nfp_logic: the cargo-line decision on plain data.

local logic = ug_require "square_no_factory_passengers::/no_factory_passengers/nfp_logic.lua"

local isSource = function(e) return e == 99 end
local isCargoStation = function(st) return st < 50 end

-- catchables(station, cargo) over a { [station] = { cargo = {...} } } table, recording every fetch
-- as "station:cargo|pax"
local function fake(world)
	local fetched = {}
	return function(station, cargo)
		fetched[#fetched + 1] = tostring(station) .. ":" .. (cargo and "cargo" or "pax")
		local s = world[station] or {}
		return cargo and s.cargo or s.pax
	end, fetched
end

test("anyCatchable: any station's catchables matching", function()
	local c = fake({ [1] = { cargo = { 1, 2 } }, [2] = { cargo = { 3, 99 } } })
	ok(logic.anyCatchable({ 1, 2 }, c, true, isSource))
	ok(not logic.anyCatchable({ 1 }, c, true, isSource))
	ok(not logic.anyCatchable({}, c, true, isSource))
	ok(not logic.anyCatchable({ 3 }, c, true, isSource), "nil catchables")
end)

test("anyCatchable: stops at the first match, without fetching further stations", function()
	local c, fetched = fake({ [1] = { cargo = { 99, 98 } }, [2] = { cargo = { 99 } } })
	ok(logic.anyCatchable({ 1, 2 }, c, true, isSource))
	eq(fetched, { "1:cargo" })
end)

test("isCargoStop: only cargo stations are fetched", function()
	local c, fetched = fake({ [60] = { cargo = { 99 } }, [1] = { cargo = { 7 } } })
	ok(not logic.isCargoStop({ 60 }, c, isCargoStation, isSource), "passenger station next to a factory")
	eq(fetched, {})
	ok(not logic.isCargoStop({ 60, 1 }, c, isCargoStation, isSource), "cargo station, no source")
	eq(fetched, { "1:cargo" })
	c = fake({ [1] = { cargo = { 7, 99 } } })
	ok(logic.isCargoStop({ 60, 1 }, c, isCargoStation, isSource))
end)

test("findCargoStop: first cargo stop, scan stops there", function()
	local c, fetched = fake({ [1] = { cargo = { 7 } }, [2] = { cargo = { 99 } }, [3] = { cargo = { 99 } } })
	eq(logic.findCargoStop({ { 1 }, { 2 }, { 3 } }, c, isCargoStation, isSource), 2)
	eq(fetched, { "1:cargo", "2:cargo" })
	eq(logic.findCargoStop({ { 1 }, { 60 } }, c, isCargoStation, isSource), nil, "passenger-only line")
	eq(logic.findCargoStop({}, c, isCargoStation, isSource), nil)
end)
