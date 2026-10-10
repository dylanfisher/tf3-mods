-- Better Bus Overlay styles: the shaded stop pin in the Lines window (ShadedStopIcon in better_bus_overlay.script.lua, which
-- replaces the engine's default bus pin inside HudStationWithLineStops). Every rule is scoped under that recipe
-- (R::SquareBetterBusLinesShadedStopIcon), so nothing here touches other views or mods. .css.lua files are picked up by
-- extension (docs/wiki/modding/general/resourcetypes.md, "Stylesheets"); layout as
-- mods/square_problem_radar radar_hud.css.lua.
--
-- The pin is the game's own mask (gui.zip gui/hud/icons/hud_background@2x.tga, 80x104, so 40x52 at 1x) in a tinted
-- ImageView scaled to the vanilla on-screen size (a nine-patch background can't shrink its corners and tail). The bus glyph (vehicle_bus_front_32@2x.tga) is a white mask tinted
-- by `color` (memory tf3-imageview-rotation-icons). Both colours are set inline per pin by the script (PIN_STOPS
-- gradient: light blue -> yellow -> red); only sizes and placement live here.
local ssu = require "::/gui/main/stylesheetutil.lua"

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	local R = "R::SquareBetterBusLinesShadedStopIcon"

	-- frame and both layers: 29x38, the vanilla pin's on-screen size (about 72 % of the mask's natural 40x52)
	a(R .. " !sqslv-pin", {
		size = { 29, 38 },
	})
	a(R .. " !sqslv-pin-bg-layer", {
		size = { 29, 38 },
	})
	-- colour: inline per pin (gradient in the script, PIN_STOPS)
	a(R .. " ImageView!sqslv-pin-bg", {
		size = { 29, 38 },
	})
	-- glyph: 20x20 centred in the pin's body (the 38 px include the ~6 px tail): padding top, right, bottom, left
	a(R .. " !sqslv-pin-bus-layer", {
		size = { 29, 38 },
		padding = { 5, 4, 13, 5 },
	})
	a(R .. " ImageView!sqslv-pin-bus", {
		size = { 20, 20 },
	})

	return result
end
