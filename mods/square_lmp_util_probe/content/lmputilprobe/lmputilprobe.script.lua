-- DEV probe for the planned Line Manager Plus "average Utilization over the last 12 game months" cell
-- (plans/square_line_manager_plus/UTIL_PROBE.md). Never upload. Read-only. Every line it logs starts with
-- "[LMPUTILPROBE]" (print -> stdout.txt; the log line prefix carries the thread: "Main Thread" / "Main Pool N").
--
-- Target: the file-local recipe "LineStatisticDetails" (.cache/game/base/content/gui/line_vehicle_mgmt/
-- manager_window.tl:3830; used at :4319 with showHeader=false and in LineStatisticDetailsEntry :4132). Its
-- Utilization value is makeValueText(api.util.toStringPercentPrecision(coverageState:old(), 0)) (:3957-3970), a
-- builtin.TextView with class "font-scale-body, details-value", built after the coverage getter was handed to
-- engine_react_util.useStepStateTimer and before the frequency one. The recipe is not exported.
--
-- Q1 techniques (all on at once; each guarded, a failure is logged; the marker lists the ones that fired):
--   T1 render wrap: find the recipe's id (debug.getupvalue on react.GetRecipeName -> the local recipeFnToRecipeName,
--      react.lua:5/441; fallback: react.getCurrentRecipeId() seen by T3) and wrap _react.recipes[id] (the render
--      function, react.lua:261; _react is a global, base/init.lua:41). For the duration of that render only,
--      builtin.TextView is swapped (see "swap"), so the Utilization value TextView gets a marker beside it.
--   T2 ReplaceRecipe: with the function object from the same scan, replacementApi.ReplaceRecipe(fn, replacement)
--      in doReplace (bootstrap_game.tl:6-10); the replacement is our recipe that renders react.CallOriginalRecipe
--      plus a small "T2" line under the row (proves fn access + whole-row wrapping; it cannot reach into a cell).
--      Fallback without debug: _react.recipeReplace[id] / _react.originalRecipeFn[id] set late from T3's id.
--   T3 narrow module field: engine_react_util.useStepStateTimer is wrapped; when called inside LineStatisticDetails
--      with the coverage getter (the closure with an upvalue named "statistics_react_util"), a one-shot
--      builtin.TextView swap is armed that fires on the next details-value TextView and is dropped at the next
--      useStepStateTimer call. No builtin widget stays wrapped.
--   T4 last resort (data point only): api.util.toStringPercentPrecision replaced, appending " T4" when called inside
--      LineStatisticDetails. Global function wrapper: never for production.
-- Q2: two always-mounted empty plugins (HostRidge: ::MainModButtonAreaExtension; HostEntry: ::ModEntryPointExtension)
--      each register react.onStep and react.onStepTimer and log a heartbeat (calls, paused, Line Manager seen).
-- Q3: HostRidge's onStepTimer runs a utilization pass over every player line every 10 s for 12 passes (~2 min),
--      timed with api.type.Clock; passes 1 and 12 are repeated from onStep (Main Thread). Then silent sampling every
--      30 s keeps the per-line averages the marker shows.
--
-- API sources (.cache/game):
--   getLineCapacityUsages        api/tealdef/api/engine/util.d.tl:143-148, :198 (cargo_util.tl:707-722)
--   getLinesForPlayer            api/tealdef/api/engine/system.d.tl:18
--   GAME_SPEED / GAME_TIME       api/tealdef/api/engine.d.tl:415-433
--   Clock                        api/tealdef/api/type.d.tl:1860-1866
--   StyleSheet.color             api/tealdef/api/gui.d.tl:20-41

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl"
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl"
local mod_entry_point = ug_require "::/gui/main/mod_entry_point.tl"

local TARGET = "LineStatisticDetails"
local VALUE_CLASS = "font-scale-body, details-value"
local REPORT_US = 10000000 -- Q1 rates and Q2 heartbeats every 10 s ...
local REPORT_LATE_US = 60000000 -- ... and every 60 s after LATE_AFTER_US
local LATE_AFTER_US = 300000000 -- 5 min
local Q3_FIRST_US = 5000000 -- first pass 5 s after the first timer tick
local Q3_EVERY_US = 10000000
local Q3_PASSES = 12
local QUIET_EVERY_US = 30000000 -- silent sampling after Q3 for the marker averages
local MAX_LINES = 5000 -- loop caps
local MAX_CARGO = 200
local MAX_UPVALUES = 60
local MAX_SCAN = 200000

