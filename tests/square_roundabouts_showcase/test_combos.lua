-- Entries read generically from the .con params, and the combination modes.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_showcase/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local combos = ug_require "/showcase/sc_combos.lua"

local ENTRIES = H.entries()

test("every square_roundabouts entry has params, a script and a mirror param", function()
	eq(#ENTRIES, 7)
	for _, e in ipairs(ENTRIES) do
		ok(#e.params >= 5, e.id .. ": params")
		ok(type(e.script) == "string" and e.script:find("@updateFn", 1, true), e.id .. ": script")
		ok(combos.mirrorParam(e), e.id .. ": mirror param")
		ok(#combos.visualParams(e) >= 2, e.id .. ": visual params")
		for _, p in ipairs(e.params) do
			ok(p.default >= 1 and p.default <= p.n, e.id .. " " .. p.key .. ": default in range")
		end
	end
	-- the highway entries carry their closure params (types)
	for _, e in ipairs(ENTRIES) do
		if e.id == "parclo" or e.id == "diamond" then ok(e.captureParams and e.captureParams.types, e.id .. ": types") end
	end
end)

test("paramsFromList drops broken params and fixes bad defaults", function()
	local ps = combos.paramsFromList({
		{ key = "a", values = { "x", "y" }, defaultIndex = 2 },
		{ key = "b", values = {} },
		{ values = { "z" } },
		{ key = "c", values = { "1", "2", "3" }, defaultIndex = 7 },
	})
	eq(#ps, 2)
	eq(ps[1].default, 2)
	eq(ps[2].default, 1)
	eq(ps[2].labels, { "1", "2", "3" })
end)

local function checkList(list, cap)
	ok(#list <= cap, "cap " .. cap)
	local seen = {}
	for _, c in ipairs(list) do
		ok(not seen[c.key], "duplicate " .. c.key)
		seen[c.key] = true
		for i, p in ipairs(c.entry.params) do
			local v = c.values[i]
			ok(v >= 1 and v <= p.n and v == math.floor(v), c.key .. ": value in range")
			eq(c.params[p.key], v)
		end
	end
end

test("every combination: capped, deterministic, entries in turn", function()
	for _, cap in ipairs({ 1, 7, 50, 500 }) do
		local a = combos.enumerate(ENTRIES, "every", cap, 1)
		eq(#a, cap)
		checkList(a, cap)
		local b = combos.enumerate(ENTRIES, "every", cap, 99)
		for i = 1, #a do eq(a[i].key, b[i].key) end
	end
	local a = combos.enumerate(ENTRIES, "every", 14, 1)
	local count = {}
	for _, c in ipairs(a) do count[c.entry.id] = (count[c.entry.id] or 0) + 1 end
	for _, e in ipairs(ENTRIES) do eq(count[e.id], 2, e.id) end
	-- a small entry runs out: all of its combinations, no more
	local small = { id = "s", params = combos.paramsFromList({ { key = "k", values = { "a", "b", "c" } } }) }
	eq(#combos.enumerate({ small }, "every", 100, 1), 3)
	-- the hard cap
	eq(#combos.enumerate(ENTRIES, "every", 1e6, 1, 300), 300)
end)

test("one setting at a time: defaults plus each other value", function()
	for _, e in ipairs(ENTRIES) do
		local want = 1
		for _, p in ipairs(e.params) do want = want + p.n - 1 end
		local list = combos.enumerate({ e }, "one", 1e6, 1, 1e6)
		eq(#list, want, e.id)
		eq(list[1].key, combos.make(e, combos.defaults(e)).key)
		checkList(list, 1e6)
	end
end)

test("showcase: every value of the most visible param, its product with the next, both sides", function()
	for _, e in ipairs(ENTRIES) do
		local list = combos.enumerate({ e }, "showcase", 1e6, 1, 1e6)
		checkList(list, 1e6)
		local vis = combos.visualParams(e)
		local a, b = vis[1], vis[2]
		local pairs_ = {}
		for _, c in ipairs(list) do pairs_[c.values[a] .. "/" .. c.values[b]] = true end
		for x = 1, e.params[a].n do
			for y = 1, e.params[b].n do ok(pairs_[x .. "/" .. y], e.id .. " " .. x .. "/" .. y) end
		end
		local mi = combos.mirrorParam(e)
		local sides = {}
		for _, c in ipairs(list) do sides[c.values[mi]] = true end
		ok(sides[1] and sides[2], e.id .. ": both traffic sides")
	end
end)

test("showcase picks a Scale / size param first wherever an entry has one (generic)", function()
	for _, e in ipairs(ENTRIES) do
		local first = e.params[combos.visualParams(e)[1]].key
		ok(first:find("scale", 1, true) or first:find("size", 1, true) or first:find("radius", 1, true), e.id .. ": " .. first)
	end
end)

test("random sample: seeded, distinct, capped", function()
	local a = combos.enumerate(ENTRIES, "random", 100, 3)
	local b = combos.enumerate(ENTRIES, "random", 100, 3)
	local c = combos.enumerate(ENTRIES, "random", 100, 4)
	eq(#a, 100)
	checkList(a, 100)
	local same, diff = true, false
	for i = 1, 100 do
		if a[i].key ~= b[i].key then same = false end
		if a[i].key ~= c[i].key then diff = true end
	end
	ok(same, "same seed, same sample")
	ok(diff, "other seed, other sample")
	local small = { id = "s", params = combos.paramsFromList({ { key = "k", values = { "a", "b" } } }) }
	eq(#combos.enumerate({ small }, "random", 100, 1), 2)
end)

test("mirrorOf flips only the traffic side", function()
	for _, e in ipairs(ENTRIES) do
		local c = combos.make(e, combos.defaults(e))
		local m = combos.mirrorOf(c)
		local mi = combos.mirrorParam(e)
		for i = 1, #e.params do
			if i == mi then ok(m.values[i] ~= c.values[i]) else eq(m.values[i], c.values[i]) end
		end
		eq(combos.mirrorOf(m).key, c.key)
	end
	eq(combos.describe(combos.make(ENTRIES[1], combos.defaults(ENTRIES[1]))), "defaults")
end)
