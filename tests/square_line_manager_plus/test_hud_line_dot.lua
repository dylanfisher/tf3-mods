-- Line Manager Plus "Line editor: active border on line dot" (hud_line_dot.lua), with fake react / builtin /
-- base modules and a fake api. Covers: install (wraps makeSelectLineTooltip once, guard flag, missing field), the
-- edited line's dot gets the border (dark on a light dot, light on a dark one), other lines / other recipes / no
-- edited line pass through, the Button wrapper disarmed after each dot (also when the border fails), a non-dot Button
-- while armed, and the base SelectLine caller never arms.

local F -- per-test fakes and records

local LIGHT = 50 -- the edited line, a light color
local DARK = 51  -- another line, a dark color
local RECIPE = "HudStationWithLineStops"

local function setup(opts)
	opts = opts or {}
	reset_modules()
	clear_logs()
	F = { recipe = RECIPE, edited = LIGHT, buttons = {} }
	local comps = {
		[LIGHT] = { COLOR = { color = { x = 0.9, y = 0.8, z = 0.4 } } },
		[DARK] = { COLOR = { color = { x = 0.1, y = 0.2, z = 0.3 } } },
	}
	set_global("api", {
		type = {
			ComponentType = setmetatable({}, { __index = function(_, k) return k end }),
			Vec4f = { new = function(a, b, c, d)
				if type(a) == "table" then return { x = a.x, y = a.y, z = a.z, w = b } end
				return { x = a, y = b, z = c, w = d }
			end },
		},
		gui = { genericRep = {
			find = function(p) return p end,
			get = function() return { data = { NeutralDarkest = { 0, 0, 0, 1 }, NeutralLightest = { 1, 1, 1, 1 } } } end,
		} },
		engine = {
			getComponent = function(e, ct)
				if F.colorError then error("color boom") end
				return comps[e] and comps[e][ct] or nil
			end,
		},
	})
	stub_module("::/gui/main/react.lua", { getCurrentRecipeName = function() return F.recipe end })
	F.realButton = function(p) F.buttons[#F.buttons + 1] = p; return { w = "Button", p = p } end
	F.builtin = { Button = F.realButton }
	stub_module("::/gui/main/builtin.lua", F.builtin)
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return { style = t } end })
	stub_module("::/gui/main/color_util.tl", { toVec4 = function(c)
		return { x = c[1], y = c[2], z = c[3], w = c[4] or 1.0 }
	end })
	F.mtu = {}
	if opts.noField ~= true then
		F.mtu.makeSelectLineTooltip = function(e) return "Select line " .. tostring(e) .. "." end
	end
	stub_module("::/gui/line_vehicle_mgmt/manager_tooltips_util.tl", F.mtu)
	stub_module("square_line_manager_plus::/line_manager_plus/lmp_capture.lua", {
		install = function() return true end,
		editedLine = function() return F.edited end,
	})
	F.m = ug_require "square_line_manager_plus::/line_manager_plus/hud_line_dot.lua"
end

local function lines(level, text)
	local n = 0
	for _i, e in ipairs(log_entries()) do
		if (level == nil or e.level == level) and e.msg:find(text, 1, true) then n = n + 1 end
	end
	return n
end

--- As the base StopLinesDisplay (manager_hud_util.tl:126-143): one Button per line, tooltip last in meta.
local function dots(lines)
	local out = {}
	for _i, l in ipairs(lines) do
		out[#out + 1] = F.builtin.Button{
			meta = {
				class = "line-dot,hover-dark",
				styleSheet = "base style",
				tooltip = F.mtu.makeSelectLineTooltip(l),
			},
			content = "component",
		}
	end
	return out
end

-- install ------------------------------------------------------------------------------------------------------------

