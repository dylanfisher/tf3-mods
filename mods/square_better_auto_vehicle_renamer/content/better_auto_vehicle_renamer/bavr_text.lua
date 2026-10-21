-- Better Auto Vehicle Renamer: name text. UTF-8 helpers (no utf8 library: the game's Lua is pre-5.3), model and line
-- name shortening, the default-name test, and rendering one vehicle's name. Pure: no api.*, Lua 5.1 syntax.
-- PLAN.md "Naming one vehicle", "Hand-typed names", "Settings".
--
-- Entry points:
--   Text.render(cfg, model, line, letter, number, year [, old, count, perLine]) -> name   (cfg from Settings.parse;
--       model / line display strings or nil; number >= 0; year number or nil; old: past its lifespan (the marker
--       cfg.oldMark goes at the end); count: the train length to show (Text.trainCount) or nil; perLine: number is
--       the position on the line (counting "Per line"), shown as "<line> #NN" in place of the type prefix, needs
--       line). At most MAX_CHARS UTF-8 characters: the model is cut first, then the line, never the number, the
--       year, the marker or the count.
--   Text.trainCount(cfg, carrier, parts, wagons) -> count to show or nil (RAIL only; PLAN.md "Train length").
--   Text.modelName(cfg, full) / Text.lineName(cfg, full): the shortened forms per setting (cache them per id).
--   Text.isDefault(name [, words]): the game's default name ("Road Vehicle 263", "Train 13"), or empty.
--   Text.ulen(s), Text.uprefix(s, n): UTF-8 length and the first n characters.

local M = {}

M.MAX_CHARS = 50     -- the base text field's cap (Destination Displays' utf8Prefix)
M.CUT_CHARS = 12     -- "Up to 12 characters" (model and line name)
M.MAX_WORDS = 64     -- loop cap on word splits
M.MAX_BYTES = 4096   -- longer input is cut first (no name is that long; a cap on every byte loop)

--- Number of UTF-8 characters in s (bytes that are not continuation bytes). Allocates nothing.
function M.ulen(s)
	local n, len = 0, #s
	if len > M.MAX_BYTES then len = M.MAX_BYTES end
	for i = 1, len do
		local b = string.byte(s, i)
		if b < 128 or b >= 192 then n = n + 1 end
	end
	return n
end

--- The first n UTF-8 characters of s (never splits a character); s itself when it is short enough.
function M.uprefix(s, n)
	if n <= 0 then return "" end
	local len, count = #s, 0
	if len > M.MAX_BYTES then len = M.MAX_BYTES end
	for i = 1, len do
		local b = string.byte(s, i)
		if b < 128 or b >= 192 then
			count = count + 1
			if count > n then return string.sub(s, 1, i - 1) end
		end
	end
	return len < #s and string.sub(s, 1, len) or s
end

-- ASCII white space only: %s follows the C locale's isspace, which may take byte 0xA0 (the second byte of "Š")
local SP, NSP = "[ \t\r\n]", "[^ \t\r\n]"
M.SP, M.NSP = SP, NSP

local function trim(s)
	return (string.gsub(string.gsub(s, "^" .. SP .. "+", ""), SP .. "+$", ""))
end
M.trim = trim

--- Cut to n characters, without a trailing space or separator left at the end ("·" is matched whole: a byte class
--- would also strip the last byte of another character).
local DOT = "\194\183" -- "·"
local function cut(s, n)
	if M.ulen(s) <= n then return s end
	local r = M.uprefix(s, n)
	for _ = 1, 8 do -- cap: each round strips one kind of tail
		local before = r
		r = string.gsub(r, "[ \t\r\n%-%.,/|]+$", "")
		if string.sub(r, -2) == DOT then r = string.sub(r, 1, -3) end
		if r == before then break end
	end
	return r
end
M.cut = cut

