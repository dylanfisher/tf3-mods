-- Line Manager Plus, feature "Line list: line info on hover" (setting line_list_hover_info): hovering anywhere on a
-- line's row in the Line Manager's line list shows the line's info block OUTSIDE the Line Manager, right of it (left
-- when the window is in the right half of the screen), top aligned with the hovered row: the line's name, its
-- vehicles by model and its Capacity, Utilization, Frequency and Rate (no estimate). The same block, look and
-- behaviour as the Send to Line list's (stl_list.lua), both through lmp_callout.lua. No row hovered: no block. Depot
-- rows: none. GUI only: reads the game state, writes nothing, saves nothing. Installed by lmp.script.lua (doReplace).
--
-- Where the rows come from: LineAndDepotList (base manager_window.tl:2463-2759) renders builtin.DataTable{ columns =
-- { builtin.ColumnDesc{ name = _("Name"), recipe = LineAndDepotListEntry, ... } } } (:2722-2736, :2746-2756): the
-- row recipe, file-local, is the column's cell recipe. builtin.DataTableCell calls it per row as
-- recipe{ rowKey, colKey, userParam } (builtin.lua:120-123); userParam = { commonParams, lineAndDepotListApi }
-- (:2738-2741). The row (manager_window.tl:1957-2461) keeps its hover in a local state through its own
-- react.onMouseEvent (:1975-1993; one listener per recipe, react.lua:768, so we can't add one there) and has the
-- "Select Line" tooltip on its row Button (:2443).
--
-- Hook: the MODULE FIELD builtin.ColumnDesc ("::/gui/main/builtin.lua", looked up per render by manager_window.tl:2)
-- is wrapped with a plain function. When it gets one table whose recipe is LineAndDepotListEntry
-- (react.GetRecipeName, react.lua:441, a table lookup), it passes a copy with recipe = a plain function (made once per
-- inner recipe, so the column's recipe never changes between renders) that calls
--   inner(react.ref(holder), { rowKey, colKey, userParam, meta = { onMouseOver = ... } })
-- inside the DataTableCell, exactly where the vanilla call is: no extra node, no extra layout, nothing re-rendered.
-- Recipes are plain Lua closures (react.lua:382-393), so the cell calls our function as it calls the recipe.
--   * meta on a recipe call is applied to the recipe's node (react.lua:308-374, stripped from the params, so the row
--     sees the same params as before): onMouseOver(isHovered) (react.d.tl:109) is a component callback, separate
--     from the row's own mouse listener, which keeps working. Base opens callouts from onMouseOver too
--     (tile_list_react_util.tl:110-115), so it runs on the GUI thread.
--   * react.ref(holder): react only calls holder:set(nodeRef) when it creates the node (react.lua:343-352); holder
--     then serves as the callout's parent (get / hasExpired). The node ref never expires by itself: a row that goes
--     while hovered gets no onMouseOver(false), and the container's own check (callout_container.tl:101-104,
--     getIdentity) did not drop it (player report 2026-10-11: delete a new line with the mouse on its row and the
--     block stays, game at ~3 FPS until another row is hovered; the container then reads the dead node every step).
--     So the holder expires itself (M.newHolder): when its line is gone, the line list's ref has expired (the Line
--     Manager closed) or the row's position can't be read; the container drops the block on its next step.
-- Every other ColumnDesc call (other tables), a call with a ref, a row param that already has meta, or anything
-- failing goes to the previous function unchanged.
--
-- Hover: onMouseOver(true) opens the block for the row's line through the module's one lmp_callout tracker (its text
-- built only then, lmp_stats 1 s cache), onMouseOver(false) closes it if it is that row's (moving to the next row
-- opens that one's in its place, whichever event comes first). No onStep, no state: nothing runs while nothing is
-- hovered. Position: getPositionFn (callout_container.tl:47-54), recomputed by the container each step: x = the line
-- list's (commonParams.lineAndDepotListRef, manager_window.tl:5952, :6343) right edge (left edge when the window's
-- centre is in the right half of the screen), y = the hovered row's top; the panel's padding adds M.GAP px, which
-- clears the window's card padding (8 px, line_vehicle_mgmt.css.lua:20, 146-148) and the card border, so the block
-- sits outside the window (the window is one 500 px column: top bar, line list card, vehicle card, line panel card,
-- line_vehicle_mgmt.css.lua:18, 150-153, 225-233). A position that can't be read keeps the last one and expires the
-- holder (the row is gone).
--
-- Chain safety: install() reads the current field (another mod's wrapper stays in the chain) and wraps the shared
-- replacement api so that a later ReplaceRecipe(<our wrapper>, x) gets the function we wrapped.
-- SQPERF section "list_hover": building the hovered row's block text.

local PREFIX = "[LineManagerPlus] list hover: "

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
local callout = ug_require "square_line_manager_plus::/line_manager_plus/lmp_callout.lua"
local perf = (ug_require "square_line_manager_plus::/line_manager_plus/lmp_perf.lua").perf

local M = {}

M.ROW_RECIPE = "LineAndDepotListEntry"
M.BUILTIN = "::/gui/main/builtin.lua"
M.GAP = 18 -- UI px from the line list's edge: the window's card padding (8) and border, then the 8 px gap

--- The block text for `line` (lmp_callout.panelText, no estimate), timed as SQPERF section "list_hover".
M.panelText = perf:wrap("list_hover", callout.panelText)

-- the one block of the line list (the Line Manager is a single window)
local shown = callout.newShown(function(line, vehicles) return M.panelText(line, vehicles) end, warnOnce)

-- the node of a ref wrap, or nil when it is missing or expired
local function liveNode(ref)
	if ref == nil then return nil end
	if ref.hasExpired ~= nil and ref:hasExpired() == true then return nil end
	return ref:get()
end

-- true while `line` is still a line (false once deleted; an engine failure counts as gone)
local function lineExists(line)
	local ok, comp = pcall(api.engine.getComponent, line, api.type.ComponentType.LINE)
	return ok and comp ~= nil
end

--- A ref for react.ref(): react calls :set(nodeRef) when it creates the row's node; :get / :hasExpired make it a
--- callout parent. line / listRef (optional): the row's line and the line list's ref wrap. Expired (for good, the
--- node dropped) once the node is unset, the line is gone or the list ref has expired; :expire() does it directly.
--- The container calls hasExpired every step while the block is shown: one component lookup. See the header.
function M.newHolder(line, listRef)
	local h = { node = nil }
	function h:set(node) self.node = node end
	function h:get() return self.node end
	function h:expire() self.node = nil end
	function h:hasExpired()
		if self.node == nil then return true end
		if (line ~= nil and not lineExists(line))
				or (listRef ~= nil and listRef.hasExpired ~= nil and listRef:hasExpired() == true) then
			self.node = nil
			return true
		end
		return false
	end
	return h
end

--- Callout params for `text` beside the line list, top aligned with the row node of `holder`. listRef: the list's
--- ref wrap (commonParams.lineAndDepotListRef); without it the row's own edges are used. Errors propagate.
function M.place(holder, listRef, text)
	local edge = liveNode(listRef) or holder:get()
	local onRight = callout.onRightOf(edge)
	local function position()
		local row = holder:get()
		local list = liveNode(listRef) or row
		return api.type.Vec2f.new(list:getPosition(onRight and 1 or 0, 0).x, row:getPosition(0, 0).y)
	end
	local last = position()
	local function getPositionFn()
		local ok, pos = pcall(position)
		if ok and pos ~= nil then
			last = pos
		else
			holder:expire() -- the row is gone: the container drops the block on its next step
		end
		return last
	end
	return callout.besideParams(holder, text, onRight, { gap = M.GAP, getPositionFn = getPositionFn })
end

--- The row's hover changed: open the block for `line` (hovered) or close the row's block. Errors propagate.
function M.onHover(holder, line, commonParams, hovered)
	local function getApi() return callout.api(commonParams.gameCtx) end
	if not hovered then return shown:hide(getApi, holder) end
	shown:show(getApi, line, holder, nil, function(text) return M.place(holder, commonParams.lineAndDepotListRef, text) end)
end

--- For a row's cell param: the ref holder and the param copy with meta.onMouseOver, or nil (leave the call as is).
function M.decorate(cell)
	-- the DataTable's C++ side passes a userdata (Builtin.TableCellParam: rowKey, colKey, userParam, builtin.d.tl
	-- :1125-1129), not a table (in game 2026-10-11); the row reads only rowKey and userParam (manager_window.tl:1957-1959)
	local kind = type(cell)
	if kind ~= "table" and kind ~= "userdata" then return nil end
	if kind == "table" and cell.meta ~= nil then return nil end
	local line, colKey, up = cell.rowKey, cell.colKey, cell.userParam
	if type(line) ~= "number" then return nil end
	local cp = type(up) == "table" and up.commonParams or nil
	if type(cp) ~= "table" then return nil end
	local holder = M.newHolder(line, cp.lineAndDepotListRef)
	local param = { rowKey = line, colKey = colKey, userParam = up }
	param.meta = { onMouseOver = function(isHovered)
		local ok, err = pcall(M.onHover, holder, line, cp, isHovered == true)
		if not ok then warnOnce("hover", err) end
	end }
	return holder, param
