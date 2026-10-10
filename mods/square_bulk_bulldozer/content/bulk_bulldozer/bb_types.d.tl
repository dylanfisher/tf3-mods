-- Bulk Bulldozer shared contract: the records the GUI recipe and the pure modules share.
-- Loaded as module "bulk_bulldozer.bb_types" (every content/**/*.d.tl; tools/tealrt.py def_modules).
-- Every global name is prefixed BulkBulldozer (globals are shared by all loaded mods).
-- Entities are plain integers here (Engine.Entity is `type Entity = integer`, engine.d.tl:13),
-- so the pure modules never touch engine types and are unit-testable with plain tables.

--- One piece of the brush ring: an arc of the circle with the terrain height at both ends.
--- Angles in radians, counter-clockwise from +x; heights in metres (world z).
global record BulkBulldozerRingArc
	startAngle : number
	angle : number
	length : number     -- arc length in metres (radius * angle)
	h0 : number         -- terrain height at startAngle
	h1 : number         -- terrain height at startAngle + angle
end

--- An edge's centre line in plan view: the cubic Hermite curve of BaseEdge position0/1 and
--- tangent0/1 (engine.d.tl:112-115), z dropped.
global record BulkBulldozerCurve
	p0x : number
	p0y : number
	t0x : number
	t0y : number
	p1x : number
	p1y : number
	t1x : number
	t1y : number
	-- heights (world z) of position0/1 and tangent0/1; optional (only the highlight lines use
	-- them, bb_highlight.curveZ; nil = take the terrain height)
	p0z : number
	t0z : number
	p1z : number
	t1z : number
end

--- The toolbar filters (PLAN "Filters"). true = that kind may be selected.
global record BulkBulldozerFilters
	roads : boolean          -- every street that is ours or has no PLAYER_OWNED (town roads,
	                         -- roads freed from street constructions); never another player's
	tracks : boolean         -- our edges without BASE_EDGE_STREET
	stations : boolean       -- our constructions with stations or depots
	assets : boolean         -- our other constructions (placed assets etc.)
	townBuildings : boolean  -- unowned constructions that are only town buildings
	underground : boolean    -- edges with BaseEdge.type == TUNNEL (any kind)
end

--- What we are (the local player) when classifying. -1 = unknown / none.
global record BulkBulldozerContext
	player : integer   -- api.engine.util.getPlayer()
	hq : integer       -- PLAYER.headquarters of that player
end

--- Plain copy of everything classification needs, read once by bb_gather (every getComponent
--- in pcall). Edge fields are set only when isEdge, construction fields only when not.
global record BulkBulldozerDesc
	entity : integer
	isEdge : boolean
	gone : boolean               -- no longer exists, or its main component could not be read
	full : boolean               -- every field read; false = only the light step (geometry / origin,
	                             -- bb_gather: owner, street, parentConstruction, industryRoad not yet)
	owner : integer              -- PLAYER_OWNED.player, -1 when the component is missing
	parentConstruction : integer -- edge: getConstructionEntityForEdge; construction: the owner of a
	                             -- subconstruction; -1 when none
	-- edge
	isStreet : boolean           -- has BASE_EDGE_STREET (no BASE_EDGE_TRACK type exists, research §4)
	isTunnel : boolean           -- BaseEdge.type == TUNNEL
	industryRoad : boolean       -- a segment that goes with an industry (findSegmentsToDelete) or
	                             -- ends on a node frozen in an industry construction
	objects : {integer}          -- BaseEdge.objects entities (signals, stops, waypoints)
	node0 : integer              -- BaseEdge.node0 / node1 (for the industry-node check)
	node1 : integer
	curve : BulkBulldozerCurve
	-- construction
	x : number                   -- transf translation (origin)
	y : number
	stations : integer           -- # of Construction.stations
	depots : integer
	industries : integer
	townBuildings : integer
	frozen : integer             -- # frozenEdges + # frozenNodes
end

global enum BulkBulldozerKind
	"road"           -- a street, ours or unowned (town roads included; user decision 2026-10-07)
	"track"          -- our track
	"station"        -- our station or depot construction
	"asset"          -- our other construction
	"town_building"  -- town building construction
	"industry"       -- industry construction (never kept)
	"other"          -- anything else (unowned track, landmark, mission prop; never kept)
end

global enum BulkBulldozerReason
	"gone"           -- entity vanished / unreadable
	"foreign"        -- PLAYER_OWNED by another player
	"part"           -- belongs to a construction (goes with it)
	"industry"       -- industry construction or industry road
	"hq"             -- our headquarters
	"not_player"     -- unowned and not a town road / town building
	"filtered"       -- its kind's toolbar filter is off
	"underground"    -- tunnel edge with "Underground" off
