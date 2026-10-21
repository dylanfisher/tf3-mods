-- Line Manager Plus: the average utilization beside the Line Manager's Utilization value and its 12-month / 2-year /
-- 5-year tooltip (lmp_util_avg.lua), with fake react / builtin / engine_react_util / statistics_react_util modules, a
-- fake engine (game time, calendar speed, lines and their capacity usages) and fake GUI save data.
-- Covers: install (wraps the two fields once, builtin.TextView untouched outside a render), sampling (game time
-- driven: no sample while the game time stands even though the timer fires, one per quarter month, the calendar
-- speed's month length and the default month when frozen), monthly buckets and the windows (12 months, 2 and 5
-- years; "~" and the months covered while partial; at most 61 buckets), capacity weighting, removed lines dropped,
-- the per-tick and per-pass caps, the savegame (read and written only in the Main Thread step, never in the
-- worker-thread tick; written only when a month closed, the round trip through a reload,
-- merged with lmp_visible.lua's part both ways, bad saved data ignored, a read failure never overwrites, time going
-- back), the render (the value and the avg both carry the tooltip, one-shot, the swap undone), and errors (the base
-- cell unchanged, logged once).

local react, builtin, eru, sru, avg, world, current, timerCalls, columnCalls, saveData, saves

local MONTH = 60000 -- the fake default month (game ms)

local function setup(opts)
	opts = opts or {}
	reset_modules()
	if not opts.keepLogs then clear_logs() end
	if not opts.keepSave then
		saveData = { other_mod = { x = 1 }, square_line_manager_plus = opts.stored }
		saves = 0
	end
	world = {
		gameTime = opts.gameTime or 1000000,
		millisPerDay = opts.millisPerDay or 0,
		lines = opts.lines or { 11, 12 },
		usage = {}, -- [line] = { { used, capacity }, ... } (array, as getLineCapacityUsages: cargo type id + 1)
		broken = {}, -- [line] = true: getLineCapacityUsages errors
		listCalls = 0,
	}
	set_global("api", {
		type = {
			ComponentType = { GAME_SPEED = "speed", GAME_TIME = "time" },
			Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end },
		},
		gui = {
			StyleSheet = { new = function() return {} end },
			game = {
				getGuiSaveData = function(modId)
					if world.worker then error("API is currently restricted") end
					if opts.brokenRead then error("no save data") end
					return saveData[modId]
				end,
				setGuiSaveData = function(modId, data)
					if world.worker then error("API is currently restricted") end
					if opts.brokenWrite then error("write failed") end
					saveData[modId] = data
					saves = saves + 1
				end,
			},
		},
		engine = {
			getComponent = function(_w, t)
				if t == "speed" then return { speedup = 1, millisPerDay = world.millisPerDay } end
				if t == "time" then return { gameTime = world.gameTime } end
			end,
			util = {
				getWorld = function() return 1 end,
				getPlayer = function() return 7 end,
				line = { getLineCapacityUsages = function(line, all)
					assert(all == false)
					if world.broken[line] then error("bad line " .. line) end
					local out = {}
					for i, u in ipairs(world.usage[line] or {}) do out[i] = { used = u[1], capacity = u[2] } end
					return out
				end },
			},
			system = { lineSystem = { getLinesForPlayer = function(p)
				assert(p == 7)
				world.listCalls = world.listCalls + 1
				return world.lines
			end } },
		},
		util = {
			getMonthDuration = function(mpd) return mpd * 30 end,
			getDefaultMonthDuration = function() return MONTH end,
			toStringPercentPrecision = opts.noPercent and {} or function(v, d)
				assert(d == 0)
				return string.format("%d%%", math.floor(v * 100 + 0.5))
			end,
		},
	})
	current = "LineStatisticDetails"
	react = {
		getCallingRecipeCtx = function() return current ~= nil and {} or nil end,
		getCurrentRecipeName = function() return current end,
	}
	builtin = {
		type = { Orientation = { Horizontal = "H", Vertical = "V" } },
		TextView = function(p) return { kind = "TextView", text = p.text, class = p.meta and p.meta.class, meta = p.meta } end,
		BoxLayout = function(p) return { kind = "BoxLayout", orientation = p.orientation, children = p.children } end,
	}
	timerCalls, columnCalls = 0, 0
	eru = { useStepStateTimer = function(getter)
		timerCalls = timerCalls + 1
		return { value = getter() }
	end }
	sru = { calculateCargoColumnDataForLine = function(line)
		columnCalls = columnCalls + 1
		return { coverage = 0.5, demand = 100, line = line }
	end }
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/engine_react_util.tl", eru)
	stub_module("::/gui/statistics/statistics_react_util.tl", sru)
	avg = ug_require "square_line_manager_plus::/line_manager_plus/lmp_util_avg.lua"
	if opts.install ~= false then ok(avg.install({})) end
