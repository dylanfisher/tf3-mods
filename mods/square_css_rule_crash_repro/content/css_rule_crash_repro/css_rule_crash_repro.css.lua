-- Bug repro (never upload): RULES stylesheet rules whose class matches no component, so nothing in the
-- game changes. Mod rules beyond ~200 (on top of the base game's ~5,970) crash the first frame after a
-- load in Component::ComputeStyles. Change RULES to move across the threshold (see README.md).
local ssu = require "::/gui/main/stylesheetutil.lua"

local RULES = 400

function data()
	local result = { }
	local a = ssu.makeAdder(result)
	for i = 1, RULES do
		a("TextView!sqcssrepro-none-" .. tostring(i), {
			color = { 1.0, 0.0, 1.0, 1.0 },
			margin = { i % 5, 0, 0, 0 },
		})
	end
	return result
end
