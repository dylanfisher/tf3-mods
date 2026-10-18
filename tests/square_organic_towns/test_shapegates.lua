-- Name shapes chosen per map: the review's Q7 hard gates (2026-10-14, NEXT_PHASE_BRIEF 53 Part A item 4;
-- names/review/REVIEW_ANSWERS.md) over many seeds x site presets x climates, on synthetic maps of 16-24 towns:
--   * frame and whole-name shares within the language's quota + 5 points;
--   * words per name: en at most 1.4 on average, usa 1.8, never 4 or more;
--   * a named feature (river, lake, peak, bay) in at most 2 town names;
--   * a stem's root at most once per 12 towns (twins excepted);
--   * one dialect per name, or an allowed hybrid near a dialect border;
--   * at most 2 feature ideas per name;
--   * a compass word only on the right side of its twin (never the map's side);
--   * quiet names (no terrain word): since NEXT_PHASE_BRIEF 60 about 10 % (gated at QUIET_SHARE + 8 points; the review's
--     35 % is the s53 rules'); the shares are those of the map's rules (PN.quota60), the words PN.WORDS60 + 0.1.
-- Part B (2026-10-14, NEXT_PHASE_BRIEF 53 items 5-6): the climate's shape table (its shares and words per name), a
-- tropical map has no -thorpe / -by / -ham, a civic name (Junction / Station / Center) never sits on a natural confluence
-- nor an old town, the settlement layers follow size and site, created towns follow the game year, a district's compass
-- word relates to its parent and sits on its side, leftover feature claims go to districts and stops, the character
-- hook. NAME_SAMPLES=1 prints EU / US x the four climates (16 towns, districts, Works) with the shape counts.
-- Quick mode runs 4 seeds, TEST_FULL 24. SHAPE_DUMP=1 prints every map's names and its NAMES shapes line.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local PN = ug_require(F.DIR .. "ot_placename.lua")
local NW = ug_require(F.DIR .. "ot_namewords.lua")
local CL = ug_require(F.DIR .. "ot_climate.lua")
local rng = ug_require(F.DIR .. "ot_rng.lua")

local FULL = os.getenv("TEST_FULL") ~= nil
local SEEDS = {}
for s = 1, FULL and 24 or 4 do SEEDS[#SEEDS + 1] = s * 37 + 1 end

local NM = loadfile(here .. "namemaps.lua", "t", _ENV)()
local SITES, PRESETS, PRESET_ORDER, CLIMATES = NM.SITES, NM.PRESETS, NM.PRESET_ORDER, NM.CLIMATES
local tags, makeMap = NM.tags, NM.makeMap
local function U(seed, ...) return rng.unit(seed, ...) end

local function wordsOf(name)
	local out = {}
	for w in (" " .. PN.lowerAll(name) .. " "):gsub("[%-]", " "):gmatch("%S+") do out[#out + 1] = w end
	return out
end

local function hasPhrase(name, phrase)
	local n = " " .. table.concat(wordsOf(name), " ") .. " "
	return n:find(" " .. phrase .. " ", 1, true) ~= nil
end

-- the gates over one finished map; returns its numbers { tokens, quiet, frames, whole }
local function gates(lang, towns, res, st, label, climate)
	local L = PN.lang(lang)
	local N = #towns
	-- (NEXT_PHASE_BRIEF 60: the shares the map's rules hand out, PN.quota60 of the climate's table)
	local q = st.ctx.quota or PN.climateOf(L, climate).quota
	local shapes, tok, quiet = {}, 0, 0
	for _, r in ipairs(res) do
		local inf = r.info or {}
		local sh = inf.shape or "plain"
		shapes[sh] = (shapes[sh] or 0) + 1
		local k = PN.tokens(r.new)
		tok = tok + k
		ok(k <= 3, string.format("%s %s: %d words: %s", label, lang, k, r.new))
		-- (a saint name is the Romance lists' flavor, not a quiet name: NEXT_PHASE_BRIEF 60)
		if inf.quiet and sh ~= "saint" then quiet = quiet + 1 end
		-- (Part B: no joined Saxon / Norse forms on a tropical map; a civic name only on a late town, never a confluence)
		if climate == "tropical" and (lang == "en") then
			local g = inf.gE and PN.lowerAll(inf.gE.text or "") or ""
			ok(g ~= "thorpe" and g ~= "by" and g ~= "ham", string.format("%s tropical -%s: %s", label, g, r.new))
		end
		local civic = sh ~= "character" and (sh == "civic" or (inf.gE and inf.gE.flags.v) or (inf.aE and inf.aE.flags.v))
		if civic then
			local me
			for _, t in ipairs(towns) do if t.id == r.id then me = t end end
			local cw = PN.withCues(me.w, me.cue)
			ok((cw.confluence or 0) < PN.CIVIC_CONFLUENCE, label .. " civic name on a confluence: " .. r.new)
			ok(inf.layer == "late", label .. " civic name on a " .. tostring(inf.layer) .. " town: " .. r.new)
		end
		-- ideas
		local nIdeas = PN.ideas(inf.sE, inf.gE, inf.aE, inf.twin ~= nil)
		ok(nIdeas <= 2, string.format("%s %s: %d ideas: %s", label, lang, nIdeas, r.new))
		-- one dialect, or a hybrid near a border
		if inf.sE and inf.gE then
			local a, b = inf.sE.grp, inf.gE.grp
			ok(PN.compatible(L, a, b), string.format("%s %s dialect mix: %s (@%s + @%s)", label, lang, r.new, tostring(a), tostring(b)))
			if a and b and a ~= b and not (L.shared[a] or L.shared[b]) then
				ok(inf.hybrid == true, string.format("%s %s hybrid away from a border: %s (@%s + @%s)", label, lang, r.new, a, b))
			end
		end
		-- the compass: a twin's, on its side of the anchor; never the map's side (%D)
		local a = inf.aE
		if a then
			ok(not a.mapDir, label .. " a map-side compass form: " .. r.new)
			if a.qkind == "compass" then
				ok(inf.twin ~= nil, label .. " compass word without a twin: " .. r.new)
				if inf.twin then
					local an, me
					for i, t in ipairs(towns) do
						if t.id == inf.twin then an = t end
						if t.id == r.id then me = t end
					end
					ok(an and me and PN.dirFrom(me.x - an.x, me.y - an.y) == a.qdir,
						string.format("%s compass %s on the wrong side of its twin: %s", label, tostring(a.qdir), r.new))
				end
			end
			if a.shape == "qualifier" and (a.qkind == "small" or a.qkind == "big") and sh ~= "character" then
				ok(inf.twin ~= nil, label .. " size qualifier without a twin: " .. r.new)
			end
		end
	end
	-- frame / whole shares
	for _, sh in ipairs({ "frame", "whole" }) do
		local share = (shapes[sh] or 0) / N
		ok(share <= (q[sh] or 0) + 0.05 + 1e-9, string.format("%s %s %s share %.2f > %.2f + 0.05", label, lang, sh, share, q[sh] or 0))
	end
	-- named features in at most 2 town names
	local feats = {}
	for stem in pairs(st.ctx.featWords or {}) do feats[stem] = { stem } end
	for _, wt in ipairs(st.waters or {}) do
		for stem, list in pairs(feats) do
			if PN.lowerAll(wt.n):sub(1, #stem) == stem then list[#list + 1] = PN.lowerAll(wt.n) end
		end
	end
	for stem, list in pairs(feats) do
		local n = 0
		for _, r in ipairs(res) do
			local inf = r.info or {}
			local se = inf.sE and PN.lowerAll(inf.sE.k or inf.sE.text or "") or ""
			local hit = se == stem
			for _, ph in ipairs(list) do if not hit and hasPhrase(r.new, ph) then hit = true end end
			if hit then n = n + 1 end
		end
		ok(n <= 2, string.format("%s %s feature %s in %d names", label, lang, stem, n))
	end
	-- roots once per 12 towns (twins and frames on a base already on the map excepted)
	if not L.script then
		local cap = math.max(1, math.ceil(N / 12))
		local roots = {}
		for _, r in ipairs(res) do
			if r.info and r.info.twin == nil and r.info.reuse == nil then
				for _, k in ipairs(PN.extraKeys(L, r.new, st.ctx.featWords)) do
					if k:sub(1, 1) == "^" then roots[k] = (roots[k] or 0) + 1 end
				end
			end
		end
		for k, n in pairs(roots) do
			ok(n <= cap or (st.budget.over or 0) > 0, string.format("%s %s root %s x%d (cap %d)", label, lang, k, n, cap))
		end
	end
	return { tokens = tok / N, quiet = quiet / N, frames = (shapes.frame or 0) / N, whole = (shapes.whole or 0) / N, shapes = shapes }
end

local function sweep(langs, climates, nTowns)
	local stats = {}
	for _, lang in ipairs(langs) do
		local agg = { n = 0, tokens = 0, quiet = 0, twins = 0, shapes = {} }
		for _, climate in ipairs(climates) do
			for pi, preset in ipairs(PRESET_ORDER) do
				for si, seed in ipairs(SEEDS) do
					local n = nTowns[(si + pi) % #nTowns + 1]
					local towns = makeMap(seed + pi * 1000, preset, n, climate)
					local res, st = PN.assign(towns, { lang = lang, seed = seed, climate = climate })
					local label = string.format("%s/%s/%d/%d", preset, climate, seed, #towns)
					if os.getenv("SHAPE_DUMP") then
						local nm = {}
						for _, r in ipairs(res) do nm[#nm + 1] = r.new .. "[" .. tostring(r.info and r.info.shape) .. "]" end
						print(label .. " " .. lang .. ": " .. table.concat(nm, ", "))
						local f = {}
						for _, e in ipairs(PN.shapeFields(st)) do f[#f + 1] = e[1] .. "=" .. tostring(e[2]) end
						print("    NAMES shapes " .. table.concat(f, " "))
					end
					local g = gates(lang, towns, res, st, label, climate)
					agg.n = agg.n + 1
					agg.tokens = agg.tokens + g.tokens
					agg.quiet = agg.quiet + g.quiet
					agg.twins = agg.twins + (st.shapes.twins or 0)
					for k, v in pairs(g.shapes) do agg.shapes[k] = (agg.shapes[k] or 0) + v end
					-- (review Q7: en 1.4, usa 1.8; a climate with more separate-word names, Port X / Fort X, its words + 0.05;
					-- NEXT_PHASE_BRIEF 60: the multi-word names raise them to PN.WORDS60 + 0.1)
					local cw = PN.climateOf(PN.lang(lang), climate).words or 1
					if lang == "en" then
						local lim = math.max(1.4, cw + 0.05, PN.WORDS60.en + 0.1)
						ok(g.tokens <= lim + 1e-9, string.format("%s en words %.2f > %.2f", label, g.tokens, lim))
					end
					if lang == "usa" then
						local lim = math.max(1.8, cw + 0.15, PN.WORDS60.usa + 0.15)
						ok(g.tokens <= lim + 1e-9, string.format("%s usa words %.2f > %.2f", label, g.tokens, lim))
					end
				end
			end
		end
		stats[lang] = agg
	end
	return stats
end

local function report(stats, langs)
	for _, lang in ipairs(langs) do
		local a = stats[lang]
		local parts = {}
		for _, sh in ipairs(PN.SHAPES) do if (a.shapes[sh] or 0) > 0 then parts[#parts + 1] = sh .. ":" .. a.shapes[sh] end end
		print(string.format("  %-4s %d maps: words %.2f, quiet %.0f %%, twins %d; %s", lang, a.n, a.tokens / a.n,
			100 * a.quiet / a.n, a.twins, table.concat(parts, ",")))
		-- (NEXT_PHASE_BRIEF 60: quiet names rare, about 10 %, instead of the review's 35 %)
		ok(a.quiet / a.n <= PN.QUIET_SHARE + 0.08, string.format("%s quiet share %.2f (target %.2f)", lang, a.quiet / a.n, PN.QUIET_SHARE))
	end
end

-- (one test per language and climate: each stays under ~8 s with TEST_FULL)
for _, lang in ipairs({ "en", "usa" }) do
	for _, climate in ipairs(CLIMATES) do
		test("Q7 gates, " .. lang .. " " .. climate .. ": seeds x 4 presets (shares, words, features, roots, dialects, ideas, compass, quiet)", function()
			report(sweep({ lang }, { climate }, { 16, 20, 24 }), { lang })
		end)
	end
end

for _, lang in ipairs({ "de", "fr", "it", "es", "pt", "nl", "sv", "nb", "ja", "ja_r" }) do
	test("Q7 gates, " .. lang .. ": seeds x 4 presets, temperate and tropical", function()
		report(sweep({ lang }, { "temperate", "tropical" }, { 16, 24 }), { lang })
	end)
end

test("dialect areas: 2-3 per map along the border; about 80 % of names in their area's own groups (en, usa, de)", function()
	for _, lang in ipairs({ "en", "usa", "de" }) do
		local own, total, areaN = 0, 0, {}
		for pi, preset in ipairs(PRESET_ORDER) do
			for _, seed in ipairs(SEEDS) do
				local towns = makeMap(seed + pi * 1000, preset, 20, "temperate")
				local res, st = PN.assign(towns, { lang = lang, seed = seed, climate = "temperate" })
				local L = PN.lang(lang)
				local names = {}
				for i, r in ipairs(res) do
					local d = PN.dialectAt(st.ctx, towns[i].x, towns[i].y)
					ok(d ~= nil, lang .. " every town in an area")
					if d then
						names[d.name] = true
						local inf = r.info or {}
						local grps = {}
						if inf.sE and inf.sE.grp then grps[#grps + 1] = inf.sE.grp end
						if inf.gE and inf.gE.grp then grps[#grps + 1] = inf.gE.grp end
						-- (a name of ungrouped parts fits every area: it counts as the area's own)
						total = total + 1
						if #grps == 0 then own = own + 1 end
						if #grps > 0 then
							local mine = true
							for _, g in ipairs(grps) do
								if not (g == d.name or (L.shared[g] and PN.compatible(L, d.name, g))) then mine = false end
							end
							if mine then own = own + 1 elseif os.getenv("SHAPE_DUMP") and lang == "en" then
								print(string.format("    foreign %s in %s (%s): %s @%s + %s @%s", r.new, d.name, d.role, tostring(inf.spec),
									tostring(inf.sE and inf.sE.grp), tostring(inf.gen), tostring(inf.gE and inf.gE.grp)))
							end
						end
					end
				end
				local n = 0
				for _ in pairs(names) do n = n + 1 end
				ok(n >= 1 and n <= 3, lang .. " areas on a map: " .. n)
				areaN[n] = (areaN[n] or 0) + 1
			end
		end
		print(string.format("  %-4s own-dialect names %.0f %% of %d; maps with 1/2/3 areas: %d/%d/%d", lang,
			100 * own / math.max(1, total), total, areaN[1] or 0, areaN[2] or 0, areaN[3] or 0))
		ok(own / math.max(1, total) >= 0.7, lang .. " own-dialect share " .. own / math.max(1, total))
	end
end)

test("twins: a close pair shares a base; Upper / Lower by the river's course, Little by size, the compass by position", function()
	-- two towns 2.5 km apart on one river (the twin upstream), a big and a small town, two equal towns side by side
	local function base(i, x, y, w, cap, cue)
		return { id = i, name = "T" .. i, x = x, y = y, w = tags(w), cap = cap, cue = cue or { w = {} }, river = false }
	end
	local function run(towns, lang)
		-- (the qualifier count: all of them for the test)
		local L = PN.lang(lang)
		local old = L.quota.qualifier
		L.quota.qualifier = 1
		local res, st = PN.assign(towns, { lang = lang, seed = 5 })
		L.quota.qualifier = old
		return res, st
	end
	local towns = {
		base(1, 0, 0, "river:1,meadow:.6,plain:.5", 1500, { w = { lower = 0.5 }, river = 1, flow = 0.3 }),
		base(2, 0, 2500, "river:1,meadow:.6,plain:.5", 600, { w = {}, river = 1, flow = 0.55 }),
		base(3, 20000, 0, "plain:.9,field:.8", 2000), base(4, 21500, 0, "plain:.9,field:.8", 300),
		base(5, 40000, 0, "plain:.9,field:.8", 800), base(6, 40000, -2000, "plain:.9,field:.8", 700),
	}
	towns[1].river, towns[2].river = true, true
	local res, st = run(towns, "en")
	local by = {}
	for _, r in ipairs(res) do by[r.id] = r end
	print(string.format("  en: %s / %s; %s / %s; %s / %s", by[1].new, by[2].new, by[3].new, by[4].new, by[5].new, by[6].new))
	eq(st.shapes.twins, 3, "three twins")
	ok(by[2].new:find("^Upper ") and by[2].new:sub(7) == by[1].new, "upstream: Upper + its anchor's name: " .. by[2].new)
	ok(by[4].new:find("^Little "), "the small one: Little: " .. by[4].new)
	ok(by[6].new:find("^South "), "the one to the south: South: " .. by[6].new)
	-- the twin pays for no word its anchor has (the root is shared)
	ok((st.budget.over or 0) == 0, "within the budget")
	-- German: Ober- / Unter- joined, Klein by size
	res = run(towns, "de")
	by = {}
	for _, r in ipairs(res) do by[r.id] = r end
	print(string.format("  de: %s / %s; %s / %s; %s / %s", by[1].new, by[2].new, by[3].new, by[4].new, by[5].new, by[6].new))
	ok(by[2].new:find("^Ober") or by[2].new:find("^Hohen"), "de upstream: Ober-: " .. by[2].new)
	ok(by[4].new:find("^Klein "), "de small: Klein: " .. by[4].new)
end)

test("twin search capped: only the first TWIN_MAX_TOWNS towns pair up (the pairs' square stays bounded)", function()
	local towns = {}
	for i = 1, 8 do
		towns[i] = { id = i, name = "T" .. i, x = (i % 2) * 1500 + math.floor((i - 1) / 2) * 20000, y = 0, w = tags("plain:.9,field:.8"),
			cap = (i % 2 == 0) and 2000 or 300 }
	end
	local L = PN.lang("en")
	local oldQ, oldCap = L.quota.qualifier, PN.TWIN_MAX_TOWNS
	L.quota.qualifier, PN.TWIN_MAX_TOWNS = 1, 4
	local okRun, err = pcall(function()
		local res, st = PN.assign(towns, { lang = "en", seed = 5 })
		ok(st.shapes.twins >= 1, "a twin among the first four: " .. st.shapes.twins)
		for i = 5, 8 do ok(res[i].info and res[i].info.twin == nil, "no twin past the cap: " .. res[i].new) end
	end)
	L.quota.qualifier, PN.TWIN_MAX_TOWNS = oldQ, oldCap
	ok(okRun, tostring(err))
end)

test("the named-feature budget: one town name per ~6 towns along a river, 2 at most, the strongest claim (the mouth) first", function()
	-- 12 towns along one river: the mouth town, a confluence, ten plain river towns
	local towns = {}
	for i = 1, 12 do
		local w = "river:1,bridge:.6,ford:.6,meadow:.6"
		local cw = {}
		if i == 1 then w = w .. ",mouth:1,coast:.8"; cw.mouth = 1 end
		if i == 6 then w = w .. ",confluence:1"; cw.confluence = 1 end
		towns[i] = { id = i, name = "T" .. i, x = 0, y = i * 2200, w = tags(w), cap = 500 + i * 10,
			cue = { w = cw, river = 1, flow = i / 12 }, river = true }
	end
	for _, lang in ipairs({ "en", "usa", "de" }) do
		local res, st = PN.assign(towns, { lang = lang, seed = 3, sat = false })
		local stem
		for s in pairs(st.ctx.riverNames or {}) do stem = PN.lowerAll(s) end
		local n, names = 0, {}
		for _, r in ipairs(res) do
			names[#names + 1] = r.new
			if r.new and PN.lowerAll(r.new):find(stem, 1, true) then n = n + 1 end
		end
		print(string.format("  %s (river %s): %s", lang, stem, table.concat(names, ", ")))
		ok(n >= 1 and n <= 2, lang .. " river in " .. n .. " names")
	end
	local grants = PN.featureGrants({}, towns, (function() local w = {} for i, t in ipairs(towns) do w[i] = PN.withCues(t.w, t.cue) end return w end)(),
		{ { kind = "river", members = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 } } })
	ok(grants[1] and grants[1].river, "the mouth town spends it first")
	ok(grants[6] and grants[6].river, "then the only confluence")
	local n = 0
	for _ in pairs(grants) do n = n + 1 end
	eq(n, 2, "12 towns along it: 2 grants")
end)

test("shape plan: counts from the quota (never above share + 5 points), whole names to the strongest cues, plain the rest", function()
	local towns = makeMap(11, "valley", 16, "temperate")
	for _, lang in ipairs({ "en", "usa", "fr" }) do
		local res, st = PN.assign(towns, { lang = lang, seed = 11 })
		local L = PN.lang(lang)
		for sh, n in pairs(st.shapes.quota) do
			ok(n <= math.floor(16 * ((st.ctx.quota[sh] or 0) + 0.05)), lang .. " count " .. sh .. " " .. n)
		end
		local f = PN.shapeFields(st)
		local parts = {}
		for _, e in ipairs(f) do parts[#parts + 1] = e[1] .. "=" .. tostring(e[2]) end
		print("  " .. lang .. " NAMES shapes " .. table.concat(parts, " "))
		-- (NEXT_PHASE_BRIEF 61: the evocative names are plain descriptions of the site too)
		local plain = (st.shapes.used.plain or 0) + (st.shapes.used.separate or 0) + (st.shapes.used.personal or 0)
			+ (st.shapes.used.evoc or 0)
		ok(plain >= 8, lang .. " plain names the majority: " .. plain)
	end
end)

test("tokens and ideas: the counts the gates use", function()
	eq(PN.tokens("Sutton-on-Arun"), 2)
	eq(PN.tokens("Stratford-upon-Avon"), 2)
	eq(PN.tokens("North Antelope Woods"), 3)
	eq(PN.tokens("Ashford"), 1)
	eq(PN.tokens("Neustadt an der Lahn"), 2)
	local L = PN.lang("en")
	local function e(list, text) for _, x in ipairs(list) do if (x.k or x.text) == text then return x end end end
	local myt, mere, vale = e(L.specs, "Myt"), e(L.gens, "mere"), e(L.affixes, "%s-in-the-Vale")
	eq(PN.ideas(myt, mere, vale), 3, "Mytmere-in-the-Vale: three ideas")
	local sut, ton, on = e(L.specs, "Sut"), e(L.gens, "ton"), e(L.affixes, "%s-on-%r")
	eq(PN.ideas(sut, ton, on), 1, "Sutton-on-Arun: one")
	eq(PN.ideas(sut, ton, nil), 0, "Sutton: quiet")
end)

---------------------------------------------------------------------------
-- Part B (2026-10-14, NEXT_PHASE_BRIEF 53 items 5-6): layers, climate tables, created towns, leftover claims, the
-- character hook

local OFF = ug_require(F.DIR .. "ot_offname.lua")
local SN = ug_require(F.DIR .. "ot_stopname.lua")

test("settlement layers: by size and site (crossings, mouths, markets oldest); no late town outranks an old one", function()
	for pi, preset in ipairs(PRESET_ORDER) do
		for _, seed in ipairs(SEEDS) do
			local towns = makeMap(seed + pi * 1000, preset, 20, "temperate")
			local ws = {}
			for i, t in ipairs(towns) do ws[i] = PN.withCues(t.w, t.cue) end
			local lay, n = PN.layers(towns, ws, 1850)
			eq(n.old, 7, preset .. " old: 35 % of 20")
			eq(n.late, 5, preset .. " late: 25 % of 20")
			local maxCap, big = 0, nil
			for i, t in ipairs(towns) do if t.cap > maxCap then maxCap, big = t.cap, i end end
			eq(lay[big], "old", "the biggest town is old")
			local info = {}
			for i, t in ipairs(towns) do
				local _, site, size = PN.oldness(t, ws[i], maxCap)
				info[i] = { site = site, size = size, ch = t.character and 1 or 0 }
			end
			for a = 1, #towns do
				if lay[a] == "late" then
					for b = 1, #towns do
						if lay[b] == "old" then
							local A, B = info[a], info[b]
							local dom = A.size >= B.size and A.site >= B.site and A.ch >= B.ch and (A.size > B.size or A.site > B.site or A.ch > B.ch)
							ok(not dom, string.format("%s/%d: late %s (size %.2f site %.2f) outranks old %s (size %.2f site %.2f)", preset, seed,
								towns[a].name, A.size, A.site, towns[b].name, B.size, B.site))
						end
					end
				end
			end
		end
	end
	-- (a map from 1900 on: more late towns)
	local towns = makeMap(77, "valley", 20, "temperate")
	local ws = {}
	for i, t in ipairs(towns) do ws[i] = PN.withCues(t.w, t.cue) end
	local _, n = PN.layers(towns, ws, 1950)
	eq(n.late, 6, "late share from 1900: 30 %")
	eq(PN.yearLayer(1890), "mid", "a created town before 1945: middle")
	eq(PN.yearLayer(1960), "late", "from 1945: late")
end)

test("layers in the names: old towns take the old forms (-ham / -ton / -by), late towns the late ones (en, usa)", function()
	for _, lang in ipairs({ "en", "usa" }) do
		local L = PN.lang(lang)
		local cnt = { old = { 0, 0 }, mid = { 0, 0 }, late = { 0, 0 } }
		for pi, preset in ipairs(PRESET_ORDER) do
			for _, seed in ipairs(SEEDS) do
				local towns = makeMap(seed + pi * 1000, preset, 20, "temperate")
				local res = PN.assign(towns, { lang = lang, seed = seed, climate = "temperate" })
				for _, r in ipairs(res) do
					local inf = r.info or {}
					if inf.layer and inf.gE then
						local c = cnt[inf.layer]
						c[2] = c[2] + 1
						if PN.layerAdj(L, inf.gE, inf.layer) > 0 then c[1] = c[1] + 1 end
					end
				end
			end
		end
		local function sh(k) return cnt[k][1] / math.max(1, cnt[k][2]) end
		print(string.format("  %-4s own-layer generics: old %.0f %% of %d, mid %.0f %% of %d, late %.0f %% of %d", lang,
			100 * sh("old"), cnt.old[2], 100 * sh("mid"), cnt.mid[2], 100 * sh("late"), cnt.late[2]))
		ok(sh("old") >= 0.4, lang .. " old towns mostly in the old forms: " .. sh("old"))
	end
end)

test("climate tables: tropical Port / Bay / -town, dry water and Spanish names, subarctic Fort / Landing / Glen; sv / nb fjords", function()
	local function names(lang, climate, n)
		local out, shapes = {}, {}
		for pi, preset in ipairs(PRESET_ORDER) do
			for si = 1, n do
				local seed = SEEDS[(si - 1) % #SEEDS + 1] + si * 101
				local towns = makeMap(seed + pi * 1000, preset, 20, climate)
				local res = PN.assign(towns, { lang = lang, seed = seed, climate = climate })
				for _, r in ipairs(res) do
					out[#out + 1] = r.new
					local s = r.info and r.info.shape or "plain"
					shapes[s] = (shapes[s] or 0) + 1
				end
			end
		end
		return out, shapes
	end
	local function share(list, pats)
		local n = 0
		for _, nm in ipairs(list) do
			for _, p in ipairs(pats) do if nm:find(p) then n = n + 1 break end end
		end
		return n / math.max(1, #list), n
	end
	local per = FULL and 4 or 2
	local trop, tsh = names("en", "tropical", per)
	local temp, msh = names("en", "temperate", per)
	local s1 = share(trop, { "^Port ", "town$", " Bay$", " Point$", " Cay$", " Key$", " Estate$", " Pen$", " Hall$", "^Mount ", "^St " })
	local s0 = share(temp, { "^Port ", "town$", " Bay$", " Point$", " Cay$", " Key$", " Estate$", " Pen$", " Hall$", "^Mount ", "^St " })
	print(string.format("  en tropical: Port / -town / Bay / Point / Cay / Estate / Pen / Hall / Mount / St %.0f %% (temperate %.0f %%); separate %d vs %d",
		100 * s1, 100 * s0, tsh.separate or 0, msh.separate or 0))
	ok(s1 >= 0.2 and s1 > s0 * 2, "tropical en takes its own forms")
	for _, nm in ipairs(trop) do
		local w = PN.lowerAll(nm):match("^(%S+)")
		ok(not (w:find("thorpe$") or w:find("by$") or w:find("ham$")), "tropical en: no -thorpe / -by / -ham: " .. nm)
	end
	local dry = names("usa", "dry", per)
	local sp, spn = share(dry, { "^Agua ", "^Arroyo ", "^Los ", "^Las ", "^San ", "^Santa " })
	local water = share(dry, { " Springs$", " Wells$", " Tank$", "^Agua ", " Creek$", " Wash$" })
	print(string.format("  usa dry: Spanish layer %.0f %% (%d), water names %.0f %%, e.g. %s", 100 * sp, spn, 100 * water,
		table.concat({ dry[1], dry[2], dry[3], dry[4], dry[5] }, ", ")))
	ok(sp >= 0.08 and sp <= 0.45, "usa dry: a Spanish layer, not the whole map: " .. sp)
	local sub = names("en", "subarctic", per)
	local s2 = share(sub, { "^Fort ", " Landing$", " Portage$", " Rapids$", " Narrows$", "^Glen", "^Strath", "^Kyle" })
	print(string.format("  en subarctic: Fort / Landing / Portage / Rapids / Narrows / Glen / Strath / Kyle %.0f %%", 100 * s2))
	ok(s2 >= 0.1, "subarctic en takes its post-and-portage and Highland forms")
	for _, lang in ipairs({ "sv", "nb" }) do
		local pat = lang == "sv" and { "vik$", "fjärd$", "fjäll$", "näs$" } or { "vik$", "fjord$", "fjell$", "nes$" }
		local a = share(names(lang, "subarctic", per), pat)
		local b = share(names(lang, "temperate", per), pat)
		print(string.format("  %s vik / fjord / fell forms: subarctic %.0f %%, temperate %.0f %%", lang, 100 * a, 100 * b))
		ok(a > b, lang .. " subarctic: more vik / fjord / fell forms")
	end
end)

test("civic names (Junction / Station / Center) only on late towns, never on a natural confluence", function()
	-- a usa map of confluence towns and plain late towns, the civic share at its most
	local L = PN.lang("usa")
	local old = L.quota.civic
	L.quota.civic = 0.3
	local okRun, err = pcall(function()
		for _, seed in ipairs(SEEDS) do
			local towns = makeMap(seed, "valley", 20, "temperate")
			for i, t in ipairs(towns) do
				if i % 3 == 0 then t.w.confluence, t.w.river = 1, 1; t.cue.w.confluence = 1 end
			end
			local res = PN.assign(towns, { lang = "usa", seed = seed })
			for i, r in ipairs(res) do
				local inf = r.info or {}
				local civic = inf.shape ~= "character" and (inf.shape == "civic" or (inf.gE and inf.gE.flags.v) or (inf.aE and inf.aE.flags.v))
				if civic then
					ok(not towns[i].w.confluence, "civic on a confluence: " .. r.new)
					eq(inf.layer, "late", "civic on a late town: " .. r.new)
				end
				ok(not (r.new:find(" Junction$") and towns[i].w.confluence), "no Junction at a confluence: " .. r.new)
			end
		end
	end)
	L.quota.civic = old
	ok(okRun, tostring(err))
end)

test("created towns follow the game year: Works before 1920 Ironbridge-style / -Works; railway Junction / Station; districts after 1945 Heights / Park / Estates", function()
	local parents = {}
	for i = 1, FULL and 120 or 50 do parents[i] = "Ash" .. ({ "ford", "ley", "ton", "bury", "field", "wick", "thorpe", "worth" })[i % 8 + 1] .. i end
	local function run(fn, year, pats)
		local n = 0
		for i, p in ipairs(parents) do
			local nm, info = fn(p, year, i)
			local hit = false
			if info and (info.pattern == "cue") then hit = pats.cue == true end
			for _, pt in ipairs(pats) do if nm and nm:find(pt) then hit = true end end
			if hit then n = n + 1 end
		end
		return n / #parents
	end
	local function works(p, year, i)
		return OFF.works("en", p, { kind = i % 2 == 0 and "rail" or "plain", fam = ({ "iron", "coal", "works", "stone" })[i % 4 + 1],
			river = i % 3 == 0, valley = i % 5 == 0, year = year }, {}, { seed = i })
	end
	local a = run(works, 1880, { " Works$", "Ironworks$", " Foundry$", " Forge$", cue = true })
	local b = run(works, 1990, { " Works$", "Ironworks$", " Foundry$", " Forge$", cue = true })
	print(string.format("  Works: Ironbridge-style / -Works %.0f %% in 1880, %.0f %% in 1990", 100 * a, 100 * b))
	ok(a > b, "Works before 1920 take the old industrial forms more")
	local function dist(cls)
		return function(p, year, i)
			return OFF.district(cls, p, { kind = i % 2 == 0 and "lead" or "upper", dz = 20, year = year }, {}, { seed = i })
		end
	end
	for _, cls in ipairs({ "en", "usa" }) do
		local pats = { " Heights$", " Park$", " Estates?$", " Acres$", " Gardens$", " Village$" }
		local c = run(dist(cls), 1965, pats)
		local d = run(dist(cls), 1900, pats)
		local r1 = run(dist(cls), 1890, { " Junction$", " Station$", "^New " })
		local r2 = run(dist(cls), 1990, { " Junction$", " Station$", "^New " })
		print(string.format("  %s districts: Heights / Park / Estates / Acres %.0f %% in 1965, %.0f %% in 1900; Junction / Station / New %.0f %% in 1890, %.0f %% in 1990",
			cls, 100 * c, 100 * d, 100 * r1, 100 * r2))
		ok(c > d, cls .. " districts after 1945: the post-war forms more")
		ok(r1 > r2, cls .. " districts in the railway era: Junction / Station / New more")
	end
end)

test("district compass words relate to the parent town and sit on its side of it (every list)", function()
	for _, cls in ipairs({ "en", "usa", "de", "fr", "it", "es", "pt", "nl", "sv", "nb", "ja", "ja_r" }) do
		local D0 = OFF.districtOf(cls)
		local words = {}
		for d, f in pairs(D0.compass) do
			for _, e in ipairs(OFF.split(f)) do words[#words + 1] = { d = d, pre = e.f:match("^(.-)%%s") or "", post = e.f:match("%%s(.*)$") or "" } end
		end
		local nCompass = 0
		for i = 1, FULL and 160 or 60 do
			local parent = ({ "Ashford", "Holt", "Brackley", "Kirkby", "Lindau", "Oberhof", "Valence", "Monteverde" })[i % 8 + 1]
			if cls == "ja" then parent = ({ "長浜", "高崎", "深谷" })[i % 3 + 1] end
			local px, py = 0, 0
			local x, y = (U(i, "dx") - 0.5) * 3000, (U(i, "dy") - 0.5) * 3000
			local dir = OFF.compass(px, py, x, y)
			local nm = OFF.district(cls, parent, { kind = "lead", dir = dir, year = 1960 }, {}, { seed = i * 7 })
			if nm then
				for _, w in ipairs(words) do
					local f = w.pre .. parent .. w.post
					if nm == f then
						nCompass = nCompass + 1
						eq(w.d, dir, string.format("%s: %s on the %s side of %s", cls, nm, tostring(dir), parent))
					end
				end
			end
		end
		ok(nCompass > 0, cls .. ": some compass districts")
		-- (a parent with a compass or size word: no second one)
		local q = ({ en = "South Ashby", usa = "North Laurelwood", de = "Klein Lindau", fr = "Petit-Valence" })[cls]
		if q then
			for i = 1, 30 do
				local nm = OFF.district(cls, q, { kind = "lead", dir = ({ "n", "s", "e", "w" })[i % 4 + 1], year = 1960 }, {}, { seed = i })
				for _, w in ipairs(words) do ok(not (nm and nm == w.pre .. q .. w.post), cls .. " a second compass word: " .. tostring(nm)) end
			end
		end
	end
end)

test("leftover feature claims: the unspent river goes to a district (Glavenside) and a stop, under the feature's budget", function()
	-- 12 towns along one river: 2 grants, the rest leftover claims
	local towns = {}
	for i = 1, 12 do
		local w = "river:1,bridge:.6,ford:.6,meadow:.6"
		local cw = {}
		if i == 1 then w = w .. ",mouth:1,coast:.8"; cw.mouth = 1 end
		towns[i] = { id = i, name = "T" .. i, x = 0, y = i * 2200, w = tags(w), cap = 500 + i * 10,
			cue = { w = cw, river = 1, flow = i / 12 }, river = true }
	end
	for _, lang in ipairs({ "en", "usa", "de" }) do
		local res, st = PN.assign(towns, { lang = lang, seed = 3, sat = false })
		ok(#st.leftList >= 6, lang .. " leftover claims listed: " .. #st.leftList)
		local names = {}
		for _, r in ipairs(res) do names[#names + 1] = r.new end
		local got = nil
		for i, r in ipairs(res) do
			local claim = PN.leftClaim(st.waters, names, towns[i].x, towns[i].y, { own = r.new })
			if claim then
				ok(not PN.lowerAll(r.new):find(PN.lowerAll(claim.s), 1, true), "a claim is never the town's own spent stem")
				local nm = PN.claimName(lang, claim, "across", { [r.new] = true }, { seed = 5 })
				if nm and got == nil then
					got = nm
					ok(PN.lowerAll(nm):find(PN.lowerAll(claim.s), 1, true) ~= nil, lang .. " the claim's stem in the district: " .. nm)
					-- (the district's name goes through ot_offname first)
					local dn, info = OFF.district(lang == "usa" and "usa" or lang, r.new, { kind = "across", river = true, year = 1900 }, {},
						{ seed = 5, extra = { { name = nm, form = "%s", first = true } } })
					eq(dn, nm, lang .. " the claim before the composed forms")
					eq(info.pattern, "feature", "pattern feature")
					-- (the stop: the claim's group before the theme's words)
					local gs = SN.groups(SN.LANG[lang == "usa" and "usa" or lang] or SN.LANG.en, "centre", { claimName = claim.s, town = r.new })
					local first = nil
					for _, g in ipairs(gs) do if first == nil or g.rank < first.rank then first = g end end
					local hasClaim = false
					for _, g in ipairs(gs) do if g.kind == "claim" then hasClaim = true; ok(g.rank < 0.5, "claim before the theme") end end
					ok(hasClaim, lang .. " stop groups carry the claim")
				end
			end
		end
		ok(got ~= nil, lang .. " a district name from a leftover claim")
		print(string.format("  %s: %d leftover claims; district %s", lang, #st.leftList, tostring(got)))
		-- (spent: three names carry the stem, no more claims)
		local claim = PN.leftClaim(st.waters, names, towns[6].x, towns[6].y, { own = "X" })
		if claim then
			local full = { names[1], claim.s .. "a", claim.s .. "b", claim.s .. "c" }
			eq(PN.leftClaim(st.waters, full, towns[6].x, towns[6].y, { own = "X" }), nil, "over the feature's budget: no claim")
		end
	end
end)

test("the naming hook for strong characters: town.character = <kind> takes a striking form of its kind", function()
	-- (NEXT_PHASE_BRIEF 61, the s61 forms: a waterfront's Quay, a street village's Long X / X Street)
	local kinds = { en = { hilltop = "%-on%-the%-Hill$|^High ", harbour = " Quay$|^Port ", garden = " Garden City$",
		market = "^Market |^Kings | Magna$", street = "^Long | Street$" },
		usa = { hilltop = " Heights$", harbour = " Cove$", garden = " Garden City$", island = " Island$", market = " Center$" } }
	for lang, ks in pairs(kinds) do
		for kind, pat in pairs(ks) do
			local hits, n = 0, 0
			for _, seed in ipairs(SEEDS) do
				local towns = makeMap(seed, "coast", 16, "temperate")
				towns[3].character = kind
				towns[3].w.hilltop, towns[3].w.coast, towns[3].w.bay, towns[3].w.island = 0.8, 0.8, 0.6, 0.6
				local res, st = PN.assign(towns, { lang = lang, seed = seed })
				local r = res[3]
				n = n + 1
				local hit = false
				for p in pat:gmatch("[^|]+") do if r.new:find(p) then hit = true end end
				if hit then
					hits = hits + 1
					eq(r.info.shape, "character", "the character shape")
					eq(r.info.charKind, kind, "the kind on the info")
				end
				ok((st.shapes.used.character or 0) <= 1, "one character town on the map")
			end
			print(string.format("  %s %s: %d of %d", lang, kind, hits, n))
			ok(hits >= n - 1, lang .. " " .. kind .. ": the kind's forms")
		end
	end
	-- (an unknown kind: an ordinary character town)
	local towns = makeMap(5, "coast", 16, "temperate")
	towns[3].character = "volcano"
	local res = PN.assign(towns, { lang = "en", seed = 5 })
	ok(res[3].info.shape ~= "character", "unknown kind: no character shape")
end)

-- samples for the report: EU (en) / US (usa) x the four climates, 16 towns, then districts and Works of four of them
test("samples (NAME_SAMPLES=1 prints): EU / US x temperate / tropical / dry / subarctic, 16 towns + districts + Works", function()
	local dump = os.getenv("NAME_SAMPLES") ~= nil
	for _, lang in ipairs({ "en", "usa" }) do
		for ci, climate in ipairs(CLIMATES) do
			local preset = ({ "valley", "coast", "upland", "lakes" })[ci]
			local towns = makeMap(1 + ci * 1000, preset, 16, climate)
			local res, st = PN.assign(towns, { lang = lang, seed = 1, climate = climate, year = 1850 })
			local used = {}
			for _, r in ipairs(res) do used[r.new] = true end
			local parts = {}
			for _, r in ipairs(res) do parts[#parts + 1] = string.format("%s[%s/%s]", r.new, r.info and r.info.shape or "-", r.info and r.info.layer or "-") end
			local offs = {}
			for k = 1, 4 do
				local i = k * 4 - 1
				local parent = res[i].new
				local B = NW.newBudget(lang, 20)
				for _, r in ipairs(res) do NW.add(B, r.new) end
				local year = k <= 2 and 1890 or 1965
				local gen = PN.related(lang, parent, k % 2 == 0 and "upper" or "lead", used, { seed = k, climate = climate, year = year })
				local claim = PN.leftClaim(st.waters, (function() local l = {} for n in pairs(used) do l[#l + 1] = n end table.sort(l) return l end)(),
					towns[i].x, towns[i].y, { own = parent })
				local extra = gen and { { name = gen, form = "%s" } } or nil
				if claim then
					local cn = PN.claimName(lang, claim, "across", used, { seed = k, climate = climate, year = year })
					if cn then extra = extra or {}; table.insert(extra, 1, { name = cn, form = "%s", first = true }) end
				end
				local dn, di = OFF.district(lang, parent, { kind = k % 2 == 0 and "upper" or "lead", dz = 20, year = year,
					dir = ({ "n", "e", "s", "w" })[k], climate = climate }, used, { seed = k, extra = extra })
				if dn then used[dn] = true end
				local wgen = PN.works(lang, parent, ({ "works", "mine", "quarry", "mill" })[k], "plain", used, { seed = k, climate = climate, year = year })
				local wn, wi = OFF.works(lang, parent, { kind = ({ "plain", "rail", "hill", "plain" })[k], fam = ({ "iron", "coal", "stone", "textile" })[k],
					river = k == 1, year = year, climate = climate }, used, { seed = k, extra = wgen and { { name = wgen, form = "%s" } } or nil })
				if wn then used[wn] = true end
				offs[#offs + 1] = string.format("%s (%d): district %s [%s], Works %s [%s]", parent, year, tostring(dn), di and di.pattern or "-",
					tostring(wn), wi and wi.pattern or "-")
			end
			if dump then
				local f = {}
				for _, e in ipairs(PN.shapeFields(st)) do f[#f + 1] = e[1] .. "=" .. tostring(e[2]) end
				print(string.format("  %s %s (%s): %s", lang, climate, preset, table.concat(parts, ", ")))
				print("    NAMES shapes " .. table.concat(f, " "))
				for _, o in ipairs(offs) do print("    " .. o) end
			end
			ok(st.named == #towns, lang .. " " .. climate .. " every town named")
		end
	end
end)