-- Logging ---------------------------------------------------------------------------------------------------------
local function say(...)
	local parts = { "[LMPUTILPROBE]" }
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	print(table.concat(parts, " "))
end

local onceSeen = {}
local function sayOnce(key, ...)
	if onceSeen[key] then return end
	onceSeen[key] = true
	say(...)
end

local clock
local function nowUs()
	if not clock then clock = api.type.Clock.new() end
	return clock:getTime()
end

local function gameState()
	local speed, gt = "?", "?"
	pcall(function()
		local w = api.engine.util.getWorld()
		local s = api.engine.getComponent(w, api.type.ComponentType.GAME_SPEED)
		local t = api.engine.getComponent(w, api.type.ComponentType.GAME_TIME)
		speed = s and s.speedup or "nil"
		gt = t and t.gameTime or "nil"
	end)
	return speed, gt
end

local hasDebug = type(debug) == "table" and type(debug.getupvalue) == "function"

--- Value of the upvalue `name` of function `fn` (nil without debug or when absent).
local function upvalue(fn, name)
	if not hasDebug or type(fn) ~= "function" then return nil end
	for i = 1, MAX_UPVALUES do
		local n, v = debug.getupvalue(fn, i)
		if n == nil then return nil end
		if n == name then return v, true end
	end
	return nil
end

