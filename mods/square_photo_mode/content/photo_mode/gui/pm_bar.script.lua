-- Photo Mode round 18: the cutscene bar (user: "Can we add a take-a-screenshot button while in Lens view?" and "can
-- we add buttons to cutscenes, e.g. take a photo?"). PLAN.md "Round 18" item 3; TESTING.md R18-3.
--
-- A playing cutscene hides react.game-ui-root (with it every mod plugin and window: the top-bar button, our window)
-- and `!action-camera Window` hides any Window (base gui/main/game.css.lua). The base FreeCamOptions recipe is
-- mounted outside that root, in GameUIProxyRoot's FloatingLayout at the top right (gui/main/game.tl:893-901), and
-- is no Window: it stays. A mod can't add a child there, but it can wrap the recipe through the official
-- "react-replacement-config" resource (pm_bar.res.lua; base gui/main/bootstrap_game.tl; the campaign wraps
-- HudIconMasterGame this way): the wrapper calls the original (react.CallOriginalRecipe: its input actions Back /
-- Menu back / F9 screenshot and its stoppedFollowAction listener run unchanged, as hooks of this recipe) and adds a
-- small bar next to it ONLY while one of Photo Mode's cutscenes plays (driver.S.cutscene: Lens view, lens tour,
-- the DEV orbit / flights). Outside a cutscene it renders exactly the original.
--
-- The bar: a camera icon, 1x / 2x / 4x (the window's shutter, driver.screenshot: screenshots never contain the UI,
-- findings map-camera.md "Screenshots") and Stop (pm_lens.stopFromBar). Inline styles only (no stylesheet rule:
-- the ~200-rule budget): a Component with a translucent background and padding, base "secondary" buttons, fixed-size
-- Components as gaps (a layout's innerSpacing needs a rule). Whether clicks reach it while the cutscene's camera
-- action holds the input is untested (TESTING.md R18-3); the game's own screenshot key (F9) works during a
-- cutscene (2026-10-14_1729 session: four 2x screenshots written during a DEV flight).
--
-- Every hook runs unconditionally and first; our part is built in pcall: an error here must never take the
-- original (and with it the game's free camera exit and F9) down. Our modules are required lazily on the first
-- frame, not when the replacement is registered (that runs at bootstrap, before any game UI exists).

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local styleutil = ug_require "::/gui/main/styleutil.tl"
local free_cam_options = ug_require "::/gui/main/free_cam_options.tl"

local B = {}
B.SCALES = { 1, 2, 4 }

-- log lines without pm_core (not loaded at bootstrap): "[PhotoMode] bar ..."
local function say(msg)
	local line = "[PhotoMode] bar" .. msg
	if log ~= nil and log.message ~= nil then log.message(line) else print(line) end
end

local mods = nil -- { core, driver, lens } once loaded; false after a failed load (logged once)
local function load()
	if mods == nil then
		local ok, err = pcall(function()
			mods = {
				core = ug_require "square_photo_mode::/photo_mode/pm_core.lua",
				driver = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua",
				lens = ug_require "square_photo_mode::/photo_mode/gui/pm_lens.lua",
			}
		end)
		if not ok then
			mods = false
			say(": modules not loaded: " .. tostring(err))
		end
	end
	return mods or nil
end

--- True while one of Photo Mode's cutscenes plays (the bar shows).
function B.active()
	local m = load()
	return m ~= nil and m.driver.S.cutscene ~= nil
end

local function try(what, fn)
	local m = load()
	local ok, err = pcall(fn, m)
	if not ok and m ~= nil then m.core.log("bar " .. what .. " ERROR " .. tostring(err)) end
end

local styles = nil
local function style()
	if styles == nil then
		local outer = api.gui.StyleSheet.new()
		-- the bar 8 px off the screen's top and right edges (inline styles take no margin: padding on a wrapper)
		outer.padding = api.type.Vec4f.new(8, 8, 0, 0)
		local panel = api.gui.StyleSheet.new()
		panel.padding = api.type.Vec4f.new(6, 6, 6, 6)
		panel.backgroundColor = api.type.Vec4f.new(0, 0, 0, 0.55)
		styles = {
			outer = outer,
			panel = panel,
			gap = styleutil.makeStyle{ size = { 6, 1 } },
			icon = styleutil.makeStyle{ size = { 20, 20 } },
		}
	end
	return styles
end

local function gap()
	return builtin.Component{ meta = { styleSheet = style().gap } }
end

-- string.format that never raises on a translated pattern (pm_core.fmt; pm_core may not be loaded yet)
local function core_fmt(pattern, ...)
	local m = load()
	if m ~= nil then return m.core.fmt(pattern, ...) end
	local ok, s = pcall(string.format, pattern, ...)
	return ok and s or tostring(pattern)
end

local function button(label, tooltip, onClick)
	return builtin.Button{
		meta = { class = "secondary", tooltip = tooltip },
		content = builtin.TextView{ meta = { class = "font-scale-body" }, text = label },
		onClick = onClick,
	}
end

local function bar()
	local children = {
		builtin.ImageView{ meta = { styleSheet = style().icon }, path = "::/gui/game_bar/icons/symbol_camera.tga" },
	}
	for __, scale in ipairs(B.SCALES) do
		children[#children + 1] = gap()
		children[#children + 1] = button(string.format("%dx", scale), -- i18n: ignore
			core_fmt(_("A screenshot of this view at %d times the screen's size.\nThe buttons and the game's interface are never in it."), scale),
			function()
				try("screenshot", function(m)
					local what = m.driver.screenshot(scale)
					m.core.log(string.format("bar: screenshot %dx pressed during the cutscene: %s", scale, tostring(what)))
				end)
			end)
	end
	children[#children + 1] = gap()
	children[#children + 1] = button(_("Stop"), _("Ends this camera move (Esc does too)."), function()
		try("stop", function(m) m.lens.stopFromBar() end)
	end)
	return builtin.Component{
		meta = { styleSheet = style().outer },
		layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.Component{
					meta = { styleSheet = style().panel },
					layout = builtin.BoxLayout{
						orientation = builtin.type.Orientation.Horizontal,
						children = children,
					},
				},
			},
		},
	}
end

local logged = false
B.Replacement = react.RegisterRecipe("PhotoModeFreeCamOptions", function(param)
	local shownState = react.useState(false)
	local shown = shownState:old() == true
	react.onStep(function()
		local ok, want = pcall(B.active)
		want = ok and want == true
		if want ~= shown then
			shown = want
			if not shownState:hasExpired() then shownState:set(want) end
		end
	end)
	local original = react.CallOriginalRecipe(free_cam_options.FreeCamOptions, param)
	local extra = nil
	if shown then
		local okB, node = pcall(bar)
		if okB then
			extra = node
		elseif not logged then
			logged = true
			say(" render ERROR " .. tostring(node))
		end
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { original, extra },
	}
end)

--- The replacement api's callback (pm_bar.res.lua): the base FreeCamOptions recipe -> ours (which calls it).
local function doReplaceFn(replacementApi)
	local ok, err = pcall(function() replacementApi.ReplaceRecipe(free_cam_options.FreeCamOptions, B.Replacement) end)
	say(": FreeCamOptions wrapped " .. (ok and "ok" or ("ERROR " .. tostring(err))))
end
B.doReplaceFn = doReplaceFn

-- .script.lua resources expose their exports through data()
function data()
	return {
		doReplaceFn = doReplaceFn,
	}
end

return B
