-- Offshoot names (ot_offname, NEXT_PHASE_BRIEF 47 "Satellite and Works name variety", 2026-10-14): Works named by the
-- industry's type, the site and the survey's cues in four patterns (parent / company / cue / generic), residential
-- districts with water words only where the site's water says so, each suffix once per map while others fit,
-- deterministic per seed, every list language; no composed names on a list without a classifier.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local OFF = ug_require(F.DIR .. "ot_offname.lua")
local WK = ug_require(F.DIR .. "ot_works.lua")
local DT = ug_require(F.DIR .. "ot_district.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")

local PARENTS = { "Haslemere", "Heywood", "Ringwood", "Tickhill", "Winchcombe", "Penkridge", "Settle", "Yarm", "Chesham",
	"Telscombe", "Ludlow", "Bampton" }
local FILES = { "industries/steel_mill/steel_mill.con", "industries/coal_mine/coal_mine.con",
	"industries/glass_works/glass_works.con", "industries/saw_mill/saw_mill.con", "industries/quarry/quarry.con",
	"industries/chemical_plant/chemical_plant.con", "industries/machine_factory/machine_factory.con",
	"industries/brewery/brewery.con", "industries/bricks_works/bricks_works.con", "industries/textile_factory/textile_factory.con" }
local KINDS = { "plain", "rail", "harbour", "plain", "hill", "across", "plain", "plain", "rail", "plain" }

local WATERY = { "Sands", "Beach", "Shore", "Sea", "Bay", "Lake", "Strand", "Waterside", "Lakeside", "Harbour", "Harbor",
	"Port", "Docks", "Quay", "Wharf" }
