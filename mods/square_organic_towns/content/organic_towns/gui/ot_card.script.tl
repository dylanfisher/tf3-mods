-- Organic Towns: the "Organic Towns" card in the town window (2026-10-17, rev 3; registered by ot_card.res.lua on
-- ::TownEowExtensionPoint, order 45). GUI thread. It writes one thing (2026-10-21): the player's street style pick for
-- the town's new streets (the Character section's "Streets" row, a dropdown on towns the mod manages, ot_card.stylePick).
-- The pick goes to the game script as an event (styleSent: api.cmd.makeScriptingSendEventCmd(ot_saved.EVENT_ID,
-- EV_STYLE, { town, ps }), the ids mirrored in ot_card) from the dropdown's onValueChange, a GUI-thread handler, as square_problem_radar's
-- radar_hud.script.tl sendEvent and square_supply_gaps' sg_saved.sendOn); the game script's handleEvent applies it
-- (ot_saved.applyStyle: idempotent, only on a framed town) and the driver's next growth step for the town resolves the
-- picked style (ot_style.resolve). One "[SQOT] STYLE event=pick" line per change. Until the poll reads the pick back the
-- dropdown keeps it (pending, at most PENDING_S). Everything else here is read-only.
--
-- The base card look (content_card.ContentCard, as town_eow.script.tl TownLevelPlugin / TownChartsPlugin): a title, a
-- one-line summary as the permanent part and the five sections as the collapsible part (collapsed by default; the
-- window keeps one card expanded at a time). Base pieces only and no stylesheet rule of ours; inline style only
-- for the two looks no base class gives (native-UI passes 2026-10-17, plans/square_organic_towns/TESTING.md "Rev 3"):
--   * the permanent part is a key / value row, the base Line "Transported" card's (line_eow.script.tl:80-97: body
--     TextView, the base horizontal spacer, value): the character left, the phase right. ContentCard draws
--     its collapse triangle at a fixed x near the right, straddling the permanent part's bottom border
--     (content_card.tl:318-337, content_card.css.lua:139-143 `arrow-component` margin 358); the base cards keep a
--     right-aligned value above it (Town Level: the growth state, entity_window.css.lua:601; Transported: the value);
--   * key / value rows as that row; descriptions visibly under their row in the base annotation font (font-scale-
--     annotation, as the base secondary lines: industry_react_util.tl:589-600, warehouse_eow.script.tl:120) and as
--     the row's tooltip;
--   * bars: a thin builtin.ProgressBar (class font-scale-annotation, as the Town Level bar town_eow.script.tl:88-96)
--     with the aim as the base threshold mark (`thresholds`, builtin.css.lua:1600-1606: a 1 px line, lighter where
--     the fill hasn't reached it, darker where it has, so it reads whether the aim is above or below the fill). The
--     base's thin bars are styled only under their own recipes (R::TownLevelWidget 8 px, entity_window.css.lua:582;
--     R::PersonCapacityWidget 10 px, :846) and entity_window_util.ProgressDisplay is 25 px tall (:1022-1025, the
--     thick bar of the first pass), so the bar carries an INLINE sheet (barSheet): the Town Level bar's colors
--     (BaseVeryLight at VeryLow behind) at the PersonCapacityWidget's 10 px, whose height the builtin mask's 5 px
--     corners fit (an inline sheet has no `mask`, which the 8 px bar needs). Fill: the District Sizes chart's
--     district colors (town_eow.script.tl:223-225), TownGrowth for the phase bar. The numbers in the row above;
--   * gaps: the base layouts' 2 px leave rows and bars nearly touching and spacing between children takes a rule
--     (docs/ui-guide.md "Spacing"), so fixed gaps are INLINE spacers (gapSheet: a Component of size { 1, h }, the
--     ui-guide's fixed-gap spacer), sized by ot_card.gapBefore (6 between groups, 3 inside one, 4 under a headline
--     and around a separator);
--   * the street style: the base builtin.ComboBox (as the base mod settings, script_param_util.tl:484-512: items
--     builtin.ComboBoxItem{ value, content = TextView with the item's tooltip }, values as strings), in the row's value
--     place; docs/ui-guide.md "Controls" (one of many). A builtin, so no base helper the PS5 build may lack;
--   * explanations and empty states: content_card.makeInfoHint (content_card.tl:479; industry_eow.script.tl:357);
--   * sections: a font-scale-headline TextView, the base `card-children-separator` line between them
--     (content_card.css.lua:59, any Component inside the card's InfoCalloutWrapper);
--   * town links: a plain Button with the town icon and the name firing "selectEntity" (sim_person_eow.script.tl:
--     115-131, entity_window_util.tl:1930-1944), styled by "R::EntityWindowContent Button" (entity_window.css.lua:74).
-- Every TextView in a card wraps at the card width by the base rule "R::EntityWindowContent R::ContentCard TextView"
-- (entity_window.css.lua:1133: textAutoWrap, InnerCardWidth 400), so long translations wrap.
--
-- Data (plain values, polled by engine_react_util.useStepStateTimer every POLL_S; read() below):
--   * the saved game-script state through state_native (findPath / find on a few keys, never the whole `state` copy):
--     the town's frame, weighting (`rc`), summary (`ui`), name origin (`no`), the offshoot lists (`dk`, `wm`) and the
--     new-map flag; GUI and game script are separate Lua states, so this is the only way to the driver's data
--     (docs/findings/towns.md; pattern mods/square_problem_radar/content/radar/gui/radar_hud.script.tl readFields);
--   * the town's TOWN component (initial capacities, size factors), its built capacities and, until its first written
--     weighting step, its live supply (the base town_util reads, as ot_engine.townSupply);
--   * the mod settings (ot_params.parse) and the names of the family's towns.
-- ot_card.view turns it into the display model (all texts and rules there, tested offline). Nothing shows in the map
-- editor (the res condition) or for a town without any Organic Towns data. One "[SQOT] CARD event=read" log line the
-- first time a town's card finds data in a session.

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local content_card = ug_require "::/gui/main/content_card.tl" as ContentCard
local engine_react_util = ug_require "::/gui/main/engine_react_util.tl" as EngineReactUtil
local styleutil = ug_require "::/gui/main/styleutil.tl" as StyleUtil
local color_util = ug_require "::/gui/main/color_util.tl" as ColorUtil
local town_eow = ug_require "::/gui/entity_window/town/town_eow.script.tl" as TownEow

local GS_NAME <const> = "square_organic_towns::/organic_towns/organic_towns.gs"
local MOD_ID <const> = "square_organic_towns"
local POLL_S <const> = 2.0
local MAX_OFFS <const> = 64
local MAX_LOGGED <const> = 200

local record OtCardTown
	id : integer
	name : string
end

local record OtCardOption
	value : string
	text : string
	tip : string
end

local record OtCardLine
	kind : string            -- "row" | "bar" | "text" | "note" | "hint" | "towns" | "style"
	text : string
	key : string
	value : any              -- row: the value text; bar: 0..1
	mark : number            -- bar: the aim (0..1) or nil
	color : string           -- bar: "res" | "com" | "ind" | "growth"
	tip : string
	towns : {OtCardTown}
	options : {OtCardOption}  -- style: the dropdown's options ("0" = Automatic, "1".. = ot_card.STYLE_IDS)
	selected : string         -- style: the selected option's value
	town : integer            -- style: the town
	from : string             -- style: the style in effect (an id) or nil
end

local record OtCardSection
	title : string
	lines : {OtCardLine}
end

local record OtCardView
	hidden : boolean
	summary : string
	summaryValue : string
	sections : {OtCardSection}
end

local record OtCardInput
	town : integer
	mapEditor : boolean
	fresh : boolean
	rciOn : boolean
	rciWeight : number       -- the "Delivery weighting" factor (ot_params deliveryWeight)
	satellitesOn : boolean
	frame : {string : any}
	rc : {string : any}
	ui : string
	origin : string
	offs : {{string : any}}
	names : {integer : string}
	init : {number}
	sf : {number}
	uses : {number}
	supply : {string : any}
	stylePick : boolean      -- the player may pick the street style (the mod acts on towns)
	forcedStyle : string     -- the "Town style" setting's forced style ("NA_GRID") or nil
	pendingStyle : integer   -- a pick sent and not read back yet (0 = Automatic) or nil
end

local record OtCardModule
	GAP_HEAD : integer
	STYLE_IDS : {string}
	EVENT_ID : string
	EV_STYLE : string
	view : function(input : OtCardInput) : OtCardView
	gapBefore : function(prev : string, kind : string) : integer
	logText : function(input : OtCardInput) : string
	hasData : function(input : OtCardInput) : boolean
end

local record OtParams
	actOn : string
	forceGrid : boolean
	townGrowth : string
	deliveryWeight : number
	satelliteTowns : string
	mapEditor : boolean
end

local record OtParamsModule
	MOD_ID : string
	parse : function(mine : any, all : any) : OtParams
end

local card = ug_require "square_organic_towns::/organic_towns/ot_card.lua" as OtCardModule
local params_mod = ug_require "square_organic_towns::/organic_towns/ot_params.lua" as OtParamsModule

-- the street style picks sent and not read back yet: { [town] = { ps, at = os.time() } } (cleared when the frame shows
-- the pick, or after PENDING_S: a pick that never arrives, e.g. the game script missing, shows the saved value again)
local record PendingPick
	ps : integer
	at : number
end
local pending : {integer : PendingPick} = {}
local PENDING_S <const> = 10
local MAX_PENDING <const> = 64

local logged : {integer : boolean} = {}
local nLogged = 0

---------------------------------------------------------------------------
-- reads (useStepStateTimer callback; every read pcall-guarded, a save without our script gives an empty input)

local function nativeOf() : NativeLuaTable
	local entity = api.engine.system.gameScriptSystem.getEntityForGameScript(GS_NAME)
	if entity == nil or entity < 0 then return nil end
	local gs = api.engine.getComponent(entity, api.type.ComponentType.GAME_SCRIPT) as Engine.Component.GameScript<any>
	if gs == nil then return nil end
	return gs.state_native
end

local function asPlain(v : NativeLuaValue) : any
	if v == nil then return nil end
	local tv = type(v)
	if tv == "string" or tv == "number" or tv == "boolean" then return v end
	return (v as NativeLuaTable):asTable()
end

local function townName(e : integer) : string
	local ok, name = pcall(function() : string
		if not api.engine.entityExists(e) then return nil end
		local c = api.engine.getComponent(e, api.type.ComponentType.NAME) as Engine.Component.Name
		return c and c.name or nil
	end)
	return ok and name or nil
end

local function addOffs(out : {{string : any}}, list : any, kind : string)
	if type(list) ~= "table" then return end
	local l = list as {{string : any}}
	for i = 1, math.min(#l, MAX_OFFS) do
		local e = l[i]
		if type(e) == "table" and #out < 2 * MAX_OFFS then
			out[#out + 1] = { t = e.t, p = e.p, kind = kind }
		end
	end
end

local function readSupply(t : integer) : {string : any}
	local ok, sd = pcall(function() : {string : any}
		local town_util = ug_require "::/game_mechanics/towns/town_util.tl" as TownUtil
		local all = town_util.getCargoSupplyDemands(t)
		if all == nil then return nil end
		local function sum(list : {CargoTypeSupplyDemand}) : {number}
			local s, d = 0.0, 0.0
			for i, c in ipairs(list or {}) do
				if i > 64 then break end
				s = s + (c.supply or 0)
				d = d + (c.demand or 0)
			end
			return { s, d }
		end
		return { line = api.engine.util.town.getTownLineUsage(t), mult = town_util.LineUsageRatingMultiplier or 2,
			res = sum(all.residential), com = sum(all.commercial), ind = sum(all.industrial) }
	end)
	return ok and sd or nil
end

-- the mod settings, read once on the GUI thread (they can't change while a game runs)
local opts : OtParams = nil

local function settings() : OtParams
	if opts ~= nil then return opts end
	local ok, o = pcall(function() : OtParams
		local all = api.engine.config.getModParams() as {string : any}
		return params_mod.parse(all and all[params_mod.MOD_ID or MOD_ID], all)
	end)
	opts = (ok and o) or { actOn = "new", townGrowth = "deliveries", satelliteTowns = "on", mapEditor = false,
		forceGrid = false }
	return opts
end

local function read(t : integer, o : OtParams) : OtCardInput
	local input : OtCardInput = { town = t, names = {}, offs = {} }
	input.mapEditor = o.mapEditor == true
	input.rciOn = o.townGrowth == "deliveries" and o.actOn ~= "off"
	input.rciWeight = o.deliveryWeight
	input.satellitesOn = o.satelliteTowns ~= "off"
	input.stylePick = o.actOn ~= "off" and not input.mapEditor
	input.forcedStyle = o.forceGrid == true and "NA_GRID" or nil
	pcall(function()
		local native = nativeOf()
		if native == nil then return end
		local key = tostring(t)
		input.frame = asPlain(native:findPath({ "frames", key })) as {string : any}
		input.rc = asPlain(native:findPath({ "rc", key })) as {string : any}
		local ui = asPlain(native:findPath({ "ui", key }))
		input.ui = type(ui) == "string" and ui as string or nil
		local no = asPlain(native:findPath({ "no", key }))
		input.origin = type(no) == "string" and no as string or nil
		input.fresh = asPlain(native:find("fresh")) == true
		addOffs(input.offs, asPlain(native:find("dk")), "district")
		addOffs(input.offs, asPlain(native:find("wm")), "works")
	end)
	for _i, e in ipairs(input.offs) do
		local a, b = tonumber(e.t), tonumber(e.p)
		if a == t and b and b >= 0 then input.names[math.floor(b)] = townName(math.floor(b)) end
		if b == t and a then input.names[math.floor(a)] = townName(math.floor(a)) end
	end
	pcall(function()
		local tc = api.engine.getComponent(t, api.type.ComponentType.TOWN) as Engine.Component.Town
		if tc == nil then return end
		input.init = { tc.initialLandUseCapacities[1], tc.initialLandUseCapacities[2], tc.initialLandUseCapacities[3] }
		input.sf = { tc.sizeFactors[1], tc.sizeFactors[2], tc.sizeFactors[3] }
		local c = api.engine.system.townBuildingSystem.getLandUsePersonCapacities(t)
		input.uses = { c[1] or 0, c[2] or 0, c[3] or 0 }
	end)
	if input.rciOn and input.rc == nil then input.supply = readSupply(t) end
	local pp = pending[t]
	if pp ~= nil then
		local fps = input.frame and tonumber(input.frame.ps) or 0
		if math.floor(fps) == pp.ps or os.time() - pp.at > PENDING_S then
			pending[t] = nil
		else
			input.pendingStyle = pp.ps
		end
	end
	return input
end

---------------------------------------------------------------------------
-- widgets

local TOWN_ICON <const> = "::/gui/entity_window/icons/building_town.tga" -- the base "Home" destination icon

local function openTown(id : integer)
	if not api.engine.entityExists(id) then return end
	react.fireEvent(nil, "selectEntity", { entity = id, stack = true })
end

-- INLINE STYLES (see the header: no base class gives a thin bar or a fixed gap here). Built once, lazily, in a render
-- (GUI thread), reused; never read back. A failed read leaves the bar on the builtin look and drops the gaps.
local barSheets : {string : StyleSheet} = nil
local gapSheets : {integer : StyleSheet} = {}
local BAR_H <const> = 10

local function barSheet(color : string) : StyleSheet
	if barSheets == nil then
		barSheets = {}
		pcall(function()
			local function gres(path : string) : {string : any}
				return api.gui.genericRep.get(api.gui.genericRep.find(path)).data as {string : any}
			end
			local c = gres("::/gui/main/default_colors.gres") as {string : {number}}
			local tr = gres("::/gui/main/transparency.gres") as {string : number}
			local d = gres("::/game_mechanics/towns/district_colors.gres") as {string : {string : {number}}}
			local g = gres("::/gui/entity_window/gameplay_colors.gres") as {string : {number}}
			-- the Town Level bar's background (entity_window.css.lua:585)
			local back = color_util.withTransparencyRaw(c.BaseVeryLight as GResColor, tr.VeryLow) as {number}
			local fills : {string : {number}} = { res = d.Residential.max, com = d.Commercial.max,
				ind = d.Industrial.max, growth = g.TownGrowth }
			for id, fill in pairs(fills) do
				barSheets[id] = styleutil.makeStyle{ size = { -1, BAR_H }, color = fill, backgroundColor1 = back }
			end
		end)
	end
	return barSheets[color] or barSheets.growth
end

local function gap(h : integer) : TreeNodeId
	if h == nil or h <= 0 then return nil end
	if gapSheets[h] == nil then
		local ok, st = pcall(function() : StyleSheet return styleutil.makeStyle{ size = { 1, h } } end)
		if not ok then return nil end
		gapSheets[h] = st
	end
	return builtin.Component{ meta = { styleSheet = gapSheets[h] } }
end

local function body(text : string, tip : string) : TreeNodeId
	return builtin.TextView{ meta = { class = "font-scale-body", tooltip = tip }, text = text or "" }
end

-- The base info hint, when this platform has it. The PS5 build's content_card has no makeInfoHint (Smart Lanes player
-- report 2026-10-19: "attempt to call field 'makeInfoHint' (a nil value)" reloaded the UI; docs/findings/gui.md
-- "Base GUI modules differ by platform"): then the base hint's own tree (content_card.tl:479-497) without the icon
-- image. Its base classes style it where they exist; plain text otherwise.
local function infoHint(text : string) : TreeNodeId
	local make = (content_card as {string : any}).makeInfoHint
	if make is function(string, boolean) : TreeNodeId then
		local ok, node = pcall(make, text, true)
		if ok and node ~= nil then return node end
	end
	return builtin.Component{
		meta = { class = "info-hint-comp" },
		layout = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = { builtin.TextView{ meta = { class = "font-scale-body, info-hint-text, no-icon" }, text = text } },
		},
	}
end

-- The base horizontal spacer, inline: gui_react_util.makeHorizontalSpacer's own body (gui_react_util.tl:367), so the
-- card does not depend on the function (base GUI modules differ by platform, see infoHint).
local function horizontalSpacer() : TreeNodeId
	return builtin.Component{ meta = { class = "horizontal-spacer" } }
end

-- key left, value right (line_eow.script.tl:80-97)
local function row(key : string, value : string, tip : string) : TreeNodeId
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			body(key, tip),
			horizontalSpacer(),
			value and body(value, tip) or nil,
		},
	}
end

-- The player's street style pick (GUI thread: the dropdown's handler): the event to the game script's handleEvent
-- (ot_saved.applyStyle), the pick kept until the poll reads it back, one log line. ps: 0 = Automatic, else an
-- ot_card.STYLE_IDS index.
local function styleSent(l : OtCardLine, ps : integer)
	local t = l.town
	if t == nil or ps < 0 or ps > #card.STYLE_IDS then return end
	local okS, err = pcall(function() : boolean
		api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", card.EVENT_ID, card.EV_STYLE, { town = t, ps = ps }))
		return true
	end)
	if okS then
		local n = 0
		for _k in pairs(pending) do n = n + 1 end
		if pending[t] ~= nil or n < MAX_PENDING then pending[t] = { ps = ps, at = os.time() } end
	end
	local name = (tostring(townName(t) or "-"):gsub("%s", "_"))
	log.message("[SQOT] STYLE event=pick town=" .. tostring(t) .. " name=" .. name
		.. " from=" .. tostring(l.from or "-") .. " to=" .. (ps == 0 and "auto" or tostring(card.STYLE_IDS[ps]))
		.. " sent=" .. tostring(okS) .. (okS and "" or (" err=" .. tostring(err))))
end

-- key left, the base dropdown right (the base mod settings' ComboBox, script_param_util.tl:484-512)
local function styleRow(l : OtCardLine) : TreeNodeId
	local items : {TreeNodeId} = {}
	local values : {string : boolean} = {}
	for _i, op in ipairs(l.options or {}) do
		values[op.value] = true
		items[#items + 1] = builtin.ComboBoxItem{
			value = op.value,
			content = builtin.TextView{ meta = { class = "font-scale-body", tooltip = op.tip }, text = op.text or "" },
		}
	end
	local sel = l.selected
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			body(l.key, l.tip),
			horizontalSpacer(),
			builtin.ComboBox{
				meta = { tooltip = l.tip },
				value = sel,
				items = items,
				onValueChange = function(v : integer|number|string)
					local s = tostring(v)
					if s == sel or not values[s] then return end
					local n = tonumber(s)
					if n ~= nil and n == math.floor(n) then styleSent(l, math.floor(n)) end
				end,
			},
		},
	}