end

local rowFns = setmetatable({}, { __mode = "k" }) -- inner recipe -> our cell function (stable per inner)

--- Our cell function around the row recipe `inner` (the same function for the same inner).
function M.rowFn(inner)
	local fn = rowFns[inner]
	if fn then return fn end
	fn = function(cell, ...)
		if select("#", ...) == 0 then
			local ok, holder, param = pcall(M.decorate, cell)
			if not ok then
				warnOnce("row", holder)
			elseif holder ~= nil then
				-- a table ref is taken as a LIST of refs (react.lua:355-358, `for _, v in ipairs(ref) do v:set(..)`),
				-- so the plain-table holder goes in a one-element list (in game 2026-10-11: `row` stayed nil)
				return inner(react.ref({ holder }), param)
			end
		end
		return inner(cell, ...)
	end
	rowFns[inner] = fn
	return fn
end

--- A copy of the ColumnDesc param `p` with our cell function, or nil when it isn't the line list's column.
function M.swap(p)
	if type(p) ~= "table" or type(p.recipe) ~= "function" then return nil end
	if react.GetRecipeName(p.recipe) ~= M.ROW_RECIPE then return nil end
	local copy = {}
	for k, v in pairs(p) do copy[k] = v end
	copy.recipe = M.rowFn(p.recipe)
	return copy
