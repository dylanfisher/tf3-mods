-- Line Manager Plus: the Line Manager's bottom statistics row shows, right of the live Utilization value ("100%"),
-- the line's average utilization over the last 12 game months in the base light blue ("avg 87%"; "avg ~87%" while
-- fewer than 12 months are recorded). Hovering the value or the avg text lists the averages over the last 12 months,
-- 2 years and 5 years, each marked "~" with the months covered while the history is shorter. Always on, no setting.
-- The history is kept in the savegame (GUI save data, part "util", written through lmp_save.lua), so it survives
-- save and load; adding the mod to an old save starts it empty.
--
-- Sampling (M.tick, from the always-mounted host lmp_util_host.script.lua, react.onStepTimer every 1 s):
--   * Driven by GAME time (GAME_TIME.gameTime), never by wall time: a pass starts only when the game time moved on by
--     one interval (a quarter of a calendar month: api.util.getMonthDuration(GAME_SPEED.millisPerDay), the default
--     month when the calendar is frozen or unreadable, as Problem Radar / the Rate Matcher do). The timer keeps
--     firing while paused (docs/findings/gui.md "Always-mounted hosts"), but the game time stands, so no sample.
--   * A pass lists the player's lines (lineSystem.getLinesForPlayer) and samples them at most PER_TICK per tick (a
--     longer list continues at the next ticks, all with the pass's game time). Per line: used and capacity summed
--     over api.engine.util.line.getLineCapacityUsages(line, false) (entries with capacity > 0, as the base cell,
--     cargo_util.tl:894-907). ~10-15 us per line in game (UTIL_PROBE.md).
--   * Per line monthly buckets { used sum, capacity sum } (u[k], c[k]; the last one is the current month, still
--     filling). A month closes at the first pass at least one month (current calendar length) after the month began:
--     every line then gets a new empty bucket. At most MAX_BUCKETS (60 closed months + the current one). Lines not
--     in a finished pass are dropped.
--   * An average over N months is capacity-weighted: sum(used) / sum(capacity) over the current month and the N
--     closed months before it (the base cell's own formula, statistics_react_util.calculateCargoColumnData, applied
--     over time). "Full" once N months are closed; before that "~" and the closed months so far. Nothing while no
--     bucket in the window has capacity.
--
-- Savegame (part "util" of the mod's GUI save data; one writer, lmp_save.lua, merges it with lmp_visible.lua's part):
--   { v = 1, t = <game ms of the last pass>, m = <game ms the current month began>,
--     lines = { "<line id>:<u>,<c>;<u>,<c>;...", ... } }   buckets oldest first, the last the current month
--   Integers only, at most MAX_SAVE_LINES lines of MAX_BUCKETS buckets. Written when a month closed (at the end of
--   that pass), never more often, so a save keeps the history up to the month's first sample. Read once, at the
--   first step after the load. All save I/O runs in M.ioStep (the host's react.onStep, Main Thread), never in M.tick:
--   onStepTimer runs on Main Pool worker threads, where api.gui.* fails with "API is currently restricted"
--   (docs/findings/gui.md "Timers and threads in GUI contexts"; rev 12's first build read there and never saved). M.tick waits for the
--   restore before sampling. Everything is validated: another version, wrong types, NaN, negative or huge numbers,
--   a malformed entry or a time after the save's own game time drop that entry or the whole part (logged), and the
--   history starts empty.
--
-- Hook (M.install, lmp.script.lua's doReplace; probe technique T3, UTIL_PROBE.md): the base recipe
-- LineStatisticDetails (base manager_window.tl:3830-4030; one row per selected line, multi-select included) is
-- file-local, so it can't be replaced. Two module fields are wrapped instead, both looked up at call time:
--   * statistics_react_util.calculateCargoColumnDataForLine: records its line argument while `capture` is on (else a
--     plain pass-through).
--   * engine_react_util.useStepStateTimer: inside LineStatisticDetails, each getter is called once with `capture` on.
--     Only the Utilization getter (makeCoverageState, :3953) calls calculateCargoColumnDataForLine, so a captured line
--     identifies it (the GUI has no debug library to read the getter's upvalues). Then builtin.TextView is swapped
--     until the next useStepStateTimer call: the Utilization value (class "font-scale-body, details-value", text with
--     "%", :3957-3970) is built in between, gets the tooltip, and comes back as a horizontal BoxLayout { value, avg }
--     (avg with the same tooltip). The swap is one-shot and also undone by the next call, outside the target recipe,
--     and at the next host tick.
-- Anything failing falls through to the base cell (logged once).

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local save = ug_require "square_line_manager_plus::/line_manager_plus/lmp_save.lua"

local PREFIX = "[LineManagerPlus] average utilization: "

local warned = {}
local function warnOnce(key, err)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(err) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local M = {}

M.MONTHS = 12 -- the visible "avg" text
M.WINDOWS = { 12, 24, 60 } -- the tooltip's averages, in months
M.MAX_BUCKETS = 61 -- 60 closed months + the current one
M.SAMPLES_PER_MONTH = 4
M.PER_TICK = 100 -- lines sampled per host tick (~1.5 ms at the probe's 15 us per line)
M.MAX_LINES = 5000 -- lines per pass
M.MAX_SAVE_LINES = 2000 -- lines kept in the savegame (~600 bytes each at 61 buckets)
M.MAX_ENTRY_LEN = 4096 -- characters of one saved line entry
M.MAX_VALUE = 1e12 -- a saved sum above this is not ours
M.MAX_CARGO = 200 -- capacity entries per line
M.TIMER_S = 1.0
M.SAVE_PART = "util"
M.FORMAT = 1
M.TARGET = "LineStatisticDetails"
M.VALUE_CLASS = "font-scale-body, details-value"
M.AVG_CLASS = "font-scale-annotation, positive" -- base classes: smaller body text, Positive (jordyBlue, light blue)
M.ENGINE = "::/gui/main/engine_react_util.tl"
M.STATS = "::/gui/statistics/statistics_react_util.tl"

-- history ------------------------------------------------------------------------------------------------------------

-- [line] = { u = { used sums }, c = { capacity sums } }, one entry per month, oldest first, the last the current month
local hist = {}
local lastPassT = nil -- game time of the last pass started
local monthStartT = nil -- game time the current month began
local pass = nil -- { lines, i, t, seen } while a pass is in progress
local dirty = false -- a month closed (or the history was cleared) since the last write
local restored = false -- the saved history was read (once per load)

function M.reset()
	hist, lastPassT, monthStartT, pass = {}, nil, nil, nil
	dirty = true
end

local function newEntry()
	return { u = { 0 }, c = { 0 } }
end

--- Adds one sample to `line`'s current month.
function M.push(line, used, cap)
	local h = hist[line]
	if h == nil then
		h = newEntry()
		hist[line] = h
	end
	local k = #h.u
	h.u[k] = h.u[k] + used
	h.c[k] = h.c[k] + cap
end

--- Closes the current month of every line (a new empty one each; the oldest dropped beyond MAX_BUCKETS).
function M.closeMonth()
	local n = 0
	for _line, h in pairs(hist) do
		n = n + 1
		if n > 2 * M.MAX_LINES then break end
		h.u[#h.u + 1], h.c[#h.c + 1] = 0, 0
		while #h.u > M.MAX_BUCKETS do -- at most one step: one bucket added per close
			table.remove(h.u, 1)
			table.remove(h.c, 1)
		end
	end
	dirty = true
end

--- Months kept for `line` (closed ones + the current one; 0 when none).
function M.buckets(line)
	local h = hist[line]
	return h and #h.u or 0
end

--- `line`'s buckets { u, c } (for tests), or nil.
function M.history(line)
	return hist[line]
end

--- Lines with a history (for tests and the log).
function M.lineCount()
	local n = 0
	for _l in pairs(hist) do n = n + 1 end
	return n
end

--- Game ms per calendar month at the current calendar speed; the default month when the calendar is frozen
--- (millisPerDay 0) or anything is unreadable. nil when no month length can be had at all.
function M.monthMs()
	local ok, ms = pcall(function()
		local gs = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED)
		local mpd = gs and gs.millisPerDay or 0
		if type(mpd) == "number" and mpd > 0 then return api.util.getMonthDuration(math.floor(mpd)) end
		return nil
	end)
	if ok and type(ms) == "number" and ms > 0 and ms == ms then return ms end
	local okD, d = pcall(function() return api.util.getDefaultMonthDuration() end)
	if okD and type(d) == "number" and d > 0 and d == d then return d end
	return nil
end

--- The game time in ms (GAME_TIME.gameTime), or nil.
function M.gameTime()
	local ok, t = pcall(function()
		local c = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
		return c and c.gameTime or nil
	end)
	if ok and type(t) == "number" and t == t then return t end
	return nil
end

--- `line`'s average over `months` (default 12): (fraction 0..1, full, closed) or nil when there's nothing to show.
--- The current month and up to `months` closed months before it count. full: `months` closed months are kept;
--- closed: the closed months counted (at most `months`).
function M.average(line, months)
	months = months or M.MONTHS
	local h = hist[line]
	if h == nil or #h.u == 0 then return nil end
	local k = #h.u
	local first = math.max(1, k - months)
	local used, cap = 0, 0
	for i = first, k do
		used, cap = used + h.u[i], cap + h.c[i]
	end
	if cap <= 0 then return nil end
	local closed = math.min(k - 1, months)
	return used / cap, closed >= months, closed
end

-- savegame -----------------------------------------------------------------------------------------------------------

local function finiteNonNeg(v)
	return type(v) == "number" and v == v and v >= 0 and v <= M.MAX_VALUE
end

local function int(v)
	if not finiteNonNeg(v) then return 0 end
	return math.floor(v + 0.5)
end

--- The saved part for the history now. Errors propagate.
function M.encode()
	local out, n = {}, 0
	for line, h in pairs(hist) do
		if n >= M.MAX_SAVE_LINES then break end
		if type(line) == "number" and line >= 1 and line == math.floor(line) and line <= M.MAX_VALUE then
			local parts = {}
			for i = 1, #h.u do
				parts[i] = string.format("%d,%d", int(h.u[i]), int(h.c[i]))
			end
			n = n + 1
			out[n] = string.format("%d", line) .. ":" .. table.concat(parts, ";")
		end
	end
	return { v = M.FORMAT, t = int(lastPassT), m = int(monthStartT), lines = out }
end

--- One saved line entry -> line, { u, c }; nil when malformed.
local function decodeEntry(s)
	if type(s) ~= "string" or #s > M.MAX_ENTRY_LEN then return nil end
	local id, rest = s:match("^(%d+):([%d,;]+)$")
	if id == nil then return nil end
	local line = tonumber(id)
	if not finiteNonNeg(line) or line < 1 then return nil end
	local u, c, raw, n = {}, {}, {}, 0
	for a, b in rest:gmatch("(%d+),(%d+)") do
		n = n + 1
		if n > M.MAX_ENTRY_LEN then return nil end -- can't happen within the length cap; a hard stop all the same
		local used, cap = tonumber(a), tonumber(b)
		if not (finiteNonNeg(used) and finiteNonNeg(cap)) then return nil end
		u[n], c[n] = math.min(used, cap), cap -- used never exceeds the capacity
		raw[n] = a .. "," .. b
	end
	-- every bucket is "<u>,<c>", separated by ";": anything else (",,", ";;", a trailing ";") is not ours
	if n == 0 or table.concat(raw, ";") ~= rest then return nil end
	return line, u, c, n
end

--- The saved part -> history table, last pass time, month start; or nil and why it was not taken. `now`: the game
--- time of this load (a saved time after it is not this save's). Never errors on bad data.
function M.decode(part, now)
	if part == nil then return nil, "none" end
	if type(part) ~= "table" then return nil, "not a table" end
	if part.v ~= M.FORMAT then return nil, "format " .. tostring(part.v) end
	local t, m = part.t, part.m
	if not (finiteNonNeg(t) and finiteNonNeg(m)) or m > t then return nil, "bad times" end
	if type(now) == "number" and t > now then return nil, "saved after this game time" end
	local lines = part.lines
	if type(lines) ~= "table" then return nil, "no lines" end
	local h, kept, bad = {}, 0, 0
	for i = 1, M.MAX_SAVE_LINES do
		local s = lines[i]
		if s == nil then break end
		local line, u, c, n = decodeEntry(s)
		if line == nil or h[line] ~= nil then
			bad = bad + 1
		else
			while n > M.MAX_BUCKETS do -- keep the newest months
				table.remove(u, 1)
				table.remove(c, 1)
				n = n - 1
			end
			h[line] = { u = u, c = c }
			kept = kept + 1
		end
	end
	return h, t, m, kept, bad
end

local function restore(now)
	restored = true
	local part = save.get(M.SAVE_PART)
	local readErr = save.readError()
	if readErr ~= nil then
		warnOnce("load", readErr)
		return
	end
	if part == nil then return end -- a new game, or a save from before this feature
	local h, t, m, kept, bad = M.decode(part, now)
	if h == nil then
		say("saved history not used (" .. tostring(t) .. "), starting empty")
		return
	end
	hist, lastPassT, monthStartT = h, t, m
	say("restored the history of " .. kept .. " lines" .. (bad > 0 and (" (" .. bad .. " bad entries skipped)") or ""))
end

local function writeSave()
	dirty = false -- one try per month: a failure is not retried every pass
	local okE, part = pcall(M.encode)
	if not okE then
		warnOnce("save", part)
		return
	end
	local ok, err = save.set(M.SAVE_PART, part)
	if not ok then warnOnce("save", err) end
end

-- sampling -----------------------------------------------------------------------------------------------------------

--- used, capacity of `line` now (entries with capacity > 0, at most MAX_CARGO). Errors propagate.
function M.lineUsage(line)
	local caps = api.engine.util.line.getLineCapacityUsages(line, false)
	local used, cap, k = 0, 0, 0
	if caps then
		for _i, c in pairs(caps) do
			k = k + 1
			if k > M.MAX_CARGO then break end
			if c ~= nil and (c.capacity or 0) > 0 then
				used = used + (c.used or 0)
				cap = cap + c.capacity
			end
		end
	end
	return used, cap
end

local function finishPass()
	-- drop lines that no longer exist (not listed in this pass); hist holds at most the lines of the last passes
	local drop, n = {}, 0
	for line in pairs(hist) do
		n = n + 1
		if n > 2 * M.MAX_LINES then break end
		if not pass.seen[line] then drop[#drop + 1] = line end
	end
	for _i, line in ipairs(drop) do hist[line] = nil end
	if pass.capped then
		warnOnce("cap", "more than " .. M.MAX_LINES .. " lines; the rest are not sampled")
	end
	pass = nil
end

local function sliceStep()
	local lines, last = pass.lines, math.min(#pass.lines, M.MAX_LINES)
	local stop = math.min(last, pass.i + M.PER_TICK - 1)
	for i = pass.i, stop do
		local line = lines[i]
		pass.seen[line] = true
		local ok, used, cap = pcall(M.lineUsage, line)
		if ok then
			M.push(line, used, cap)
		else
			warnOnce("sample", used)
		end
	end
	pass.i = stop + 1
	if pass.i > last then finishPass() end
end

--- One host tick: continues a pass in progress, else starts one when the game time moved on by an interval. Never
--- errors.
function M.tick()
	local ok, err = pcall(function()
		M.restoreSwap() -- a render never spans a tick: a swap still standing was missed
		if pass then
			sliceStep()
			return
		end
		local t = M.gameTime()
		if t == nil then return end
		if not restored then return end -- M.ioStep reads the save first (Main Thread)
		local monthMs = M.monthMs()
		if monthMs == nil then
			warnOnce("month", "no month length; not sampling")
			return
		end
		local interval = monthMs / M.SAMPLES_PER_MONTH
		if not (interval > 0) then return end
		if lastPassT ~= nil then
			if t < lastPassT then
				-- game time went back (should not happen within a load): start over
				say("game time went back (" .. tostring(lastPassT) .. " -> " .. tostring(t) .. "), history cleared")
				M.reset()
			elseif t - lastPassT < interval then
				return -- paused (game time stands) or not yet an interval
			end
		end
		if monthStartT == nil or t < monthStartT then
			monthStartT = t
		elseif t - monthStartT >= monthMs then
			M.closeMonth()
			monthStartT = t
		end
		local lines = api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer()) or {}
		lastPassT = t
		pass = { lines = lines, i = 1, t = t, seen = {}, capped = #lines > M.MAX_LINES }
		sliceStep()
	end)
	if not ok then
		pass = nil
		warnOnce("tick", err)
	end
end

--- One Main Thread step (react.onStep, every frame): reads the saved history once (then M.tick starts sampling) and
--- writes it when a month closed and the pass is finished. Two flag checks otherwise. Never errors.
function M.ioStep()
	if restored and not (dirty and pass == nil) then return end
	local ok, err = pcall(function()
		if not restored then
			local t = M.gameTime()
			if t == nil then return end
			local okR, errR = pcall(restore, t)
			if not okR then
				hist, lastPassT, monthStartT = {}, nil, nil
				warnOnce("load", errR)
			end
		elseif dirty and pass == nil then
			writeSave()
		end
	end)
	if not ok then warnOnce("io", err) end
end

-- display ------------------------------------------------------------------------------------------------------------

local function percent(v)
	local ok, s = pcall(function() return api.util.toStringPercentPrecision(v, 0) end)
	if ok and type(s) == "string" then return s end
	return string.format("%d%%", math.floor(v * 100 + 0.5))
end

-- one tooltip line per window; one format string per sentence (CLAUDE.md "Translations")
local function windowLine(months, p, full, closed)
	if months == 12 then
		if full then return string.format(_("Last 12 months: %s"), p) end
		return string.format(_("Last 12 months: ~%s (%d of 12 months)"), p, closed)
	elseif months == 24 then
		if full then return string.format(_("Last 2 years: %s"), p) end
		return string.format(_("Last 2 years: ~%s (%d of 24 months)"), p, closed)
	elseif months == 60 then
		if full then return string.format(_("Last 5 years: %s"), p) end
		return string.format(_("Last 5 years: ~%s (%d of 60 months)"), p, closed)
	end
	return nil
end

--- text, tooltip for `line`, or nil when nothing is to be shown. Errors propagate.
function M.texts(line)
	local avg, full = M.average(line, M.MONTHS)
	if avg == nil then return nil end
	local text = full and string.format(_("avg %s"), percent(avg)) or string.format(_("avg ~%s"), percent(avg))
	local rows = { _("Average utilization:") }
	for _i, months in ipairs(M.WINDOWS) do
		local a, f, closed = M.average(line, months)
		if a ~= nil then rows[#rows + 1] = windowLine(months, percent(a), f, closed) end
	end
	return text, table.concat(rows, "\n")
end

-- the scoped builtin.TextView swap ------------------------------------------------------------------------------------

local swap = { orig = nil, fn = nil, line = nil }
local capture = nil -- { line } while a getter runs under our probe

local function inTarget()
	if type(react.getCallingRecipeCtx) ~= "function" or react.getCallingRecipeCtx() == nil then return false end
	local ok, name = pcall(react.getCurrentRecipeName)
	return ok and name == M.TARGET
end

--- Puts builtin.TextView back if our swap is in place. Never errors.
function M.restoreSwap()
	if swap.orig ~= nil and builtin.TextView == swap.fn then builtin.TextView = swap.orig end
	swap.orig, swap.line = nil, nil
end

--- What the Utilization value of `line` gets: { text, tooltip, styleSheet } of the avg node, or nil when there's
--- nothing to show. Everything that can fail happens here, before any node is made. Errors propagate.
function M.prepare(line)
	local text, tooltip = M.texts(line)
	if text == nil then return nil end
	local st = api.gui.StyleSheet.new()
	st.padding = api.type.Vec4f.new(2, 0, 0, 4) -- top (annotation text sits lower, near the body baseline), left gap
	return { text = text, tooltip = tooltip, styleSheet = st }
end

--- The Utilization value for TextView param `p`: { value, avg } side by side, both with the tooltip. Errors
--- propagate (the value node is made first, so a later failure can still hand it back: see swapFn).
function M.decorate(orig, p, extra, made, ...)
	local q = {}
	for k, v in pairs(p) do q[k] = v end
	local meta = {}
	for k, v in pairs(p.meta) do meta[k] = v end
	meta.tooltip = extra.tooltip
	q.meta = meta
	local node = orig(q, ...)
	made.node = node
	local avg = orig{ meta = { class = M.AVG_CLASS, tooltip = extra.tooltip, styleSheet = extra.styleSheet },
		text = extra.text }
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = { node, avg } }
end

local function swapFn(p, ...)
	local orig = swap.orig
	if orig == nil then
		-- a stale reference to the swap: should not happen; nothing to call
		warnOnce("swap", "called without the original TextView")
		return nil
	end
	local okHit, hit = pcall(function()
		if type(p) ~= "table" or type(p.text) ~= "string" then return false end
		local m = p.meta
		if type(m) ~= "table" or m.class ~= M.VALUE_CLASS then return false end
		if not inTarget() then return "outside" end
		return p.text:find("%", 1, true) ~= nil
	end)
	if not okHit then
		warnOnce("swap check", hit)
		M.restoreSwap()
		return orig(p, ...)
	end
	if hit == "outside" then
		M.restoreSwap()
		return orig(p, ...)
	end
	if not hit then return orig(p, ...) end
	local line = swap.line
	M.restoreSwap() -- one-shot
	local okP, extra = pcall(M.prepare, line)
	if not okP then warnOnce("decorate", extra) end
	if not okP or extra == nil then return orig(p, ...) end
	local made = {}
	local ok, out = pcall(M.decorate, orig, p, extra, made, ...)
	if ok then return out end
	warnOnce("decorate", out)
	if made.node ~= nil then return made.node end
	return orig(p, ...)
end
swap.fn = swapFn

local function arm(line)
	if builtin.TextView ~= swapFn then
		swap.orig = builtin.TextView
		builtin.TextView = swapFn
	end
	swap.line = line
end

-- wrappers -----------------------------------------------------------------------------------------------------------

local prev = {}

--- Inside the target recipe: finds out whether `getter` is the Utilization getter (it passes its line to
--- calculateCargoColumnDataForLine) and arms the swap with that line. Errors propagate.
function M.onTimerCall(getter)
	M.restoreSwap() -- an arm standing from the previous call was not used
	if type(getter) ~= "function" or not inTarget() then return end
	capture = {}
	local ok = pcall(getter)
	local line = capture.line
	capture = nil
	if ok and line ~= nil then arm(line) end
end

local function useStepStateTimer(getter, ...)
	local ok, err = pcall(M.onTimerCall, getter)
	if not ok then
		capture = nil
		warnOnce("timer", err)
	end
	return prev.timer(getter, ...)
end

local function columnData(line, ...)
	if capture ~= nil and capture.line == nil then capture.line = line end
	return prev.column(line, ...)
end

--- Wraps the two fields; true when installed (now or before). Never errors.
function M.install(_replacementApi)
	if prev.timer then return true end
	local ok, err = pcall(function()
		if type(react.getCurrentRecipeName) ~= "function" or type(react.getCallingRecipeCtx) ~= "function" then
			warnOnce("install", "react.getCurrentRecipeName / getCallingRecipeCtx missing; not installed")
			return
		end
		local eru, sru = ug_require(M.ENGINE), ug_require(M.STATS)
		local fnTimer = type(eru) == "table" and eru.useStepStateTimer or nil
		local fnColumn = type(sru) == "table" and sru.calculateCargoColumnDataForLine or nil
		if type(fnTimer) ~= "function" or type(fnColumn) ~= "function" then
			warnOnce("install", "useStepStateTimer is " .. type(fnTimer) .. ", calculateCargoColumnDataForLine is "
				.. type(fnColumn) .. "; not installed")
			return
		end
		prev.timer, prev.column = fnTimer, fnColumn
		sru.calculateCargoColumnDataForLine = columnData
		eru.useStepStateTimer = useStepStateTimer
		say("installed")
	end)
	if not ok then warnOnce("install", err) end
	return prev.timer ~= nil
end

function M.installed()
	return prev.timer ~= nil
end

return M
