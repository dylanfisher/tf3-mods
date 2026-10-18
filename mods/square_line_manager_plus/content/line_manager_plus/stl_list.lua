-- Line Manager Plus, feature "Send to Line list: line info panel" (PLAN.md feature 1, setting send_to_line_list_info):
-- while the Send to Line popup is open (the "Send to Line" title, the "First Stop" combo box and the list of lines),
-- hovering a line in that list shows a dark info block OUTSIDE the popup, right of it (left when the popup is in the
-- right half of the screen; user decision D2, 2026-10-11: "right of the card, the darker blue of the map hover") with
-- the line's name, its vehicles by model and its Capacity, Utilization, Frequency and Rate, the same lines as the map
-- hover text (stli.lua), plus the before -> after estimate for the vehicles being sent when "send_to_line_estimate"
-- is On. No row hovered: no block. GUI only: reads the game state, writes nothing, saves nothing. Installed by lmp.script.lua (doReplace).
--
-- Where the list comes from: the Send to Line button opens popover_react_util.PopoverWindow with
-- recipe = SendToLineSelection (base manager_window.tl:7336-7366 from the vehicle manager, :7893-7925 from the line
-- window), params { commonParams, selection = the vehicles being sent, sendToLine, ... } (:4504-4511).
-- SendToLineSelection (:4513-4690) is file-local, so ReplaceRecipe can't reach it. Each row's onMouseOver only sets
-- commonParams.sendToLineHoveredLineState (:4626-4636; the state is the manager's, :5917, :6334).
--
-- Hook: PopoverWindow renders popover_react_util.PopoverWindowContent{ recipe = params.recipe, params = ... }
-- (popover_react_util.tl:41-46), a MODULE FIELD looked up per render, and PopoverWindowContent renders
-- params.recipe(params.params) (:25-28). That field is wrapped with a plain function (as UI Overhaul's
-- gui/terminals.lua and Easy Terminal Assignment do for the terminal popover). Not ReplaceRecipe: one slot per recipe,
-- and Auto Assign Terminals already replaces PopoverWindowContent (aat_eow.script.lua:430-441, 704; it captured the
-- base recipe at load, so it stays in the chain behind us). The wrapper swaps the inner recipe only when
--   * it gets one table argument with a recipe,
--   * whose params have a `selection` table and commonParams.sendToLineHoveredLineState, and
--   * react.GetRecipeName(recipe) is "SendToLineSelection" (react.lua:441, a table lookup).
-- Then a copy of the param goes on with recipe = SquareLmpStlList and params = { inner, innerParams }; every other
-- field (onClose, meta) stays, so the popover's own focus and "pressed outside closes" handling (popover_react_util.tl:
-- 7-23) and other mods' wrappers work as before. Any other
-- popover, or anything failing, goes to the previous function unchanged.
--
-- Why not inside the card (rev 1's first build, 2026-10-11 in game): the popover window has a FIXED width, 440 px
-- ("Window!popover" size, popover_react_util.css.lua:14-17; the rows are 416 px, line_vehicle_mgmt.css.lua:1047-1051,
-- in a ScrollArea that fills the width, :1010-1017). A panel in a horizontal BoxLayout beside the list squeezed the
-- list (names clipped, the scrollbar moved left) and took the place of the rows' right part: the mouse there was now
-- over the panel, the row's onMouseOver(false) (manager_window.tl:4626-4636) cleared the hovered line, the panel went,
-- the row came back under the mouse, hover again: flicker.
--
-- So the panel is a CALLOUT outside the card: the game's callout overlay (gameCtx.calloutContainerRef, reached
-- through commonParams.gameCtx, line_util.d.tl:420-421; game.tl:173-187), the layer the entity windows' card callouts
-- (content_card.tl:65-180) and the tile list's warnings (tile_list_react_util.tl:54-80) use. CalloutContainer
-- (callout_container.tl) is a FloatingLayout over the whole UI (game.tl:910-915, after the ui-root that holds the
-- windows, so on top of them), react.setMouseTransparent(true) (:7): it never takes the mouse, so the list keeps its
-- hover, and it never takes focus, so the popover's focus and "pressed outside closes" handling are untouched (a
-- click on the block goes to whatever is under it, as a click beside the card does). One callout at a time; it
-- follows its parent node every step (:95-120) and is dropped when that node is gone.
--
-- The callout itself (the Panel recipe, its look, placement and the open/close tracker) is lmp_callout.lua, shared
-- with the Line Manager's main line list (line_list_hover.lua), so both blocks look and behave the same.
--
-- SquareLmpStlList: BoxLayout{ inner(innerParams) }, the vanilla list alone with its untouched params, so the card
-- looks and lays out exactly as vanilla. Its react.onStep (Main Thread, docs/findings.md "Timers and threads") reads
-- the hovered line (one state read and compare per step) and hands it to its lmp_callout tracker: on a change it
-- opens the callout for that line with parent = its own node, or closes it (no line, a deleted line or a depot, any
-- failure). The block goes RIGHT of the card (top-right corner of the list, anchored by its top-left) when the card's
-- centre is in the left half of the screen, else LEFT of it, so it never covers the rows; the container also keeps
-- it on screen (KeepInside). onUnmount closes it (as callout_react_util.ToggleCalloutButton does), so it goes with
-- the popover. The text is built only for a hovered line, through lmp_stats.lua (1 s cache per line).
--
-- Chain safety: install() reads the current field (other mods' wrappers stay in the chain) and wraps the shared
-- replacement api so that a later mod's ReplaceRecipe(<our wrapper>, x) gets the recipe we wrapped.
-- SQPERF section "stl_list": building the hovered line's panel text.

local PREFIX = "[LineManagerPlus] list info: "

local warned = {}
local function warnOnce(key, err)
	if warned[key] then return end
	warned[key] = true
	local text = PREFIX .. key .. ": " .. tostring(err) .. " (further failures not logged)"
	if log and log.warning then log.warning(text) else print(text) end
end

local function say(msg)
	if log and log.message then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local callout = ug_require "square_line_manager_plus::/line_manager_plus/lmp_callout.lua"
local detect = ug_require "square_line_manager_plus::/line_manager_plus/lmp_detect.lua"
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf

local M = {}

M.BASE_RECIPE = "SendToLineSelection"
M.POP = "::/gui/main/popover_react_util.tl"
M.PANEL_CLASS = callout.PANEL_CLASS
M.GAP = callout.GAP -- UI px between the card and the block
M.Panel = callout.Panel

local estimateOn = false -- send_to_line_estimate, read by install()

--- The panel text for `line` (lmp_callout.panelText: name, vehicles by model, stats; with `vehicles`, the estimate),
--- timed as SQPERF section "stl_list". nil when it isn't a line (deleted, a depot). Errors propagate.
M.panelText = perf:wrap("stl_list", callout.panelText)

-- the hovered line of the list (nil: none). The state belongs to the manager window; :old() is a plain read, skipped
-- once that window is gone (an expired state's :old() prints a traceback, as lmp_capture.expired explains).
local function hoveredLine(commonParams)
	local state = commonParams.sendToLineHoveredLineState
	if state == nil then return nil end
	local isExpired = state.hasExpired
	if isExpired ~= nil and isExpired(state) == true then return nil end
	local line = state:old()
	if type(line) == "number" then return line end
	return nil
end

--- The callout params for `text` beside the node `selfRef` (the list): right of it when its centre is in the left
--- half of the screen, else left of it; top aligned either way (lmp_callout.besideParams). Errors propagate.
function M.calloutParams(selfRef, text)
	return callout.besideParams(selfRef, text, callout.onRightOf(selfRef:get()))
end

-- p = { inner = SendToLineSelection, innerParams = its params }. The vanilla list alone, untouched; the info block is
-- a callout outside the card, opened and closed from onStep when the hovered line changes (see the header).
M.List = react.RegisterRecipe("SquareLmpStlList", function(p)
	local selfRef = react.useSelfRef()
	local shownRef = react.useRef(nil) -- the lmp_callout tracker of this list's block, made on first use
	local cp = p.innerParams.commonParams
	local function getApi() return callout.api(cp.gameCtx) end
	local function shown()
		local s = shownRef:get()
		if s == nil then
			s = callout.newShown(function(line, vehicles) return M.panelText(line, vehicles) end, warnOnce)
			shownRef:set(s)
		end
		return s
	end
	local function place(text) return M.calloutParams(selfRef, text) end

	react.onStep(function()
		local okHover, line = pcall(hoveredLine, cp)
		if not okHover then
			warnOnce("hover", line)
			line = nil
		end
		shown():show(getApi, line, selfRef, estimateOn and p.innerParams.selection or nil, place)
	end)
	-- the block goes with the popover. Shown:hide skips the overlay when our ref has expired: the container then drops
	-- the callout itself on its next step (its parent is gone, callout_container.tl:101-104).
	react.onUnmount(function()
		local s = shownRef:get()
		if s ~= nil then s:hide(getApi, nil) end
	end)

	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = { p.inner(p.innerParams) } }
end)

--- true when `p` (a PopoverWindowContent param) is the Send to Line popover. Errors propagate.
function M.matches(p)
	if type(p) ~= "table" or p.recipe == nil then return false end
	local params = p.params
	if type(params) ~= "table" or type(params.selection) ~= "table" then return false end
	local cp = params.commonParams
	if type(cp) ~= "table" or cp.sendToLineHoveredLineState == nil then return false end
	return react.GetRecipeName(p.recipe) == M.BASE_RECIPE
end

--- A copy of `p` with our recipe around the vanilla one, or nil when `p` isn't the Send to Line popover.
function M.swap(p)
	if not M.matches(p) then return nil end
	local copy = {}
	for k, v in pairs(p) do copy[k] = v end
	copy.recipe = M.List
	copy.params = { inner = p.recipe, innerParams = p.params }
	return copy
end

local prev -- the PopoverWindowContent we wrapped, set by install()
local wrapper -- our function in popover_react_util.PopoverWindowContent

local function content(p, ...)
	if select("#", ...) == 0 then
		local ok, copy = pcall(M.swap, p)
		if not ok then
			warnOnce("swap", copy)
		elseif copy ~= nil then
			return prev(copy)
		end
	end
	return prev(p, ...)
end

-- a later ReplaceRecipe(<our wrapper>, x) gets the recipe we wrapped instead (see the header)
local function shimReplacementApi(replacementApi)
	if type(replacementApi) ~= "table" then return end
	local replace = replacementApi.ReplaceRecipe
	if type(replace) ~= "function" then return end
	replacementApi.ReplaceRecipe = function(original, ...)
		if wrapper ~= nil and original == wrapper then original = prev end
		return replace(original, ...)
	end
end

--- Wraps popover_react_util.PopoverWindowContent; true when installed (now or before). Never errors.
--- params: this mod's params (lmp_detect.modParams); "send_to_line_estimate" Off leaves the estimate out.
function M.install(replacementApi, params)
	if prev then return true end
	local ok, err = pcall(function()
		local pop = ug_require(M.POP)
		local fn = type(pop) == "table" and pop.PopoverWindowContent or nil
		if type(fn) ~= "function" then
			warnOnce("install", "popover_react_util.PopoverWindowContent is " .. type(fn) .. "; list left as is")
			return
		end
		if type(react.GetRecipeName) ~= "function" then
			warnOnce("install", "react.GetRecipeName is missing; list left as is")
			return
		end
		estimateOn = detect.paramOn(params, "send_to_line_estimate")
		prev = fn
		wrapper = content
		pop.PopoverWindowContent = wrapper
		shimReplacementApi(replacementApi)
		say(estimateOn and "installed" or "installed (estimate off: mod setting)")
	end)
	if not ok then
		warnOnce("install", err)
	end
	return prev ~= nil
end

return M