--- The model name per the "Model name" setting: full / short (drop the first word when there are 2+) / first
--- (first word) / cut (up to CUT_CHARS characters).
function M.modelName(cfg, full)
	if type(full) ~= "string" then return nil end
	full = trim(full)
	if full == "" then return nil end
	local mode = cfg.model
	if mode == "short" or mode == "first" then
		local first, rest = string.match(full, "^(" .. NSP .. "+)" .. SP .. "+(.+)$")
		if first == nil then return full end
		return mode == "first" and first or rest
	elseif mode == "cut" then
		return cut(full, M.CUT_CHARS)
	end
	return full
end

--- The line name per the "Line name in names" setting: full / cut / number (the first number in it, else full).
function M.lineName(cfg, full)
	if type(full) ~= "string" then return nil end
	full = trim(full)
	if full == "" then return nil end
	local mode = cfg.lineName
	if mode == "cut" then return cut(full, M.CUT_CHARS) end
	if mode == "number" then return string.match(full, "%d+") or full end
	return full
end

local DEFAULT_PAT = "^%D.-" .. SP .. "%d+$" -- the plan's `^%D.-%s%d+$` with an ASCII-only %s
local STEM_PAT = "^(.-)" .. SP .. "+%d+$"

--- True for the game's default vehicle name "<carrier word> <number>" (`^%D.-%s%d+$`, console 2026-10-20) and for an
--- empty name. words (optional set { ["Road Vehicle"] = true, ... }): when given, the word part must be one of them.
function M.isDefault(name, words)
	if name == nil or name == "" then return true end
	if #name > M.MAX_BYTES then return false end
	if not string.find(name, DEFAULT_PAT) then return false end
	if words == nil then return true end
	local stem = string.match(name, STEM_PAT)
	return stem ~= nil and words[stem] == true
end

-- zero-padded number formats per digit count
local NUMFMT = {}
for d = 1, 9 do NUMFMT[d] = "%0" .. d .. "d" end

--- The number with at least `digits` digits.
function M.number(n, digits)
	return string.format(NUMFMT[digits] or "%d", math.floor(n))
end

--- The fleet id: prefix + separator + padded number ("B-0412", "0412", "1925-0412").
function M.fleetId(cfg, letter, number, year)
	local p
	if cfg.year == "before" and year ~= nil then
		p = tostring(math.floor(year))
	elseif cfg.prefix == "letter" then
		p = letter
	elseif cfg.prefix == "short" then
		p = cfg.short[letter] or letter
	elseif cfg.prefix == "full" then
		p = cfg.words[letter] or letter
	else
		p = ""
	end
	local num = M.number(number, cfg.digits)
	if p == "" then return num end
	return p .. cfg.numSep .. num
end

local function sepModel(cfg) return cfg.partSep == "auto" and " " or cfg.partSep end
local function sepLine(cfg) return cfg.partSep == "auto" and " · " or cfg.partSep end

-- The layout of a format: which pieces it shows, in order (m model, l line, i fleet id, p "model (id)").
-- A line format without a line falls back to the model (PLAN.md "Settings").
local KINDS = { model_num = "mi", num_model = "im", num = "i", model_paren = "mp", line_num = "li", num_line = "il",
	model_line_num = "mli" }
local function kindsOf(fmt, hasLine)
	if not hasLine then
		if fmt == "num_line" then return "im" end
		if fmt == "line_num" or fmt == "model_line_num" then return "mi" end
	end
	return KINDS[fmt] or "mi"
end
M.kindsOf = kindsOf

local function join(m, l, id, tail, kinds, sm, sl)
	local s
	if kinds == "mi" then
		s = m and (m .. sm .. id) or id
	elseif kinds == "im" then
		s = m and (id .. sm .. m) or id
	elseif kinds == "i" then
		s = id
	elseif kinds == "mp" then
		s = m and (m .. " (" .. id .. ")") or id
	elseif kinds == "li" then
		s = l and (l .. sl .. id) or id
	elseif kinds == "il" then
		s = l and (id .. sl .. l) or id
	else -- mli
		if m and l then
			s = m .. sl .. l .. sl .. id
		elseif m then
			s = m .. sl .. id
		elseif l then
			s = l .. sl .. id
		else
			s = id
		end
	end
	if tail then s = s .. tail end
	return s
