-- Site classifier (ot_site): per-town street style from the town's site, the region only biasing, the era gating
-- the modern styles (NEXT_PHASE_BRIEF 8: flat open land -> sprawl, coasts / hills / valleys -> dense, winding).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local T = ug_require(F.DIR .. "ot_terrain.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local SITE = ug_require(F.DIR .. "ot_site.lua")

local SPRAWL = { NA_GRID = true, NA_SUBURB = true, SUPERBLOCK = true, EU_EXTENSION = true, MED_ENSANCHE = true }
local DENSE = { EU_ORGANIC = true, MED_HILL = true, NORDIC = true, JP_DENSE = true }
local NAMES = { EU = "::/names/germany/germany.names", US = "::/names/usa/usa.names", JP = "::/names/japan/japan.names",
	MED = "::/names/italy/italy.names" }

local TERRAINS = {
	flat = F.flat,
	coast = F.coast(300),
	valley = F.valley(math.rad(30)),
	hills = F.hill,
}

local cache = {}
local function survey(name)
	if cache[name] == nil then
		local s = TERRAINS[name]
		cache[name] = { stats = T.stats(s, 0, 0, 600, 24), wide = T.wide(s, 0, 0, 2000) }
	end
	return cache[name]
end

--- Style picks of n towns at a site: counts by id, shares of sprawl / dense, the last style table.
local function picks(terrain, region, year, n)
	local sv = survey(terrain)
	local counts, sprawl, dense = {}, 0, 0
	for town = 1, n do
		local inputs = I.build({ townId = town, pos = { 0, 0 }, capacity = 1500, year = year, nameList = NAMES[region],
			climate = "temperate", autoStyle = true })
		inputs.terrain, inputs.wide = sv.stats, sv.wide
		local p = ST.resolve(inputs)
		counts[p.id] = (counts[p.id] or 0) + 1
		if SPRAWL[p.id] then sprawl = sprawl + 1 end
		if DENSE[p.id] then dense = dense + 1 end
	end
	return counts, sprawl / n, dense / n
end

local function text(c)
	local parts = {}
	for _, id in ipairs(ST.IDS) do if c[id] then parts[#parts + 1] = id .. "=" .. c[id] end end
	return table.concat(parts, " ")
end

test("features: the four synthetic sites classify as plain, coast, valley and hills", function()
	eq(SITE.features(survey("flat").stats, survey("flat").wide).kind, "plain")
	local c = SITE.features(survey("coast").stats, survey("coast").wide)
	eq(c.kind, "coast")
	ok(c.coast >= 0.5, "coast " .. c.coast)
	eq(SITE.features(survey("valley").stats, survey("valley").wide).kind, "valley")
	local h = SITE.features(survey("hills").stats, survey("hills").wide)
	ok(h.rough >= 0.5 and h.open < 0.2, string.format("hills rough=%.2f open=%.2f", h.rough, h.open))
	ok(SITE.features(survey("flat").stats, survey("flat").wide).open >= 0.9)
end)

test("picks follow the site: flat land sprawls, coasts / valleys / hills are dense; the region biases", function()
	for _, region in ipairs({ "EU", "US" }) do
		local cf, sf, df = picks("flat", region, 1970, 80)
		print(region .. " flat   " .. text(cf))
		ok(sf >= 0.6, region .. " flat: sprawl share " .. sf)
		for _, site in ipairs({ "valley", "hills" }) do
			local c, s, d = picks(site, region, 1970, 80)
			print(region .. " " .. site .. " " .. text(c))
			ok((c.SUPERBLOCK or 0) <= 2, region .. " " .. site .. ": superblocks are for open land")
			-- (2026-10-13: Nordic needs rough AND coast now, so US hills keep more of their grids: SF-style grids on hills)
			local gap = (region == "US" and site == "hills") and 0.2 or 0.3
			ok(d >= df + gap, region .. " " .. site .. ": dense share " .. d .. " vs flat " .. df)
		end
		local cc, sc, dc = picks("coast", region, 1970, 80)
		print(region .. " coast  " .. text(cc))
		ok(dc >= df + 0.15, region .. " coast: dense share " .. dc .. " vs flat " .. df)
		ok(sc < sf, region .. " coast sprawls less than flat land")
	end
	-- the region still biases: US flat land is mostly grids, EU valleys mostly EU organic, JP coasts JP dense
	local us = picks("flat", "US", 1970, 80)
	ok((us.NA_GRID or 0) + (us.NA_SUBURB or 0) >= 48, "US flat: " .. text(us))
	local eu = picks("valley", "EU", 1970, 80)
	ok((eu.EU_ORGANIC or 0) >= 30, "EU valley: " .. text(eu))
	local jp = picks("coast", "JP", 1970, 80)
	ok((jp.JP_DENSE or 0) >= 50, "JP coast: " .. text(jp))
end)

test("one map, several styles: an EU map's towns on the four sites use at least four styles", function()
	local seen, n = {}, 0
	for _, site in ipairs({ "flat", "coast", "valley", "hills" }) do
		local c = picks(site, "EU", 1970, 12)
		for id in pairs(c) do
			if not seen[id] then seen[id] = true; n = n + 1 end
		end
	end
	ok(n >= 4, "styles on one EU map: " .. n)
end)

test("era gates (era range 1900+): no superblocks or car suburbs before 1950, no ensanche before 1920", function()
	for _, site in ipairs({ "flat", "coast" }) do
		local c = picks(site, "EU", 1920, 80)
		eq(c.SUPERBLOCK, nil, site)
		eq(c.NA_SUBURB, nil, site)
		local m = picks(site, "MED", 1910, 60)
		eq(m.MED_ENSANCHE, nil)
	end
	local late = picks("flat", "EU", 1970, 80)
	ok((late.SUPERBLOCK or 0) + (late.NA_SUBURB or 0) >= 15, "1970 EU flat: " .. text(late))
end)

test("seeded and saved: the same town keeps its style; a saved frame's style wins; a forced style wins", function()
	local sv = survey("flat")
	local function resolve(raw)
		local r = { townId = 9, pos = { 10, 20 }, capacity = 1500, year = 1970, nameList = NAMES.EU, autoStyle = true }
		for k, v in pairs(raw or {}) do r[k] = v end
		local inputs = I.build(r)
		inputs.terrain, inputs.wide = sv.stats, sv.wide
		return ST.resolve(inputs)
	end
	local a, b = resolve(), resolve()
	eq(a.id, b.id)
	eq(a.styleSource, "site")
	ok(a.styleWhy:find("^plain:"), a.styleWhy)
	local other = a.id == "MED_HILL" and "NORDIC" or "MED_HILL"
	local s = resolve({ frame = { axis = 0, origin = { 0, 0 }, style = other } })
	eq(s.id, other)
	eq(s.styleSource, "saved")
	eq(resolve({ forceStyle = "NA_GRID" }).id, "NA_GRID")
	-- without autoStyle: the region's profile as before
	local inputs = I.build({ townId = 9, pos = { 0, 0 }, year = 1970, nameList = NAMES.EU })
	eq(ST.resolve(inputs).id, "EU_ORGANIC")
end)

test("EU map: Nordic only for rough coasts, rare elsewhere; a flat town floor in hills is less rough (2026-10-13)", function()
	-- the English test map's sites (session 2026-10-13_0018_top-up-598153): every town rough 1.00, many by lakes; 6 of 14
	-- styled towns were Nordic
	local function share(f, region, year)
		local ws = SITE.weights({ region = region, year = year or 1900 }, f)
		local total, out = 0, {}
		for _, x in ipairs(ws) do total = total + x.w end
		for _, x in ipairs(ws) do out[x.id] = x.w / total end
		return out
	end
	local sites = {
		hillValley = { open = 0, rough = 1, coast = 0, river = 0, valley = 1 },
		hillLake = { open = 0, rough = 1, coast = 0.8, river = 0, valley = 0 },
		hillLakeValley = { open = 0, rough = 1, coast = 0.8, river = 0, valley = 1 },
		hills = { open = 0, rough = 1, coast = 0, river = 0, valley = 0 },
		flatCoast = { open = 0.3, rough = 0.2, coast = 0.9, river = 0, valley = 0 },
	}
	local sum = 0
	for name, f in pairs(sites) do
		local sh = share(f, "EU")
		print(string.format("      EU %-14s NORDIC %.2f EU_ORGANIC %.2f MED_HILL %.2f EU_EXTENSION %.2f", name, sh.NORDIC or 0,
			sh.EU_ORGANIC or 0, sh.MED_HILL or 0, sh.EU_EXTENSION or 0))
		sum = sum + (sh.NORDIC or 0)
		ok((sh.EU_ORGANIC or 0) > (sh.NORDIC or 0), name .. ": EU organic leads")
	end
	ok(sum / 5 <= 0.15, "EU map: Nordic share " .. sum / 5)
	ok(share(sites.hillLake, "EU").NORDIC > share(sites.hills, "EU").NORDIC * 1.5, "rough + coast pulls Nordic")
	ok(share(sites.hillLake, "NORDIC").NORDIC >= 0.6, "Nordic names: Nordic")
	-- the town floor: a flat river town in hilly country (Bexley: slope 0.02, 2 km spread 82 m)
	local fl = SITE.features({ meanSlope = 0.02, waterFraction = 0.05 }, { sd = 82, water = 0.27 })
	local st = SITE.features({ meanSlope = 0.12, waterFraction = 0 }, { sd = 82, water = 0.05 })
	ok(fl.rough <= 0.55, "flat floor rough " .. fl.rough)
	ok(st.rough >= 0.95, "steep town rough " .. st.rough)
	ok(fl.floor >= 0.9, "floor " .. fl.floor)
end)

-- (2026-10-14, NEXT_PHASE_BRIEF 48 item 3, run 2026-10-14_0814_sqot load 3: on the base "asia" list, Karachi to Seoul,
-- 14 of 16 towns came out JP_DENSE; tropical had no style bias)
local ASIA_SITES = nil
local function asiaSites()
	if ASIA_SITES then return ASIA_SITES end
	local list = { F.flat, F.hill, F.coast(300), F.coast(600), F.bay(), F.valley(math.rad(30)), F.valley(math.rad(110)),
		F.river(-120), F.river(60), F.plane(0.03, 0.5), F.plane(0.08, 2), F.steep(), F.ridgeVar(), F.cliff(0),
		F.shoreSlope(250, 0.06), F.terraces }
	ASIA_SITES = {}
	for i, s in ipairs(list) do ASIA_SITES[i] = { stats = T.stats(s, 0, 0, 600, 24), wide = T.wide(s, 0, 0, 2000) } end
	return ASIA_SITES
end

--- Styles of `per` towns on each of the 16 sites: counts, n.
local function sitePicks(nameList, climate, year, per, first)
	local counts, n = {}, 0
	for i, sv in ipairs(asiaSites()) do
		for k = 1, per do
			local town = (first or 1) + (i - 1) * per + (k - 1)
			local inputs = I.build({ townId = town, pos = { town * 37, -town * 53 }, capacity = 1500, year = year,
				nameList = nameList, climate = climate, autoStyle = true })
			inputs.terrain, inputs.wide = sv.stats, sv.wide
			local id = SITE.pick(inputs, town * 7919 + 13)
			counts[id] = (counts[id] or 0) + 1
			n = n + 1
		end
	end
	return counts, n
end

local function maxShare(c, n)
	local best, bid = 0, "-"
	for id, v in pairs(c) do if v / n > best then best, bid = v / n, id end end
	return best, bid
end

test("asia list: its own region, a broad mix of styles, no style over 50 % on 16 varied sites (BRIEF 48.3)", function()
	eq(I.region("::/names/asia/asia.names"), "ASIA")
	eq(I.region("::/names/japan/japan.names"), "JP")
	eq(I.region("::/names/china/china.names"), "EAST_ASIA")
	for _, climate in ipairs({ "tropical", "temperate", "dry" }) do
		for _, year in ipairs({ 1900, 1960 }) do
			-- the run's map: 16 towns, one per site
			local c, n = sitePicks("::/names/asia/asia.names", climate, year, 1)
			local sh, id = maxShare(c, n)
			local kinds = 0
			for _ in pairs(c) do kinds = kinds + 1 end
			print(string.format("      asia %-9s %d (16 towns): %s", climate, year, text(c)))
			ok(sh <= 0.5, string.format("%s %d: %s %.2f", climate, year, id, sh))
			ok(kinds >= 4, string.format("%s %d: %d styles", climate, year, kinds))
			-- and the odds behind it: 10 towns per site
			local c2, n2 = sitePicks("::/names/asia/asia.names", climate, year, 10, 500)
			local sh2, id2 = maxShare(c2, n2)
			ok(sh2 <= 0.42, string.format("%s %d, 160 towns: %s %.2f (%s)", climate, year, id2, sh2, text(c2)))
		end
	end
end)

test("the japan list stays JP_DENSE-led, china / korea keep their East Asian lead, also on a tropical map", function()
	for _, climate in ipairs({ "temperate", "tropical" }) do
		local c, n = sitePicks("::/names/japan/japan.names", climate, 1900, 10)
		local sh, id = maxShare(c, n)
		print(string.format("      japan %-9s 1900: %s", climate, text(c)))
		eq(id, "JP_DENSE", climate)
		ok(sh >= 0.5, string.format("japan %s: JP_DENSE %.2f", climate, sh))
		local e, en = sitePicks("::/names/china/china.names", climate, 1960, 10)
		local esh, eid = maxShare(e, en)
		ok(eid == "JP_DENSE" or eid == "SUPERBLOCK", "china " .. climate .. ": " .. text(e))
		ok((e.JP_DENSE or 0) + (e.SUPERBLOCK or 0) >= 0.6 * en, "china: dense / superblock " .. text(e))
		ok(esh > 0, "")
	end
end)

test("tropical bias: looser, lower styles and spreading forms weigh more, the dense compact ones less", function()
	local f = { open = 0.6, rough = 0.2, coast = 0.4, river = 0, valley = 0 }
	local function w(climate, region, year)
		local out, total = {}, 0
		for _, x in ipairs(SITE.weights({ region = region, climate = climate, year = year }, f)) do
			out[x.id] = x.w
			total = total + x.w
		end
		for id, v in pairs(out) do out[id] = v / total end
		return out
	end
	for _, region in ipairs({ "EU", "ASIA", "US" }) do
		local t, m = w("tropical", region, 1960), w("temperate", region, 1960)
		print(string.format("      %-4s 1960 tropical / temperate: NA_SUBURB %.2f/%.2f EU_EXTENSION %.2f/%.2f JP_DENSE %.2f/%.2f MED_HILL %.2f/%.2f",
			region, t.NA_SUBURB or 0, m.NA_SUBURB or 0, t.EU_EXTENSION or 0, m.EU_EXTENSION or 0, t.JP_DENSE or 0,
			m.JP_DENSE or 0, t.MED_HILL or 0, m.MED_HILL or 0))
		ok((t.NA_SUBURB or 0) > (m.NA_SUBURB or 0), region .. ": suburbs up")
		ok((t.EU_EXTENSION or 0) > (m.EU_EXTENSION or 0), region .. ": the extension up")
		ok((t.JP_DENSE or 0) < (m.JP_DENSE or 0) and (t.MED_HILL or 0) < (m.MED_HILL or 0), region .. ": dense styles down")
	end
	-- the form draw: sprawling / linear / radiating up, clustered down; the shore form more often
	local FM = ug_require(F.DIR .. "ot_form.lua")
	F.withForms(function()
		local function forms(climate)
			local c = {}
			for town = 1, 120 do
				local inputs = I.build({ townId = town, pos = { 0, 0 }, capacity = 1500, year = 1930, climate = climate,
					nameList = NAMES.EU, forceStyle = "EU_ORGANIC" })
				inputs.terrain = survey("flat").stats
				local p = ST.resolve(inputs)
				local id = p.form and p.form.id or "-"
				c[id] = (c[id] or 0) + 1
			end
			return c
		end
		local t, m = forms("tropical"), forms("temperate")
		local function s(c) local o = {} for k, v in pairs(c) do o[#o + 1] = k .. "=" .. v end table.sort(o) return table.concat(o, " ") end
		print("      forms tropical: " .. s(t) .. " | temperate: " .. s(m))
		ok((t.clustered or 0) < (m.clustered or 0), "fewer clustered")
		ok((t.sprawling or 0) + (t.linear or 0) + (t.radiating or 0) > (m.sprawling or 0) + (m.linear or 0) + (m.radiating or 0),
			"more spreading forms")
		local sf = { shore = 0.8, island = false }
		ok(FM.shoreChance(sf, "EU_ORGANIC", 200, "tropical") > FM.shoreChance(sf, "EU_ORGANIC", 200, "temperate"), "shore form more often")
		ok(FM.shoreChance(sf, "EU_ORGANIC", 200, "tropical") <= FM.SHORE_P.max, "within the cap")
	end)
	-- wider plots, within the subarctic's
	local trop = F.style({ forceStyle = "EU_ORGANIC", townId = 4, year = 1930, climate = "tropical" }, F.flat)
	local temp = F.style({ forceStyle = "EU_ORGANIC", townId = 4, year = 1930, climate = "temperate" }, F.flat)
	ok(trop.block.depth > temp.block.depth and trop.block.depth <= temp.block.depth * 1.2 + 1e-6, "wider plots, at most x 1.2")
end)

test("dry and subarctic climate biases: hill towns / grids on a dry map, Nordic in the subarctic, no fjord towns in the desert", function()
	local f = { open = 0.3, rough = 0.6, coast = 0.5, river = 0, valley = 0 }
	local function share(climate, id)
		local total, v = 0, 0
		for _, x in ipairs(SITE.weights({ region = "EU", climate = climate, year = 1930 }, f)) do
			total = total + x.w
			if x.id == id then v = x.w end
		end
		return v / total
	end
	ok(share("dry", "MED_HILL") > share("temperate", "MED_HILL"), "dry: hill towns up")
	ok(share("dry", "NORDIC") < share("temperate", "NORDIC"), "dry: Nordic down")
	ok(share("subarctic", "NORDIC") > share("temperate", "NORDIC"), "subarctic: Nordic up")
	ok(share("subarctic", "MED_HILL") < share("temperate", "MED_HILL"), "subarctic: Mediterranean hill towns down")
end)