local function upvalueNames(fn)
	if not hasDebug or type(fn) ~= "function" then return "-" end
	local out = {}
	for i = 1, MAX_UPVALUES do
		local n = debug.getupvalue(fn, i)
		if n == nil then break end
		out[#out + 1] = n
	end
	return table.concat(out, ",")
end

-- Per-line samples (written by Q3 passes, read by the marker) -------------------------------------------------------
local samples = {} -- [line] = { sum, n, last }

local function lineUsage(line)
	local caps = api.engine.util.line.getLineCapacityUsages(line, false)
	local used, cap, k = 0, 0, 0
	if caps then
		for _i, c in ipairs(caps) do
			k = k + 1
			if k > MAX_CARGO then break end
			if c then
				used = used + (c.used or 0)
				cap = cap + (c.capacity or 0)
			end
		end
	end
	return used, cap, k
end

local function avgText(line)
	local s = line and samples[line]
	if not s or s.n == 0 then return nil end
	return string.format("avg %d%% n%d", math.floor(100 * s.sum / s.n + 0.5), s.n)
end

-- Q1 counters -----------------------------------------------------------------------------------------------------
local Q1 = { t1Render = 0, t2Create = 0, t2Render = 0, t3Call = 0, t3Arm = 0, t3Miss = 0, swapMatch = 0, t4Call = 0 }
local Q1lines = {}
local lastTargetUs = nil

local function seen(key, line)
	Q1[key] = Q1[key] + 1
	if line ~= nil then Q1lines[tostring(line)] = true end
	lastTargetUs = nowUs()
	sayOnce("first:" .. key, "Q1 FIRST", key, "line", tostring(line))
end

local function inTarget()
	if type(react.getCallingRecipeCtx) ~= "function" or react.getCallingRecipeCtx() == nil then return false end
	local ok, name = pcall(react.getCurrentRecipeName)
	return ok and name == TARGET
end

-- The scoped builtin.TextView swap (T1 for one render, T3 one-shot) ------------------------------------------------
local swap = { orig = nil, labels = {}, line = nil }
local swapFn
local markerStyle

local function labelText()
	local out = {}
	for _i, l in ipairs({ "T1", "T3" }) do
		if swap.labels[l] then out[#out + 1] = l end
	end
	return table.concat(out, "+")
end

local function swapRestore()
	if swap.orig and builtin.TextView == swapFn then builtin.TextView = swap.orig end
	swap.orig = nil
end

local function swapAdd(label)
	swap.labels[label] = true
	if builtin.TextView ~= swapFn then
		swap.orig = builtin.TextView
		builtin.TextView = swapFn
	end
end

local function swapDrop(label)
	swap.labels[label] = nil
	if next(swap.labels) == nil then swapRestore() end
end

swapFn = function(p, ...)
	local orig = swap.orig
	if orig == nil then
		-- someone kept a stale reference: should not happen
		sayOnce("stale", "Q1 WARN swap called without orig")
		return nil
	end
	local ok, hit = pcall(function()
		if type(p) ~= "table" or type(p.text) ~= "string" then return false end
		local m = p.meta
		if type(m) ~= "table" or m.class ~= VALUE_CLASS then return false end
		if not inTarget() then return "outside" end
		return p.text:find("%", 1, true) ~= nil
	end)
	if not ok then
		sayOnce("swaperr", "Q1 ERROR swap check", hit)
		return orig(p, ...)
	end
	if hit == "outside" then
		-- a T3 arm left over from the previous render (loose mode: the rate call): drop it, pass through
		swapDrop("T3")
		return orig(p, ...)
	end
	if not hit then return orig(p, ...) end
	local labels = labelText()
	local value = orig(p, ...)
	local okB, node = pcall(function()
		if not markerStyle then
			local st = api.gui.StyleSheet.new()
			st.color = api.type.Vec4f.new(0.55, 0.72, 0.95, 1.0) -- muted blue
			markerStyle = st
		end
		local text = labels .. " " .. (avgText(swap.line) or ("now " .. p.text))
		local marker = orig{ meta = { class = VALUE_CLASS, styleSheet = markerStyle }, text = text }
		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = { value, marker } }
	end)
	Q1.swapMatch = Q1.swapMatch + 1
	sayOnce("match:" .. labels, "Q1 MARKER rendered by", labels, "line", tostring(swap.line), "value", p.text)
	swap.labels.T3 = nil -- one-shot
	if next(swap.labels) == nil then swapRestore() end
	if okB then return node end
	sayOnce("markererr", "Q1 ERROR marker", node)
	return value
end

-- T1: render wrap ---------------------------------------------------------------------------------------------------
local T1 = { installed = false, id = nil }

local function installT1(id, via)
	if T1.installed then return end
	local ok, err = pcall(function()
		local R = _react
		if type(R) ~= "table" or type(R.recipes) ~= "table" then
			error("_react.recipes missing (" .. type(R) .. ")")
		end
		local orig = R.recipes[id]
		if type(orig) ~= "function" then error("_react.recipes[" .. tostring(id) .. "] is " .. type(orig)) end
		R.recipes[id] = function(ctx, cppProps)
			local line = nil
			pcall(function()
				local p = cppProps and cppProps.props and cppProps.props[1]
				line = p and p.lineEntity
			end)
			pcall(seen, "t1Render", line)
			swap.line = line
			pcall(swapAdd, "T1")
			local okR, errR = pcall(orig, ctx, cppProps)
			pcall(swapDrop, "T1")
			if not okR then error(errR, 0) end
		end
		T1.installed, T1.id = true, id
	end)
	say("Q1 install T1 render-wrap", ok and "OK" or "FAILED", "via", via, "id", tostring(id), ok and "" or tostring(err))
end

-- T2: ReplaceRecipe -------------------------------------------------------------------------------------------------
local T2 = { fn = nil, id = nil, installed = false }

local function callOriginal(params)
	if T2.fn then return react.CallOriginalRecipe(T2.fn, params) end
	return _react.originalRecipeFn[T2.id](params)
end

local T2Recipe = react.RegisterRecipe("SquareLmpUtilProbeT2", function(params)
	local line = type(params) == "table" and params.lineEntity or nil
	pcall(seen, "t2Render", line)
	local node = callOriginal(params)
	local ok, wrapped = pcall(function()
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Vertical,
			children = {
				node,
				builtin.TextView{
					meta = { class = "font-scale-annotation", styleSheet = markerStyle },
					text = "T2 replace ok, line " .. tostring(line) .. " " .. (avgText(line) or ""),
				},
			},
		}
	end)
	if ok then return wrapped end
	sayOnce("t2err", "Q1 ERROR T2 render", wrapped)
	return builtin.BoxLayout{ children = { node } }
end)

local function t2Replacement(...)
	local p = select(1, ...)
	pcall(function()
		seen("t2Create", type(p) == "table" and p.lineEntity or nil)
	end)
	return T2Recipe(...)
