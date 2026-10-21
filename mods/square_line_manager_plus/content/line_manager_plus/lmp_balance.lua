-- Line Manager Plus: hovering a line's Balance shows it over longer time frames: last year, last 2 years, last 5
-- years (income minus running costs, as the cell). Always on, no setting. GUI only: reads the game's journal, writes
-- nothing, saves nothing.
--
-- Where: the base recipe line_react_util.LineBalance (base line_react_util.tl:621-640: calculateBalance({line},
-- max(now - defaultYear, 0), now, true) in a TextView, refreshed by a step timer) is used by the Line Manager's bottom
-- statistics row (manager_window.tl:4007), the Statistics window's lines table (statistic_lines.tl:240, one per row)
-- and the line window's "Last Year" (line_eow.script.tl:308). The tooltip applies to all three.
--
-- Hook (M.install, lmp.script.lua's doReplace): the MODULE FIELD line_react_util.LineBalance (looked up per render by
-- every caller) is wrapped with a plain function. A call with one params table (no meta) renders our recipe
-- SquareLmpLineBalance instead, which renders the base recipe unchanged inside a BoxLayout, with the tooltip as a
-- `meta.tooltip` on that call (react hands a recipe call's meta to its node and strips it from the params:
-- docs/findings/gui.md "DataTable column weights, inline sizes on recipe calls"; the base does the same with a tooltip:
-- line_react_util.NameTextView{ meta = { tooltip = ... } }, vehicle_eow.script.tl:63-64, a recipe whose root is a
-- BoxLayout, as LineBalance's). So the base node, its TextView, its
-- classes and every base rule (`R::LineWindowContent R::LineBalance TextView`, `R::LineBalanceCell`) stay as they
-- are. Any other call (a ref, meta) goes to the base unchanged. The replacement api is shimmed so a later
-- ReplaceRecipe(<our wrapper>, x) gets the function we wrapped.
--
-- Cost: our recipe polls its tooltip text with useStepStateTimer every TIMER_S (the base cell polls every 0.5 s). Per
-- poll: the last-year value (one calculateBalance call, as the cell) plus the 2- and 5-year values from a per-line
-- cache, recomputed at most once per quarter game month (default year / 48) and for at most BUDGET lines per wall
-- second, so a Statistics table of hundreds of rows spreads its first fill over a few seconds. A window that reaches
-- back before the game start is clamped to it ("since the game started"), and a longer window that would show the
-- same clamped value is left out. Open (TESTING.md): whether the journal keeps line entries older than a few years.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"

local PREFIX = "[LineManagerPlus] balance: "

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

M.LINE_UTIL = "::/gui/line_vehicle_mgmt/line_react_util.tl"
M.ENGINE = "::/gui/main/engine_react_util.tl"
M.RECIPE = "SquareLmpLineBalance"
M.WINDOWS = { 1, 2, 5 } -- years
M.REFRESH_YEARS = 1 / 48 -- the cached windows are recomputed at most this often (a quarter month)
M.BUDGET = 40 -- lines whose cached windows are recomputed per wall second
M.MAX_CACHE = 5000 -- lines cached; the cache starts over beyond
M.TIMER_S = 1.0

-- cache ---------------------------------------------------------------------------------------------------------------

-- [line] = { t = game time computed, [2] = balance, [5] = balance }
local cache, cacheN = {}, 0
local budget = { start = nil, used = 0 }

function M.reset()
	cache, cacheN = {}, 0
	budget.start, budget.used = nil, 0
end

local clock
--- Wall clock in microseconds (api.type.Clock, safe on every thread), or nil.
function M.wallUs()
	local ok, t = pcall(function()
		if not clock then clock = api.type.Clock.new() end
		return clock:getTime()
	end)
	if ok and type(t) == "number" then return t end
	return nil
end

--- true when one more line may be recomputed in this wall second.
local function takeBudget()
	local now = M.wallUs()
	if now ~= nil and (budget.start == nil or now - budget.start >= 1e6 or now < budget.start) then
		budget.start, budget.used = now, 0
	end
	if budget.used >= M.BUDGET then return false end
	budget.used = budget.used + 1
	return true
end

local function gameTime()
	local c = api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	local t = c and c.gameTime
	if type(t) ~= "number" or t ~= t then error("no game time") end
	return t
end

--- `line`'s balance over the `years` before `now` (clamped to the game start, as the base cell). Errors propagate.
function M.balance(line, years, now, year)
	return api.engine.util.finance.calculateBalance({ line }, math.max(now - years * year, 0), now, true)
end

--- { { years, value, clamped }, ... } for `line`, nil while nothing can be had. The last year is computed now; the
--- longer windows come from the cache (stale ones kept while the budget is spent). Errors propagate.
function M.values(line)
	local now = gameTime()
	local year = api.util.getDefaultYearDuration()
	if type(year) ~= "number" or not (year > 0) then error("no year length") end
	local e = cache[line]
	if e == nil or now < e.t or now - e.t >= year * M.REFRESH_YEARS then
		if takeBudget() then
			local fresh = { t = now }
			for _i, years in ipairs(M.WINDOWS) do
				if years > 1 then fresh[years] = M.balance(line, years, now, year) end
			end
			if e == nil then
				if cacheN >= M.MAX_CACHE then cache, cacheN = {}, 0 end
				cacheN = cacheN + 1
			end
			cache[line] = fresh
			e = fresh
		end
	end
	local out = {}
	for _i, years in ipairs(M.WINDOWS) do
		local value
		if years == 1 then
			value = M.balance(line, 1, now, year)
		elseif e ~= nil then
			value = e[years]
		end
		if type(value) == "number" then
			out[#out + 1] = { years = years, value = value, clamped = now < years * year }
			if now < years * year then break end -- the longer windows would show the same clamped value
		end
	end
	if #out == 0 then return nil end
	return out
end

-- one format string per sentence (CLAUDE.md "Translations")
local function windowLine(years, money, clamped)
	if years == 1 then
		if clamped then return string.format(_("Last year: %s (since the game started)"), money) end
		return string.format(_("Last year: %s"), money)
	elseif years == 2 then
		if clamped then return string.format(_("Last 2 years: %s (since the game started)"), money) end
		return string.format(_("Last 2 years: %s"), money)
	elseif years == 5 then
		if clamped then return string.format(_("Last 5 years: %s (since the game started)"), money) end
		return string.format(_("Last 5 years: %s"), money)
	end
	return nil
end

--- The tooltip text for `line`, or nil. Errors propagate.
function M.tooltip(line)
	local values = M.values(line)
	if values == nil then return nil end
	local rows = {}
	for _i, v in ipairs(values) do
		rows[#rows + 1] = windowLine(v.years, api.util.formatMoney(v.value), v.clamped)
	end
	return table.concat(rows, "\n")
end

-- the recipe and the wrapper ------------------------------------------------------------------------------------------

local prev = {} -- prev.balance: the LineBalance we wrapped
local recipe = nil
local eruMod = nil -- engine_react_util (its useStepStateTimer field looked up per render)

local function tipText(line)
	local ok, tip = pcall(M.tooltip, line)
	if not ok then
		warnOnce("tooltip", tip)
		return ""
	end
	return type(tip) == "string" and tip or ""
end

--- The body of our recipe: the base LineBalance with the tooltip. Errors propagate (react's own handling, as for a
--- base recipe; nothing in here can fail but the base call itself).
function M.body(p)
	local tipState = eruMod.useStepStateTimer(function() return tipText(p.entity) end, M.TIMER_S)
	local tip = tipState:old()
	local params = { entity = p.entity, stepTimer = p.stepTimer }
	if type(tip) == "string" and tip ~= "" then params.meta = { tooltip = tip } end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { prev.balance(params) },
	}
end

local function lineBalance(p, ...)
	if recipe ~= nil and select("#", ...) == 0 and type(p) == "table" and p.meta == nil and p.entity ~= nil then
		return recipe{ entity = p.entity, stepTimer = p.stepTimer }
	end
	return prev.balance(p, ...)
end

-- a later ReplaceRecipe(<our wrapper>, x) gets the function we wrapped instead (as line_list_hover.lua)
local function shimReplacementApi(replacementApi)
	if type(replacementApi) ~= "table" then return end
	local replace = replacementApi.ReplaceRecipe
	if type(replace) ~= "function" then return end
	replacementApi.ReplaceRecipe = function(original, ...)
		if original == lineBalance then original = prev.balance end
		return replace(original, ...)
	end
end

--- Wraps line_react_util.LineBalance; true when installed (now or before). Never errors.
function M.install(replacementApi)
	if prev.balance then return true end
	local ok, err = pcall(function()
		if type(react.RegisterRecipe) ~= "function" then
			warnOnce("install", "react.RegisterRecipe is missing; not installed")
			return
		end
		local lru, eru = ug_require(M.LINE_UTIL), ug_require(M.ENGINE)
		local fn = type(lru) == "table" and lru.LineBalance or nil
		local timer = type(eru) == "table" and eru.useStepStateTimer or nil
		if type(fn) ~= "function" or type(timer) ~= "function" then
			warnOnce("install", "LineBalance is " .. type(fn) .. ", useStepStateTimer is " .. type(timer)
				.. "; not installed")
			return
		end
		eruMod = eru
		recipe = react.RegisterRecipe(M.RECIPE, M.body)
		prev.balance = fn
		lru.LineBalance = lineBalance
		shimReplacementApi(replacementApi)
		say("installed")
	end)
	if not ok then
		recipe = nil -- the wrapper then passes every call through
		warnOnce("install", err)
	end
	return prev.balance ~= nil
end

function M.installed()
	return prev.balance ~= nil
end

return M
