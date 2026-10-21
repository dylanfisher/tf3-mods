-- Line Manager Plus: the Line Manager's bottom statistics row shows, right of the live Utilization value ("100%"),
-- the line's average utilization over the last 12 game months in the base light blue ("avg 87%"; "avg ~87%" while
-- fewer than 12 months were sampled since the game was loaded). Always on, no setting. GUI only: the history lives in
-- this Lua state, nothing goes into the save, and it starts empty at every load (the GUI scripts reload).
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
--   * Per line a bounded ring of RING samples { t, used, cap }; lines not in a finished pass are dropped.
--   * The average is capacity-weighted: sum(used) / sum(capacity) over the samples of the last 12 months (the base
--     cell's own formula, statistics_react_util.calculateCargoColumnData, applied over time). Nothing while no sample
--     has capacity.
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
--     "%", :3957-3970) is built in between and comes back as a horizontal BoxLayout { value, avg }. The swap is
--     one-shot and also undone by the next call, outside the target recipe, and at the next host tick.
-- Anything failing falls through to the base cell (logged once).

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"

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

M.MONTHS = 12
M.SAMPLES_PER_MONTH = 4
M.RING = M.MONTHS * M.SAMPLES_PER_MONTH + 4 -- a few spare: the window is cut by game time
M.PER_TICK = 100 -- lines sampled per host tick (~1.5 ms at the probe's 15 us per line)
M.MAX_LINES = 5000 -- lines per pass
M.MAX_CARGO = 200 -- capacity entries per line
M.TIMER_S = 1.0
M.TARGET = "LineStatisticDetails"
M.VALUE_CLASS = "font-scale-body, details-value"
M.AVG_CLASS = "font-scale-annotation, positive" -- base classes: smaller body text, Positive (jordyBlue, light blue)
M.ENGINE = "::/gui/main/engine_react_util.tl"
M.STATS = "::/gui/statistics/statistics_react_util.tl"

-- history ------------------------------------------------------------------------------------------------------------

-- [line] = { t = {}, u = {}, c = {}, head = 0, n = 0, first = gameTime of the first sample }
local hist = {}
local lastPassT = nil -- game time of the last pass started
local pass = nil -- { lines, i, t, seen } while a pass is in progress

function M.reset()
	hist, lastPassT, pass = {}, nil, nil
end

--- Adds one sample to `line`'s ring.
function M.push(line, t, used, cap)
	local h = hist[line]
	if h == nil then
		h = { t = {}, u = {}, c = {}, head = 0, n = 0, first = t }
		hist[line] = h
	end
	local i = h.head % M.RING + 1
	h.head = i
	h.t[i], h.u[i], h.c[i] = t, used, cap
	if h.n < M.RING then h.n = h.n + 1 end
end

--- Number of samples kept for `line` (0 when none).
function M.count(line)
	local h = hist[line]
	return h and h.n or 0
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

--- `line`'s average: (fraction 0..1, full, months) or nil when there's nothing to show. full: the samples cover 12
--- months; months: whole months covered (since load while not full).
function M.average(line, monthMs)
	local h = hist[line]
	if h == nil or h.n == 0 then return nil end
	monthMs = monthMs or M.monthMs()
	if monthMs == nil then return nil end
	local window = M.MONTHS * monthMs
	local last = h.t[h.head]
	local from = last - window
	local used, cap = 0, 0
	for k = 1, h.n do
		if h.t[k] > from then
			used, cap = used + h.u[k], cap + h.c[k]
		end
	end
	if cap <= 0 then return nil end
	local span = last - h.first + monthMs / M.SAMPLES_PER_MONTH -- the last sample stands for one interval
	local full = span >= window
	local months = math.floor(math.min(span, window) / monthMs)
	return used / cap, full, months
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
			M.push(line, pass.t, used, cap)
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

-- display ------------------------------------------------------------------------------------------------------------

local function percent(v)
	local ok, s = pcall(function() return api.util.toStringPercentPrecision(v, 0) end)
	if ok and type(s) == "string" then return s end
	return string.format("%d%%", math.floor(v * 100 + 0.5))
end

--- text, tooltip for `line`, or nil when nothing is to be shown. Errors propagate.
function M.texts(line)
	local avg, full, months = M.average(line)
	if avg == nil then return nil end
	local p = percent(avg)
	if full then
		return string.format(_("avg %s"), p), _("Average utilization over the last 12 months.")
	end
	return string.format(_("avg ~%s"), p),
		string.format(_("Average utilization since the game was loaded\n(%d of 12 months so far)."), months)
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

--- The node for the Utilization value `node` of `line`: { node, avg } side by side, or `node` with nothing to show.
--- Errors propagate.
function M.decorate(orig, node, line)
	local text, tooltip = M.texts(line)
	if text == nil then return node end
	local st = api.gui.StyleSheet.new()
	st.padding = api.type.Vec4f.new(2, 0, 0, 4) -- top (annotation text sits lower, near the body baseline), left gap
	local avg = orig{ meta = { class = M.AVG_CLASS, tooltip = tooltip, styleSheet = st }, text = text }
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
	local node = orig(p, ...)
	local ok, out = pcall(M.decorate, orig, node, line)
	if ok then return out end
	warnOnce("decorate", out)
	return node
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
