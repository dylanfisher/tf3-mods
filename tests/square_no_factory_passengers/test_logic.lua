-- nfp_logic: the per-station-group decision on plain data.

local logic = ug_require "square_no_factory_passengers::/no_factory_passengers/nfp_logic.lua"

local isInd = function(e) return e == 99 end
local isHome = function(e) return e == 42 end

-- catchables(station, cargo) over a { [station] = { cargo = {...}, pax = {...} } } table, recording
-- every fetch as "station:cargo|pax"
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
	ok(logic.anyCatchable({ 1, 2 }, c, true, isInd))
	ok(not logic.anyCatchable({ 1 }, c, true, isInd))
	ok(not logic.anyCatchable({}, c, true, isInd))
	ok(not logic.anyCatchable({ 3 }, c, true, isInd), "nil catchables")
end)

test("anyCatchable: stops at the first match, without fetching further stations", function()
	local c, fetched = fake({ [1] = { cargo = { 99, 98 } }, [2] = { cargo = { 99 } } })
	ok(logic.anyCatchable({ 1, 2 }, c, true, isInd))
	eq(fetched, { "1:cargo" })
end)

test("decide: industry + homes -> keep, cargo catchables never fetched", function()
	local c, fetched = fake({ [1] = { cargo = { 99 }, pax = { 99, 42 } } })
	eq({ logic.decide({ 1 }, c, isInd, isHome) }, { false, false, true })
	eq(fetched, { "1:pax" })
	c = fake({ [1] = { cargo = { 99 }, pax = {} }, [2] = { cargo = {}, pax = { 42 } } })
	eq({ logic.decide({ 1, 2 }, c, isInd, isHome) }, { false, false, true }, "homes at another station of the group")
end)

test("decide: industry only -> clear, even with the factory's own workplaces in reach", function()
	eq({ logic.decide({ 1 }, fake({ [1] = { cargo = { 99 }, pax = { 99 } } }), isInd, isHome) }, { true, true, false })
	eq({ logic.decide({ 1 }, fake({ [1] = { cargo = { 7, 99 } } }), isInd, isHome) }, { true, true, false })
end)

test("decide: town stop -> keep, stops at the first home without fetching cargo catchables", function()
	local c, fetched = fake({ [1] = { cargo = { 7, 8, 9 }, pax = { 42, 43 } }, [2] = { pax = { 42 } } })
	eq({ logic.decide({ 1, 2 }, c, isInd, isHome) }, { false, false, true })
	eq(fetched, { "1:pax" })
end)

test("decide: no homes, no industry -> keep", function()
	local c, fetched = fake({ [1] = { cargo = { 7 }, pax = { 7 } } })
	eq({ logic.decide({ 1 }, c, isInd, isHome) }, { false, false, false })
	eq(fetched, { "1:pax", "1:cargo" })
	eq({ logic.decide({ 1 }, fake({}), isInd, isHome) }, { false, false, false }, "nothing in reach")
end)

test("decideLine: no-home stops cleared only on a line with an industry-only stop", function()
	local world = { [1] = { cargo = { 99 }, pax = { 99 } }, [2] = { cargo = {}, pax = { 7 } },
		[3] = { cargo = { 99 }, pax = { 42 } } }
	local c, fetched = fake(world)
	local clear, industry = logic.decideLine({ { 1 }, { 2 }, { 3 } }, c, isInd, isHome)
	eq(clear, { true, true, false })
	eq(industry, { true, false, false })
	eq(fetched, { "1:pax", "1:cargo", "2:pax", "2:cargo", "3:pax" }, "each kind fetched at most once per group")
	clear = logic.decideLine({ { 2 }, { 3 } }, c, isInd, isHome)
	eq(clear, { false, false }, "no factory on the line")
	eq({ logic.decideLine({}, c, isInd, isHome) }, { {}, {} })
end)
