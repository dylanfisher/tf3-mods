-- Bigger Line Dots: enlarges the line-colour dots in the map HUD above stations and stops.
-- Base rules (7x7 dots in a 9 px tall pill):
-- .cache/game/base/content/gui/line_vehicle_mgmt/line_vehicle_mgmt.css.lua:1422-1452.
-- Element tree (.cache/game/base/content/gui/line_vehicle_mgmt/manager_hud_util.tl:118-160):
--   R::HudStationWithLineStops ... BoxLayout > R::Component!stop-lines > BoxLayout > Button!line-dot
-- Each selector below adds one level to the base selector, so it is more specific and wins
-- whatever the stylesheet load order (docs/wiki/modding/scripting/userinterface.md:77).
-- Only size and margin change; colours, images and hover borders stay the base ones.
local ssu = require "::/gui/main/stylesheetutil.lua"

-- Dot edge length in px (base: 7). The pill is DOT + 2 px tall: 1 px dot margin top and bottom,
-- like the base 7 + 2 = 9.
local DOT = 12

function data()
	local result = { }

	local a = ssu.makeAdder(result)

	a("R::HudStationWithLineStops BoxLayout R::Component!stop-lines", {
		size = { -1, DOT + 2 },
		minSize = { DOT + 2, -1 },
	})

	a("R::HudStationWithLineStops R::Component!stop-lines Button!line-dot", {
		size = { DOT, DOT },
	})

	return result
end
