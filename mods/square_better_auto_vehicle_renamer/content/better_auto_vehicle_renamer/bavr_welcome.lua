-- Better Auto Vehicle Renamer: the welcome window's decision, texts and payloads (bavr_welcome.script.lua draws it).
-- Pure: no api.* (the state read comes in as a function), Lua 5.1 syntax. PLAN.md "First load of a save", "Phase 3".
--
-- Entry points:
--   Welcome.new() -> w; Welcome.tick(w, readFn) -> "wait" | "show" | "done" | "skip"   (one timer tick, ~1 s; the
--       state is read at DELAY_TICKS and then every RETRY_TICKS, at most MAX_TRIES times, then never again)
--       readFn() -> read: { editor = bool } (the map editor), nil (unreadable), or the game-script state's fields
--       { ver, welcome, count, pass, standDown, sdSeen, words } (bavr_register.lua header).
--       After "show" / "done" / "skip", w.kind is "first" | "renumber" | "standDown" (show) and w.reason the log reason.
--   Welcome.decide(read, cfg) -> kind | nil (nothing to show) | false (not decidable yet: the game script has not
--       written its state, or not counted the vehicles yet)
--   Welcome.example(cfg) -> a sample name under the current settings ("B-0412 | Mercedes-Benz Citaro (1925)" by default;
--       "Bus 12 #03 | Mercedes-Benz Citaro (1925)" with counting "Per line")
--   Welcome.payload(answer, number) / Welcome.wordsPayload(words) / Welcome.sdSeenPayload(): the event params
--   Welcome.wordsDiffer(stored, words) -> bool: the GUI's translated words differ from the stored ones
--   Welcome.wrapLine(text, cols): "\n" line breaks (a TextView doesn't wrap without a stylesheet rule)

local Text = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_text.lua"
local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"

local M = {}

M.DELAY_TICKS = 3     -- first state read ~3 s after the game UI is up (the game script has run by then)
M.RETRY_TICKS = 2     -- then every ~2 s while undecided (a paused game: the vehicles are counted once it runs)
M.MAX_TRIES = 300     -- ~10 min of tries, then the window is skipped for this load (logged)
M.WRAP_COLS = 50      -- the dialog's text width in columns (as square_smart_lanes' welcome)

function M.new()
	return { phase = "wait", ticks = 0, tries = 0, kind = nil, reason = nil, read = nil }
end

function M.decide(read, cfg)
	if type(read) ~= "table" or read.ver == nil then return false end
	if read.standDown ~= nil then
		if read.sdSeen == 1 then return nil end
		return "standDown"
	end
	local st = { welcome = read.welcome, pass = read.pass, standDown = nil }
	if read.welcome == nil then
		if read.count == nil then return false end -- not counted yet
		return Reg.welcomeDue(st, cfg, read.count)
	end
	local due = Reg.welcomeDue(st, cfg, read.count)
	if due == "renumber" then
		if read.count == nil then return false end -- counted at the end of the game script's next cycle
		if read.count <= 0 then return nil end      -- nothing left to number
	end
	return due
end