test("install: wraps makeSelectLineTooltip and builtin.Button once, sets the guard flag and logs installed", function()
	setup()
	local orig = F.mtu.makeSelectLineTooltip
	ok(F.m.install({}, {}))
	ok(F.mtu.makeSelectLineTooltip ~= orig)
	ok(F.builtin.Button ~= F.realButton)
	ok(F.mtu.squareLmpLineDot == true)
	local w, wb = F.mtu.makeSelectLineTooltip, F.builtin.Button
	ok(F.m.install({}, {}))
	eq(F.mtu.makeSelectLineTooltip, w, "no second wrap")
	eq(F.builtin.Button, wb, "no second Button wrap")
	eq(lines("message", "[LineManagerPlus] line dot: installed"), 1)
	eq(lines("warning", "line dot"), 0)
end)

test("install: a missing makeSelectLineTooltip installs nothing and warns once", function()
	setup({ noField = true })
	eq(F.m.install({}, {}), false)
	eq(F.mtu.makeSelectLineTooltip, nil)
	eq(F.mtu.squareLmpLineDot, nil)
	eq(F.builtin.Button, F.realButton)
	eq(lines("warning", "[LineManagerPlus] line dot: install"), 1)
end)

-- dots ---------------------------------------------------------------------------------------------------------------

test("the edited line's dot gets a dark border on a light color; other dots stay as the base built them", function()
	setup()
	F.m.install({}, {})
	local nodes = dots({ DARK, LIGHT, DARK })
	eq(#nodes, 3)
	eq(nodes[1].p.meta.styleSheet, "base style")
	eq(nodes[3].p.meta.styleSheet, "base style")
	local st = nodes[2].p.meta.styleSheet.style
	eq(st.backgroundColor1.x, 0.9)
	eq(st.backgroundColor1.w, 1.0)
	eq(st.borderColor.x, 0)
	eq(st.borderColor.w, 1)
	eq(nodes[2].p.meta.tooltip, "Select line 50.", "the tooltip kept")
	eq(nodes[2].p.meta.class, "line-dot,hover-dark")
	eq(nodes[2].p.content, "component")
	eq(#F.buttons, 3, "one base Button call per dot")
end)

test("a dark edited line gets a light border", function()
	setup()
	F.edited = DARK
	F.m.install({}, {})
	local nodes = dots({ LIGHT, DARK })
	eq(nodes[1].p.meta.styleSheet, "base style")
	eq(nodes[2].p.meta.styleSheet.style.borderColor.x, 1)
end)

test("no edited line or another recipe: every dot passes through and nothing is armed", function()
	setup()
	F.m.install({}, {})
	F.edited = nil
	for _i, n in ipairs(dots({ LIGHT, DARK })) do eq(n.p.meta.styleSheet, "base style") end
	F.edited = LIGHT
	F.recipe = "SelectLine"
	local text = F.mtu.makeSelectLineTooltip(LIGHT)
	eq(text, "Select line 50.")
	F.recipe = RECIPE
	local n = F.builtin.Button{ meta = { class = "line-dot,x", styleSheet = "base style", tooltip = text } }
	eq(n.p.meta.styleSheet, "base style", "the SelectLine caller never arms")
end)

test("a failing border keeps the base dot, disarms and warns once", function()
	setup()
	F.m.install({}, {})
	F.colorError = true
	local nodes = dots({ LIGHT, LIGHT })
	eq(nodes[1].p.meta.styleSheet, "base style")
	eq(nodes[2].p.meta.styleSheet, "base style")
	eq(lines("warning", "[LineManagerPlus] line dot: dot"), 1)
end)

test("armed, a Button that is not this line dot passes through and disarms", function()
	setup()
	F.m.install({}, {})
	local text = F.mtu.makeSelectLineTooltip(LIGHT)
	local n = F.builtin.Button{ meta = { class = "other", styleSheet = "s", tooltip = "something else" } }
	eq(n.p.meta.styleSheet, "s")
	n = F.builtin.Button{ meta = { class = "line-dot,x", styleSheet = "base style", tooltip = text } }
	eq(n.p.meta.styleSheet, "base style", "disarmed by the first call")
	F.mtu.makeSelectLineTooltip(LIGHT)
	n = F.builtin.Button{ meta = { class = "stop-number", styleSheet = "s", tooltip = text } }
	eq(n.p.meta.styleSheet, "s", "same tooltip but not a line dot")
end)
