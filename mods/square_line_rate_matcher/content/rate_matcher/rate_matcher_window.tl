-- Line Rate Matcher: the toolbar button and the popup window (plans/square_line_rate_matcher/PLAN.md phase 3).
-- rate_matcher.script.lua mounts ToolbarButton left of A+ in the Line Manager and hands over the manager's context.
--
-- Threads (docs/findings.md "Timers and threads in GUI contexts"): every engine read and every command runs on the
-- GUI main thread: in a click, or in a useStepState getter (react.onStep, Main Thread). No useStepStateTimer here
-- (worker threads). Command callbacks only store their result in the session table; the next step picks it up.
--
-- One window (addSingletonWindow), one module-level session = the line it shows. Opening it for another line
-- replaces the window; opening it for the same line brings it to the front and re-reads the line. After Apply, the
-- line is read again 1 s and 3 s after the last command callback (Rate follows within 1 s, findings "Line Rate,
-- cloning onto a line, sell on arrival"); while open, Rate and the vehicles are re-read every 2 s.
--
-- GUI rules (memory): every recipe returns a BoxLayout; recipes are items, never a Component's layout; no
-- mouseTransparent on ImageView; ScrollArea not used. Styles are inline (meta.styleSheet, as Problem Radar's
-- radar_inline.tl) except the window's opaque background and the right-aligned table columns (three rules in
-- rate_matcher.css.lua: the mod stylesheet rule total crashes the game above ~200, docs/findings.md).
--
-- Tables (after the second GUI test, 2026-10-10: fixed-width Components inside ToggleButtons did not line up): the
-- game's own table, builtin.DataTable with builtin.ColumnDesc columns (name, tooltip, weight, headerStyleClass), as
-- the management window's Lines tab (base gui/statistics/statistic_lines.tl:403-457): the table lays out header and
-- cells in shared weighted columns. Numeric cells call react.setStyleClasses("right-aligned") like the Lines tab's
-- cells (:103, :129) and the headers get headerStyleClass "right-aligned"; the base rule that aligns them is scoped
-- to the statistics window (statistics.css.lua:386-391), so rate_matcher.css.lua repeats it for our window. The
-- selected row: a CheckBox column first (the Line Manager's line rows, manager_window.tl:1873-1891) and the base
-- "Table !table-item!highlight" background (builtin.css.lua:1439-1441) on its cells; a click anywhere on a row
-- selects it (react.onMouseEvent Clicked, as credits_react_util.tl:204). DataTable hands userParam only to NEWLY
-- created cells (builtin.d.tl:1170), so every render uses fresh row keys: all cells are rebuilt with the current
-- texts (a handful of rows).
--
-- Layout (phase 3b, after the first in-game test, 2026-10-10): title = the line name; one summary line; supply on
-- one line per cargo; the target box (TextInputField: onTyping updates the plans per keystroke, builtin.d.tl:935-957,
-- as the vehicle store's search field, vehicle_store_window.tl:2259-2277; Enter / focus loss commits); the selected
-- model's plans (count rows with cost columns); the model comparison table (one row per model, click = select);
-- what Apply will do; Apply / Replace window / Close.
--
-- Vehicle list refresh: the Line Manager's vehicle list (commonParams.vehicleManagerStateRef) is filled when a line
-- is selected (manager_window.tl:1405-1410) and never re-read from the line; vanilla Clone adds its new vehicles in
-- its onBuy (vehicleManagerApi.addVehiclesToVehicleListAndSelect, manager_window.tl:5108-5117), Buy Vehicles in its
-- buyCallback (:7154-7163). We do the same through commonParams.addOrRemoveVehicleToVehicleList (:7000-7017, the
-- context's listAdd / listRemove) once the command callbacks are in, and again at the 1 s / 3 s re-reads.

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local game_react_globals = ug_require "::/gui/main/game_react_globals.tl" as GameReactGlobals
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil

local engine = ug_require "square_line_rate_matcher::/rate_matcher/rate_matcher_engine.tl" as SquareRateMatcherEngine
local commands = ug_require "square_line_rate_matcher::/rate_matcher/rate_matcher_commands.tl" as SquareRateMatcherCommands
local model = ug_require "square_line_rate_matcher::/rate_matcher/rate_matcher_model.tl" as SquareRateMatcherModel
local view = ug_require "square_line_rate_matcher::/rate_matcher/rate_matcher_view.tl" as SquareRateMatcherView

local M : SquareRateMatcherWindow = {}

local PREFIX <const> = "[RateMatcher] "
local WINDOW_ID <const> = "squarelineratematcher.window" -- rate_matcher.css.lua "#squarelineratematcher.window"
-- base icon (gui.zip gui/line_vehicle_mgmt/icons/stat_load_speed@2x.tga, 48x48 greyscale mask like the A+ icon
-- symbol_autorename@2x.tga: a clock and a cargo box, i.e. cargo per time); the engine picks @2x for the plain path
local ICON <const> = "::/gui/line_vehicle_mgmt/icons/stat_load_speed.tga"
local LIVE_US <const> = 2000000
local CONTENT_W <const> = 740
local PAD_X <const> = 12
local GROUP_PAD <const> = 8
-- Widths (phase 3f): a StyleSheet `size` is the CONTENT size and padding comes on top (3e in game: stats cells of
-- 150+120+160+258 + 3 x 4 = 700 plus their 12 px padding each poked out of a 700 px panel, and the 700 px tables
-- ended short of a 716 + 16 px panel). So: content inner = CONTENT_W; a panel's size = CONTENT_W - its padding, so its
-- outer edge is the content's; tables and the stats row = the panel's inner width.
local GROUP_W <const> = CONTENT_W - 2 * GROUP_PAD
local TABLE_W <const> = GROUP_W
local STAT_GAP <const> = 4
local STAT_PAD_X <const> = 6
local STAT_SHARE <const> = { 150, 120, 160, 258 } -- Rate, Vehicles, Per vehicle, Running costs per year

--- Content widths of the stats cells: shares of TABLE_W minus the gaps and every cell's padding; the last cell takes
--- the rounding remainder, so the row ends exactly at the tables' right edge.
local function statWidths() : {integer}
	local avail = TABLE_W - (#STAT_SHARE - 1) * STAT_GAP - #STAT_SHARE * 2 * STAT_PAD_X
	local total = 0
	for __, w in ipairs(STAT_SHARE) do total = total + w end
	local out : {integer} = {}
	local used = 0
	for i, w in ipairs(STAT_SHARE) do
		if i < #STAT_SHARE then
			out[i] = math.floor(avail * w / total)
			used = used + out[i]
		else
			out[i] = avail - used
		end
	end
	return out
end
-- vertical padding of the target row's texts and buttons = the base TextInputField's (builtin.css.lua:1074-1090:
-- padding 2), so label, box, -/+ and "suggested" share one line height and baseline
local INPUT_PAD_Y <const> = 2
local MAX_COLS <const> = 8
local REFRESH_AFTER_US <const> = { 1000000, 3000000 }

local function say(msg : string)
	log.message(PREFIX .. msg)
end

local warned : {string : boolean} = {}
local function warnOnce(key : string, msg : any)
	if warned[key] then return end
	warned[key] = true
	log.warning(PREFIX .. key .. ": " .. tostring(msg) .. " (further failures not logged)")
end

local contextFn : function() : SquareRateMatcherContext = nil

function M.setContextFn(fn : function() : SquareRateMatcherContext)
	contextFn = fn
end

local function context() : SquareRateMatcherContext
	if contextFn == nil then return nil end
	local ok, c = pcall(contextFn)
	if ok then return c end
	warnOnce("context", c)
	return nil
end

local clock : Clock = nil
local function now() : integer
	if clock == nil then clock = api.type.Clock.new() end
	return clock:getTime()
end

-- Session ------------------------------------------------------------------------------------------------------

local record Pending
	kind : string
	result : SquareRateMatcherCommandResult
	modelName : string
end

local record ListSync
	add : {integer}
	remove : {integer}
end

local record Session
	line : integer
	title : string
	data : SquareRateMatcherLineData
	err : string
	supply : SquareRateMatcherSupplyView
	target : number
	targetText : string
	selectedModel : integer
	selectedCount : integer
	catalogue : {SquareRateMatcherModelInfo}
	catalogueWhy : string
	infoCache : {string : SquareRateMatcherModelInfo}
	priceCache : {integer : integer}
	message : string
	messageError : boolean
	busy : boolean
	pending : Pending
	listSync : ListSync
	refreshAt : {integer}
	liveAt : integer
	timingLogged : string
	tableEpoch : integer
	gen : integer
	mounted : boolean
end

local session : Session = nil
local liveState : ReactStateT<integer> = nil

local function activeIds(data : SquareRateMatcherLineData) : {integer}
	local out : {integer} = {}
	for __, v in ipairs(data ~= nil and data.vehicles or {}) do
		if not v.selling then out[#out + 1] = v.id end
	end
	return out
end

local function setTarget(s : Session, t : integer, text? : string)
	s.target = t
	s.targetText = text or tostring(t)
	s.selectedCount = nil
end

local function fullLoad(s : Session)
	local ctx = context()
	local data, err = engine.readLine(s.line, ctx ~= nil and ctx.protected or nil)
	s.data, s.err = data, err
	if data ~= nil then
		s.supply = view.supplyView(data)
		if s.target == nil then setTarget(s, view.defaultTarget(data, s.supply)) end
		-- the round-trip split for the other models' Rate estimate (rate_matcher_model.tl header); logged, as
		-- LineCargoInfo's section times are not used by the base GUI (units unverified)
		local timing, terr = engine.lineTiming(s.line, s.supply.cargo)
		data.timing = timing
		local tkey = timing ~= nil and (tostring(timing.section) .. "/" .. tostring(timing.drive)) or tostring(terr)
		if tkey ~= s.timingLogged then
			s.timingLogged = tkey
			say("timing line " .. tostring(s.line) .. (timing ~= nil and (" cargo " .. tostring(timing.cargo) .. ": "
				.. tostring(timing.sections) .. " sections, section times " .. tostring(timing.section)
				.. ", drive times " .. tostring(timing.drive) .. ", at stops " .. tostring(timing.loadShare)
				.. ", maxFrequency " .. tostring(timing.maxFrequency)) or (": " .. tostring(terr))))
		end
		local cat, why = engine.modelCatalogue(activeIds(data), s.supply.cargo,
			{ vehicleFilter = ctx ~= nil and ctx.vehicleFilter or nil })
		s.catalogue, s.catalogueWhy = cat, why
		s.priceCache = {}
	else
		if err ~= "not_a_line" then warnOnce("read", err) end
	end
	s.gen = s.gen + 1
end

local function sameVehicles(a : {SquareRateMatcherVehicle}, b : {SquareRateMatcherVehicle}) : boolean
	if #a ~= #b then return false end
	for i = 1, #a do
		if a[i].id ~= b[i].id or a[i].selling ~= b[i].selling or a[i].model ~= b[i].model then return false end
	end
	return true
end

-- Rate and vehicles only (cheap); the supply walk and the catalogue are re-read on open and after Apply.
local function liveRefresh(s : Session)
	if s.data == nil then return end
	local ctx = context()
	local rate = engine.lineRate(s.line)
	local vehicles = engine.lineVehicles(s.line, ctx ~= nil and ctx.protected or nil)
	if rate == nil or vehicles == nil then
		fullLoad(s) -- line gone: show it
		return
	end
	if math.abs(rate - (s.data.rate or 0)) > 0.01 or not sameVehicles(vehicles, s.data.vehicles) then
		s.data.rate, s.data.vehicles = rate, vehicles
		s.gen = s.gen + 1
	end
end

-- The Line Manager's vehicle list: add what Apply bought or replaced, drop what it sends to be sold (vanilla Clone's
-- onBuy, manager_window.tl:5108-5117). Only while the manager shows this line; adding twice is a no-op
-- (addVehiclesToVehicleListAndSelect checks, :5457-5480), so the 1 s / 3 s re-reads repeat it safely (a replaced
-- vehicle may have been dropped by the list's own revision check, :5430-5453).
local function syncList(s : Session)
	local ls = s.listSync
	if ls == nil then return end
	local ctx = context()
	if ctx == nil or ctx.line ~= s.line then return end
	if #ls.add > 0 and ctx.listAdd ~= nil then
		local ok, err : boolean, any = pcall(ctx.listAdd, ls.add)
		if not ok then warnOnce("list add", err) end
	end
	if #ls.remove > 0 and ctx.listRemove ~= nil then
		local ok, err : boolean, any = pcall(ctx.listRemove, ls.remove)
		if not ok then warnOnce("list remove", err) end
	end
end

local function listChanges(kind : string, r : SquareRateMatcherCommandResult) : ListSync
	local out : ListSync = { add = {}, remove = {} }
	if r == nil then return out end
	if kind == "clone" then
		for __, v in ipairs(r.done or {}) do out.add[#out.add + 1] = v end
	elseif kind == "sell" then
		for __, v in ipairs(r.done or {}) do out.remove[#out.remove + 1] = v end
	elseif kind == "switch" then
		for __, v in ipairs(r.replaced or {}) do out.add[#out.add + 1] = v end
		for __, v in ipairs(r.bought or {}) do out.add[#out.add + 1] = v end
		for __, v in ipairs(r.sold or {}) do out.remove[#out.remove + 1] = v end
	end
	return out
end

local function newSession(line : integer) : Session
	local title = ""
	local ok, name = pcall(api.engine.util.getEntityName, line)
	if ok and type(name) == "string" then title = name end
	if title == "" then title = _("Match line rate") end
	return {
		line = line,
		title = title,
		infoCache = {},
		priceCache = {},
		refreshAt = {},
		liveAt = 0,
		gen = 0,
	}
end

--- One step (react.onStep, Main Thread): command results, scheduled re-reads, the live refresh.
local function stepTick() : integer
	local s = session
	if s == nil then return -1 end
	local t = now()
	if s.pending ~= nil then
		local p = s.pending
		s.pending = nil
		s.busy = false
		s.message, s.messageError = view.resultText(p.kind, p.result, p.modelName)
		s.selectedModel, s.selectedCount = nil, nil
		say(p.kind .. " line " .. tostring(s.line) .. ": " .. tostring(p.result ~= nil and p.result.status or nil)
			.. " " .. tostring(p.result ~= nil and #p.result.done or 0) .. "/" .. tostring(p.result ~= nil and p.result.requested or 0))
		s.listSync = listChanges(p.kind, p.result)
		syncList(s)
		s.refreshAt = {}
		for __, dt in ipairs(REFRESH_AFTER_US) do s.refreshAt[#s.refreshAt + 1] = t + dt end
		s.gen = s.gen + 1
	end
	if #s.refreshAt > 0 and t >= s.refreshAt[1] then
		table.remove(s.refreshAt, 1)
		fullLoad(s)
		syncList(s)
		if #s.refreshAt == 0 then s.listSync = nil end
		s.liveAt = t + LIVE_US
	elseif t >= s.liveAt then
		s.liveAt = t + LIVE_US
		liveRefresh(s)
	end
	return s.gen
end

-- Inline styles (created once, in a render) ----------------------------------------------------------------------

local record Sheets
	content : StyleSheet
	dim : StyleSheet
	head : StyleSheet
	ok : StyleSheet
	err : StyleSheet
	hgap : StyleSheet
	input : StyleSheet
	table : StyleSheet
	gaps : {integer : StyleSheet}
	group : StyleSheet
	stats : {StyleSheet}

	compactButton : StyleSheet
	inputText : StyleSheet
	inputTextDim : StyleSheet
	inputTextPlain : StyleSheet
end

-- A base nine-patch (inline, as vehicle_react_util.tl:95-106 does); nil when the API is missing (offline tests).
local function ninePatch(file : string, h : {integer}) : NinePatch
	local ok, np = pcall(function() : NinePatch
		local n = api.gui.NinePatch.new()
		n.fileName = file
		n.horizontal = h
		n.vertical = h
		return n
	end)
	if ok then return np end
	return nil
end
local sheets : Sheets = nil

local function st() : Sheets
	if sheets == nil then
		local c = api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/default_colors.gres")).data as {string : {number}}
		local content = styleutil.makeStyle{ size = { CONTENT_W, -1 } }
		content.padding = api.type.Vec4f.new(8, PAD_X, 12, PAD_X) -- CSS order (top, right, bottom, left)
		local okT, tr = pcall(function() : {string : any}
			return api.gui.genericRep.get(api.gui.genericRep.find("::/gui/main/transparency.gres")).data as {string : any}
		end)
		local high = okT and tr ~= nil and type(tr.High) == "number" and tr.High as number or 0.25
		local function alpha(col : {number}, a : number) : {number}
			return { col[1], col[2], col[3], a }
		end
		-- Group panels as the Line Manager's sections (R::LineManager / R::VehicleManager / R::LinePanel,
		-- line_vehicle_mgmt.css.lua:169-187: card_surface + card_contour, BaseMedium, border BaseVeryLight)
		local group = styleutil.makeStyle{
			size = { GROUP_W, -1 },
			backgroundImage1 = ninePatch("::/gui/entity_window/design/card_surface.tga", { 0, 6, 26, 32 }),
			backgroundColor1 = c.BaseMedium,
			borderColor = c.BaseVeryLight,
		}
		local contour = ninePatch("::/gui/entity_window/design/card_contour.tga", { 0, 6, 26, 32 })
		if contour ~= nil then group.borderImage = contour end
		group.padding = api.type.Vec4f.new(GROUP_PAD, GROUP_PAD, GROUP_PAD, GROUP_PAD)
		-- Stats cells as the Line Manager's Capacity / Utilization / ... row (R::LineStatisticDetails !details,
		-- line_vehicle_mgmt.css.lua:1594-1606: compact_surface, BaseVeryLight at transparency High)
		-- cell widths (UI px, sum = TABLE_W - 3 gaps): the money cell gets the most room (phase 3e: "$182,880"
		-- overflowed an equal quarter); room for ~40 % longer de / ru / fr titles
		local stats : {StyleSheet} = {}
		for i, w in ipairs(statWidths()) do
			local sh = styleutil.makeStyle{
				size = { w, -1 },
				backgroundImage1 = ninePatch("::/gui/builtin/button/compact_surface.tga", { 0, 5, 7, 12 }),
				backgroundColor1 = alpha(c.BaseVeryLight, high),
			}
			sh.padding = api.type.Vec4f.new(2, STAT_PAD_X, 3, STAT_PAD_X)
			stats[i] = sh
		end

		local compactButton = styleutil.makeStyle{}
		compactButton.padding = api.type.Vec4f.new(INPUT_PAD_Y, 8, INPUT_PAD_Y, 8)
		local inputText = styleutil.makeStyle{ color = c.NeutralLightest }
		inputText.padding = api.type.Vec4f.new(INPUT_PAD_Y + 1, 0, INPUT_PAD_Y + 1, 0)
		local inputTextDim = styleutil.makeStyle{ color = c.NeutralLight }
		inputTextDim.padding = api.type.Vec4f.new(INPUT_PAD_Y + 1, 0, INPUT_PAD_Y + 1, 0)
		local inputTextPlain = styleutil.makeStyle{}
		inputTextPlain.padding = api.type.Vec4f.new(INPUT_PAD_Y + 1, 0, INPUT_PAD_Y + 1, 0)
		sheets = {
			group = group,
			stats = stats,

			compactButton = compactButton,
			inputText = inputText,
			inputTextDim = inputTextDim,
			inputTextPlain = inputTextPlain,
			content = content,
			dim = styleutil.makeStyle{ color = c.NeutralLight },
			head = styleutil.makeStyle{ color = c.NeutralLightest },
			-- green / red as Problem Radar's money classes (docs/findings.md: Positive reads as a link)
			ok = styleutil.makeStyle{ color = c.Ok },
			err = styleutil.makeStyle{ color = c.Negative },
			hgap = styleutil.makeStyle{ size = { 6, 1 } },
			input = styleutil.makeStyle{ size = { 90, -1 } },
			table = styleutil.makeStyle{ size = { TABLE_W, -1 } },
			gaps = {},
		}
	end
	return sheets
end

local function text(str : string, sheet? : StyleSheet, class? : string, tip? : string) : TreeNodeId
	return builtin.TextView{
		meta = { class = class or "font-scale-annotation", styleSheet = sheet, tooltip = tip },
		text = str or "",
	}
end

local function hbox(children : {TreeNodeId}) : TreeNodeId
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Horizontal, children = children }
end

local function vbox(children : {TreeNodeId}) : TreeNodeId
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end

-- Vertical spacing (UI px), one scale for the whole card: GAP_S inside a section (below a heading), GAP_M between
-- the summary and the target, GAP_L before a section heading and before the button row.
local GAP_S <const> = 6
local GAP_M <const> = 12
local GAP_L <const> = 20

local function vgap(h? : integer) : TreeNodeId
	local px = h or GAP_M
	local sh = st().gaps[px]
	if sh == nil then
		sh = styleutil.makeStyle{ size = { 1, px } }
		st().gaps[px] = sh
	end
	return builtin.Component{ meta = { styleSheet = sh } }
end

local function hgap() : TreeNodeId
	return builtin.Component{ meta = { styleSheet = st().hgap } }
end

--- Section heading: the same style for every section of the card.
local function head(str : string) : TreeNodeId
	return text(str, st().head, "font-scale-headline")
end

--- A sunken group panel (Line Manager section look, inline: no stylesheet rule) holding `children` stacked.
local function group(children : {TreeNodeId}) : TreeNodeId
	return builtin.Component{ meta = { styleSheet = st().group }, layout = vbox(children) }
end

--- The Line Manager's stats row: equal cells, a title above its value.
local function statsRow(cells : {SquareRateMatcherStatCell}) : TreeNodeId
	local children : {TreeNodeId} = {}
	for i, c in ipairs(cells) do
		if i > 1 then
			children[#children + 1] = builtin.Component{ meta = { styleSheet = styleutil.makeStyle{ size = { STAT_GAP, 1 } } } }
		end
		children[#children + 1] = builtin.Component{
			meta = { styleSheet = st().stats[i] or st().stats[1], tooltip = c.tip },
			layout = vbox({
				text(c.title, st().dim, "font-scale-body"),
				text(c.value, st().head, "font-scale-body"),
			}),
		}
	end
	return hbox(children)
end

--- A target-row text with the text box's vertical padding (one baseline with the box and the buttons).
local function inputLine(str : string, dim : boolean) : TreeNodeId
	return builtin.Component{
		meta = { styleSheet = dim and st().inputTextDim or st().inputText },
		layout = hbox({ builtin.TextView{ meta = { class = "font-scale-body" }, text = str or "" } }),
	}
end

-- Tables (see the header) ---------------------------------------------------------------------------------------

local record TableRow
	cells : {integer : string}  -- by column; column 1 is the select box
	tips : {integer : string}
	tag : {integer : boolean}  -- the cell's text in the base "positive" colour ("suggested", "best")
	selected : boolean
	select : function()
end

local record TableData
	rows : {integer : TableRow}
	right : {integer : boolean}
end

local record Column
	name : string
	tip : string
	weight : number
	right : boolean
end

local tableSerial = 0

local function selectRow(row : TableRow)
	if row == nil or row.selected or row.select == nil then return end
	local ok, err : boolean, any = pcall(row.select)
	if not ok then warnOnce("select", err) end
end

-- a left click anywhere on a row's cell selects the row (not consumed: the CheckBox still toggles)
local function rowClicks(row : TableRow)
	react.onMouseEvent(function(evt : Gui.Mouse.Event) : boolean
		if evt ~= nil and evt.button == 0 and evt.type == api.gui.mouse.Event.Type.Clicked then selectRow(row) end
		return false
	end)
end

local function rowOf(p : Builtin.TableCellParam) : TableRow, TableData
	local d = p ~= nil and p.userParam as TableData or nil
	if d == nil or d.rows == nil then return nil, nil end
	return d.rows[p.rowKey], d
end

local SelectCell = react.RegisterRecipe("SquareRateMatcherSelectCell", function(p : Builtin.TableCellParam) : TreeNodeId
	local row = rowOf(p)
	if row == nil then return hbox({}) end
	if row.selected then react.setStyleClasses("highlight") end
	rowClicks(row)
	return hbox({
		builtin.CheckBox{
			value = row.selected and 1 or 0,
			onValueChange = function(__ : integer) selectRow(row) end,
		},
	})
end)

-- one recipe per column index (a ColumnDesc takes a recipe; the cell gets rowKey, colKey and userParam)
local TEXT_CELLS : {integer : IRecipe} = {}
for col = 2, MAX_COLS do
	TEXT_CELLS[col] = react.RegisterRecipe("SquareRateMatcherCell" .. tostring(col), function(p : Builtin.TableCellParam) : TreeNodeId
		local row, d = rowOf(p)
		if row == nil then return hbox({}) end
		local right = d.right ~= nil and d.right[col] == true
		if right and row.selected then
			react.setStyleClasses("right-aligned", "highlight")
		elseif right then
			react.setStyleClasses("right-aligned")
		elseif row.selected then
			react.setStyleClasses("highlight")
		end
		rowClicks(row)
		local str = row.cells[col] or ""
		local tip = row.tips ~= nil and row.tips[col] or nil
		-- "suggested" / "best": the base class "positive" (default.css.lua:12-14, light blue), as the Line Manager's
		-- Balance value (line_react_util.tl:630-635)
		local tagged = row.tag ~= nil and row.tag[col] == true
		return hbox({
			builtin.TextView{
				meta = { class = tagged and "font-scale-body, positive" or "font-scale-body", tooltip = tip },
				text = str,
			},
		})
	end) as IRecipe
end

--- A builtin.DataTable over `rows` (in order). Fresh row keys on every call (see the header).
--- No sorting (user request, phase 3d): every column compares by display order, so an ascending header click keeps
--- the order; a descending one makes onSortColumnChange (builtin.d.tl:1174) recreate the table through a new
--- meta.localKey (the base forces regeneration the same way, statistics.tl:626), which starts unsorted again. The sort
--- caret is hidden by rate_matcher.css.lua. `name` keeps the two tables apart.
local function dataTable(s : Session, name : string, columns : {Column}, rows : {TableRow}) : TreeNodeId
	tableSerial = tableSerial + 1
	local keys : {integer} = {}
	local order : {integer : integer} = {}
	local d : TableData = { rows = {}, right = {} }
	for i, r in ipairs(rows) do
		local key = tableSerial * 64 + i
		keys[i] = key
		d.rows[key] = r
		order[key] = i
	end
	local descs : {TreeNodeId} = {}
	for i, c in ipairs(columns) do
		d.right[i] = c.right == true
		descs[i] = builtin.ColumnDesc{
			name = c.name,
			tooltip = c.tip,
			weight = c.weight,
			headerStyleClass = c.right and "right-aligned" or nil,
			recipe = i == 1 and SelectCell as IRecipe or TEXT_CELLS[i],
			getCompareValue = function(rowKey : integer) : any return order[rowKey] or 0 end,
		}
	end
	return hbox({
		builtin.DataTable{
			meta = { styleSheet = st().table, localKey = name .. "-" .. tostring(s.tableEpoch or 0) },
			onSortColumnChange = function(__ : integer, ascending : boolean)
				if ascending or session ~= s then return end
				s.tableEpoch = (s.tableEpoch or 0) + 1
				s.gen = s.gen + 1
			end,
			columns = descs,
			rowKeys = keys,
			userParam = d,
			disableSortKey = true,
			-- no scroll bars: a handful of rows, the table takes their height (phase 3e: the default vertical policy
			-- showed a bar in the top right corner)
			scrollPolicyHorizontal = builtin.type.ScrollBarPolicy.AlwaysOff,
			scrollPolicyVertical = builtin.type.ScrollBarPolicy.AlwaysOff,
		},
	})
end

--- A button with its gap inside (docs/findings.md FlowLayout: a wrapped row never starts with a bare spacer).
local function button(label : string, tip : string, onClick : function(), enabled : boolean, primary? : boolean, compact? : boolean) : TreeNodeId
	return hbox({
		builtin.Button{
			-- "primary" / "secondary": the base filled / outlined buttons (gui/main/default.css.lua:77-79, 104-107);
			-- compact: the text box's vertical padding, so it is as tall as the box (target row)
			-- a disabled primary button is unreadable (NeutralVeryDark text on NeutralDark, default.css.lua:91-100): disabled
			-- buttons use the outlined secondary style (only its border dims, :116-119), as the greyed undo / redo
			meta = { class = (primary and enabled) and "primary" or "secondary", tooltip = tip, enabled = enabled,
				styleSheet = compact and st().compactButton or nil },
			content = text(label, nil, compact and "font-scale-body" or nil),
			onClick = function()
				local ok, err : boolean, any = pcall(onClick)
				if not ok then
					warnOnce("click " .. label, err)
					if session ~= nil then
						session.message, session.messageError = _("Something went wrong (see the game log)."), true
						session.gen = session.gen + 1
					end
				end
			end,
		},
		hgap(),
	})
end

local function money(v : integer) : string
	local ok, s = pcall(api.util.formatMoney, v)
	if ok and type(s) == "string" then return s end
	return tostring(v)
end

local function cargoName(c : integer) : string
	local ok, n = pcall(function() : string
		local ct = api.res.cargoTypeRep.get(c)
		return ct ~= nil and ct.name or nil
	end)
	if ok then return n end
	return nil
end

-- Actions ------------------------------------------------------------------------------------------------------

local function apply(s : Session, v : SquareRateMatcherViewState)
	local p = v.selected
	if p == nil or s.busy then return end
	if not p.switch and p.delta == 0 then return end
	local ctx = context()
	s.busy = true
	s.message, s.messageError = _("Working..."), false
	s.gen = s.gen + 1
	local name = v.selectedModel ~= nil and v.selectedModel.name or nil
	if p.switch then
		say("apply: switch line " .. tostring(s.line) .. " to model " .. tostring(p.model) .. ": replace "
			.. tostring(#p.replace) .. ", buy " .. tostring(p.buy) .. ", sell " .. tostring(#p.remove))
		commands.switchModel(p, s.line, v.templateVehicle, function(r : SquareRateMatcherCommandResult)
			s.pending = { kind = "switch", result = r, modelName = name } -- plain table write: the next step shows it
		end, ctx ~= nil and ctx.protected or nil)
	elseif p.delta > 0 then
		say("apply: clone " .. tostring(p.delta) .. " of vehicle " .. tostring(v.templateVehicle) .. " onto line " .. tostring(s.line))
		commands.cloneOntoLine(v.templateVehicle, s.line, p.delta, function(r : SquareRateMatcherCommandResult)
			s.pending = { kind = "clone", result = r }
		end)
	else
		say("apply: sell " .. tostring(#(p.remove or {})) .. " vehicles of line " .. tostring(s.line))
		commands.sellVehicles(p.remove, function(r : SquareRateMatcherCommandResult)
			s.pending = { kind = "sell", result = r }
		end, ctx ~= nil and ctx.protected or nil)
	end
end

local function openReplace(s : Session)
	local ids = activeIds(s.data)
	local ok, why = commands.replaceViaWindow(ids, function()
		-- the Replace window closed (accepted or cancelled): read the line again
		s.refreshAt = {}
		local t = now()
		for __, dt in ipairs(REFRESH_AFTER_US) do s.refreshAt[#s.refreshAt + 1] = t + dt end
	end)
	if ok then
		s.message, s.messageError = nil, false
	elseif why == "fallback_manager" then
		s.message, s.messageError = _("The Replace window could not be opened; the vehicle manager shows the line's vehicles instead."), true
	else
		s.message, s.messageError = _("The Replace window could not be opened."), true
	end
	s.gen = s.gen + 1
end

-- Sections -----------------------------------------------------------------------------------------------------

local function modelInfoFor(s : Session, modelId : integer, cargo : integer) : SquareRateMatcherModelInfo
	for __, m in ipairs(s.catalogue or {}) do
		if m.model == modelId then return m end
	end
	local key = tostring(modelId) .. ":" .. tostring(cargo)
	local info = s.infoCache[key]
	if info == nil then
		info = engine.modelInfo(modelId, cargo)
		s.infoCache[key] = info
	end
	return info
end

local function priceFor(s : Session, template : integer) : integer
	if template == nil then return nil end
	local p = s.priceCache[template]
	if p == nil then
		p = commands.clonePrice(template) or -1
		s.priceCache[template] = p
	end
	if p < 0 then return nil end
	return p
end

local function tips() : {string : string}
	return {
		buy = _("Price of the new vehicles\nminus what the vehicles leaving the line sell for."),
		cost = _("Yearly cost of the fleet after the change:\nrunning costs plus each vehicle's purchase price\nspread over its lifespan."),
		per = _("Yearly cost divided by the rate:\nwhat carrying one unit costs.\nLower is more cost-effective."),
		rate = _("Estimated Rate per year after the change."),
	}
end

local function selectedName(v : SquareRateMatcherViewState) : string
	return v.selectedModel ~= nil and (v.selectedModel.name or "?") or "?"
end

-- Both tables: the same 8 columns, weights and width, so Vehicles .. Per rate sit at the same x in both (phase 3d).
-- Column 2 is the model name (comparison) or the change "+1" (plans), both left-aligned.
local function tableColumns(second : string) : {Column}
	local t = tips()
	return {
		-- weights = UI px of TABLE_W (724); the note column fits "suggested" with room for longer translations
		-- ("vorgeschlagen", 3e cut "suggested" to "suggestec" at 80)
		{ name = " ", weight = 28 },
		{ name = second, weight = 140 },
		{ name = _("Vehicles"), weight = 80, right = true },
		{ name = _("≈ Rate"), tip = t.rate, weight = 64, right = true },
		{ name = _("Price"), tip = t.buy, weight = 92, right = true },
		{ name = _("Cost/yr"), tip = t.cost, weight = 92, right = true },
		{ name = _("Cost per unit"), tip = t.per, weight = 110, right = true },
		{ name = " ", weight = 118 },
	}
end

local function costCells(row : TableRow, first : integer, p : SquareRateMatcherPlan)
	local cells = view.planCells(p, money)
	row.cells[first], row.cells[first + 1], row.cells[first + 2], row.cells[first + 3] = cells[3], cells[4], cells[5], cells[6]
	row.tips[first + 2] = view.costTip(p, money)
end

local function plansSection(s : Session, v : SquareRateMatcherViewState) : {TreeNodeId}
	local out : {TreeNodeId} = {}
	local status = view.statusText(v)
	if v.status ~= "ok" then
		out[#out + 1] = text(status, st().dim)
		return out
	end
	-- the selected model's name as the section heading, then its count rows
	out[#out + 1] = head(view.modelName(v.selectedModel))
	out[#out + 1] = vgap(GAP_S)
	local columns = tableColumns(_("Change"))
	local rows : {TableRow} = {}
	for __, p in ipairs(v.plans) do
		local cells = view.planCells(p, money)
		local row : TableRow = {
			cells = { [2] = cells[2], [3] = cells[1], [8] = p.suggested and _("suggested") or "" },
			tips = {},
			tag = { [8] = true },
			selected = v.selected ~= nil and p.count == v.selected.count,
			select = function()
				if session == s then
					s.selectedCount = p.count
					s.gen = s.gen + 1
				end
			end,
		}
		costCells(row, 4, p)
		rows[#rows + 1] = row
	end
	out[#out + 1] = dataTable(s, "plans", columns, rows)
	if status ~= nil then out[#out + 1] = text(status, st().dim) end
	return out
end

local function modelsSection(s : Session, v : SquareRateMatcherViewState) : {TreeNodeId}
	if v.status ~= "ok" or #v.models == 0 then return {} end
	local out : {TreeNodeId} = { head(_("Compare models (estimate)")), vgap(GAP_S) }
	local columns = tableColumns(_("Model"))
	local rows : {TableRow} = {}
	for __, mrow in ipairs(v.models) do
		local p = mrow.plan
		local row : TableRow = {
			cells = { [2] = view.modelName(mrow), [8] = mrow.best and _("best") or "" },
			tips = { [8] = mrow.best and _("The lowest cost per unit\nin this comparison.") or nil },
			tag = { [8] = true },
			selected = v.selectedModel == mrow,
			select = function()
				if session == s then
					s.selectedModel = mrow.model
					s.selectedCount = nil
					s.gen = s.gen + 1
				end
			end,
		}
		if p ~= nil then
			row.cells[3] = tostring(p.count)
			costCells(row, 4, p)
		end
		rows[#rows + 1] = row
	end
	out[#out + 1] = dataTable(s, "models", columns, rows)
	if v.modelsWhy ~= nil then out[#out + 1] = text(view.modelsHint(v.modelsWhy), st().dim) end
	return out
end

local function targetRow(s : Session) : TreeNodeId
	local function commit(t : integer, textValue? : string)
		if t ~= nil and session == s and (t ~= s.target or textValue ~= s.targetText) then
			setTarget(s, t, textValue)
			s.gen = s.gen + 1
		end
	end
	local children : {TreeNodeId} = {
		inputLine(_("Target per year"), false),
		hgap(),
		builtin.TextInputField{
			meta = { class = "font-scale-body, no-clear-button", styleSheet = st().input },
			value = s.targetText or "",
			-- digits only (as gui_react_util.FocusNumberInputField's filter, gui_react_util.tl:388-390)
			filter = function(str : string) : boolean
				return str:match("^[0-9]*$") ~= nil
			end,
			-- every keystroke: the plans follow at once (the field keeps the typed text)
			onTyping = function(str : string)
				local ok, err : boolean, any = pcall(function()
					if session ~= s then return end
					local t = view.parseTarget(str)
					if t ~= nil then
						commit(t, str)
					elseif str ~= s.targetText then
						s.targetText = str
					end
				end)
				if not ok then warnOnce("target typing", err) end
			end,
			-- Enter or focus loss: tidy the text (an empty box goes back to the current target)
			onValueChange = function(str : string)
				local ok, err : boolean, any = pcall(function()
					if session ~= s then return end
					local t = view.parseTarget(str) or view.clampTarget(s.target)
					if t ~= nil then commit(t, tostring(t)) end
				end)
				if not ok then warnOnce("target", err) end
			end,
			acceptOnFocusLoss = true,
			virtualKeyboardTitle = _("Target per year"),
			virtualKeyboardDescription = _("The Rate the line should reach, per year."),
		},
		hgap(),
		button("-", _("1 less"), function() commit(view.clampTarget((s.target or 0) - 1)) end, (s.target or 0) > 0, false, true),
		button("+", _("1 more"), function() commit(view.clampTarget((s.target or 0) + 1)) end, true, false, true),
	}
	local suggested = s.supply ~= nil and s.supply.suggested or nil
	if suggested ~= nil then
		if s.target == suggested then
			-- the same blue as in the tables, on the text box's baseline
			children[#children + 1] = builtin.Component{
				meta = { styleSheet = st().inputTextPlain },
				layout = hbox({ builtin.TextView{ meta = { class = "font-scale-body, positive" }, text = _("suggested") } }),
			}
		else
			children[#children + 1] = button(view.fill(_("Suggested: {target}"), { target = view.fmt(suggested) }),
				_("Back to the target from the supply in reach."), function() commit(suggested) end, true, false, true)
		end
	end
	return builtin.FlowLayout{ children = children }
end

local function renderSession(s : Session) : TreeNodeId
	local children : {TreeNodeId} = {}
	local data = s.data
	if data == nil then
		children[#children + 1] = text(s.err == "not_a_line" and _("This line no longer exists.")
			or _("Could not read the line (see the game log)."), st().err)
		children[#children + 1] = vgap(GAP_M)
		children[#children + 1] = builtin.FlowLayout{ children = { button(_("Close"), nil, M.close, true) } }
		return vbox(children)
	end
	local input : SquareRateMatcherBuildInput = {
		selectedModel = s.selectedModel,
		selectedCount = s.selectedCount,
		catalogue = s.catalogue,
		catalogueWhy = s.catalogueWhy,
		infoOf = function(m : integer) : SquareRateMatcherModelInfo return modelInfoFor(s, m, s.supply ~= nil and s.supply.cargo or nil) end,
	}
	local v = view.build(data, s.supply, s.target, input)
	if v.status == "ok" and v.templateVehicle ~= nil then
		input.clonePrice = priceFor(s, v.templateVehicle)
		v = view.build(data, s.supply, s.target, input)
	end

	-- group 1: the line now (stats row as the Line Manager's), supply, target
	local top : {TreeNodeId} = { statsRow(view.statsCells(v, data, money)), vgap(GAP_S) }
	for __, line in ipairs(view.supplyLines(s.supply, cargoName)) do
		top[#top + 1] = text(line, st().dim)
	end
	top[#top + 1] = vgap(GAP_M)
	top[#top + 1] = targetRow(s)
	children[#children + 1] = group(top)

	-- group 2: the selected model's options; group 3: the comparison
	local plans = plansSection(s, v)
	if #plans > 0 then
		children[#children + 1] = vgap(GAP_M)
		children[#children + 1] = group(plans)
	end
	local models = modelsSection(s, v)
	if #models > 0 then
		children[#children + 1] = vgap(GAP_M)
		children[#children + 1] = group(models)
	end

	-- message, what Apply does, buttons
	children[#children + 1] = vgap(GAP_L)
	if s.message ~= nil then
		children[#children + 1] = text(s.message, s.messageError and st().err or st().ok)
	end
	local p = v.selected
	local canApply = not s.busy and v.status == "ok" and p ~= nil and (p.switch or p.delta ~= 0)
	local action = view.planActionText(canApply and p or nil, selectedName(v))
	if canApply then children[#children + 1] = text(action, st().dim) end
	children[#children + 1] = vgap(GAP_S)
	-- no tooltip on Apply: the line above says what it does
	local buttons : {TreeNodeId} = { button(_("Apply"), nil, function() apply(s, v) end, canApply, true) }
	if #activeIds(data) > 0 then
		buttons[#buttons + 1] = button(_("Replace window"), _("Opens the game's Replace window\nfor this line's vehicles."),
			function() openReplace(s) end, not s.busy)
	end
	buttons[#buttons + 1] = button(_("Close"), nil, M.close, true)
	children[#children + 1] = builtin.FlowLayout{ children = buttons }
	return vbox(children)
end

local record ContentParam
	meta : Meta
end

local RateMatcherContent = react.RegisterRecipe("SquareRateMatcherContent", function(__ : ContentParam) : TreeNodeId
	local state = engine_react_util.useStepState(function() : integer
		local ok, g = pcall(stepTick)
		if ok then return g end
		warnOnce("step", g)
		return -2
	end, nil, function(a : integer, b : integer) : boolean return a == b end)
	liveState = state
	local s = session
	if s ~= nil then s.mounted = true end
	local ok, root = pcall(function() : TreeNodeId
		if s == nil then return vbox({ text(_("No line selected.")) }) end
		return renderSession(s)
	end)
	if ok and root ~= nil then return root end
	warnOnce("render", root)
	-- a recipe returns a layout (memory: react-recipe-must-return-layout)
	return vbox({ text(_("Something went wrong (see the game log)."), st().err) })
end)

local record WindowParam
	title : string
	onClose : function()
end

local RateMatcherWindow = react.RegisterWrapperRecipe("SquareRateMatcherWindow", builtin.Window, function(p : WindowParam) : TreeNodeId
	-- WindowParam: builtin.d.tl:1186-1210; same pattern as Problem Radar's fleet window (radar_fleet.tl)
	return builtin.Window{
		id = WINDOW_ID,
		title = p.title,
		closable = true,
		movable = true,
		onClose = p.onClose,
		content = RateMatcherContent{ meta = { styleSheet = st().content } },
	}
end)

-- Open / close -------------------------------------------------------------------------------------------------

local function windowAlive() : boolean
	if session == nil then return false end
	if not session.mounted then return true end
	return liveState ~= nil and not liveState:hasExpired()
end

function M.isOpenFor(line : integer) : boolean
	return session ~= nil and session.line == line and windowAlive()
end

function M.close()
	session, liveState = nil, nil
	local wa = game_react_globals.getDefaultWindowApi()
	if wa ~= nil then wa.removeAllWindows(RateMatcherWindow) end
end

function M.open(line : integer)
	local wa = game_react_globals.getDefaultWindowApi()
	if wa == nil then
		warnOnce("window", "no window container; cannot open the window")
		return
	end
	if M.isOpenFor(line) then
		session.refreshAt = { now() }
		wa.moveSingletonWindowToFront(RateMatcherWindow)
		return
	end
	if session ~= nil then wa.removeAllWindows(RateMatcherWindow) end
	liveState = nil
	local s = newSession(line)
	session = s
	fullLoad(s)
	s.liveAt = now() + LIVE_US
	say("open line " .. tostring(line) .. ": rate " .. tostring(s.data ~= nil and s.data.rate or nil)
		.. ", supply " .. tostring(s.supply ~= nil and s.supply.kind or s.err) .. ", target " .. tostring(s.target))
	-- every price candidate, to compare with the vehicle store (rate_matcher_commands.tl header "price check")
	local first = activeIds(s.data)[1]
	if first ~= nil and commands.priceReport ~= nil then say("price " .. commands.priceReport(first)) end
	-- onClose belongs to this session: a late close of a replaced window must not close the new one
	wa.addSingletonWindow(RateMatcherWindow, { title = s.title, onClose = function()
		if session == s then M.close() end
	end })
	wa.moveSingletonWindowToFront(RateMatcherWindow)
end

-- Toolbar button -----------------------------------------------------------------------------------------------

local record ButtonView
	line : integer
	open : boolean
end

local HIDDEN : ButtonView = { line = nil, open = false }

local function buttonView() : ButtonView
	local ctx = context()
	if ctx == nil or ctx.line == nil then return HIDDEN end
	return { line = ctx.line, open = M.isOpenFor(ctx.line) }
end

M.ToolbarButton = react.RegisterRecipe("SquareRateMatcherButton", function(__ : SquareRateMatcherButtonParam) : TreeNodeId
	local state = engine_react_util.useStepState(function() : ButtonView
		local ok, bv = pcall(buttonView)
		if ok then return bv end
		warnOnce("button view", bv)
		return HIDDEN
	end, nil, function(a : ButtonView, b : ButtonView) : boolean
		return a.line == b.line and a.open == b.open
	end)
	local bv = state:old() or HIDDEN
	if bv.line == nil then
		-- hidden (no single line, e.g. several lines selected): an empty layout (memory: react-recipe-must-return-layout)
		return hbox({})
	end
	local line = bv.line
	return hbox({
		-- the A+ button's own shape and class (button_react_util.makeIconToggleButton, manager_window.tl:3520-3521):
		-- a ToggleButton with an AutoFit ImageView, checked while the window shows this line. No stylesheet rule
		-- needed: it is the same widget as A+. No mouseTransparent on ImageView (crashes).
		builtin.ToggleButton{
			meta = { class = "vehicle-button, secondary", tooltip = _("Match line rate") },
			content = builtin.ImageView{
				path = ICON,
				scaling = builtin.type.ImageViewScaling.AutoFit,
			},
			value = bv.open and 1 or 0,
			onValueChange = function(val : integer)
				local ok, err : boolean, any = pcall(function()
					if val == 1 then
						if not M.isOpenFor(line) then M.open(line) end
					elseif M.isOpenFor(line) then
						M.close()
					end
				end)
				if not ok then warnOnce("button", err) end
			end,
		},
	})
end)

return M