end

--- One classified hit. reason == nil means keep (will be bulldozed in Phase 3).
global record BulkBulldozerCandidate
	entity : integer
	kind : BulkBulldozerKind
	reason : BulkBulldozerReason
	objects : integer   -- edge objects that go with an edge (0 for constructions)
end

--- The selection: every sample of every stroke since it was last cleared or bulldozed.
global record BulkBulldozerStroke
	keep : {integer : BulkBulldozerCandidate}   -- entity → kept candidate
	order : {integer}                           -- kept entities in the order they were added
	skipped : {integer : BulkBulldozerReason}   -- entity → reason (unique entities)
	kindCounts : {string : integer}             -- kept per kind
	reasonCounts : {string : integer}           -- skipped per reason
	objects : integer                           -- edge objects riding along with kept edges
	capped : boolean                            -- a keep was refused because of the cap
end

-- Module: ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_brush.tl" as BulkBulldozerBrush
global record BulkBulldozerBrush
	RADII : {number}               -- toolbar slider steps in metres (PLAN "Radius")
	DEFAULT_RADIUS : number
	RING_ARCS : integer            -- arcs per ring (one EdgeRenderable edge each)
	SAMPLE_MIN_INTERVAL : number   -- seconds; a sample is due at least this often while the cursor moves
	SAMPLE_MOVE_FRACTION : number  -- or once the cursor moved this fraction of the radius
	EDGE_SAMPLES : integer         -- points along an edge curve for the touch test
	EDGE_MARGIN : number           -- metres added to the edge octree query radius
	SAMPLE_MAX_ENTITIES : integer  -- per octree query; more hits are ignored (cost bound)

	--- Slider labels for RADII, e.g. "20 m".
	radiusLabels : function() : {string}
	--- 1-based index of r in RADII, or nil.
	radiusIndex : function(r : number) : integer
	--- A slider value read back from the menu (metres) as a valid radius, or nil if it is not one.
	radiusFromParam : function(v : number) : number
	--- The ring as n arcs; heightAt(x, y) gives the terrain height (injected so this stays pure).
	ringArcs : function(cx : number, cy : number, r : number, n : integer,
		heightAt : function(number, number) : number) : {BulkBulldozerRingArc}
	--- Ring line width in metres for radius r (readable at small and large radii).
	ringWidth : function(r : number) : number
	--- Sample-throttle policy: true when the cursor moved >= r * SAMPLE_MOVE_FRACTION
	--- or dt >= SAMPLE_MIN_INTERVAL since the last sample.
	sampleDue : function(dx : number, dy : number, dt : number, r : number) : boolean
	--- Radius for the BASE_EDGE octree query: r + EDGE_MARGIN.
	edgeQueryRadius : function(r : number) : number
	--- Point on the curve at t in [0, 1].
	hermite : function(c : BulkBulldozerCurve, t : number) : number, number
	--- Distance from (px, py) to the segment (ax, ay)-(bx, by).
	pointSegmentDistance : function(px : number, py : number, ax : number, ay : number,
		bx : number, by : number) : number
	--- true when the curve comes within r of (cx, cy): EDGE_SAMPLES points, polyline distance.
	curveTouchesCircle : function(c : BulkBulldozerCurve, cx : number, cy : number, r : number) : boolean
	--- true when (px, py) is inside or on the circle.
	pointInCircle : function(px : number, py : number, cx : number, cy : number, r : number) : boolean
end

