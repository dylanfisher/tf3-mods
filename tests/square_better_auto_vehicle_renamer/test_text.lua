-- Better Auto Vehicle Renamer: bavr_text.lua (UTF-8 helpers, model / line shortening, default names, render) and
-- bavr_settings.lua (params -> cfg). PLAN.md "Settings", "Naming one vehicle".

local Settings = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_settings.lua"
-- The render tests were written for the first layout (Model + number, automatic separators, no year): pin
-- those three settings unless a test sets them; the defaults test reads Settings.parse directly.
local function P(t, ...)
	local m = { ["bavr.format"] = 1, ["bavr.partSep"] = 1, ["bavr.year"] = 1 }
	for k, v in pairs(t or {}) do m[k] = v end
	return Settings.parse(m, ...)
end

local Text = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_text.lua"

local FULL = os.getenv("TEST_FULL") ~= nil

local function cfgOf(t) return P(t) end
local function rawOf(t) return Settings.parse(t) end

local function utf8ok(s)
	-- every lead byte is followed by the right number of continuation bytes
	local i, n = 1, #s
	while i <= n do
		local b = s:byte(i)
		local need = b < 0x80 and 0 or (b >= 0xF0 and 3) or (b >= 0xE0 and 2) or (b >= 0xC0 and 1) or -1
		if need < 0 then return false end
		for j = 1, need do
			local c = s:byte(i + j)
			if c == nil or c < 0x80 or c >= 0xC0 then return false end
		end
		i = i + need + 1
	end
	return true
end

---------------------------------------------------------------------------
-- Settings

test("settings: defaults, every index, garbage falls back to the default", function()
	local c = rawOf(nil)
	eq({ c.format, c.model, c.prefix, c.numSep, c.partSep, c.digits, c.start, c.counter, c.year, c.lineName },
		{ "num_model", "full", "letter", "-", " | ", 4, 1, "type", "after", "full" })
	eq({ c.takeOver, c.renumberNext, c.budget, c.debug }, { false, false, 10, false })
	for _, l in ipairs(Settings.LETTERS) do eq(c.enabled[l], true, l) end
	c = cfgOf({ ["bavr.format"] = 7, ["bavr.digits"] = 1.0, ["bavr.speed"] = 3, ["bavr.type.heli"] = 1,
		["bavr.takeOver"] = 2, sqperf_log = 2 })
	eq({ c.format, c.digits, c.budget, c.enabled.H, c.enabled.B, c.takeOver, c.debug },
		{ "model_line_num", 1, 25, false, true, true, true })
	for _, bad in ipairs({ 0, 8, 1.5, -1, "x", 0 / 0, math.huge }) do
		eq(rawOf({ ["bavr.format"] = bad }).format, "num_model", tostring(bad))
	end
	for _, it in ipairs(Settings.ITEMS) do
		for i = 1, #it.opts do
			eq(rawOf({ [it.key] = i })[it.name], it.opts[i], it.key .. " " .. i)
		end
	end
end)

test("settings: the hash moves with every render setting and the full words, not with budget or types", function()
	local base = cfgOf({}).hash
	eq(cfgOf({ ["bavr.speed"] = 3, ["bavr.type.bus"] = 1, ["bavr.takeOver"] = 2 }).hash, base)
	local seen = { [base] = true }
	for _, k in ipairs({ "bavr.format", "bavr.model", "bavr.prefix", "bavr.numSep", "bavr.partSep", "bavr.digits",
		"bavr.counter", "bavr.year", "bavr.lineName" }) do
		local h = cfgOf({ [k] = 2 }).hash
		ok(not seen[h], k)
		seen[h] = true
	end
	local full = cfgOf({ ["bavr.prefix"] = 3 })
	local de = P({ ["bavr.prefix"] = 3 }, { T = "Lkw" })
	ok(full.hash ~= de.hash, "translated words re-render")
	eq(de.words.T, "Lkw")
	eq(de.words.B, "Bus", "missing words stay English")
end)

---------------------------------------------------------------------------
-- UTF-8, shortening

