-- Bulk Bulldozer: a bulldoze brush in Road → Tools and Rail → Tools (PLAN.md).
-- Phase 1 (skeleton + interaction spike): the tool mounts, a terrain-following ring of the chosen
-- radius follows the cursor. Mouse events are logged with the "[BulkBulldozer]" prefix to answer
-- the open questions in PLAN "Risks" (camera on left-drag, Moved while LMB held, getCurrentParams).
-- Phase 2 (selection engine): filter CheckBoxes, live highlight of what the brush would take
-- (hover preview and the painted selection), counts per kind and per skip reason in the tooltip.
-- Phase 3 (commit path) + user decision 2026-10-07 (PLAN "Interaction"): one mode, Paint, and
-- always select-then-confirm. Strokes only ADD to the selection (it stays highlighted after LMB
-- is released, later strokes add to it, up to the 400 cap). The toolbar button "Bulldoze"
-- removes it through bb_commit (preflight, money check, sendCommand, split retries).
-- RMB / ESC / the "Clear" button clear the selection. Every commit is logged with the "[BulkBulldozer]" prefix.
-- User feedback 2026-10-07 (PLAN "Filters", "Clear / exit"): one "Roads" filter for every street
-- (owned or not); a right click clears on the RMB Clicked event (the RMB Pressed / Released events
-- never reach the Selector, research §12); closing or switching the tool empties the selection.
-- User request 2026-10-07 (PLAN "Toolbar", research §10): the toolbar has [Bulldoze] [Clear] side
-- by side (one `group`, hideLabel) and a status chip under them with the live selection
-- ("12 selected · $34,500" + counts per kind, results for 3 s). The cursor tooltip keeps only the
-- radius, the right-click hint and skip reasons.
--
-- Wiring (research §1): bulk_bulldozer.res.lua → getDefinition below → ACTION_CUSTOM with the
-- BulkBulldozerAction recipe. The construction menu mounts the recipe while the entry is selected
-- (construction.tl:401-436); the recipe hands the world-layer body to params.setActionFn, like the
-- base construction_react_util.RegisterCustomSelectorBasedActionRecipe (1282-1442) and the
-- Overpass Builder mod (.cache/subscribed/move_it_probe_overpass, overpass_probe.script.tl).
--
-- Threads / state: everything runs in the GUI recipe. No game script, no saved state, no
-- modifiers; timing uses os.clock(). getDefinition may run in a different Lua VM than the recipe
-- (research §6), so toolbar values reach the recipe through onChangeFn → api.gui.fireReactEvent →
-- react.onEvent, and getCurrentParams() on activation.

local react = ug_require "::/gui/main/react.lua" as React
local builtin = ug_require "::/gui/main/builtin.lua" as Builtin
local constructionUi = ug_require "::/gui/construction/construction_react_util.tl" as ConstructionReactUtil
local brush = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_brush.tl" as BulkBulldozerBrush
local sel = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_select.tl" as BulkBulldozerSelect
local gather = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_gather.tl" as BulkBulldozerGather
local commit = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_commit.tl" as BulkBulldozerCommit
local status = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_status.tl" as BulkBulldozerStatus
local hl = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_highlight.tl" as BulkBulldozerHighlight

local PREFIX <const> = "[BulkBulldozer] "
local EV_RADIUS <const> = "BulkBulldozer.radius"
local EV_BULLDOZE <const> = "BulkBulldozer.bulldoze"
local EV_FILTER <const> = "BulkBulldozer.filter"
local EV_SHOWN <const> = "BulkBulldozer.shown"
local EV_CLEAR <const> = "BulkBulldozer.clear"
local EV_STATUS <const> = "BulkBulldozer.status"
local KEY_RADIUS <const> = "bulk_bulldozer_radius"
local KEY_BULLDOZE <const> = "bulk_bulldozer_bulldoze"
local KEY_CLEAR <const> = "bulk_bulldozer_clear"
local KEY_STATUS <const> = "bulk_bulldozer_status"
-- Toolbar groups (construction.tl:2024-2074: consecutive params with the same `group` and
-- hideLabel share one horizontal row; a named group gets a separator line before it).
local GROUP_ACTIONS <const> = "bulk_bulldozer_actions"
local GROUP_FILTERS <const> = "bulk_bulldozer_filters"

-- What the selection shows: the hover preview (nothing selected), a stroke being painted
-- (LMB held, adding), the selection waiting for "Bulldoze" (LMB released), or the
-- selection being removed.
local PHASE_IDLE <const> = "idle"
local PHASE_PAINTING <const> = "painting"
local PHASE_SELECTED <const> = "selected"
local PHASE_COMMITTING <const> = "committing"

-- A result / notice stays in the status chip this long (seconds).
local RESULT_SECONDS <const> = 3.0
-- A commit with no final callback after this long is given up on screen (seconds).
local COMMIT_TIMEOUT <const> = 20.0

-- The ring follows the cursor once it moved this far (metres); smaller moves don't re-render.
local CURSOR_EPS <const> = 0.25
-- Moved events are summarised in one log line at most this often (seconds).
local MOVED_LOG_INTERVAL <const> = 0.5
-- The hover preview drops its descriptor cache this often (seconds), so it never goes stale.
local HOVER_CACHE_TTL <const> = 2.0
-- A sample slower than this is logged (seconds; PLAN Phase 4 target is 2 ms), at most once a second.
local SLOW_SAMPLE <const> = 0.004
-- Spike aid (PLAN Phase 1 "octree hit semantics", TESTING §2): the hover tooltip also shows the raw
-- octree counts for exactly radius r. Two extra native queries per hover sample. Off in Phase 4.
local DEBUG_OCTREE <const> = false
-- Right click (research §12): only PressedOutside and Clicked of button 2 reach the Selector. A
-- Clicked this far (screen px, either axis) from its press is a camera drag, not a click: the
-- selection stays. Tune from the "right click: moved N px" log line.
local RMB_CLICK_MAX_PX <const> = 16
-- The world layer (actionFn) counts as closed once it stays unmounted this long (os.clock s). An
-- unmount followed by a mount in the same frame (re-binding) is not a close.
local LAYER_GONE_SECONDS <const> = 0.25

-- Toolbar CheckBoxes, in sel.FILTER_KEYS order (PLAN "Filters"). Keys are stable: the menu
-- remembers values by key.
local record FilterParam
	field : string
	key : string
	name : string
	tooltip : string
end
local FILTER_PARAMS : {FilterParam} = {
	-- One key for all streets (user decision 2026-10-07); a new key, so the menu's remembered
	-- values of the old "Your roads" / "Town roads" CheckBoxes don't carry over.
	{ field = "roads", key = "bulk_bulldozer_f_roads", name = _("Roads"),
		tooltip = _("All roads: yours, town roads and roads without an owner. Never another company's roads or the roads of stations and industries.") },
	{ field = "tracks", key = "bulk_bulldozer_f_tracks", name = _("Tracks"),
		tooltip = _("Your tracks, with their signals and waypoints.") },
	{ field = "stations", key = "bulk_bulldozer_f_stations", name = _("Stations & depots"),
		tooltip = _("Your stations and depots.") },
	{ field = "assets", key = "bulk_bulldozer_f_assets", name = _("Other assets"),
		tooltip = _("Other things you placed, such as assets.") },
	{ field = "townBuildings", key = "bulk_bulldozer_f_town_buildings", name = _("Town buildings"),
		tooltip = _("Houses and other town buildings.") },
	{ field = "underground", key = "bulk_bulldozer_f_underground", name = _("Underground"),
		tooltip = _("Also tunnels.") },
}

-- field → toolbar key, for bb_select.paramFilters.
local FILTER_KEY_OF : {string : string} = {}
for _, fp in ipairs(FILTER_PARAMS) do FILTER_KEY_OF[fp.field] = fp.key end

