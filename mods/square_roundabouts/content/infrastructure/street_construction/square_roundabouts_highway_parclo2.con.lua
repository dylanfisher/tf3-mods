-- Better Roundabouts: Highway Interchange "Parclo, two quadrants" menu entry (INTERCHANGES.md "Phase 7c3 notes").
-- A thin wrapper: params, icons and the updateScript (types fixed by its params) come from
-- square_roundabouts_highway_menu.lua; geometry: square_roundabouts_highway.lua.

local menu = ug_require "square_roundabouts::/infrastructure/street_construction/square_roundabouts_highway_menu.lua"

function data()
	return menu.data("parclo2", _)
end
