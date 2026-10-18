-- pm_variety.lua (Photo Mode, pure): round 17, "The interesting buttons should always be able to click through and
-- get a new view each time". Bags (a cycle of subjects per kind, a shuffle bag over a list) and view variants.

local V

before_each(function()
	reset_modules()
	V = ug_require "square_photo_mode::/photo_mode/pm_variety.lua"
end)

local function rng(seed)
	local s = seed
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

local BASE = { x = 100, y = -50, d = 150, a = 0.4, p = 0.12 }

test("a one-item pool: 20 clicks give 20 distinct views of the same subject", function()
	local bag = V.newBag()
	local views, last = {}, nil
	for i = 1, 20 do
		ok(i == 1 or not V.isFresh(bag, "only"), "the only subject is taken")
		local n, m, k = V.take(bag, "only")
		eq(n, 1); eq(m, 1); eq(k, i - 1)
		local v = V.distinct(BASE, k, last)
		for j, w in ipairs(views) do ok(not V.same(v, w), "click " .. i .. " repeats click " .. j) end
		ok(v.d >= V.D_MIN and v.d <= V.D_MAX, "distance in range: " .. v.d)
		ok(v.p > 0 and v.p <= 0.85, "pitch in range: " .. v.p)
		eq(v.x, BASE.x); eq(v.y, BASE.y)
		views[#views + 1], last = v, v
	end
end)

test("a five-item pool visits all before repeating, then cycles again with new variants", function()
	local bag = V.newBag()
	local ids = { "a", "b", "c", "d", "e" }
	for cycle = 1, 3 do
		local seen = {}
		for i = 1, 5 do
			-- a scan: the first fresh id in its order wins, else the best shown one
			local pick = nil
			for __, id in ipairs(ids) do
				if V.isFresh(bag, id) then pick = id break end
			end
			pick = pick or ids[1]
			ok(not seen[pick], "no repeat in cycle " .. cycle)
			seen[pick] = true
			local n, m, k = V.take(bag, pick)
			eq(n, i); eq(m, cycle == 1 and i or 5, "the pool as found so far"); eq(k, cycle - 1)
		end
	end
end)

test("the cycle holds at most POOL_MAX subjects, then the best ones come back", function()
	local bag = V.newBag()
	for i = 1, V.POOL_MAX do
		ok(V.isFresh(bag, i))
		V.take(bag, i)
	end
	ok(not V.isFresh(bag, 99), "a full cycle: nothing is fresh")
	local n, m, k = V.take(bag, 1)
	eq(n, 1); eq(k, 1)
	ok(V.isFresh(bag, 2), "a new cycle")
end)

test("choose: a shuffle bag, every item once per cycle, never the last one first", function()
	local bag = V.newBag(math.huge)
	local ids = { 1, 2, 3, 4, 5, 6, 7 }
	local r = rng(5)
	local last = nil
	for cycle = 1, 10 do
		local seen = {}
		for __ = 1, #ids do
			local id = V.choose(bag, ids, r)
			ok(not seen[id], "once per cycle")
			ok(id ~= last, "not twice in a row")
			seen[id] = true
			V.take(bag, id, #ids)
			last = id
		end
	end
	eq(V.choose(bag, {}, r), nil)
	local one = V.newBag(math.huge)
	eq(V.choose(one, { 9 }, r), 9); V.take(one, 9)
	eq(V.choose(one, { 9 }, r), 9, "a single item comes back")
end)

test("vary: variant 0 is the framing itself; later ones turn, change style and stay finite", function()
	local v0, s0 = V.vary(BASE, 0)
	eq(v0, BASE); eq(s0, "frame")
	ok(v0 ~= BASE, "a copy")
	local styles = {}
	for k = 1, 6 do
		local v, style = V.vary(BASE, k)
		styles[#styles + 1] = style
		ok(v.a == v.a and v.d == v.d and v.p == v.p, "finite")
		ok(math.abs(v.a) <= math.pi + 1e-9)
	end
	eq(styles, { "eye", "high", "low", "eye", "high", "low" })
	eq(V.vary(nil, 3), nil)
	local bad = V.vary({ x = 0, y = 0, d = 0 / 0, a = 0, p = 0.1 }, 2)
	ok(bad ~= nil, "a non-finite view comes back unchanged, never raises")
end)

test("distinct: never the identical view twice in a row", function()
	local v, k = V.distinct(BASE, 0, nil)
	eq(k, 0); eq(v, BASE)
	local w, k2 = V.distinct(BASE, 0, v)
	ok(k2 >= 1 and not V.same(w, v), "the same framing as last time: a new variant")
	ok(V.same(BASE, { x = 100.5, y = -50, d = 150.5, a = 0.41, p = 0.12 }))
	ok(not V.same(BASE, nil))
end)

test("take: a missing id counts as a pool of one; memory starts afresh past MEMORY_MAX", function()
	local n, m, k = V.take(V.newBag(), nil)
	eq(n, 1); eq(m, 1); eq(k, 0)
	local bag = V.newBag(math.huge)
	for i = 1, V.MEMORY_MAX + 3 do V.take(bag, i) end
	ok(bag.seenN <= V.MEMORY_MAX, "bounded: " .. bag.seenN)
end)