end

local function installT2Late(id)
	if T2.installed then return end
	local ok, err = pcall(function()
		if type(_react.originalRecipeFn[id]) ~= "function" then error("originalRecipeFn missing") end
		T2.id = id
		_react.recipeReplace[id] = t2Replacement
		T2.installed = true
	end)
	say("Q1 install T2 replace (late, _react.recipeReplace)", ok and "OK" or "FAILED", "id", tostring(id), ok and "" or tostring(err))
end

-- T3: engine_react_util.useStepStateTimer -----------------------------------------------------------------------------
local T3 = { orig = nil, strict = hasDebug }

local function onT3(getter)
	if not inTarget() then return end
	local params = upvalue(getter, "params")
	local line = type(params) == "table" and params.lineEntity or nil
	seen("t3Call", line)
	sayOnce("t3names:" .. upvalueNames(getter), "Q1 T3 getter upvalues", upvalueNames(getter))
	local okId, id = pcall(react.getCurrentRecipeId)
	if okId and id ~= nil then
		sayOnce("t3id", "Q1 T3 current recipe id", tostring(id), "T1 id", tostring(T1.id))
		if not T1.installed then installT1(id, "late:T3") end
		if not T2.installed then installT2Late(id) end
	end
	-- strict when upvalue names are readable (bytecode not stripped): only the coverage getter arms. Loose (every call
	-- arms, the next call drops) also lands on the Utilization value: it is built between the coverage and the
	-- frequency useStepStateTimer calls.
	local _p, named = upvalue(getter, "params")
	local strict = T3.strict and named
	sayOnce("t3mode", "Q1 T3 mode", strict and "strict (coverage getter only)" or "loose (every call arms)")
	-- an arm still standing at the next call was not used: in strict mode that is a miss
	if swap.labels.T3 then
		if strict then Q1.t3Miss = Q1.t3Miss + 1 end
		swapDrop("T3")
	end
	local coverage = (not strict) or upvalue(getter, "statistics_react_util") ~= nil
	if coverage then
		Q1.t3Arm = Q1.t3Arm + 1
		swap.line = line
		swapAdd("T3")
	end
end

local function useStepStateTimerWrapper(getFromEngine, interval, stateEqualsFn)
	local ok, err = pcall(onT3, getFromEngine)
	if not ok then sayOnce("t3err", "Q1 ERROR T3", err) end
	return T3.orig(getFromEngine, interval, stateEqualsFn)
end

-- T4: api.util.toStringPercentPrecision -------------------------------------------------------------------------------
local T4 = { orig = nil }

local function percentWrapper(v, d)
	local s = T4.orig(v, d)
	local ok, inside = pcall(inTarget)
	if ok and inside then
		pcall(seen, "t4Call", nil)
		return tostring(s) .. " T4"
	end
	return s
end

-- doReplace ---------------------------------------------------------------------------------------------------------
local function findTargetFn()
	if not hasDebug then return nil, "debug.getupvalue unavailable" end
	local map = upvalue(react.GetRecipeName, "recipeFnToRecipeName")
	if type(map) ~= "table" then
		return nil, "upvalue recipeFnToRecipeName not found (upvalues: " .. upvalueNames(react.GetRecipeName) .. ")"
	end
	local found, matches, total = nil, 0, 0
	for fn, name in pairs(map) do
		total = total + 1
		if total > MAX_SCAN then break end
		if name == TARGET then
			found = fn
			matches = matches + 1
		end
	end
	return found, string.format("scanned %d recipes, %d named %s", total, matches, TARGET)
end