-- Toolbar sync (coordinator request 2026-10-07): the filters the tool uses must match the
-- CheckBoxes shown. getCurrentParams() returned {} in game (research §12), so the tool learns the
-- shown values from (a) the params map the menu passes to checkEnabledFn on every activation and
-- change (construction.tl:1584-1596, 1650-1653, 1890) and (b) the onChangeFn events (with the
-- menu category, ConstructionMenuParamsAPI.getCategory). File scope and NOT reset on mount or
-- close: like the menu's remembered values (refStoredParams) it lives until the GUI is rebuilt.
-- Unknown or conflicting values are OFF (bb_select.resolveFilters).
local record FilterMemory
	shown : {string : boolean}               -- last values the toolbar showed (certain only)
	toggles : {string : {string : boolean}}  -- menu category → field → last toggled value
end
local g_filterMem : FilterMemory = { shown = {}, toggles = {} }

local function rememberShown(vals : {string : boolean}) : boolean
	local changed = false
	for k, v in pairs(vals) do
		if g_filterMem.shown[k] ~= v then g_filterMem.shown[k] = v; changed = true end
	end
	return changed
end

local function rememberToggle(category : string, field : string, on : boolean)
	local cat = category or "?"
	g_filterMem.toggles[cat] = g_filterMem.toggles[cat] or {}
	g_filterMem.toggles[cat][field] = on
	g_filterMem.shown[field] = on
end

local function logMsg(msg : string)
	pcall(function() log.message(PREFIX .. msg) end)
end

local record RadiusEvent
	meters : number
end
local record FilterEvent
	field : string
	on : boolean
	category : string   -- menu category of the toolbar (nil when unreadable)
	shown : {string : boolean}  -- every filter that toolbar certainly shows (nil when unreadable)
end
local record ShownEvent
	values : {string : boolean}
end
local record BulkBulldozerActionParam end
local record MovedLog
	count : integer       -- Moved events since the last summary
	withLmb : integer     -- of those, while LMB was held
	handled : integer     -- of those, with evt.handled already set
	lastAt : number       -- os.clock() of the last summary
end
local record Sample
	x : number
	y : number
	r : number
	at : number
end
-- Everything about the current selection; mutated in place, re-rendered via versionState.
local record Selection
	phase : string
	stroke : BulkBulldozerStroke
	cache : BulkBulldozerGatherCache
	ctx : BulkBulldozerContext
	samples : integer
	worst : number          -- slowest sample in seconds
	truncated : boolean     -- an octree query hit SAMPLE_MAX_ENTITIES
	slowLoggedAt : number
	rawEdges : integer      -- DEBUG_OCTREE: octree BASE_EDGE hits at exactly r (-1 = query failed)
	rawCons : integer       -- DEBUG_OCTREE: octree CONSTRUCTION hits at exactly r
	preview : BulkBulldozerPreview  -- last makeProposalData summary of the stroke (nil = none yet)
	previewAt : number      -- os.clock() of that preview
	previewCount : integer  -- stroke size it was computed for
	commitAt : number       -- os.clock() when the commit started
end
local record RmbPress
	x : integer
	y : integer
end
local record ResultLine
	text : BulkBulldozerStatusText
	untilAt : number        -- os.clock() deadline
end

-- Status chip text shared between the action recipe (writer) and the BulkBulldozerStatus recipe
-- in the toolbar (reader). Same module, same Lua state: the construction menu loads this file once
-- through util.useFn (construction_react_util.tl:2829, scripts/util.tl:5-27), and the Overpass
-- Builder shares file-level state between its recipe and its toolbar params the same way
-- (overpass_probe.script.tl:4123-4128 → 6125-6127). The EV_STATUS event carries the same text
-- in case the two ever run in different Lua states.
local record StatusEvent
	head : string
	detail : string
	version : integer
end
-- File-scope state outlives the recipe (the module stays loaded across unmounts), so the action
-- recipe resets it on mount and unmount (resetStatus) and the chip never shows a stale selection.
local STATUS_IDLE : BulkBulldozerStatusText = { head = "Nothing selected", detail = "Paint with the left mouse button" }
local g_status : StatusEvent = { head = STATUS_IDLE.head, detail = STATUS_IDLE.detail, version = 0 }

local function publishStatus(t : BulkBulldozerStatusText)
	g_status = { head = t.head, detail = t.detail, version = g_status.version + 1 }
	pcall(api.gui.fireReactEvent, EV_STATUS, g_status)
end

local function resetStatus()
	publishStatus(STATUS_IDLE)
end

local function newSelection(phase : string) : Selection
	return {
		phase = phase,
		stroke = sel.newStroke(),
		cache = gather.newCache(),
		ctx = gather.context(),
		samples = 0,
		worst = 0,
		truncated = false,
		slowLoggedAt = 0,
	}
end

local function eventTypeName(t : Gui.Mouse.Event.Type) : string
	local T = api.gui.mouse.Event.Type
	if t == T.Pressed then return "Pressed"
	elseif t == T.Released then return "Released"
	elseif t == T.Moved then return "Moved"
	elseif t == T.Wheel then return "Wheel"
	elseif t == T.Clicked then return "Clicked"
	elseif t == T.DoubleClicked then return "DoubleClicked"
	elseif t == T.Entered then return "Entered"
	elseif t == T.Exited then return "Exited"
	elseif t == T.PressedOutside then return "PressedOutside"
	end
	return tostring(t)
end