-- Module: ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_select.tl" as BulkBulldozerSelect
global record BulkBulldozerSelect
	STROKE_CAP : integer               -- kept entities per selection (PLAN: 400)
	CONSTRUCTION_ORIGIN_ONLY : boolean -- constructions hit only when their origin is in the circle
	KINDS : {BulkBulldozerKind}        -- display order
	REASONS : {BulkBulldozerReason}    -- display order

	defaultFilters : function() : BulkBulldozerFilters
	--- Filter field name of a toolbar CheckBox key suffix, e.g. "roads".
	FILTER_KEYS : {string}
	--- CheckBox value (1-based index: 2 = on, 1 = off) → boolean; anything else → dflt.
	checkboxOn : function(v : number, dflt : boolean) : boolean
	--- One menu CheckBox value → true (2) / false (1) / nil (unknown).
	paramValue : function(v : number) : boolean
	--- Filter values a toolbar params map certainly shows (keys: field → param key).
	paramFilters : function(params : {string : number}, keys : {string : string}) : {string : boolean}
	--- Filters to use from the last shown toolbar values, the toggles seen per menu category and
	--- the defaults; unknown fields are OFF and returned in the 2nd result.
	resolveFilters : function(shown : {string : boolean}, toggles : {string : {string : boolean}},
		defaults : BulkBulldozerFilters) : BulkBulldozerFilters, {string}
	--- Hard rules first, then filters. reason nil = keep.
	classify : function(d : BulkBulldozerDesc, f : BulkBulldozerFilters, ctx : BulkBulldozerContext) : BulkBulldozerCandidate
	newStroke : function() : BulkBulldozerStroke
	--- Merge one candidate; returns true when it became a new keep. Respects STROKE_CAP.
	add : function(s : BulkBulldozerStroke, c : BulkBulldozerCandidate) : boolean
	--- Take kept entities back out (Shift stroke); returns how many were removed.
	remove : function(s : BulkBulldozerStroke, entities : {integer}) : integer
	--- Number of kept entities.
	count : function(s : BulkBulldozerStroke) : integer
	--- Kept entities (for highlightedEntities), in add order.
	entities : function(s : BulkBulldozerStroke) : {integer}
	--- Log lines (English, also compared for change detection): kept per kind (+ edge objects),
	--- skipped per reason, cap note.
	describe : function(s : BulkBulldozerStroke) : {string}
	--- Translated tooltip lines: skipped per reason, cap note (none when nothing was skipped).
	skipLines : function(s : BulkBulldozerStroke) : {string}
end

--- Per-stroke cache of descriptors and industry protection (bb_gather). Plain tables.
global record BulkBulldozerGatherCache
	descs : {integer : BulkBulldozerDesc}
	industryRoads : {integer : boolean}   -- edge entity → protected
	industryCons : {integer : boolean}    -- industry construction already expanded
	conIsIndustry : {integer : boolean}   -- construction entity → has industries (node check)
	createdAt : number                    -- os.clock() at creation
end

--- One gather result (bb_gather.sample).
global record BulkBulldozerSampleResult
	candidates : {BulkBulldozerCandidate}  -- hits that touch the circle, classified
	edgeHits : integer                      -- octree BASE_EDGE results (before the touch test)
	conHits : integer                       -- octree CONSTRUCTION results
	truncated : boolean                     -- a query returned more than SAMPLE_MAX_ENTITIES
	seconds : number                        -- wall time of the sample (os.clock)
end

-- Module: ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_gather.tl" as BulkBulldozerGather
-- API layer (GUI thread only): octree queries → plain descriptors → bb_select.classify.
global record BulkBulldozerGather
	newCache : function() : BulkBulldozerGatherCache
	--- Our player and HQ (pcall; -1 when unreadable).
	context : function() : BulkBulldozerContext
	describeEdge : function(e : integer, cache : BulkBulldozerGatherCache) : BulkBulldozerDesc
	describeConstruction : function(e : integer, cache : BulkBulldozerGatherCache) : BulkBulldozerDesc
	--- One brush sample at (cx, cy) with radius r.
	sample : function(cx : number, cy : number, r : number, f : BulkBulldozerFilters,
		ctx : BulkBulldozerContext, cache : BulkBulldozerGatherCache) : BulkBulldozerSampleResult
end

-- Phase 3: commit path ------------------------------------------------------------------------

--- Split planner state (bb_batch). Items are entity ids; batches are sent one at a time.
global record BulkBulldozerBatchPlan
	queue : {{integer}}     -- batches still to send, front first
	cap : integer           -- most commands this plan may send
	sent : integer          -- commands reported so far
	done : {integer}        -- items of batches that succeeded
	failed : {integer}      -- single items that failed on their own
	capSkipped : {integer}  -- items never sent because the command cap ran out
end

-- Module: ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_batch.tl" as BulkBulldozerBatch
-- PURE: split-on-failure planner and orphan-node computation (PLAN "Commit and errors", "Orphan nodes").
global record BulkBulldozerBatch
	MAX_COMMANDS : integer   -- hard cap of commands per stroke (PLAN: 48)

	--- A plan that starts with all items in one batch.
	newPlan : function(items : {integer}, cap? : integer) : BulkBulldozerBatchPlan
	--- The next batch to send, or nil when the plan is finished. Once `sent` reaches `cap`,
	--- everything still queued moves to capSkipped and nil is returned.
	nextBatch : function(p : BulkBulldozerBatchPlan) : {integer}
	--- Report one sent command. success → items are done; failure → a single goes to failed,
	--- a larger batch is halved and both halves go to the front of the queue (order kept).
	report : function(p : BulkBulldozerBatchPlan, items : {integer}, success : boolean)
	--- The two halves of a list (first half gets the smaller part when odd).
	split : function(items : {integer}) : {integer}, {integer}
	--- Nodes left without any edge once `edgeEnds` ({node0, node1} per removed edge, edges
	--- unique) are gone. degree[n] = incident edges now (missing = unknown → kept);
	--- frozen[n] = owned by a construction → never. Sorted ascending.
	orphanNodes : function(edgeEnds : {{integer}}, degree : {integer : integer},
		frozen : {integer : boolean}) : {integer}