test("utf8: length and prefix never split a character", function()
	eq(Text.ulen(""), 0)
	eq(Text.ulen("Citaro"), 6)
	eq(Text.ulen("Škoda Électrique"), 16)
	eq(Text.ulen("新幹線 N700系"), 9)
	eq(Text.uprefix("Škoda", 1), "Š")
	eq(Text.uprefix("新幹線", 2), "新幹")
	eq(Text.uprefix("abc", 10), "abc")
	eq(Text.uprefix("abc", 0), "")
	eq(Text.cut("Mercedes-Benz Citaro", 14), "Mercedes-Benz", "trailing space dropped")
	eq(Text.cut("Bus · Express", 5), "Bus", "a trailing middle dot is dropped whole")
	eq(Text.cut("Taķ", 3), "Taķ", "ķ ends in the byte of · (B7): kept")
	eq(Text.cut("Taķx", 3), "Taķ")
	ok(utf8ok(Text.cut("Taķx", 3)))
end)

test("model name modes: full, short (drop the first word), first word, up to 12 characters", function()
	local function m(mode, s) return Text.modelName(cfgOf({ ["bavr.model"] = mode }), s) end
	eq(m(1, "Mercedes-Benz Citaro"), "Mercedes-Benz Citaro")
	eq(m(2, "Mercedes-Benz Citaro"), "Citaro")
	eq(m(2, "Sternwheeler"), "Sternwheeler", "one word stays")
	eq(m(3, "Mercedes-Benz Citaro"), "Mercedes-Benz")
	eq(m(4, "Mercedes-Benz Citaro"), "Mercedes-Ben")
	eq(m(4, "  Class 101  "), "Class 101", "trimmed")
	eq(m(1, ""), nil)
	eq(m(1, nil), nil)
end)

test("line name modes: full, up to 12 characters, first number else full", function()
	local function l(mode, s) return Text.lineName(cfgOf({ ["bavr.lineName"] = mode }), s) end
	eq(l(1, "Bus 12 Central - Harbor"), "Bus 12 Central - Harbor")
	eq(l(2, "Bus 12 Central - Harbor"), "Bus 12 Centr")
	eq(l(3, "Bus 12 Central - Harbor"), "12")
	eq(l(3, "Harbor Express"), "Harbor Express")
	eq(l(1, " "), nil)
end)

test("default names: the game's '<word> <number>', empty, and optional word sets", function()
	for _, s in ipairs({ "Road Vehicle 263", "Train 13", "Ship 76", "Aircraft 2", "", "Straßenfahrzeug 4" }) do
		eq(Text.isDefault(s), true, s)
	end
	for _, s in ipairs({ "AMO F-15", "Citaro B-0412", "B-0412", "12", "My bus", "Train 13a" }) do
		eq(Text.isDefault(s), false, s)
	end
	eq(Text.isDefault(nil), true)
	local words = { ["Road Vehicle"] = true, Train = true }
	eq(Text.isDefault("Train 13", words), true)
	eq(Text.isDefault("Express 5", words), false, "pattern matches, word unknown")
end)

---------------------------------------------------------------------------
-- Render

