-- Line Manager Plus: the line info block shown OUTSIDE a card while a line is hovered, shared by "Send to Line list:
-- line info panel" (stl_list.lua, the Send to Line popover's list) and "Line list: line info on hover"
-- (line_list_hover.lua, the Line Manager's main line list), so both look and behave the same. GUI only.
--
-- The block is a CALLOUT in the game's callout overlay (gameCtx.calloutContainerRef, game.tl:173-187, 910-915;
-- callout_container.tl): a FloatingLayout over the whole UI, after the ui-root that holds the windows (so drawn on
-- top of them), react.setMouseTransparent(true) (callout_container.tl:7): it never takes the mouse, so the list
-- under it keeps its hover, and never takes focus. One callout at a time: open() replaces the current one,
-- close(parent) closes it only while it is that parent's (:83-93). The container recomputes the position every step
-- (getPositionFn when given, else the parent node's point at `gravity`, :47-54, 95-120), keeps it on screen
-- (KeepInside) and drops it once its parent node is gone (:101-104). No delay: shown at once.
--
-- Content: the line's name, then lmp_stats.lines (vehicles by model; Capacity, Utilization, Frequency, Rate; with
-- `vehicles`, the before -> after estimate), in a TextView with the vanilla tooltip text classes plus "sq-lmp-stli",
-- the map hover block's class (stli.lua), whose one rule in lmp.css.lua colours all of them the same darker blue.
-- Panel recipe: { text, onRight, gap } -> BoxLayout{ Component(padding: `gap` px on the card's side, inline
-- StyleSheet) -> BoxLayout{ TextView } }; root BoxLayout; the container sets its anchorPoint through meta.styleSheet
-- (callout_container.tl:122-129). The TextView sizes to its longest line, so translated text fits.
--
-- Placement (as content_card.useShowCalloutOnRight, content_card.tl:183-189): RIGHT of the card when the card's
-- centre is in the left half of the screen, else LEFT of it, top aligned, so it never covers the hovered rows.
--
-- Shown (newShown): which line's block one owner shows. show() opens the block for a line once (nothing while the
-- same line and parent stay hovered; the text is built only then, through the caller's perf-wrapped text function),
-- closes it for a line without text (deleted, a depot) or on a stats error; hide() closes it (only the given
-- parent's). Every call into the overlay is guarded: failures go to the owner's warn-once logger ("stats",
-- "callout") and never reach the game.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local stats = ug_require "square_line_manager_plus::/line_manager_plus/lmp_stats.lua"

local M = {}

-- vanilla tooltip text classes + the map hover block's class (as stli.lua TOOLTIP_CLASS): the same look and colour
M.PANEL_CLASS = "lvm-selector-tooltip, font-scale-tooltip, default-tooltip-configuration, sq-lmp-stli"
M.GAP = 8 -- UI px between the card and the block (default)

--- The block text for `line`: its name, then stats.lines (vehicles by model, the stats row; with `vehicles`, the
--- before -> after estimate). nil when it isn't a line (deleted, a depot). Errors propagate.
function M.panelText(line, vehicles)
	local lines = stats.lines(line, vehicles)
	if type(lines) ~= "table" or #lines == 0 then return nil end
	local out = {}
	local okName, name = pcall(function() return api.engine.util.getEntityName(line) end)
	if okName and type(name) == "string" and name ~= "" then out[1] = name end
	for _i, s in ipairs(lines) do out[#out + 1] = s end -- a copy: the cached list stays as it is
	return table.concat(out, "\n")
end

-- the callout recipe. p = { text, onRight, gap } (+ meta.styleSheet with the anchorPoint, set by the container).
-- Root BoxLayout; the Component's padding keeps `gap` to the card on its side (top, right, bottom, left).
M.Panel = react.RegisterRecipe("SquareLmpInfoCallout", function(p)
	local gap = p.gap or M.GAP
	local st = api.gui.StyleSheet.new()
	st.padding = api.type.Vec4f.new(0, p.onRight and 0 or gap, 0, p.onRight and gap or 0)
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.Component{
				meta = { styleSheet = st },
				layout = builtin.BoxLayout{
					orientation = builtin.type.Orientation.Vertical,
					children = { builtin.TextView{ meta = { class = M.PANEL_CLASS }, text = p.text } },
				},
			},
		},
	}
end)

