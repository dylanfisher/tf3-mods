-- Industry Production Label: when the pills show, for the mod setting "Show only while holding Shift"
-- (PLAN "Show only while holding Shift (2026-10-19)"): while Shift is held on the map, on every label; and
-- always on the industry / warehouse whose window is open (selected).
--
-- Shift: written by the ::ModEntryPointExtension plugin's onStep (production_label_entry.script.tl, main
-- thread, every frame): Shift held (input action IA_PRECISION_MODE, as Passenger Destinations and Line
-- Manager Plus read it) and the top tool is the plain map or an entity window (EntityDetailsTool; the map's
-- default tool is the same tool, view_manager.tl:340) or Passenger Destinations' Shift tool (it pushes
-- "SquarePassengerDestinations" while its Shift arrows show). Never while building or in any other tool
-- (line manager, layers, statistics, ...).
-- Selected: the industry / warehouse window plugins (production_label_entry.script.tl, ::IndustryEow- /
-- ::WarehouseEowExtensionPoint) call opened / closed with the window's entity on mount / unmount.
-- Both sides go through toConstruction (CONSTRUCTION component, else
-- streetConnectorSystem.getConstructionEntityForSubconstruction, as view_manager_util.wouldCreateView,
-- view_manager_util.tl:125-126): the window's entity and the label's STOCK_LIST subconstruction differ.
--
-- Read by the HUD labels (production_label.script.tl ProductionLabelShiftGate). Mod entry point, window
-- plugins and HUD icon scripts share one Lua state, so this module table is the channel
-- (docs/findings/gui.md, 2026-10-20). A label that sees `installed` false (no entry point in its state)
-- shows always.
--
-- No api.* except toConstruction; unit-tested in tests/square_industry_production_label/test_shift.lua.
-- Nothing is saved.

local shift : SquareProductionLabelShift = {}

-- Top tools in which holding Shift shows the pills.
shift.TOOLS = { EntityDetailsTool = true, SquarePassengerDestinations = true }

-- True once the entry point runs in this Lua state.
shift.installed = false
-- True while Shift shows the pills on every label.
shift.active = false
-- Construction -> number of its windows open.
shift.selected = {}

--- One frame's input: Shift held, and the top tool's name (nil when unknown). Returns shift.active.
function shift.update(held : boolean, toolName : string) : boolean
	shift.active = held == true and toolName ~= nil and shift.TOOLS[toolName] == true
	return shift.active
end

--- A window of `construction` opened.
function shift.opened(construction : integer)
	if construction == nil or construction < 0 then return end
	shift.selected[construction] = (shift.selected[construction] or 0) + 1
end

--- A window of `construction` closed.
function shift.closed(construction : integer)
	local n = construction ~= nil and shift.selected[construction] or nil
	if n == nil then return end
	if n <= 1 then
		shift.selected[construction] = nil
	else
		shift.selected[construction] = n - 1
	end
end

--- True when the label of `construction` shows its pills.
function shift.isShown(construction : integer) : boolean
	if shift.active or not shift.installed then
		return true
	end
	return construction ~= nil and shift.selected[construction] ~= nil
end

--- Fresh state (tests).
function shift.reset()
	shift.installed = false
	shift.active = false
	shift.selected = {}
end

--- The construction entity of `entity` (itself when it is one), or `entity` when it belongs to none.
--- -1 for nil or negative. Engine reads only; errors pass to the caller.
function shift.toConstruction(entity : integer) : integer
	if entity == nil or entity < 0 then
		return -1
	end
	if api.engine.getComponent(entity, api.type.ComponentType.CONSTRUCTION) ~= nil then
		return entity
	end
	local con = api.engine.system.streetConnectorSystem.getConstructionEntityForSubconstruction(entity)
	if con ~= nil and con >= 0 then
		return con
	end
	return entity
end

return shift