end

local function warnings(text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "warning" and (text == nil or e.msg:find(text, 1, true)) then n = n + 1 end
	end
	return n
end

-- one host timer tick as in game: Main Thread steps (save I/O) around the timer tick, which runs on a worker thread
-- where api.gui.* is restricted
local function tick()
	avg.ioStep()
	world.worker = true
	avg.tick()
	world.worker = false
	avg.ioStep()
end

-- one tick per call, after moving the game time by `dt` ms (0: paused)
local function tickAfter(dt)
	world.gameTime = world.gameTime + dt
	tick()
end

local Q = MONTH / 4 -- the sample interval at the default month

-- LineStatisticDetails' calls in order (manager_window.tl:3830-4000): the name getter, the Capacity value, the
-- coverage getter, the Utilization title and value, the frequency getter and value, the rate getter. Returns the
-- Utilization value node and the other value nodes.
local function render(line, pct)
	local nodes = {}
	eru.useStepStateTimer(function() return "Line " .. line end)
	nodes.capacity = builtin.TextView{ meta = { class = "font-scale-body, details-value" }, text = "120" }
	eru.useStepStateTimer(function() return sru.calculateCargoColumnDataForLine(line).coverage end)
	nodes.title = builtin.TextView{ meta = { class = "font-scale-body, details-title" }, text = "Utilization" }
	nodes.util = builtin.TextView{ meta = { class = "font-scale-body, details-value" }, text = pct or "50%" }
	eru.useStepStateTimer(function() return 90 end)
	nodes.freq = builtin.TextView{ meta = { class = "font-scale-body, details-value" }, text = "1:30" }
	eru.useStepStateTimer(function() return 400 end)
	return nodes.util, nodes
end

local function avgText(node)
	if node.kind ~= "BoxLayout" then return nil end
	return node.children[2].text, node.children[2].meta.tooltip, node.children[2]
end

local function messages(text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if e.level == "message" and e.msg:find(text, 1, true) then n = n + 1 end
	end
	return n
end

-- the capacity summed over `line`'s buckets (samples x capacity), 0 when none
local function capSum(line)
	local h = avg.history(line)
	if h == nil then return 0 end
	local n = 0
	for _i, c in ipairs(h.c) do n = n + c end
	return n
end

local function stored() return saveData.square_line_manager_plus end

-- `n` more passes, one quarter month apart
local function passes(n)
	for _i = 1, n do tickAfter(Q) end
end

-- a saved part with `months` buckets of u,c for each line
local function savedPart(lines, months, u, c, t, m)
	local entries = {}
	for i, line in ipairs(lines) do
		local b = {}
		for k = 1, months do b[k] = u .. "," .. c end
		entries[i] = line .. ":" .. table.concat(b, ";")
	end
	return { v = 1, t = t or 1000000, m = m or 1000000, lines = entries }
end

-- install ------------------------------------------------------------------------------------------------------------

test("install: wraps the two fields once; builtin.TextView untouched outside a render", function()
	setup({ install = false })
	local timer, column, tv = eru.useStepStateTimer, sru.calculateCargoColumnDataForLine, builtin.TextView
	ok(avg.install({}))
	ok(avg.install({}))
	ok(eru.useStepStateTimer ~= timer)
	ok(sru.calculateCargoColumnDataForLine ~= column)
	ok(builtin.TextView == tv)
	-- pass-through outside a capture
	eq(sru.calculateCargoColumnDataForLine(5).line, 5)
	eq(eru.useStepStateTimer(function() return 3 end).value, 3)
	eq(warnings(), 0)
end)

test("install: a missing field installs nothing, logged once", function()
	setup({ install = false })
	sru.calculateCargoColumnDataForLine = nil
	local timer = eru.useStepStateTimer
	ok(not avg.install({}))
	ok(eru.useStepStateTimer == timer)
	eq(warnings("average utilization: install"), 1)
end)

-- sampling -----------------------------------------------------------------------------------------------------------

test("sampling: game time driven; the timer firing while paused takes no sample", function()
	setup()
	world.usage[11] = { { 50, 100 } }
	tick() -- first pass at once
	eq(capSum(11), 100)
	eq(world.listCalls, 1)
	for _i = 1, 20 do tickAfter(0) end -- paused: callbacks fire, game time stands
	eq(capSum(11), 100)
	eq(world.listCalls, 1)
	tickAfter(Q - 1) -- not yet an interval
	eq(capSum(11), 100)
	tickAfter(1)
	eq(capSum(11), 200)
	tickAfter(10 * Q) -- a long jump: still one sample per pass, and one month closed
	eq(capSum(11), 300)
	eq(avg.buckets(11), 2)
end)

test("sampling: the month length follows the calendar speed; default month when frozen", function()
	setup({ millisPerDay = 4000 }) -- month = 120000 in the fake
	world.usage[11] = { { 10, 100 } }
	tick()
	tickAfter(Q) -- a quarter of the default month: not a quarter of this one
	eq(capSum(11), 100)
	tickAfter(Q)
	eq(capSum(11), 200)
	world.millisPerDay = 0 -- frozen calendar: default month
	tickAfter(Q)
	eq(capSum(11), 300)
	eq(avg.monthMs(), MONTH)
end)

test("buckets: a month closes at the first pass a month after it began; four samples each", function()
	setup({ lines = { 11 } })
	world.usage[11] = { { 30, 100 } }
	tick()
	passes(3)
	eq(avg.buckets(11), 1)
	eq(avg.history(11).c[1], 400)
	passes(1) -- one month after the first pass
	eq(avg.buckets(11), 2)
	eq(avg.history(11).c[1], 400)
	eq(avg.history(11).c[2], 100)
	eq(avg.history(11).u[1], 120)
end)

test("windows: the current month plus N closed months; only the last 12 months count for avg", function()
	setup({ lines = { 11 } })
	world.usage[11] = { { 100, 100 } } -- 100 % for the first 12 months
	tick()
	passes(47) -- 48 samples, 12 months, the 12th month not yet closed
	local a, full, months = avg.average(11)
	near(a, 1.0)
	ok(not full)
	eq(months, 11)
	passes(1) -- the 12th month closes
	a, full, months = avg.average(11)
	near(a, 1.0)
	ok(full)
	eq(months, 12)
	world.usage[11] = { { 0, 100 } } -- then empty
	passes(24) -- 6 months
	a, full = avg.average(11)
	-- window: the current month (1 empty sample) + 12 closed (6 full months, one with 1 full + 3 empty samples, 5 empty)
	near(a, 25 / 49)
	ok(full)
	-- the 5-year window holds everything since the start: 49 full of 73 samples
	a, full, months = avg.average(11, 60)
	near(a, 49 / 73)
	ok(not full)
	eq(months, 18)
end)

test("windows: at most 61 buckets; the 5-year window full after 60 closed months", function()
	setup({ lines = { 11 } })
	world.usage[11] = { { 50, 100 } }
	tick()
	passes(4 * 70)
	eq(avg.buckets(11), avg.MAX_BUCKETS)
	local a, full, months = avg.average(11, 60)
	near(a, 0.5)
	ok(full)
	eq(months, 60)
end)

test("texts: '~' and the months covered per window until it is full", function()
	setup({ lines = { 11 } })
	world.usage[11] = { { 87, 100 } }
	tick()
	local text, tip = avg.texts(11)
	eq(text, "avg ~87%")
	eq(tip, "Average utilization:\nLast 12 months: ~87% (0 of 12 months)\nLast 2 years: ~87% (0 of 24 months)\n"
		.. "Last 5 years: ~87% (0 of 60 months)")
	passes(4 * 14) -- 14 months closed
	text, tip = avg.texts(11)
	eq(text, "avg 87%")
	eq(tip, "Average utilization:\nLast 12 months: 87%\nLast 2 years: ~87% (14 of 24 months)\n"
		.. "Last 5 years: ~87% (14 of 60 months)")
	passes(4 * 50)
	text, tip = avg.texts(11)
	eq(tip, "Average utilization:\nLast 12 months: 87%\nLast 2 years: 87%\nLast 5 years: 87%")
	for _line in tip:gmatch("[^\n]+") do ok(#_line <= 70) end
end)

test("weighting: capacity-weighted over samples and cargo types; lines kept apart", function()
	setup()
	world.usage[11] = { { 10, 100 }, { 0, 0 }, { 30, 100 } } -- 40 / 200; the 0-capacity type is left out
	world.usage[12] = { { 9, 10 } }
	tick()
	near((avg.average(11)), 0.2)
	near((avg.average(12)), 0.9)
	world.usage[11] = { { 300, 300 } } -- a sample with more capacity weighs more
	tickAfter(Q)
	near((avg.average(11)), 340 / 500)
	near((avg.average(12)), 0.9)
end)

test("nothing to show: no sample yet, or no capacity in the window", function()
	setup()
	eq(avg.texts(11), nil)
	world.usage[11] = {} -- a line without vehicles
	tick()
	eq(avg.buckets(11), 1)
	eq(avg.texts(11), nil)
end)

test("removed lines are dropped at the end of a pass", function()
	setup({ lines = { 11, 12, 13 } })
	tick()
	eq(avg.lineCount(), 3)
	world.lines = { 11, 13 }
	tickAfter(Q)
	eq(avg.lineCount(), 2)
	eq(avg.buckets(12), 0)
	eq(avg.buckets(11), 1)
end)

test("caps: at most PER_TICK lines per tick, a pass continues at the next ticks; MAX_LINES per pass", function()
	local lines = {}
	for i = 1, 250 do lines[i] = 1000 + i end
	setup({ lines = lines })
	tick()
	eq(avg.lineCount(), avg.PER_TICK)
	tickAfter(0) -- paused: the pass in progress still finishes, with its own game time
	eq(avg.lineCount(), 2 * avg.PER_TICK)
	tickAfter(0)
	eq(avg.lineCount(), 250)
	eq(world.listCalls, 1)
	tickAfter(0) -- pass done, game time stands: nothing new
	eq(world.listCalls, 1)
	-- the per-pass cap
	avg.MAX_LINES = 120
	tickAfter(Q)
	tickAfter(0)
	eq(avg.buckets(1001), 1)
	eq(avg.buckets(1121), 0) -- beyond the cap: not sampled this pass, then dropped as unseen
	eq(avg.lineCount(), 120)
	eq(warnings("average utilization: cap"), 1)
	avg.MAX_LINES = 5000
end)

test("sampling errors: a broken line is skipped and logged once; the others are sampled", function()
	setup({ lines = { 11, 12 } })
	world.broken[11] = true
	world.usage[12] = { { 1, 10 } }
	tick()
	tickAfter(Q)
	eq(avg.buckets(11), 0)
	eq(capSum(12), 20)
	eq(warnings("average utilization: sample"), 1)
end)

-- savegame -----------------------------------------------------------------------------------------------------------

test("save: written only when a month closed, at the end of that pass; the format", function()
	setup({ lines = { 11, 12 } })
	world.usage[11] = { { 30, 100 } }
	world.usage[12] = { { 5, 10 } }
	tick()
	passes(3)
	eq(saves, 0) -- no month closed yet
	passes(1)
	eq(saves, 1)
	local part = stored().util
	eq(part.v, 1)
	eq(part.t, world.gameTime)
	eq(part.m, world.gameTime)
	eq(#part.lines, 2)
	local byLine = {}
	for _i, s in ipairs(part.lines) do byLine[s:match("^(%d+):")] = s end
	eq(byLine["11"], "11:120,400;30,100")
	eq(byLine["12"], "12:20,40;5,10")
	passes(3)
	eq(saves, 1) -- at most once a month
	passes(1)
	eq(saves, 2)
	eq(saveData.other_mod.x, 1)
end)

test("save: the round trip through a reload keeps the history and the month", function()
	setup({ lines = { 11 } })
	world.usage[11] = { { 87, 100 } }
	tick()
	passes(4 * 13) -- 13 months closed, written at the last close
	local before = { avg.texts(11) }
	local t = world.gameTime
	-- the player saves now and loads that save: the GUI scripts reload, the save data and game time come back
	setup({ lines = { 11 }, keepSave = true, gameTime = t })
	world.usage[11] = { { 87, 100 } }
	eq(avg.buckets(11), 0) -- read lazily at the first tick
	tick() -- restores; same game time: no pass yet
	eq(avg.buckets(11), 14)
	eq(world.listCalls, 0)
	eq(messages("restored the history of 1 lines"), 1)
	local text, tip = avg.texts(11)
	eq(text, before[1])
	eq(tip, before[2])
	passes(3)
	eq(avg.buckets(11), 14) -- the month continues where the save left it
	passes(1)
	eq(avg.buckets(11), 15)
end)

test("save: lines removed since are dropped from the next write", function()
	setup({ lines = { 11, 12 } })
	tick()
	passes(4)
	eq(#stored().util.lines, 2)
	world.lines = { 11 }
	passes(4)
	eq(#stored().util.lines, 1)
	ok(stored().util.lines[1]:find("^11:") ~= nil)
end)

test("save: merged with lmp_visible's part both ways; neither wipes the other", function()
	setup({ lines = { 11 }, stored = { lineManager = true } })
	world.usage[11] = { { 1, 2 } }
	tick()
	passes(4)
	eq(stored().lineManager, true)
	ok(stored().util ~= nil)
	-- lmp_visible.lua writes through the same module: the history stays
	stub_module("::/gui/main/popover_react_util.tl", {})
	stub_module("::/gui/line_vehicle_mgmt/manager_window.tl", {})
	local vis = ug_require "square_line_manager_plus::/line_manager_plus/lmp_visible.lua"
	vis.set("lineManager", false)
	eq(stored().lineManager, false)
	eq(#stored().util.lines, 1)
	passes(4)
	eq(stored().lineManager, false)
	eq(avg.buckets(11), 3)
	eq(stored().util.lines[1], "11:4,8;4,8;1,2")
	-- unknown parts (a newer revision's) are kept
	saveData.square_line_manager_plus.future = { y = 2 }
	setup({ lines = { 11 }, keepSave = true, gameTime = world.gameTime })
	tick()
	passes(4)
	eq(stored().future.y, 2)
	eq(stored().lineManager, false)
end)

test("save: a failed read never writes (it would replace the other parts)", function()
	setup({ lines = { 11 }, brokenRead = true, stored = { lineManager = true } })
	tick()
	passes(8)
	eq(saves, 0)
	eq(stored().lineManager, true)
	eq(warnings("average utilization: load"), 1)
	eq(avg.buckets(11), 3) -- the history still runs for this load
end)

test("save: a failed write is logged once and retried only at the next month", function()
	setup({ lines = { 11 }, brokenWrite = true })
	tick()
	passes(12)
	eq(warnings("average utilization: save"), 1)
	eq(avg.buckets(11), 4)
end)

test("save: bad saved data is ignored whole or per entry, never raises", function()
	local T = 1000000
	local cases = {
		{ name = "not a table", part = 42 },
		{ name = "another format", part = { v = 2, t = T, m = T, lines = {} } },
		{ name = "no version", part = { t = T, m = T, lines = {} } },
		{ name = "NaN time", part = { v = 1, t = 0 / 0, m = T, lines = {} } },
		{ name = "negative time", part = { v = 1, t = -5, m = -5, lines = {} } },
		{ name = "month after the pass", part = { v = 1, t = T, m = T + 1, lines = {} } },
		{ name = "saved after this game time", part = { v = 1, t = T + 1, m = T, lines = {} } },
		{ name = "lines not a table", part = { v = 1, t = T, m = T, lines = "11:1,2" } },
		{ name = "string time", part = { v = 1, t = "1000000", m = T, lines = {} } },
	}
	for _i, case in ipairs(cases) do
		setup({ lines = { 11 }, stored = { util = case.part } })
		tick()
		eq(avg.buckets(11), 1, case.name)
		eq(messages("saved history not used"), 1, case.name)
		eq(warnings(), 0, case.name)
	end
end)

test("save: malformed entries are skipped; long ones trimmed to the newest months; used clamped", function()
	local long = {}
	for k = 1, 70 do long[k] = k .. ",100" end
	local part = { v = 1, t = 1000000, m = 1000000, lines = {
		"11:" .. table.concat(long, ";"), -- 70 buckets: the newest 61 kept
		"12:500,100", -- used above the capacity: clamped
		"13:1,2;;3,4", -- empty bucket
		"14:1,2;", -- trailing separator
		"15:1,2,3", -- three numbers
		"x:1,2", -- no id
		"0:1,2", -- id 0
		"16:-1,2", -- negative
		"17:1.5,2", -- not an integer
		"12:1,1", -- duplicate: the first kept
		42, -- not a string
		"18:" .. string.rep("1,1;", 2000) .. "1,1", -- too long
		"19:99999999999999999,99999999999999999", -- too large
		"20:1,2",
	} }
	setup({ lines = { 11, 12, 20 }, stored = { util = part } })
	tick()
	eq(messages("restored the history of 3 lines (11 bad entries skipped)"), 1)
	eq(avg.buckets(11), 61)
	eq(avg.history(11).u[1], 10)
	eq(avg.buckets(12), 1)
	eq(avg.history(12).u[1], 100)
	eq(avg.buckets(20), 1)
	eq(warnings(), 0)
end)

test("save: a save from before this feature or a new game starts empty, quietly", function()
	setup({ lines = { 11 }, stored = { lineManager = true } })
	tick()
	eq(avg.buckets(11), 1)
	eq(messages("saved history"), 0)
	eq(messages("restored"), 0)
	setup({ lines = { 11 } })
	tick()
	eq(avg.buckets(11), 1)
end)

test("save: at most MAX_SAVE_LINES lines are written", function()
	local lines = {}
	for i = 1, 30 do lines[i] = 100 + i end
	setup({ lines = lines })
	avg.MAX_SAVE_LINES = 10
	tick()
	passes(4)
	eq(#stored().util.lines, 10)
	avg.MAX_SAVE_LINES = 2000
end)

test("game time going back clears the history, written at the next pass", function()
	setup({ lines = { 11 } })
	world.usage[11] = { { 1, 1 } }
	tick()
	passes(5)
	eq(avg.buckets(11), 2)
	world.gameTime = world.gameTime - 10 * Q
	tick()
	eq(avg.buckets(11), 1)
	eq(messages("history cleared"), 1)
	eq(#stored().util.lines, 1)
	eq(stored().util.lines[1], "11:1,1")
end)

-- render -------------------------------------------------------------------------------------------------------------

test("render: only the Utilization value gets the avg; the swap is one-shot and undone", function()
	setup()
	local tv = builtin.TextView
	world.usage[11] = { { 87, 100 } }
	tick()
	local util, nodes = render(11, "50%")
	eq(util.kind, "BoxLayout")
	eq(util.orientation, "H")
	eq(util.children[1].text, "50%")
	eq(util.children[1].class, "font-scale-body, details-value")
	local text, tip, node = avgText(util)
	eq(text, "avg ~87%")
	ok(tip:find("Last 5 years", 1, true) ~= nil)
	eq(util.children[1].meta.tooltip, tip) -- hovering the live value shows it too
	eq(node.class, "font-scale-annotation, positive")
	eq(nodes.capacity.kind, "TextView")
	eq(nodes.title.kind, "TextView")
	eq(nodes.freq.kind, "TextView")
	ok(builtin.TextView == tv)
	eq(warnings(), 0)
end)

test("render: one row per selected line, each with its own average", function()
	setup()
	world.usage[11] = { { 20, 100 } }
	world.usage[12] = { { 90, 100 } }
	tick()
	eq((avgText(render(11))), "avg ~20%")
	eq((avgText(render(12))), "avg ~90%")
end)

test("render: no samples yet -> the base cell as is", function()
	setup()
	local util = render(11)
	eq(util.kind, "TextView")
	eq(util.text, "50%")
end)

test("render: outside LineStatisticDetails nothing is probed or swapped", function()
	setup()
	world.usage[11] = { { 50, 100 } }
	tick()
	current = "VehicleManager"
	local tv = builtin.TextView
	local util = render(11)
	eq(util.kind, "TextView")
	ok(builtin.TextView == tv)
end)

test("render: a swap left standing is undone at the next tick", function()
	setup()
	world.usage[11] = { { 50, 100 } }
	tick()
	local tv = builtin.TextView
	eru.useStepStateTimer(function() return sru.calculateCargoColumnDataForLine(11).coverage end)
	ok(builtin.TextView ~= tv) -- armed
	tick()
	ok(builtin.TextView == tv)
end)

test("errors: a failing decoration or percent formatter falls through to the base cell, logged once", function()
	setup({ noPercent = true }) -- api.util.toStringPercentPrecision not callable: own format
	world.usage[11] = { { 87, 100 } }
	tick()
	eq((avgText(render(11))), "avg ~87%")
	-- a broken StyleSheet: the base value node, logged once
	api.gui.StyleSheet.new = function() error("no style") end
	local util = render(11)
	eq(util.kind, "TextView")
	eq(util.text, "50%")
	render(11)
	eq(warnings("average utilization: decorate"), 1)
	-- a getter that errors under the probe: the base call still happens
	local before = timerCalls
	local okCall = pcall(eru.useStepStateTimer, function() error("getter boom") end)
	ok(not okCall) -- the base's own call of the getter raises, as without the mod
	eq(timerCalls, before + 1)
	eq(warnings("average utilization: timer"), 0) -- our probe call failed quietly: not our error
end)

test("errors: a broken engine in tick is logged once and never raises", function()
	setup()
	api.engine.system.lineSystem.getLinesForPlayer = function() error("no lines") end
	tick()
	tickAfter(Q)
	eq(warnings("average utilization: tick"), 1)
end)
