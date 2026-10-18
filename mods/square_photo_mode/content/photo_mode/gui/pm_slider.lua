-- Photo Mode: a slider row of the Light tab (round 15: time of day, season, sun direction; user: "Can season, time
-- of day, and sun direction be sliders?"). GUI thread only. Pure part (ranges, mapping, the throttle):
-- ../pm_light.lua "Sliders".
--
-- The base builtin.Slider (a C++ builtin, gui/main/builtin.lua:68; params base tealdef scripts/builtin.d.tl
-- SliderParam: integer min / max / step / pageStep / value, onValueChange(integer), no release callback) calls
-- onValueChange for every value it passes while dragged. The window re-renders as a whole when its version moves
-- (pm_window.lua PhotoModeContent), so a write per value must not reach it. As the base construction slider
-- (script_param_util.tl ScriptParamSliderAndText ~287-345):
--   - this recipe keeps the dragged value in its own react state: a move re-renders only this row (the slider and
--     its value text), never the window;
--   - live writes go out through the throttle (pm_light.throttleInput / throttleStep, at most every THROTTLE_MS,
--     the value the player stopped on as a trailing write) as quiet sets (pm_sky.setLive: no log, no save, no
--     window refresh);
--   - the gesture ends with one final write (onFinal: pm_sky.set: log, marker, window refresh) at the mouse release
--     (react.onMouseEvent, as the base) or SETTLE_MS after the last move (keyboard, gamepad, a release the recipe
--     didn't see).
-- The recipe returns a layout (docs/findings/gui.md "Recipe roots") and sits in a layout's children (never as a
-- Component's layout). Every callback in pcall: an error inside a react callback takes the UI down.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
local L = ug_require "square_photo_mode::/photo_mode/pm_light.lua"

local M = {}

M.THROTTLE_MS = 80 -- live writes at most 12.5 times a second (a setEnvironment costs 0.01-0.07 ms in game)
M.SETTLE_MS = 400  -- no release seen: the value counts as final this long after the last move

local clock = nil
--- Milliseconds (api.type.Clock, as pm_weather); a test may replace it.
M.nowMs = function()
	local ok, t = pcall(function()
		if clock == nil then clock = api.type.Clock.new() end
		return clock:getTime() / 1000
	end)
	return ok and t or 0
end

local function try(what, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then core.log("slider " .. what .. " ERROR " .. tostring(err)) end
	return ok
end

local function released(evt)
	local ok, r = pcall(function()
		return evt.button == 0 and evt.type == api.gui.mouse.Event.Type.Released
	end)
	return ok and r == true
end

--- params: key (a name for the log), min, max, step, pageStep, value (integer: what the game has now), text
--- (integer -> the value text), tooltip (the slider's), valueStyle (the value text's inline style), onLive(integer),
--- onFinal(integer), children (optional: { before = {...}, after = {...} } widgets around the slider, e.g. step
--- buttons), sliderStyle (optional inline style of the slider: its width).
M.Slider = react.RegisterRecipe("PhotoModeSlider", function(p)
	-- the value dragged to, and the game's value it was dragged from: a game value that moved since (a final write
	-- landed, a preset, a step button) wins once the gesture is over
	local drag = react.useState(nil)
	local thr = react.useRef(nil)
	if thr:get() == nil then thr:set(L.newThrottle(M.THROTTLE_MS, M.SETTLE_MS)) end
	local t = thr:get()
	local d = drag:old()
	local shown = p.value
	if d ~= nil and (t.open or d.base == p.value) then shown = d.value end

	local function final(v)
		if v ~= nil and p.onFinal ~= nil then try(p.key .. " final", p.onFinal, v) end
	end
	react.onStep(function()
		local v, kind = L.throttleStep(t, M.nowMs())
		if v == nil then return end
		if kind == "final" then final(v)
		elseif p.onLive ~= nil then try(p.key .. " live", p.onLive, v) end
	end)
	react.onMouseEvent(function(evt)
		if released(evt) then final(L.throttleRelease(t, M.nowMs())) end
		return false -- the slider (a child) handles the mouse itself
	end)

	local slider = builtin.Slider{
		meta = { tooltip = p.tooltip, styleSheet = p.sliderStyle },
		horizontal = true,
		min = p.min,
		max = p.max,
		step = p.step,
		pageStep = p.pageStep,
		value = shown or p.min,
		onValueChange = function(v)
			try(p.key .. " change", function()
				if type(v) ~= "number" then return end
				drag:set({ value = v, base = p.value })
				local live = L.throttleInput(t, v, M.nowMs())
				if live ~= nil and p.onLive ~= nil then p.onLive(live) end
			end)
		end,
	}
	local children = {}
	for __, w in ipairs(p.before or {}) do children[#children + 1] = w end
	children[#children + 1] = slider
	children[#children + 1] = builtin.TextView{
		meta = { class = "font-scale-body", styleSheet = p.valueStyle, tooltip = p.tooltip },
		text = shown ~= nil and p.text(shown) or "-",
	}
	for __, w in ipairs(p.after or {}) do children[#children + 1] = w end
	return builtin.BoxLayout{
		meta = { class = "sqpm-gap" },
		orientation = builtin.type.Orientation.Horizontal,
		children = children,
	}
end)

return M
