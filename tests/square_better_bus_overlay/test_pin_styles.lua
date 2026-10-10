-- Lines window pin styles (ShadedStopIcon in better_bus_overlay.script.lua): every StyleSheet is made
-- once in doReplace (Main Thread at GUI start), and a pin render (HUD worker thread) only looks them up.
-- styleutil is faked as the base one (gui/main/styleutil.tl: api.gui.StyleSheet.new, color = Vec4f), and
-- the fake StyleSheet.new records each call. The expected colours are the pre-cache formula (pinColour /
-- glyphColour, revision 3), recomputed here, so the cache must not change any pin.
-- run_tests: no-split (each test reloads the module; the fakes record per test)

local MOD = "square_better_bus_overlay"
local PATH = MOD .. "::/better_bus_overlay/better_bus_overlay.script.lua"

local F

local function widget(name)
	return function(p) return { w = name, p = p } end
end

local function stubs()
	F.cru = { getActionParams = function() return { hudIconManagerParams = nil } end }
	F.builtin = {
		BoxLayout = widget("BoxLayout"), LineViewer = widget("LineViewer"), Component = widget("Component"),
		FloatingLayout = widget("FloatingLayout"), FloatingLayoutChild = widget("FloatingLayoutChild"),
		ImageView = widget("ImageView"),
		ActionDescriptor = function(p) return { w = "ActionDescriptor", p = p } end,
		UseDefaultHudIcon = function(p) return { w = "DefaultIcon", p = p } end,
		type = {
			Orientation = { Horizontal = "H", Vertical = "V" },
			ImageViewScaling = { Stretch = 1, AutoFit = 2 },
			LineVisualization = { new = function() return {} end },
		},
	}
	stub_module("::/gui/main/react.lua", {
		RegisterRecipe = function(_name, fn) return fn end,
		getCurrentRecipeName = function() return F.recipe end,
		setMouseTransparent = function() end,
	})
	stub_module("::/gui/main/builtin.lua", F.builtin)
	stub_module("::/gui/construction/construction_react_util.tl", F.cru)
	stub_module("::/gui/construction/constructionHudIconMaster.tl", function() return { w = "BaseMaster" } end)
	stub_module("::/gui/main/color_util.tl", { toVec4 = function(c) return c end })
	stub_module("::/gui/layers/layer_react_util.tl", { createDefaultFallbackColor = function() return "fallback" end })
	stub_module("::/gui/hud/hud_react_util.tl", {
		makeDefaultVisibilityThresholds = function() return {} end,
		makeDefaultLineViewerSnapFactors = function() return { view = 1, world = 2 } end,
	})
	stub_module("::/gui/main/engine_react_util.tl", {
		useStepStateTimer = function(fn)
			local s = { v = fn(nil) }
			function s:old() return self.v end
			return s
		end,
	})
	stub_module("::/gui/main/cargo_util.tl", {
		getPassengerCargoTypeId = function() return 0 end,
		getPassengerCargoIcon = function() return "pax.tga" end,
	})
	stub_module("::/gui/main/gui_react_util.tl", { makeContentLabelIndictator = function(p) return { w = "Tag", p = p } end })
	stub_module("::/scripts/lang_util.tl", { formatInt = function(n) return tostring(n) end })
	-- as base styleutil.makeStyle for the one key the pins use
	stub_module("::/gui/main/styleutil.tl", {
		makeStyle = function(t)
			local style = api.gui.StyleSheet.new()
			if t.color then
				local c = t.color
				style.color = api.type.Vec4f.new(c[1], c[2], c[3], c[4])
			end
			return style
		end,
	})
end

local function fakeApi(sqperfLog)
	set_global("api", {
		type = {
			Clock = { new = function() return { getTime = function() return F.clockUs end } end },
			Vec4f = { new = function(x, y, z, w) return { x, y, z, w } end },
			ComponentType = { STATION_GROUP = "STATION_GROUP" },
			enum = { Carrier = { ROAD = 1, TRAM = 2 } },
		},
		gui = {
			StyleSheet = { new = function()
				F.styleNew = F.styleNew + 1
				return { id = F.styleNew }
			end },
			SelectionDetails = { Type = { Station = "Station" } },
		},
		engine = {
			config = { getModParams = function() return { [MOD] = { sqperf_log = sqperfLog } } end },
			entityExists = function() return true end,
			getComponent = function() return {} end,
			system = { lineSystem = {
				getLines = function() return {} end,
				getLineStops = function() return { 1 } end,
			} },
			util = {
				line = { isLineCompatibleWithAnyCarrier = function() return true end },
				cargo = { getCargoQualityDataAtStationGroup = function(e)
					return { countTotal = F.waiting[e] or 0, countBad = 0 }
				end },
			},
		},
	})
end

local function load(sqperfLog)
	F = { clockUs = 1e9, styleNew = 0, waiting = {} }
	clear_logs()
	stubs()
	fakeApi(sqperfLog)
	reset_modules()
	set_global("data", nil)
	ug_require(PATH)
	data().doReplace({})
