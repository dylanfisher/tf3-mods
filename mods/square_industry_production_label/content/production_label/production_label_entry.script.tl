-- Industry Production Label: GUI hooks for the mod setting "Show only while holding Shift" (PLAN "Show
-- only while holding Shift (2026-10-19)"), all writing production_label_shift.tl's state:
--   * ProductionLabelEntry: an invisible root mounted with the game UI (::ModEntryPointExtension, base
--     gui/main/game.tl:73-93, production_label_entry.res.lua). When the setting is On, its onStep (main
--     thread, every frame, also while paused) tracks Shift held with the map or an entity window on top.
--   * ProductionLabelIndustryWindow / ProductionLabelWarehouseWindow: a plugin in every industry / warehouse
--     window (production_label_industry_eow.res.lua, production_label_warehouse_eow.res.lua) that draws
--     nothing and reports the window's construction open / closed, so the selected one keeps its pills.
--     Registered whatever the setting: the list costs nothing, and the labels only read it when it is On.
-- Settings only change on a game load, which rebuilds the GUI state, so reading them once here is enough.
-- The Mod Hub's upload validator runs this chunk without api.engine (docs/findings/publishing.md), so
-- every load-time api read is guarded: there it stays off.
-- GUI only: reads input, the tool stack and open windows, writes nothing, saves nothing.

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local mod_entry_point = ug_require "::/gui/main/mod_entry_point.tl" as ModEntryPoint
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals
local industry_eow = ug_require "::/gui/entity_window/industry/industry_eow.script.tl" as IndustryEow
local warehouse_eow = ug_require "::/gui/entity_window/warehouse/warehouse_eow.script.tl" as WarehouseEow

local model = ug_require "square_industry_production_label::/production_label/production_label_model.tl" as SquareProductionLabelModel
local shift = ug_require "square_industry_production_label::/production_label/production_label_shift.tl" as SquareProductionLabelShift

local MOD_ID <const> = "square_industry_production_label"
local SHIFT_ACTION <const> = "IA_PRECISION_MODE"

local enabled = false
do
	local ok, all = pcall(function() : any
		return api.engine.config.getModParams()
	end)
	local mine : any = nil
	if ok and type(all) == "table" then
		mine = (all as {string : any})[MOD_ID]
	end
	enabled = model.options(mine).holdShift
	if enabled then
		shift.installed = true
		log.message("square_industry_production_label: show only while holding Shift: on")
	end
end

local function shiftHeld() : boolean
	local ok, on = pcall(api.gui.inputAction.modifierOnlyActionIsActive, SHIFT_ACTION)
	return ok and on == true
end

--- Name of the top tool of the default tool stack, nil when unknown.
local function topToolName() : string
	local tsApi = game_react_globals.getDefaultToolStackApi()
	if tsApi == nil or tsApi.getActiveTool == nil then return nil end
	local ok, tool = pcall(tsApi.getActiveTool)
	local def = ok and tool as {string : any} or nil
	return def ~= nil and def.name as string or nil
end

local ProductionLabelEntry = react.RegisterPluginRecipe(mod_entry_point.ModEntryPointExtension, "ProductionLabelEntry", function() : TreeNodeId
	if enabled then
		react.onStep(function()
			-- the tool lookup only while Shift is down
			local held = shiftHeld()
			shift.update(held, held and topToolName() or nil)
		end)
	end
	return builtin.BoxLayout{ children = {} }
end)

-- Logged once: what a window's entity maps to (the window's entity and the label's differ).
local windowLogged = false

--- Window plugin body: report the window's construction open on mount, closed on unmount.
local function trackWindow(entity : Engine.Entity) : TreeNodeId
	local conRef : ReactRefT<integer> = react.useRef(-1)
	react.onMount(function()
		local ok, con = pcall(shift.toConstruction, entity as integer)
		if not ok then
			log.warning("square_industry_production_label: no construction for window entity " .. tostring(entity) .. ": " .. tostring(con))
			return
		end
		conRef:set(con)
		shift.opened(con)
		if not windowLogged then
			windowLogged = true
			log.message("square_industry_production_label: window entity " .. tostring(entity) .. " -> construction " .. tostring(con))
		end
	end)
	react.onUnmount(function()
		shift.closed(conRef:get())
	end)
	-- root BoxLayout, as every custom recipe's must be
	return builtin.BoxLayout{ children = {} }
end

local ProductionLabelIndustryWindow = react.RegisterPluginRecipe(industry_eow.IndustryEowExtensionPoint, "ProductionLabelIndustryWindow", function(params : IndustryEow.IndustryWidgetPluginParams) : TreeNodeId
	return trackWindow(params.entityId)
end)

local ProductionLabelWarehouseWindow = react.RegisterPluginRecipe(warehouse_eow.WarehouseEowExtensionPoint, "ProductionLabelWarehouseWindow", function(params : WarehouseEow.WarehouseWidgetPluginParams) : TreeNodeId
	return trackWindow(params.entityId)
end)

return {
	ProductionLabelEntry = ProductionLabelEntry,
	ProductionLabelIndustryWindow = ProductionLabelIndustryWindow,
	ProductionLabelWarehouseWindow = ProductionLabelWarehouseWindow,
}