local installed = false
local function doReplace(replacementApi)
	if installed then return end
	installed = true
	say("Q1 env debug=" .. tostring(hasDebug), "_react=" .. type(_react),
		"getCallingRecipeCtx=" .. type(react.getCallingRecipeCtx), "getCurrentRecipeId=" .. type(react.getCurrentRecipeId))

	-- T1 + T2 (function object from react's local name map)
	local okF, fn, info = pcall(findTargetFn)
	if not okF then fn, info = nil, tostring(fn) end
	say("Q1 find LineStatisticDetails fn:", fn and "FOUND" or "NOT FOUND", tostring(info))
	if fn then
		local id = react.GetRecipeId(fn)
		installT1(id, "doReplace:upvalue-scan")
		local okR, errR = pcall(function()
			replacementApi.ReplaceRecipe(fn, t2Replacement)
			T2.fn, T2.id, T2.installed = fn, id, true
		end)
		say("Q1 install T2 ReplaceRecipe", okR and "OK" or "FAILED", "id", tostring(id), okR and "" or tostring(errR))
	end

	-- T3
	local okT3, errT3 = pcall(function()
		local cur = engine_react_util.useStepStateTimer
		if type(cur) ~= "function" then error("useStepStateTimer is " .. type(cur)) end
		T3.orig = cur
		engine_react_util.useStepStateTimer = useStepStateTimerWrapper
	end)
	say("Q1 install T3 useStepStateTimer wrap", okT3 and "OK" or "FAILED", "strict(coverage getter only)=" .. tostring(T3.strict),
		okT3 and "" or tostring(errT3))

	-- T4
	local okT4, errT4 = pcall(function()
		local cur = api.util.toStringPercentPrecision
		if type(cur) ~= "function" then error("toStringPercentPrecision is " .. type(cur)) end
		T4.orig = cur
		api.util.toStringPercentPrecision = percentWrapper
		if api.util.toStringPercentPrecision ~= percentWrapper then
			api.util.toStringPercentPrecision = cur
			error("assignment did not stick (api.util is read-only)")
		end
	end)
	say("Q1 install T4 api.util.toStringPercentPrecision wrap", okT4 and "OK" or "FAILED", okT4 and "" or tostring(errT4))
end

-- Q3: utilization pass ------------------------------------------------------------------------------------------------
local Q3 = { passes = 0, nextUs = nil, done = false, mainWanted = false, quietNextUs = nil, loggedCaps = false }

local function pass(label, quiet)
	local c = api.type.Clock.new()
	local t0 = c:getTime()
	local lines = api.engine.system.lineSystem.getLinesForPlayer(api.engine.util.getPlayer()) or {}
	local tList = c:getTime() - t0
	local n, okN, errs, maxUs, maxLine, used, cap = 0, 0, 0, 0, nil, 0, 0
	for i, line in ipairs(lines) do
		if i > MAX_LINES then break end
		n = n + 1
		local a = c:getTime()
		local ok, u, k, nCaps = pcall(lineUsage, line)
		local d = c:getTime() - a
		if ok then
			okN = okN + 1
			used, cap = used + u, cap + k
			if k > 0 then
				local s = samples[line]
				if not s then
					s = { sum = 0, n = 0 }
					samples[line] = s
				end
				s.sum, s.n, s.last = s.sum + u / k, s.n + 1, u / k
			end
			if not Q3.loggedCaps and k > 0 then
				Q3.loggedCaps = true
				say(string.format("Q3 sample line=%s capsEntries=%d used=%s capacity=%s util=%.3f", tostring(line), nCaps, tostring(u),
					tostring(k), u / k))
			end
		else
			errs = errs + 1
			sayOnce("q3err", "Q3 ERROR line", tostring(line), tostring(u))
		end
		if d > maxUs then maxUs, maxLine = d, line end
	end
	local total = c:getTime() - t0
	if quiet then return end
	local speed, gt = gameState()
	say(string.format("Q3 pass=%s lines=%d ok=%d errors=%d totalUs=%d listUs=%d maxUsPerLine=%d (line %s) avgUsPerLine=%.1f "
		.. "allUtil=%s speedup=%s gameTime=%s lmSeenAgoS=%s",
		label, n, okN, errs, total, tList, maxUs, tostring(maxLine), n > 0 and (total - tList) / n or 0,
		cap > 0 and string.format("%.3f", used / cap) or "-", tostring(speed), tostring(gt),
		lastTargetUs and string.format("%.0f", (nowUs() - lastTargetUs) / 1000000) or "never"))
end

local function q3Tick()
	local t = nowUs()
	if Q3.done then
		if Q3.quietNextUs and t >= Q3.quietNextUs then
			Q3.quietNextUs = t + QUIET_EVERY_US
			pass("quiet", true)
		end
		return
	end
	if Q3.nextUs == nil then
		Q3.nextUs = t + Q3_FIRST_US
		return
	end
	if t < Q3.nextUs then return end
	Q3.nextUs = t + Q3_EVERY_US
	Q3.passes = Q3.passes + 1
	pass("worker#" .. Q3.passes, false)
	if Q3.passes == 1 or Q3.passes == Q3_PASSES then Q3.mainWanted = true end
	if Q3.passes >= Q3_PASSES then
		Q3.done = true
		Q3.quietNextUs = t + QUIET_EVERY_US
		say("Q3 done: logging stops; silent sampling every", QUIET_EVERY_US / 1000000, "s for the marker averages")
	end
end

local function mainPassIfWanted()
	if not Q3.mainWanted then return end
	Q3.mainWanted = false
	pass("main#" .. Q3.passes, false)
end

-- Q1 report (from HostRidge onStep) -----------------------------------------------------------------------------------
local q1Next = nil
local function q1Report()
	local t = nowUs()
	if q1Next == nil then q1Next = t + REPORT_US end
	if t < q1Next then return end
	q1Next = t + REPORT_US
	local any = false
	for _k, v in pairs(Q1) do
		if v > 0 then any = true end
	end
	if not any then return end
	local lines = {}
	for l in pairs(Q1lines) do lines[#lines + 1] = l end
	table.sort(lines)
	say(string.format("Q1 rates window=10s T1render=%d T2create=%d T2render=%d T3call=%d T3arm=%d T3miss=%d swapMatch=%d T4=%d "
		.. "builtinTextViewSwappedNow=%s lines=%s",
		Q1.t1Render, Q1.t2Create, Q1.t2Render, Q1.t3Call, Q1.t3Arm, Q1.t3Miss, Q1.swapMatch, Q1.t4Call,
		tostring(builtin.TextView == swapFn), table.concat(lines, ",")))
	for k in pairs(Q1) do Q1[k] = 0 end
	Q1lines = {}
end

-- Q2 hosts ------------------------------------------------------------------------------------------------------------
local beats = {}
local t0Us = nil

local function hostStep(host, cb)
	local key = host .. "/" .. cb
	local st = beats[key]
	local t = nowUs()
	if not st then
		st = { n = 0, total = 0, nextUs = t + REPORT_US }
		beats[key] = st
		local speed, gt = gameState()
		say("Q2 FIRST host=" .. host, "cb=" .. cb, "(thread: see this line's prefix) speedup=" .. tostring(speed),
			"gameTime=" .. tostring(gt))
	end
	st.n, st.total = st.n + 1, st.total + 1
	if t >= st.nextUs then
		if t0Us == nil then t0Us = t end
		local speed, gt = gameState()
		say(string.format("Q2 beat host=%s cb=%s calls=%d total=%d speedup=%s gameTime=%s lmSeenAgoS=%s",
			host, cb, st.n, st.total, tostring(speed), tostring(gt),
			lastTargetUs and string.format("%.0f", (t - lastTargetUs) / 1000000) or "never"))
		st.n = 0
		st.nextUs = t + (((t - t0Us) > LATE_AFTER_US) and REPORT_LATE_US or REPORT_US)
	end
	if host == "ridge" then
		if cb == "onStepTimer" then q3Tick() end
		if cb == "onStep" then
			q1Report()
			mainPassIfWanted()
		end
	end
end

local function guarded(host, cb)
	return function()
		local ok, err = pcall(hostStep, host, cb)
		if not ok then sayOnce("hosterr:" .. host .. cb, "Q2 ERROR host=" .. host, "cb=" .. cb, err) end
	end
end

local function hostRender(host)
	return function()
		react.onStep(guarded(host, "onStep"))
		react.onStepTimer(guarded(host, "onStepTimer"), 1.0)
		react.onMount(function() say("Q2 mount host=" .. host) end)
		react.onUnmount(function() say("Q2 UNMOUNT host=" .. host) end)
		return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = {} }
	end
end

local HostRidge = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "SquareLmpUtilProbeHostRidge",
	hostRender("ridge"))
local HostEntry = react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "SquareLmpUtilProbeHostEntry",
	hostRender("entry"))

say("loaded")

-- .script.lua resources export through data()
function data()
	return {
		doReplace = doReplace,
		HostRidge = HostRidge,
		HostEntry = HostEntry,
	}
end
