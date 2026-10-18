-- OT Dev window (otd_hud.script.lua) with fake react / builtin / api: the tab layout (Stress Test style), the
-- remembered tab, the green "go" buttons, button -> command mapping, and that every button of every tab runs
-- without an error. Plus the pure helpers of otd_hudview.lua.

local V = ug_require "/organic_towns_dev/otd_hudview.lua"

---------------------------------------------------------------------------
-- fakes

local sent, steps, opened, nowT, status

local function baseStatus()
	return {
		main = true, mainPhase = "run", mainOff = "", mainCounts = "checks 1, builds 0, fails 0, refused 0",
		paused = false, ownJoins = false, player = true, debug = "param", busy = "", queue = 0, log = {},
		town = "", townLines = {}, plan = "", rb = true, rbWhy = nil,
		showOpts = { fill = false, freeze = false, ringMode = "oneway", shapes = true, density = true, settle = "off",
			settleCap = 20, settleForce = false, tourAfter = false },
		show = { phase = "grow", head = "Showcase grow: 2/2 towns, 3 increments built, 2 towns still growing, round 2",
			towns = { { key = "A", label = "Town A", x = 100, y = 200 }, { key = "B", label = "Town B", x = 900, y = 200 } },
			lines = { "Town A: step 1/2" }, focus = {}, autoTour = 0 },
		allTowns = { { key = "ALL_1", label = "Big", x = 5, y = 5 } },
	}
end

local function newState(v)
	local s = { v = v }
	function s:old() return self.v end
	function s:set(x) self.v = x end
	function s:hasExpired() return false end
	return s
end

