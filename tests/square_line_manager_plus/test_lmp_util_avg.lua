-- Line Manager Plus: the 12-month average utilization beside the Line Manager's Utilization value (lmp_util_avg.lua),
-- with fake react / builtin / engine_react_util / statistics_react_util modules and a fake engine (game time, calendar
-- speed, lines and their capacity usages).
-- Covers: install (wraps the two fields once, builtin.TextView untouched outside a render), sampling (game time
-- driven: no sample while the game time stands even though the timer fires, one per quarter month, the calendar
-- speed's month length and the default month when frozen), the ring and the 12-month window, the "~" since-load state
-- and its months, capacity weighting (per sample and over cargo types; lines kept apart), removed lines dropped, the
-- per-tick and per-pass caps, the render (only the Utilization value of LineStatisticDetails gets the avg, one-shot,
-- the swap undone), and errors (the base cell unchanged, logged once).

local react, builtin, eru, sru, avg, world, current, timerCalls, columnCalls

local MONTH = 60000 -- the fake default month (game ms)

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	world = {
		gameTime = 1000000,
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
		gui = { StyleSheet = { new = function() return {} end } },
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

-- one tick per call, after moving the game time by `dt` ms (0: paused)
local function tickAfter(dt)
	world.gameTime = world.gameTime + dt
	avg.tick()
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
	avg.tick() -- first pass at once
	eq(avg.count(11), 1)
	eq(world.listCalls, 1)
	for _i = 1, 20 do tickAfter(0) end -- paused: callbacks fire, game time stands
	eq(avg.count(11), 1)
	eq(world.listCalls, 1)
	tickAfter(Q - 1) -- not yet an interval
	eq(avg.count(11), 1)
	tickAfter(1)
	eq(avg.count(11), 2)
	tickAfter(10 * Q) -- a long jump: still one sample per pass
	eq(avg.count(11), 3)
end)

test("sampling: the month length follows the calendar speed; default month when frozen", function()
	setup({ millisPerDay = 4000 }) -- month = 120000 in the fake
	world.usage[11] = { { 10, 100 } }
	avg.tick()
	tickAfter(Q) -- a quarter of the default month: not a quarter of this one
	eq(avg.count(11), 1)
	tickAfter(Q)
	eq(avg.count(11), 2)
	world.millisPerDay = 0 -- frozen calendar: default month
	tickAfter(Q)
	eq(avg.count(11), 3)
	eq(avg.monthMs(), MONTH)
end)

test("ring and window: only the last 12 months count; the ring stays bounded", function()
	setup({ lines = { 11 } })
	world.usage[11] = { { 100, 100 } } -- 100 % for the first 12 months
	avg.tick()
	for _i = 2, 48 do tickAfter(Q) end
	local a, full, months = avg.average(11)
	near(a, 1.0)
	ok(full)
	eq(months, 12)
	world.usage[11] = { { 0, 100 } } -- then empty
	for _i = 1, 24 do tickAfter(Q) end -- 6 months
	a, full = avg.average(11)
	near(a, 0.5) -- 24 full + 24 empty samples in the window
	ok(full)
	for _i = 1, 200 do tickAfter(Q) end
	ok(avg.count(11) <= avg.RING)
	near((avg.average(11)), 0.0)
end)

test("since load: '~' and the months so far until 12 months are covered", function()
	setup({ lines = { 11 } })
	world.usage[11] = { { 87, 100 } }
	avg.tick()
	local text, tip = avg.texts(11)
	eq(text, "avg ~87%")
	eq(tip, "Average utilization since the game was loaded\n(0 of 12 months so far).")
	for _i = 2, 12 do tickAfter(Q) end -- 12 samples = 3 months
	text, tip = avg.texts(11)
	eq(text, "avg ~87%")
	ok(tip:find("(3 of 12 months so far)", 1, true))
	for _i = 13, 47 do tickAfter(Q) end
	eq((avg.texts(11)), "avg ~87%")
	tickAfter(Q) -- the 48th sample: 12 months
	text, tip = avg.texts(11)
	eq(text, "avg 87%")
	eq(tip, "Average utilization over the last 12 months.")
end)

test("weighting: capacity-weighted over samples and cargo types; lines kept apart", function()
	setup()
	world.usage[11] = { { 10, 100 }, { 0, 0 }, { 30, 100 } } -- 40 / 200; the 0-capacity type is left out
	world.usage[12] = { { 9, 10 } }
	avg.tick()
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
	avg.tick()
	eq(avg.count(11), 1)
	eq(avg.texts(11), nil)
end)

test("removed lines are dropped at the end of a pass", function()
	setup({ lines = { 11, 12, 13 } })
	avg.tick()
	eq(avg.lineCount(), 3)
	world.lines = { 11, 13 }
	tickAfter(Q)
	eq(avg.lineCount(), 2)
	eq(avg.count(12), 0)
	eq(avg.count(11), 2)
end)

test("caps: at most PER_TICK lines per tick, a pass continues at the next ticks; MAX_LINES per pass", function()
	local lines = {}
	for i = 1, 250 do lines[i] = 1000 + i end
	setup({ lines = lines })
	avg.tick()
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
	eq(avg.count(1001), 2)
	eq(avg.count(1121), 0) -- beyond the cap: not sampled this pass, then dropped as unseen
	eq(avg.lineCount(), 120)
	eq(warnings("average utilization: cap"), 1)
	avg.MAX_LINES = 5000
end)

test("sampling errors: a broken line is skipped and logged once; the others are sampled", function()
	setup({ lines = { 11, 12 } })
	world.broken[11] = true
	avg.tick()
	tickAfter(Q)
	eq(avg.count(11), 0)
	eq(avg.count(12), 2)
	eq(warnings("average utilization: sample"), 1)
end)

-- render -------------------------------------------------------------------------------------------------------------

test("render: only the Utilization value gets the avg; the swap is one-shot and undone", function()
	setup()
	local tv = builtin.TextView
	world.usage[11] = { { 87, 100 } }
	avg.tick()
	local util, nodes = render(11, "50%")
	eq(util.kind, "BoxLayout")
	eq(util.orientation, "H")
	eq(util.children[1].text, "50%")
	local text, tip, node = avgText(util)
	eq(text, "avg ~87%")
	ok(tip ~= nil)
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
	avg.tick()
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
	avg.tick()
	current = "VehicleManager"
	local tv = builtin.TextView
	local util = render(11)
	eq(util.kind, "TextView")
	ok(builtin.TextView == tv)
end)

test("render: a swap left standing is undone at the next tick", function()
	setup()
	world.usage[11] = { { 50, 100 } }
	avg.tick()
	local tv = builtin.TextView
	eru.useStepStateTimer(function() return sru.calculateCargoColumnDataForLine(11).coverage end)
	ok(builtin.TextView ~= tv) -- armed
	avg.tick()
	ok(builtin.TextView == tv)
end)

test("errors: a failing decoration or percent formatter falls through to the base cell, logged once", function()
	setup({ noPercent = true }) -- api.util.toStringPercentPrecision not callable: own format
	world.usage[11] = { { 87, 100 } }
	avg.tick()
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
	avg.tick()
	tickAfter(Q)
	eq(warnings("average utilization: tick"), 1)
end)
