-- Names from the map's shape (2026-10-14, NEXT_PHASE_BRIEF 45): the word budget (ot_namewords), the map survey
-- (ot_mapshape: rivers as a network, forks, mouths, upper / lower, the compass, the big lake, peaks, ranges, bays,
-- capes, narrows), cue tags in Generated names (ot_placename) and Landscape names (ot_names), clean list names, the
-- driver's survey phase and its caps.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local NW = ug_require(F.DIR .. "ot_namewords.lua")
local MS = ug_require(F.DIR .. "ot_mapshape.lua")
local PN = ug_require(F.DIR .. "ot_placename.lua")
local NM = ug_require(F.DIR .. "ot_names.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local rng = ug_require(F.DIR .. "ot_rng.lua")

local BOUNDS = { -8000, -8000, 8000, 8000 }

local function segDist(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local t = l2 > 0 and ((px - ax) * dx + (py - ay) * dy) / l2 or 0
	if t < 0 then t = 0 elseif t > 1 then t = 1 end
	local qx, qy = ax + t * dx, ay + t * dy
	return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2)
end

-- A map: a river from the west edge (x -8000) to a fork at (0, 0), two arms on to the sea in the east (x > 6500); the
-- river bed rises westward (the upper course); a round lake at (-4000, 5000) r 1500; a peak at (-4000, -5000) on a
-- ridge running east-west (the range); a bay cut into the coast at (6500, -5000).
local function shapeMap()
	local function wet(x, y)
		if x > 6500 then
			-- the bay: water reaching west of the coast line
			return true
		end
		if (x - 5800) ^ 2 + (y + 5000) ^ 2 < 900 ^ 2 then return true end
		if (x + 4000) ^ 2 + (y - 5000) ^ 2 < 1500 ^ 2 then return true end
		if segDist(x, y, -8000, 0, 0, 0) < 110 then return true end
		if segDist(x, y, 0, 0, 7000, 4000) < 110 then return true end
		if segDist(x, y, 0, 0, 7000, -2500) < 110 then return true end
		return false
	end
	local function height(x, y)
		local h = 30 + math.max(0, -x) * 0.004
		local d2 = (x + 4000) ^ 2 + (y + 5000) ^ 2
		h = h + 420 * math.exp(-d2 / (2 * 900 ^ 2))
		-- the ridge
		h = h + 220 * math.exp(-((y + 5000) ^ 2) / (2 * 500 ^ 2)) * (math.abs(x + 2000) < 4500 and 1 or 0)
		if wet(x, y) then h = h - 6 end
		return h
	end
	return T.sampler(height, wet, 0)
end

local function survey(s, o)
	local st = MS.new(BOUNDS, o)
	MS.step(st, s or shapeMap())
	return st
end

test("survey: rivers as a network (a fork, mouths, the upper course), the big lake, a peak and a range, a bay", function()
	local st = survey()
	ok(st.done, "done")
	local c = MS.counts(st)
	print(string.format("survey: rivers %d forks %d mouths %d bends %d falls %d lakes %d sea %s peaks %d ranges %d bays %d capes %d narrows %d isthmus %d units %d capped %s",
		c.rivers, c.forks, c.mouths, c.bends, c.falls, c.lakes, tostring(c.sea), c.peaks, c.ranges, c.bays, c.capes, c.narrows,
		c.isthmus, st.work, table.concat(st.capped, "+")))
	for _, k in ipairs({ "forks", "mouths", "bays", "capes" }) do
		for _, f in ipairs(st[k] or {}) do print(string.format("  %s at %.0f,%.0f n=%d arms=%s", k, f.x, f.y, f.n, tostring(f.arms))) end
	end
	eq(#st.capped, 0, "no caps hit")
	ok(c.rivers >= 1, "a long river")
	ok(c.forks >= 1, "the fork")
	ok(c.mouths >= 1, "a mouth")
	ok(c.sea, "the sea")
	ok(c.lakes >= 1, "the lake")
	ok(c.peaks >= 1 and c.ranges == 1, "a peak and a range")
	ok(c.bays >= 1, "the bay")
	-- the fork is near (0, 0)
	local f = st.forks[1]
	ok(math.abs(f.x) < 700 and math.abs(f.y) < 700, string.format("fork at %.0f,%.0f", f.x, f.y))
	-- the highest peak is the one at (-4000, -5000)
	local p = st.peaks[1]
	ok(math.abs(p.x + 4000) < 400 and math.abs(p.y + 5000) < 400, string.format("peak at %.0f,%.0f", p.x, p.y))
end)

test("town cues: a fork town, an upper-course town, a mouth town, the compass, the lake, the peak, the bay", function()
	local st = survey()
	local fork = MS.townCues(st, 300, 250)
	ok((fork.w.confluence or 0) >= 1, "fork: " .. MS.cueText(fork))
	ok(fork.river, "on the river")
	local up = MS.townCues(st, -6500, 300)
	ok((up.w.upper or 0) >= 0.6, "upper: " .. MS.cueText(up))
	eq(up.river, fork.river, "one river from the west edge to the fork")
	local mouth = MS.townCues(st, 6300, 3700)
	ok((mouth.w.mouth or 0) >= 1, "mouth: " .. MS.cueText(mouth))
	ok((mouth.w.lower or 0) >= 0.6, "lower course by the mouth: " .. MS.cueText(mouth))
	local north = MS.townCues(st, 0, 7000)
	ok((north.w.north or 0) >= 0.8 and north.dir == "north", "north: " .. MS.cueText(north))
	ok(north.w.south == nil, "not south")
	local mid = MS.townCues(st, 500, -900)
	ok((mid.w.central or 0) > 0, "central: " .. MS.cueText(mid))
	local lake = MS.townCues(st, -4000, 3300)
	ok((lake.w.biglake or 0) >= 1 and lake.ldir == "south", "lake south shore: " .. MS.cueText(lake) .. " " .. tostring(lake.ldir))
	local peak = MS.townCues(st, -3000, -4200)
	ok((peak.w.peak or 0) >= 1, "peak: " .. MS.cueText(peak))
	ok((peak.w.summit or 0) > 0 or (peak.w.range or 0) > 0, "on / by the range: " .. MS.cueText(peak))
	local bay = MS.townCues(st, 5600, -6200)
	ok((bay.w.bay or 0) >= 1, "bay: " .. MS.cueText(bay))
end)

test("survey caps: a phase over its cap is logged and skipped; a time budget slices the work; stop ends it", function()
	local old = MS.PHASE_K
	MS.PHASE_K = 0.5
	local st = survey()
	MS.PHASE_K = old
	ok(st.done, "done anyway")
	ok(#st.capped >= 1, "capped: " .. table.concat(st.capped, "+"))
	local fields = MS.surveyFields(st)
	local capped = nil
	for _, f in ipairs(fields) do if f[1] == "capped" then capped = f[2] end end
	ok(capped and capped ~= "-", "capped field " .. tostring(capped))
	-- slices: a budget of 100 units per step
	local s = shapeMap()
	local st2 = MS.new(BOUNDS)
	local steps = 0
	while not MS.step(st2, s, 100) do
		steps = steps + 1
		if steps > 100000 then break end
	end
	ok(steps > 10, "sliced over " .. steps .. " steps")
	local full = survey()
	eq(#st2.forks, #full.forks, "same result sliced")
	-- the driver's time cap
	local st3 = MS.new(BOUNDS)
	MS.step(st3, s, 500)
	MS.stop(st3, "timeout")
	ok(st3.done and table.concat(st3.capped, "+"):find("timeout"), table.concat(st3.capped, "+"))
	ok(MS.townCues(st3, 0, 0) ~= nil, "cues from a partial survey")
	-- no bounds: no survey
	local none, why = MS.new(nil)
	ok(none == nil and why == "noBounds")
end)

---------------------------------------------------------------------------
-- the word budget, rarity, clean names

local NAMES_DIR = here .. "../../.cache/game/base/content/names/"
local function loadList(path, dir)
	local chunk = loadfile(NAMES_DIR .. path .. "/" .. dir .. "/towns.lua", "t", {})
	if chunk == nil then return nil end
	local okL, list = pcall(chunk)
	if okL and type(list) == "table" then return list end
	return nil
end

local function pool(list, cls)
	local p = NM.newPool(list, cls)
	NM.classifyStep(p)
	return p
end

-- n towns spread over the 16 km map (seeded), all with the weights w
local function sameSiteTowns(n, seed, w, names)
	local towns = {}
	for i = 1, n do
		local ww = {}
		for k, v in pairs(w) do ww[k] = v end
		towns[i] = { id = 100 + i, name = names and names[i] or ("Town" .. i), x = -7000 + rng.unit(seed, "x", i) * 14000,
			y = -7000 + rng.unit(seed, "y", i) * 14000, w = ww, ranked = PN.rankOf(ww), cap = 400 + i * 37 }
	end
	return towns
end

local function within5km(res, towns, cls)
	-- no generic word twice within NEAR_M (SOFT words: half that)
	for i = 1, #res do
		for j = i + 1, #res do
			-- (twins share their anchor's base by design, NEXT_PHASE_BRIEF 53: "Laurelwood" and "South Laurelwood")
			local ti, tj = res[i].info and res[i].info.twin, res[j].info and res[j].info.twin
			local twin = ti == res[j].id or tj == res[i].id
			local d = twin and math.huge or math.sqrt((towns[i].x - towns[j].x) ^ 2 + (towns[i].y - towns[j].y) ^ 2)
			local ki = {}
			for _, k in ipairs(NW.keys(res[i].new, cls)) do ki[k] = true end
			for _, k in ipairs(NW.keys(res[j].new, cls)) do
				local lim = NW.SOFT[k] and NW.NEAR_M / NW.SOFT_K or NW.NEAR_M
				if ki[k] and d < lim then return false, string.format("%s / %s share %s at %.0f m", res[i].new, res[j].new, k, d) end
			end
		end
	end
	return true
end

test("budget: 16 towns that all read lake get at most 2 lake words (Generated names: usa, en, de, sv; never within 5 km)", function()
	for _, lang in ipairs({ "usa", "en", "de", "sv" }) do
		local towns = sameSiteTowns(16, 5, { lake = 1, mere = 0.7, forest = 0.6, edge = 0.5, plain = 0.5 })
		local res, st = PN.assign(towns, { lang = lang, seed = 77 })
		local key = ({ usa = "lake", en = "lake", de = "see", sv = "sjo" })[lang]
		local n, names = 0, {}
		for _, r in ipairs(res) do
			names[#names + 1] = r.new
			for _, k in ipairs(NW.keys(r.new, PN.CLS_OF_GEN[lang])) do if k == key then n = n + 1 end end
		end
		print(string.format("  %-4s lake words %d: %s | used %s held %s", lang, n, table.concat(names, ", "),
			NW.usedText(st.budget), NW.heldText(st.budget)))
		ok(n <= 2, lang .. ": " .. n .. " lake words")
		local okN, why = within5km(res, towns, PN.CLS_OF_GEN[lang])
		ok(okN, lang .. ": " .. tostring(why))
		for _, k in pairs(st.budget.used) do ok(k <= st.budget.cap * NW.SOFT_K, "cap") end
	end
end)

test("budget: Landscape names on the real usa list, 16 lake towns: at most 2 lake words, no Forest / Woods pile-up", function()
	local list = loadList("usa", "en")
	if list == nil then print("  (no .cache/game: skipped)") return end
	local p = pool(list, "usa")
	local start = {}
	for i = 1, 16 do start[i] = list[100 + i * 7] end
	local towns = sameSiteTowns(16, 9, { lake = 1, forest = 0.8, hill = 0.4 }, start)
	for _, t in ipairs(towns) do
		t.weights = { lake = 1, forest = 0.8, hill = 0.4 }
		t.ranked = { { "lake", 1 }, { "forest", 0.8 }, { "hill", 0.4 } }
	end
	local res, st = NM.assign(towns, p, { seed = 3 })
	local count = {}
	local names = {}
	for _, r in ipairs(res) do
		names[#names + 1] = r.new
		for _, k in ipairs(NW.keys(r.new, "usa")) do count[k] = (count[k] or 0) + 1 end
	end
	print("  " .. table.concat(names, ", "))
	print("  used " .. NW.usedText(st.budget) .. " held " .. NW.heldText(st.budget) .. " rare " .. NW.rarityText(st.rarity))
	ok((count.lake or 0) <= 2, "lake words " .. tostring(count.lake))
	ok((count.forest or 0) <= 2 and (count.woods or 0) <= 2, "forest / woods")
	local okN, why = within5km(res, towns, "usa")
	ok(okN, tostring(why))
	-- the same without the budget: the old pile-up
	local res0 = NM.assign(towns, p, { seed = 3, budget = false, rarity = false })
	local n0 = 0
	for _, r in ipairs(res0) do for _, k in ipairs(NW.keys(r.new, "usa")) do if k == "lake" then n0 = n0 + 1 end end end
	print(string.format("  without the budget: %d lake words", n0))
	ok(n0 > 2, "the fixture reproduces the pile-up")
end)

test("rarity: a tag every town reads weighs RARE_MIN, a rare one keeps its weight", function()
	local maps = {}
	for i = 1, 16 do maps[i] = { lake = 1, forest = (i <= 2) and 1 or nil, north = 1 } end
	local f = NW.rarity(maps)
	ok(math.abs(f.lake - NW.RARE_MIN) < 1e-9, "lake " .. tostring(f.lake))
	eq(f.forest, nil, "2 of 16: no factor")
	eq(f.north, nil, "compass exempt")
	local w = NW.applyRarity({ lake = 1, forest = 1 }, f)
	ok(w.lake < w.forest)
	eq(next(NW.rarity({ { lake = 1 }, { lake = 1 } })), nil, "too few towns")
end)

test("clean list names: '(city)', 'Milford city ', '(CDP)' off; Kansas City stays; industries and stops follow", function()
	eq(NW.clean("Milford city "), "Milford")
	eq(NW.clean("Salem (city)"), "Salem")
	eq(NW.clean("Oak Hill (CDP)"), "Oak Hill")
	eq(NW.clean("Kansas City"), "Kansas City")
	eq(NW.clean("Milford city"), "Milford city", "no trailing blank: the list didn't add it")
	eq(NW.clean("  Taunton "), "Taunton")
	local p = pool({ "Milford city ", "Fairview", "Georgetown", "Ashland" }, "usa")
	local towns = { { id = 1, name = "Milford city ", x = 0, y = 0, cap = 500, weights = { ford = 1 }, ranked = { { "ford", 1 } } } }
	local res, st = NM.assign(towns, p, { seed = 1 })
	eq(res[1].new, "Milford")
	eq(res[1].match, "clean")
	eq(st.clean, 1)
	local ren = NM.industryRenames({ { id = 9, name = "Milford city  Crop Farm" }, { id = 10, name = "Milford city Coal Mine" } },
		{ ["Milford city "] = "Milford" }, { "Milford city " })
	eq(#ren, 2)
	eq(ren[1].new, "Milford Crop Farm")
	eq(ren[2].new, "Milford Coal Mine")
	local c = NM.stopCandidates("fr", "station", { "Rue de la Gare ", "Rue du Champ de Foire " })
	eq(c[1], "Rue de la Gare")
end)

---------------------------------------------------------------------------
-- cues in names

local function cueTowns(st, pts, base)
	local towns = {}
	for i, p in ipairs(pts) do
		local w = {}
		for k, v in pairs(base or { plain = 0.6, field = 0.5 }) do w[k] = v end
		local cue = MS.townCues(st, p[1], p[2])
		if cue.river then w.river = 1; w.ford = 0.6; w.bridge = 0.6 end
		towns[i] = { id = 200 + i, name = "T" .. i, x = p[1], y = p[2], w = w, ranked = PN.rankOf(w), cap = 500 + i * 41,
			cue = cue, river = cue.river ~= nil }
	end
	return towns
end

local MAP_PTS = { { 300, 250 }, { -6500, 300 }, { 6300, 3700 }, { 0, 7000 }, { 500, -900 }, { -4000, 3300 },
	{ -3000, -4200 }, { 5600, -6200 }, { -7000, -7000 }, { 7000, -7200 }, { -7200, 6800 }, { 3000, 6500 },
	{ -2500, 1500 }, { 2500, -3500 }, { -6000, -2500 }, { 4000, 1500 } }

local FORKY = { fork = true }

test("a fork town gets a fork name (Generated usa / en: Forks, Junction, Three Rivers, Middle Fork ...; Landscape usa: Grand Forks ...)", function()
	local st = survey()
	local towns = cueTowns(st, MAP_PTS)
	for _, lang in ipairs({ "usa", "en", "de", "fr" }) do
		local res = PN.assign(towns, { lang = lang, seed = 11 })
		local nm = res[1].new
		local info = res[1].info or {}
		print(string.format("  %-4s fork town: %s [%s] feature %s", lang, nm, PN.partsText(info), tostring(info.feature)))
		if lang == "usa" then
			local c = NW.cuesOf(nm, "usa") or {}
			local k = {}
			for _, key in ipairs(NW.keys(nm, "usa")) do k[key] = true end
			ok(c.fork or k.fork or nm:find("Rivers") or nm:find("Junction"), "usa fork name: " .. nm)
		end
		-- a confluence part (the generic, the stem or the affix) in every language
		local feats = { info.genTag, info.specTag, info.aE and info.aE.main }
		local hit = false
		for _, f in pairs(feats) do if f == "confluence" or f == "twin" then hit = true end end
		ok(hit, lang .. " confluence part: " .. nm .. " " .. PN.partsText(info))
	end
	local list = loadList("usa", "en")
	if list == nil then return end
	local p = pool(list, "usa")
	local lt = {}
	for i, t in ipairs(towns) do
		local cue = t.cue
		lt[i] = { id = t.id, name = list[300 + i * 11], x = t.x, y = t.y, cap = t.cap, cue = cue, cues = NM.townCueTags(cue) }
		lt[i].ranked, lt[i].weights = NM.townTags({ feat = { open = 0.6, river = cue.river and 1 or 0 }, cue = cue })
	end
	local res = NM.assign(lt, p, { seed = 5 })
	print("  landscape fork town: " .. res[1].new .. " (" .. res[1].match .. ")")
	ok((NW.cuesOf(res[1].new, "usa") or {}).fork, "a list name with Fork(s) / Junction: " .. res[1].new)
end)

test("the compass: Generated names never by the map's side, only a twin's side of its anchor or the big lake's side (usa / sv / nb / nl); Landscape list names on their side", function()
	local st = survey()
	local towns = cueTowns(st, MAP_PTS)
	local words = { usa = { North = "north", South = "south", East = "east", West = "west" },
		sv = { Norra = "north", ["Södra"] = "south", ["Östra"] = "east", ["Västra"] = "west" },
		nb = { Nordre = "north", ["Søndre"] = "south", ["Østre"] = "east", Vestre = "west" },
		nl = { Noord = "north", Zuid = "south", Oost = "east", West = "west" } }
	for lang, map in pairs(words) do
		local res = PN.assign(towns, { lang = lang, seed = 21 })
		local hits = 0
		for i, r in ipairs(res) do
			for w, side in pairs(map) do
				if r.new:find("^" .. w .. "[ %-]") then
					hits = hits + 1
					-- (2026-10-14, NEXT_PHASE_BRIEF 53: "a compass word relates to the twin or to a named feature, never to the map
					-- edge": a twin on its side of its anchor, or a big-lake town's "%E %k", its side of the lake)
					local inf = r.info or {}
					local okSide = (towns[i].cue.ldir == side and inf.affix == "%E %k")
					if inf.twin then
						for j, t in ipairs(towns) do
							if t.id == inf.twin then okSide = PN.dirFrom(towns[i].x - t.x, towns[i].y - t.y) == side end
						end
					end
					ok(okSide, string.format("%s %s at %.0f,%.0f", lang, r.new, towns[i].x, towns[i].y))
				end
			end
		end
		print(string.format("  %-4s compass names %d", lang, hits))
	end
	-- landscape: a northern and a southern plain town whose names say nothing take the list's North / South names (a
	-- compass word is a preference, not a reason of its own: a fitting game name stays)
	local p = pool({ "North Platte", "South Gate", "Springfield", "Fairview", "Georgetown", "Riverside" }, "usa")
	local lt = {
		{ id = 1, name = "Georgetown", x = 0, y = 7000, cap = 500, cues = NM.townCueTags(MS.townCues(st, 0, 7000)) },
		{ id = 2, name = "Fairview", x = 0, y = -7000, cap = 500, cues = NM.townCueTags(MS.townCues(st, 0, -7000)) },
	}
	for _, t in ipairs(lt) do t.weights, t.ranked = { plain = 0.6 }, { { "plain", 0.6 } } end
	local res = NM.assign(lt, p, { seed = 2 })
	eq(res[1].new, "North Platte")
	eq(res[2].new, "South Gate")
	-- and never the other way round
	local lt2 = { { id = 1, name = "North Platte", x = 0, y = -7000, cap = 500, cues = NM.townCueTags(MS.townCues(st, 0, -7000)),
		weights = { plain = 0.6 }, ranked = { { "plain", 0.6 } } } }
	local r2 = NM.assign(lt2, p, { seed = 2 })
	ok(r2[1].new ~= "North Platte", "a North name in the south goes: " .. r2[1].new)
end)

test("a river shared along its towns: one survey river, one name, its towns carry it", function()
	local st = survey()
	-- six river towns among ten others (a river on every town would weigh nothing: rarity)
	local pts = { { -6500, 300 }, { -3500, -250 }, { -1200, 280 }, { 300, 250 }, { 3500, 2300 }, { 4000, -1100 } }
	for i = 4, #MAP_PTS do if i ~= 13 and i ~= 16 then pts[#pts + 1] = MAP_PTS[i] end end
	local towns = cueTowns(st, pts)
	for _, lang in ipairs({ "usa", "en", "de" }) do
		local res, stats = PN.assign(towns, { lang = lang, seed = 31 })
		local rv = res[1].river
		ok(rv ~= nil, lang .. " named river")
		local carry = 0
		for i = 1, 6 do eq(res[i].river, rv, lang .. " one river") end
		local stem = nil
		for _, wtr in ipairs(stats.waters) do if wtr.n == rv then stem = wtr end end
		for i = 1, 6 do
			local r = res[i]
			local rs = rv and NW.lower(rv:match("^(%S+)")) or ""
			if rs ~= "" and NW.lower(r.new):find(rs, 1, true) then carry = carry + 1 end
		end
		local names = {}
		for i = 1, 6 do names[#names + 1] = res[i].new end
		print(string.format("  %-4s river %s: %s (%d carry it)", lang, tostring(rv), table.concat(names, ", "), carry))
		ok(carry >= 1, lang .. " a town carries the river's name")
		-- (NEXT_PHASE_BRIEF 53 item 2: six towns along it, one name spends it, two at most)
		ok(carry <= 2, lang .. " the river in at most two names")
		eq(stats.rivers, 1, lang .. " one river system")
	end
end)

test("deterministic per seed: the survey, Generated and Landscape names", function()
	local a, b = survey(), survey()
	eq(#a.forks, #b.forks)
	eq(MS.cueText(MS.townCues(a, 300, 250)), MS.cueText(MS.townCues(b, 300, 250)))
	local towns = cueTowns(a, MAP_PTS)
	local r1 = PN.assign(towns, { lang = "usa", seed = 4 })
	local r2 = PN.assign(cueTowns(b, MAP_PTS), { lang = "usa", seed = 4 })
	for i = 1, #r1 do eq(r1[i].new, r2[i].new) end
	local r3 = PN.assign(towns, { lang = "usa", seed = 5 })
	local diff = 0
	for i = 1, #r1 do if r1[i].new ~= r3[i].new then diff = diff + 1 end end
	ok(diff > 0, "another seed, other names")
end)

test("derived names: a district / Works / satellite pays only for its own words; a parent's words don't block it", function()
	local B = NW.newBudget("usa", 16)
	NW.add(B, "Forest Lake", 0, 0)
	NW.add(B, "Cedar Lake", 9000, 9000)
	-- cap 2 for lake now full
	ok(not NW.check(B, "Pine Lake", -9000, -9000), "third lake word")
	ok(NW.check(B, "Forest Lake Heights", 300, 0, NW.keys("Forest Lake", "usa")), "the parent's words skipped")
	ok(not NW.check(B, "Forest Woods", 400, 0), "forest within 5 km")
	ok(NW.check(B, "Pine Bluff", 400, 0), "a new word")
	NW.remove(B, "Cedar Lake", 9000, 9000)
	ok(NW.check(B, "Pine Lake", -9000, -9000), "given back")
	-- PN.related with the budget
	local nm = PN.related("en", "Ashford", "upper", { Ashford = true }, { seed = 3, budget = B, x = 0, y = 0 })
	ok(nm == nil or NW.check(B, nm, 0, 0, NW.keys("Ashford", "en")), tostring(nm))
end)

---------------------------------------------------------------------------
-- the driver: the survey phase, cue= on NAME lines, the NAMES survey / words lines; never on a reload

local D = ug_require(F.DIR .. "ot_driver.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")

local LIST = { "Taunton", "Bilston", "Norton", "Seaford", "Whitehaven", "Newhaven", "Bournemouth", "Exmouth", "Oxford",
	"Stafford", "Stockbridge", "Tonbridge", "Wimbledon", "Haslemere", "Windermere", "Rochdale", "Ilfracombe", "Henley",
	"Bexley", "Lyndhurst", "Skegness", "Sheerness", "Radcliffe", "Clifton", "Market Deeping", "Axminster", "Wakefield",
	"Driffield", "Felton", "Potton", "Hetton", "Filton", "Surbiton", "Southsea", "Withernsea", "Huntingdon", "Abingdon",
	"Swindon", "Croydon", "Chertsey", "Northwich", "Southwold", "Eastbourne", "Westbury", "Twyford", "Lakeside Mere" }

local function fakeEngine(o)
	o = o or {}
	local E = { t = 0, logs = {}, events = {}, renames = {}, names = {} }
	local pos = {}
	for i, p in ipairs(MAP_PTS) do
		if i > (o.towns or 8) then break end
		pos[i] = p
		E.names[i] = LIST[i]
	end
	-- (the clock moves 5 us per read, so the survey's time slices end inside a tick)
	function E.nowUs() E.t = E.t + 5 return E.t end
	function E.log(l) E.logs[#E.logs + 1] = l end
	function E.global(k)
		if k == "SQOT_CONFIG" then return { nameList = "::/names/europe/europe.names", climate = "temperate" } end
	end
	function E.modParams() return o.params or { act_on = 3, debug_log = 2 }, {} end
	function E.gameTime() return 1000 end
	function E.year() return 1950 end
	function E.towns()
		local ids = {}
		for i in pairs(pos) do ids[#ids + 1] = i end
		table.sort(ids)
		return ids
	end
	function E.name(e) return E.names[e] or ("?" .. tostring(e)) end
	function E.boxCentre(t) local p = pos[t] if p then return p[1], p[2] end return nil end
	function E.townCaps(_t) return { target = 1000, actual = 900 } end
	function E.sendEvent(id, name, param) E.events[#E.events + 1] = { id = id, name = name, param = param } end
	function E.mapBounds() if o.noBounds then return nil end return BOUNDS end
	local sm = shapeMap()
	function E.sampler() return sm end
	function E.townList(_path, dir)
		if dir == "en" then return LIST end
		return { "Berlin", "Ulm" }
	end
	function E.language() return "en", "test" end
	function E.setName(e, name, cb)
		E.renames[#E.renames + 1] = { e, name }
		E.names[e] = name
		cb(true)
	end
	function E.industryNames() return {} end
	E.groups = {}
	function E.stationGroup(st) return E.groups[st] end
	function E.groupStations() return {} end
	function E.stationTown() return 1 end
	function E.townStopNames() return {} end
	function E.streetList() return { "High Street" } end
	function E.osTime() return 100 end
	return E
end

local function run(E, ticks, saved)
	local oldHead = D.HEAD
	D.HEAD = false
	local d = D.new(E)
	for _ = 1, ticks do
		E.t = E.t + 20000
		d:tick(E.t, saved)
		local done = false
		for _, l in ipairs(E.logs) do if l:find("%[SQOT%] NAMES on=true") then done = true end end
		if done then break end
	end
	D.HEAD = oldHead
	return d
end

local function findLog(E, pat)
	for _, l in ipairs(E.logs) do if l:find(pat) then return l end end
	return nil
end

test("driver: the survey runs once per new map (sliced), NAME lines carry cue=, NAMES survey / words lines; Landscape and Generated", function()
	for _, tn in ipairs({ 1, 3 }) do
		local E = fakeEngine({ params = { act_on = 3, debug_log = 2, town_names = tn } })
		run(E, 20000)
		local sv = findLog(E, "%[SQOT%] NAMES survey ")
		ok(sv and sv:find("rivers=1") and sv:find("forks=1") and sv:find("capped=%-"), tostring(sv))
		print("  " .. tostring(sv))
		local w = findLog(E, "%[SQOT%] NAMES words ")
		ok(w and w:find("used=") and w:find("held="), tostring(w))
		print("  " .. tostring(w))
		local fork = findLog(E, "%[SQOT%] NAME town=1 ")
		ok(fork and fork:find("cue=confluence:1.00"), tostring(fork))
		-- (NEXT_PHASE_BRIEF 53: shape= on every NAME line, one NAMES shapes line per map)
		ok(fork and fork:find("shape=%a+"), tostring(fork))
		local sh = findLog(E, "%[SQOT%] NAMES shapes ")
		ok(sh and sh:find("quota=") and sh:find("used=") and sh:find("frames=%d") and sh:find("whole=%d") and sh:find("twins=%d")
			and sh:find("quiet=%d"), tostring(sh))
		print("  " .. tostring(sh))
		ok(findLog(E, "%[SQOT%] NAMES on=true why=ok"), "names done")
		ok(sv:find("ms=%d+") and not sv:find("ms=0 "), "the survey's time")
		local names = {}
		for i = 1, 8 do names[#names + 1] = E.names[i] end
		print(string.format("  town_names=%d: %s", tn, table.concat(names, ", ")))
		-- a reload names nothing and surveys nothing
		local E2 = fakeEngine({ params = { act_on = 3, debug_log = 2, town_names = tn } })
		run(E2, 50, { v = 1, frames = {}, nm = 1 })
		ok(findLog(E2, "NAMES on=false why=done"))
		ok(findLog(E2, "NAMES survey") == nil, "no survey on a reload")
		eq(#E2.renames, 0)
	end
	-- (NEXT_PHASE_BRIEF 61: the industry near a town on its NAME line, ind=; the NAMES shapes line's evoc= charCue=
	-- indCue=)
	local E4 = fakeEngine({ params = { act_on = 3, debug_log = 2, town_names = 3 } })
	local p2 = { E4.boxCentre(2) }
	function E4.industries() return { { p2[1] + 400, p2[2], file = "industry/oil_well/oil_well.con" } } end
	run(E4, 20000)
	local l2 = findLog(E4, "%[SQOT%] NAME town=2 ")
	ok(l2 and l2:find("ind=oil:400") and l2:find("evoc="), tostring(l2))
	local sh4 = findLog(E4, "%[SQOT%] NAMES shapes ")
	ok(sh4 and sh4:find("evoc=%d") and sh4:find("charCue=%d+/%d+") and sh4:find("indCue=%d") and sh4:find("rules=s61"), tostring(sh4))
	print("  " .. tostring(sh4))
	-- no bounds: no survey, names as before
	local E3 = fakeEngine({ noBounds = true, params = { act_on = 3, debug_log = 2, town_names = 1 } })
	run(E3, 3000)
	ok(findLog(E3, "NAMES survey on=false why=noBounds"), "no bounds line")
	ok(findLog(E3, "%[SQOT%] NAMES on=true why=ok"))
end)

test("driver: the survey's time cap ends it (capped=timeout) and names go on", function()
	local old = D.NAMES_SHAPE_MAX_S
	D.NAMES_SHAPE_MAX_S = 0.05
	local E = fakeEngine({ params = { act_on = 3, debug_log = 2, town_names = 1 } })
	run(E, 3000)
	D.NAMES_SHAPE_MAX_S = old
	local sv = findLog(E, "%[SQOT%] NAMES survey ")
	ok(sv and sv:find("capped=[%w%+:]*timeout"), tostring(sv))
	ok(findLog(E, "%[SQOT%] NAMES on=true why=ok"), "names done")
end)

test("cost (printed): the survey per 1000 units, Landscape and Generated assignments on 16 / 100 towns", function()
	local s = shapeMap()
	local st = MS.new(BOUNDS)
	local t0 = os.clock()
	MS.step(st, s)
	local surveyMs = (os.clock() - t0) * 1000
	print(string.format("  survey %d units %.0f ms (%.1f us / unit, sampler included)", st.work, surveyMs, surveyMs * 1000 / st.work))
	local list = loadList("usa", "en")
	local p = list and pool(list, "usa") or pool({ "Fairview", "Riverside", "Georgetown", "Lakewood", "Ashland" }, "usa")
	for _, n in ipairs({ 16, 100 }) do
		local towns = {}
		for i = 1, n do
			local x, y = -7500 + rng.unit(1, "x", i) * 15000, -7500 + rng.unit(1, "y", i) * 15000
			local cue = MS.townCues(st, x, y)
			local t = { id = i, name = p.names[(i * 13) % #p.names + 1], x = x, y = y, cap = 500, cue = cue, cues = NM.townCueTags(cue) }
			t.ranked, t.weights = NM.townTags({ feat = { open = 0.5, coast = (i % 4 == 0) and 0.6 or 0, river = cue.river and 1 or 0,
				body = (i % 5 == 0) and "lake" or nil }, forestShare = (i % 3) * 0.2, cue = cue })
			towns[i] = t
		end
		local t1 = os.clock()
		NM.assign(towns, p, { seed = 1 })
		local lms = (os.clock() - t1) * 1000
		for _, t in ipairs(towns) do t.w = PN.withCues(t.weights, nil) end
		local t2 = os.clock()
		PN.assign(towns, { lang = "usa", seed = 1 })
		local gms = (os.clock() - t2) * 1000
		local t3 = os.clock()
		PN.assign(towns, { lang = "usa", seed = 1, budget = false })
		local g0 = (os.clock() - t3) * 1000
		local t4 = os.clock()
		PN.assign(towns, { lang = "usa", seed = 1, shapes = false })
		local g1 = (os.clock() - t4) * 1000
		print(string.format("  %3d towns: landscape %.0f ms, generated %.0f ms (without the budget %.0f ms, without the shape plan %.0f ms)",
			n, lms, gms, g0, g1))
	end
end)

-- run 2026-10-14_0710_sqot (seed a, USA list, Landscape names): the 16 towns' tags and positions from its NAME / site
-- lines; 9 of 16 got Lake / Forest names
local RUN0710 = {
	{ 60255, "Marysville", "lake:1.00,forest:0.60,hill:0.57", false, 397, -2012, -2748 },
	{ 60256, "Midland", "river:1.00,forest:0.85,ford:0.80,bridge:0.80,market:0.80", false, 907, -1739, 54 },
	{ 60257, "Sioux Falls", "lake:1.00,valley:0.60,headland:0.50,forest:0.36", false, 560, -5500, -5320 },
	{ 60258, "Kingsport", "lake:1.00,forest:0.77,headland:0.50,hill:0.35", false, 392, -7298, 4910 },
	{ 60259, "Fair Oaks", "lake:1.00,forest:0.67,valley:0.60,plain:0.46", false, 258, 2804, 144 },
	{ 60260, "Frankfort", "plain:0.66,valley:0.60,forest:0.54", false, 535, 364, 2640 },
	{ 60261, "Dover", "lake:1.00,forest:0.48,hill:0.39", false, 357, -4011, 2577 },
	{ 60262, "Mustang", "market:0.80,plain:0.67,forest:0.65,valley:0.60", true, 709, 1436, 6640 },
	{ 60263, "Columbus", "coast:1.00,island:1.00,headland:0.90,hill:0.67,forest:0.44", false, 644, 4340, 3204 },
	{ 60264, "Chicago", "forest:0.64,hill:0.35", false, 316, -2446, 7296 },
	{ 60265, "Johnston", "valley:0.60,forest:0.60,plain:0.56", false, 284, 4238, -6403 },
	{ 60266, "Maryland Heights", "forest:0.64,valley:0.60", false, 257, 7097, -651 },
	{ 60267, "Christiansburg", "lake:1.00,forest:0.72,valley:0.60", false, 446, 5474, -3254 },
	{ 60268, "Burlington", "forest:0.56,hill:0.36", false, 340, 5006, 6344 },
	{ 60269, "Bloomington", "forest:0.91,valley:0.60,plain:0.38", false, 469, 1737, -3497 },
	{ 60270, "Cedar Hill", "forest:1.00,headland:0.90,hill:0.57", true, 418, 695, -6755 },
}

test("replay of run 0710 (USA list, Landscape names): Lake / Forest at most 2 each, none twice within 5 km (printed)", function()
	local list = loadList("usa", "en")
	if list == nil then print("  (no .cache/game: skipped)") return end
	local p = pool(list, "usa")
	-- a flat dry map of the run's size: only the compass cues
	local st = MS.new({ -8192, -8192, 8192, 8192 })
	MS.step(st, T.sampler(function() return 50 end, function() return false end, 0))
	local towns = {}
	for i, e in ipairs(RUN0710) do
		local w, ranked = {}, {}
		for tag, v in e[3]:gmatch("(%a+):([%d%.]+)") do w[tag] = tonumber(v); ranked[#ranked + 1] = { tag, tonumber(v) } end
		local cue = MS.townCues(st, e[6], e[7])
		towns[i] = { id = e[1], name = e[2], x = e[6], y = e[7], cap = e[5], character = e[4], weights = w, ranked = ranked,
			cue = cue, cues = NM.townCueTags(cue) }
	end
	local res, stats = NM.assign(towns, p, { seed = 7 })
	local count, lines = {}, {}
	for i, r in ipairs(res) do
		for _, k in ipairs(NW.keys(r.new, "usa")) do count[k] = (count[k] or 0) + 1 end
		lines[#lines + 1] = string.format("%s -> %s (%s)", RUN0710[i][2], r.new, r.match)
	end
	print("  " .. table.concat(lines, "; "))
	print("  used " .. NW.usedText(stats.budget) .. " | rare " .. NW.rarityText(stats.rarity))
	ok((count.lake or 0) <= 2 and (count.forest or 0) <= 2, "lake / forest words")
	local okN, why = within5km(res, towns, "usa")
	ok(okN, tostring(why))
end)
