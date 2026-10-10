-- Every menu entry's params sit in the left toolbar (location "Toolbar", 2026-10-09: the menu's
-- hover tooltip no longer covers the settings there). The toolbar's buttons fit about 6 characters
-- (the user's screenshot: 3-button rows fit "Medium", 2-button rows cut "Highway" to "Highwa…"), so
-- every Button row has at most 5 labels of at most 6 characters; longer choices are ComboBoxes.

local DIR = "square_roundabouts::/infrastructure/street_construction/"

local function loadData(file)
	-- the file defines a global data(); each load replaces it
	ug_require(DIR .. file)
	return data()
end

local ENTRIES = {
	"square_roundabouts.con.lua",
	"square_roundabouts_magic.con.lua",
	"square_roundabouts_channel.con.lua",
	"square_roundabouts_interchange.con.lua",
	"square_roundabouts_highway_parclo.con.lua",
	"square_roundabouts_highway_parclo2.con.lua",
	"square_roundabouts_highway_diamond.con.lua",
}

-- UTF-8 characters, not bytes
local function chars(s)
	local _, n = s:gsub("[^\128-\191]", "")
	return n
end

test("every entry: params in the toolbar; Button rows of at most 5 labels of at most 6 characters", function()
	local buttons = 0
	for _, file in ipairs(ENTRIES) do
		local con = loadData(file)
		ok(#con.params > 0, file)
		for _, p in ipairs(con.params) do
			local n = file .. " " .. p.key
			eq(p.location, "Toolbar", n .. ": location")
			ok(p.uiType == "Button" or p.uiType == "ComboBox", n .. ": Button or ComboBox")
			if p.uiType == "Button" then
				buttons = buttons + 1
				ok(#p.values <= 5, n .. ": at most 5 buttons")
				for _, v in ipairs(p.values) do ok(chars(v) <= 6, n .. ": label '" .. v .. "' at most 6 characters") end
				-- per-value tooltips, where given, cover every button
				if p.tooltips then eq(#p.tooltips, #p.values, n .. ": tooltips") end
			else
				eq(p.tooltips, nil, n .. ": no per-value tooltips on a ComboBox")
			end
		end
	end
	ok(buttons >= 30, "button rows checked: " .. buttons)
end)

test("short labels are explained in the tooltip", function()
	-- S / M / L (and XS / XL) and the CCW / CW, Hwy abbreviations: the row's tooltip says what they mean
	local explain = { S = "small", M = "medium", L = "large", XS = "extra small", XL = "extra large",
		CCW = "counterclockwise", CW = "clockwise", Hwy = "highway", Right = "right-hand", Left = "left-hand" }
	for _, file in ipairs(ENTRIES) do
		local con = loadData(file)
		for _, p in ipairs(con.params) do
			if p.uiType == "Button" then
				for _, v in ipairs(p.values) do
					local word = explain[v]
					if word then
						ok(type(p.tooltip) == "string" and p.tooltip:lower():find(word, 1, true) ~= nil,
							file .. " " .. p.key .. ": tooltip explains '" .. v .. "'")
					end
				end
			end
		end
	end
end)

-- Translations (strings.json, 2026-10-10). In a .con.lua `_()` returns the key and the game translates
-- the whole text on display, so a tooltip that lists radii is one translatable text with the numbers
-- written out: these tests keep those numbers in step with the geometry tables.

local SC = "square_roundabouts::/infrastructure/street_construction/"

-- ug_require caches a file after its first load, and a cached load leaves the previous file's
-- data(): the tests below start from a clean module cache for every entry.
local function loadFresh(file)
	reset_modules()
	return loadData(file)
end

local function paramByKey(con, key)
	for _, p in ipairs(con.params) do if p.key == key then return p end end
end

test("radius tooltips list the preset radii of the geometry tables", function()
	local geom = ug_require(SC .. "square_roundabouts_geometry.lua")
	local ix = ug_require(SC .. "square_roundabouts_interchange.lua")
	local cases = {
		{ "square_roundabouts.con.lua", geom.RADIUS_PRESET_KEY, geom.RADIUS_PRESET_NAMES, geom.RADIUS_PRESETS, geom.RADII },
		{ "square_roundabouts_interchange.con.lua", ix.RADIUS_PRESET_KEY, ix.RADIUS_PRESET_NAMES, ix.RADIUS_PRESETS, ix.RADII },
	}
	for _, c in ipairs(cases) do
		local p = paramByKey(loadFresh(c[1]), c[2])
		local list = {}
		for i, ri in ipairs(c[4]) do list[i] = c[3][i] .. " " .. c[5][ri] .. " m" end
		local want = table.concat(list, ", ")
		ok(p.tooltip:find(want, 1, true) ~= nil, c[1] .. ": tooltip lists " .. want)
		eq(p.values, c[3], c[1] .. ": size codes as button labels")
	end
end)

test("highway Scale tooltips list hx.LOOP_RADII / hx.TERMINAL_DISTANCES", function()
	local hx = ug_require(SC .. "square_roundabouts_highway.lua")
	local function orList(list)
		local out = {}
		for i = 1, #list do out[i] = tostring(list[i]) end
		return table.concat(out, ", ", 1, #out - 1) .. " or " .. out[#out] .. " m"
	end
	for _, id in ipairs({ "parclo", "parclo2", "diamond" }) do
		local con = loadFresh("square_roundabouts_highway_" .. id .. ".con.lua")
		local tip = paramByKey(con, hx.PARAM_KEYS.size).tooltip
		local want = orList(id == "diamond" and hx.TERMINAL_DISTANCES or hx.LOOP_RADII)
		ok(tip:find(want, 1, true) ~= nil, id .. ": Scale tooltip lists " .. want)
	end
end)

-- strings.json in the stable layout of `make i18n ARGS=--fix-format`: one "key": "text" per line
local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts/"
local function loadStrings()
	local f = assert(io.open(here .. "../../mods/square_roundabouts/strings.json", "r"))
	local langs, cur = {}, nil
	for line in f:lines() do
		local lang = line:match('^    "([%w_]+)": {')
		if lang then
			cur = {}; langs[lang] = cur
		elseif cur then
			local k, v = line:match('^        "(.-)": "(.*)",?$')
			if k then cur[k] = v end
		end
	end
	f:close()
	return langs
end

-- display width: CJK / full-width characters count as 2
local function width(s)
	local w = 0
	for _, c in utf8.codes(s) do
		local wide = (c >= 0x1100 and c <= 0x115F) or (c >= 0x2E80 and c <= 0xA4CF) or (c >= 0xAC00 and c <= 0xD7A3)
			or (c >= 0xF900 and c <= 0xFAFF) or (c >= 0xFF00 and c <= 0xFF60)
		w = w + (wide and 2 or 1)
	end
	return w
end

test("translated button labels fit the toolbar (6 characters, CJK counted double)", function()
	local langs = loadStrings()
	local n = 0
	for _, lang in ipairs({ "ru", "de", "fr", "es", "it", "nl", "pl", "pt_BR", "ja", "ko", "zh_CN", "zh_TW" }) do
		local tr = langs[lang]
		ok(tr ~= nil, "strings.json has " .. lang)
		for _, file in ipairs(ENTRIES) do
			for _, p in ipairs(loadFresh(file).params) do
				if p.uiType == "Button" then
					for _, v in ipairs(p.values) do
						local t = tr[v]
						if t then
							n = n + 1
							ok(width(t) <= 6, lang .. " " .. file .. " " .. p.key .. ": '" .. t .. "' fits 6")
						end
					end
				end
			end
		end
	end
	ok(n >= 300, "translated labels checked: " .. n)
end)
