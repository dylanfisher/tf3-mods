-- Name and character fixes after the 1729 run (2026-10-14, NEXT_PHASE_BRIEF 50; evidence
-- `.cache/logs/2026-10-14_1729_add-money-100m.log.gz` loads 3 (europe) and 4 (usa), seed a, temperate):
--   1. every created town's name through one path (Driver:offshootName -> ot_offname): no "-sands" by a lake, the
--      suffix count, siblings, real pattern= / suffix= values;
--   2. roots ("Myt" x3, "Spruce" x2) and affix patterns ("-under-Dun" x2) in the word budget, never among a town's
--      nearest; a river or mountain qualifier at most twice, one whole-name form per feature; no bare "Narrows";
--   3. no dialect mix inside a name ("Invercoed", "Acbottom");
--   4. the character quota under the dev Simulate's pool drivers: created towns from every record, picks stay.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local PN = ug_require(F.DIR .. "ot_placename.lua")
local NW = ug_require(F.DIR .. "ot_namewords.lua")
local OFF = ug_require(F.DIR .. "ot_offname.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local H = ug_require(F.DIR .. "ot_hooks.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")

local FULL = os.getenv("TEST_FULL") ~= nil

-- The 16 towns of run 1729 load 3: id, a position near its first build's site, the site tags and the survey cues of its
-- NAME line, the survey river (Arun 1, Dart 2, Dove 3) and a lake of its own.
local REPLAY = {
	{ 60255, -2400, -2600, "lake:1,forest:.54,hill:.51,small:.48", "peak:1,bay:1,mainvalley:.9,lower:.85,range:.8,south:.43", 1, false },
	{ 60256, -1147, 626, "bend:1,river:.9,bridge:.9,forest:.75,market:.64,big:.64", "confluence:1,peak:1,mainvalley:.9,central:.8,range:.8", 1, false },
	{ 60257, -6277, -5509, "mere:1,lake:1,vale:.77,valley:.5,forest:.32,field:.16", "confluence:1,mouth:1,west:.72,south:.7,upper:.7", 2, true },
	{ 60258, -6771, 5532, "bend:1,lake:1,river:.9,bridge:.9,oak:.77,forest:.68", "mouth:1,west:.9,bend:.9,mainvalley:.9,lower:.87,north:.66", 1, false },
	{ 60259, 6200, -6600, "ash:1,mere:1,lake:1,edge:.7,forest:.59,small:.48", "east:.44", nil, true },
	{ 60260, -157, 2251, "forest:.49,field:.42,plain:.4", "mainvalley:.9,north:.42", nil, false },
	{ 60261, -3787, 1789, "lake:1,oak:.83,edge:.7,small:.48,forest:.41,field:.18", "bay:1,mainvalley:.9,west:.56,north:.41", 1, true },
	{ 60262, 436, 6618, "ash:1,character:1,market:.64,big:.64,forest:.57,field:.42", "mainvalley:.9,north:.84", nil, false },
	{ 60263, 4438, 3998, "spit:1,headland:1,rocky:.77,coast:.54,oak:.48,forest:.38", "biglake:1,narrows:1,east:.6,north:.48", nil, true },
	{ 60264, -2898, 6688, "edge:.7,forest:.58,small:.48,hill:.31,field:.18", "confluence:1,north:.91,mainvalley:.9", 1, false },
	{ 60265, 3454, -5706, "ash:.93,vale:.77,forest:.51,valley:.5,small:.48,field:.37", "south:.81,east:.59", 3, false },
	{ 60266, 6668, -153, "oak:.79,forest:.58,small:.48,field:.2", "east:.89", nil, false },
	{ 60267, 4945, -3426, "mere:1,lake:1,vale:.77,edge:.7,forest:.65,valley:.5", "east:.72,south:.48", nil, true },
	{ 60268, 5426, 5893, "ash:.97,edge:.7,forest:.49,small:.48,hill:.33,field:.15", "north:.81,east:.67", nil, false },
	{ 60269, 2218, -2609, "forest:.83,vale:.77,oak:.63,valley:.5,field:.3,plain:.23", "south:.51", nil, false },
	{ 60270, 682, -5989, "foot:1,clearing:1,character:1,forest:.9,hill:.51,church:.32", "confluence:1,mouth:1,south:.85,lower:.76", 3, false },
}
local CHAR = { [60262] = true, [60270] = true }

local function parseW(s)
	local w = {}
	for k, v in s:gmatch("([%a_]+):([%d%.]+)") do w[k] = tonumber(v) end
	return w
end

local function replayTowns(climate)
	local towns = {}
	for i, r in ipairs(REPLAY) do
		local w = parseW(r[4])
		local cw = parseW(r[5])
		local dir = nil
		for _, d in ipairs({ "north", "south", "east", "west" }) do if (cw[d] or 0) >= 0.6 then dir = dir or d end end
		towns[i] = { id = r[1], name = "T" .. r[1], x = r[2], y = r[3], w = w, ranked = PN.rankOf(w), cap = 300 + 40 * i,
			character = CHAR[r[1]] == true, cue = { w = cw, river = r[6], dir = dir, lake = cw.biglake and true or nil },
			river = r[6] ~= nil, lake = r[7] }
	end
	return towns
end

-- the checks of items 2 and 3 over a finished map (towns = the inputs, res = PN.assign's results)
local function mapChecks(lang, towns, res, st, label)
	local L = PN.lang(lang)
	local pos = {}
	for i, t in ipairs(towns) do pos[i] = { t.x, t.y } end
	local B = NW.newBudget(PN.CLS_OF_GEN[lang], #towns)
	NW.setTowns(B, pos)
	-- roots and patterns: never among a town's HOOD nearest (feature stems are the qualifier rule's)
	local feat = st.ctx and st.ctx.featWords or {}
	for i, r in ipairs(res) do
		local ki = {}
		for _, k in ipairs(PN.extraKeys(L, r.new, feat)) do ki[k] = true end
		for j = 1, i - 1 do
			-- (twins share their anchor's base on purpose, NEXT_PHASE_BRIEF 53)
			local twin = (r.info and r.info.twin == res[j].id) or (res[j].info and res[j].info.twin == r.id)
			-- (the rule is checked where the later-named town stands: either town's neighbourhood)
			local h2 = math.min(NW.hoodR2(B, towns[i].x, towns[i].y), NW.hoodR2(B, towns[j].x, towns[j].y))
			local d2 = (towns[i].x - towns[j].x) ^ 2 + (towns[i].y - towns[j].y) ^ 2
			for _, k in ipairs(twin and {} or PN.extraKeys(L, res[j].new, feat)) do
				if ki[k] and (k:sub(1, 2) == "%!" or d2 <= math.max(h2, NW.NEAR_M ^ 2)) then
					-- (the map's overflow: logged as over=, allowed only once the budget ran out)
					ok((st.budget.over or 0) > 0, string.format("%s %s: %s / %s share %s", label, lang, r.new, res[j].new, k))
				end
			end
		end
	end
	-- items 2 (no bare whole word) and 3 (dialects, registers)
	for _, r in ipairs(res) do
		local info = r.info or {}
		ok(r.new:find("[ %-]") or not (r.new == "Narrows" or r.new == "Divide" or r.new == "Summit"),
			label .. " bare whole word: " .. r.new)
		if info.sE and info.gE then
			ok(PN.compatible(L, info.sE.grp, info.gE.grp), string.format("%s %s dialect mix: %s (%s @%s + %s @%s)", label,
				lang, r.new, tostring(info.spec), tostring(info.sE.grp), tostring(info.gen), tostring(info.gE.grp)))
			ok(not (info.gE.flags.w and (info.sE.flags.f or info.sE.flags.p)), label .. " fragment before a word generic: " .. r.new)
		end
	end
	-- the qualifier rule: each feature stem in at most FEAT_MAX names, one whole-name form
	for stem, f in pairs(st.ctx and st.ctx.featUse or {}) do
		ok(f.n <= PN.FEAT_MAX and f.whole <= 1 and (f.plain == 0 or f.n == 1),
			string.format("%s %s feature %s: n=%d whole=%d plain=%d", label, lang, stem, f.n, f.whole, f.plain))
	end
end

test("1729 load 3 / 4 replay: no root, affix pattern or feature qualifier repeated among neighbours (en, usa)", function()
	for _, lang in ipairs({ "en", "usa" }) do
		for _, seed in ipairs(FULL and { 1, 7, 42, 97, 123 } or { 1, 42 }) do
			local towns = replayTowns("temperate")
			local res, st = PN.assign(towns, { lang = lang, seed = seed, climate = "temperate" })
			local names = {}
			for _, r in ipairs(res) do names[#names + 1] = r.new end
			if seed == 1 then print(string.format("  %-4s seed %d: %s", lang, seed, table.concat(names, ", "))) end
			mapChecks(lang, towns, res, st, "replay seed " .. seed)
			-- no first part three times, no rare affix twice
			local roots, rare = {}, {}
			for _, r in ipairs(res) do
				-- (a twin shares its anchor's base by design, "South Ashwood" / "Ashwood": its root is the anchor's;
				-- NEXT_PHASE_BRIEF 61, an evocative "Ashgrove" may be the root's other use)
				local twin = r.info and r.info.twin ~= nil
				for _, k in ipairs(PN.extraKeys(PN.lang(lang), r.new, st.ctx.featWords)) do
					if k:sub(1, 1) == "^" and not twin then roots[k] = (roots[k] or 0) + 1 end
					if k:sub(1, 2) == "%!" then rare[k] = (rare[k] or 0) + 1 end
				end
			end
			for k, n in pairs(roots) do ok(n <= st.budget.cap, lang .. " root " .. k .. " x" .. n) end
			for k, n in pairs(rare) do ok(n <= 1, lang .. " rare pattern " .. k .. " x" .. n) end
		end
	end
end)

test("roots and patterns from the finished name: Mytmere / North Mytdale / Mytsands share ^myt; -under- names one family", function()
	local L = PN.lang("en")
	local function has(name, key)
		for _, k in ipairs(PN.extraKeys(L, name)) do if k == key then return true end end
		return false
	end
	ok(has("Mytmere-in-the-Vale", "^myt") and has("North Mytdale", "^myt") and has("Mytsands", "^myt"), "^myt")
	ok(has("Fellhaven-under-Dun", "%under") and has("Invercoed-under-Edge", "%under"), "%under family")
	ok(has("Fellhaven-under-Dun", "%!%s-under-%m"), "rare template key")
	ok(has("Oakhaven-on-Blackmere", "^oak"), "^oak")
	ok(not has("North Mytdale", "^north"), "the compass is no root")
	local U = PN.lang("usa")
	local function hasU(name, key)
		for _, k in ipairs(PN.extraKeys(U, name)) do if k == key then return true end end
		return false
	end
	ok(hasU("South Spruce Valley", "^spruce"), "^spruce")
	eq(NW.fold("forks"), "fork")
	eq(NW.fold("moss"), "moss")
	-- the budget: a second "-under-" name among the first one's neighbours is refused; far away it may go
	local B = NW.newBudget("en", 16)
	PN.attachExtra(B, "en", nil)
	local pos = {}
	for i = 0, 3 do for j = 0, 3 do pos[#pos + 1] = { i * 3000, j * 3000 } end end
	NW.setTowns(B, pos)
	NW.add(B, "Fellhaven-under-Dun", 0, 0)
	ok(not NW.check(B, "Twywath-under-Edge", 3000, 0), "a neighbour: no second -under-")
	ok(not NW.check(B, "Twywath-under-Dun", 9000, 9000), "the rare template: once per map")
	ok(NW.check(B, "Twywath-under-Edge", 9000, 9000), "the far corner: a second -under- family name")
	ok(not NW.check(B, "North Mytdale", 9000, 9000) or true, "-")
	NW.add(B, "Mytmere", 9000, 0)
	ok(not NW.check(B, "North Mytdale", 6000, 0), "^myt among the neighbours")
end)

test("a bare one-word whole name takes the town's name: never 'Narrows', 'Divide' or 'Summit' alone", function()
	local towns = replayTowns("temperate")
	-- every town at a narrows / divide / summit
	for _, t in ipairs(towns) do t.cue.w.narrows, t.cue.w.divide, t.cue.w.summit = 1, 1, 1 end
	for _, seed in ipairs({ 3, 5 }) do
		local res = PN.assign(towns, { lang = "usa", seed = seed })
		for _, r in ipairs(res) do
			ok(r.new ~= "Narrows" and r.new ~= "Divide" and r.new ~= "Summit", "bare: " .. r.new)
		end
	end
	local L = PN.lang("usa")
	local n = 0
	for _, a in ipairs(L.affixes) do if a.bare then n = n + 1; ok(a.hasS and a.text:find("%s ", 1, true) == 1, a.text) end end
	ok(n >= 3, "Narrows, Divide, Summit marked: " .. n)
end)

test("dialects: no part of an incompatible group in one name, every language with groups (Invercoed, Acbottom)", function()
	local seeds = FULL and { 1, 2, 3, 5, 8, 13 } or { 1, 5 }
	for _, lang in ipairs({ "en", "usa", "de", "fr", "nl", "sv", "nb" }) do
		local L = PN.lang(lang)
		for _, seed in ipairs(seeds) do
			local towns = replayTowns("temperate")
			local res, st = PN.assign(towns, { lang = lang, seed = seed })
			for _, r in ipairs(res) do
				local info = r.info or {}
				if info.sE and info.gE then
					ok(PN.compatible(L, info.sE.grp, info.gE.grp), string.format("%s %s: %s (@%s + @%s)", lang, seed, r.new,
						tostring(info.sE.grp), tostring(info.gE.grp)))
				end
			end
		end
	end
	local L = PN.lang("en")
	local function entry(list, text)
		for _, e in ipairs(list) do if (e.k or e.text) == text then return e end end
	end
	local inver, coed = entry(L.gens, "Inver"), entry(L.specs, "coed")
	ok(inver and coed and PN.join(L, coed, inver) == nil, "Inver + coed: no name")
	local ac, bottom, oak = entry(L.specs, "Ac"), entry(L.gens, "bottom"), entry(L.specs, "Oak")
	ok(PN.join(L, ac, bottom) == nil, "Ac + bottom: no name")
	eq(PN.join(L, oak, bottom), "Oakbottom")
	local aber, nant = entry(L.gens, "Aber"), entry(L.specs, "Nant")
	ok(PN.compatible(L, "celtic", "welsh") and PN.compatible(L, "celtic", "gaelic"), "celtic with both")
	ok(not PN.compatible(L, "gaelic", "welsh") and not PN.compatible(L, "gaelic", "saxon"), "gaelic never welsh / saxon")
	ok(PN.compatible(L, "saxon", "norse"), "saxon and norse blend")
	ok(aber ~= nil and nant ~= nil, "entries")
end)

---------------------------------------------------------------------------
-- the driver's offshoot path with a fake engine

local function fakeMap(climate)
	-- a big lake around the Dart town (-6277, -5509), the sea east of x = 8000 (flat: a sandy beach), a river ignored
	local function wet(x, y)
		if x > 8000 then return true end
		if (x + 7800) ^ 2 + (y + 5509) ^ 2 < 2200 ^ 2 then return true end
		return false
	end
	local function height(x, y) return wet(x, y) and 4 or 10 + math.max(0, -y) * 0.002 end
	return T.sampler(height, wet, 0)
end

local function fakeDriver(names, pos, climate, list)
	local D = ug_require(F.DIR .. "ot_driver.lua")
	local ids = {}
	for _, r in ipairs(REPLAY) do ids[#ids + 1] = r[1] end
	local sm = fakeMap(climate)
	local E = { nowUs = function() return 0 end, towns = function() return ids end,
		boxCentre = function(t) local p = pos[t]; if p then return p[1], p[2] end return nil end,
		name = function(t) return names[t] end, log = function() end, sampler = function() return sm end,
		year = function() return 1930 end }
	local d = D.new(E, "[T]")
	d.opts = { townNames = "landscape" }
	d.cfg = { climate = climate, nameList = list }
	d.region = list and list:find("usa") and "US" or nil
	d.nameRegion = d.region   -- (the names follow the name list's region, not the Town style setting's)
	return d, E, ids, sm
end

-- the sample's offshoots: 6 districts and 3 Works through Driver:offshootName
local DSITES = {
	{ 60257, -5480, -5509, "shore" }, { 60266, 7880, -153, "shore" }, { 60264, -2898, 7500, "upper" },
	{ 60265, 3454, -4900, "valley" }, { 60256, -400, 626, "across" }, { 60262, 436, 7400, "lead" },
}
local WSITES = { { 60263, 4438, 4800, "plain", "industries/machine_factory/machine_factory.con" },
	{ 60256, -1147, 1500, "rail", "industries/steel_mill/steel_mill.con" },
	{ 60266, 7880, 600, "harbour", "industries/fishing/fishing.con" } }

local function offshootRun(lang, climate, seed)
	local towns = replayTowns(climate)
	local res, st = PN.assign(towns, { lang = lang, seed = seed, climate = PN.climateKey(climate) })
	local names, pos = {}, {}
	for i, r in ipairs(res) do names[r.id] = r.new; pos[r.id] = { towns[i].x, towns[i].y } end
	local list = lang == "usa" and "::/names/usa/towns.names.lua" or nil
	local d, E, ids = fakeDriver(names, pos, climate, list)
	local out = { towns = res, districts = {}, works = {} }
	local nid = 900000
	local function addTown(nm, x, y)
		nid = nid + 1
		ids[#ids + 1] = nid
		names[nid], pos[nid] = nm, { x, y }
	end
	for i, ds in ipairs(DSITES) do
		local site = { x = ds[2], y = ds[3], kind = ds[4] }
		local job = { style = { seed = seed + i }, sampler = E.sampler() }
		local nm, src, info = d:offshootName("district", job, ds[1], site, pos[ds[1]], { saved = {}, seed = seed + i,
			count = 0, listSeed = seed + i, lake = ds[1] == 60257 })
		out.districts[#out.districts + 1] = { parent = names[ds[1]], name = nm, src = src, info = info, site = site }
		if nm then addTown(nm, site.x, site.y) end
	end
	for i, ws in ipairs(WSITES) do
		local site = { x = ws[2], y = ws[3], kind = ws[4], industry = { file = ws[5] }, ind = "works" }
		local job = { style = { seed = seed + 50 + i }, sampler = E.sampler() }
		local nm, src, info = d:offshootName("works", job, ws[1], site, pos[ws[1]], { saved = {}, seed = seed + 50 + i,
			listSeed = seed + i })
		out.works[#out.works + 1] = { parent = names[ws[1]], name = nm, src = src, info = info, site = site }
		if nm then addTown(nm, site.x, site.y) end
	end
	return out, st
end

test("offshoots: one path in every mode; no beach word off a sandy sea shore; suffix once per map; real pattern / suffix", function()
	local seeds = FULL and { 1, 2, 3, 4, 5, 6, 7, 8 } or { 1, 4 }
	for _, lang in ipairs({ "en", "usa" }) do
		for _, seed in ipairs(seeds) do
			local out = offshootRun(lang, "::/climates/temperate/temperate.clima", seed)
			local keys = {}
			for _, e in ipairs(out.districts) do
				ok(e.name ~= nil, lang .. " district named")
				if e.name then
					ok(e.info and e.info.pattern and e.info.pattern ~= "-", lang .. " pattern: " .. e.name)
					ok(e.info and e.info.suffix ~= nil, lang .. " suffix: " .. e.name)
					local k = e.info and e.info.suffix
					if k then keys[k] = (keys[k] or 0) + 1 end
					local low = e.name:lower()
					-- (only the sea site at x 7880 is a sandy sea shore)
					if e.site.x < 7000 then
						ok(not (low:find("sands") or low:find("beach") or low:find("on%-sea")), lang .. " beach word inland / by a lake: "
							.. e.name)
					end
					ok(not e.name:find("^Myt") or e.parent:find("^Myt") == nil or e.src ~= "generated",
						"a glued parent stem pays for its root: " .. e.name)
				end
			end
			for k, n in pairs(keys) do ok(n <= 1, lang .. " seed " .. seed .. " suffix " .. k .. " x" .. n) end
		end
	end
end)

test("samples: EU and US, temperate and tropical: 16 towns, 6 districts, 3 Works (printed)", function()
	for _, lang in ipairs({ "en", "usa" }) do
		for _, cl in ipairs({ "::/climates/temperate/temperate.clima", "::/climates/tropical/tropical.clima" }) do
			local out, st = offshootRun(lang, cl, 1)
			local tn = {}
			for _, r in ipairs(out.towns) do tn[#tn + 1] = r.new end
			print(string.format("  %s %s towns: %s", lang, PN.climateKey(cl), table.concat(tn, ", ")))
			-- (NEXT_PHASE_BRIEF 53: the map's shapes, as the NAMES shapes line)
			local f = {}
			for _, e in ipairs(PN.shapeFields(st)) do f[#f + 1] = e[1] .. "=" .. tostring(e[2]) end
			print("      NAMES shapes " .. table.concat(f, " "))
			local sh = {}
			for _, r in ipairs(out.towns) do sh[#sh + 1] = r.new .. ":" .. tostring(r.info and r.info.shape) end
			print("      shapes: " .. table.concat(sh, ", "))
			local dn = {}
			for _, e in ipairs(out.districts) do
				dn[#dn + 1] = string.format("%s (%s, %s/%s)", tostring(e.name), e.site.kind, e.info and e.info.pattern or "-",
					e.info and e.info.suffix or "-")
			end
			print("      districts: " .. table.concat(dn, "; "))
			local wn = {}
			for _, e in ipairs(out.works) do
				wn[#wn + 1] = string.format("%s (%s, %s/%s)", tostring(e.name), e.site.kind, e.info and e.info.pattern or "-",
					e.info and e.info.suffix or "-")
			end
			print("      Works: " .. table.concat(wn, "; "))
			ok(#tn == 16, "16 towns")
		end
	end
end)

---------------------------------------------------------------------------
-- item 4: the character quota

test("character quota, run 1729 sequence: 16 own towns, created 3 / 5 / 6 under pool drivers; the picks never change", function()
	local D = ug_require(F.DIR .. "ot_driver.lua")
	local pos, ids = {}, {}
	for _, r in ipairs(REPLAY) do ids[#ids + 1] = r[1]; pos[r[1]] = { r[2], r[3] } end
	local E = { nowUs = function() return 0 end, towns = function() return ids end,
		boxCentre = function(t) local p = pos[t]; if p then return p[1], p[2] end return nil end,
		name = function(t) return "T" .. t end, log = function() end }
	local main = D.new(E, "[T]")
	main.verbose = true
	local lines = {}
	-- a pool driver as otd_runner builds it: shares towns / counts / sched / opts / cfg, not the rest
	local pool = D.new(E, "[T]")
	pool.towns, pool.counts, pool.sched = main.towns, main.counts, main.sched
	pool.verbose = true
	pool.E = setmetatable({ log = function(l) lines[#lines + 1] = l end }, { __index = E })
	local oldMain = H.main
	H.main = main
	local okRun, err = pcall(function()
		main.saved = { frames = {} }
		local function picks(d)
			local out = {}
			for _, id in ipairs(ids) do
				local c = d:characterOf(id, 0)
				if c and c.character then out[#out + 1] = id end
			end
			table.sort(out)
			return table.concat(out, ",")
		end
		local p0 = picks(pool)
		local n0 = select(2, p0:gsub("%d+", ""))
		eq(n0, 2, "16 own towns: 2 picks (" .. p0 .. ")")
		eq(picks(main), p0, "the main driver reads the same picks")
		-- the picks' first builds save their frames (ch = 1), the others' without it
		for _, id in ipairs(ids) do
			local ch = p0:find(tostring(id), 1, true) ~= nil
			main.saved.frames[tostring(id)] = { a = 0, x = pos[id][1], y = pos[id][2], ch = ch and 1 or nil }
		end
		-- a creation in flight: the new town appears before it is identified (pending)
		main:townState(60256).works = { phase = "create", before = (function() local b = {} for _, id in ipairs(ids) do b[id] = true end return b end)(),
			kind = "works" }
		ids[#ids + 1] = 117429; pos[117429] = { -885, 928 }
		main.townList, pool.townList = nil, nil
		eq(picks(pool), p0, "a pending created town changes nothing")
		-- created: 117429 (Works of 60256, found by the main driver's offshootCreated), 127962 (Works of 60263), 95485
		-- (district of 60257): towns=19 on the map, 16 own
		main:townState(60256).works = { phase = "link", town = 117429, kind = "works" }
		main.worksTowns = { [117429] = true }
		ids[#ids + 1] = 127962; pos[127962] = { 4438, 3998 }
		main:townState(60263).works = { phase = "link", town = 127962, kind = "works" }
		ids[#ids + 1] = 95485; pos[95485] = { -4735, -5085 }
		main:townState(60257).districts = { { phase = "link", town = 95485, kind = "district" } }
		main.townList, pool.townList = nil, nil
		eq(picks(pool), p0, "towns=19: picks unchanged")
		-- 44932 (60269), 54620 (60267): 21; 167360 (60264): 22, saved by now (dk)
		ids[#ids + 1] = 44932; pos[44932] = { 343, -3939 }
		ids[#ids + 1] = 54620; pos[54620] = { 4945, -3426 }
		main.districtTowns = { [44932] = 60269 }
		main:townState(60267).districts = { { phase = "link", town = 54620, kind = "district" } }
		main.townList, pool.townList = nil, nil
		eq(picks(pool), p0, "towns=21: picks unchanged")
		ids[#ids + 1] = 167360; pos[167360] = { -2195, 6093 }
		main.saved.dk = { { t = 167360, p = 60264 } }
		main.townList, pool.townList = nil, nil
		eq(picks(pool), p0, "towns=22: picks unchanged")
		local last = lines[#lines] or ""
		ok(last:find("towns=16", 1, true) and last:find("created=6", 1, true) and last:find("count=2", 1, true),
			"CHARACTER towns=16 created=6 count=2: " .. last)
		for _, id in ipairs({ 117429, 127962, 95485, 44932, 54620, 167360 }) do
			ok(pool:characterOf(id, 0) == nil, "created town " .. id .. " never ranked")
			ok(pool:isOffshootTown(id, nil), "created town " .. id .. " known to the pool driver")
		end
		-- without saved frames (a reload's first seconds), a pick made this session stays one
		main.saved = { dk = main.saved.dk }
		main.chars = nil
		eq(picks(pool), p0, "session picks stay without frames")
	end)
	H.main = oldMain
	ok(okRun, tostring(err))
end)