test("render: the plan's examples", function()
	local function r(t, model, line, letter, n, year)
		return Text.render(cfgOf(t), model, line, letter, n, year)
	end
	eq(r({}, "Sternwheeler", nil, "S", 12), "Sternwheeler S-0012")
	eq(r({}, "Citaro", "Bus 12", "B", 412), "Citaro B-0412")
	eq(r({ ["bavr.format"] = 2 }, "Citaro", nil, "B", 412), "B-0412 Citaro")
	eq(r({ ["bavr.format"] = 3 }, "Citaro", nil, "B", 412), "B-0412")
	eq(r({ ["bavr.format"] = 4 }, "Citaro", nil, "B", 412), "Citaro (B-0412)")
	eq(r({ ["bavr.format"] = 5 }, "Citaro", "Bus 12", "B", 412), "Bus 12 · B-0412")
	eq(r({ ["bavr.format"] = 6 }, "Citaro", "Bus 12", "B", 412), "B-0412 · Bus 12")
	eq(r({ ["bavr.format"] = 7 }, "Citaro", "Bus 12", "B", 412), "Citaro · Bus 12 · B-0412")
	eq(r({ ["bavr.format"] = 5 }, "Citaro", nil, "B", 412), "Citaro B-0412", "no line: the model")
	eq(r({ ["bavr.format"] = 6 }, "Citaro", nil, "B", 412), "B-0412 Citaro", "no line: the model")
	eq(r({ ["bavr.format"] = 7 }, "Citaro", nil, "B", 412), "Citaro B-0412", "no line: the model")
	eq(r({ ["bavr.prefix"] = 2 }, "Citaro", nil, "T", 412), "Citaro Trk-0412")
	eq(r({ ["bavr.prefix"] = 3 }, "AW101", nil, "H", 3), "AW101 Helicopter-0003")
	eq(r({ ["bavr.prefix"] = 4 }, "Citaro", nil, "B", 412), "Citaro 0412")
	eq(r({ ["bavr.numSep"] = 2 }, "Citaro", nil, "B", 412), "Citaro B0412")
	eq(r({ ["bavr.numSep"] = 3 }, "Citaro", nil, "B", 412), "Citaro B 0412")
	eq(r({ ["bavr.numSep"] = 4 }, "Citaro", nil, "B", 412), "Citaro B.0412")
	eq(r({ ["bavr.numSep"] = 5 }, "Citaro", nil, "B", 412), "Citaro B/0412")
	eq(r({ ["bavr.partSep"] = 2 }, "Citaro", nil, "B", 412), "Citaro · B-0412")
	eq(r({ ["bavr.partSep"] = 5, ["bavr.format"] = 7 }, "Citaro", "Bus 12", "B", 4), "Citaro, Bus 12, B-0004")
	eq(r({ ["bavr.digits"] = 1 }, "Citaro", nil, "B", 412), "Citaro B-412")
	eq(r({ ["bavr.digits"] = 5 }, "Citaro", nil, "B", 412), "Citaro B-00412")
	eq(r({ ["bavr.digits"] = 2 }, "Citaro", nil, "B", 412), "Citaro B-412", "more digits than asked: all shown")
	eq(r({ ["bavr.year"] = 2 }, "Citaro", nil, "B", 412, 1925), "Citaro B-0412 (1925)")
	eq(r({ ["bavr.year"] = 3 }, "Citaro", nil, "B", 412, 1925), "Citaro 1925-0412")
	eq(r({ ["bavr.year"] = 2 }, "Citaro", nil, "B", 412, nil), "Citaro B-0412", "no year known")
	eq(r({}, nil, nil, "B", 412), "B-0412", "no model name")
end)

local LONG_MODEL = "Ein sehr langer Modellname für Überlandbusse mit Gelenk und Anhänger"
local CJK_MODEL = "新幹線電車ＮＳＶ７００系統長距離高速列車特別仕様車両型式番号一二三四五六七八九十"
local MODELS = { "Citaro", LONG_MODEL, CJK_MODEL, "Škoda 15T ForCity Alfa Riga", nil }
local LINES = { nil, "Bus 12", "Línea 7 Plaza de España – Estación Central de Autobuses Interurbanos", "東京駅 ⇄ 新大阪駅 特急" }

