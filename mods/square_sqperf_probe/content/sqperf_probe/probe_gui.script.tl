-- SQPERF probe: an invisible plugin in the top-left mod button ridge (probe_gui.res.lua) whose
-- render (GUI thread: the baseline, plus a timer benchmark) creates a Clock, and whose react onStep /
-- onStepTimer callbacks (worker threads, memory "onStep runs on worker threads") create and read
-- Clocks: a new one in the callback, the render's shared one, and an SQPERF timed instrument.
-- Base precedent: react.onStep reads a Clock made in render in credits_react_util.tl:212-226 and
-- main_menu.tl:201-242; this probe checks it for a mod in a loaded game.

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea

local record ProbeUtil
	log : function(string)
	stage : function() : integer
	hudOn : function(integer) : boolean
	stepOn : function(integer) : boolean
	probe : function(string, any, any)
	bench : function(any, any)
end
local util = ug_require "square_sqperf_probe::/sqperf_probe/probe_util.lua" as ProbeUtil
local sqperf = ug_require "square_sqperf_probe::/sqperf/square_sqperf_probe.lua" as SquareSqperfProbeSqPerf

local benched = false
local rendered = 0

local SqPerfProbePlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "SqPerfProbePlugin", function() : TreeNodeId
	local stage = util.stage()
	rendered = rendered + 1
	if rendered == 1 then util.log("ctx=render stage=" .. tostring(stage)) end
	-- GUI thread: the baseline (same as base main_menu.tl:492 react.useState(api.type.Clock.new())).
	util.probe("render", nil, nil)
	local clockRef = react.useRefLazy(function() : Clock return api.type.Clock.new() end) as ReactRefT<Clock>
	local shared = clockRef:get()
	if not benched then
		benched = true
		util.bench(shared, sqperf)
	end
	if util.stepOn(stage) then
		-- Created here (render), used in the callbacks: the pattern SQPERF uses in a GUI state.
		local instRef = react.useRefLazy(function() : SquareSqperfProbeSqPerfInst
			return sqperf.new({ mod = "square_sqperf_probe", ctx = "step", enabled = false })
		end) as ReactRefT<SquareSqperfProbeSqPerfInst>
		local inst = instRef:get()
		react.onStep(function()
			util.probe("onStep", shared, inst)
		end)
		react.onStepTimer(function()
			util.probe("onStepTimer", shared, inst)
		end, 1.0)
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {},
	}
end)

return {
	SqPerfProbePlugin = SqPerfProbePlugin,
}
