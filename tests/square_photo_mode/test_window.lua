-- pm_window.lua (Photo Mode window) rendered on a fake react / builtin: every tab and the footer build, no layout
-- carries an inline styleSheet (it never applies in game: round 6 layout bug), every spacing class used has its
-- rule in pm_button.css.lua, the stylesheet stays within its budget, the Tour tab per mode.

local W, D, H, SKY, nodes, recipes, tabChange
-- round 15 sliders (gui/pm_slider.lua): the last render's onStep / onMouseEvent callbacks
local stepFns, mouseFns

local function newNode(kind, p)
	local n = { kind = kind, p = p or {} }
	nodes[#nodes + 1] = n
	return n
end

local function fakeBuiltin()
	local b = { type = { Orientation = { Vertical = 1, Horizontal = 0 }, TabOrientation = { North = 0 } } }
	for __, k in ipairs({ "BoxLayout", "FlowLayout", "Component", "TextView", "Button", "ToggleButton", "CheckBox",
		"ToggleButtonGroup", "ImageView", "ScrollArea", "TabWidgetChild", "Window", "ComboBox", "ComboBoxItem", "Slider",
		"TextInputField" }) do
		b[k] = function(p) return newNode(k, p) end
	end
	b.TabWidget = function(p) tabChange = p.onValueChange return newNode("TabWidget", p) end
	return b
end

before_each(function()
	reset_modules()
	nodes, recipes = {}, {}
	set_global("api", {
		type = { Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end } },
		gui = {
			StyleSheet = { new = function() return {} end },
			game = { getGuiSaveData = function() return nil end, setGuiSaveData = function() end },
			genericRep = { find = function() return -1 end, get = function() return nil end },
		},
	})
	local react = {
		RegisterRecipe = function(name, fn) recipes[name] = fn return function(p) return fn(p or {}) end end,
		RegisterWrapperRecipe = function(name, __, fn) recipes[name] = fn return fn end,
		useState = function(v0)
			local v = v0
			return { old = function() return v end, set = function(__, x) v = x end, hasExpired = function() return false end }
		end,
		onStep = function(fn) stepFns[#stepFns + 1] = fn end,
		-- round 15 (gui/pm_slider.lua): a ref per call (a render keeps it only within itself here)
		useRef = function(v0)
			local v = v0
			return { get = function() return v end, set = function(__, x) v = x end }
		end,
		onMouseEvent = function(fn) mouseFns[#mouseFns + 1] = fn end,
	}
	stepFns, mouseFns = {}, {}
	stub_module("::/gui/main/react.lua", react)
	stub_module("::/gui/main/builtin.lua", fakeBuiltin())
	stub_module("::/gui/main/game_react_globals.tl", { getDefaultWindowApi = function() return nil end })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return { style = t } end })
	-- (the horizontal spacer is built inline, never through gui_react_util.makeHorizontalSpacer: PS5, last test)
	stub_module("::/gui/main/gui_react_util.tl", { FocusTextInputField = function(p) return newNode("Field", p) end })
	local timer = { start = function() return 0 end, stop = function() end, wrap = function(__, __, fn) return fn end }
	stub_module("square_photo_mode::/photo_mode/gui/pm_perf.lua", { perf = timer, perfStep = timer })
	local cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
	D = {
		S = { version = 0, tourMode = "ground", tourSources = cam.copySet(cam.DEFAULT_SOURCES), rangeSel = cam.preset("ground"),
			tourChoice = 2, legChoice = 2, flightSubjects = cam.copySet(cam.DEFAULT_FLIGHT_SUBJECTS), kenBurns = true,
			aerialLook = "high", lookReturn = true, tourLabels = true, tourPause = false, areaChoice = 2,
			tourStyle = "shots", tourWhere = "map", tourFlights = false, aerialWhere = "map", stayChoice = 2 },
	}
	setmetatable(D, { __index = function() return function() end end })
	stub_module("square_photo_mode::/photo_mode/gui/pm_driver.lua", D)
	H = setmetatable({}, { __index = function() return function() return false end end })
	stub_module("square_photo_mode::/photo_mode/gui/pm_hud.lua", H)
	-- phase 4 / round 12: a base climate's look layers (pm_looks.SKY_ORDER / HAZE_ORDER / WATER_ORDER), nothing running
	local sky = setmetatable({ shown = function() return {} end, status = function()
		return { climate = "dry", looks = {
			sky = { "soft_light", "dramatic", "storybook", "moonlit_night" },
			haze = { "crisp_clear", "hazy_morning", "misty_valley", "soft_background" },
			water = { "mirror", "clear", "wild" },
		} }
	end }, { __index = function() return function() return false end end })
	SKY = sky
	stub_module("square_photo_mode::/photo_mode/gui/pm_sky.lua", sky)
	W = ug_require "square_photo_mode::/photo_mode/gui/pm_window.lua"
end)

local function render(tab)
	nodes = {}
	if tab ~= nil then tabChange(tab) end
	nodes = {}
	recipes.PhotoModeContent({})
	return nodes
end