test("render sweep: every format x prefix x separators x digits x year (x counting, marker, train length) stays within 50 UTF-8 characters, keeps the number", function()
	local STRIDE = FULL and 1 or 7
	local idx, checked = 0, 0
	local letters = { "B", "T", "R", "L", "S", "A", "H" }
	local hit = { counter = {}, old = {}, trainLen = {} }
	for f = 1, 7 do for p = 1, 4 do for ns = 1, 5 do for ps = 1, 5 do for d = 1, 5 do for y = 1, 3 do
		idx = idx + 1
		-- every value of every param is hit in quick mode too: the stride walks a product whose sizes are coprime to 7
		if idx % STRIDE == 0 or (f == 1 and p == 1 and ns == 1 and ps == 1 and d == 4 and y == 1) then
			-- the new settings ride along: counting (4 values, incl. Per line), old marker (4), train length (3)
			local counter, oldM, tl = 1 + idx % 4, 1 + (idx // 3) % 4, 1 + (idx // 5) % 3
			hit.counter[counter], hit.old[oldM], hit.trainLen[tl] = true, true, true
			local cfg = cfgOf({ ["bavr.format"] = f, ["bavr.prefix"] = p, ["bavr.numSep"] = ns, ["bavr.partSep"] = ps,
				["bavr.digits"] = d, ["bavr.year"] = y, ["bavr.model"] = 1 + idx % 4, ["bavr.lineName"] = 1 + idx % 3,
				["bavr.counter"] = counter, ["bavr.old"] = oldM, ["bavr.trainLen"] = tl })
			for mi = 1, 5 do for li = 1, 4 do
				local model = Text.modelName(cfg, MODELS[mi])
				local line = Text.lineName(cfg, LINES[li])
				local letter = letters[1 + (idx + mi) % 7]
				local n = ({ 1, 412, 99999, 123456 })[1 + (mi + li) % 4]
				local isOld = (mi + li) % 2 == 0
				local count = Text.trainCount(cfg, letter == "L" and 1 or 0, 9, 8)
				local perLine = cfg.counter == "line" and line ~= nil
				local s = Text.render(cfg, model, line, letter, n, 1925, isOld, count, perLine)
				local fid = perLine and ("#" .. Text.number(n, math.min(d, Text.LINE_DIGITS)))
					or Text.fleetId(cfg, letter, n, 1925)
				ok(Text.ulen(s) <= Text.MAX_CHARS, s)
				ok(s:find(fid, 1, true) ~= nil, "number kept: " .. s)
				ok(utf8ok(s), "valid UTF-8: " .. s:gsub("[\128-\255]", function(c) return string.format("\\x%02X", c:byte()) end))
				ok(not s:find("^%s") and not s:find("%s$"), "no outer spaces: '" .. s .. "'")
				if y == 2 or (y == 3 and perLine) then ok(s:find("(1925)", 1, true) ~= nil, "year kept: " .. s) end
				if isOld and cfg.oldMark ~= "" then
					ok(s:sub(-#cfg.oldMark) == cfg.oldMark, "marker kept at the end: " .. s)
				else
					ok(cfg.oldMark == "" or not s:find(cfg.oldMark, 1, true), "no marker: " .. s)
				end
				if count ~= nil then
					local cs = (cfg.trainLen == "units" and "\195\151" or "+") .. count
					ok(s:find(cs, 1, true) ~= nil, "count kept: " .. s)
				end
				checked = checked + 1
			end end
		end
	end end end end end end
	ok(checked > 1000, "checked " .. checked)
	eq({ #hit.counter, #hit.old, #hit.trainLen }, { 4, 4, 3 }, "every new value hit")
end)

test("render cap: the model is cut first, then the line, never the number", function()
	local cfg = cfgOf({ ["bavr.format"] = 7 })
	local s = Text.render(cfg, LONG_MODEL, "Bus 12", "B", 412)
	eq(Text.ulen(s) <= 50, true)
	ok(s:sub(-#" · Bus 12 · B-0412") == " · Bus 12 · B-0412", s)
	local longLine = string.rep("Linie ", 12)
	s = Text.render(cfg, "Citaro", longLine, "B", 412)
	ok(s:find("Citaro · Linie", 1, true) == 1 and s:sub(-6) == "B-0412", s)
	s = Text.render(cfg, LONG_MODEL, longLine, "B", 412)
	ok(s:sub(-6) == "B-0412" and Text.ulen(s) <= 50, s)
	s = Text.render(cfgOf({}), CJK_MODEL .. CJK_MODEL, nil, "L", 7)
	eq(Text.ulen(s), 50)
	ok(utf8ok(s))
end)

test("byte loops are capped at MAX_BYTES: a huge name never runs away", function()
	local huge = string.rep("é", Text.MAX_BYTES) -- 2 * MAX_BYTES bytes
	eq(Text.ulen(huge), Text.MAX_BYTES / 2, "counted up to the cap")
	eq(#Text.uprefix(huge, 1e9), Text.MAX_BYTES, "cut at the cap")
	eq(Text.isDefault(string.rep("a", Text.MAX_BYTES) .. " 1"), false, "over the cap: not a default name")
	local s = Text.render(cfgOf({}), huge, nil, "B", 1)
	ok(Text.ulen(s) <= Text.MAX_CHARS and s:sub(-6) == "B-0001", "rendered within the cap")
end)

test("render: the default name is number | model (year)", function()
	local c = rawOf(nil)
	eq(Text.render(c, "Daimler Deck Seat Car", nil, "B", 205, 1934), "B-0205 | Daimler Deck Seat Car (1934)")
	eq(Text.render(c, "Daimler Deck Seat Car", "Bus 12", "B", 205, nil), "B-0205 | Daimler Deck Seat Car")
end)

---------------------------------------------------------------------------
-- Per line counting, old-vehicle marker, train length (PLAN.md "Per line counting", "Old-vehicle marker", "Train
-- length")

test("settings: the new options default to Off / unchanged and move the hash", function()
	local c = rawOf(nil)
	eq({ c.counter, c.old, c.trainLen, c.oldMark }, { "type", "off", "off", "" })
	local base = c.hash
	local seen = { [base] = true }
	for _, t in ipairs({ { ["bavr.counter"] = 4 }, { ["bavr.old"] = 2 }, { ["bavr.old"] = 3 }, { ["bavr.old"] = 4 },
		{ ["bavr.trainLen"] = 2 }, { ["bavr.trainLen"] = 3 } }) do
		local h = rawOf(t).hash
		ok(not seen[h], "hash moves")
		seen[h] = true
	end
	eq(rawOf({ ["bavr.old"] = 2 }).oldMark, "\226\140\155", "hourglass U+231B")
	eq(rawOf({ ["bavr.old"] = 3 }).oldMark, "*")
	eq(rawOf({ ["bavr.old"] = 4 }).oldMark, "(old)")
	local de = Settings.parse({ ["bavr.old"] = 4 }, { O = "(alt)" })
	eq(de.oldMark, "(alt)", "the translated word")
	ok(de.hash ~= rawOf({ ["bavr.old"] = 4 }).hash, "a translated word re-renders")
	eq(de.needWords, true)
	eq(rawOf({ ["bavr.old"] = 3 }).needWords, false)
	eq(rawOf({ ["bavr.prefix"] = 3 }).needWords, true)
end)

test("render per line: <line> #NN in place of the type prefix, in every format; no line falls back", function()
	local function r(t, model, line, n, year, perLine)
		t["bavr.counter"] = 4
		return Text.render(rawOf(t), model, line, "B", n, year, false, nil, perLine ~= false)
	end
	-- the defaults (Number + model, bar, year after)
	eq(r({}, "Citaro", "Bus 12", 3, 1925), "Bus 12 #03 | Citaro (1925)")
	eq(r({ ["bavr.format"] = 1 }, "Citaro", "Bus 12", 3, 1925), "Citaro | Bus 12 #03 (1925)")
	eq(r({ ["bavr.format"] = 3 }, "Citaro", "Bus 12", 3, 1925), "Bus 12 #03 (1925)")
	eq(r({ ["bavr.format"] = 4 }, "Citaro", "Bus 12", 3, 1925), "Citaro (Bus 12 #03) (1925)")
	eq(r({ ["bavr.format"] = 5 }, "Citaro", "Bus 12", 3, 1925), "Bus 12 #03 (1925)", "the line shows once")
	eq(r({ ["bavr.format"] = 6 }, "Citaro", "Bus 12", 3, 1925), "Bus 12 #03 (1925)")
	eq(r({ ["bavr.format"] = 7 }, "Citaro", "Bus 12", 3, 1925), "Citaro | Bus 12 #03 (1925)")
	eq(r({ ["bavr.format"] = 1, ["bavr.partSep"] = 1, ["bavr.year"] = 1 }, "Citaro", "Bus 12", 3), "Citaro Bus 12 #03")
	eq(r({ ["bavr.year"] = 3 }, "Citaro", "Bus 12", 3, 1925), "Bus 12 #03 | Citaro (1925)",
		"Before the number: the line has the prefix's place, the year goes after")
	eq(r({ ["bavr.digits"] = 1 }, "Citaro", "Bus 12", 3, nil), "Bus 12 #3 | Citaro")
	eq(r({ ["bavr.digits"] = 5 }, "Citaro", "Bus 12", 3, nil), "Bus 12 #03 | Citaro", "padded to 2 at most")
	eq(r({}, "Citaro", "Bus 12", 112, nil), "Bus 12 #112 | Citaro")
	eq(r({ ["bavr.lineName"] = 3 }, "Citaro", Text.lineName(rawOf({ ["bavr.lineName"] = 3 }), "Bus 12 Harbor"), 3, nil),
		"12 #03 | Citaro", "Line number only")
	eq(Text.render(rawOf({ ["bavr.counter"] = 4 }), "Citaro", nil, "B", 205, 1925, false, nil, true),
		"B-0205 | Citaro (1925)", "no line: the per-type number with its prefix")
	local long = string.rep("Harbor ", 10)
	local s = r({}, "Mercedes-Benz Citaro", long, 7, 1925)
	ok(Text.ulen(s) <= 50 and s:find(" #07 | ", 1, true) and s:sub(-6) == "(1925)", s)
end)

test("render: the old marker goes at the very end and is never cut", function()
	local function r(old, t, model, line, year)
		t["bavr.old"] = old
		return Text.render(rawOf(t), model, line, "B", 412, year, true)
	end
	eq(r(2, {}, "Citaro", nil, 1925), "B-0412 | Citaro (1925) \226\140\155")
	eq(r(3, {}, "Citaro", nil, 1925), "B-0412 | Citaro (1925) *")
	eq(r(4, {}, "Citaro", nil, 1925), "B-0412 | Citaro (1925) (old)")
	eq(r(1, {}, "Citaro", nil, 1925), "B-0412 | Citaro (1925)", "Off: no marker")
	eq(Text.render(rawOf({ ["bavr.old"] = 3 }), "Citaro", nil, "B", 412, 1925, false), "B-0412 | Citaro (1925)",
		"not old: no marker")
	local s = r(4, { ["bavr.format"] = 7 }, string.rep("Long model ", 6), "Bus 12", 1925)
	ok(Text.ulen(s) <= 50 and s:sub(-#" (1925) (old)") == " (1925) (old)" and s:find("B-0412", 1, true), s)
end)

test("train length: RAIL only; wagons count unpowered parts (> 0), units every part (> 1); never cut", function()
	local w, u = rawOf({ ["bavr.trainLen"] = 2 }), rawOf({ ["bavr.trainLen"] = 3 })
	eq(Text.trainCount(w, 1, 9, 8), 8)
	eq(Text.trainCount(w, 1, 4, 0), nil, "a multiple unit with every car powered: nothing")
	eq(Text.trainCount(u, 1, 9, 8), 9)
	eq(Text.trainCount(u, 1, 1, 0), nil, "a lone loco: nothing")
	eq(Text.trainCount(w, 2, 3, 2), nil, "trams are not trains")
	eq(Text.trainCount(w, 0, 2, 1), nil, "road")
	eq(Text.trainCount(rawOf(nil), 1, 9, 8), nil, "Off")
	eq(Text.render(w, "Class 101", nil, "L", 45, 1911, false, 8), "L-0045 | Class 101 +8 (1911)")
	eq(Text.render(u, "Class 101", nil, "L", 45, 1911, false, 9), "L-0045 | Class 101 \195\151" .. "9 (1911)")
	eq(Text.render(rawOf({ ["bavr.trainLen"] = 2, ["bavr.format"] = 3 }), "Class 101", nil, "L", 45, nil, false, 8),
		"L-0045 +8", "no model in the format: after the number")
	eq(Text.render(rawOf({ ["bavr.trainLen"] = 2, ["bavr.counter"] = 4, ["bavr.old"] = 3 }), "Class 101", "IC 5", "L",
		2, 1911, true, 8, true), "IC 5 #02 | Class 101 +8 (1911) *", "all three together")
	local s = Text.render(w, CJK_MODEL, nil, "L", 45, 1911, false, 12)
	ok(Text.ulen(s) == 50 and s:find(" +12 (1911)", 1, true), s)
end)

test("render cap without a model: the long line is cut once, never copied into the model's place", function()
	local long = string.rep("Linie ", 12)
	local s = Text.render(cfgOf({ ["bavr.format"] = 7 }), nil, long, "B", 412)
	local _, seps = s:gsub(" \194\183 ", "")
	ok(Text.ulen(s) <= 50 and s:sub(-6) == "B-0412", s)
	eq(seps, 1, "line · number, the line once: " .. s)
end)