end

--- makeProposalData summary (bb_commit.preview).
global record BulkBulldozerPreview
	ok : boolean          -- every makeProposalData call returned data
	cost : integer        -- sum of ProposalData.costs (sign as the engine reports it); nil if unknown
	critical : boolean    -- any errorState.critical
	errors : {string}     -- unique errorState.messages
	seconds : number      -- wall time (os.clock)
end

--- Outcome of one commit (bb_commit.commit → onDone).
global record BulkBulldozerCommitResult
	requested : integer             -- entities handed to commit
	removed : integer               -- entities in successful commands
	skipped : integer               -- requested - removed
	reasons : {string : integer}    -- skip reason → count
	commands : integer              -- commands sent
	refused : string                -- set when nothing was sent (money, nothing left); else nil
	cost : integer                  -- preflight cost (nil if unknown)
	seconds : number                -- wall time from commit() to onDone (os.clock)
end

-- Module: ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_commit.tl" as BulkBulldozerCommit
-- API layer (GUI thread only): proposals, preflight, sendCommand with split retries.
global record BulkBulldozerCommit
	--- false (default) = the base two-step (constructions in a SimpleProposal first, then the
	--- edges through makeSegmentsRemoveProposal in the callback, industry_util.tl:560-601);
	--- true = ONE SimpleProposal with constructionsToRemove + streetProposal edges, edge objects
	--- and orphan nodes. Flip after the in-game test (TESTING §4).
	COMBINED_PROPOSAL : boolean
	--- true = the build Context carries our player and the GUI refundable entities, as the base
	--- player-initiated build does (bridge_and_tunnel.tl:187-194); false = a bare Context.new().
	CONTEXT_WITH_PLAYER : boolean
	--- Seconds between two previews while a stroke changes (≤ 4×/s).
	PREVIEW_INTERVAL : number

	--- Player balance (ACCOUNT on the player), nil when unreadable.
	balance : function() : integer
	--- Cost + errors of removing these entities, without sending anything.
	preview : function(edges : {integer}, cons : {integer}) : BulkBulldozerPreview
	--- Re-checks the hard rules on fresh descriptors right before sending. Returns the edges and
	--- constructions that still pass, plus entity → reason for the dropped ones. `industryRoads`
	--- carries the stroke's industry-road protection over (bb_gather cache).
	assertHardRules : function(edges : {integer}, cons : {integer}, ctx : BulkBulldozerContext,
		industryRoads : {integer : boolean}) : {integer}, {integer}, {integer : string}
	--- Removes the entities: preflight (unless `pre` is given), money check, then commands with
	--- split retries (MAX_COMMANDS). onDone runs once, possibly from a sendCommand callback.
	commit : function(edges : {integer}, cons : {integer}, ctx : BulkBulldozerContext,
		industryRoads : {integer : boolean}, pre : BulkBulldozerPreview,
		onDone : function(BulkBulldozerCommitResult), logFn : function(string))
end

-- Toolbar status (user request 2026-10-07: the selection shows in the panel, not the tooltip) ----

--- Two lines for the toolbar status chip: a headline and a detail line (both always set, so
--- the chip keeps its height while the content changes).
global record BulkBulldozerStatusText
	head : string
	detail : string
end

--- What the status chip describes (plain values; bb_status stays pure).
global record BulkBulldozerStatusInput
	phase : string                   -- "none" | "idle" (hover preview) | "painting" | "selected" | "committing"
	count : integer                  -- kept entities in the selection (or under the brush when idle)
	kindCounts : {string : integer}  -- kept per BulkBulldozerKind
	objects : integer                -- edge objects riding along
	cost : string                    -- formatted preview cost, nil when unknown
	capped : boolean                 -- the selection hit STROKE_CAP
	cap : integer                    -- STROKE_CAP
	result : BulkBulldozerStatusText -- a recent result / notice (shown instead of "Nothing selected"), or nil
