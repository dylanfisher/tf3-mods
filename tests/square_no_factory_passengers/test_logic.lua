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

test("decide: industry + homes -> keep", function()
	local c = fake({ [1] = { cargo = { 99 }, pax = { 99, 42 } } })
	eq({ logic.decide({ 1 }, c, isInd, isHome) }, { false, true })
	c = fake({ [1] = { cargo = { 99 }, pax = {} }, [2] = { cargo = {}, pax = { 42 } } })
	eq({ logic.decide({ 1, 2 }, c, isInd, isHome) }, { false, true }, "homes at another station of the group")
end)

test("decide: industry only -> clear, even with the factory's own workplaces in reach", function()
	eq({ logic.decide({ 1 }, fake({ [1] = { cargo = { 99 }, pax = { 99 } } }), isInd, isHome) }, { true, true })
	eq({ logic.decide({ 1 }, fake({ [1] = { cargo = { 7, 99 } } }), isInd, isHome) }, { true, true })
end)

test("decide: no industry -> keep, passenger catchables never fetched", function()
	local c, fetched = fake({ [1] = { cargo = { 7 }, pax = { 42 } } })
	eq({ logic.decide({ 1 }, c, isInd, isHome) }, { false, false })
	eq(fetched, { "1:cargo" })
	eq({ logic.decide({ 1 }, fake({}), isInd, isHome) }, { false, false }, "nothing in reach")
end)

test("decideLine: no-home stops cleared only on a line with an industry-only stop", function()
	local world = { [1] = { cargo = { 99 }, pax = { 99 } }, [2] = { cargo = {}, pax = { 7 } },
		[3] = { cargo = {}, pax = { 42 } } }
	local clear, industry = logic.decideLine({ { 1 }, { 2 }, { 3 } }, fake(world), isInd, isHome)
	eq(clear, { true, true, false })
	eq(industry, { true, false, false })
	local c, fetched = fake(world)
	clear = logic.decideLine({ { 2 }, { 3 } }, c, isInd, isHome)
	eq(clear, { false, false }, "no factory on the line")
	eq(fetched, { "2:cargo", "3:cargo" }, "pax catchables not fetched")
	eq({ logic.decideLine({}, c, isInd, isHome) }, { {}, {} })
end)