local function load()
	reset_modules()
	sent, steps, opened, nowT, status = {}, {}, nil, 1000000, baseStatus()
	clear_logs()
	stub_module("::/gui/main/react.lua", {
		RegisterRecipe = function(_n, fn) return function(p) return fn(p) end end,
		RegisterWrapperRecipe = function(name, _base, fn) return { name = name, fn = fn } end,
		RegisterPluginRecipe = function(_ext, _n, fn) return fn end,
		useState = newState,
		useRef = function(v)
			local r = { v = v }
			function r:get() return self.v end
			function r:set(x) self.v = x end
			return r
		end,
		useRefLazy = function(f)
			local r = { v = f() }
			function r:get() return self.v end
			return r
		end,
		onStep = function(fn) steps[#steps + 1] = fn end,
		onEvent = function() end,
	})
	local builtin = setmetatable({
		type = { Orientation = { Horizontal = 1, Vertical = 2 }, ScrollBarPolicy = { AlwaysOff = 0, AsNeeded = 1 },
			TabOrientation = { North = 0 } },
	}, { __index = function(_t, k) return function(p) p.__type = k return p end end })
	stub_module("::/gui/main/builtin.lua", builtin)
	stub_module("::/gui/main/main_mod_button_area.tl", { MainModButtonAreaExtension = "ext" })
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultWindowApi = function()
		return { addSingletonWindow = function(rec) opened = rec end, moveSingletonWindowToFront = function() end,
			removeAllWindows = function() opened = nil end }
	end })
	set_global("api", {
		type = { Clock = { new = function() return { getTime = function() return nowT end } end },
			Vec5f = { new = function(x, y, z, w, q) return { x = x, y = y, z = z, w = w, q = q } end } },
		gui = {
			fireGuiScriptEvent = function(_id, _ev, p)
				sent[#sent + 1] = p
				return status
			end,
			game = { isMapEditor = function() return false end },
			camera = {
				getCameraData = function() return { x = 100, y = 200, z = 1800, w = 0.1, q = 0.6 } end,
				setCameraData = function() end,
				takeScreenshot = function() end,
			},
		},
	})
	ug_require "/organic_towns_dev/otd_hud.script.lua"
	local plugin = data().OtdHudPlugin
	local root = plugin()
	root.children[1].onClick()   -- the OT Dev HUD button opens the window
	assert(opened ~= nil and opened.name == "OtdWindow", "window opened")
	sent = {}
end

local function render()
	return opened.fn({ onClose = function() end }).content
end

local function walk(node, fn)
	if type(node) ~= "table" then return end
	fn(node)
	for _, k in ipairs({ "content", "layout", "item", "indicator" }) do walk(node[k], fn) end
	for _, k in ipairs({ "children", "tabs", "buttons" }) do
		if type(node[k]) == "table" then
			for _, c in ipairs(node[k]) do walk(c, fn) end
		end
	end
end

local function find(tree, typ, label)
	local out = nil
	walk(tree, function(n)
		if out == nil and n.__type == typ then
			local l = n.label or n.text or (n.content and n.content.text)
			if label == nil or l == label then out = n end
		end
	end)
	return out
end

local function all(tree, typ)
	local out = {}
	walk(tree, function(n) if n.__type == typ then out[#out + 1] = n end end)
	return out
end

local function tabWidget(tree) return find(tree, "TabWidget") end

local function select(key)
	tabWidget(render()).onValueChange(key)
	return render()
end

local function lastSent() return sent[#sent] end

local function warnings()
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.level == "warning" then out[#out + 1] = e.msg end
	end
	return out
end

---------------------------------------------------------------------------
-- pure helpers

test("hudview: tab keys, unknown key falls back to Simulate", function()
	local keys = {}
	for i, t in ipairs(V.TABS) do keys[i] = t.key end
	eq(table.concat(keys, ","), "sim,showcase,town,main,camera")
	eq(V.tabKey("town"), "town")
	eq(V.tabKey("nope"), "sim")
	eq(V.tabKey(nil), "sim")
end)

test("hudview: status lines (link, main driver, task + queue, progress, tour)", function()
	ok(V.linkText(nil):find("no reply", 1, true))
	eq(V.linkText({}, "boom"), "Link: sending failed: boom")
	eq(V.linkText({ main = true }, nil, 2.4), "Link: ok (status 2 s old)")
	eq(V.mainText(nil), nil)
	eq(V.mainText({ main = true, mainPhase = "run", paused = true, mainCounts = "checks 3" }), "Main driver: PAUSED, run, checks 3")
	ok(V.mainText({ main = false }):find("NOT visible", 1, true))
	eq(V.taskText(nil), "Task: nothing")
	eq(V.taskText({ busy = "grow Town A", queue = 2 }), "Task: grow Town A (+2 queued)")
	local lines = V.progressLines({ sim = { head = "Running: 3 simulated years" }, show = { head = "Showcase grow" } }, "Tour x")
	eq(#lines, 3)
	eq(lines[1], "Simulation: Running: 3 simulated years")
	eq(V.tourText(nil, false), nil)
	eq(V.tourText(nil, true), "Tour: waits for the showcase settle to end")
	eq(V.tourText({ i = 3 }, false, 12, "all", "Big"), "Tour (all towns): town 3/12: Big")
end)

test("hudview: simStart params, ring and debug pickers", function()
	local p = V.simStartParams({ simPace = 2, simSeed = 3, simLimit = 1, simNear = true, simBias = false, simTour = true }, 5, 6)
	eq(p.pace, 2); eq(p.seed, 3); eq(p.limit, 1); eq(p.scope, "near"); eq(p.x, 5); eq(p.y, 6)
	eq(p.bias, false); eq(p.tourWhenDone, true)
	eq(p.fastFill, true, "Fast fill on unless switched off"); eq(p.waitMain, true); eq(p.speedUp, true)
	eq(p.buildRound, true, "build round on unless switched off")
	eq(V.simStartParams({ simRound = false }).buildRound, false)
	p = V.simStartParams({ simFill = false, simWait = false, simSpeedUp = false, simFillEvery = 3 }, nil, nil)
	eq(p.fastFill, false); eq(p.waitMain, false); eq(p.speedUp, false); eq(p.fillEvery, 3)
	local SG = ug_require "/organic_towns_dev/otd_simgrow.lua"
	local o = V.applyQuick({ simPace = 5, simLimit = 1, simFill = false, simWait = false, simSpeedUp = false, simRound = false }, SG)
	eq(o.simRound, true)
	eq(SG.PACES[o.simPace], SG.QUICK.pace); eq(SG.LIMITS[o.simLimit], SG.QUICK.limit)
	eq(SG.FILL_EVERY[o.simFillEvery], SG.QUICK.fillEvery)
	eq(o.simFill, true); eq(o.simWait, true); eq(o.simSpeedUp, true)
	eq(V.ringIndex("oneway"), 1)
	eq(V.ringIndex("twoway"), 2)
	eq(V.ringToggle(1, "oneway"), false)
	eq(V.ringToggle(2, "oneway"), true)
	eq(V.ringToggle(1, nil), true)
	eq(V.debugIndex("off"), 3)
	eq(V.debugIndex(nil), 1)
end)

---------------------------------------------------------------------------
-- window

test("window: status and queue on top, tabs in order, Simulate selected first, only that tab built", function()
	load()
	local tree = render()
	ok(find(tree, "TextView", "Link: ok (status 0 s old)"), "link line")
	ok(find(tree, "TextView", "Task: nothing"), "queue line")
	ok(find(tree, "Button", "Stop dev tasks"), "stop at the top")
	ok(find(tree, "TextView", status.show.head), "showcase progress at the top")
	local tw = tabWidget(tree)
	eq(tw.value, "sim")
	local labels = {}
	for i, t in ipairs(tw.tabs) do labels[i] = t.indicator.text end
	eq(table.concat(labels, "|"), "Simulate|Showcase|Town|Main mod|Camera & tour")
	ok(find(tw.tabs[1], "Button", "Simulate natural growth"), "Simulate tab content")
	eq(find(tw.tabs[2], "Button"), nil, "unselected tabs are empty")
end)

test("window: the selected tab is remembered after closing and reopening", function()
	load()
	local tree = select("town")
	eq(tabWidget(tree).value, "town")
	ok(find(tree, "Button", "Grow now"))
	-- close + reopen (the HUD button toggles the window)
	local hud = data().OtdHudPlugin().children[1]
	hud.onClick()
	eq(opened, nil, "closed")
	hud.onClick()
	eq(tabWidget(render()).value, "town")
end)

test("window: primary actions are green and send their commands", function()
	load()
	local tree = render()
	local b = find(tree, "Button", "Simulate natural growth")
	eq(b.meta.class, "sqotd-go")
	b.onClick()
	eq(lastSent().action, "simStart")
	eq(lastSent().scope, "all")
	eq(lastSent().tourWhenDone, true)
	eq(find(tree, "Button", "Tour all towns").meta.class, "sqotd-go")

	tree = select("showcase")
	b = find(tree, "Button", "Showcase: build all")
	eq(b.meta.class, "sqotd-go")
	b.onClick()
	eq(lastSent().action, "showcase")
	eq(lastSent().sn, 2)
	eq(find(tree, "Button", "Auto tour").meta.class, "sqotd-go")

	tree = select("town")
	b = find(tree, "Button", "Grow now")
	eq(b.meta.class, "sqotd-go")
	b.onClick()
	eq(lastSent().action, "grow")

	tree = select("main")
	b = find(tree, "Button", "Fast-forward all")
	eq(b.meta.class, "sqotd-go")
	b.onClick()
	eq(lastSent().action, "fast")
end)

test("window: Quick preset is green, sets the pickers and starts; Fast fill options send simOpt to a known run", function()
	load()
	local SG = ug_require "/organic_towns_dev/otd_simgrow.lua"
	local tree = render()
	local q = find(tree, "Button", "Quick: " .. SG.QUICK.limit .. " years")
	ok(q, "quick button")
	eq(q.meta.class, "sqotd-go")
	q.onClick()
	local p = lastSent()
	eq(p.action, "simStart")
	eq(SG.PACES[p.pace], SG.QUICK.pace); eq(SG.LIMITS[p.limit], SG.QUICK.limit)
	eq(SG.FILL_EVERY[p.fillEvery], SG.QUICK.fillEvery)
	eq(p.fastFill, true); eq(p.waitMain, true); eq(p.speedUp, true)
	tree = render()
	local n = #sent
	find(tree, "CheckBox", "Fast fill: houses catch up at once").onValueChange(0)
	eq(#sent, n, "no simulation known yet: nothing sent")
	status.sim = { running = false, head = "Stopped: 2 simulated years" }
	find(render(), "Button", "Pause main driver").onClick()   -- any send: the status comes back
	find(render(), "CheckBox", "Wait for the main mod in each fill year (when the build round is off)").onValueChange(0)
	eq(lastSent().action, "simOpt"); eq(lastSent().waitMain, false)
	find(render(), "CheckBox", "Build round: the main mod's turn on every grown town").onValueChange(0)
	eq(lastSent().action, "simOpt"); eq(lastSent().buildRound, false)
	local fill = nil
	for _, g in ipairs(all(render(), "ToggleButtonGroup")) do
		if g.buttons[1].content.text == "1" and #g.buttons == #SG.FILL_EVERY then fill = g end
	end
	ok(fill, "fill every picker")
	fill.onValueChange(3)
	eq(lastSent().action, "simOpt"); eq(lastSent().fillEvery, 3)
end)

test("window: a running simulation shows Stop simulation (red) in the tab and at the top", function()
	load()
	status.sim = { running = true, head = "Running: 4 simulated years" }
	find(render(), "Button", "Pause main driver").onClick()   -- any send: the status comes back
	local tree = render()
	local stops = {}
	walk(tree, function(n) if n.__type == "Button" and n.content.text == "Stop simulation" then stops[#stops + 1] = n end end)
	eq(#stops, 2)
	eq(stops[1].meta.class, "sqotd-armed")
	ok(find(tree, "TextView", "Simulation: Running: 4 simulated years"))
	stops[1].onClick()
	eq(lastSent().action, "simStop")
end)

test("window: pickers and check boxes send the runner's options", function()
	load()
	local tree = select("main")
	local debugRow = nil
	for _, g in ipairs(all(tree, "ToggleButtonGroup")) do
		if g.buttons[1].content.text == "Mod setting" then debugRow = g end
	end
	ok(debugRow, "debug picker")
	debugRow.onValueChange(2)
	eq(lastSent().action, "debug"); eq(lastSent().mode, "on")
	local cb = find(tree, "CheckBox", "Build as player (off: free town streets, the default; on: the player pays, refunded)")
	eq(cb.value, 1)
	cb.onValueChange(0)
	eq(lastSent().action, "player"); eq(lastSent().on, false)

	tree = select("showcase")
	local ring = nil
	for _, g in ipairs(all(tree, "ToggleButtonGroup")) do
		if g.buttons[1].content.text == V.RING_LABELS[1] then ring = g end
	end
	eq(ring.selected, 1)
	local n = #sent
	ring.onValueChange(1)
	eq(#sent, n, "same ring: nothing sent")
	ring.onValueChange(2)
	eq(lastSent().action, "showOpt"); eq(lastSent().opt, "ring")
	find(tree, "CheckBox", "Tour after settle").onValueChange(1)
	eq(lastSent().opt, "tourAfter")

	tree = select("camera")
	find(tree, "CheckBox", "Screenshots during the tour").onValueChange(0)
	tree = render()
	eq(find(tree, "CheckBox", "Screenshots during the tour").value, 0)
end)

test("window: the Town tab's motif picker (M0) sends the forced motif with every command", function()
	load()
	local tree = select("town")
	local motifRow = nil
	for _, g in ipairs(all(tree, "ToggleButtonGroup")) do
		if g.buttons[2] and g.buttons[2].content.text == "Crescent" then motifRow = g end
	end
	ok(motifRow, "motif picker")
	eq(motifRow.selected, 1, "the main mod's own motifs by default")
	motifRow.onValueChange(3)
	eq(lastSent().action, "style")
	eq(lastSent().motif, 3)
	tree = render()
	find(tree, "Button", "Grow now").onClick()
	eq(lastSent().action, "grow")
	eq(lastSent().motif, 3, "Grow now carries the motif")
end)

test("window: every button of every tab runs without an error and every runner command is reachable", function()
	load()
	local actions = {}
	for _, t in ipairs(V.TABS) do
		local tree = select(t.key)
		local labels = {}
		for _, b in ipairs(all(tree, "Button")) do labels[#labels + 1] = b.content.text end
		for _, l in ipairs(labels) do
			local b = find(render(), "Button", l)
			if b then
				b.onClick()
				-- armed confirms: the second click within 8 s runs it
				local again = find(render(), "Button", "CONFIRM undo") or find(render(), "Button", "CONFIRM reset showcase")
				if again then again.onClick() end
			end
		end
		for _, g in ipairs(all(render(), "ToggleButtonGroup")) do g.onValueChange(#g.buttons) end
		for _, c in ipairs(all(render(), "CheckBox")) do c.onValueChange(c.value == 1 and 0 or 1) end
	end
	for _, p in ipairs(sent) do actions[p.action] = true end
	eq(#warnings(), 0, table.concat(warnings(), "\n"))
	for _, a in ipairs({ "select", "inspect", "roundabout", "rbAdopt", "nodeDump", "style", "grow", "dry", "markers",
		"undo", "growTown", "ownJoins", "fast", "growAll", "showFocus", "showcase", "stop", "showReset", "showOpt",
		"showDestroy", "allTowns", "simStart", "simSpeed", "pause", "debug", "player" }) do
		ok(actions[a], "command reachable: " .. a)
	end
end)

test("tour: the session's first screenshot request is a primer; the first real shot waits after it (2026-10-13)", function()
	load()
	local shots = 0
	api.gui.camera.takeScreenshot = function() shots = shots + 1 end
	-- the camera reads back whatever it was asked
	local cam = { x = 0, y = 0, z = 1800, w = 0.1, q = 0.6 }
	api.gui.camera.setCameraData = function(v) cam = { x = v.x, y = v.y, z = v.z, w = v.w, q = v.q } end
	api.gui.camera.getCameraData = function() return cam end
	local tree = select("showcase")
	local b
	walk(tree, function(n) if b == nil and n.__type == "Button" and n.content and n.content.text == "Auto tour" then b = n end end)
	assert(b, "Auto tour button")
	b.onClick()
	eq(shots, 1, "primer at the tour start")
	for _ = 1, 400 do
		nowT = nowT + 50000
		for _, fn in ipairs(steps) do fn() end
	end
	local primer, real = nil, {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find("SHOT primer=true", 1, true) then primer = e.msg end
		if e.msg:find("SHOT n=", 1, true) then real[#real + 1] = e.msg end
	end
	ok(primer and primer:find("sessionShot=1", 1, true), tostring(primer))
	ok(#real >= 1 and real[1]:find("sessionShot=2", 1, true), tostring(real[1]))
	-- a second tour in the same session: no primer
	b = nil
	walk(select("showcase"), function(n) if b == nil and n.__type == "Button" and n.content and n.content.text == "Auto tour" then b = n end end)
	if b then
		local before = shots
		b.onClick()
		eq(shots, before, "no second primer")
	end
end)

test("window: Build out is green and starts mode=buildout; pace 0 and Fill every 1/2/4/8 pickers with tooltips; Move date", function()
	load()
	local SG = ug_require "/organic_towns_dev/otd_simgrow.lua"
	local tree = render()
	local b = find(tree, "Button", "Build out: " .. SG.BUILDOUT.years .. " years")
	ok(b, "build out button")
	eq(b.meta.class, "sqotd-go")
	ok(b.meta.tooltip:find("mature towns", 1, true), b.meta.tooltip)
	b.onClick()
	eq(lastSent().action, "simStart"); eq(lastSent().mode, "buildout")
	-- Quick: pace 0, mode quick
	find(render(), "Button", "Quick: " .. SG.QUICK.limit .. " years").onClick()
	eq(lastSent().mode, "quick")
	eq(SG.PACES[lastSent().pace], 0)
	local pace, fill = nil, nil
	for _, g in ipairs(all(render(), "ToggleButtonGroup")) do
		if g.buttons[1].content.text == "0 (as fast as possible)" then pace = g end
		if g.buttons[1].content.text == "1" and #g.buttons == #SG.FILL_EVERY then fill = g end
	end
	ok(pace and pace.layout == "Flow", "the pace picker wraps")
	ok(pace.buttons[1].meta.tooltip:find("As fast as possible", 1, true), pace.buttons[1].meta.tooltip)
	ok(fill, "fill every picker")
	eq(#fill.buttons, 4)
	eq(fill.buttons[4].content.text, "8")
	ok(fill.buttons[4].meta.tooltip:find("twice as fast", 1, true) and fill.buttons[4].meta.tooltip:find("half", 1, true),
		fill.buttons[4].meta.tooltip)
	-- every tooltip line within 70 columns
	walk(render(), function(n)
		local tip = n.meta and n.meta.tooltip
		if tip then
			for line in tostring(tip):gmatch("[^\n]+") do ok(#line <= 70, "tooltip line over 70: " .. line) end
		end
	end)
	local md = find(render(), "CheckBox", "Move the game date with the simulated years")
	ok(md, "move date check box"); eq(md.value, 1, "on by default (§68)")
	find(render(), "Button", "Simulate natural growth").onClick()
	eq(lastSent().moveDate, true)
	md.onValueChange(0)
	find(render(), "Button", "Simulate natural growth").onClick()
	eq(lastSent().moveDate, false, "unticked: the calendar stands still")
	md.onValueChange(1)
	eq(lastSent().mode, nil, "the pickers as set")
end)

test("hudview: fill every tips, pace labels, simStart mode and moveDate", function()
	local SG = ug_require "/organic_towns_dev/otd_simgrow.lua"
	local tips = V.fillEveryTips(SG.FILL_EVERY, SG.QUICK.fillEvery)
	eq(#tips, 4)
	ok(tips[3]:find("Quick", 1, true), tips[3])
	ok(tips[4]:find("twice", 1, true), tips[4])
	eq(V.paceLabels({ 0, 1, 30 }), { "0 (as fast as possible)", "1", "30" })
	local p = V.simStartParams({ simMoveDate = true }, nil, nil, "buildout")
	eq(p.mode, "buildout"); eq(p.moveDate, true)
	eq(V.simStartParams({}).moveDate, true, "§68: on by default")
	eq(V.simStartParams({ simMoveDate = false }).moveDate, false)
end)
