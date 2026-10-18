-- Synthetic maps for the name tests (moved from test_shapegates.lua, 2026-10-15, NEXT_PHASE_BRIEF 60, so that
-- test_names60.lua runs the same maps): site kinds, map presets, the climates and makeMap. Loaded with loadfile.

local DIR = "square_organic_towns::/organic_towns/"
local PN = ug_require(DIR .. "ot_placename.lua")
local CL = ug_require(DIR .. "ot_climate.lua")
local rng = ug_require(DIR .. "ot_rng.lua")

local SITES = {
	river = "river:1,bridge:.6,ford:.6,meadow:.6,plain:.5",
	confluence = "river:1,confluence:1,ford:.6,bridge:.6,plain:.5",
	mouth = "river:1,mouth:1,coast:.8,bay:.6,bridge:.7,market:.6",
	bend = "river:1,bend:.9,meadow:.6,forest:.4",
	falls = "river:1,falls:1,gorge:.5,rock:.4,forest:.4",
	lake = "lake:1,mere:.8,edge:.7,forest:.5,meadow:.5",
	tarn = "lake:1,tarn:1,mountain:.7,hill:.6,small:.6",
	coast = "coast:1,sandy:.8,bay:.6,plain:.6",
	cliff = "coast:1,cliff:1,rocky:.8,headland:.9,hilltop:.6",
	spit = "coast:1,spit:1,headland:.8,sandy:.5",
	island = "island:1,coast:1,sandy:.7,bay:.6",
	hill = "hill:.8,hilltop:.7,slope:.6,heath:.4",
	pass = "pass:1,mountain:.8,hill:.7,rock:.6,pine:.5",
	moor = "moor:.8,heath:.6,hill:.6,spring:.6",
	vale = "valley:1,vale:.8,forest:.6,meadow:.5",
	gorge = "valley:1,gorge:1,river:1,rock:.7,slope:.7",
	forest = "forest:.9,clearing:.8,oak:.7,edge:.6",
	edge = "forest:.6,edge:.7,ash:.7,field:.4",
	plain = "plain:.9,field:.8",
	marsh = "marsh:.8,fen:.8,plain:.7,willow:.6",
}
local PRESETS = {
	valley = { "river", "confluence", "mouth", "bend", "falls", "vale", "plain", "edge", "forest", "hill", "marsh", "river" },
	coast = { "coast", "cliff", "spit", "island", "mouth", "plain", "edge", "hill", "marsh", "forest", "coast" },
	lakes = { "lake", "tarn", "forest", "edge", "vale", "hill", "plain", "river", "moor", "lake" },
	upland = { "hill", "pass", "moor", "gorge", "tarn", "vale", "forest", "river", "falls", "plain" },
}
local PRESET_ORDER = { "valley", "coast", "lakes", "upland" }
local CLIMATES = { "temperate", "tropical", "dry", "subarctic" }

local function tags(s)
	local w = {}
	for t, v in s:gmatch("([%a_]+):([%d%.]+)") do w[t] = tonumber(v) end
	return w
end

local function U(seed, ...) return rng.unit(seed, ...) end

-- A synthetic map: n towns on a 16 km square (at least 1.4 km apart), site kinds from the preset, the survey's cues as
-- ot_mapshape.townCues gives them (the compass by position, two rivers by the x side with a flow from the north, the
-- main valley, the peak and range on high ground, the big bay and the big lake), heights, sizes, two character towns,
-- the climate's site tags and vetoes as siteTags applies them.
local function makeMap(seed, preset, n, climate)
	local kinds = PRESETS[preset]
	local towns = {}
	local tries = 0
	while #towns < n and tries < n * 60 do
		tries = tries + 1
		local x = (U(seed * 3 + 1, tries, "px") - 0.5) * 16000
		local y = (U(seed * 7 + 5, "py", tries * 13 + 3) - 0.5) * 16000
		local okP = true
		for _, t in ipairs(towns) do if (t.x - x) ^ 2 + (t.y - y) ^ 2 < 1400 ^ 2 then okP = false break end end
		if okP then
			local i = #towns + 1
			local kind = kinds[rng.hash(seed, "kind", i) % #kinds + 1]
			local w = tags(SITES[kind])
			local cw = {}
			local nx, ny = x / 8000, y / 8000
			local function side(v) return v > 0.3 and math.min(1, 0.4 + 0.6 * (v - 0.3) / 0.7) or nil end
			cw.north, cw.south, cw.east, cw.west = side(ny), side(-ny), side(nx), side(-nx)
			if math.max(math.abs(nx), math.abs(ny)) <= 0.25 then cw.central = 0.8 end
			local dir, dv = nil, 0
			for _, d in ipairs({ "north", "south", "east", "west" }) do if (cw[d] or 0) > dv then dir, dv = d, cw[d] end end
			local cue = { w = cw, dir = dir }
			local alt = preset == "upland" and 150 + U(seed, "alt", i) * 450 or 5 + U(seed, "alt", i) * 110
			if w.river then
				cue.river = x < 0 and 1 or 2
				cue.flow = math.max(0, math.min(1, (y + 8000) / 16000))
				if cue.flow <= 0.33 then cw.lower = 0.6 + 0.4 * (1 - cue.flow / 0.33)
				elseif cue.flow >= 0.67 then cw.upper = 0.6 + 0.4 * (cue.flow - 0.67) / 0.33 end
				if w.confluence then cw.confluence = 1 end
				if w.mouth then cw.mouth = 1 end
				if w.falls then cw.falls = 1 end
				if w.bend then cw.bend = 0.9 end
				if cue.river == 1 then cw.mainvalley = 0.9 end
				alt = alt * (0.4 + cue.flow)
			end
			if preset == "upland" and (w.hill or w.pass or w.mountain) then
				cw.range = 0.8
				if U(seed, "peak", i) < 0.4 then cw.peak = 1 end
				if w.pass then cw.summit = 0.7 end
			end
			if (w.bay or 0) > 0 and preset == "coast" and U(seed, "bay", i) < 0.5 then cw.bay, cw.bigbay, cue.bigbay = 1, 1, true end
			if w.lake and preset == "lakes" and U(seed, "big", i) < 0.5 then
				cw.biglake, cue.lake = 1, true
				cue.ldir = PN.dirFrom(x - 1000, y)
			end
			if climate ~= "temperate" then
				for t, v in pairs(CL.SITE[climate] or {}) do w[t] = math.max(w[t] or 0, v) end
				if climate == "tropical" and (w.coast or 0) > 0 then w.reef = 0.5 end
				if climate == "tropical" and (w.bay or w.island) then w.lagoon = 0.8 end
				for t in pairs(w) do if CL.vetoTag(climate, t) then w[t] = nil end end
			end
			local cap = 150 + math.floor(U(seed, "cap", i) * 2300)
			local ch = i == 3 or i == 9
			if ch then w.character, w.church = 1, 0.4 end
			if cap > 1800 then w.market, w.big = 0.8, 0.8 elseif cap < 400 then w.small = 0.6 end
			towns[i] = { id = 1000 + i * 7, name = "T" .. i, x = x, y = y, w = w, ranked = PN.rankOf(w), cap = cap,
				character = ch, cue = cue, river = w.river ~= nil, lake = w.lake ~= nil, alt = alt }
		end
	end
	return towns
end

return { SITES = SITES, PRESETS = PRESETS, PRESET_ORDER = PRESET_ORDER, CLIMATES = CLIMATES, tags = tags, makeMap = makeMap }