end

-- Counting "Per line": the line is part of the fleet id ("Bus 12 #03"), so the formats that show the line on its own
-- show only the id there (no line twice)
local LINE_KINDS = { mi = "mi", im = "im", i = "i", mp = "mp", li = "i", il = "i", mli = "mi" }
M.LINE_DIGITS = 2 -- per-line positions are padded to at most this many digits (#03; "Number digits" 1: #3)

--- The train length to show (setting "Train length"): RAIL vehicles only; "wagons" counts the parts without power
--- (wagons, coaches, unpowered trailers; locos, power cars and powered multiple-unit cars are not counted), shown
--- when > 0; "units" counts every part of the consist, shown when > 1. nil when nothing is shown.
function M.trainCount(cfg, carrier, parts, wagons)
	if cfg.trainLen == "off" or carrier ~= 1 then return nil end -- 1 = Carrier RAIL
	if cfg.trainLen == "wagons" then
		if type(wagons) == "number" and wagons > 0 then return wagons end
		return nil
	end
	if type(parts) == "number" and parts > 1 then return parts end
	return nil
end

--- The vehicle's name (see the header). model / line: display strings already shortened per setting, or nil.
function M.render(cfg, model, line, letter, number, year, old, count, perLine)
	perLine = perLine == true and line ~= nil
	local id, lineNum
	if perLine then
		lineNum = "#" .. M.number(number, math.min(cfg.digits or 2, M.LINE_DIGITS))
	else
		id = M.fleetId(cfg, letter, number, year)
	end
	local kinds = kindsOf(cfg.format, line ~= nil)
	if perLine then kinds = LINE_KINDS[kinds] or kinds end
	local usesModel = kinds == "mi" or kinds == "im" or kinds == "mp" or kinds == "mli"
	local usesLine = perLine or kinds == "li" or kinds == "il" or kinds == "mli"
	local m = usesModel and model or nil
	local l = usesLine and line or nil
	local sm, sl = sepModel(cfg), sepLine(cfg)
	-- never cut: the count (after the model, else after the id), the year after the name, the marker at the end
	local cs = nil
	if count ~= nil then
		cs = (cfg.trainLen == "units" and " \195\151" or " +") .. tostring(math.floor(count)) -- " ×9" / " +8"
	end
	local yearOn = year ~= nil and (cfg.year == "after" or (cfg.year == "before" and perLine))
	local tail = yearOn and (" (" .. tostring(math.floor(year)) .. ")") or nil
	if old and cfg.oldMark ~= nil and cfg.oldMark ~= "" then tail = (tail or "") .. " " .. cfg.oldMark end
	local function build()
		local fid = id
		if perLine then fid = l and (l .. " " .. lineNum) or lineNum end
		local mm = m
		if cs ~= nil then
			if mm ~= nil then mm = mm .. cs else fid = fid .. cs end
		end
		return join(mm, (not perLine) and l or nil, fid, tail, kinds, sm, sl)
	end
	local s = build()
	local over = M.ulen(s) - M.MAX_CHARS
	if over <= 0 then return s end
	-- shorten the model to CUT_CHARS, then the line to CUT_CHARS, then the model, then the line down to nothing (a
	-- piece cut to nothing is dropped with its separator); the number, year, marker and count are never cut
	for stage = 1, 4 do
		local isModel = stage == 1 or stage == 3
		-- (not `isModel and m or l`: with no model that picked the line and cut it into the model's place)
		local piece
		if isModel then piece = m else piece = l end
		if piece ~= nil then
			local floor = stage <= 2 and M.CUT_CHARS or 0
			local len = M.ulen(piece)
			local keep = len - over
			if keep < floor then keep = floor end
			if keep < len then
				piece = keep > 0 and cut(piece, keep) or nil
				if piece == "" then piece = nil end
				if isModel then m = piece else l = piece end
				s = build()
				over = M.ulen(s) - M.MAX_CHARS
				if over <= 0 then return s end
			end
		end
	end
	return s
end

return M
