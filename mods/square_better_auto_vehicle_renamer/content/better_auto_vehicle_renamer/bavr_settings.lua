-- Better Auto Vehicle Renamer: mod settings (mod.json params) -> one config table. Pure: no api.* anywhere, Lua 5.1
-- syntax (the game's Lua is pre-5.3). PLAN.md "Settings".
--
-- Entry point (phase 2 game script, phase 3 welcome GUI):
--   Settings.parse(mine [, words]) -> cfg
--     mine:  api.engine.config.getModParams()[MOD_ID] (keys "bavr.*", values 1-based option indices, maybe doubles);
--            nil or garbage gives the defaults.
--     words: optional { B = "Bus", T = "Truck", ..., O = "(old)" } full type words and the "Word" old-vehicle marker
--            (translated by the caller with _(); the English ones below otherwise).
--   cfg fields: format, model, prefix, numSep, partSep, digits, start, counter ("type" | "all" | "model" | "line"),
--   year, old (old-vehicle marker: "off" | "glyph" | "star" | "word"), trainLen ("off" | "wagons" | "units"),
--   lineName (strings / numbers, see ITEMS), takeOver (bool), renumberNext (bool), budget (renames per 2 s window),
--   enabled[letter] (bool), debug (bool), words / short (letter -> word), oldMark (the marker text, "" when off),
--   usesLine (a setting shows the line: a line format or counting "Per line"; "Line name in names" only shapes it;
--   without it the sweep reads no line names and runs no line watch),
--   hash (string of every render-relevant index: an input of the per-vehicle fast path, so a setting changed
--   between loads re-renders our names).

local M = {}

M.MOD_ID = "square_better_auto_vehicle_renamer"

-- Type letters in a fixed order (Classify.LETTERS is the same list).
M.LETTERS = { "B", "T", "R", "L", "S", "A", "H" }

-- One entry per mod.json param: key, option names (index = mod.json value index), default index (1-based).
M.ITEMS = {
	{ name = "format", key = "bavr.format", default = 2, -- i18n: ignore
		opts = { "model_num", "num_model", "num", "model_paren", "line_num", "num_line", "model_line_num" } }, -- i18n: ignore
	{ name = "model", key = "bavr.model", default = 1, opts = { "full", "short", "first", "cut" } }, -- i18n: ignore
	{ name = "prefix", key = "bavr.prefix", default = 1, opts = { "letter", "short", "full", "none" } }, -- i18n: ignore
	{ name = "numSep", key = "bavr.numSep", default = 1, opts = { "-", "", " ", ".", "/" } }, -- i18n: ignore
	-- "auto": a space between model and number, " · " around a line name (the plan's examples)
	{ name = "partSep", key = "bavr.partSep", default = 4, opts = { "auto", " · ", " - ", " | ", ", " } }, -- i18n: ignore
	{ name = "digits", key = "bavr.digits", default = 4, opts = { 1, 2, 3, 4, 5 } }, -- i18n: ignore
	{ name = "start", key = "bavr.start", default = 1, opts = { 1, 100, 1000 } }, -- i18n: ignore
	-- "line": the position on the line (Bus 12 #03), kept beside the three permanent numbers (PLAN.md "Per line")
	{ name = "counter", key = "bavr.counter", default = 1, opts = { "type", "all", "model", "line" } }, -- i18n: ignore
	{ name = "year", key = "bavr.year", default = 2, opts = { "off", "after", "before" } }, -- i18n: ignore
	{ name = "old", key = "bavr.old", default = 1, opts = { "off", "glyph", "star", "word" } }, -- i18n: ignore
	{ name = "trainLen", key = "bavr.trainLen", default = 1, opts = { "off", "wagons", "units" } }, -- i18n: ignore
	{ name = "lineName", key = "bavr.lineName", default = 1, opts = { "full", "cut", "number" } }, -- i18n: ignore
	{ name = "takeOver", key = "bavr.takeOver", default = 1, opts = { false, true } }, -- i18n: ignore
	{ name = "renumberNext", key = "bavr.renumberNext", default = 1, opts = { false, true } }, -- i18n: ignore
	{ name = "budget", key = "bavr.speed", default = 2, opts = { 5, 10, 25 } }, -- i18n: ignore
	{ name = "debug", key = "sqperf_log", default = 1, opts = { false, true } }, -- i18n: ignore
}

-- The per-type on/off params (values Off / On, default On), in LETTERS order.
M.TYPE_KEYS = { "bavr.type.bus", "bavr.type.truck", "bavr.type.tram", "bavr.type.train", "bavr.type.ship", -- i18n: ignore
	"bavr.type.air", "bavr.type.heli" } -- i18n: ignore

-- Settings that change a rendered name (the fast-path hash). counter picks which number shows.
local HASHED = { format = true, model = true, prefix = true, numSep = true, partSep = true, digits = true,
	counter = true, year = true, lineName = true, old = true, trainLen = true }

-- The formats that show the line name (the rest never do: Text.render's kinds)
local LINE_FORMATS = { line_num = true, num_line = true, model_line_num = true } -- i18n: ignore

-- Full type words (Type prefix "Full word"); the game script passes them through _() when that translates there.
M.WORDS = { B = "Bus", T = "Truck", R = "Tram", L = "Train", S = "Ship", A = "Aircraft", H = "Helicopter" } -- i18n: keys
-- Short words (Type prefix "Short word"): abbreviations, kept as they are in every language.
M.SHORT = { B = "Bus", T = "Trk", R = "Trm", L = "Trn", S = "Shp", A = "Air", H = "Hel" } -- i18n: ignore
-- Old-vehicle markers (setting "Mark vehicles past their lifespan"). The hourglass is in the game's Noto Sans CJK
-- but not in Lato (fontTools 2026-10-20): whether names fall back to Noto is a TESTING.md check.
M.OLD_WORD = "(old)" -- i18n: keys
M.MARKS = { glyph = "\226\140\155", star = "*" } -- "⌛" (U+231B), "*"; "word": the translated OLD_WORD

local function index(v, n, default)
	v = tonumber(v)
	if v == nil or v ~= v or v ~= math.floor(v) or v < 1 or v > n then return default end
	return v
end
M.index = index

--- The config for the mod's params table (see the header).
function M.parse(mine, words)
	if type(mine) ~= "table" then mine = {} end
	local cfg, idx = {}, {}
	for i = 1, #M.ITEMS do
		local it = M.ITEMS[i]
		local k = index(mine[it.key], #it.opts, it.default)
		idx[#idx + 1] = HASHED[it.name] and tostring(k) or nil
		cfg[it.name] = it.opts[k]
	end
	cfg.enabled = {}
	for i = 1, #M.LETTERS do
		cfg.enabled[M.LETTERS[i]] = index(mine[M.TYPE_KEYS[i]], 2, 2) == 2
	end
	cfg.short = M.SHORT
	cfg.words = {}
	for i = 1, #M.LETTERS do
		local l = M.LETTERS[i]
		local w = type(words) == "table" and words[l] or nil
		cfg.words[l] = (type(w) == "string" and w ~= "") and w or M.WORDS[l]
	end
	local ow = type(words) == "table" and words.O or nil
	cfg.oldWord = (type(ow) == "string" and ow ~= "") and ow or M.OLD_WORD
	if cfg.old == "word" then
		cfg.oldMark = cfg.oldWord
	else
		cfg.oldMark = M.MARKS[cfg.old] or ""
	end
	-- whether a rendered name can show the line (the sweep's line watch and line name reads)
	cfg.usesLine = cfg.counter == "line" or LINE_FORMATS[cfg.format] == true
	-- whether the GUI's translated words are needed (the game script waits a while for them)
	cfg.needWords = cfg.prefix == "full" or cfg.old == "word"
	-- the words go into the hash too: a game language switch re-renders full-word prefixes and the old marker
	local wl = {}
	if cfg.prefix == "full" then
		for i = 1, #M.LETTERS do wl[i] = cfg.words[M.LETTERS[i]] end
	end
	if cfg.old == "word" then wl[#wl + 1] = cfg.oldWord end
	cfg.hash = table.concat(idx, ".") .. (#wl > 0 and ("|" .. table.concat(wl, ",")) or "")
	return cfg
end

return M