end

local function townButton(tw : OtCardTown) : TreeNodeId
	local id = tw.id
	return builtin.Button{
		meta = { tooltip = _("Open this town's window.") },
		content = builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.ImageView{ path = TOWN_ICON, scaling = builtin.type.ImageViewScaling.AutoFit },
				builtin.TextView{ meta = { class = "font-scale-body" }, text = tw.name },
			},
		},
		onClick = function() openTown(id) end,
	}
end

local function lineWidget(l : OtCardLine) : TreeNodeId
	if l.kind == "row" then
		return row(l.key, type(l.value) == "string" and l.value as string or nil, l.tip)
	elseif l.kind == "bar" then
		local v = type(l.value) == "number" and l.value as number or 0
		-- (in a horizontal row of its own: the builtin ProgressBar rule's gravity { -1, -1 } then only fills the row's
		-- own height, as Problem Radar's fleet bar, radar_fleet.tl:455-463)
		return builtin.BoxLayout{
			orientation = builtin.type.Orientation.Horizontal,
			children = {
				builtin.ProgressBar{
					meta = { tooltip = l.tip, class = "font-scale-annotation", styleSheet = barSheet(l.color) }, -- INLINE STYLES
					value = math.max(0, math.min(1, v)),
					thresholds = l.mark and { math.max(0, math.min(1, l.mark)) } or nil,
				},
			},
		}
	elseif l.kind == "style" then
		return styleRow(l)
	elseif l.kind == "note" then
		return builtin.TextView{ meta = { class = "font-scale-annotation" }, text = l.text or "" }
	elseif l.kind == "hint" then
		return infoHint(l.text or "")
	elseif l.kind == "towns" then
		local kids : {TreeNodeId} = {}
		for _i, tw in ipairs(l.towns or {}) do kids[#kids + 1] = townButton(tw) end
		return builtin.FlowLayout{ children = kids }
	end
	return body(l.text, nil)
end

local record BodyParam
	view : OtCardView
end

local CardBody = react.RegisterRecipe("SquareOrganicTownsCardBody", function(p : BodyParam) : TreeNodeId
	local children : {TreeNodeId} = {}
	local function add(node : TreeNodeId) if node ~= nil then children[#children + 1] = node end end
	for i, sec in ipairs(p.view.sections or {}) do
		if i > 1 then
			add(gap(card.GAP_HEAD))
			add(builtin.Component{ meta = { class = "card-children-separator" } })
			add(gap(card.GAP_HEAD))
		end
		add(builtin.TextView{ meta = { class = "font-scale-headline" }, text = sec.title })
		local prev : string = nil
		for _i, l in ipairs(sec.lines or {}) do
			add(gap(card.gapBefore(prev, l.kind)))
			add(lineWidget(l))
			prev = l.kind
		end
	end
	return builtin.BoxLayout{ orientation = builtin.type.Orientation.Vertical, children = children }
end)

local CardSummary = react.RegisterRecipe("SquareOrganicTownsCardSummary", function(p : BodyParam) : TreeNodeId
	return row(p.view.summary or "", p.view.summaryValue, nil)
end)

local SquareOrganicTownsCard = react.RegisterPluginRecipe(town_eow.TownEowExtensionPoint, "SquareOrganicTownsCard", function(params : TownEow.TownWidgetPluginParams) : TreeNodeId
	local uniqueCardKey = tostring(react.getCurrentRecipeId())
	local t = params.entityId
	local o = settings()
	local state = engine_react_util.useStepStateTimer(function() : OtCardInput
		local ok, input = pcall(read, t, o)
		if ok then return input end
		return { town = t, names = {}, offs = {} }
	end, POLL_S)
	local input = state:old()
	local okV, view = pcall(card.view, input)
	if not okV or view == nil or view.hidden then
		return builtin.BoxLayout{ children = {} }
	end
	if not logged[t] and nLogged < MAX_LOGGED then
		logged[t] = true
		nLogged = nLogged + 1
		local okL, txt = pcall(card.logText, input)
		log.message("[SQOT] CARD event=read town=" .. tostring(t) .. " sections=" .. tostring(#view.sections) .. " "
			.. (okL and txt or "-"))
	end
	-- (base GUI modules differ by platform, see infoHint: no card rather than a UI reload)
	local cc = content_card as {string : any}
	local ccCard, ccRecipe = cc.ContentCard, cc.makeRecipeAndParam
	if not (ccCard is function and ccRecipe is function) then
		return builtin.BoxLayout{ children = {} }
	end
	return builtin.BoxLayout{
		child = content_card.ContentCard{
			title = _("Organic Towns"),
			initialCalloutTextPermanent = "",
			recipeAndParamPermanent = content_card.makeRecipeAndParam(CardSummary, { view = view }),
			recipeAndParamCollapsible = content_card.makeRecipeAndParam(CardBody, { view = view }),
			setCollapsibleExpanded = function(v : boolean) params.setCollapsibleExpanded(uniqueCardKey, v) end,
			collapsibleExpanded = params.getCollapsibleExpanded(uniqueCardKey),
			gameCtx = params.gameCtx,
			showOnRightSide = params.showCalloutOnRightSide,
		}
	}
end)

local function notMapEditor(params : TownEow.TownWidgetPluginParams) : boolean
	return not (params and params.state and params.state.isMapEditor)
end

return {
	SquareOrganicTownsCard = SquareOrganicTownsCard,
	notMapEditor = notMapEditor,
}