local function cssRules()
	local rules = {}
	set_global("log", { message = function() end })
	api.gui.genericRep = { find = function() return -1 end, get = function() return nil end }
	stub_module("::/gui/main/stylesheetutil.lua", {
		makeAdder = function(result) return function(sel, st) rules[#rules + 1] = { sel = sel, st = st } end end,
	})
	local f = io.open("mods/square_photo_mode/content/photo_mode/gui/pm_button.css.lua")
	local src = f:read("a")
	f:close()
	local env = setmetatable({ require = function(name) return ug_require(name) end }, { __index = _G })
	local chunk = load(src, "css", "t", env)
	chunk()
	env.data()
	return rules
end

local function classes(n)
	local out = {}
	local c = n.p.meta and n.p.meta.class
	if type(c) == "string" then for part in c:gmatch("[^,%s]+") do out[part] = true end end
	return out
end

test("every tab and the footer render; no layout carries an inline styleSheet", function()
	render() -- the first render mounts the TabWidget
	for __, tab in ipairs({ "aerial", "tour", "subjects", "animals", "camera", "light", "weather", "settings" }) do
		local ns = render(tab)
		local tabs = 0
		for __, n in ipairs(ns) do
			if n.kind == "TabWidget" then tabs = tabs + 1 end
			if n.kind == "BoxLayout" or n.kind == "FlowLayout" then
				eq(n.p.meta and n.p.meta.styleSheet, nil, tab .. ": inline styleSheet on a " .. n.kind .. " never applies")
			end
			if n.kind == "TextView" and n.p.text == "Nothing found." then ok(false, tab .. " failed to render") end
		end
		eq(tabs, 1)
	end
end)

test("spacing: columns, rows and flows carry a spacing class that has its rule; the budget holds", function()
	local rules = cssRules()
	ok(#rules <= 14, "at most 14 rules (10 + the shared 4): " .. #rules)
	local sel = {}
	for __, r in ipairs(rules) do sel[#sel + 1] = r.sel end
	local all = table.concat(sel, "\n")
	render()
	for __, tab in ipairs({ "aerial", "tour", "subjects", "animals", "light", "weather", "settings" }) do
		for __, n in ipairs(render(tab)) do
			local kids = n.p.children
			if (n.kind == "BoxLayout" or n.kind == "FlowLayout") and kids ~= nil and #kids > 1 then
				local c = classes(n)
				ok(c["sqpm-gap"] or c["sqpm-checks"] or c["sqpm-content"], tab .. ": a " .. n.kind .. " of " .. #kids
					.. " children without a spacing class")
				for k in pairs(c) do
					if k:match("^sqpm%-") then ok(all:find("!" .. k, 1, true) ~= nil, "rule for " .. k) end
				end
			end
		end
	end
	for __, r in ipairs(rules) do
		if r.sel:find("sqpm-content", 1, true) then
			eq(r.st.padding, nil, "round 8: no padding on a layout (it never applies); the root Component carries it")
		end
		if r.sel:find("sqpm-gap", 1, true) then eq(r.st.innerSpacing, { 6, 6 }) end
		if r.sel:find("sqpm-checks", 1, true) then eq(r.st.innerSpacing, { 12, 6 }) end
	end
end)

test("round 8: the content and the footer are padded by Components, not layouts", function()
	local ns = render()
	local root, footer = nil, nil
	for __, n in ipairs(ns) do
		local st = n.kind == "Component" and n.p.meta and n.p.meta.styleSheet
		if st and type(st.padding) == "table" then
			local lay = n.p.layout
			local c = lay and classes(lay) or {}
			if c["sqpm-content"] then root = st end
			-- the footer: the Component whose column holds the separator and the camera / screenshot row (round 12)
			for __, k in ipairs(lay and lay.p.children or {}) do
				if k.kind == "Component" and k.p.layout and k.p.layout.kind == "BoxLayout" then
					for __, kk in ipairs(k.p.layout.p.children or {}) do
						if kk.p.meta and kk.p.meta.class == "horizontal-spacer" then footer = st end
					end
				end
			end
		end
	end
	ok(root ~= nil, "the root column sits in a padded Component")
	eq(root.padding, { 8, 8, 8, 8 }, "8 px off every window edge")
	ok(footer ~= nil, "the footer sits in a padded Component")
	eq(footer.padding, { 0, 8, 0, 8 }, "inset like the tab page (TabWidget::Content padding 8)")
end)

test("round 8: every action button is outlined and compact; option sets are grids of equal cells or a dropdown", function()
	local rules = cssRules()
	local cellText, small = nil, nil
	for __, r in ipairs(rules) do
		if r.sel:find("!sqpm-cell TextView", 1, true) then cellText = r.st end
		if r.sel:find("!sqpm-small", 1, true) and r.sel:find("!sqpm-cell", 1, true) then small = r.st end
	end
	ok(cellText ~= nil and small ~= nil, "the two button rules")
	eq(cellText.textAutoWrap, true)
	local cellW = cellText.size[1] + small.padding[2] + small.padding[4]
	ok(3 * cellW + 2 * 6 <= 424, "three cells and two gaps fit in a 424 px row: " .. cellW)
	ok(small.padding[1] < 8, "compact: less than the base 8 px")
	render()
	local cells = {}
	for __, tab in ipairs({ "aerial", "tour", "subjects", "animals", "camera", "light", "weather", "settings" }) do
		cells[tab] = 0
		for __, n in ipairs(render(tab)) do
			if n.kind == "Button" then
				local c = classes(n)
				ok(c.secondary or c.primary, tab .. ": a borderless base Button '" .. tostring(n.p.content and n.p.content.p.text) .. "'")
				ok(c.primary or c["sqpm-cell"] or c["sqpm-small"], tab .. ": a Button without the compact padding")
				eq(n.p.meta.styleSheet, nil, tab .. ": no inline styleSheet on a Button")
				if c["sqpm-cell"] then cells[tab] = cells[tab] + 1 end
			end
			if n.kind == "ToggleButton" then
				local c = classes(n)
				ok(c["sqpm-cell"], tab .. ": a toggle cell")
				cells[tab] = cells[tab] + 1
			end
			if n.kind == "ToggleButtonGroup" then
				for __, b in ipairs(n.p.buttons) do ok(b.meta.class == "sqpm-small", tab .. ": compact options") end
			end
		end
	end
	eq(cells.subjects, 23, "every subject a grid cell")
	eq(cells.animals, 2, "round 20: the Animals tab's Add and Remove all")
	eq(cells.camera, 10, "6 shots + 4 moves (round 17: the Lens buttons are natural width, one line)")
	eq(cells.light, 4 + 3 + 3 + 3, "4 time presets, 3 time-lapse, 3 seasons, 3 light angles")
	eq(cells.weather, 3 + 3, "3 cloud presets, 3 weather over time (the looks are dropdowns)")
	-- round 22: the Tour tab's Style and Where, the Aerials tab's Where: option groups (no mode dropdown)
	local groups = {}
	for __, n in ipairs(render("tour")) do
		ok(n.kind ~= "ComboBox", "round 22: no Tour mode dropdown")
		if n.kind == "ToggleButtonGroup" then groups[#groups + 1] = n end
	end
	eq(#groups[1].p.buttons, 2, "Style: Shots, Wander")
	eq(#groups[2].p.buttons, 3, "Where: Across the map, Saved views, Here")
	local picked
	D.setTourWhere = function(m) picked = m end
	groups[2].p.onValueChange(3)
	eq(picked, "here")
	picked = nil
	groups[2].p.onValueChange(9)
	eq(picked, nil, "an unknown value is ignored")
	D.setTourWhere = nil
	D.setTourStyle = function(m) picked = m end
	groups[1].p.onValueChange(2)
	eq(picked, "wander")
	D.setTourStyle = nil
	local aerialGroups = {}
	for __, n in ipairs(render("aerial")) do if n.kind == "ToggleButtonGroup" then aerialGroups[#aerialGroups + 1] = n end end
	eq(#aerialGroups[1].p.buttons, 2, "Aerials Where: Across the map, Saved views")
	D.setAerialWhere = function(m) picked = m end
	aerialGroups[1].p.onValueChange(2)
	eq(picked, "views")
	D.setAerialWhere = nil
end)

test("round 12: the Settings tab holds High graphics mode and Hide labels (round 18 name); the footer the camera buttons", function()
	local function boxes(ns)
		local out = {}
		for __, n in ipairs(ns) do if n.kind == "CheckBox" then out[#out + 1] = n.p.label end end
		return table.concat(out, "|")
	end
	render()
	eq(boxes(render("subjects")), "", "no checkbox in the footer")
	local hq, labelsOn = 0, nil
	W.hqOn = function() return false end
	W.onHqToggle = function() hq = hq + 1 end
	H.setLabels = function(on) labelsOn = on end
	local ns = render("settings")
	eq(boxes(ns), "High graphics mode|Hide labels", "round 18: renamed; no DEV rows without the DEV mod")
	for __, n in ipairs(ns) do
		if n.kind == "CheckBox" then
			ok(type(n.p.meta.tooltip) == "string" and #n.p.meta.tooltip > 40, n.p.label .. ": its tooltip")
			n.p.onValueChange(1)
		end
	end
	eq(hq, 1, "ticking High graphics mode switches it")
	eq(labelsOn, true, "ticking Hide labels hides them")
	W.hqOn, W.onHqToggle, H.setLabels = function() return false end, function() end, nil
	ns = render("subjects")
	local labels = {}
	for __, n in ipairs(ns) do
		if n.kind == "CheckBox" then labels[#labels + 1] = n.p.label end
		local t = n.kind == "Button" and n.p.content and n.p.content.p.text
		if t == "Smooth camera" or t == "Free camera" then
			labels[#labels + 1] = "[" .. t .. "]"
			ok(classes(n).secondary, "round 8: outlined like every action button")
		end
	end
	local all = table.concat(labels, "|")
	ok(all:find("[Free camera]", 1, true), all)
	ok(not all:find("[Smooth camera]", 1, true), "round 13: the Smooth camera button is gone")
	ok(not all:find("Hide UI", 1, true), "the Hide UI checkbox is gone")
	ok(not all:find("Camera mode", 1, true), "round 10: Camera mode is the Free camera button")
end)

test("round 13: Camera tab: no Smooth camera section any more", function()
	render()
	local t = {}
	for __, n in ipairs(render("camera")) do
		if n.kind == "TextView" then t[#t + 1] = n.p.text end
		if n.kind == "CheckBox" then t[#t + 1] = n.p.label end
	end
	local all = table.concat(t, "|")
	for __, gone in ipairs({ "Smooth camera", "Smoothing", "Level zoom" }) do
		ok(not all:find(gone, 1, true), gone .. " in " .. all)
	end
	ok(all:find("Camera moves", 1, true), all)
end)

test("Tour tab: each style and where shows its rows; Aerials: the flight rows or the saved views", function()
	render()
	local function texts(ns)
		local t = {}
		for __, n in ipairs(ns) do
			if n.kind == "TextView" then t[#t + 1] = n.p.text end
			if n.kind == "CheckBox" then t[#t + 1] = n.p.label end
		end
		return table.concat(t, "|")
	end
	local ground = texts(render("tour"))
	ok(ground:find("Sources", 1, true) and ground:find("Distance from", 1, true), ground)
	ok(ground:find("Angle from", 1, true) and ground:find("Angle to", 1, true) and ground:find("Distance to", 1, true))
	ok(not ground:find("Lowest view", 1, true) and not ground:find("Closest", 1, true), "the old, unclear labels are gone")
	ok(not ground:find("camera mode", 1, true), "round 9: no camera mode option for tours")
	ok(ground:find("Hide labels during tours", 1, true))
	ok(ground:find("Pause the game during the tour", 1, true))
	ok(ground:find("Across the map", 1, true) and ground:find("Here", 1, true), "round 22: the Where options")
	ok(ground:find("Drone flight between shots", 1, true), "round 22: Mixed is a checkbox")
	ok(not ground:find("Flight leg", 1, true) and not ground:find("Save view|", 1, true), "no flight rows, no list")
	local function set(k, v)
		D.S[k] = v
		D.S.version = D.S.version + 1
	end
	set("tourFlights", true)
	local mixed = texts(render())
	ok(mixed:find("Flight leg", 1, true) and mixed:find("Look", 1, true), mixed)
	ok(not mixed:find("Fly over", 1, true), "the Aerials tab's Fly over")
	set("tourFlights", false)
	set("tourWhere", "here")
	local placeTab = texts(render())
	ok(placeTab:find("Area", 1, true) and placeTab:find("Medium", 1, true), placeTab)
	ok(not placeTab:find("Sources", 1, true) and not placeTab:find("Distance from", 1, true))
	ok(placeTab:find("Angle from", 1, true) and placeTab:find("Angle to", 1, true) and placeTab:find("Hold", 1, true))
	ok(not placeTab:find("Stay", 1, true), "This place never moves on")
	set("tourStyle", "wander")
	local wanderTab = texts(render())
	ok(wanderTab:find("Area", 1, true) and wanderTab:find("Angle from", 1, true), wanderTab)
	ok(not wanderTab:find("Hold", 1, true) and not wanderTab:find("Ken Burns", 1, true), "continuous: no hold, no drift")
	ok(not wanderTab:find("Stay", 1, true), "Wander here stays")
	set("tourWhere", "map")
	local roam = texts(render())
	ok(roam:find("Stay", 1, true) and roam:find("Sources", 1, true) and roam:find("1 min", 1, true), roam)
	set("tourWhere", "views")
	local roamViews = texts(render())
	ok(roamViews:find("Stay", 1, true) and roamViews:find("Save view", 1, true), roamViews)
	ok(not roamViews:find("Sources", 1, true))
	set("tourStyle", "shots")
	local views = texts(render())
	ok(views:find("Hold", 1, true) and views:find("Save view", 1, true) and not views:find("Angle from", 1, true), views)
	set("tourWhere", "map")
	local aerial = texts(render("aerial"))
	ok(aerial:find("Flight leg", 1, true) and aerial:find("Fly over", 1, true) and aerial:find("Start aerials", 1, true),
		aerial)
	ok(not aerial:find("Save view", 1, true))
	set("aerialWhere", "views")
	local aerialViews = texts(render())
	ok(aerialViews:find("Save view", 1, true) and aerialViews:find("Look", 1, true), aerialViews)
	ok(not aerialViews:find("Flight leg", 1, true) and not aerialViews:find("Fly over", 1, true), "no legs along the views")
	set("aerialWhere", "map")
	-- the Start buttons start their own tab's tour
	local started
	D.startTab = function(kind) started = kind end
	for __, n in ipairs(render()) do
		if n.kind == "Button" and n.p.meta.class == "primary" then n.p.onClick() end
	end
	eq(started, "aerial")
	for __, n in ipairs(render("tour")) do
		if n.kind == "Button" and n.p.meta.class == "primary" then n.p.onClick() end
	end
	eq(started, "tour")
	D.startTab = nil
end)

test("every control has a tooltip: buttons, toggles, checkboxes, every choice option, step buttons, row actions", function()
	api.gui.game.getGuiSaveData = function() return { v = 1, views = { { id = 1, x = 0, y = 0, d = 100, a = 0, p = 0.5 },
		{ id = 2, x = 5, y = 0, d = 100, a = 0, p = 0.5 } } } end
	render()
	local seen = { Button = 0, ToggleButton = 0, CheckBox = 0, Slider = 0, option = 0 }
	local function tipOk(meta) return meta ~= nil and type(meta.tooltip) == "string" and meta.tooltip ~= "" end
	local function label(n)
		if n.p.label then return n.p.label end
		local c = n.p.content
		if c and c.p then return tostring(c.p.text or c.p.path) end
		return "?"
	end
	local function audit(ns, where)
		for __, n in ipairs(ns) do
			if n.kind == "Button" or n.kind == "ToggleButton" or n.kind == "CheckBox" or n.kind == "Slider" then
				seen[n.kind] = seen[n.kind] + 1
				ok(tipOk(n.p.meta), where .. ": " .. n.kind .. " '" .. label(n) .. "' has no tooltip")
			elseif n.kind == "ComboBox" then
				ok(tipOk(n.p.meta), where .. ": a dropdown without a tooltip")
				for i, it in ipairs(n.p.items) do
					seen.option = seen.option + 1
					ok(tipOk(it.p.content.p.meta), where .. ": dropdown item " .. i .. " has no tooltip")
				end
			elseif n.kind == "ToggleButtonGroup" then
				for i, b in ipairs(n.p.buttons) do
					seen.option = seen.option + 1
					ok(tipOk(b.meta), where .. ": option " .. i .. " '" .. tostring(b.content and b.content.p.text)
						.. "' has no tooltip")
				end
			end
		end
	end
	for __, tab in ipairs({ "subjects", "animals", "camera", "views", "light", "weather", "settings" }) do audit(render(tab), tab) end
	render("tour")
	for __, style in ipairs({ "shots", "wander" }) do
		for __, where in ipairs({ "map", "views", "here" }) do
			for __, flights in ipairs({ false, true }) do
				D.S.tourStyle, D.S.tourWhere, D.S.tourFlights = style, where, flights
				D.S.version = D.S.version + 1
				audit(render(), "tour/" .. style .. "/" .. where .. (flights and "/flights" or ""))
			end
		end
	end
	D.S.tourStyle, D.S.tourWhere, D.S.tourFlights = "shots", "map", false
	render("aerial")
	for __, where in ipairs({ "map", "views" }) do
		D.S.aerialWhere = where
		D.S.version = D.S.version + 1
		audit(render(), "aerial/" .. where)
	end
	D.S.aerialWhere = "map"
	ok(seen.Button > 20 and seen.ToggleButton >= 4 and seen.CheckBox > 8 and seen.option > 30, "the audit saw the controls")
	eq(seen.Slider, 6, "round 15: the Light tab's three sliders; round 16: the Weather tab's three cloud sliders")
end)

test("round 11 / 12 / 20 / 22: eight tabs as icons with their name as tooltip; they fit the window", function()
	local ns = render()
	local tabs, keys = {}, {}
	for __, n in ipairs(ns) do
		if n.kind == "TabWidgetChild" then
			tabs[#tabs + 1] = n
			keys[#keys + 1] = n.p.value
			local ind = n.p.indicator
			eq(ind.kind, "ImageView", n.p.value .. ": an icon indicator")
			ok(type(ind.p.path) == "string" and ind.p.path:match("^::/gui/.+%.tga$"), n.p.value .. ": a base icon")
			ok(type(ind.p.meta.tooltip) == "string" and ind.p.meta.tooltip ~= "", n.p.value .. ": the name as tooltip")
			eq(ind.p.meta.styleSheet.style.size, { 16, 16 })
		end
	end
	-- round 22: Aerials and Tour first; the saved views moved into them (a ninth tab would not fit)
	eq(table.concat(keys, ","), "aerial,tour,subjects,animals,camera,light,weather,settings")
	-- base TabWidget::Indicator padding 18 left + 18 right (builtin.css.lua) around each icon (round 20: 16 px for
	-- eight tabs), within the 440 px content less the root's 8 px padding on each side
	ok(#tabs * (16 + 36) <= 440 - 2 * 8, "the indicators fit the 424 px inside the content's padding")
end)

test("round 11: the Light tab (time, time-lapse, season and sun) and the Weather tab (looks, clouds)", function()
	render()
	local function scan(ns)
		local heads, toggles, buttons, combos, labels = {}, {}, {}, {}, {}
		for __, n in ipairs(ns) do
			if n.kind == "TextView" and n.p.meta and n.p.meta.class == "font-scale-headline" then heads[#heads + 1] = n.p.text end
			if n.kind == "TextView" and n.p.meta and tostring(n.p.meta.class):find("sqpm-label", 1, true) then labels[#labels + 1] = n.p.text end
			if n.kind == "ToggleButton" then toggles[n.p.content.p.text] = n end
			if n.kind == "Button" and n.p.content.p.text ~= nil then buttons[n.p.content.p.text] = n end
			if n.kind == "ComboBox" then combos[#combos + 1] = n end
		end
		return table.concat(heads, "|"), toggles, buttons, combos, table.concat(labels, "|")
	end
	local heads, toggles, buttons, combos, labels = scan(render("light"))
	eq(heads, "Presets|Time-lapse|Season|Light angle|Adjust", "round 12: season and light angle under their own headings")
	eq(labels, "Time of day|Season|Sun direction")
	for __, l in ipairs({ "Golden hour", "Blue hour", "Noon", "Night", "Winter sun", "Spring sun", "Summer sun", "Backlight",
		"Side light", "Front light" }) do
		local b = buttons[l]
		ok(b ~= nil and b.p.meta.class == "secondary, sqpm-cell" and type(b.p.meta.tooltip) == "string", l .. ": an outlined cell with a tooltip")
	end
	-- round 12: three seasons in a row, then three light angles with Front light first
	local order = {}
	for __, n in ipairs(render("light")) do
		local t = n.kind == "Button" and n.p.content and n.p.content.p.text
		if t and (t:find(" sun", 1, true) or t:find("light", 1, true)) then order[#order + 1] = t end
	end
	eq(table.concat(order, ","), "Winter sun,Spring sun,Summer sun,Front light,Side light,Backlight")
	for __, l in ipairs({ "Sunrise", "Sunset", "Run the clock" }) do
		ok(toggles[l] ~= nil and toggles[l].p.value == 0, "toggle cell " .. l)
	end
	eq(#combos, 0)
	heads, toggles, buttons, combos, labels = scan(render("weather"))
	eq(heads, "Looks|Presets|Weather over time|Adjust|Foreground") -- round 16b: the Foreground section
	eq(labels, "Sky|Haze|Water|Clouds|Cloud height|Cloud density", "round 16: three cloud sliders")
	for __, l in ipairs({ "Clear", "Overcast", "Storm" }) do ok(buttons[l] ~= nil, "preset " .. l) end
	for __, l in ipairs({ "Storm rolls in", "Clearing", "Low clouds" }) do ok(toggles[l] ~= nil, "toggle cell " .. l) end
	eq(#combos, 3, "a sky, a haze and a water dropdown")
	local function itemTexts(c)
		local t = {}
		for __, it in ipairs(c.p.items) do t[#t + 1] = it.p.content.p.text end
		return table.concat(t, ",")
	end
	eq(itemTexts(combos[1]), "Original,Soft light,Dramatic,Storybook,Moonlit night")
	eq(itemTexts(combos[2]), "Original,Crisp & clear,Hazy morning,Misty valley,Soft background")
	eq(itemTexts(combos[3]), "Original,Mirror water,Crystal clear,Wild water")
	eq(combos[1].p.value, "1", "Original while no look is on")
	-- the calls: a layer picked, Original back, weather, time-lapse, season, sun (below the horizon: the status line)
	local calls = {}
	SKY.layer = function(l, k) calls[#calls + 1] = l .. " " .. tostring(k) end
	SKY.weather = function(k) calls[#calls + 1] = "weather " .. k end
	SKY.lapse = function(k) calls[#calls + 1] = "lapse " .. k end
	SKY.season = function(k) calls[#calls + 1] = "season " .. k end
	SKY.placeSun = function(k) calls[#calls + 1] = "sun " .. k return -0.2 end
	local status
	D.setStatus = function(s) status = s end
	combos[1].p.onValueChange("3")
	combos[2].p.onValueChange("5")
	combos[3].p.onValueChange("4")
	combos[3].p.onValueChange("1")
	toggles["Storm rolls in"].p.onValueChange(1)
	heads, toggles, buttons = scan(render("light"))
	toggles["Sunset"].p.onValueChange(1)
	buttons["Winter sun"].p.onClick()
	buttons["Spring sun"].p.onClick()
	buttons["Backlight"].p.onClick()
	eq(table.concat(calls, ","), "sky dramatic,haze soft_background,water wild,water nil,weather storm,lapse sunset,season winter,season spring,sun back")
	ok(status ~= nil and status:find("below the horizon", 1, true), "the sun below the horizon: a status line")
	-- a look on: the dropdowns show it
	local st0 = SKY.status
	SKY.status = function()
		local s = st0()
		s.look, s.sky, s.haze, s.water, s.weather = "dramatic_soft_background_wild", "dramatic", "soft_background", "wild", "storm"
		return s
	end
	D.S.version = D.S.version + 1
	heads, toggles, buttons, combos = scan(render("weather"))
	eq(combos[1].p.value, "3")
	eq(combos[2].p.value, "5")
	eq(combos[3].p.value, "4")
	eq(toggles["Storm rolls in"].p.value, 1)
	-- an unknown climate: the note, no dropdowns; the other sections stay
	SKY.status = function() return {} end
	D.S.version = D.S.version + 1
	local ns = render()
	heads, toggles, buttons, combos = scan(ns)
	eq(#combos, 0, "no look dropdowns")
	local note = false
	for __, n in ipairs(ns) do if n.kind == "TextView" and tostring(n.p.text):find("has no looks", 1, true) then note = true end end
	ok(note, "the unknown-climate note")
	ok(toggles["Storm rolls in"] ~= nil and buttons["Clear"] ~= nil, "weather still there")
	SKY.status = st0
	SKY.layer, SKY.weather, SKY.lapse, SKY.season, SKY.placeSun, D.setStatus = nil, nil, nil, nil, nil, nil
end)

test("round 12: one footer row: the camera buttons left (wrapping box), the base spacer, the screenshot group right", function()
	local ns = render()
	local rowLayout
	for __, n in ipairs(ns) do
		if n.kind == "BoxLayout" and n.p.orientation == 0 then
			for __, k in ipairs(n.p.children or {}) do
				if k.p.meta and k.p.meta.class == "horizontal-spacer" then rowLayout = n end
			end
		end
	end
	ok(rowLayout ~= nil, "a horizontal row with the base horizontal spacer (no new CSS rule)")
	ok(classes(rowLayout)["sqpm-gap"], "the row's gap class")
	local kids = rowLayout.p.children
	eq(#kids, 3, "left box, spacer, screenshot group")
	-- left: a FlowLayout in a fixed-width Component (the buttons wrap there instead of widening the window)
	eq(kids[1].kind, "Component")
	eq(kids[1].p.meta.styleSheet.style.size, { 250, -1 })
	eq(kids[1].p.layout.kind, "FlowLayout")
	local left = {}
	for __, b in ipairs(kids[1].p.layout.p.children) do left[#left + 1] = b.p.content.p.text end
	eq(table.concat(left, ","), "Free camera", "round 13: the Smooth camera button removed")
	eq(kids[2].p.layout, nil, "the spacer is an empty Component")
	-- right: the camera icon (Screenshot as its tooltip), 1x, 2x, 4x
	eq(kids[3].kind, "BoxLayout")
	local right = kids[3].p.children
	eq(right[1].kind, "ImageView")
	eq(right[1].p.meta.tooltip, "Screenshot")
	ok(right[1].p.path:match("^::/gui/.+%.tga$"), "a base icon")
	local r = {}
	for i = 2, #right do r[#r + 1] = right[i].p.content.p.text end
	eq(table.concat(r, ","), "1x,2x,4x")
	-- the row's box is the flow width (the left box + two gaps + the group fit in it, see pm_window FOOT_LEFT_W)
	local box
	for __, n in ipairs(ns) do if n.kind == "Component" and n.p.layout == rowLayout then box = n end end
	eq(box.p.meta.styleSheet.style.size, { 424, -1 })
end)

test("footer: the screenshot group's 1x / 2x / 4x buttons, their tooltips, disabled while busy, the scale passed", function()
	local function shutterButtons()
		local out = {}
		for __, n in ipairs(render()) do
			local t = n.kind == "Button" and n.p.content and n.p.content.p.text
			if t == "1x" or t == "2x" or t == "4x" then out[t] = n end
		end
		return out
	end
	-- no viewport size: the size in words
	local b = shutterButtons()
	for __, k in ipairs({ "1x", "2x", "4x" }) do
		ok(b[k] ~= nil, k)
		ok(classes(b[k]).secondary and classes(b[k])["sqpm-small"], k .. ": outlined and compact")
		local tip = b[k].p.meta.tooltip
		ok(tip:find("screenshots folder", 1, true) and tip:find("interface is never", 1, true), tip)
		eq(b[k].p.meta.enabled, true)
		for line in tip:gmatch("[^\n]+") do ok(#line <= 70, "tooltip line within 70: " .. line) end
	end
	ok(b["2x"].p.meta.tooltip:find("twice", 1, true))
	ok(b["4x"].p.meta.tooltip:find("four times", 1, true) and b["4x"].p.meta.tooltip:find("freezes for 10 seconds", 1, true))
	-- the viewport size known: the pixel sizes
	D.viewportSize = function() return 2560, 1440 end
	D.S.version = D.S.version + 1
	b = shutterButtons()
	ok(b["1x"].p.meta.tooltip:find("2560 x 1440 pixels", 1, true), b["1x"].p.meta.tooltip)
	ok(b["2x"].p.meta.tooltip:find("5120 x 2880 pixels", 1, true))
	ok(b["4x"].p.meta.tooltip:find("10240 x 5760 pixels", 1, true))
	-- a click passes its scale; busy: disabled
	local got = {}
	D.screenshot = function(scale) got[#got + 1] = scale end
	b["1x"].p.onClick(); b["2x"].p.onClick(); b["4x"].p.onClick()
	eq(table.concat(got, ","), "1,2,4")
	D.shutterBusy = function() return true end
	D.S.version = D.S.version + 1
	b = shutterButtons()
	eq(b["4x"].p.meta.enabled, false, "disabled while a shot is pending or saved")
end)

test("round 15: each look layer has < and > beside its dropdown, with tooltips, stepping and wrapping round", function()
	local P = ug_require "square_photo_mode::/photo_mode/pm_looks.lua"
	local st0 = SKY.status
	SKY.status = function()
		return { climate = "dry", sky = "neon_dusk", haze = nil, water = "mirror",
			looks = { sky = P.SKY_ORDER, haze = P.HAZE_ORDER, water = P.WATER_ORDER } }
	end
	render()
	local rows = {}
	for __, n in ipairs(render("weather")) do
		-- a layer row's control: a horizontal BoxLayout of < , the dropdown, >
		local kids = n.kind == "BoxLayout" and n.p.children or nil
		if kids and #kids == 3 and kids[2].kind == "ComboBox" then rows[#rows + 1] = kids end
	end
	eq(#rows, 3, "Sky, Haze and Water rows with arrows")
	local calls = {}
	SKY.layer = function(l, k) calls[#calls + 1] = l .. " " .. tostring(k) end
	for i, kids in ipairs(rows) do
		eq(kids[1].kind, "Button"); eq(kids[3].kind, "Button")
		-- round 18: the base spin box arrows as icons (the text "<" / ">" showed a notch in the contour)
		eq(kids[1].p.content.p.path, "::/gui/builtin/spinbox/arrow_left.tga")
		eq(kids[3].p.content.p.path, "::/gui/builtin/spinbox/arrow_right.tga")
		eq(kids[1].p.meta.tooltip, "Previous look."); eq(kids[3].p.meta.tooltip, "Next look.")
		ok(kids[1].p.meta.class:find("sqpm-small", 1, true) and kids[1].p.meta.class:find("secondary", 1, true),
			"compact outlined arrows (ui-guide: Step a value)")
		eq(#kids[2].p.items, #P.ORDER[P.LAYERS[i]] + 1, "Original + every look in the dropdown")
		kids[1].p.onClick()
		kids[3].p.onClick()
	end
	eq(table.concat(calls, ","), "sky vintage,sky legacy,haze dust_storm,haze crisp_clear,water nil,water clear",
		"< and > from Neon dusk (round 16: > goes on to Legacy, the whole look), from Original (< wraps to the last) and from Mirror")
	SKY.status, SKY.layer = st0, nil
end)

test("round 15: the Light tab's time, season and sun sliders: live writes throttled and quiet, a final set", function()
	local sliders = ug_require "square_photo_mode::/photo_mode/gui/pm_slider.lua"
	local now = 0
	sliders.nowMs = function() return now end
	SKY.shown = function() return { time = 13 * 3600 + 30 * 60, day = 172, sun = -math.pi / 2 } end
	render()
	stepFns, mouseFns = {}, {}
	local ns = render("light")
	local bars, values = {}, {}
	for i, n in ipairs(ns) do
		if n.kind == "Slider" then bars[#bars + 1] = n end
	end
	eq(#bars, 3, "time of day, season, sun direction")
	-- each slider sits in its row between the step buttons, its value text after it
	for __, n in ipairs(ns) do
		local kids = n.kind == "BoxLayout" and n.p.children or nil
		if kids and #kids == 4 and kids[2].kind == "Slider" then
			eq(kids[1].kind, "Button"); eq(kids[4].kind, "Button"); eq(kids[3].kind, "TextView")
			values[#values + 1] = kids[3].p.text
			eq(n.p.meta.class, "sqpm-gap", "the row's gap class (no inline sheet on a layout)")
		end
	end
	eq(table.concat(values, "|"), "13:30|21 Jun|270°", "the value texts: hh:mm, the date, degrees")
	local t, d, s = bars[1].p, bars[2].p, bars[3].p
	eq(t.min, 0); eq(t.max, 1439); eq(t.value, 13 * 60 + 30)
	eq(d.min, 1); eq(d.max, 365); eq(d.value, 172)
	eq(s.min, 0); eq(s.max, 359); eq(s.value, 270)
	for __, b in ipairs(bars) do
		eq(b.p.horizontal, true)
		ok(type(b.p.meta.tooltip) == "string" and b.p.meta.tooltip ~= "", "a slider tooltip")
	end
	-- a drag on the time slider: values every frame (16 ms); live writes at most every 80 ms, quiet
	local live, final = {}, {}
	SKY.setLive = function(c) live[#live + 1] = c end
	SKY.set = function(c) final[#final + 1] = c end
	local v0 = D.S.version
	for i = 0, 20 do
		now = i * 16
		t.onValueChange(600 + i)
		for __, f in ipairs(stepFns) do f() end
	end
	ok(#live >= 4 and #live <= 6, "about one write per 80 ms over 320 ms: " .. #live)
	eq(live[1].time, 600 * 60, "the first value at once (seconds)")
	eq(#final, 0, "no final set while dragging")
	eq(D.S.version, v0, "the window's version never moved while dragging")
	-- the release: the final value as a click
	now = 400
	for __, f in ipairs(mouseFns) do f({ button = 0, type = "released" }) end
	-- (the fake api has no mouse event types: the release goes by the settle time instead)
	now = 1000
	for __, f in ipairs(stepFns) do f() end
	eq(#final, 1, "one final set")
	eq(final[1].time, 620 * 60, "the value the drag ended on")
	-- the sun slider: degrees to sunRotation in (-pi, pi]
	now = 5000
	s.onValueChange(90)
	near(live[#live].sun, math.pi / 2, 1e-9)
	s.onValueChange(300)
	now = 6000
	for __, f in ipairs(stepFns) do f() end -- the trailing live write
	near(live[#live].sun, math.rad(300) - 2 * math.pi, 1e-9)
	now = 6500
	for __, f in ipairs(stepFns) do f() end -- settled: the final set
	near(final[#final].sun, math.rad(300) - 2 * math.pi, 1e-9, "300 degrees is -60 degrees")
	SKY.shown, SKY.setLive, SKY.set = nil, nil, nil
end)

test("round 16: the Settings tab's saved setups: dropdown, actions, the rename field, Restore last setup", function()
	local G = ug_require "square_photo_mode::/photo_mode/gui/pm_setups.lua"
	local SP = ug_require "square_photo_mode::/photo_mode/pm_setup.lua"
	local function scan(ns)
		local heads, buttons, combos, fields = {}, {}, {}, {}
		for __, n in ipairs(ns) do
			if n.kind == "TextView" and n.p.meta and n.p.meta.class == "font-scale-headline" then heads[#heads + 1] = n.p.text end
			if n.kind == "Button" and n.p.content and n.p.content.p.text then buttons[n.p.content.p.text] = n end
			if n.kind == "ComboBox" then combos[#combos + 1] = n end
			if n.kind == "Field" then fields[#fields + 1] = n end
		end
		return table.concat(heads, "|"), buttons, combos, fields
	end
	render()
	G.S.lib = {}
	local heads, buttons, combos = scan(render("settings"))
	eq(heads, "Saved setups|Options")
	eq(#combos, 0, "no setups: a note instead of the dropdown")
	for __, l in ipairs({ "Load", "Overwrite", "Rename", "Delete", "Restore last setup" }) do
		ok(buttons[l] ~= nil and buttons[l].p.meta.enabled == false, l .. ": disabled with nothing to act on")
	end
	ok(buttons["Save new"].p.meta.enabled ~= false, "Save new is always there")
	-- Save new: the new setup "Setup 1", its name field open
	local saved
	G.saveNew = function(name) saved = name; G.S.lib = { SP.valid({ id = 1, name = name }) }; G.S.editing = 1; G.S.version = G.S.version + 1 end
	buttons["Save new"].p.onClick()
	eq(saved, "Setup 1")
	local __, __, combos2, fields = scan(render())
	eq(#fields, 1, "the rename field while naming"); eq(#combos2, 0)
	eq(fields[1].p.value, "Setup 1"); eq(fields[1].p.maxLength, SP.NAME_MAX)
	G.rename = function(id, name) G.S.lib[1].name = name; G.S.editing = nil; G.S.version = G.S.version + 1 end
	fields[1].p.onValueChange("custom golden 1")
	-- two setups, the second picked; its tooltip names its looks and time
	G.S.lib[2] = SP.valid({ id = 2, name = "my dark night", look = { sky = "moonlit_night" }, values = { time = 0, day = 172 }, freeze = true })
	G.S.selected = 2
	G.S.version = G.S.version + 1
	heads, buttons, combos = scan(render())
	eq(#combos, 1)
	eq(combos[1].p.value, "2"); eq(combos[1].p.items[1].p.content.p.text, "custom golden 1")
	local tip = combos[1].p.items[2].p.content.p.meta.tooltip
	ok(tip:find("Moonlit night", 1, true) and tip:find("00:00", 1, true) and tip:find("21 Jun", 1, true)
		and tip:find("Time frozen.", 1, true), tip)
	for line in tip:gmatch("[^\n]+") do ok(#line <= 70, "tooltip line width: " .. line) end
	local calls = {}
	G.load = function(id) calls[#calls + 1] = "load " .. id return true end
	G.overwrite = function(id) calls[#calls + 1] = "overwrite " .. id return true end
	G.editName = function(id) calls[#calls + 1] = "rename " .. id end
	G.remove = function(id) calls[#calls + 1] = "delete " .. id end
	G.restoreLast = function() calls[#calls + 1] = "last" end
	local status
	D.setStatus = function(s) status = s end
	for __, l in ipairs({ "Load", "Overwrite", "Rename", "Delete" }) do
		ok(buttons[l].p.meta.enabled ~= false, l .. " enabled"); buttons[l].p.onClick()
	end
	eq(table.concat(calls, ","), "load 2,overwrite 2,rename 2,delete 2")
	ok(status ~= nil, "a status line after an action")
	-- a last setup: Restore enabled, its tooltip says what comes back
	G.S.last = SP.valid({ look = { sky = "dramatic", haze = "misty_valley" } })
	G.S.version = G.S.version + 1
	heads, buttons = scan(render())
	ok(buttons["Restore last setup"].p.meta.enabled ~= false)
	ok(buttons["Restore last setup"].p.meta.tooltip:find("Dramatic + Misty valley", 1, true))
	buttons["Restore last setup"].p.onClick()
	eq(calls[#calls], "last")
	-- full: Save new disabled, the tooltip says why
	for i = 1, SP.CAP do G.S.lib[i] = SP.valid({ id = i, name = "s" .. i }) end
	G.S.version = G.S.version + 1
	heads, buttons = scan(render())
	eq(buttons["Save new"].p.meta.enabled, false); ok(buttons["Save new"].p.meta.tooltip:find("At most", 1, true))
	G.S.lib, G.S.last, G.S.selected, D.setStatus = nil, nil, nil, nil
end)

test("our GUI save data: one writer; a setup change writes the views, the markers, last and the setups together", function()
	local store = { square_photo_mode = { v = 1, views = { { id = 1, name = "Home", x = 0, y = 0, d = 500, a = 0, p = 0.5 } } } }
	api.gui.game.getGuiSaveData = function(k) return store[k] end
	api.gui.game.setGuiSaveData = function(k, d) store[k] = d end
	render()
	local G = ug_require "square_photo_mode::/photo_mode/gui/pm_setups.lua"
	G.start()
	eq(#G.library(), 0)
	G.saveNew("Golden 1")
	local mine = store.square_photo_mode
	eq(#mine.views, 1, "the saved views kept"); eq(mine.views[1].name, "Home")
	eq(#mine.setups.list, 1); eq(mine.setups.list[1].name, "Golden 1")
	ok(mine.light ~= nil, "the light marker written with them")
	-- a later write of another part keeps the setups
	G.S.lib = nil
	G.persist()
	eq(store.square_photo_mode.setups.list[1].name, "Golden 1", "read back from the save data, then written again")
end)

test("a platform whose base gui_react_util lacks FocusTextInputField / makeHorizontalSpacer (PS5 report 2026-10-19): no error, no direct call", function()
	-- docs/findings/gui.md "Base GUI modules differ by platform": the console build's own base GUI scripts lack
	-- functions the PC copies have; the window must render without them
	stub_module("::/gui/main/gui_react_util.tl", {})
	reset_modules()
	ug_require "square_photo_mode::/photo_mode/gui/pm_window.lua"
	local G = ug_require "square_photo_mode::/photo_mode/gui/pm_setups.lua"
	local SP = ug_require "square_photo_mode::/photo_mode/pm_setup.lua"
	render()
	local spacer = false
	for __, tab in ipairs({ "aerial", "tour", "subjects", "animals", "camera", "light", "weather", "settings" }) do
		for __, n in ipairs(render(tab)) do
			if n.kind == "TextView" and n.p.text == "Nothing found." then ok(false, tab .. " failed to render") end
			if n.kind == "Component" and n.p.meta and n.p.meta.class == "horizontal-spacer" then spacer = true end
		end
	end
	ok(spacer, "the footer keeps the base spacer (inline, not the helper)")
	-- the setup rename field: a plain TextInputField with the base field's values
	G.S.lib = { SP.valid({ id = 1, name = "Setup 1" }) }
	G.S.editing = 1
	G.S.version = G.S.version + 1
	local field
	for __, n in ipairs(render()) do if n.kind == "TextInputField" then field = n end end
	ok(field ~= nil, "the fallback field")
	eq(field.p.value, "Setup 1"); eq(field.p.maxLength, SP.NAME_MAX)
	eq(field.p.meta.class, "font-scale-body, no-clear-button")
	ok(field.p.meta.styleSheet ~= nil, "the caller's sheet kept")
	local renamed
	G.rename = function(id, name) renamed = name end
	field.p.onValueChange("my dark night")
	eq(renamed, "my dark night")
	G.S.lib, G.S.editing = nil, nil
	-- no unguarded call left in the source
	local fh = assert(io.open("mods/square_photo_mode/content/photo_mode/gui/pm_window.lua", "r"))
	local code = fh:read("a"):gsub("%-%-[^\n]*", "")
	fh:close()
	ok(not code:find("gui_react_util.makeHorizontalSpacer(", 1, true), "no makeHorizontalSpacer call")
	ok(not code:find("gui_react_util.FocusTextInputField{", 1, true), "FocusTextInputField only through nameField")
end)
