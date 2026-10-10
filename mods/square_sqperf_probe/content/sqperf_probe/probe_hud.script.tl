-- SQPERF probe: HUD icon script set on industries by content/mod.script.lua. HudIconMasterGame calls
-- hudIconFn(captureParams, params, userParam) and mounts the returned layout next to the stock pill
-- (.cache/game/base/content/gui/main/hud_icon_toolbox.tl:242-251; shape as
-- square_industry_production_label's production_label.script.tl). HUD icon code runs off the GUI
-- thread (memory: getApplicationTime hard-crashed there), so this is where api.type.Clock is unproven.
-- Probes: ctx=hudIconFn (the script function) and ctx=hud_render (the recipe it returns). Draws nothing.

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin

local record ProbeUtil
	log : function(string)
	stage : function() : integer
	hudOn : function(integer) : boolean
	stepOn : function(integer) : boolean
	probe : function(string, any, any)
end
local util = ug_require "square_sqperf_probe::/sqperf_probe/probe_util.lua" as ProbeUtil

local function emptyLayout() : TreeNodeId
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {},
	}
end

local SqPerfProbeHudIcon = react.RegisterRecipe("SqPerfProbeHudIcon", function() : TreeNodeId
	util.probe("hud_render", nil, nil)
	return emptyLayout()
end)

return {
	hudIconFn = function(_captureParams : any, _params : any, _userParam : any) : TreeNodeId
		if not util.hudOn(util.stage()) then
			return emptyLayout()
		end
		util.probe("hudIconFn", nil, nil)
		return SqPerfProbeHudIcon{}
	end,
}
