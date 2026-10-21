-- Close the gap census (§74 loosened, 2026-10-18): grown towns (no near-miss pass while growing, houses beside the
-- streets), then one pass with every chance 1 and no cap: how many near-miss dead ends can join, and why the rest stay.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OG = ug_require(F.DIR .. "ot_graph.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local NM = ug_require(F.DIR .. "ot_nearmiss.lua")

local FULL = os.getenv("TEST_FULL") ~= nil

local STYLES = { "EU_ORGANIC", "NORDIC", "EU_EXTENSION", "MED_HILL", "NA_SUBURB", "JP_DENSE" }
local VARIANTS = { { town = 11, angle = 0.4, year = 1905 }, { town = 23, angle = 1.1, year = 1950 },
	{ town = 37, angle = 2.3, year = 1990 } }

-- houses: a centre HOUSE_OFF m off both sides of every street every 25 m, none within 14 m of a node
local HOUSE_OFF = 15
local function houses(g)
	local out = {}
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		local L = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
		if L > 30 then
			local ux, uy = (b.x - a.x) / L, (b.y - a.y) / L
			local k = math.floor(L / 25)
			for i = 1, k do
				local s = (i - 0.5) * L / k
				if s >= 14 and s <= L - 14 then
					local x, y = a.x + ux * s, a.y + uy * s
					out[#out + 1] = { x - uy * HOUSE_OFF, y + ux * HOUSE_OFF }
					out[#out + 1] = { x + uy * HOUSE_OFF, y - ux * HOUSE_OFF }
				end
			end
		end
	end
	return out
end

local cache = {}
local function grown(id, v, steps)
	local key = id .. ":" .. v.town .. ":" .. steps
	if cache[key] then return cache[key] end
	local st, stats = F.style({ forceStyle = id, townId = v.town, year = v.year, capacity = 3000 }, F.flat)
	local g = F.vanillaTown(OG.new(), { angle = v.angle })
	for k = 1, steps do
		local inc = core.planIncrement(g, st, { terrain = F.flat, stats = stats, join = "deadEnd" })
		if #inc.edges == 0 then break end
		OG.apply(g, inc, k)
	end
	cache[key] = { g = g, st = st, b = houses(g) }
	return cache[key]
end

--- One census pass over a grown town: rep (why per dead end, joins).
local function census(t)
	local a, b, cap, tests, plans = NM.P_NEAR, NM.P_FAR, NM.MAX_PER_INC, NM.MAX_TESTS, NM.MAX_PLANS
	NM.P_NEAR, NM.P_FAR, NM.MAX_TESTS, NM.MAX_PLANS = 1.01, 1.01, 1000, 1000
	local okR, add, rep = pcall(NM.joins, t.g, t.st, nil, { terrain = F.flat, buildings = t.b, cap = 1000 })
	NM.P_NEAR, NM.P_FAR, NM.MAX_PER_INC, NM.MAX_TESTS, NM.MAX_PLANS = a, b, cap, tests, plans
	assert(okR, add)
	return rep, add
end

local function sum(into, rep)
	into.found = (into.found or 0) + rep.found
	into.joined = (into.joined or 0) + rep.joined
	into.why = into.why or {}
	for k, n in pairs(rep.why) do into.why[k] = (into.why[k] or 0) + n end
	into.kinds = into.kinds or {}
	for _, j in ipairs(rep.joins) do
		local k = j:match("^[^:]+")
		into.kinds[k] = (into.kinds[k] or 0) + 1
	end
end

local function line(s)
	local keys = {}
	for k in pairs(s.why or {}) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. ":" .. s.why[k] end
	local kp = {}
	for k, n in pairs(s.kinds or {}) do kp[#kp + 1] = k .. ":" .. n end
	table.sort(kp)
	return string.format("found %d joined %d (%s) kept %s", s.found or 0, s.joined or 0, table.concat(kp, ","),
		table.concat(parts, ","))
end

-- the rules before the loosening (2026-10-18; PLAN.md §74 "Less cautious")
local OLD = { KINK_DEG = 35, ARC_MIN = 78, GEN_SHAPES = 4, NODE_MAX = 80, SURE_M = 15, P_FAR = 0.15 }

local function with(rules, fn)
	local keep = {}
	for k, v in pairs(rules) do keep[k] = NM[k]; NM[k] = v end
	local okR, a, b = pcall(fn)
	for k, v in pairs(keep) do NM[k] = v end
	assert(okR, a)
	return a, b
end

-- expected joins under the seeded chance (the census draws none: every chance 1): the sum of chance(gap) over the joins
local function expected(rep)
	local e = 0
	for _, j in ipairs(rep.joins) do e = e + NM.chance(tonumber(j:match(":(%d+)$"))) end
	return e
end

test("census: near-miss dead ends of grown towns that can join, per reason, the old rules against the new", function()
	local STRIDE = FULL and 1 or 3
	local before, after = {}, {}
	local eb, ea = 0, 0
	local msB, msA = 0, 0
	local i = 0
	for _, id in ipairs(STYLES) do
		for _, v in ipairs(VARIANTS) do
			i = i + 1
			if (i - 1) % STRIDE == 0 then
				local t = grown(id, v, FULL and 10 or 8)
				local c0 = os.clock()
				local rb = with(OLD, function() return census(t) end)
				local c1 = os.clock()
				eb = eb + with(OLD, function() return expected(rb) end)
				local ra = census(t)
				local c2 = os.clock()
				msB, msA = math.max(msB, (c1 - c0) * 1000), math.max(msA, (c2 - c1) * 1000)
				ea = ea + expected(ra)
				sum(before, rb)
				sum(after, ra)
				ok(ra.found == rb.found, id .. ": the same near misses")
				local one = {}
				sum(one, ra)
				print(string.format("%-12s town %d: %s", id, v.town, line(one)))
			end
		end
	end
	print("before: " .. line(before))
	print("after:  " .. line(after))
	print(string.format("expected joins under the chance: before %.1f after %.1f", eb, ea))
	-- (the census lifts MAX_TESTS / MAX_PLANS: a pass in game stops at those and at its 8 ms budget)
	print(string.format("slowest uncapped pass: before %.1f ms after %.1f ms", msB, msA))
	ok((after.found or 0) > 0)
	ok(after.joined > before.joined, string.format("joined %d -> %d", before.joined, after.joined))
	ok(ea > eb * 1.2, string.format("expected %.1f -> %.1f", eb, ea))
	-- (what the loosening is for: fewer stubs with no node in reach, fewer too-sharp curves)
	ok((after.why.noNode or 0) < (before.why.noNode or 0), "noNode")
	ok((after.why.curve or 0) <= (before.why.curve or 0), "curve")
end)