--- The game's callout overlay api (game_context.d.tl CalloutApi), or an error.
function M.api(gameCtx)
	return gameCtx.calloutContainerRef:get():getApi()
end

--- true when the node's centre is in the left half of the screen (the block then goes right of it). Errors propagate.
function M.onRightOf(node)
	return node:getPosition(0.5, 0.0).x < 0.5
end

--- Callout params for `text` beside a card: anchored by its top-left corner (onRight) or top-right corner (left).
--- Without opts.getPositionFn the container places it at `parentRef`'s top-right (onRight) / top-left corner.
--- opts: { gap = px (default M.GAP), getPositionFn = function() : Vec2f }.
function M.besideParams(parentRef, text, onRight, opts)
	opts = opts or {}
	local gap = opts.gap or M.GAP
	return {
		recipe = M.Panel,
		recipeParam = { text = text, onRight = onRight, gap = gap },
		anchor = api.type.Vec2f.new(onRight and 0 or 1, 0),
		gravity = api.type.Vec2f.new(onRight and 1 or 0, 0),
		parent = parentRef,
		getPositionFn = opts.getPositionFn,
		recipeParamCompareFn = function(a, b) return a.text == b.text and a.onRight == b.onRight and a.gap == b.gap end,
	}
end

-- close the block of `parent` (a ref wrap) unless that ref is gone (the container then drops it on its next step)
local function closeOn(getApi, parent, warn)
	local ok, err = pcall(function()
		if parent == nil then return end
		if parent.hasExpired ~= nil and parent:hasExpired() == true then return end
		getApi().close(parent)
	end)
	if not ok then warn("callout", err) end
end

local Shown = {}
Shown.__index = Shown

--- A tracker of one owner's block. textFn(line, vehicles) builds the text (perf-wrapped by the owner);
--- warn(key, err) is the owner's warn-once logger.
function M.newShown(textFn, warn)
	return setmetatable({ line = nil, parent = nil, open = false, textFn = textFn, warn = warn }, Shown)
end

--- Show the block for `line` beside `parent` (line nil: hide the parent's block). Nothing happens while the same
--- line and parent are already handled. place(text) returns the callout params (it may error: logged, no block).
--- getApi() returns the overlay api. Never errors.
function Shown:show(getApi, line, parent, vehicles, place)
	if line == nil then return self:hide(getApi, parent) end
	if line == self.line and parent == self.parent then return end
	local wasOpen, oldParent = self.open, self.parent
	self.line, self.parent, self.open = line, parent, false
	local okText, text = pcall(self.textFn, line, vehicles)
	if not okText then
		self.warn("stats", text)
		text = nil
	end
	if text == nil then -- a deleted line, a depot or a stats error: no block
		if wasOpen then closeOn(getApi, oldParent, self.warn) end
		return
	end
	local ok, err = pcall(function() getApi().open(place(text)) end)
	if ok then
		self.open = true
	else
		self.warn("callout", err)
		if wasOpen then closeOn(getApi, oldParent, self.warn) end
	end
end

--- Hide the block if it is `parent`'s (parent nil: whatever this owner shows). Never errors.
function Shown:hide(getApi, parent)
	if self.line == nil and not self.open then return end
	if parent ~= nil and parent ~= self.parent then return end
	local wasOpen, oldParent = self.open, self.parent
	self.line, self.parent, self.open = nil, nil, false
	if wasOpen then closeOn(getApi, oldParent, self.warn) end
end

return M