end

local prev -- the ColumnDesc we wrapped, set by install()
local wrapper -- our function in builtin.ColumnDesc

local function columnDesc(...)
	if select("#", ...) == 1 then
		local ok, copy = pcall(M.swap, ...)
		if not ok then
			warnOnce("column", copy)
		elseif copy ~= nil then
			local okNode, node = pcall(prev, copy)
			if okNode then return node end
			warnOnce("column", node)
		end
	end
	return prev(...)
end

-- a later ReplaceRecipe(<our wrapper>, x) gets the function we wrapped instead (see the header)
local function shimReplacementApi(replacementApi)
	if type(replacementApi) ~= "table" then return end
	local replace = replacementApi.ReplaceRecipe
	if type(replace) ~= "function" then return end
	replacementApi.ReplaceRecipe = function(original, ...)
		if wrapper ~= nil and original == wrapper then original = prev end
		return replace(original, ...)
	end
end

--- Wraps builtin.ColumnDesc; true when installed (now or before). Never errors.
function M.install(replacementApi)
	if prev then return true end
	local ok, err = pcall(function()
		local builtin = ug_require(M.BUILTIN)
		local fn = type(builtin) == "table" and builtin.ColumnDesc or nil
		if type(fn) ~= "function" then
			warnOnce("install", "builtin.ColumnDesc is " .. type(fn) .. "; line list left as is")
			return
		end
		if type(react.GetRecipeName) ~= "function" or type(react.ref) ~= "function" then
			warnOnce("install", "react.GetRecipeName / react.ref missing; line list left as is")
			return
		end
		prev = fn
		wrapper = columnDesc
		builtin.ColumnDesc = wrapper
		shimReplacementApi(replacementApi)
		say("installed")
	end)
	if not ok then
		warnOnce("install", err)
	end
	return prev ~= nil
end

return M