end

-- Module: ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_status.tl" as BulkBulldozerStatus
-- PURE: the text of the toolbar status chip and of commit results.
global record BulkBulldozerStatus
	MAX_CHARS : integer       -- per line; longer lines are clipped with "..."
	MAX_KIND_PARTS : integer  -- kinds listed on the detail line before "..."

	--- "8 roads · 3 tracks · 1 asset" (+ signals/stops), at most MAX_KIND_PARTS parts.
	kindSummary : function(kindCounts : {string : integer}, objects : integer) : string
	--- Display width of s: 1 per character, 2 per CJK / Hangul / full-width character (U+3000 and up).
	width : function(s : string) : integer
	--- Clip s to at most n display columns (status.width; UTF-8 safe), appending "..." when clipped.
	clip : function(s : string, n : integer) : string
	--- Translated display text of a skip reason / refusal (English text from bb_commit); unknown
	--- reasons (the game's own error messages) are returned unchanged.
	reasonLabel : function(reason : string) : string
	--- The chip text with nothing selected (translated).
	idle : function() : BulkBulldozerStatusText
	--- The chip text for the current state.
	lines : function(v : BulkBulldozerStatusInput) : BulkBulldozerStatusText
	--- The chip text for a finished commit.
	resultLines : function(r : BulkBulldozerCommitResult) : BulkBulldozerStatusText
	--- Single-line form of a status text (log / tooltip).
	oneLine : function(t : BulkBulldozerStatusText) : string
end

-- Selection highlight (user report 2026-10-07: the selection was not visible in the world) -------

--- Colours of one highlight state as plain rgba {r, g, b, a} in [0, 1].
global record BulkBulldozerHighlightColors
	fill : {number}       -- Selector.selectionColor
	outline : {number}    -- Selector.selectionOutlineColor
	outline1 : {number}   -- Selector.selectionOutlineColor1
	line : {number}       -- overlay lines / construction markers (EdgeRenderable)
	lineWidth : number    -- overlay line width in metres
end

--- One straight piece of an overlay line (world coordinates).
global record BulkBulldozerSegment
	x0 : number
	y0 : number
	z0 : number
	x1 : number
	y1 : number
	z1 : number
end

-- Module: ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_highlight.tl" as BulkBulldozerHighlight
-- PURE: how the selection is shown in the world (engine tint, overlay lines or both).
global record BulkBulldozerHighlight
	MODE : string                    -- "engine" | "lines" | "both" (default)
	HOVER_ONLY_HIGHLIGHTED : boolean -- Selector filter accepts only highlighted entities
	MAX_SEGMENTS : integer           -- overlay pieces (lines + markers) per render
	SEGMENT_LENGTH : number          -- metres per piece
	MAX_PER_EDGE : integer           -- pieces per edge at most
	LINE_OFFSET_Z : number           -- metres above the edge
	MARKER_RADIUS : number           -- construction marker circle radius in metres

	usesEngine : function(mode : string) : boolean
	usesLines : function(mode : string) : boolean
	--- "idle" (hover preview) → light coral; any other phase (the selection) → red.
	colors : function(phase : string) : BulkBulldozerHighlightColors
	--- Upper bound of the curve length in plan view (Bezier control polygon).
	curveLength : function(c : BulkBulldozerCurve) : number
	--- Pieces for an edge of this length: ceil(length / SEGMENT_LENGTH) in [1, MAX_PER_EDGE].
	piecesFor : function(length : number) : integer
	--- Hermite height at t, nil when the curve has no z.
	curveZ : function(c : BulkBulldozerCurve, t : number) : number
	--- Straight pieces along all curves, at most maxSegments: over budget every edge gets fewer
	--- pieces (at least one), then trailing edges are dropped (truncated = true). Heights from the
	--- curve's z, else heightAt(x, y), else 0.
	edgeSegments : function(curves : {BulkBulldozerCurve}, maxSegments : integer,
		heightAt? : function(number, number) : number) : {BulkBulldozerSegment}, boolean
	--- The budget split edgeSegments uses: pieces per curve, how many curves fit, truncated.
	piecePlan : function(curves : {BulkBulldozerCurve}, maxSegments : integer) : {integer}, integer, boolean
	--- One curve cut into n straight pieces (heights as in edgeSegments).
	curveSegments : function(c : BulkBulldozerCurve, n : integer,
		heightAt? : function(number, number) : number) : {BulkBulldozerSegment}
	--- One log line naming the active path.
	describeMode : function(mode : string) : string
end