end

local function lines(pattern)
	local out = {}
	for _, e in ipairs(log_entries()) do
		if e.msg:find(pattern, 1, true) then out[#out + 1] = e.msg end
	end
	return out
end

-- one Lines window pin for a stop with `waiting` passengers: its pin and glyph ImageView styles
local nextEntity = 100
local function renderPin(waiting)
	nextEntity = nextEntity + 1
	F.waiting[nextEntity] = waiting
	F.recipe = "HudStationWithLineStops"
	local pin = F.builtin.UseDefaultHudIcon({ entity = nextEntity })
	F.recipe = nil
	eq(pin.w, "BoxLayout")
	local layers = pin.p.children[1].p.layout.p.children
	local function view(i) return layers[i].p.item.p.layout.p.children[1].p end
	eq(view(1).meta.class, "sqslv-pin-bg")
	eq(view(2).meta.class, "sqslv-pin-bus")
	return view(1).meta.styleSheet, view(2).meta.styleSheet
end

-- revision 3's per-render colours
local STOPS = {
	{ 0, { 0.62, 0.77, 0.92 } },
	{ 40, { 0.96, 0.78, 0.20 } },
	{ 80, { 0.89, 0.25, 0.22 } },
}
local function expectedPin(waiting)
	local n = math.min(waiting, 80)
	n = n - n % 4
	local prev = STOPS[1]
	for i = 2, #STOPS do
		local s = STOPS[i]
		if n <= s[1] then
			local t = (n - prev[1]) / (s[1] - prev[1])
			local c = {}
			for k = 1, 3 do c[k] = prev[2][k] + (s[2][k] - prev[2][k]) * t end
			c[4] = 1.0
			return c
		end
		prev = s
	end
	return { 0.89, 0.25, 0.22, 1.0 }
end
local function expectedGlyph(c)
	local lum = 0.299 * c[1] + 0.587 * c[2] + 0.114 * c[3]
	return lum > 0.6 and { 0.11, 0.17, 0.27, 1.0 } or { 1.0, 1.0, 1.0, 1.0 }
end

local function sameColour(got, want, msg)
	for k = 1, 4 do near(got[k], want[k], 1e-9, msg .. " [" .. k .. "]") end
end

test("doReplace makes all 21 pin styles and 2 glyph styles, once", function()
	load(1)
	eq(F.styleNew, 23)
	data().doReplace({}) -- second call: already installed, nothing new
	eq(F.styleNew, 23)
end)

test("pin renders make no StyleSheet after warm-up, and every pin keeps its colours", function()
	load(1)
	local warm = F.styleNew
	local byStep = {}
	for waiting = 0, 200 do
		local bg, bus = renderPin(waiting)
		local want = expectedPin(waiting)
		sameColour(bg.color, want, "pin " .. waiting)
		sameColour(bus.color, expectedGlyph(want), "glyph " .. waiting)
		local step = math.min(waiting, 80) - math.min(waiting, 80) % 4
		byStep[step] = byStep[step] or bg
		ok(byStep[step] == bg, "one shared style per step " .. step)
	end
	eq(F.styleNew, warm, "StyleSheet.new calls during renders")
	-- both glyph colours appear, each one shared object
	local light, dark = select(2, renderPin(0)), select(2, renderPin(80))
	ok(light ~= dark)
	ok(select(2, renderPin(4)) == light)
	ok(select(2, renderPin(200)) == dark)
end)

test("a step outside the warmed set is built lazily once, same colours, counted as a miss", function()
	load(2)
	local warm = F.styleNew
	local bg = renderPin(-3) -- step -4: impossible in game, exercises the fallback
	sameColour(bg.color, expectedPin(-3), "lazy pin")
	eq(F.styleNew, warm + 1, "only the pin style; the glyph style is shared")
	renderPin(-3)
	eq(F.styleNew, warm + 1, "cached after the miss")
	F.clockUs = F.clockUs + 31e6
	renderPin(0)
	local hud = table.concat(lines("ctx=hud"), "\n")
	ok(hud:find("pin_style_miss n=1", 1, true), hud)
end)

test("check line only with the debug gate On; no miss counted in normal renders", function()
	load(1)
	eq(#lines("phase=pin_styles"), 0, "debug Off: silent")
	load(2)
	local l = lines("phase=pin_styles")
	eq(#l, 1)
	ok(l[1]:find("ctx=gui", 1, true) and l[1]:find("styles=21 glyphs=2", 1, true), l[1])
	for waiting = 0, 90 do renderPin(waiting) end
	F.clockUs = F.clockUs + 31e6
	renderPin(0)
	local hud = table.concat(lines("ctx=hud"), "\n")
	ok(hud:find("pin_render n=", 1, true), hud)
	ok(not hud:find("pin_style_miss", 1, true), hud)
end)