local function paramsToString(p : {string : number}) : string
	if p == nil then return "nil" end
	local keys : {string} = {}
	for k in pairs(p) do keys[#keys + 1] = k end
	table.sort(keys)
	local parts : {string} = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. tostring(p[k]) end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local function filtersToString(f : BulkBulldozerFilters) : string
	local on : {string} = {}
	local ff = f as {string : boolean}
	for _, k in ipairs(sel.FILTER_KEYS) do
		if ff[k] then on[#on + 1] = k end
	end
	return "{" .. table.concat(on, ", ") .. "}"
end

local function copyFilters(f : BulkBulldozerFilters) : BulkBulldozerFilters
	local out = {} as {string : boolean}
	for k, v in pairs(f as {string : boolean}) do out[k] = v end
	return out as BulkBulldozerFilters
end

local function rawCount(x : number, y : number, r : number, t : Engine.ComponentType) : integer
	local ok, res = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r, t)
	return (ok and res ~= nil) and #res or -1
end

local function terrainHeight(x : number, y : number) : number
	return api.engine.terrain.getHeightAt(api.type.Vec2f.new(x, y))
end

-- One EdgeRenderable edge per ring arc (shape from overpass_probe.script.tl:4532-4555).
local function ringEdges(cx : number, cy : number, r : number, color : Vec4f) : {Builtin.Type.EdgeRenderable.Edge}
	local edges : {Builtin.Type.EdgeRenderable.Edge} = {}
	local width = brush.ringWidth(r)
	for _, a in ipairs(brush.ringArcs(cx, cy, r, brush.RING_ARCS, terrainHeight)) do
		local arc = api.type.EdgeGeometry.Arc.new()
		arc.center = api.type.Vec2f.new(cx, cy)
		arc.radius = r
		arc.startAngle = a.startAngle
		arc.angle = a.angle
		local g = api.type.EdgeGeometry.new()
		g.arc = arc
		g.height = api.type.Vec2f.new(a.h0, a.h1)
		g.width = width
		g.length = a.length
		local viz = builtin.type.EdgeRenderable.Edge.new(g)
		viz.colors = { color, color, color }
		viz.stepSize = 1
		viz.width = width
		viz.offsetZ = 1.0
		edges[#edges + 1] = viz
	end
	return edges
end

local function safeHeight(x : number, y : number) : number
	local ok, h = pcall(terrainHeight, x, y)
	if ok and h ~= nil then return h end
	return 0
end

local function vec4(c : {number}) : Vec4f
	return api.type.Vec4f.new(c[1], c[2], c[3], c[4])
end

-- Selection overlay (bb_highlight "lines"): one straight EdgeRenderable piece, the Overpass
-- Straight shape (overpass_probe.script.tl:4831-4846).
local function segmentEdge(sg : BulkBulldozerSegment, color : Vec4f, width : number) : Builtin.Type.EdgeRenderable.Edge
	local dx, dy = sg.x1 - sg.x0, sg.y1 - sg.y0
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.05 then return nil end
	local st = api.type.EdgeGeometry.Straight.new()
	st.pos = { api.type.Vec2f.new(sg.x0, sg.y0), api.type.Vec2f.new(sg.x1, sg.y1) }
	local g = api.type.EdgeGeometry.new()
	g.straight = st
	g.height = api.type.Vec2f.new(sg.z0, sg.z1)
	g.width = width
	g.length = len
	local viz = builtin.type.EdgeRenderable.Edge.new(g)
	viz.colors = { color, color, color }
	viz.stepSize = 1
	viz.width = width
	viz.offsetZ = hl.LINE_OFFSET_Z
	return viz
end

-- A full circle on a construction's origin (the Overpass full-circle Arc, 4532-4555).
local function markerEdge(x : number, y : number, color : Vec4f, width : number) : Builtin.Type.EdgeRenderable.Edge
	local z = safeHeight(x, y)
	local r = hl.MARKER_RADIUS
	local arc = api.type.EdgeGeometry.Arc.new()
	arc.center = api.type.Vec2f.new(x, y)
	arc.radius = r
	arc.startAngle = 0
	arc.angle = 2 * math.pi
	local g = api.type.EdgeGeometry.new()
	g.arc = arc
	g.height = api.type.Vec2f.new(z, z)
	g.width = width
	g.length = 2 * math.pi * r
	local viz = builtin.type.EdgeRenderable.Edge.new(g)
	viz.colors = { color, color, color }
	viz.stepSize = 1
	viz.width = width
	viz.offsetZ = hl.LINE_OFFSET_Z
	return viz
end

-- One brush sample into the selection's stroke. Returns true when the stroke changed.
local function takeSample(s : Selection, x : number, y : number, r : number, f : BulkBulldozerFilters) : boolean
	local ok, res = pcall(gather.sample, x, y, r, f, s.ctx, s.cache)
	if not ok then
		logMsg("sample failed: " .. tostring(res))
		return false
	end
	s.samples = s.samples + 1
	if res.seconds > s.worst then s.worst = res.seconds end
	if res.truncated then s.truncated = true end
	if res.seconds > SLOW_SAMPLE and os.clock() - s.slowLoggedAt >= 1.0 then
		s.slowLoggedAt = os.clock()
		logMsg(string.format("slow sample: %.1f ms (r = %d m, %d edges, %d constructions in query)",
			res.seconds * 1000, math.floor(r), res.edgeHits, res.conHits))
	end
	local before = sel.count(s.stroke)
	local skippedBefore = 0
	for _, n in pairs(s.stroke.reasonCounts) do skippedBefore = skippedBefore + n end
	for _, c in ipairs(res.candidates) do sel.add(s.stroke, c) end
	local skippedAfter = 0
	for _, n in pairs(s.stroke.reasonCounts) do skippedAfter = skippedAfter + n end
	return sel.count(s.stroke) ~= before or skippedAfter ~= skippedBefore
end

local EDGE_KINDS : {string : boolean} = { road = true, track = true }

-- The stroke's kept entities split into edges and constructions (add order).
local function strokeLists(st : BulkBulldozerStroke) : {integer}, {integer}
	local edges : {integer} = {}
	local cons : {integer} = {}
	for _, e in ipairs(st.order) do
		local c = st.keep[e]
		if c ~= nil and EDGE_KINDS[c.kind as string] then edges[#edges + 1] = e else cons[#cons + 1] = e end
	end
	return edges, cons
end

-- The highlight overlay of one selection state, cached until the selection or phase changes
-- (the action re-renders on every cursor move for the ring).
local record Overlay
	key : string
	edges : {Builtin.Type.EdgeRenderable.Edge}
	pieces : integer      -- straight pieces along edges
	markers : integer     -- construction circles
	truncated : boolean   -- MAX_SEGMENTS reached; some pieces / edges left out
end

local function buildOverlay(s : Selection, phase : string, key : string) : Overlay
	local c = hl.colors(phase)
	local color = vec4(c.line)
	local curves : {BulkBulldozerCurve} = {}
	local points : {BulkBulldozerDesc} = {}
	for _, e in ipairs(s.stroke.order) do
		local cand = s.stroke.keep[e]
		local d = s.cache.descs[e]
		if cand ~= nil and d ~= nil and not d.gone then
			if EDGE_KINDS[cand.kind as string] then
				if d.curve ~= nil then curves[#curves + 1] = d.curve end
			elseif d.x ~= nil and d.y ~= nil then
				points[#points + 1] = d
			end
		end
	end
	local out : Overlay = { key = key, edges = {}, pieces = 0, markers = 0, truncated = false }
	local markerBudget = math.min(#points, math.floor(hl.MAX_SEGMENTS / 4))
	if markerBudget < #points then out.truncated = true end
	for i = 1, markerBudget do
		local d = points[i]
		local m = markerEdge(d.x, d.y, color, c.lineWidth)
		out.edges[#out.edges + 1] = m
		out.markers = out.markers + 1
	end
	local segs, trunc = hl.edgeSegments(curves, hl.MAX_SEGMENTS - out.markers, safeHeight)
	if trunc then out.truncated = true end
	for _, sg in ipairs(segs) do
		local v = segmentEdge(sg, color, c.lineWidth)
		if v ~= nil then
			out.edges[#out.edges + 1] = v
			out.pieces = out.pieces + 1
		end
	end
	return out
end

local function moneyText(c : integer) : string
	if c == nil then return "cost unknown" end
	local ok, t = pcall(api.util.formatMoney, c)
	if ok and t ~= nil then return t end
	return tostring(c)
end

local function previewCost(s : Selection) : integer
	if s.preview == nil then return nil end
	return s.preview.cost
end

-- Fresh makeProposalData summary of the whole stroke.
local function updatePreview(s : Selection)
	local edges, cons = strokeLists(s.stroke)
	local ok, pv = pcall(commit.preview, edges, cons)
	if not ok then
		logMsg("preview failed: " .. tostring(pv))
		pv = { ok = false, cost = nil, critical = false, errors = {}, seconds = 0 }
	end
	if pv.seconds > 0.02 then
		logMsg(string.format("slow preview: %.1f ms for %d objects", pv.seconds * 1000, sel.count(s.stroke)))
	end
	s.preview = pv
	s.previewAt = os.clock()
	s.previewCount = sel.count(s.stroke)
end

local function logStroke(what : string, s : Selection)
	logMsg(string.format("%s: %d selected, cost %s, %d samples, worst %.1f ms%s — %s",
		what, sel.count(s.stroke), moneyText(previewCost(s)),
		s.samples, s.worst * 1000, s.stroke.capped and ", capped" or "",
		table.concat(sel.describe(s.stroke), " / ")))
end

local BulkBulldozerAction = react.RegisterRecipe("BulkBulldozerAction",
	function(param : ConstructionCustomActionParams<BulkBulldozerActionParam>) : TreeNodeId

	-- All hooks first, in a fixed order; the isActive gate comes after them.
	local radiusState = react.useState(brush.DEFAULT_RADIUS) as ReactStateT<number>
	-- Starts from the toolbar memory, not the defaults (a remount must not re-tick a box the
	-- player unticked); unknown → off.
	local filtersState = react.useState((sel.resolveFilters(g_filterMem.shown, g_filterMem.toggles,
		sel.defaultFilters()))) as ReactStateT<BulkBulldozerFilters>
	local cursorState = react.useState(nil) as ReactStateT<Vec3f>
	local versionState = react.useState(0) as ReactStateT<integer>   -- bumped when the selection changes
	local refLmbDown = react.useRef(false) as ReactRefT<boolean>
	local refRmbPress = react.useRef(nil) as ReactRefT<RmbPress>     -- last RMB press position
	local refRenderActive = react.useRef(false) as ReactRefT<boolean> -- isActive at the last render
	local refLayerDownAt = react.useRef(nil) as ReactRefT<number>     -- os.clock() the world layer unmounted
	-- The next LMB release is ignored (it ends a press that RMB cleared or that came mid-commit).
	local refSkipRelease = react.useRef(false) as ReactRefT<boolean>
	local refSample = react.useRef(nil) as ReactRefT<Sample>
	local refSel = react.useRef(nil) as ReactRefT<Selection>
	local refVersion = react.useRef(0) as ReactRefT<integer>
	local refMoved = react.useRef({ count = 0, withLmb = 0, handled = 0, lastAt = 0 }) as ReactRefT<MovedLog>
	local refWasActive = react.useRef(false) as ReactRefT<boolean>
	local refJob = react.useRef(0) as ReactRefT<integer>            -- id of the latest commit
	local refResult = react.useRef(nil) as ReactRefT<ResultLine>    -- status chip result (3 s)
	local refStatusKey = react.useRef("") as ReactRefT<string>      -- last published status text
	local refOverlay = react.useRef(nil) as ReactRefT<Overlay>      -- cached highlight lines
	local refHlSet = react.useRef({}) as ReactRefT<{integer : boolean}>  -- highlighted, for the Selector filter
	local refTruncLogged = react.useRef(nil) as ReactRefT<Selection> -- selection whose overlay cap was logged
	-- The latest params for the step/event callbacks (they may outlive this render's closure).
	local refParam = react.useRef(param) as ReactRefT<ConstructionCustomActionParams<BulkBulldozerActionParam>>
	refParam:set(param)

	local function bump()
		refVersion:set(refVersion:get() + 1)
		versionState:set(refVersion:get())
	end
	-- Back to the hover preview; the next step re-samples under the cursor.
	local function resetToIdle()
		refSel:set(nil)
		refSample:set(nil)
		bump()
	end
	-- A stroke being painted or a selection waiting for "Bulldoze": RMB / ESC clear it.
	local function hasPending() : boolean
		local s = refSel:get()
		return s ~= nil and (s.phase == PHASE_PAINTING or s.phase == PHASE_SELECTED)
	end
	local function cancelPending(why : string)
		local s = refSel:get()
		if s == nil then return end
		logMsg(string.format("selection cleared (%s): %d selected, nothing removed", why, sel.count(s.stroke)))
		-- The LMB release that ends a cleared press must not start a new selection.
		if refLmbDown:get() then refSkipRelease:set(true) end
		refLmbDown:set(false)
		resetToIdle()
	end
	-- The tool was closed, switched or hidden (user feedback 2026-10-07): drop the selection, the
	-- hover preview, the result line and the status chip, so reopening starts empty. A commit that
	-- is running keeps going in the engine; its result is no longer shown. rerender = false when
	-- called during a render or an unmount (no state updates there).
	local function resetAll(why : string, rerender : boolean)
		local s = refSel:get()
		if s ~= nil and (s.phase == PHASE_PAINTING or s.phase == PHASE_SELECTED) then
			logMsg(string.format("selection cleared (%s): %d selected, nothing removed", why, sel.count(s.stroke)))
		elseif s ~= nil and s.phase == PHASE_COMMITTING then
			logMsg("tool closed while bulldozing (" .. why .. "); commands already sent still run")
			refJob:set(refJob:get() + 1)
		end
		refSel:set(nil)
		refSample:set(nil)
		refLmbDown:set(false)
		refSkipRelease:set(false)
		refRmbPress:set(nil)
		refResult:set(nil)
		refOverlay:set(nil)
		refHlSet:set({})
		refStatusKey:set("")
		resetStatus()
		if rerender then bump() end
	end

	-- Mount / unmount of the tool recipe (base pattern: construction_react_util.tl:1355-1364):
	-- file-scope state (g_status) survives an unmount, so both ends reset it.
	react.onMount(function()
		resetStatus()
	end)
	react.onUnmount(function()
		resetStatus()
		pcall(resetAll, "tool closed", false)
	end)
	-- isActive dropped since the last render: clear at once (onStep may not run any more when the
	-- menu is hidden, and the log of 2026-10-07 never showed "tool deactivated").
	if refRenderActive:get() and not param.isActive then
		pcall(resetAll, "tool closed", false)
	end
	refRenderActive:set(param.isActive == true)

	-- Removes the selection (bb_commit). pre = a fresh preview to reuse, or nil to preflight again.
	local function startCommit(s : Selection, pre : BulkBulldozerPreview)
		local edges, cons = strokeLists(s.stroke)
		s.phase = PHASE_COMMITTING
		s.commitAt = os.clock()
		local job = refJob:get() + 1
		refJob:set(job)
		logStroke("commit", s)
		bump()
		local onDone = function(res : BulkBulldozerCommitResult)
			-- pcall: the tool may have been closed (recipe unmounted) before the last callback.
			pcall(function()
				if refJob:get() ~= job then return end   -- given up on (timeout), tool closed or superseded
				refJob:set(job + 1)
				refResult:set({ text = status.resultLines(res), untilAt = os.clock() + RESULT_SECONDS })
				refSel:set(nil)
				refSample:set(nil)
				bump()
			end)
		end
		local ok, err = pcall(function() : string
			commit.commit(edges, cons, s.ctx, s.cache.industryRoads, pre, onDone, logMsg)
			return nil
		end)
		if not ok then
			logMsg("commit failed: " .. tostring(err))
			refResult:set({ text = { head = "Bulldozing failed", detail = "See the game log" }, untilAt = os.clock() + RESULT_SECONDS })
			refJob:set(job + 1)
			resetToIdle()
		end
	end

	-- LMB released: the selection stays (highlighted) and waits for "Bulldoze"; the
	-- next stroke adds to it. Nothing is removed here (PLAN "Interaction").
	local function finishStroke(s : Selection)
		if sel.count(s.stroke) == 0 then
			logStroke("stroke (nothing selected)", s)
			resetToIdle()
			return
		end
		updatePreview(s)
		s.phase = PHASE_SELECTED
		refSel:set(s)
		logStroke("stroke (waiting for Bulldoze)", s)
		local ov = refOverlay:get()
		if hl.usesLines(hl.MODE) and ov ~= nil then
			logMsg(string.format("highlight: %d entities, overlay %d line pieces + %d construction circles%s (last render)",
				sel.count(s.stroke), ov.pieces, ov.markers, ov.truncated and ", capped" or ""))
		end
		bump()
	end

	-- The toolbar button "Bulldoze" (onChangeFn → EV_BULLDOZE).
	local function bulldozeSelection()
		local s = refSel:get()
		if s == nil or s.phase == PHASE_IDLE or sel.count(s.stroke) == 0 then
			logMsg("bulldoze button: nothing selected")
			refResult:set({ text = { head = "Nothing selected", detail = "Paint over objects first" }, untilAt = os.clock() + RESULT_SECONDS })
			bump()
			return
		end
		if s.phase == PHASE_COMMITTING then
			logMsg("bulldoze button: a commit is already running")
			return
		end
		-- PAINTING only if LMB still counts as held (it can't be while the toolbar is clicked):
		-- the release that follows must not touch the selection being removed.
		if refLmbDown:get() then
			refSkipRelease:set(true)
			refLmbDown:set(false)
		end
		logMsg("bulldoze button: " .. tostring(sel.count(s.stroke)) .. " selected")
		startCommit(s, nil)   -- fresh preflight (cost, money check) in bb_commit
	end

	react.onEvent(EV_RADIUS, function(_name : string, payload : any)
		local m = (payload as RadiusEvent).meters
		local r = brush.radiusFromParam(m)
		logMsg("radius event: " .. tostring(m) .. " -> r = " .. tostring(r)
			.. " (getCurrentParams " .. paramsToString(refParam:get().getCurrentParams()) .. ")")
		if r ~= nil then radiusState:set(r) end
	end)
	react.onEvent(EV_BULLDOZE, function(_name : string, _payload : any)
		if not refParam:get().isActive then return end
		bulldozeSelection()
	end)
	-- The toolbar button "Clear" (onChangeFn → EV_CLEAR): same as a right click.
	react.onEvent(EV_CLEAR, function(_name : string, _payload : any)
		if not refParam:get().isActive then return end
		if hasPending() then
			cancelPending("clear button")
		else
			logMsg("clear button: nothing selected")
		end
	end)
	-- The filters from the toolbar memory (never more than the toolbar certainly shows).
	local function syncFilters(why : string)
		local f, unknown = sel.resolveFilters(g_filterMem.shown, g_filterMem.toggles, sel.defaultFilters())
		local old = filtersState:old()
		if filtersToString(f) ~= filtersToString(old) or #unknown > 0 then
			logMsg("filters (" .. why .. ") " .. filtersToString(f)
				.. (#unknown > 0 and (" -- unknown, treated as off: " .. table.concat(unknown, ", ")) or ""))
		end
		local changed = filtersToString(f) ~= filtersToString(old)
		filtersState:set(f)
		-- The hover preview is redone with the new filters; a selection keeps what it has.
		local s = refSel:get()
		if changed and (s == nil or s.phase == PHASE_IDLE) then resetToIdle() end
	end
	react.onEvent(EV_SHOWN, function(_name : string, payload : any)
		local ev = payload as ShownEvent
		if ev == nil or ev.values == nil then return end
		rememberShown(ev.values)
		syncFilters("toolbar shown")
	end)
	react.onEvent(EV_FILTER, function(_name : string, payload : any)
		local ev = payload as FilterEvent
		if ev.shown ~= nil then rememberShown(ev.shown) end
		rememberToggle(ev.category, ev.field, ev.on == true)
		syncFilters("toggle")
		local f = filtersState:old()
		logMsg("filter event: " .. tostring(ev.field) .. " = " .. tostring(ev.on)
			.. " (category " .. tostring(ev.category) .. ") -> " .. filtersToString(f))
		-- A painting stroke keeps going with the new filters; the hover preview is redone; a
		-- selection waiting for "Bulldoze" or being removed keeps what it has.
		local s = refSel:get()
		if s == nil or s.phase == PHASE_IDLE then resetToIdle() end
	end)

	-- The status chip text for the current selection (or hover preview) and result line.
	local function statusNow() : BulkBulldozerStatusText
		local s = refSel:get()
		local rl = refResult:get()
		local v : BulkBulldozerStatusInput = {
			phase = s ~= nil and s.phase or "none",
			count = s ~= nil and sel.count(s.stroke) or 0,
			kindCounts = s ~= nil and s.stroke.kindCounts or {},
			objects = s ~= nil and s.stroke.objects or 0,
			cost = (s ~= nil and s.preview ~= nil and s.preview.cost ~= nil) and moneyText(s.preview.cost) or nil,
			capped = s ~= nil and s.stroke.capped or false,
			cap = sel.STROKE_CAP,
			result = (rl ~= nil and os.clock() < rl.untilAt) and rl.text or nil,
		}
		return status.lines(v)
	end
	-- Publish to the toolbar chip only when the text changed.
	local function publishIfChanged()
		local t = statusNow()
		local key = t.head .. "\n" .. t.detail
		if key ~= refStatusKey:get() then
			refStatusKey:set(key)
			publishStatus(t)
		end
	end

	react.onStep(function()
		local prm = refParam:get()
		local active = prm.isActive == true
		-- Activation edge: read back the toolbar (onChangeFn does not fire at mount).
		if active ~= refWasActive:get() then
			refWasActive:set(active)
			if active then
				local p = prm.getCurrentParams()
				logMsg("tool activated; getCurrentParams " .. paramsToString(p))
				logMsg("highlight mode " .. hl.describeMode(hl.MODE)
					.. (hl.HOVER_ONLY_HIGHLIGHTED and "; hover effect only on highlighted objects" or ""))
				local r = p ~= nil and brush.radiusFromParam(p[KEY_RADIUS]) or nil
				if r ~= nil and r ~= radiusState:old() then radiusState:set(r) end
				rememberShown(sel.paramFilters(p, FILTER_KEY_OF))
				syncFilters("activated")
				logMsg("filters " .. filtersToString(filtersState:old()))
			else
				logMsg("tool deactivated")
				resetAll("tool closed", true)
				cursorState:set(nil)
			end
		end
		if not active then
			refLayerDownAt:set(nil)
			publishIfChanged()
			return
		end
		-- World layer unmounted and not back (another tool took the world): the tool was switched.
		local downAt = refLayerDownAt:get()
		if downAt ~= nil and os.clock() - downAt >= LAYER_GONE_SECONDS then
			refLayerDownAt:set(nil)
			logMsg("world layer unmounted")
			resetAll("tool switched", true)
		end

		-- Cursor follow (the ring re-renders only when the cursor moved).
		if api.gui.mouse.hasTerrainPosition() then
			local c = api.gui.mouse.getTerrainPosition()
			local old = cursorState:old()
			if old == nil or math.abs(old.x - c.x) > CURSOR_EPS or math.abs(old.y - c.y) > CURSOR_EPS then
				cursorState:set(api.type.Vec3f.new(c.x, c.y, c.z))
			end
		end

		-- Brush samples, throttled by the sample policy (PLAN "Batching / rate limit").
		local cur = cursorState:old()
		local r = radiusState:old()
		local now = os.clock()
		local s = refSel:get()
		if cur ~= nil and (s == nil or s.phase == PHASE_IDLE or s.phase == PHASE_PAINTING) then
			local last = refSample:get()
			local due = last == nil or last.r ~= r or brush.sampleDue(cur.x - last.x, cur.y - last.y, now - last.at, r)
			-- A cursor that hasn't moved adds nothing while painting; the hover preview refreshes the
			-- same spot only when its cache expires (the 100 ms timer would re-take it otherwise).
			if due and s ~= nil and last ~= nil and last.r == r and cur.x == last.x and cur.y == last.y
					and (s.phase == PHASE_PAINTING or now - last.at < HOVER_CACHE_TTL) then
				due = false
			end
			if due and s ~= nil and s.phase == PHASE_PAINTING and s.stroke.capped then due = false end
			if due then
				refSample:set({ x = cur.x, y = cur.y, r = r, at = now })
				if s ~= nil and s.phase == PHASE_PAINTING then
					if takeSample(s, cur.x, cur.y, r, filtersState:old()) then bump() end
				else
					-- Hover preview: a fresh single-sample stroke, cache reused for HOVER_CACHE_TTL.
					local cache = s ~= nil and s.cache or nil
					local ctx = s ~= nil and s.ctx or nil
					local hs = newSelection(PHASE_IDLE)
					if cache ~= nil and now - cache.createdAt < HOVER_CACHE_TTL then
						hs.cache = cache
						hs.ctx = ctx
					end
					takeSample(hs, cur.x, cur.y, r, filtersState:old())
					local changed = s == nil or sel.count(s.stroke) ~= sel.count(hs.stroke)
						or table.concat(sel.describe(s.stroke), "|") ~= table.concat(sel.describe(hs.stroke), "|")
					if DEBUG_OCTREE then
						hs.rawEdges = rawCount(cur.x, cur.y, r, api.type.ComponentType.BASE_EDGE)
						hs.rawCons = rawCount(cur.x, cur.y, r, api.type.ComponentType.CONSTRUCTION)
						if s == nil or s.rawEdges ~= hs.rawEdges or s.rawCons ~= hs.rawCons then changed = true end
					end
					if not changed then
						for i, e in ipairs(hs.stroke.order) do
							if s.stroke.order[i] ~= e then changed = true; break end
						end
					end
					refSel:set(hs)
					if changed then bump() end
				end
			end
		end

		-- Cost preview while painting: at most every PREVIEW_INTERVAL, only when the stroke grew.
		s = refSel:get()
		if s ~= nil and s.phase == PHASE_PAINTING and sel.count(s.stroke) > 0
				and sel.count(s.stroke) ~= (s.previewCount or 0)
				and (s.previewAt == nil or now - s.previewAt >= commit.PREVIEW_INTERVAL) then
			updatePreview(s)
			bump()
		end
		-- A commit whose last callback never came: stop waiting on screen.
		if s ~= nil and s.phase == PHASE_COMMITTING and now - (s.commitAt or now) > COMMIT_TIMEOUT then
			logMsg(string.format("commit: no final callback after %d s, giving up waiting", math.floor(COMMIT_TIMEOUT)))
			refJob:set(refJob:get() + 1)
			refResult:set({ text = { head = "No answer from the game", detail = "Check what was removed" }, untilAt = now + RESULT_SECONDS })
			resetToIdle()
		end
		-- Drop the result line when it expires.
		local rl = refResult:get()
		if rl ~= nil and now >= rl.untilAt then
			refResult:set(nil)
			bump()
		end

		-- Summarise Moved events instead of logging every one.
		local ml = refMoved:get()
		if ml.count > 0 and now - ml.lastAt >= MOVED_LOG_INTERVAL then
			logMsg("mouse Moved x" .. tostring(ml.count) .. " (with LMB held: " .. tostring(ml.withLmb)
				.. ", handled: " .. tostring(ml.handled) .. ")")
			refMoved:set({ count = 0, withLmb = 0, handled = 0, lastAt = now })
		end

		publishIfChanged()
	end)

	local onMouse = function(e : Gui.Mouse.Event) : boolean
		local T = api.gui.mouse.Event.Type
		local isLmb = e.button == 0
		local isRmb = e.button == 2
		if e.type == T.Moved then
			local ml = refMoved:get()
			ml.count = ml.count + 1
			if refLmbDown:get() then ml.withLmb = ml.withLmb + 1 end
			if e.handled then ml.handled = ml.handled + 1 end
			return false
		end
		local s = refSel:get()
		local consume = isLmb and (e.type == T.Pressed or e.type == T.Released)

		if isLmb and e.type == T.Pressed then
			if s ~= nil and s.phase == PHASE_COMMITTING then
				-- Nothing new starts while a commit runs.
				refLmbDown:set(false)
				refSkipRelease:set(true)
			else
				refSkipRelease:set(false)
				refLmbDown:set(true)
				if s ~= nil and s.phase == PHASE_SELECTED then
					-- Another stroke adds to the selection.
					s.phase = PHASE_PAINTING
				else
					-- New selection (the hover preview is dropped).
					refSel:set(newSelection(PHASE_PAINTING))
				end
				-- The next step takes the stroke's first sample at the cursor.
				refSample:set(nil)
				bump()
			end
		elseif isLmb and e.type == T.Released then
			local skipThis = refSkipRelease:get()
			refSkipRelease:set(false)
			refLmbDown:set(false)
			if skipThis then
				-- ignore: its press was cleared with RMB or came while a commit ran
			elseif s ~= nil and s.phase == PHASE_PAINTING then
				-- A plain click (released before a step sampled) still adds what is under the circle.
				local cur = cursorState:old()
				if refSample:get() == nil and cur ~= nil and not s.stroke.capped then
					takeSample(s, cur.x, cur.y, radiusState:old(), filtersState:old())
				end
				finishStroke(s)
			end
		elseif isRmb and (e.type == T.Pressed or e.type == T.PressedOutside) then
			-- RMB press: only remember where. In game (log 2026-10-07) RMB Pressed / Released never
			-- arrive here, only PressedOutside (press) and Clicked (release): the press is taken
			-- before the Selector (RMB is bound to IA_MENU_BACK / IA_BACK / IA_CLOSE_TOPMOST_WINDOW /
			-- IA_CONSTRUCTION_ACTION_CANCEL, research §12). Pressed is kept in case it ever arrives.
			refRmbPress:set({ x = e.x, y = e.y })
		elseif isRmb and (e.type == T.Clicked or e.type == T.Released) then
			-- RMB release: clears the selection, painted or waiting (nothing is removed), unless the
			-- mouse moved like a camera drag since the press. Released and Clicked may both come;
			-- the second finds nothing pending.
			local p = refRmbPress:get()
			refRmbPress:set(nil)
			local moved = 0
			if p ~= nil and e.x ~= nil and e.y ~= nil then
				moved = math.max(math.abs(e.x - p.x), math.abs(e.y - p.y))
			end
			if not hasPending() then
				logMsg(string.format("right click (%s): nothing selected", eventTypeName(e.type)))
			elseif moved > RMB_CLICK_MAX_PX then
				logMsg(string.format("right click (%s): moved %d px > %d (camera drag), selection kept",
					eventTypeName(e.type), moved, RMB_CLICK_MAX_PX))
			else
				logMsg(string.format("right click (%s): moved %d px%s -> clear",
					eventTypeName(e.type), moved, p == nil and " (no press seen)" or ""))
				cancelPending("right click")
				consume = true
			end
		end
		logMsg("mouse " .. eventTypeName(e.type) .. " button=" .. tostring(e.button)
			.. " handled=" .. tostring(e.handled) .. " -> return " .. tostring(consume)
			.. " (phase " .. (s ~= nil and s.phase or "none") .. ")")
		return consume
	end

	-- The cursor tooltip is minimal now: the selection lives in the toolbar status chip.
	local function tooltipText(s : Selection, r : number) : string
		local lines : {string} = { string.format("r = %d m", math.floor(r)) }
		if s ~= nil and (s.phase == PHASE_PAINTING or s.phase == PHASE_SELECTED) then
			lines[#lines + 1] = "Right-click clears the selection"
		end
		if s ~= nil and s.phase ~= PHASE_COMMITTING then
			-- Skip reasons stay here (small, for checking the filters); the kept counts are in the chip.
			for _, l in ipairs(sel.describe(s.stroke)) do
				if string.sub(l, 1, 8) == "Skipped:" or string.sub(l, 1, 6) == "Limit " then
					lines[#lines + 1] = l
				end
			end
			if s.truncated then lines[#lines + 1] = "Too many objects here, some were ignored" end
			if DEBUG_OCTREE and s.phase == PHASE_IDLE and s.rawEdges ~= nil then
				lines[#lines + 1] = string.format("octree at r: %d edges · %d constructions", s.rawEdges, s.rawCons)
			end
			if s.preview ~= nil and #s.preview.errors > 0 and s.phase ~= PHASE_IDLE then
				lines[#lines + 1] = "Game says: " .. s.preview.errors[1]
			end
		end
		return table.concat(lines, "\n")
	end

	local actionFn = function() : TreeNodeId
		local _ = versionState:old()   -- re-render on selection changes
		-- World-layer lifecycle (base: construction_react_util.tl:1355-1364). The menu swaps the
		-- action to another entry's (or its "default") when the tool is left (construction.tl:4489-4501),
		-- which unmounts this layer. An unmount not followed by a mount within LAYER_GONE_SECONDS
		-- clears the selection (here or in onStep), so a same-frame re-binding never does.
		react.onMount(function()
			pcall(function()
				local downAt = refLayerDownAt:get()
				refLayerDownAt:set(nil)
				if downAt ~= nil and os.clock() - downAt >= LAYER_GONE_SECONDS then
					logMsg("world layer mounted again")
					resetAll("tool switched", true)
				end
			end)
		end)
		react.onUnmount(function()
			pcall(function() refLayerDownAt:set(os.clock()) end)
		end)
		local cur = cursorState:old()
		local r = radiusState:old()
		local s = refSel:get()
		local phase = s ~= nil and s.phase or PHASE_IDLE
		local highlighted : {Engine.Entity} = {}
		if s ~= nil then highlighted = sel.entities(s.stroke) end
		local hlSet : {integer : boolean} = {}
		for _, e in ipairs(highlighted) do hlSet[e] = true end
		refHlSet:set(hlSet)

		-- Selection highlight (bb_highlight, research §11). The engine colours highlightedEntities
		-- (and the hovered entity) with the Selector selection colours; transparent ones hide it.
		local hc = hl.colors(phase)
		local selFill = api.type.Vec4f.new(0, 0, 0, 0)
		local selOutline = api.type.Vec4f.new(0, 0, 0, 0)
		local selOutline1 = api.type.Vec4f.new(0, 0, 0, 0)
		if hl.usesEngine(hl.MODE) then
			selFill = vec4(hc.fill)
			selOutline = vec4(hc.outline)
			selOutline1 = vec4(hc.outline1)
		end

		local children : {TreeNodeId} = {
			builtin.Selector{
				filter = function(entity : Engine.Entity) : boolean
					if entity == nil or entity < 0 then return false end
					-- Hover effect only where the highlight is (same colours), so an object the
					-- brush would not take never looks selected.
					if hl.HOVER_ONLY_HIGHLIGHTED then return refHlSet:get()[entity] == true end
					return api.engine.entityExists(entity)
				end,
				-- Consume the click so no entity window opens (overpass_probe.script.tl:4405-4430).
				onSelect = function(_e : Engine.Entity, _i : {integer}, _d : Gui.SelectionDetails) : boolean
					return true
				end,
				onProcessMouseEvent = onMouse,
				-- Rev 1 had these transparent (Overpass pattern, overpass_probe.script.tl:4500-4517),
				-- which also hid highlightedEntities: the selection was invisible in game.
				selectionColor = selFill,
				selectionOutlineColor = selOutline,
				selectionOutlineColor1 = selOutline1,
			},
		}

		-- Overlay lines / circles for the selection (cached per selection version + phase).
		local overlayEdges : {Builtin.Type.EdgeRenderable.Edge} = {}
		if hl.usesLines(hl.MODE) and s ~= nil and #highlighted > 0 then
			local key = tostring(versionState:old()) .. "/" .. phase .. "/" .. tostring(#highlighted)
			local ov = refOverlay:get()
			if ov == nil or ov.key ~= key then
				local ok, built = pcall(buildOverlay, s, phase, key)
				if ok then
					ov = built
				else
					logMsg("highlight overlay failed: " .. tostring(built))
					ov = { key = key, edges = {}, pieces = 0, markers = 0, truncated = false }
				end
				refOverlay:set(ov)
				if ov.truncated and phase ~= PHASE_IDLE and refTruncLogged:get() ~= s then
					refTruncLogged:set(s)
					logMsg(string.format("highlight overlay capped at %d pieces (%d line pieces, %d circles for %d objects)",
						hl.MAX_SEGMENTS, ov.pieces, ov.markers, #highlighted))
				end
			end
			overlayEdges = ov.edges
		end

		local bag : {Builtin.Type.EdgeRenderable.Edge} = {}
		for _, v in ipairs(overlayEdges) do bag[#bag + 1] = v end
		if cur ~= nil then
			-- White hover, red while painting, amber while the selection waits / is removed.
			local color = api.type.Vec4f.new(1, 1, 1, 0.7)
			if s ~= nil and s.phase == PHASE_PAINTING then
				color = api.type.Vec4f.new(1, 0.25, 0.2, 0.8)
			elseif s ~= nil and (s.phase == PHASE_SELECTED or s.phase == PHASE_COMMITTING) then
				color = api.type.Vec4f.new(1, 0.7, 0.1, 0.8)
			end
			for _, v in ipairs(ringEdges(cur.x, cur.y, r, color)) do bag[#bag + 1] = v end
			children[#children + 1] = builtin.ActionTooltip{
				recipe = constructionUi.SimpleTooltipRecipe,
				param = { message = { message = tooltipText(s, r) } },
			}
		end
		-- Only ONE EdgeRenderable per recipe: the engine asserts on more (overpass_probe.script.tl:4517-4519),
		-- so the ring and the selection overlay share it.
		if #bag > 0 then
			children[#children + 1] = builtin.EdgeRenderable{
				edges = bag,
				ignoreDepth = true,
			}
		end

		return builtin.ActionDescriptor{
			tool = "bulk-bulldozer-tool",
			crosshair = false,
			terrainCirclePolicy = "Never",
			highlightedEntities = highlighted,
			-- Back (ESC) clears the selection first; otherwise it leaves the tool as before.
			onBack = function()
				if hasPending() then cancelPending("back") else param.abort() end
			end,
			children = children,
		}
	end

	-- Keep focus on the tool, as the base selector-based tools do (construction_react_util.tl:1325-1327).
	react.setForceFocusable(true)
	react.setRestrictMouseFocus(true)

	if not param.isActive then return nil end
	param.setActionFn(actionFn, "BulkBulldozerAction")
	-- ESC: while something is selected it clears the selection (nothing removed). Otherwise, in mouse
	-- mode, it falls through and closes the construction window (construction_react_util.tl:1437-1441;
	-- useInputAction may be conditional, as the base does there).
	if hasPending() then
		react.useInputAction("IA_MENU_BACK", react.iaHandler(function() cancelPending("Esc") end))
	end
	return nil
end)

-- Toolbar status chip: the content of a disabled one-value Button (makeCompactButtonFn below).
-- A recipe as button content is base practice (cargofilter_window.tl:156, IconLabelIndicator →
-- BoxLayout, gui_react_util.tl:330-332); it returns a BoxLayout (memory: a recipe child must be a
-- layout) and re-renders itself, since the menu re-renders a param only when its value or
-- definition changes (construction.tl:1072-1092). Two TextViews, not a direct TextView child of
-- the button: the bar fixes those to 50 x 24 px (construction.css.lua:820-823).
local record StatusParam end
local BulkBulldozerStatus = react.RegisterRecipe("BulkBulldozerStatus", function(_param : StatusParam) : TreeNodeId
	local textState = react.useState({ head = g_status.head, detail = g_status.detail }) as ReactStateT<BulkBulldozerStatusText>
	local refSeen = react.useRef(g_status.version) as ReactRefT<integer>
	local function take(head : string, detail : string)
		local old = textState:old()
		if head == nil or detail == nil then return end
		if old == nil or old.head ~= head or old.detail ~= detail then
			textState:set({ head = head, detail = detail })
		end
	end
	react.onEvent(EV_STATUS, function(_name : string, payload : any)
		local ev = payload as StatusEvent
		if ev ~= nil then take(ev.head, ev.detail) end
	end)
	react.onStep(function()
		if g_status.version ~= refSeen:get() then
			refSeen:set(g_status.version)
			take(g_status.head, g_status.detail)
		end
	end)
	local t = textState:old()
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Vertical,
		children = {
			builtin.TextView{ meta = { class = "font-scale-body" }, text = t.head },
			builtin.TextView{ meta = { class = "font-scale-annotation" }, text = t.detail },
		},
	}
end)

-- Button label wrapped in a BoxLayout, so the bar's 50 px TextView rule (construction.css.lua:820-823)
-- doesn't clip it; the BoxLayout is centred by builtin.css.lua:178-182.
local function buttonLabel(label : string) : TreeNodeId
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = { builtin.TextView{ meta = { class = "font-scale-body" }, text = label } },
	}
end

-- UG erases the generic at this boundary (marketing_campaign_tool.script.tl:120-122).
local makeCustomAction = function<P>(recipe : Recipe<ConstructionCustomActionParams<P>>, customParam? : P) : ConstructionCustomAction<any>
	return { recipe = recipe as Recipe<ConstructionCustomActionParams<any>>, customParam = customParam }
end

local function alwaysEnabled(_params : {string : number}) : ConstructionMenuParam.CheckEnabledResult
	return "Enabled"
end

-- CheckBox: values {Off, On}, onChangeFn gets the 1-based index, 2 = checked
-- (overpass_probe.script.tl overpass_live_preview, research §1).
-- checkEnabledFn of the filter CheckBoxes and the status chip: the menu calls it with the params
-- map of the toolbar it shows, on every activation and change. Records the filter values in this
-- VM's memory and fires EV_SHOWN for the recipe (it may run in another Lua state, research §6).
-- Only the status chip's call fires (one event per menu update, not one per CheckBox).
local function noteShown(params : {string : number}, fire : boolean)
	pcall(function()
		local vals = sel.paramFilters(params, FILTER_KEY_OF)
		if next(vals) ~= nil then
			rememberShown(vals)
			if fire then api.gui.fireReactEvent(EV_SHOWN, { values = vals }) end
		end
	end)
end

local function filterEnabled(params : {string : number}) : ConstructionMenuParam.CheckEnabledResult
	noteShown(params, false)
	return "Enabled"
end

local function filterParam(fp : FilterParam, dflt : boolean) : ConstructionMenuParam
	return {
		key = fp.key,
		name = fp.name,
		tooltip = fp.tooltip,
		values = { _("Off"), _("On") },
		defaultIndex = dflt and 2 or 1,
		group = GROUP_FILTERS,
		uiType = api.type.enum.ScriptParamType.CheckBox,
		yearFrom = 0,
		yearTo = 0,
		location = api.type.enum.ScriptParamLocation.Toolbar,
		onChangeFn = function(newValue : number, menuApi : ConstructionMenuParamsAPI, oldValue? : number)
			if oldValue ~= nil and newValue == oldValue then return end
			local category : string = nil
			local shown : {string : boolean} = nil
			if menuApi ~= nil then
				local okC, c = pcall(function() : integer return menuApi.getCategory() end)
				if okC and c ~= nil then category = tostring(c) end
				local okP, p = pcall(function() : {string : number} return menuApi.getCurrentParams() end)
				if okP and p ~= nil then shown = sel.paramFilters(p, FILTER_KEY_OF) end
			end
			-- The toggled value itself is certain whatever getCurrentParams says.
			shown = shown or {}
			shown[fp.field] = newValue == 2
			api.gui.fireReactEvent(EV_FILTER, { field = fp.field, on = newValue == 2, category = category, shown = shown })
		end,
		checkEnabledFn = filterEnabled,
	}
end

local Ret = {
	getDefinition = function(constructionDefinition : ResName, _repository : ConstructionActionRepository, _params : {string : number}) : ConstructionDefinition
		local defaultRadiusIndex = brush.radiusIndex(brush.DEFAULT_RADIUS)
		local params : {ConstructionMenuParam} = {
			{
				key = KEY_RADIUS,
				name = _("Radius"),
				tooltip = _("Size of the brush."),
				values = brush.radiusLabels(),
				numbers = brush.RADII,
				defaultIndex = defaultRadiusIndex,
				uiType = api.type.enum.ScriptParamType.Slider,
				yearFrom = 0,
				yearTo = 0,
				location = api.type.enum.ScriptParamLocation.Toolbar,
				-- Slider with numbers: onChangeFn gets the number (overpass_probe.script.tl overpass_height).
				onChangeFn = function(newValue : number, _api : ConstructionMenuParamsAPI, oldValue? : number)
					if oldValue ~= nil and newValue == oldValue then return end
					api.gui.fireReactEvent(EV_RADIUS, { meters = newValue })
				end,
				checkEnabledFn = alwaysEnabled,
			},
			{
				-- [Bulldoze] [Clear] (user request 2026-10-07): two one-value Buttons with hideLabel
				-- in one `group` render side by side (construction.tl:2024-2074; same as the Overpass
				-- Builder presets, overpass_probe.script.tl:5677-5715). Every click runs onChangeFn
				-- (construction.tl changeParam calls it even when the value is unchanged; Overpass
				-- "Build", overpass_probe.script.tl:6105-6130). No oldValue guard on purpose.
				key = KEY_BULLDOZE,
				name = _("Bulldoze"),
				tooltip = _("Remove everything that is selected (highlighted). There is no undo."),
				values = { _("Bulldoze") },
				defaultIndex = 1,
				hideLabel = true,
				group = GROUP_ACTIONS,
				uiType = api.type.enum.ScriptParamType.Button,
				yearFrom = 0,
				yearTo = 0,
				location = api.type.enum.ScriptParamLocation.Toolbar,
				-- Label in a BoxLayout: unclipped (script_param_util.tl:403-405 uses this as the content).
				makeCompactButtonFn = function(_value : number) : TreeNodeId
					return buttonLabel(_("Bulldoze"))
				end,
				onChangeFn = function(_newValue : number, _api : ConstructionMenuParamsAPI, _oldValue? : number)
					api.gui.fireReactEvent(EV_BULLDOZE, {})
				end,
				checkEnabledFn = alwaysEnabled,
			},
			{
				key = KEY_CLEAR,
				name = _("Clear"),
				tooltip = _("Clear the selection without removing anything (same as a right click)."),
				values = { _("Clear") },
				defaultIndex = 1,
				hideLabel = true,
				group = GROUP_ACTIONS,
				uiType = api.type.enum.ScriptParamType.Button,
				yearFrom = 0,
				yearTo = 0,
				location = api.type.enum.ScriptParamLocation.Toolbar,
				makeCompactButtonFn = function(_value : number) : TreeNodeId
					return buttonLabel(_("Clear"))
				end,
				onChangeFn = function(_newValue : number, _api : ConstructionMenuParamsAPI, _oldValue? : number)
					api.gui.fireReactEvent(EV_CLEAR, {})
				end,
				checkEnabledFn = alwaysEnabled,
			},
			{
				-- Status chip under the buttons: a one-value Button kept "Disabled" (not clickable,
				-- grey; the Overpass Builder shows its build errors as disabled Buttons,
				-- overpass_probe.script.tl:6093-6098) whose content is the self-updating
				-- BulkBulldozerStatus recipe. No group: no separator between it and the buttons.
				key = KEY_STATUS,
				name = _("Selection"),
				tooltip = _("What is selected. Right-click or Clear empties the selection."),
				values = { _("Selection") },
				defaultIndex = 1,
				hideLabel = true,
				uiType = api.type.enum.ScriptParamType.Button,
				yearFrom = 0,
				yearTo = 0,
				location = api.type.enum.ScriptParamLocation.Toolbar,
				makeCompactButtonFn = function(_value : number) : TreeNodeId
					return BulkBulldozerStatus{}
				end,
				onChangeFn = function(_newValue : number, _api : ConstructionMenuParamsAPI, _oldValue? : number)
				end,
				checkEnabledFn = function(params : {string : number}) : ConstructionMenuParam.CheckEnabledResult
					noteShown(params, true)
					return "Disabled"
				end,
			},
		}
		local defaults = sel.defaultFilters() as {string : boolean}
		for _, fp in ipairs(FILTER_PARAMS) do
			params[#params + 1] = filterParam(fp, defaults[fp.field] == true)
		end
		return {
			resName = constructionDefinition,
			name = _("Bulk Bulldozer"),
			description = _("Bulldoze with a brush: paint to select everything under the circle that your filters allow, then press \"Bulldoze\" to remove it at the normal bulldoze cost. \"Clear\", right-click or Esc clears the selection."),
			icon = { icon = resolve("bulk_bulldozer.tga") },
			previewIcon = { icon = resolve("bulk_bulldozer_preview.tga") },
			availability = { yearFrom = 0, yearTo = 0 },
			action = "ACTION_CUSTOM",
			customAction = makeCustomAction(BulkBulldozerAction),
			constructions = {},
			categories = {},
			params = params,
			-- Order below the first year-gated entry so isActionActive(listIndex) matches
			-- (overpass_probe.script.tl:6181-6217, research §1).
			menuCategory = {
				categories = {
					{ category = "roads_tools", order = 5 },
					{ category = "rail_tools", order = 5 },
				},
			},
		}
	end,
}

return Ret
