-- DEV probe (never upload): RULES stylesheet rules whose class matches no component, so nothing in the
-- game changes. Tests whether the total rule count from all mods triggers the load crash in
-- Component::ComputeStyles (plans/bugreports/2026-10-10-load-crash-gui-tree.md, review 2026-10-10).
local ssu = require "::/gui/main/stylesheetutil.lua"

local RULES = 40

function data()
	local result = { }
	local a = ssu.makeAdder(result)
	for i = 1, RULES do
		a("TextView!sqcssprobe-none-" .. tostring(i), {
			color = { 1.0, 0.0, 1.0, 1.0 },
			margin = { i % 5, 0, 0, 0 },
		})
	end
	return result
end