function M.tick(w, readFn, cfg)
	if w.phase == "show" then w.phase = "shown" end
	if w.phase ~= "wait" then return w.phase end
	w.ticks = w.ticks + 1
	if w.ticks < M.DELAY_TICKS or (w.ticks - M.DELAY_TICKS) % M.RETRY_TICKS ~= 0 then return "wait" end
	w.tries = w.tries + 1
	local ok, read = pcall(readFn)
	if ok and type(read) == "table" and read.editor then
		w.phase, w.reason = "done", "editor"
		return w.phase
	end
	if ok then w.read = read end
	local kind = false -- (not `ok and decide() or false`: decide's nil means "nothing to show")
	if ok then kind = M.decide(read, cfg) end
	if kind then
		w.phase, w.kind = "show", kind
	elseif kind == nil then
		w.phase, w.reason = "done", "nothing"
	elseif w.tries >= M.MAX_TRIES then
		w.phase, w.reason = "skip", (ok and type(read) == "table") and "uncounted" or "unreadable"
	end
	return w.phase
end

function M.example(cfg)
	-- counting "Per line": the 3rd vehicle of its line (Bus 12 #03)
	local perLine = cfg.counter == "line"
	return Text.render(cfg, Text.modelName(cfg, "Mercedes-Benz Citaro"), Text.lineName(cfg, "Bus 12"), "B", -- i18n: ignore
		perLine and 3 or 412, 1925, false, nil, perLine)
end

function M.payload(answer, number)
	return { op = "welcome", answer = answer == "apply" and "apply" or "later", number = number == true } -- i18n: ignore
end

function M.wordsPayload(words)
	return { op = "words", words = words } -- i18n: ignore
end

function M.sdSeenPayload()
	return { op = "sdseen" } -- i18n: ignore
end

function M.wordsDiffer(stored, words)
	local w = Reg.cleanWords(words)
	if w == nil then return false end
	return Reg.wordsKey(w) ~= Reg.wordsKey(Reg.cleanWords(stored))
end

--- Breaks a display text into lines of at most `cols` columns with "\n" (square_smart_lanes sl_allmode.lua
--- wrapLine, same rules). Columns: CJK and other wide glyphs count 2. Breaks at a space (dropped); a run with no
--- space (ja / zh) breaks between glyphs, never before closing punctuation. A word longer than cols stays whole on
--- its own line. Existing "\n" kept. Pure, UTF-8 aware; capped at 4000 bytes (longer text is returned as it is).
local CLOSING = { ["、"] = true, ["。"] = true, ["，"] = true, ["："] = true, ["）"] = true, ["」"] = true,
	["』"] = true, ["！"] = true, ["？"] = true, ["；"] = true, ["・"] = true, ["”"] = true }
local function wideGlyph(ch)
	if #ch ~= 3 then return false end
	local b1, b2, b3 = ch:byte(1, 3)
	local cp = (b1 - 0xE0) * 4096 + (b2 - 0x80) * 64 + (b3 - 0x80)
	return (cp >= 0x1100 and cp <= 0x115F) or (cp >= 0x2E80 and cp <= 0xA4CF) or (cp >= 0xAC00 and cp <= 0xD7A3)
		or (cp >= 0xF900 and cp <= 0xFAFF) or (cp >= 0xFE30 and cp <= 0xFE4F) or (cp >= 0xFF00 and cp <= 0xFF60)
		or (cp >= 0xFFE0 and cp <= 0xFFE6)
end
M.wideGlyph = wideGlyph

function M.wrapLine(text, cols)
	if type(text) ~= "string" or #text > 4000 or type(cols) ~= "number" or cols < 4 then return text end
	local out = {}
	for para in (text .. "\n"):gmatch("(.-)\n") do
		local g = {}
		for ch in para:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			local w = wideGlyph(ch) and 2 or 1
			g[#g + 1] = { ch = ch, w = w, wide = w == 2 }
		end
		local lines, cur, curW, lastBreak = {}, {}, 0, nil
		for i = 1, #g do
			local c = g[i]
			if curW + c.w > cols and #cur > 0 and c.ch ~= " " then
				-- break at the last space, else before this glyph (wide text; not before closing punctuation)
				local cut = lastBreak
				if cut == nil and c.wide and not CLOSING[c.ch] then cut = #cur + 1 end
				if cut == nil and c.wide and CLOSING[c.ch] and #cur > 1 then cut = #cur end
				if cut ~= nil then
					local head, rest = {}, {}
					for k = 1, #cur do
						if k < cut then head[#head + 1] = cur[k].ch
						elseif k > cut or cur[k].ch ~= " " then rest[#rest + 1] = cur[k] end
					end
					lines[#lines + 1] = table.concat(head)
					cur, curW, lastBreak = rest, 0, nil
					for k, r in ipairs(cur) do
						curW = curW + r.w
						if r.ch == " " then lastBreak = k end
					end
				end
			end
			cur[#cur + 1] = c
			curW = curW + c.w
			if c.ch == " " then lastBreak = #cur end
		end
		local tail = {}
		for _, r in ipairs(cur) do tail[#tail + 1] = r.ch end
		lines[#lines + 1] = table.concat(tail)
		out[#out + 1] = table.concat(lines, "\n")
	end
	return table.concat(out, "\n")
end

return M