local function watery(nm, parent)
	-- (the parent's own words don't count: Haslemere's "mere")
	if parent then nm = nm:gsub(parent:gsub("%p", "%%%0"), " ") end
	if WK.hasWater(nm) then return true end
	for _, w in ipairs(WATERY) do if nm:find(w, 1, true) then return true end end
	return false
end

local function worksRun(cls, parents, seed, kinds)
	local used, out = {}, {}
	for i = 1, 10 do
		local p = parents[i]
		used[p] = true
	end
	for i = 1, 10 do
		local p = parents[i]
		local kind = kinds and kinds[i] or "plain"
		local nm, info = WK.name(cls, p, kind, used, { seed = seed + i, file = FILES[i], year = 1900,
			site = { harbour = kind == "harbour" } })
		ok(nm ~= nil, cls .. " " .. p)
		if nm then
			used[nm] = true
			out[#out + 1] = { nm, info }
		end
	end
	return out
end

local function keyCounts(list)
	local c = {}
	for _, e in ipairs(list) do
		local k = e[2] and e[2].suffix or "?"
		c[k] = (c[k] or 0) + 1
	end
	return c
end

test("industry types: the file's family (steel -> iron, coal mine -> coal, glass works -> glass ...)", function()
	eq(OFF.indType("industries/steel_mill/steel_mill.con"), "iron")
	eq(OFF.indType("industries/coal_mine/coal_mine.con"), "coal")
	eq(OFF.indType("industries/iron_ore_mine/iron_ore_mine.con"), "ore")
	eq(OFF.indType("industries/glass_works/glass_works.con"), "glass")
	eq(OFF.indType("industries/bricks_works/bricks_works.con"), "clay")
	eq(OFF.indType("industries/saw_mill/saw_mill.con"), "timber")
	eq(OFF.indType("industries/oil_refinery/oil_refinery.con"), "oil")
	eq(OFF.indType("industries/tire_factory/tire_factory.con"), "eng")
	eq(OFF.indType(nil), "works")
	local nm, info = WK.name("en", "Haslemere", "works", {}, { file = FILES[3], seed = 1 })
	eq(info.fam, "glass")
	ok(nm:find("Glass", 1, true) or nm:find("Bottle", 1, true) or info.pattern ~= "parent", nm)
end)

test("10 Works on one map with mixed industries: no suffix more than twice, Works at most once, not all <Parent> <suffix>", function()
	for _, cls in ipairs({ "en", "usa" }) do
		for seed = 1, 6 do
			local list = worksRun(cls, PARENTS, seed * 100, KINDS)
			local c = keyCounts(list)
			for k, n in pairs(c) do ok(n <= 2, cls .. " suffix " .. k .. " x" .. n) end
			ok((c.works or 0) <= 1, cls .. " Works x" .. tostring(c.works))
			local pats = {}
			for _, e in ipairs(list) do pats[e[2].pattern] = (pats[e[2].pattern] or 0) + 1 end
			ok((pats.parent or 0) <= 8, cls .. " parent pattern on " .. tostring(pats.parent) .. " of 10")
			ok((pats.company or 0) + (pats.cue or 0) >= 1, cls .. " some standalone names")
		end
	end
	-- the old "first form" behaviour is gone: the same plain site on ten maps doesn't always say Works
	local works = 0
	for seed = 1, 20 do
		local nm = WK.name("en", "Haslemere", "works", {}, { seed = seed })
		if nm == "Haslemere Works" then works = works + 1 end
	end
	ok(works <= 4, "Haslemere Works on " .. works .. " of 20 maps")
end)

test("Works: the site and the survey's cues (harbour, river, valley) bring their own words", function()
	local seen = {}
	for seed = 1, 30 do
		local nm, info = WK.name("en", "Heywood", "harbour", {}, { seed = seed, file = FILES[1], site = { sea = true } })
		seen[info.pattern] = true
		ok(nm ~= nil)
	end
	local sk = {} for k in pairs(seen) do sk[#sk + 1] = k end
	ok(seen.parent and seen.company, "parent and company names by a harbour: " .. table.concat(sk, ","))
	local cue = 0
	for seed = 1, 30 do
		local nm, info = WK.name("en", "Heywood", "across", {}, { seed = seed, file = FILES[2] })
		if info.pattern == "cue" then cue = cue + 1; ok(nm:find("bridge") or nm:find("brook") or nm:find("port"), nm) end
	end
	ok(cue >= 3, "river compounds " .. cue)
	-- no water word inland
	for seed = 1, 30 do
		local nm = WK.name("en", "Heywood", "plain", {}, { seed = seed, file = FILES[seed % 10 + 1] })
		ok(not watery(nm, "Heywood"), "inland Works " .. nm)
	end
end)

local function districtRun(cls, seed, site)
	local used, out = {}, {}
	for i = 1, 10 do used[PARENTS[i]] = true end
	local kinds = { "upper", "lead", "valley", "across", "shore", "lead", "upper", "shore", "valley", "lead" }
	local dirs = { "n", "e", "s", "w", "n", "s", "e", "w", "n", "e" }
	for i = 1, 10 do
		local st = { dir = dirs[i], dz = kinds[i] == "upper" and 25 or 0 }
		for k, v in pairs(site or {}) do st[k] = v end
		local nm, src, info = DT.name(cls, PARENTS[i], kinds[i], used, { seed = seed + i, site = st })
		ok(nm ~= nil, cls .. " district " .. PARENTS[i])
		if nm then
			used[nm] = true
			out[#out + 1] = { nm, info, PARENTS[i] }
		end
	end
	return out
end

test("10 residential satellites inland: no water words; a sandy sea shore gets one, once per map each", function()
	for seed = 1, 8 do
		local list = districtRun("en", seed * 37)
		for _, e in ipairs(list) do ok(not watery(e[1], e[3]), "inland " .. e[1]) end
		local c = keyCounts(list)
		for k, n in pairs(c) do ok(n <= 1, "district suffix " .. k .. " x" .. n) end
		-- usa too
		for _, e in ipairs(districtRun("usa", seed * 37)) do ok(not watery(e[1], e[3]), "inland usa " .. e[1]) end
	end
	-- by a river (a shore kind with river water): no beach words
	for seed = 1, 10 do
		local nm = DT.name("en", "Settle", "shore", {}, { seed = seed, site = { river = true } })
		ok(not nm:find("Sea") and not nm:find("Sands") and not nm:find("Strand"), "river bank " .. nm)
	end
	-- a sandy sea shore: a sea word sometimes; two on one map never share it
	local sea = 0
	for seed = 1, 20 do
		local used = {}
		local a = DT.name("en", "Penkridge", "shore", used, { seed = seed, site = { sea = true, sandy = true } })
		used[a] = true
		local b = DT.name("en", "Yarm", "shore", used, { seed = seed, site = { sea = true, sandy = true } })
		if watery(a, "Penkridge") then sea = sea + 1 end
		local ka = select(3, DT.name("en", "Penkridge", "shore", {}, { seed = seed, site = { sea = true, sandy = true } })).suffix
		local _, _, ib = DT.name("en", "Yarm", "shore", { [a] = true }, { seed = seed, site = { sea = true, sandy = true } })
		ok(ka ~= ib.suffix, a .. " / " .. b)
	end
	ok(sea >= 6, "sea words on " .. sea .. " of 20 sandy shores")
	-- a lake shore: the lake forms, never the sea ones
	for seed = 1, 10 do
		local nm = DT.name("en", "Penkridge", "shore", {}, { seed = seed, lake = true })
		ok(not nm:find("Sea") and not nm:find("Sands"), "lake " .. nm)
	end
end)

test("determinism per seed; a different seed varies", function()
	local a = worksRun("en", PARENTS, 500, KINDS)
	local b = worksRun("en", PARENTS, 500, KINDS)
	for i = 1, #a do eq(a[i][1], b[i][1]) end
	local d1 = districtRun("de", 9)
	local d2 = districtRun("de", 9)
	for i = 1, #d1 do eq(d1[i][1], d2[i][1]) end
	local diff = 0
	local c = worksRun("en", PARENTS, 900, KINDS)
	for i = 1, #a do if a[i][1] ~= c[i][1] then diff = diff + 1 end end
	ok(diff >= 3, "another seed: " .. diff .. " of 10 differ")
end)

test("every list language: 10 Works and 10 districts, no suffix more than twice", function()
	local parents = {
		ja = { "大垣", "高山", "松本", "長野", "富山", "金沢", "福井", "岐阜", "津", "奈良", "堺", "姫路" },
		ru = { "Тверь", "Клин", "Орёл", "Тула", "Псков", "Омск", "Томск", "Пермь", "Уфа", "Курск", "Ржев", "Тамбов" },
	}
	for cls in pairs(OFF.WORKS) do
		local ps = parents[cls] or PARENTS
		local list = worksRun(cls, ps, 7, KINDS)
		eq(#list, 10, cls)
		for k, n in pairs(keyCounts(list)) do ok(n <= 2, cls .. " Works suffix " .. k .. " x" .. n) end
		local used, dl = {}, {}
		for i = 1, 10 do used[ps[i]] = true end
		local kinds = { "upper", "lead", "valley", "across", "lead", "upper", "valley", "lead", "across", "upper" }
		for i = 1, 10 do
			local nm, _, info = DT.name(cls, ps[i], kinds[i], used, { seed = i, site = { dir = ({ "n", "e", "s", "w" })[i % 4 + 1] } })
			ok(nm ~= nil, cls .. " district " .. ps[i])
			if nm then used[nm] = true; dl[#dl + 1] = { nm, info }; ok(not watery(nm, ps[i]) or cls == "ja" or cls == "ja_r", cls .. " " .. nm) end
		end
		for k, n in pairs(keyCounts(dl)) do ok(n <= 2, cls .. " district suffix " .. k .. " x" .. n) end
	end
end)

test("lists without a classifier (asia, oceania ...): no composed name, an unused list name instead", function()
	eq(WK.name(false, "Wuhan", "plain", {}), nil)
	eq(DT.name(false, "Wuhan", "upper", {}), nil)
	eq(OFF.works(nil, "Wuhan", {}, {}), nil)
	local list = { "Wuhan", "Wenzhou", "Chengdu", "Mumbai", "Jakarta", "Manila" }
	local used = { Wuhan = true, Wenzhou = true }
	local nm = OFF.listName(list, used, 3)
	ok(nm ~= nil and not used[nm], tostring(nm))
	eq(OFF.listName(list, used, 3), nm, "deterministic")
	local all = {}
	for _, n in ipairs(list) do all[n] = true end
	eq(OFF.listName(list, all, 3), nil, "every name used")
	ok(not nm:find("High", 1, true) and not nm:find("Works", 1, true))
end)

test("the site's water: sea and sandy, a lake, a river, none inland", function()
	local function sampler(wet, h)
		return { height = h or function() return 10 end, water = wet }
	end
	local o = { isWater = T.isWater, slope = function(s, x, y) return T.slope(s, x, y) end }
	local sea = OFF.readWater(sampler(function(x) return x > 150 end), 0, 0, o)
	ok(sea.sea and sea.sandy and not sea.river, "sea")
	local lake = OFF.readWater(sampler(function(x, y) return x > 150 and x < 2500 and math.abs(y) < 2000 end), 0, 0, o)
	ok(lake.lake and not lake.sea, "lake")
	local river = OFF.readWater(sampler(function(x) return x > 150 and x < 220 end), 0, 0, o)
	ok(river.river and not river.sea and not river.lake, "river")
	local none = OFF.readWater(sampler(function() return false end), 0, 0, o)
	ok(none.near == nil and not none.sea and not none.river, "inland")
end)

test("samples: a typical EU (en) and US map", function()
	for _, cls in ipairs({ "en", "usa", "de" }) do
		local w = worksRun(cls, PARENTS, 42, KINDS)
		local parts = {}
		for _, e in ipairs(w) do parts[#parts + 1] = e[1] .. " [" .. e[2].pattern .. "]" end
		print(cls .. " Works: " .. table.concat(parts, "; "))
		local d = districtRun(cls, 42, nil)
		parts = {}
		for _, e in ipairs(d) do parts[#parts + 1] = e[1] .. " [" .. e[2].pattern .. "]" end
		print(cls .. " districts: " .. table.concat(parts, "; "))
	end
	print("used: " .. OFF.usedText("en", { "Haslemere Works", "Ironbridge", "Port Crossley", "North Settle" }))
end)

test("driver: an untagged list (asia) gives offshoots an unused list name, a tagged one its classifier (NEXT_PHASE_BRIEF 48 item 2)", function()
	local D = ug_require(F.DIR .. "ot_driver.lua")
	local E = { townList = function(path, dir) return { "Wuhan", "Wenzhou", "Chengdu", "Mumbai", "Jakarta" } end,
		log = function() end }
	local d = D.new(E)
	d.cfg = { nameList = "::/names/asia/towns.names.lua" }
	d.opts = {}
	eq(d:offshootCls({}), false)
	local nm = d:offshootListName({}, { Wuhan = true, Wenzhou = true }, 4)
	ok(nm == "Chengdu" or nm == "Mumbai" or nm == "Jakarta", tostring(nm))
	local d2 = D.new(E)
	d2.cfg = { nameList = "::/names/germany/towns.names.lua" }
	d2.opts = {}
	ok(d2:offshootCls({ nd = "de" }) == "de", "germany: de")
end)
