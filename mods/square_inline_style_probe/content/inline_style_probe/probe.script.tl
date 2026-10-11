-- DEV ONLY - NOT FOR UPLOAD. Inline-style probe for the load crash above ~200 mod stylesheet rules
-- (docs/findings.md; plans/bugreports/2026-10-10-load-crash-gui-tree.md). The crash reads a stale
-- animationName pointer in Component::ComputeStyles, from rule storage or from instance rules
-- (GetValueFromBestInstanceRule). Question: do inline StyleSheets (meta.styleSheet) count too?
-- This mod has NO .css.lua. Its MainModButtonArea plugin (rendered on the Main Thread from the first
-- frame, docs/findings.md "Timers and threads in GUI contexts") returns N invisible Components, each
-- with its own distinct StyleSheet (size 0x0, distinct colour and padding, so nothing can be shared),
-- stacked in a FloatingLayout inside a 0x0 Component. No game script, no visible effect.
-- GUI rules (memory): plugin root is a BoxLayout; only fields from builtin.d.tl's *Param records.

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl" as MainModButtonArea
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil

--- Number of distinct inline StyleSheets.
local N <const> = 60
local LOG_PREFIX <const> = "[SQISP] "

-- Created once, lazily, in the first render (GUI thread), then reused.
local sheets : {StyleSheet} = nil
local outer : StyleSheet = nil

local function makeSheets()
	sheets = {}
	for i = 1, N do
		local st = styleutil.makeStyle{ size = { 0, 0 }, color = { i / N, 0, 1, 1 } }
		st.padding = api.type.Vec4f.new(i % 4, 0, 0, 0)
		sheets[i] = st
	end
	outer = styleutil.makeStyle{ size = { 0, 0 } }
	log.message(LOG_PREFIX .. "created " .. tostring(N + 1) .. " inline StyleSheets")
end

local InlineStyleProbePlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "InlineStyleProbePlugin", function() : TreeNodeId
	if sheets == nil then makeSheets() end
	local children : {TreeNodeId} = {}
	for i = 1, N do
		children[i] = builtin.Component{ meta = { styleSheet = sheets[i] } }
	end
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Component{
				meta = { styleSheet = outer },
				layout = builtin.FloatingLayout{ children = children },
			},
		},
	}
end)

return {
	InlineStyleProbePlugin = InlineStyleProbePlugin,
}
