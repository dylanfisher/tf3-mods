-- Stress Test "Junction test" (Towns tab), shown when square_roundabouts (Roundabouts & Interchanges)
-- is enabled: a test grid of towns (towns.createGrid, no town links) with one junction in the middle
-- of every cell, turned 45 deg so its arms point at the cell's four corner towns, and every arm linked
-- to its town by a straight road. Towns have no other road between them, so all town-to-town car
-- traffic drives through the junctions: one of each type (stress_logic.JUNCTION_CASES).
--
-- One serial job, one command in flight, in three stages:
--   1. towns: towns.createGrid (the Test grid's flow, same names "Grid A1", so Remove towns > Grid
--      towns removes them again);
--   2. junctions: built back to back (each waits for its own callback only), then one settle
--      (INLINE_SETTLE_MS) before every one's arms are read; per cell a SimpleProposal construction (fileName, params = global construction
--      params + the case's params + seed, transf turned 45 deg with every zero +0, docs/findings.md
--      "Negative zero"), pre-checked with makeProposalData and sent with makeWorldBuildProposalCmd
--      (as mods/square_roundabouts_showcase sc_engine.lua). square_roundabouts frees every node, so
--      the result is plain streets: the arm ends are the new street nodes near the cell centre with
--      one street edge (node diff before / after, read after the settle, minus the nodes a later
--      build added inside its own scan circle: laterOwns; resultEntities are only logged, res_nodes,
--      docs/findings.md "Stress Test probes" fifth run). Ends closer than ARM_GAP
--      are one arm (a highway's two one-way carriageways); each arm goes to the corner town in its
--      direction (stress_logic.assignArms);
--   3. links: per arm one street proposal to the town's best street node (stress_logic.rankTownNodes:
--      nearest to the arm, dead ends first, never on an earlier link road), split into pieces of at
--      most MAX_SEG. A single end continues with a copy of its own edge (BASE_EDGE + BASE_EDGE_STREET,
--      as stress_buslines' copiedSegment, probe 4: street from scratch works); a carriageway pair stays
--      a highway: both carriageways run on side by side, each in its own direction (one-way edges run
--      node0 -> node1), and meet in one node TOWN_MERGE before the town, joined to it by a short copy
--      of a large two-way street (the town node's own if large; town nodes on large streets are
--      preferred, stress_logic.rankTownNodes).
--      Both existing nodes (arm end, town node) are replaced by new ones (linkProposal: an existing
--      node keeps its old lane connections, a dead end none). A refused link tries the next town
--      node (NODE_TRIES).
--   In-line junctions (setting "In line" = As many as fit): before its town link, each arm gets as
--   many extra junctions on its line to the town as fit (stress_logic.inlineStops), every one another
--   layout (roads: INLINE_ROAD, highway arms: INLINE_HIGHWAY), turned so its through arms (local x)
--   lie on the line. All of them are built back to back, one more settle, their arms read, then each
--   route linked one after another (arm -> stop 1 -> ... -> town): a single end into a single end with linkProposal, two carriageways into two with
--   linkPairProposal. A refused stop is left out; a stop without both through arms, or a refused
--   link, ends that chain (logged).
-- Every step logs a [SQST] line; the summary lists built / refused junctions and linked arms.

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local bench = ug_require "square_stress_test::/stress/stress_bench.tl" as SquareStressBench
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime
local towns = ug_require "square_stress_test::/stress/gui/stress_towns.tl" as SquareStressTowns
local buslines = ug_require "square_stress_test::/stress/gui/stress_buslines.tl" as SquareStressBusLines
local slzones = ug_require "square_stress_test::/stress/gui/stress_slzones.tl" as SquareStressSlZones
local nc = ug_require "square_stress_test::/stress/gui/stress_nodecfg.tl" as SquareStressNodeCfg

local jn : SquareStressJunctions = {
	ui = { set = 1, spacing = 1, size = 2, centre = 1, streets = 2, inline = 1, lights = 1, traffic = 1 },
}

local TARGET_MOD <const> = "square_roundabouts"
local SCAN_R <const> = 520.0          -- new junction nodes are looked for this far from the cell centre (builds reach < 486 m;
                                      -- town streets start 0.71 x spacing - town radius away)
local ARM_GAP <const> = 45.0          -- arm ends closer than this are one arm (two carriageways, median + ramps)
local MAX_ARM_DEG <const> = 60.0      -- an arm is linked to the corner town at most this far off its direction
local TOWN_MERGE <const> = 60.0       -- a carriageway pair meets in one node this far before the town node
local TAPER <const> = 120.0           -- over this length before that node the carriageways close in
local MAX_SEG <const> = 200.0         -- link roads are split into pieces of at most this length
local TOWN_R <const> = 0.45           -- town nodes within spacing x this of the town centre may take a link
local NODE_TRIES <const> = 3          -- town nodes tried per arm
local READ_DELAY_MS <const> = 1000    -- arm ends are read this long after the build callback
local MAP_MARGIN <const> = 400.0       -- town centres stay this far inside the map (towns' land check probes 300 m)

local function str(v : any) : string
	return logic.listText(v)
end

local function z0(v : number) : number
	if v == 0 then return 0.0 end   -- -0 == 0: return +0
	return v
end

local function comp(e : integer, ct : Engine.ComponentType) : any
	local ok, c : boolean, any = pcall(api.engine.getComponent, e, ct)
	if not ok then return nil end
	return c
end

local function vec3(v : {number}) : Vec3f
	return api.type.Vec3f.new(z0(v[1]), z0(v[2]), z0(v[3] or 0))
end

local function heightAt(x : number, y : number) : number
	local ok, h = pcall(api.engine.terrain.getHeightAt, api.type.Vec2f.new(x, y))
	return ok and h ~= nil and h or 0.0
end

local function errText(data : any) : string
	local ok, s = pcall(function() : string
		local d = data as WorldBuildProposalCommandData
		local es = d.resultProposalData.errorState
		return string.format("critical=%s messages=%s", tostring(es.critical), str(es.messages))
	end)
	return ok and s or "(no error state)"
end

---------------------------------------------------------------------------
-- square_roundabouts present?

local resolved : {string : string} = {}   -- file -> resource name ("" = not found)

--- The construction resource name of a square_roundabouts file, nil when it isn't loaded (the
--- showcase's candidates: with "::/" first).
local function resolve(file : string) : string
	if resolved[file] == nil then
		resolved[file] = ""
		-- our own constructions (the Crossings set's test crossing) by our mod, the rest square_roundabouts'
		local names : {string} = { TARGET_MOD .. "::/" .. logic.JUNCTION_DIR .. file, TARGET_MOD .. "::" .. logic.JUNCTION_DIR .. file,
			logic.JUNCTION_DIR .. file }
		if file:sub(1, #"square_stress_test") == "square_stress_test" then names = { "square_stress_test::/" .. logic.JUNCTION_DIR .. file } end
		for _, name in ipairs(names) do
			local ok, id = pcall(function() : integer return api.res.constructionRep.find(name) end)
			if ok and type(id) == "number" and id >= 0 then
				resolved[file] = name
				break
			end
		end
	end
	local r = resolved[file]
	return r ~= "" and r or nil
end

local availableAnswer : boolean = nil

function jn.available() : boolean
	if availableAnswer == nil then
		availableAnswer = resolve(logic.JUNCTION_CASES[1].file) ~= nil
	end
	return availableAnswer
end

---------------------------------------------------------------------------
-- Labels

local function selectedCases() : {SquareStressJunctionCase}
	return logic.junctionCases(logic.JUNCTION_SETS[jn.ui.set] or logic.JUNCTION_SETS[1])
end

local function selectedSpacing() : number
	return logic.JUNCTION_SPACINGS[jn.ui.spacing] or logic.JUNCTION_SPACINGS[1]
end

function jn.label() : string
	return logic.junctionLabel(#selectedCases(), selectedSpacing())
end

function jn.caseNames() : string
	local names : {string} = {}
	for i, c in ipairs(selectedCases()) do names[i] = c.label end
	local cols, rows = logic.junctionGrid(#names)
	return string.format("%s. Towns: %d x %d grid.", table.concat(names, ", "), cols, rows)
end

function jn.uiSignature() : string
	local u = jn.ui
	return string.format("%d/%d/%d/%d/%d/%d/%d/%d", u.set, u.spacing, u.size, u.centre, u.streets, u.inline, u.lights, u.traffic)
end

---------------------------------------------------------------------------
-- Engine reads

-- The octree matches an edge by one point of it (most likely its midpoint), not by its extent
-- (docs/findings/roads.md "Octree edge search matches the edge's position, not its extent"): a node within
-- r is found only through an edge whose point lies within r + half that edge. So the query reaches this
-- much further (street edges up to 2 x this long: town grid blocks ~80 m, link pieces MAX_SEG 200 m,
-- junction arms and ramps) and the nodes are then kept by their own position.
local EDGE_HALF <const> = 200.0

local function nodePos(n : integer) : {number}
	local bn = comp(n, api.type.ComponentType.BASE_NODE) as Engine.Component.BaseNode
	if bn == nil then return nil end
	return { bn.position.x, bn.position.y, bn.position.z }
end

--- Street nodes within r of (x, y) (by their position; see EDGE_HALF): node -> true. Before / after
--- snapshots with this compare exactly the nodes inside the circle: an old node that a new edge reaches
--- is never taken for a new one, and a node inside is never missed because its streets are long.
local function nodesNear(x : number, y : number, r : number) : {integer : boolean}
	local out : {integer : boolean} = {}
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r + EDGE_HALF, api.type.ComponentType.BASE_EDGE)
	if not ok or list == nil then return out end
	local seen : {integer : boolean} = {}
	local r2 = r * r
	for _, e in ipairs(list as {integer}) do
		if comp(e, api.type.ComponentType.BASE_EDGE_STREET) ~= nil then
			local be = comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
			if be ~= nil then
				for _, n in ipairs({ be.node0, be.node1 }) do
					if not seen[n] then
						seen[n] = true
						local p = nodePos(n)
						if p ~= nil and (p[1] - x) ^ 2 + (p[2] - y) ^ 2 <= r2 then out[n] = true end
					end
				end
			end
		end
	end
	return out
end

local function streetMap() : {integer : {integer}}
	local ok, m = pcall(api.engine.system.streetSystem.getNode2StreetEdgeMap)
	if not ok or m == nil then return {} end
	return m as {integer : {integer}}
end

local function inConstruction(n : integer) : boolean
	local ok, con = pcall(api.engine.system.streetConnectorSystem.getConstructionEntityForNode, n)
	return not ok or con == nil or con >= 0
end

---------------------------------------------------------------------------
-- Proposals

local function context() : Context
	local ok, c = pcall(function() : Context
		local ctx = api.type.Context.new()
		ctx.player = rt.player()
		ctx.checkTerrainAlignment = true
		ctx.cleanupStreetGraph = false
		ctx.gatherBuildings = true
		ctx.gatherFields = true
		return ctx
	end)
	return ok and c or nil
end

-- Component types that name an entity a check collided with that is no building, edge or construction.
local OTHER_KINDS : {string} = { "BASE_NODE", "SUBCONSTRUCTION", "ASSET_GROUP", "FIELD", "MODEL_INSTANCE_LIST", "EDGE_OBJECT",
	"BRIDGE", "INDUSTRY", "TOWN", "ANIMAL", "TERRAIN" }
local OTHER_PROBES <const> = 20   -- unknown entities per collision list probed for OTHER_KINDS

--- " (hits 3 town buildings, 2 streets)" from a proposal's collision info, "" without any. A kind whose list
--- names an entity more than once says how many distinct ones ("12 other BASE_NODE (3 distinct) e.g. #9092");
--- labels (entity -> what it is to the caller) adds "; known: #9092 left far node, ..." for the hits it names.
local function collisionText(pd : ProposalData, labels? : {integer : string}) : string
	local ok, s = pcall(function() : string
		local ci = pd.collisionInfo
		if ci == nil or ci.collisionEntities == nil or #ci.collisionEntities == 0 then return "" end
		local CT = api.type.ComponentType
		local counts : {string : integer} = {}
		local order : {string} = {}
		local first : {string : integer} = {}
		local distinct : {string : integer} = {}
		local seen : {integer : boolean} = {}
		local known : {string} = {}
		-- the other kinds' component types, resolved once; only the first OTHER_PROBES unknown entities
		-- are probed for them (a big collision list costs at most that many x #OTHER_KINDS reads)
		local others : {{any}} = {}
		for _, ct in ipairs(OTHER_KINDS) do
			local okT, t = pcall(function() : Engine.ComponentType return (CT as {string : Engine.ComponentType})[ct] end)
			if okT and t ~= nil then others[#others + 1] = { ct, t } end
		end
		local probed = 0
		for _, d in ipairs(ci.collisionEntities) do
			local e = d.entity
			local kind = "other"
			if comp(e, CT.TOWN_BUILDING) ~= nil then kind = "town buildings"
			elseif comp(e, CT.BASE_EDGE_STREET) ~= nil then kind = "streets"
			elseif comp(e, CT.BASE_EDGE) ~= nil then kind = "tracks"
			elseif comp(e, CT.CONSTRUCTION) ~= nil then kind = "constructions"
			elseif probed < OTHER_PROBES then
				-- name what else it is (2026-10-12 Showcase: "hits 12 other" with no clue)
				probed = probed + 1
				for _, o in ipairs(others) do
					if comp(e, o[2] as Engine.ComponentType) ~= nil then
						kind = "other " .. tostring(o[1])
						break
					end
				end
			end
			if counts[kind] == nil then
				counts[kind] = 0
				distinct[kind] = 0
				order[#order + 1] = kind
				first[kind] = e
			end
			counts[kind] = counts[kind] + 1
			if not seen[e] then
				seen[e] = true
				distinct[kind] = distinct[kind] + 1
				if labels ~= nil and labels[e] ~= nil and #known < 8 then known[#known + 1] = string.format("#%s %s", tostring(e), labels[e]) end
			end
		end
		local parts : {string} = {}
		for _, k in ipairs(order) do
			parts[#parts + 1] = string.format("%d %s%s%s", counts[k], k, distinct[k] < counts[k] and string.format(" (%d distinct)", distinct[k]) or "",
				k:sub(1, 5) == "other" and string.format(" e.g. #%s", tostring(first[k])) or "")
		end
		return " (hits " .. table.concat(parts, ", ") .. (#known > 0 and ("; known: " .. table.concat(known, ", ")) or "") .. ")"
	end)
	return ok and s or ""
end

--- "ok", the first error message / "critical" (with what it hits; labels: collisionText's), or nil when
--- makeProposalData is unavailable.
local function precheck(proposal : SimpleProposal, ctx : Context, labels? : {integer : string}) : string
	local okU, util = pcall(function() : UtilProposal return api.engine.util.proposal end)
	if not okU or util == nil or util.makeProposalData == nil then return nil end
	local validate = util.makeProposalData as function(SimpleProposal, Context) : ProposalData
	local ok, pd = pcall(validate, proposal, ctx)
	if not ok or pd == nil then return nil end
	local okE, reason = pcall(function() : string
		local es = pd.errorState
		if es == nil then return nil end
		local r : string = nil
		if es.messages ~= nil and #es.messages > 0 then r = tostring(es.messages[1])
		elseif es.critical then r = "critical" end
		if r == nil then return "ok" end
		return r .. collisionText(pd, labels)
	end)
	return okE and reason or nil
end

--- The placement transform at (x, y) on the terrain, turned by `angle` (radians; local x -> that
--- direction), every zero +0.
local function junctionTransf(x : number, y : number, angle : number) : Mat4f
	local c, sn = math.cos(angle), math.sin(angle)
	local V = api.type.Vec4f.new
	return api.type.Mat4f.new(V(z0(c), z0(sn), 0.0, 0.0), V(z0(-sn), z0(c), 0.0, 0.0), V(0.0, 0.0, 1.0, 0.0),
		V(z0(x), z0(y), z0(heightAt(x, y)), 1.0))
end

local function globalParams() : {string : number}
	local out : {string : number} = {}
	local ok, g = pcall(api.engine.util.construction.getGlobalConstructionParams)
	if ok and g ~= nil then
		pcall(function() for k, v in pairs(g as {string : number}) do out[k] = v end end)
	end
	return out
end

local function junctionProposal(file : string, case_ : SquareStressJunctionCase, x : number, y : number, seed : integer, angle : number) : SimpleProposal
	local params = globalParams()
	for k, v in pairs(case_.params) do params[k] = v end
	params.seed = seed
	local proposal = api.type.SimpleProposal.new()
	local ce = api.type.SimpleProposal.ConstructionEntity.new()
	ce.fileName = file
	ce.params = params
	ce.transf = junctionTransf(x, y, angle)
	ce.playerEntity = rt.player()
	ce.name = "SQST " .. case_.label
	proposal.constructionsToAdd = { ce }
	return proposal
end

--- A straight street segment with srcEdge's BASE_EDGE / BASE_EDGE_STREET (template, lanes), plain
--- ground type, no objects.
local function segment(id : integer, srcEdge : integer, n0 : integer, n1 : integer, p0 : {number}, p1 : {number}) : Proposal.SegmentAndEntity
	local t = { p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3] }
	local seg = api.type.SegmentAndEntity.new()
	seg.entity = id
	seg.type = 0
	seg.comp = api.engine.getComponent(srcEdge, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
	seg.streetEdge = api.engine.getComponent(srcEdge, api.type.ComponentType.BASE_EDGE_STREET) as Engine.Component.BaseEdgeStreet
	seg.comp.node0 = n0
	seg.comp.node1 = n1
	seg.comp.position0 = vec3(p0)
	seg.comp.position1 = vec3(p1)
	seg.comp.tangent0 = vec3(t)
	seg.comp.tangent1 = vec3(t)
	seg.comp.objects = {}
	pcall(function()
		local c = seg.comp as {string : any}
		c["type"] = 0
		c["typeIndex"] = -1
	end)
	return seg
end

---------------------------------------------------------------------------
-- Arms

--- One arm end of a built junction: its node, its only street edge, and whether traffic on that
--- edge drives towards the end (the edge's node1).
local record ArmEnd
	node : integer
	edge : integer
	pos : {number}
	out : boolean
	dir : {number}                -- unit vector from its edge's other node to it (the arm's heading); nil: unknown
end

local record Arm
	ends : {ArmEnd}
	x : number
	y : number
	jx : number                   -- junction (cell) centre
	jy : number
	town : integer                -- town entity
	townPos : {number}
	townName : string
	townR : number                -- Showcase: town nodes within this of the town centre may take its link
	townHalf : number             -- Showcase: half its town's street grid (its nodes: within the square + OWN_TOWN_MARGIN)
	cell : string
	corner : integer              -- Junction test: the cell corner (1..4, junctionCells' order) of its town
	caseLabel : string
	tried : {integer : boolean}   -- town nodes already refused
	try : integer
	collided : boolean            -- Showcase: a link of it was refused with a collision (later tries: nearest node, along the arm)
	entryNode : integer           -- Lights showcase: its town's entry roundabout's outward arm end (the link's target; nil: none)
	entryPos : {number}
	linkLanes : integer           -- bench: the link's road lanes (0: the arm's own; nil: the spec's linkLanes)
	pairLanes : integer           -- bench: a highway arm's merge piece lanes (nil: 6)
end

--- One build's scan circle and the street nodes in it just before the build (its `before`), kept in
--- send order so a read can tell its own new nodes from a later build's.
local record Scan
	x : number
	y : number
	r : number
	before : {integer : boolean}
end

--- An in-line junction on an arm's line to its town.
local record Stop
	pos : {number}
	case_ : SquareStressJunctionCase
	built : boolean
	linkTries : integer           -- refused links into it so far
	back : Arm                    -- its arm towards the cell junction
	front : Arm                   -- its arm towards the town
	-- set by its build, used when its arms are read after the settle
	prev : {number}               -- the points its through arms point at (the neighbours on the route)
	nxt : {number}
	scanR : number
	before : {integer : boolean}  -- street nodes near it before the build
	seq : integer                 -- its scan in JunctionState.scans
	res : {integer : boolean}     -- its build's result entities (log evidence)
	ms : number                   -- build time (send to callback)
end

--- An arm's route to its town through its in-line junctions.
local record Chain
	main : Arm                    -- the cell junction's arm (carries the town fields)
	stops : {Stop}
	tail : Arm                    -- where the next link starts
	broken : boolean
end

local record Task
	-- "build" (cell k), "settle", "read" (cell k's arms), "plan", "inline" (build stop k), "sread" (stop k's
	-- arms), "clink" (to stop k) or "link" (to the town)
	kind : string
	cell : SquareStressJunctionCell
	case_ : SquareStressJunctionCase
	arm : Arm                     -- link: the arm (nil: the chain's tail)
	chain : Chain
	k : integer                   -- settle: 1 after the cell junctions, 2 after the in-line stops
end

--- A cell junction built in the build phase, its arms read after the settle.
local record Placed
	before : {integer : boolean}
	seq : integer                             -- its scan in JunctionState.scans
	res : {integer : boolean}                 -- its build's result entities (log evidence)
	ms : number
end

--- One Junction test run's counters and lists.
local record JunctionState
	placed : {integer : Placed}               -- cell index -> its build
	scans : {Scan}                            -- every junction build's scan, in send order (newEnds)
	stopTasks : {Task}                        -- planned by the reads, queued by "plan"
	readTasks : {Task}
	linkTasks : {Task}
	avoid : {{{number}}}                      -- our link roads (2D start, end)
	built : integer
	refused : integer
	linked : integer
	unlinked : integer
	inBuilt : integer
	inRefused : integer
	stopCount : integer                       -- in-line junctions built (Lights: every other one)
	nextVariant : {string : integer}
	notes : {string}
	problems : {string}                       -- for the warning dialog after the summary
	linkedOf : {string : {integer : boolean}} -- cell name -> corners whose route reached the town
end

--- Whether one of the edges carries edge objects (a stop): a link replaces its node's edges by
--- copies without objects, so such a node is never used.
local function hasObjects(list : {integer}) : boolean
	for _, e in ipairs(list or {}) do
		local be = comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
		if be ~= nil and be.objects ~= nil and #be.objects > 0 then return true end
	end
	return false
end

--- Whether a street edge is a large two-way street (its BaseEdge.roadTemplate, logic.isLargeStreet);
--- false when the template can't be read.
local function isLargeEdge(e : integer) : boolean
	local be = comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
	if be == nil then return false end
	local ok, t = pcall(function() : string return tostring(be.roadTemplate) end)
	return ok and logic.isLargeStreet(t)
end

local function anyLarge(list : {integer}) : integer
	for _, e in ipairs(list or {}) do
		if isLargeEdge(e) then return e end
	end
	return nil
end

--- Street nodes of the town near (tx, ty) a link may end at (not ours, not in a construction, no stop).
local function townNodes(tx : number, ty : number, r : number, ours : {integer : boolean}, map : {integer : {integer}}) : {SquareStressNodeCand}
	local out : {SquareStressNodeCand} = {}
	for n in pairs(nodesNear(tx, ty, r)) do
		if not ours[n] and not inConstruction(n) and not hasObjects(map[n]) then
			local p = nodePos(n)
			if p ~= nil then
				out[#out + 1] = { id = n, x = p[1], y = p[2], z = p[3], deg = #(map[n] or {}), large = anyLarge(map[n]) ~= nil, score = 0 }
			end
		end
	end
	return out
end

--- A copy of node's lane configuration with old -> new edge ids (remove + add, as the Crossing Tool:
--- never a remove alone). Lane connections read from a node are read-only, so they are rebuilt with
--- api.type.LaneConnection.new() (docs/findings.md "Junction lane connections"; plain tables when the
--- constructor is missing). nil when the node has no configuration.
local function repointedConfig(node : integer, newIds : {integer : integer}) : Proposal.BaseNodeLaneConnectionAndEntity
	return (rt.nodeConfigEntry(node, newIds, nil))
end

--- An edge to add: a copy of src (BASE_EDGE + BASE_EDGE_STREET) between two node refs, its own
--- geometry kept (copy) or straight from p0 to p1. Refs: existing node ids >= 0, new nodes -k.
local record EdgeSpec
	src : integer
	n0 : integer
	n1 : integer
	copy : boolean
	p0 : {number}
	p1 : {number}
	template : string             -- a new piece of this street template instead of src's (Showcase links: country roads)
end

--- Collects the nodes and edges of one link proposal (temp refs: existing nodes >= 0, new ones -k).
local record Builder
	map : {integer : {integer}}
	newNodes : {{number}}                        -- positions; ref -k
	specs : {EdgeSpec}
	removeEdges : {integer}
	removeNodes : {integer}
	repoint : {integer : {integer : integer}}    -- far node -> old edge -> spec index
	replaced : {integer : integer}               -- new node ref -> the existing node it replaces
	copyOf : {integer : {integer : integer}}     -- new node ref -> old edge -> spec index of its copy
	lock : boolean                               -- every added edge roadDevelopmentLocked (Showcase towns)
	template : string                            -- straight pieces of this street template (nil: copies of their src)
	ghosts : {integer : SquareStressLightGhost}  -- replaced node -> the lit leg an earlier proposal removed there (town entries)
end

local function newBuilder() : Builder
	return { map = streetMap(), newNodes = {}, specs = {}, removeEdges = {}, removeNodes = {}, repoint = {}, replaced = {}, copyOf = {},
		ghosts = {} }
end

local function addNode(b : Builder, p : {number}) : integer
	b.newNodes[#b.newNodes + 1] = p
	return -#b.newNodes
end

--- Replaces node x by a new node at its spot and its edges by copies ending there (see linkProposal).
local function replaceNode(b : Builder, x : integer) : integer, {number}
	local pos = nodePos(x)
	local ref = addNode(b, pos)
	b.replaced[ref] = x
	b.copyOf[ref] = {}
	for _, e in ipairs(b.map[x] or {}) do
		local be = comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
		b.specs[#b.specs + 1] = { src = e, n0 = be.node0 == x and ref or be.node0, n1 = be.node1 == x and ref or be.node1, copy = true }
		b.removeEdges[#b.removeEdges + 1] = e
		local y = be.node0 == x and be.node1 or be.node0
		b.repoint[y] = b.repoint[y] or {}
		b.repoint[y][e] = #b.specs
		b.copyOf[ref][e] = #b.specs
	end
	b.removeNodes[#b.removeNodes + 1] = x
	return ref, pos
end

--- Straight copies of src from (refA, pA) to (refB, pB) in pieces of at most MAX_SEG, on the terrain;
--- driving A -> B when forward, else B -> A (one-way carriageways).
local function straight(b : Builder, src : integer, refA : integer, pA : {number}, refB : integer, pB : {number}, forward : boolean)
	local pts = logic.linePoints(pA, pB, MAX_SEG)
	local prevRef, prevPos = refA, pA
	for k = 2, #pts do
		local ref : integer
		local p = pts[k]
		if k == #pts then
			ref, p = refB, pB
		else
			p = { p[1], p[2], heightAt(p[1], p[2]) }
			ref = addNode(b, p)
		end
		if forward then
			b.specs[#b.specs + 1] = { src = src, n0 = prevRef, n1 = ref, p0 = prevPos, p1 = p, template = b.template }
		else
			b.specs[#b.specs + 1] = { src = src, n0 = ref, n1 = prevRef, p0 = p, p1 = prevPos, template = b.template }
		end
		prevRef, prevPos = ref, p
	end
end

--- As straight, through one more point `via` (2D; nil: straight).
local function straightVia(b : Builder, src : integer, refA : integer, pA : {number}, refB : integer, pB : {number}, forward : boolean,
		via : {number})
	if via == nil then
		straight(b, src, refA, pA, refB, pB, forward)
		return
	end
	local vp = { via[1], via[2], heightAt(via[1], via[2]) }
	local vRef = addNode(b, vp)
	straight(b, src, refA, pA, vRef, vp, forward)
	straight(b, src, vRef, vp, refB, pB, forward)
end

--- Makes a new piece one of street template `path` (its lanes and style; as stress_buslines' depot stub):
--- a Showcase link's country road. Left as copied when the template can't be read.
local function setTemplate(seg : Proposal.SegmentAndEntity, path : string)
	local ok, tpl = pcall(function() : StreetTemplate return api.res.streetTemplateRep.get(api.res.streetTemplateRep.find(path)) end)
	if not ok or tpl == nil then return end
	seg.comp.roadTemplate = path
	seg.comp.laneConfigs = tpl.laneConfigs
	seg.comp.roadStyle = tpl.streetStyle
end

--- Road lanes (both ways together) of a two-way street edge: its lanes minus the two sidewalks, when
--- they run both ways; nil for a one-way edge (a highway carriageway, a one-way street) or unreadable.
local function twoWayLanes(e : integer) : integer
	local ok, n = pcall(function() : integer
		local be = comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
		local lc = be.laneConfigs
		if lc == nil or #lc < 4 then return nil end
		local fwd, back = 0, 0
		for k = 2, #lc - 1 do
			if lc[k].forward then fwd = fwd + 1 else back = back + 1 end
		end
		if fwd == 0 or back == 0 then return nil end
		return fwd + back
	end)
	return ok and n or nil
end

--- The street template of a Showcase link's new pieces: the country road of the arm edge's lanes
--- (logic.countryTemplate, the game year's era); nil (copies of the arm) for a one-way arm.
local function countryOf(e : integer) : string
	local okY, y = pcall(api.engine.util.getYear)
	return logic.countryTemplate(twoWayLanes(e), (okY and type(y) == "number") and math.floor(y as number) or nil)
end

--- The SimpleProposal of a builder.
local function assemble(b : Builder) : SimpleProposal
	local CT = api.type.ComponentType
	-- Temp ids: edges -1, -2, ... first, then the new nodes after them (stress_buslines' connectProposal).
	local nEdges = #b.specs
	local function realId(ref : integer) : integer
		if ref >= 0 then return ref end
		return -(nEdges + (-ref))
	end
	local nodes : {Proposal.NodeAndEntity} = {}
	for k, p in ipairs(b.newNodes) do
		local ne = api.type.NodeAndEntity.new()
		ne.entity = realId(-k)
		ne.comp.position = vec3(p)
		nodes[#nodes + 1] = ne
	end
	local edges : {Proposal.SegmentAndEntity} = {}
	for k, sp in ipairs(b.specs) do
		if sp.copy then
			local seg = api.type.SegmentAndEntity.new()
			seg.entity = -k
			seg.type = 0
			seg.comp = api.engine.getComponent(sp.src, CT.BASE_EDGE) as Engine.Component.BaseEdge
			seg.streetEdge = api.engine.getComponent(sp.src, CT.BASE_EDGE_STREET) as Engine.Component.BaseEdgeStreet
			seg.comp.node0 = realId(sp.n0)
			seg.comp.node1 = realId(sp.n1)
			seg.comp.objects = {}
			edges[#edges + 1] = seg
		else
			edges[#edges + 1] = segment(-k, sp.src, realId(sp.n0), realId(sp.n1), sp.p0, sp.p1)
			if sp.template ~= nil then setTemplate(edges[#edges], sp.template) end
		end
		-- Showcase towns: no town grows streets off the link either (stress_towns "Town growth locked
		-- into the grid"); the copies of the town's own (locked) edges stay locked anyway
		if b.lock then edges[#edges].comp.roadDevelopmentLocked = true end
	end
	local cfgRemove : {integer} = {}
	local cfgAdd : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
	for y, olds in pairs(b.repoint) do
		local newIds : {integer : integer} = {}
		for old, k in pairs(olds) do newIds[old] = -k end
		local entry = repointedConfig(y, newIds)
		if entry ~= nil then
			cfgRemove[#cfgRemove + 1] = y
			cfgAdd[#cfgAdd + 1] = entry
		end
	end
	-- Every other node of the link gets a config too (script-made nodes get none, and such a node can
	-- crash the simulation: docs/findings/roads.md "Script link roads without node configs"): a replaced
	-- node's new node carries the old node's config over to the copies plus the pattern for the link's
	-- piece (nc.configs seeds), the link's own new nodes (pieces, merge node) the engine pattern per
	-- segment and direction, far nodes without a config a fresh one.
	local seeds : {integer : SquareStressNodeSeed} = {}
	for ref, x in pairs(b.replaced) do
		local newIds : {integer : integer} = {}
		for old, k in pairs(b.copyOf[ref] or {}) do newIds[old] = -k end
		seeds[realId(ref)] = { node = x, newIds = newIds, ghost = b.ghosts ~= nil and b.ghosts[x] or nil }
	end
	nc.complete(edges, b.removeEdges, cfgAdd, cfgRemove, seeds)
	local proposal = api.type.SimpleProposal.new()
	proposal.streetProposal.nodesToAdd = nodes
	proposal.streetProposal.edgesToAdd = edges
	proposal.streetProposal.edgesToRemove = b.removeEdges
	proposal.streetProposal.nodesToRemove = b.removeNodes
	proposal.streetProposal.nodeConfigsToRemove = cfgRemove
	proposal.streetProposal.nodeConfigsToAdd = cfgAdd
	return proposal
end

local LARGE_SRC_R <const> = 600.0   -- a large street to copy for a highway's last piece is looked for this far from the town node

--- The street the piece from a highway link's merge node to the town node c copies: a large two-way
--- street (2026-10-11: a copy of the town node's own small street squeezed the highway's traffic into
--- it): c's own if large, else the nearest large street edge within LARGE_SRC_R, else c's own edge.
local function mergeEdge(map : {integer : {integer}}, c : SquareStressNodeCand) : integer
	local own = (map[c.id] or {})[1]
	local large = anyLarge(map[c.id])
	if large ~= nil then return large end
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(c.x, c.y), LARGE_SRC_R, api.type.ComponentType.BASE_EDGE)
	if not ok or list == nil then return own end
	local bestE, bestD : integer, number = nil, math.huge
	for _, e in ipairs(list as {integer}) do
		if comp(e, api.type.ComponentType.BASE_EDGE_STREET) ~= nil and isLargeEdge(e) then
			local be = comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
			local p = nodePos(be.node0)
			local d = p ~= nil and (p[1] - c.x) ^ 2 + (p[2] - c.y) ^ 2 or math.huge
			if d < bestD or (d == bestD and bestE ~= nil and e < bestE) then bestE, bestD = e, d end
		end
	end
	return bestE or own
end

--- The link proposal of an arm to the node c (a town street's dead end, or the single end of an
--- in-line junction's arm). Second result: the road's start and end (2D) for the avoid list.
---
--- The link never ends on an existing node: such a node keeps the lane connections it was built with,
--- and a dead end has none, so traffic could not pass (in game 2026-10-11: the HUD's red dead-end sign
--- on every arm end and town node a link joined, none on the link's own new nodes). Each of the two
--- nodes is replaced by a new node at the same spot, its edges by copies ending there; the copies' far
--- nodes keep their configs, re-pointed at the copies. The engine gives script-made nodes no config at
--- all (Smart Lanes: `reason=no_config` on 37 link nodes, 2026-10-12), so assemble gives every new node
--- one (stress_nodecfg: the old node's config carried over plus the link piece's lanes).
--- via (Showcase, after a collision): a single end's road runs through this point (2D) first.
--- lock (Showcase towns): every edge of the proposal goes out roadDevelopmentLocked.
--- country (Showcase towns, SHOWCASE.md "Link roads are country roads"): every new piece between the
--- arm and the town node is the country road of the arm's lanes (country = true: no houses along it,
--- the town never lines the link); a highway pair's merge piece the large country road. Only the copies
--- of the existing edges at the two replaced nodes keep their own type (the grid's street at the join).
local function linkBuilder(arm : Arm, c : SquareStressNodeCand, via? : {number}, lock? : boolean, country? : boolean,
		lanes? : integer, pairLanes? : integer) : Builder, {{number}}
	local b = newBuilder()
	b.lock = lock == true
	local targetRef, target = replaceNode(b, c.id)
	if #arm.ends == 1 then
		-- A single end continues with a copy of its edge (a country road of its lanes when country, or of
		-- `lanes` road lanes: the Lights showcase's large country links); one whose (one-way) edge leads into
		-- the junction runs town -> junction.
		local e = arm.ends[1]
		if country then
			local okY, y = pcall(api.engine.util.getYear)
			local tpl = lanes ~= nil and logic.countryTemplate(lanes, (okY and type(y) == "number") and math.floor(y as number) or nil) or nil
			b.template = tpl or countryOf(e.edge)
		end
		local startRef, startPos = replaceNode(b, e.node)
		straightVia(b, e.edge, startRef, startPos, targetRef, target, e.out, via)
		return b, { { arm.x, arm.y }, { c.x, c.y } }
	end
	-- A highway arm stays a highway: each carriageway runs on beside the other (copies of its own
	-- one-way edge, its side offset across the link kept) towards the target, closes in over TAPER
	-- and meets the other in one node TOWN_MERGE before the target node; a short piece of a large
	-- two-way street (mergeEdge) joins that node to it.
	local dx, dy = target[1] - arm.x, target[2] - arm.y
	local len = math.max(1.0, math.sqrt(dx * dx + dy * dy))
	local ux, uy = dx / len, dy / len
	local px, py = -uy, ux
	local mergeD = math.min(TOWN_MERGE, len / 4)
	local mx, my = target[1] - ux * mergeD, target[2] - uy * mergeD
	local startPos = { mx, my, heightAt(mx, my) }
	local startRef = addNode(b, startPos)
	local runD = mergeD + TAPER
	local parallel = len > runD + 50
	for _, e in ipairs(arm.ends) do
		local chain : {{number}} = { e.pos }
		if parallel then
			local side = (e.pos[1] - arm.x) * px + (e.pos[2] - arm.y) * py
			local q = { target[1] - ux * runD + px * side, target[2] - uy * runD + py * side, 0.0 }
			local run = logic.linePoints(e.pos, q, MAX_SEG)
			for k = 2, #run do chain[#chain + 1] = { run[k][1], run[k][2], heightAt(run[k][1], run[k][2]) } end
		end
		chain[#chain + 1] = startPos
		local refs : {integer} = { (replaceNode(b, e.node)) }
		for k = 2, #chain - 1 do refs[k] = addNode(b, chain[k]) end
		refs[#chain] = startRef
		for k = 1, #chain - 1 do
			if e.out then
				b.specs[#b.specs + 1] = { src = e.edge, n0 = refs[k], n1 = refs[k + 1], p0 = chain[k], p1 = chain[k + 1] }
			else
				b.specs[#b.specs + 1] = { src = e.edge, n0 = refs[k + 1], n1 = refs[k], p0 = chain[k + 1], p1 = chain[k] }
			end
		end
	end
	if country then
		local okY, y = pcall(api.engine.util.getYear)
		-- the merge piece: the large country road, or (bench: pairLanes) the highway's own lanes both ways
		b.template = logic.countryTemplate(pairLanes or 6, (okY and type(y) == "number") and math.floor(y as number) or nil)
	end
	straight(b, mergeEdge(b.map, c), startRef, startPos, targetRef, target, true)
	return b, { { arm.x, arm.y }, { c.x, c.y } }
end

--- linkBuilder's proposal (the Junction test's links).
local function linkProposal(arm : Arm, c : SquareStressNodeCand, via? : {number}, lock? : boolean, country? : boolean) : SimpleProposal, {{number}}
	local b, seg = linkBuilder(arm, c, via, lock, country)
	return assemble(b), seg
end

--- Several links' builders as one (Showcase link groups, SHOWCASE.md "batched building"): their new nodes
--- and pieces renumbered after each other (node refs -k, piece indices), so assemble makes ONE proposal
--- with every link's node configs. nil and why when two of them replace (remove) the same existing node or
--- edge, or one re-points a node another replaces. A far node two of them re-point (each for another of its
--- edges: a Lights showcase entry's joins share the grid corners between its ring and central street) gets
--- both re-pointings in its one new config.
local function mergeBuilders(list : {Builder}) : Builder, string
	local m : Builder = { map = list[1].map, newNodes = {}, specs = {}, removeEdges = {}, removeNodes = {}, repoint = {}, replaced = {},
		copyOf = {}, lock = list[1].lock, ghosts = {} }
	local removed : {integer : boolean} = {}
	local pointed : {integer : boolean} = {}
	for _, b in ipairs(list) do
		local mine : {integer} = {}
		for _, x in ipairs(b.removeNodes) do mine[#mine + 1] = x end
		for _, x in ipairs(b.removeEdges) do mine[#mine + 1] = x end
		for _, x in ipairs(mine) do
			if removed[x] or pointed[x] then return nil, string.format("entity %d in two links", x) end
		end
		for y in pairs(b.repoint) do
			if removed[y] then return nil, string.format("entity %d in two links", y) end
		end
		for _, x in ipairs(mine) do removed[x] = true end
		for y in pairs(b.repoint) do pointed[y] = true end
		local nOff, sOff = #m.newNodes, #m.specs
		local function ref(r : integer) : integer
			if r < 0 then return r - nOff end
			return r
		end
		for _, p in ipairs(b.newNodes) do m.newNodes[#m.newNodes + 1] = p end
		for _, sp in ipairs(b.specs) do
			m.specs[#m.specs + 1] = { src = sp.src, n0 = ref(sp.n0), n1 = ref(sp.n1), copy = sp.copy, p0 = sp.p0, p1 = sp.p1, template = sp.template }
		end
		for _, x in ipairs(b.removeEdges) do m.removeEdges[#m.removeEdges + 1] = x end
		for _, x in ipairs(b.removeNodes) do m.removeNodes[#m.removeNodes + 1] = x end
		for y, olds in pairs(b.repoint) do
			local t = m.repoint[y] or {}
			for old, k in pairs(olds) do t[old] = k + sOff end
			m.repoint[y] = t
		end
		for r, x in pairs(b.replaced) do m.replaced[ref(r)] = x end
		for x, g in pairs(b.ghosts or {}) do m.ghosts[x] = g end
		for r, olds in pairs(b.copyOf) do
			local t : {integer : integer} = {}
			for old, k in pairs(olds) do t[old] = k + sOff end
			m.copyOf[ref(r)] = t
		end
	end
	return m, nil
end

--- The link of two highway arms (two carriageways each; Junction test in-line stops): the carriageway
--- leaving a joins the one entering b, each a straight run between the replaced ends, of copies of the
--- carriageway edges of the arm whose carriageways lie closer together (the narrower highway:
--- 2026-10-12, copies of a medium highway's 18 m carriageways into a small highway's ends 13 m apart
--- overlapped each other, "Collision" 3 times). nil, reason when the ends don't pair up (not two ends
--- each, or not one out and one in). Third result: when the two highways differ (ends more than 1 m
--- further apart), which one was copied into the other's ends, with both templates: log evidence for
--- the lane change at the joined ends (assemble gives the replaced ends their configs, nc.configs).
local function linkPairProposal(a : Arm, bArm : Arm) : SimpleProposal, string, string
	if #a.ends ~= 2 or #bArm.ends ~= 2 then return nil, string.format("ends %d/%d", #a.ends, #bArm.ends) end
	local function split(arm : Arm) : ArmEnd, ArmEnd
		local o, i : ArmEnd, ArmEnd = nil, nil
		for _, e in ipairs(arm.ends) do if e.out then o = e else i = e end end
		return o, i
	end
	local aOut, aIn = split(a)
	local bOut, bIn = split(bArm)
	if aOut == nil or aIn == nil or bOut == nil or bIn == nil then return nil, "carriageway directions" end
	local function gap(o : ArmEnd, i : ArmEnd) : number
		return math.sqrt((o.pos[1] - i.pos[1]) ^ 2 + (o.pos[2] - i.pos[2]) ^ 2)
	end
	local gapA, gapB = gap(aOut, aIn), gap(bOut, bIn)
	local narrowB = gapB < gapA - 1
	local note : string = nil
	if math.abs(gapA - gapB) > 1 then
		local function tmpl(e : integer) : string
			local be = comp(e, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
			local ok, t = pcall(function() : string return tostring(be.roadTemplate) end)
			return ok and t or "?"
		end
		local cE, oE = narrowB and bIn.edge or aIn.edge, narrowB and aIn.edge or bIn.edge
		note = string.format("copies %s (ends %.0fm apart) into the ends of %s (%.0fm apart)", tmpl(cE),
			narrowB and gapB or gapA, tmpl(oE), narrowB and gapA or gapB)
	end
	local b = newBuilder()
	-- a -> b: a's leaving carriageway into b's entering one; b -> a: b's leaving one into a's entering one
	local r1, p1 = replaceNode(b, aOut.node)
	local r2, p2 = replaceNode(b, bIn.node)
	straight(b, narrowB and bIn.edge or aOut.edge, r1, p1, r2, p2, true)
	local r3, p3 = replaceNode(b, bOut.node)
	local r4, p4 = replaceNode(b, aIn.node)
	straight(b, narrowB and bOut.edge or aIn.edge, r3, p3, r4, p4, true)
	return assemble(b), nil, note
end

---------------------------------------------------------------------------
-- The job

-- math.atan2 in the game's Lua 5.1; the offline tests' Lua 5.4 only has the two-argument math.atan
local atan2 = math.atan2 or math.atan
local INLINE_MAX <const> = 12           -- in-line junctions per arm at most
local INLINE_SCAN <const> = 40.0       -- their new nodes are looked for this far beyond their reach
-- A refused stop tries these spots along the route (x its SHIFT) before giving up (2026-10-11: half the
-- stops near Large towns were "Construction Not Possible" at their first spot).
local INLINE_SHIFTS : {number} = { 0, -1, 1, -2, 2 }
local INLINE_SHIFT_ROAD <const> = 80.0
local INLINE_SHIFT_HIGHWAY <const> = 150.0
-- Junctions are built back to back, then one wait this long after the last build before their arms are
-- read and linked (Junction test: after the cell junctions and again after the in-line stops; Showcase:
-- once): Smart Lanes rewrites each new junction's lanes and lights meanwhile, and a link sent while its
-- light commands were still pending was refused ("Apply: invalid entity" on the ring node being changed,
-- 2026-10-11; docs/findings.md suggests ~3 s, not yet confirmed in game). Earlier builds wait longer.
local INLINE_SETTLE_MS <const> = 3000
local BENCH_IDLE_MS <const> = 30000      -- the bench's settle waits at most this long for Smart Lanes' queue to empty
local LINK_TRIES <const> = 3           -- tries of a link into a stop
local LINK_RETRY_MS <const> = 3000

--- An Arm of a built junction from a cluster of its ends, with the town fields of `main`.
local function armOf(cl : SquareStressArmCluster, ends : {ArmEnd}, main : Arm, jx : number, jy : number, caseLabel : string) : Arm
	local arm : Arm = { ends = {}, x = cl.x, y = cl.y, jx = jx, jy = jy, town = main.town, townPos = main.townPos,
		townName = main.townName, cell = main.cell, corner = main.corner, caseLabel = caseLabel, tried = {}, try = 1 }
	for _, m in ipairs(cl.members) do arm.ends[#arm.ends + 1] = ends[m] end
	return arm
end

--- Whether node n (at p) was added after a later build's snapshot inside that build's circle, i.e. by
--- that build (builds are serial: build j's snapshot is taken after build j-1's callback), not by the
--- one being read. Back-to-back builds read only after all of them, so neighbouring scan circles may
--- overlap (in-line stops shifted along their route: 2026-10-11 review).
local function laterOwns(n : integer, p : {number}, sc : {Scan}, seq : integer) : boolean
	if sc == nil or seq == nil or p == nil then return false end
	for j = seq + 1, #sc do
		local q = sc[j]
		if not q.before[n] and (p[1] - q.x) ^ 2 + (p[2] - q.y) ^ 2 <= q.r * q.r then return true end
	end
	return false
end

--- The entity ids of a command's resultEntities ({entity, revision} pairs), for the read's log.
local function resultIds(res : {{integer}}) : {integer : boolean}
	local out : {integer : boolean} = {}
	pcall(function()
		for _, er in ipairs(res or {}) do out[er[1]] = true end
	end)
	return out
end

--- The new dead ends among the street nodes near (x, y) that were not there `before` and were not
--- added by a later build (laterOwns, with the scans `sc` and this build's sequence number `seq`; both
--- nil: no later builds); every such node goes into `ours`. Returns the ends (sorted by node), the
--- count of new nodes, the new nodes where 3 or more streets meet (the junctions proper, for the
--- Lights setting) and how many of the new nodes are among the build's result entities `res` (log
--- evidence whether resultEntities name a construction's street nodes; not used to attribute yet).
local function newEnds(x : number, y : number, r : number, before : {integer : boolean}, ours : {integer : boolean},
		sc? : {Scan}, seq? : integer, res? : {integer : boolean}) : {ArmEnd}, integer, {integer}, integer
	local map = streetMap()
	local ends : {ArmEnd} = {}
	local joins : {integer} = {}
	local newN, inRes = 0, 0
	for n in pairs(nodesNear(x, y, r)) do
		local p = not before[n] and nodePos(n) or nil
		if not before[n] and not laterOwns(n, p, sc, seq) then
			newN = newN + 1
			ours[n] = true
			if res ~= nil and res[n] then inRes = inRes + 1 end
			local list = map[n]
			if list ~= nil and #list == 1 and p ~= nil then
				local be = comp(list[1], api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
				local q = be ~= nil and nodePos(be.node0 == n and be.node1 or be.node0) or nil
				local dir : {number} = nil
				if q ~= nil then
					local dl = math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2)
					if dl > 0 then dir = { (p[1] - q[1]) / dl, (p[2] - q[2]) / dl } end
				end
				ends[#ends + 1] = { node = n, edge = list[1], pos = p, out = be ~= nil and be.node1 == n, dir = dir }
			elseif list ~= nil and #list >= 3 then
				joins[#joins + 1] = n
			end
		end
	end
	table.sort(ends, function(a : ArmEnd, b : ArmEnd) : boolean return a.node < b.node end)
	table.sort(joins)
	return ends, newN, joins, inRes
end

--- Lights setting: whether the junctions built lose their traffic lights.
local function lightsOffFor(_k : integer) : boolean
	return jn.ui.lights == 2
end

--- Sets the traffic light preference at `nodes` (NO: lights off, as the node window's "None" button;
--- YES: the Lights showcase's fallback) with the game's own proposal: createTrafficLightProposal(node,
--- config:clone(), pref), base gui/entity_window/double_slip_switch.tl:56,489; the clone is read right
--- now, so its phases index the node's current lane connections. One command each; done() once all answered.
local function setLights(name : string, nodes : {integer}, pref : TrafficLightPreference, done : function(refused : {integer}))
	local left = #nodes
	local refused : {integer} = {}
	if left == 0 then done(refused) return end
	for _, n in ipairs(nodes) do
		local ok, err : boolean, any = pcall(function()
			local cfg = comp(n, api.type.ComponentType.BASE_NODE_CONFIG) as Engine.Component.BaseNodeConfig
			local tlc = cfg.trafficLightConfig
			local okC, c : boolean, any = pcall(function() : any return tlc:clone() end)
			if okC and c ~= nil then tlc = c as Engine.Component.TrafficLightConfig end
			local p = api.engine.util.proposal.createTrafficLightProposal(n, tlc, pref)
			rt.send(name .. ":lights", api.cmd.makeWorldBuildProposalCmd(p, nil, false, true), function(sent : boolean, _d : any)
				-- refused (e.g. a light or lane change of Smart Lanes still pending on the node): no retry,
				-- but the node is named so a dark (or still lit) twin is traceable in the log
				if not sent then
					rt.log(string.format("[SQST] %s: lights %s at node %d refused", name, pref == api.type.enum.TrafficLightPreference.NO
						and "off" or "on", n))
					refused[#refused + 1] = n
				end
				left = left - 1
				if left == 0 then done(refused) end
			end)
		end)
		if not ok then
			rt.detail(string.format("[SQST] %s: lights %s at node %d failed: %s", name, pref == api.type.enum.TrafficLightPreference.NO and "off"
				or "on", n, tostring(err)))
			refused[#refused + 1] = n
			left = left - 1
			if left == 0 then done(refused) end
		end
	end
end

local function lightsOff(name : string, nodes : {integer}, done : function(refused : {integer}))
	setLights(name, nodes, api.type.enum.TrafficLightPreference.NO, done)
end

local function endPoints(ends : {ArmEnd}) : {{number}}
	local pts : {{number}} = {}
	for k, e in ipairs(ends) do pts[k] = e.pos end
	return pts
end

--- Traffic = Bus lines (logic.TEST_TRAFFIC): after a test, one bus line per route between two of its
--- towns (stress_buslines addRouteLines, Auto bus lines' Buses per line), started TRAFFIC_DELAY_MS
--- after the last link so the new roads (and Smart Lanes' lane writes on the link's nodes) have settled:
--- the junction settle (a stop proposal on a town edge next to a just-linked node is the same case). The
--- job "bus_lines_<test>" is refused (rt.warn) while another bus-lines job is queued or running.
local TRAFFIC_DELAY_MS <const> = INLINE_SETTLE_MS
local TEST_JOBS : {string} = rt.TEST_JOBS

local function queueTraffic(name : string, title : string, routes : {SquareStressBusRoute})
	if #routes == 0 then return end
	rt.later(name .. ":traffic", TRAFFIC_DELAY_MS, function()
		buslines.addRouteLines("bus_lines_" .. name, title, routes)
	end)
end

--- The route between grid points ia and ib of a test (nil when a town is missing). gridSize (towns on our
--- wide street grid: the batch's TOWN_SIZES index, a point's own size first) gives each town its grid
--- half-size: the route's stops and depots stay on that grid (logic.busEdgeReject "outside_town").
local function route(points : {SquareStressGridPoint}, created : {integer : integer}, ia : integer, ib : integer,
		prefix : string, gridSize? : integer) : SquareStressBusRoute
	local pa, pb = points[ia], points[ib]
	local ta, tb = created[ia], created[ib]
	if pa == nil or pb == nil or ta == nil or tb == nil then return nil end
	local ha = gridSize ~= nil and logic.gridHalfOfSize(pa.size or gridSize) or nil
	local hb = gridSize ~= nil and logic.gridHalfOfSize(pb.size or gridSize) or nil
	return { a = { id = ta, x = pa.x, y = pa.y, half = ha }, b = { id = tb, x = pb.x, y = pb.y, half = hb },
		label = string.format("%s%s -> %s", prefix, pa.name, pb.name) }
end

--- Build pressed with Traffic = Bus lines (on): a dialog up front when Keep balance is off and costs
--- are on (the bus lines come last and are skipped below buslines.MIN_LINE_BALANCE); the build goes on.
local function moneyWarn(title : string, on : boolean)
	if not on then return end
	local ok, w = pcall(buslines.moneyWarning)
	if ok and w ~= nil then rt.warn(title, "Traffic is Bus lines. " .. w) end
end

function jn.build()
	local busy = rt.busyJob(TEST_JOBS)   -- also a Crossing test (it refuses a Junction test the same way)
	if busy ~= nil then
		rt.warn("Junction test", "A test is already running (" .. busy .. "). Wait for it to finish.")
		return
	end
	local cases = selectedCases()
	local inline = jn.ui.inline == 2
	local files : {string : string} = {}       -- construction file -> resolved name
	local missing : {string} = {}
	local function need(list : {SquareStressJunctionCase})
		for _, c in ipairs(list) do
			if files[c.file] == nil then
				local f = resolve(c.file)
				if f == nil then missing[#missing + 1] = c.file else files[c.file] = f end
			end
		end
	end
	need(cases)
	local inlineRoad = logic.INLINE_ROAD
	if inline then
		need(inlineRoad)
		need(logic.INLINE_HIGHWAY)
	end
	if #missing > 0 then
		rt.warn("Junction test", "Constructions not found (is Roundabouts & Interchanges enabled?): " .. table.concat(missing, ", "))
		return
	end
	moneyWarn("Junction test", jn.ui.traffic == 2)
	local asked = selectedSpacing()
	local size = logic.TOWN_SIZES[jn.ui.size] or logic.TOWN_SIZES[1]
	local useCamera = jn.ui.centre == 2
	local cx, cy = 0.0, 0.0
	if useCamera then cx, cy = rt.camera() end
	-- The grid that fits the map (2026-10-11: 5 x 4 towns 4 km apart reached -8 km on a 16 km map and
	-- was cancelled). Around the camera the map is narrower on one side: twice the shorter distance.
	local mapW, mapH = 0.0, 0.0
	pcall(function()
		local box = api.engine.terrain.getBoundingBox()
		if useCamera then
			mapW = 2 * math.min(cx - box.min.x, box.max.x - cx)
			mapH = 2 * math.min(cy - box.min.y, box.max.y - cy)
		else
			mapW, mapH = box.max.x - box.min.x, box.max.y - box.min.y
		end
	end)
	local cols, rows, spacing = logic.fitJunctionGrid(#cases, asked, mapW, mapH, MAP_MARGIN)
	if spacing < asked then
		rt.warn("Junction test", string.format("%d junctions %g km apart do not fit this map (%.0f x %.0f km). Using %g km: %d x %d towns.\nFor a wider spacing pick fewer junctions (Roundabouts or Interchanges) or a larger map.",
			#cases, asked / 1000, mapW / 1000, mapH / 1000, spacing / 1000, cols, rows))
	end
	rt.log(string.format("[SQST] junction_test: %d junctions, %d x %d towns %.0fm apart, size %s, in line %s", #cases, cols, rows,
		spacing, size.label, logic.JUNCTION_INLINE[jn.ui.inline] or "?"))
	towns.createGrid({
		name = "junction_grid",
		label = "Creating junction test towns",
		cols = cols,
		rows = rows,
		spacing = spacing,
		size = size,
		useCamera = useCamera,
		cx = cx,
		cy = cy,
		connect = 1,
		streets = jn.ui.streets,
		batch = true,   -- grids several per proposal, their locks across towns, every town in one command
	}, function(created : {integer : integer}, points : {SquareStressGridPoint})
		local cells = logic.junctionCells(points, cols, rows)
		-- Build phase: every cell junction back to back (each waits for its own callback only); one
		-- settle; read every junction's arms; then "plan" queues the in-line stops (built back to back,
		-- one more settle, their arms read) and the links in route order.
		local tasks : {Task} = {}
		for k, cell in ipairs(cells) do
			tasks[#tasks + 1] = { kind = "build", cell = cell, case_ = cases[(k - 1) % #cases + 1], k = k }
		end
		tasks[#tasks + 1] = { kind = "settle", k = 1 }
		for k, cell in ipairs(cells) do
			tasks[#tasks + 1] = { kind = "read", cell = cell, case_ = cases[(k - 1) % #cases + 1], k = k }
		end
		tasks[#tasks + 1] = { kind = "plan" }
		local ctx = context()
		local ours : {integer : boolean} = {}    -- nodes of our junctions and link roads
		-- the run's counters and lists in one table: the build step below is near Lua 5.1's limit of 60
		-- upvalues per function (tests/square_stress_test/test_junctions.lua checks it)
		local js : JunctionState = { placed = {}, scans = {}, stopTasks = {}, readTasks = {}, linkTasks = {}, avoid = {}, built = 0,
			refused = 0, linked = 0, unlinked = 0, inBuilt = 0, inRefused = 0, stopCount = 0,
			nextVariant = { road = 0, highway = 0 }, notes = {}, problems = {}, linkedOf = {} }
		local traffic = jn.ui.traffic == 2
		local name = "junction_test"
		local townR = (size.spacing or 1500) * logic.INLINE_TOWN_R

		rt.enqueue(name, #tasks, function(i : integer, job : SquareStressJob)
			local function finish()
				logic.resume(job)
				if i >= job.total then
					rt.log(string.format("[SQST] %s summary junctions=%d built=%d refused=%d in_line built=%d refused=%d arms linked=%d unlinked=%d %s",
						name, #cells, js.built, js.refused, js.inBuilt, js.inRefused, js.linked, js.unlinked, table.concat(js.notes, " ")))
					local routes : {SquareStressBusRoute} = {}
					if traffic then
						for _, r in ipairs(logic.cellRoutes(cells, js.linkedOf, logic.TEST_ROUTES_MAX)) do
							local cell = cells[r[3]]
							local rr = route(points, created, r[1], r[2], (cell and cell.name or "?") .. " ",
								jn.ui.streets >= 2 and jn.ui.size or nil)
							if rr ~= nil then routes[#routes + 1] = rr end
						end
					end
					rt.log("[SQST] " .. logic.testSummary("Junction test", js.built + js.inBuilt, js.built + js.refused + js.inBuilt + js.inRefused, "junctions",
						js.linked, js.linked + js.unlinked, traffic and #routes or nil))
					queueTraffic(name, "Junction test", routes)
					if #js.problems > 0 then
						local shown : {string} = {}
						for k = 1, math.min(#js.problems, 10) do shown[k] = "- " .. js.problems[k] end
						if #js.problems > 10 then shown[#shown + 1] = string.format("... and %d more (see the log)", #js.problems - 10) end
						rt.warn("Junction test", string.format("%d junction%s built, %d refused; %d route%s linked, %d not.\n%s\n\nRefused junctions usually lack room: try a larger spacing or smaller towns.",
							js.built + js.inBuilt, js.built + js.inBuilt == 1 and "" or "s", js.refused + js.inRefused, js.linked, js.linked == 1 and "" or "s",
							js.unlinked, table.concat(shown, "\n")))
					end
				end
			end
			local function push(t : Task)
				tasks[#tasks + 1] = t
				job.total = job.total + 1
			end
			--- The in-line stops of a new arm and their tasks, then the town link (queued by "plan").
			local function planArm(arm : Arm)
				if not inline then
					js.linkTasks[#js.linkTasks + 1] = { kind = "link", arm = arm }
					return
				end
				local highway = #arm.ends >= 2
				local list = highway and logic.INLINE_HIGHWAY or inlineRoad
				local R = highway and logic.INLINE_HIGHWAY_R or logic.INLINE_ROAD_R
				local pts = logic.inlineStops({ arm.x, arm.y }, arm.townPos, logic.INLINE_GAP + R, townR + logic.INLINE_GAP + R,
					2 * R + logic.INLINE_GAP, INLINE_MAX)
				local chain : Chain = { main = arm, stops = {}, tail = arm, broken = false }
				local kindKey = highway and "highway" or "road"
				for k, p in ipairs(pts) do
					local v = js.nextVariant[kindKey] % #list + 1
					js.nextVariant[kindKey] = v
					chain.stops[k] = { pos = p, case_ = list[v], built = false }
					js.stopTasks[#js.stopTasks + 1] = { kind = "inline", chain = chain, k = k }
					js.readTasks[#js.readTasks + 1] = { kind = "sread", chain = chain, k = k }
				end
				for k = 1, #pts do js.linkTasks[#js.linkTasks + 1] = { kind = "clink", chain = chain, k = k } end
				js.linkTasks[#js.linkTasks + 1] = { kind = "link", chain = chain }
			end
			local task = tasks[i]
			if task == nil then finish() return end

			if task.kind == "settle" then
				-- One wait per phase: Smart Lanes rewrites each new junction's lanes and lights right after
				-- its build, and a proposal touching a node whose light change is still pending is refused
				-- (docs/findings.md "invalid entity"); the last build waits INLINE_SETTLE_MS, earlier ones more.
				local n = task.k == 1 and js.built or js.inBuilt
				if n == 0 then finish() return end
				rt.detail(string.format("[SQST] %s: %d %s built; reading their arms in %.0f s", name, n,
					task.k == 1 and "junctions" or "in-line junctions", INLINE_SETTLE_MS / 1000))
				rt.later(name .. ":settle", INLINE_SETTLE_MS, finish)
				return
			end

			if task.kind == "plan" then
				for _, t in ipairs(js.stopTasks) do push(t) end
				if #js.stopTasks > 0 then
					push({ kind = "settle", k = 2 })
					for _, t in ipairs(js.readTasks) do push(t) end
				end
				for _, t in ipairs(js.linkTasks) do push(t) end
				finish()
				return
			end

			if task.kind == "build" then
				local cell, case_ = task.cell, task.case_
				local tag = string.format("%s %s", cell.name, case_.label)
				local angle = math.pi / 4
				local proposal = junctionProposal(files[case_.file], case_, cell.x, cell.y, i, angle)
				local verdict = precheck(proposal, ctx)
				if verdict ~= nil and verdict ~= "ok" then
					js.refused = js.refused + 1
					js.notes[#js.notes + 1] = string.format("%s=refused(%s)", case_.id, verdict)
					rt.log(string.format("[SQST] %s %s at %.0f,%.0f refused by the check: %s", name, tag, cell.x, cell.y, verdict))
					js.problems[#js.problems + 1] = string.format("%s: %s", tag, verdict)
					finish()
					return
				end
				local before = nodesNear(cell.x, cell.y, SCAN_R)
				js.scans[#js.scans + 1] = { x = cell.x, y = cell.y, r = SCAN_R, before = before }
				local seq = #js.scans
				local t0 = rt.nowUs()
				rt.send(name, api.cmd.makeWorldBuildProposalCmd(junctionProposal(files[case_.file], case_, cell.x, cell.y, i, angle), ctx, false, true, false),
					function(success : boolean, data : any, res : {{integer}})
						local ms = (rt.nowUs() - t0) / 1000
						if not success then
							js.refused = js.refused + 1
							js.notes[#js.notes + 1] = case_.id .. "=failed"
							rt.log(string.format("[SQST] %s %s build failed ms=%.0f %s", name, tag, ms, errText(data)))
							js.problems[#js.problems + 1] = string.format("%s: build failed", tag)
							finish()
							return
						end
						js.built = js.built + 1
						js.placed[task.k] = { before = before, seq = seq, res = resultIds(res), ms = ms }
						finish()   -- the next junction at once; its arms are read after the settle
					end)
				return
			end

			if task.kind == "read" then
				local cell, case_ = task.cell, task.case_
				local pl = js.placed[task.k]
				if pl == nil then finish() return end   -- refused or failed
				local tag = string.format("%s %s", cell.name, case_.label)
				local ends, newN, joins, inRes = newEnds(cell.x, cell.y, SCAN_R, pl.before, ours, js.scans, pl.seq, pl.res)
				local clusters = logic.clusterEnds(endPoints(ends), ARM_GAP)
				local corners : {{number}} = {}
				for k, idx in ipairs(cell.corners) do corners[k] = { points[idx].x, points[idx].y } end
				local assign = logic.assignArms(cell.x, cell.y, clusters, corners, MAX_ARM_DEG)
				local armText : {string} = {}
				for k, cl in ipairs(clusters) do
					local corner = assign[k]
					local town = corner ~= nil and created[cell.corners[corner]] or nil
					local pt = corner ~= nil and points[cell.corners[corner]] or nil
					if town ~= nil then
						local main : Arm = { town = town, townPos = { pt.x, pt.y }, townName = pt.name, cell = cell.name, corner = corner }
						planArm(armOf(cl, ends, main, cell.x, cell.y, case_.label))
						armText[#armText + 1] = string.format("%d->%s", #cl.members, pt.name)
					else
						js.unlinked = js.unlinked + 1
						armText[#armText + 1] = string.format("%d->none", #cl.members)
					end
				end
				local off = lightsOffFor(task.k)
				rt.log(string.format("[SQST] %s %s built ms=%.0f nodes=%d ends=%d arms=%d [%s] res_nodes=%d%s", name, tag, pl.ms, newN, #ends,
					#clusters, table.concat(armText, " "), inRes, off and string.format(" lights off at %d", #joins) or ""))
				if off then lightsOff(name, joins, finish) else finish() end
				return
			end

			if task.kind == "inline" then
				local chain, k = task.chain, task.k
				local stop = chain.stops[k]
				local main = chain.main
				local prev = k == 1 and { main.x, main.y } or chain.stops[k - 1].pos
				local nxt = k == #chain.stops and main.townPos or chain.stops[k + 1].pos
				local angle = atan2(main.townPos[2] - main.y, main.townPos[1] - main.x)
				local case_ = stop.case_
				local tag = string.format("%s %s -> %s in line %d/%d %s", main.cell, main.caseLabel, main.townName, k, #chain.stops, case_.label)
				-- the first spot along the route the check accepts
				local shift = #main.ends >= 2 and INLINE_SHIFT_HIGHWAY or INLINE_SHIFT_ROAD
				local ca, sa = math.cos(angle), math.sin(angle)
				local x, y = stop.pos[1], stop.pos[2]
				local firstVerdict : string = nil
				local placed = false
				for _, f in ipairs(INLINE_SHIFTS) do
					local tx, ty = stop.pos[1] + ca * shift * f, stop.pos[2] + sa * shift * f
					local verdict = precheck(junctionProposal(files[case_.file], case_, tx, ty, 1000 + i, angle), ctx)
					if verdict == nil or verdict == "ok" then
						x, y, placed = tx, ty, true
						if f ~= 0 then rt.detail(string.format("[SQST] %s %s: placed %.0fm along the route", name, tag, shift * f)) end
						break
					end
					firstVerdict = firstVerdict or verdict
				end
				if not placed then
					js.inRefused = js.inRefused + 1
					js.notes[#js.notes + 1] = string.format("%s=refused(%s)", case_.id, firstVerdict)
					rt.log(string.format("[SQST] %s %s at %.0f,%.0f refused by the check at %d spots: %s", name, tag, x, y,
						#INLINE_SHIFTS, firstVerdict))
					js.problems[#js.problems + 1] = string.format("%s: %s", tag, firstVerdict)
					finish()
					return
				end
				stop.pos = { x, y }
				local R = (#main.ends >= 2 and logic.INLINE_HIGHWAY_R or logic.INLINE_ROAD_R) + INLINE_SCAN
				local before = nodesNear(x, y, R)
				js.scans[#js.scans + 1] = { x = x, y = y, r = R, before = before }
				local seq = #js.scans
				local t0 = rt.nowUs()
				rt.send(name, api.cmd.makeWorldBuildProposalCmd(junctionProposal(files[case_.file], case_, x, y, 1000 + i, angle), ctx, false, true, false),
					function(success : boolean, data : any, res : {{integer}})
						local ms = (rt.nowUs() - t0) / 1000
						if not success then
							js.inRefused = js.inRefused + 1
							js.notes[#js.notes + 1] = case_.id .. "=failed"
							rt.log(string.format("[SQST] %s %s build failed ms=%.0f %s", name, tag, ms, errText(data)))
							js.problems[#js.problems + 1] = string.format("%s: build failed", tag)
							finish()
							return
						end
						js.inBuilt = js.inBuilt + 1
						stop.built = true
						stop.prev, stop.nxt, stop.scanR, stop.before, stop.ms = prev, nxt, R, before, ms
						stop.seq, stop.res = seq, resultIds(res)
						finish()   -- the next stop at once; its arms are read after the settle
					end)
				return
			end

			if task.kind == "sread" then
				local chain, k = task.chain, task.k
				local stop = chain.stops[k]
				if not stop.built then finish() return end
				local main = chain.main
				local case_ = stop.case_
				local tag = string.format("%s %s -> %s in line %d/%d %s", main.cell, main.caseLabel, main.townName, k, #chain.stops, case_.label)
				local x, y = stop.pos[1], stop.pos[2]
				local ends, newN, joins, inRes = newEnds(x, y, stop.scanR, stop.before, ours, js.scans, stop.seq, stop.res)
				local clusters = logic.clusterEnds(endPoints(ends), ARM_GAP)
				local assign = logic.assignArms(x, y, clusters, { stop.prev, stop.nxt }, MAX_ARM_DEG)
				for c, side in pairs(assign) do
					local arm = armOf(clusters[c], ends, main, x, y, case_.label)
					if side == 1 then stop.back = arm else stop.front = arm end
				end
				js.stopCount = js.stopCount + 1
				local off = lightsOffFor(js.stopCount)
				rt.log(string.format("[SQST] %s %s built ms=%.0f nodes=%d ends=%d arms=%d through=%s res_nodes=%d%s", name, tag, stop.ms, newN, #ends,
					#clusters, (stop.back ~= nil and stop.front ~= nil) and "yes" or "no", inRes,
					off and string.format(" lights off at %d", #joins) or ""))
				if off then lightsOff(name, joins, finish) else finish() end
				return
			end

			if task.kind == "clink" then
				local chain, k = task.chain, task.k
				local stop = chain.stops[k]
				local main = chain.main
				local tag = string.format("%s %s -> %s in line %d/%d %s", main.cell, main.caseLabel, main.townName, k, #chain.stops, stop.case_.label)
				if chain.broken or not stop.built then finish() return end
				if stop.back == nil or stop.front == nil then
					chain.broken = true
					js.unlinked = js.unlinked + 1
					rt.log(string.format("[SQST] %s %s: no through arms; the rest of this route is not linked", name, tag))
					js.problems[#js.problems + 1] = string.format("%s: no through arms, route not linked", tag)
					finish()
					return
				end
				local from, to = chain.tail, stop.back
				local okP, proposal, why = pcall(function() : SimpleProposal, string
					if #from.ends >= 2 and #to.ends >= 2 then
						local pp, pw = linkPairProposal(from, to)
						return pp, pw
					end
					if #to.ends == 1 then
						local e = to.ends[1]
						return (linkProposal(from, { id = e.node, x = e.pos[1], y = e.pos[2], z = e.pos[3], deg = 1, score = 0 })), nil
					end
					local e = from.ends[1]
					return (linkProposal(to, { id = e.node, x = e.pos[1], y = e.pos[2], z = e.pos[3], deg = 1, score = 0 })), nil
				end)
				if not okP or proposal == nil then
					chain.broken = true
					js.unlinked = js.unlinked + 1
					local err = okP and tostring(why) or tostring(proposal)
					rt.log(string.format("[SQST] %s %s: link proposal error %s", name, tag, err))
					finish()
					return
				end
				rt.detail(string.format("[SQST] %s %s sending link: ends=%d->%d", name, tag, #from.ends, #to.ends))
				local t0 = rt.nowUs()
				rt.send(name, api.cmd.makeWorldBuildProposalCmd(proposal as SimpleProposal, ctx, false, true, false), function(success : boolean, data : any)
					local ms = (rt.nowUs() - t0) / 1000
					if success then
						js.linked = js.linked + 1
						js.avoid[#js.avoid + 1] = { { from.x, from.y }, { to.x, to.y } }
						chain.tail = stop.front
						rt.detail(string.format("[SQST] %s %s linked ms=%.0f", name, tag, ms))
					elseif (stop.linkTries or 0) + 1 < LINK_TRIES then
						-- probably Smart Lanes still changing a node of it: the same link again, read afresh
						stop.linkTries = (stop.linkTries or 0) + 1
						rt.log(string.format("[SQST] %s %s: link refused (%s); trying again in %.0f s (%d/%d)", name, tag, errText(data),
							LINK_RETRY_MS / 1000, stop.linkTries + 1, LINK_TRIES))
						rt.later(name .. ":relink", LINK_RETRY_MS, function()
							push({ kind = "clink", chain = chain, k = k })
							finish()
						end)
						return
					else
						chain.broken = true
						js.unlinked = js.unlinked + 1
						rt.log(string.format("[SQST] %s %s: link refused %d times (%s); the rest of this route is not linked", name, tag,
							LINK_TRIES, errText(data)))
						js.problems[#js.problems + 1] = string.format("%s: link refused, route not linked", tag)
					end
					finish()
				end)
				return
			end

			-- link (to the town)
			local arm = task.arm
			if arm == nil and task.chain ~= nil then
				if task.chain.broken then finish() return end
				arm = task.chain.tail
			end
			local tag = string.format("%s %s -> %s", arm.cell, arm.caseLabel, arm.townName)
			-- Fresh every try: an earlier link may have replaced a town node since.
			local ranked = logic.rankTownNodes(townNodes(arm.townPos[1], arm.townPos[2], spacing * TOWN_R, ours, streetMap()),
				{ arm.x, arm.y }, arm.townPos, spacing * TOWN_R, js.avoid)
			local c : SquareStressNodeCand = nil
			for _, cand in ipairs(ranked) do
				if not arm.tried[cand.id] then c = cand break end
			end
			if c == nil then
				js.unlinked = js.unlinked + 1
				rt.log(string.format("[SQST] %s %s: no town street node left to link to (candidates=%d tried=%d)", name, tag,
					#ranked, arm.try - 1))
				js.problems[#js.problems + 1] = string.format("%s: no town street to link to", tag)
				finish()
				return
			end
			local okP, proposal, seg = pcall(linkProposal, arm, c)
			if not okP or proposal == nil then
				rt.log(string.format("[SQST] %s %s: link proposal error %s", name, tag, tostring(proposal)))
				js.unlinked = js.unlinked + 1
				finish()
				return
			end
			-- Before the send, so a crash in the build names what was being built (2026-10-11).
			rt.detail(string.format("[SQST] %s %s sending: ends=%s town node=%d deg=%d", name, tag,
				(function() : string
					local ids : {string} = {}
					for _, e in ipairs(arm.ends) do ids[#ids + 1] = tostring(e.node) end
					return table.concat(ids, ",")
				end)(), c.id, c.deg))
			local t0 = rt.nowUs()
			rt.send(name, api.cmd.makeWorldBuildProposalCmd(proposal as SimpleProposal, ctx, false, true, false), function(success : boolean, data : any)
				local ms = (rt.nowUs() - t0) / 1000
				local len = math.sqrt((c.x - arm.x) ^ 2 + (c.y - arm.y) ^ 2)
				if success then
					js.linked = js.linked + 1
					js.avoid[#js.avoid + 1] = seg as {{number}}
					if arm.corner ~= nil then
						js.linkedOf[arm.cell] = js.linkedOf[arm.cell] or {}
						js.linkedOf[arm.cell][arm.corner] = true
					end
					rt.detail(string.format("[SQST] %s %s linked ends=%d node=%d deg=%d length=%.0fm ms=%.0f", name, tag, #arm.ends,
						c.id, c.deg, len, ms))
				elseif arm.try < NODE_TRIES then
					rt.detail(string.format("[SQST] %s %s node=%d refused (%s); trying the next node", name, tag, c.id, errText(data)))
					arm.tried[c.id] = true
					arm.try = arm.try + 1
					push({ kind = "link", arm = arm })
				else
					js.unlinked = js.unlinked + 1
					rt.log(string.format("[SQST] %s %s: link refused at %d node(s), last %s", name, tag, arm.try, errText(data)))
					js.problems[#js.problems + 1] = string.format("%s: link refused", tag)
				end
				finish()
			end)
		end, { serial = true, label = "Building junctions" })
	end)
end

---------------------------------------------------------------------------
-- Crossing test (stress_logic.crossingLayout): 4 towns and a 3 x 3 grid of long roads, every junction a
-- plain crossing of our own construction. Stage 1 towns (towns.createGrid with explicit points, wide
-- grid streets), stage 2 the 21 crossings (each read a second later: its arm ends by direction, lights
-- off when asked), stage 3 the 32 links between arms (linkProposal: single end into single end),
-- stage 4 the 4 town links (a town street dead end, the nearest first, NODE_TRIES).

local CROSS_FILE <const> = "square_stress_test_crossing.con"
local CROSS_SCAN <const> = 120.0        -- a crossing's arms reach 60 m
local CROSS_DIR_DEG <const> = 30.0      -- an arm is E / N / W / S within this many degrees
local CROSS_TOWN_R <const> = 1200.0     -- town street nodes this far from the town centre may take its link
local CROSS_TOWN_REACH <const> = 700.0  -- a town's own extent beyond its centre (map fit)

jn.crossUi = { size = 2, lights = 1, traffic = 1 }

function jn.crossLabel() : string
	return "Build crossing test"
end

function jn.crossSignature() : string
	return string.format("%d/%d/%d", jn.crossUi.size, jn.crossUi.lights, jn.crossUi.traffic)
end

--- The direction key ("E", "N", "W", "S") of the vector (dx, dy), nil when none is within CROSS_DIR_DEG.
local function dirKey(dx : number, dy : number) : string
	local a = atan2(dy, dx)
	for key, v in pairs(logic.CROSSING_DIRS) do
		local d = math.abs(a - atan2(v[2], v[1])) % (2 * math.pi)
		if d > math.pi then d = 2 * math.pi - d end
		if d <= math.rad(CROSS_DIR_DEG) then return key end
	end
	return nil
end

function jn.buildCrossings()
	local busy = rt.busyJob(TEST_JOBS)
	if busy ~= nil then
		rt.warn("Crossing test", "A test is already running (" .. busy .. "). Wait for it to finish.")
		return
	end
	local file = resolve(CROSS_FILE)
	if file == nil then
		rt.warn("Crossing test", "The Stress Test crossing construction was not found (" .. CROSS_FILE .. ").")
		return
	end
	moneyWarn("Crossing test", jn.crossUi.traffic == 2)
	local size = logic.TOWN_SIZES[jn.crossUi.size] or logic.TOWN_SIZES[2]
	local lightsOffAll = jn.crossUi.lights == 1
	-- centre of the map; shrink the layout when the map is too small
	local cx, cy, half = 0.0, 0.0, 0.0
	pcall(function()
		local box = api.engine.terrain.getBoundingBox()
		cx, cy = (box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2
		half = math.min(box.max.x - box.min.x, box.max.y - box.min.y) / 2
	end)
	local scale = 1.0
	local reach = logic.crossingReach(CROSS_TOWN_REACH)
	if half > 0 and reach + MAP_MARGIN > half then
		scale = math.max(0.4, (half - MAP_MARGIN - CROSS_TOWN_REACH) / (reach - CROSS_TOWN_REACH))
		rt.warn("Crossing test", string.format("The layout (%.1f km across) does not fit this map (%.1f km): roads shortened to %.0f%%.",
			2 * reach / 1000, 2 * half / 1000, scale * 100))
	end
	local layout = logic.crossingLayout(0.0, 0.0, scale)
	local points : {SquareStressGridPoint} = {}
	for k, t in ipairs(layout.towns) do points[k] = { x = t.x, y = t.y, name = t.name, row = 1, col = k } end
	rt.log(string.format("[SQST] crossing_test: %d crossings, %d links, 4 towns (%s), scale %.2f, lights %s", #layout.junctions,
		#layout.links, size.label, scale, lightsOffAll and "off" or "game"))
	towns.createGrid({
		name = "crossing_towns",
		label = "Creating crossing test towns",
		cols = #points,
		rows = 1,
		spacing = 2 * (logic.CROSSING_D + logic.CROSSING_L + logic.CROSSING_G) * scale,
		size = size,
		useCamera = true,
		cx = cx,
		cy = cy,
		connect = 1,
		streets = 2,
		points = points,
		batch = true,   -- grids several per proposal, every town in one command
	}, function(created : {integer : integer}, townPts : {SquareStressGridPoint})
		local name = "crossing_test"
		local ctx = context()
		local ours : {integer : boolean} = {}
		local avoid : {{{number}}} = {}
		local arms : {string : {string : Arm}} = {}
		local built, refused, linked, failed = 0, 0, 0, 0
		local problems : {string} = {}
		local townLinked : {integer : boolean} = {}   -- town index (layout.towns) -> its link was built
		local traffic = jn.crossUi.traffic == 2
		local nJ, nL = #layout.junctions, #layout.links
		local total = nJ + nL + #layout.towns
		local function caseOf(cj : SquareStressCrossingJunction) : SquareStressJunctionCase
			return { id = cj.id, label = cj.label, file = CROSS_FILE, params = { sqst_x_shape = cj.shape, sqst_x_main = cj.main, sqst_x_side = cj.side } }
		end
		local townOf : {string : SquareStressGridPoint} = {}
		local townEntity : {string : integer} = {}
		for k, t in ipairs(layout.towns) do
			townOf[t.from] = townPts[k]
			townEntity[t.from] = created[k]
		end

		rt.enqueue(name, total, function(i : integer, job : SquareStressJob)
			local function finish()
				logic.resume(job)
				if i >= job.total then
					rt.log(string.format("[SQST] %s summary crossings=%d built=%d refused=%d links=%d linked=%d failed=%d", name, nJ,
						built, refused, nL + #layout.towns, linked, failed))
					local routes : {SquareStressBusRoute} = {}
					if traffic then
						for _, r in ipairs(logic.crossingRoutes(townLinked)) do
							local rr = route(townPts, created, r[1], r[2], "", jn.crossUi.size or 2)
							if rr ~= nil then routes[#routes + 1] = rr end
						end
					end
					rt.log("[SQST] " .. logic.testSummary("Crossing test", built, nJ, "crossings", linked, nL + #layout.towns,
						traffic and #routes or nil))
					queueTraffic(name, "Crossing test", routes)
					if #problems > 0 then
						local shown : {string} = {}
						for k = 1, math.min(#problems, 10) do shown[k] = "- " .. problems[k] end
						rt.warn("Crossing test", string.format("%d of %d crossings built, %d of %d roads linked.\n%s", built, nJ, linked,
							nL + #layout.towns, table.concat(shown, "\n")))
					end
				end
			end
			local function sendLink(tag : string, proposal : SimpleProposal, seg : {{number}}, tries : integer, retry : function(),
					onOk? : function())
				rt.send(name, api.cmd.makeWorldBuildProposalCmd(proposal, ctx, false, true, false), function(success : boolean, data : any)
					if success then
						linked = linked + 1
						if onOk ~= nil then onOk() end
						if seg ~= nil then avoid[#avoid + 1] = seg end
						rt.detail(string.format("[SQST] %s %s linked", name, tag))
						finish()
					elseif tries > 1 then
						rt.log(string.format("[SQST] %s %s: link refused (%s); trying again in %.0f s", name, tag, errText(data), LINK_RETRY_MS / 1000))
						rt.later(name .. ":relink", LINK_RETRY_MS, retry)
					else
						failed = failed + 1
						problems[#problems + 1] = tag .. ": link refused"
						rt.log(string.format("[SQST] %s %s: link refused (%s)", name, tag, errText(data)))
						finish()
					end
				end)
			end

			if i <= nJ then
				local j = layout.junctions[i]
				local tag = string.format("%s %s", j.id, j.label)
				local case_ = caseOf(j)
				local verdict = precheck(junctionProposal(file, case_, cx + j.x, cy + j.y, i, j.angle), ctx)
				if verdict ~= nil and verdict ~= "ok" then
					refused = refused + 1
					problems[#problems + 1] = tag .. ": " .. verdict
					rt.log(string.format("[SQST] %s %s refused by the check: %s", name, tag, verdict))
					finish()
					return
				end
				local x, y = cx + j.x, cy + j.y
				local before = nodesNear(x, y, CROSS_SCAN)
				rt.send(name, api.cmd.makeWorldBuildProposalCmd(junctionProposal(file, case_, x, y, i, j.angle), ctx, false, true, false),
					function(success : boolean, data : any)
						if not success then
							refused = refused + 1
							problems[#problems + 1] = tag .. ": build failed"
							rt.log(string.format("[SQST] %s %s build failed %s", name, tag, errText(data)))
							finish()
							return
						end
						built = built + 1
						rt.later(name .. ":arms", READ_DELAY_MS, function()
							local ends, newN, joins = newEnds(x, y, CROSS_SCAN, before, ours)
							local found : {string : Arm} = {}
							local dirs : {string} = {}
							for _, e in ipairs(ends) do
								local key = dirKey(e.pos[1] - x, e.pos[2] - y)
								if key ~= nil and found[key] == nil then
									found[key] = { ends = { e }, x = e.pos[1], y = e.pos[2], jx = x, jy = y, cell = j.id, caseLabel = j.label, tried = {}, try = 1 }
									dirs[#dirs + 1] = key
								end
							end
							arms[j.id] = found
							table.sort(dirs)
							rt.log(string.format("[SQST] %s %s built nodes=%d arms=%s%s", name, tag, newN, table.concat(dirs, ""),
								lightsOffAll and string.format(" lights off at %d", #joins) or ""))
							if lightsOffAll then lightsOff(name, joins, finish) else finish() end
						end)
					end)
				return
			end

			if i <= nJ + nL then
				local l = layout.links[i - nJ]
				local tag = string.format("%s.%s -> %s.%s", l.a, l.aDir, l.b, l.bDir)
				local function attempt(tries : integer)
					local from = arms[l.a] and arms[l.a][l.aDir] or nil
					local to = arms[l.b] and arms[l.b][l.bDir] or nil
					if from == nil or to == nil then
						failed = failed + 1
						problems[#problems + 1] = tag .. ": arm missing"
						rt.log(string.format("[SQST] %s %s: arm missing (%s built: %s, %s built: %s)", name, tag, l.a, tostring(arms[l.a] ~= nil),
							l.b, tostring(arms[l.b] ~= nil)))
						finish()
						return
					end
					local e = to.ends[1]
					local okP, proposal, seg = pcall(linkProposal, from, { id = e.node, x = e.pos[1], y = e.pos[2], z = e.pos[3], deg = 1, score = 0 })
					if not okP or proposal == nil then
						failed = failed + 1
						problems[#problems + 1] = tag .. ": proposal error"
						rt.log(string.format("[SQST] %s %s: link proposal error %s", name, tag, tostring(proposal)))
						finish()
						return
					end
					sendLink(tag, proposal as SimpleProposal, seg as {{number}}, tries, function() attempt(tries - 1) end)
				end
				attempt(LINK_TRIES)
				return
			end

			-- town links
			local ti = i - nJ - nL
			local t = layout.towns[ti]
			local tp = townOf[t.from]
			local arm = arms[t.from] and arms[t.from][t.dir] or nil
			local tag = string.format("%s.%s -> %s", t.from, t.dir, t.name)
			if arm == nil or tp == nil or townEntity[t.from] == nil then
				failed = failed + 1
				problems[#problems + 1] = tag .. ": arm or town missing"
				rt.log(string.format("[SQST] %s %s: arm or town missing", name, tag))
				finish()
				return
			end
			arm.town, arm.townPos, arm.townName = townEntity[t.from], { tp.x, tp.y }, tp.name
			local function attempt(tries : integer)
				local ranked = logic.rankTownNodes(townNodes(tp.x, tp.y, CROSS_TOWN_R, ours, streetMap()), { arm.x, arm.y }, { tp.x, tp.y },
					CROSS_TOWN_R, avoid)
				local c : SquareStressNodeCand = nil
				for _, cand in ipairs(ranked) do
					if not arm.tried[cand.id] then c = cand break end
				end
				if c == nil then
					failed = failed + 1
					problems[#problems + 1] = tag .. ": no town street to link to"
					rt.log(string.format("[SQST] %s %s: no town street node left (candidates=%d)", name, tag, #ranked))
					finish()
					return
				end
				arm.tried[c.id] = true
				local okP, proposal, seg = pcall(linkProposal, arm, c)
				if not okP or proposal == nil then
					failed = failed + 1
					problems[#problems + 1] = tag .. ": proposal error"
					rt.log(string.format("[SQST] %s %s: link proposal error %s", name, tag, tostring(proposal)))
					finish()
					return
				end
				sendLink(tag, proposal as SimpleProposal, seg as {{number}}, tries, function() attempt(tries - 1) end,
					function() townLinked[ti] = true end)
			end
			attempt(NODE_TRIES)
		end, { serial = true, label = "Building the crossing test" })
	end)
end


---------------------------------------------------------------------------
-- Showcase (stress_logic.showcaseLayout, plans/square_stress_test/SHOWCASE.md "Showcase v2"): one
-- button, groups only. Per group one junction (every interchange, roundabout and plain game crossing
-- type in turn, random params from a seed drawn fresh per press) with a Medium town on every
-- arm, close around it; groups are joined to nothing else. Stage 1 the towns (towns.createGrid with
-- explicit points and sizes, wide grid streets, named by test, set, side and mode: "Parclo 3 N (Smart lanes)", ...; a town whose spot fails the land check is
-- skipped, not the whole Showcase: its arm stays unlinked, its set logs match=no); then every group's junction pre-checked
-- and built back to back, each waiting for its own callback only, where its footprint is measured
-- (the new street nodes around it: "reach est=..m measured=..m"); one settle (INLINE_SETTLE_MS after the
-- last build); then every placement's arm ends read (only within its measured footprint +
-- SHOW_ARM_MARGIN, so town streets grown meanwhile don't count), its zone line logged (the traffic log,
-- FLOW.md "Showcase zones"), the lights of a plain crossing switched off when drawn so, and its arms
-- matched to its towns by their measured headings (a town without an arm within MAX_ARM_DEG gets the
-- nearest free arm); then every arm linked to its town (NODE_TRIES town nodes; a highway arm as both
-- carriageways with the large-street merge piece, linkProposal). A placement refused by the check with
-- "Construction Not Possible" is redrawn once (same type and arms); a refused link is sent again
-- LINK_RETRY_MS later; after a "Collision" a town link takes the nearest node, along the arm first. A town
-- link only ever ends on a node of its own town's grid (logic.ownTownNodes, notOwnTown); an arm left unlinked
-- marks its set match=no reason=link (a `showcase zone_match` line after the links). Links are locked country
-- roads (linkProposal country); every street in a junction's zone is locked with its towns (showAreas zones).
-- The build turns Keep balance on, and the bus lines (across every group) always follow.
-- Town growth locked into the grid (spec.lockStreets, SHOWCASE.md "Town growth locked into the grid"): the
-- grids are built locked (createGrid streets = 3), every town's own streets are locked right after the
-- towns (towns.lockTowns, pass "towns", before any junction), every link edge goes out locked
-- (linkProposal lock), and after the links a second lock pass removes the corner stubs no link uses;
-- then every town grows denser (towns.densify: level weights, x growFactor in growPasses passes, a leak
-- check after each), job "<name>_grow", before the bus lines.
--
-- Lights showcase (stress_logic.lightsSpec, SHOWCASE.md "Lights showcase" and "Faster, simpler Lights
-- showcase"): the same code with another spec: ONE lit junction shape per press in every set (2x2 X, 3x3 X,
-- 3x2 X, T 2x2 all on one map: lightsMixedSpec; two-way country arms; the light asked for in the construction:
-- sqst_x_lights Yes; square layout: 90 deg, never turned, towns on the axes at one distance, each link
-- straight to the middle of its town's facing side), four twins per set (sl, game, sl_phases, sl_lock),
-- Medium towns (all); at each read the junction node's light is checked (`lit=` on its line) and set to
-- Yes when it has none (`lights forced on at N`); after the links every town grows x10 once (towns.densify,
-- one pass, job lights_showcase_grow); no bus lines. Before 1950 (no automatic lights) a dialog says so up
-- front. Both Showcases build in batches: createGrid batch (grids, locks, towns), link groups (sendGroup).

local SHOW_ARM_GAP <const> = 20.0     -- roundabout / crossing arm ends are each their own arm (a 6-arm ring's lie ~45 m apart)
local SHOW_SCAN <const> = 40.0        -- arm ends are looked for this far beyond a placement's reach (not measured)
local SHOW_TOWN_R <const> = 0.5       -- town nodes within the town's size spacing x this may take a link
local SHOW_MEASURE <const> = 90.0     -- the footprint is measured this far beyond the reach estimate
local SHOW_HALF_W <const> = 12.0      -- road half width added to the outermost new node (the measured reach)
local SHOW_ARM_MARGIN <const> = 25.0  -- arm ends count up to this far beyond the measured reach
local SHOW_LEAD <const> = 60.0        -- a town link after a collision runs this far along the arm first

function jn.showcaseSignature() : string
	return tostring(jn.lastSeed)
end

function jn.lightsSignature() : string
	return tostring(jn.lastLightsSeed)
end

--- A Lights showcase town entry (SHOWCASE.md "Town entries must not be the bottleneck"): the middle of the
--- town's grid side facing its junction, our entry roundabout (stress_entry_streets.lua) there when it can be built.
local record ShowEntry
	ti : integer                  -- town index (layout / points / created)
	name : string                 -- the town's name
	set : integer                 -- its group's set (twins compare the same set)
	x : number                    -- the side's middle: the grid node there, the roundabout's centre
	y : number
	out : {number}                -- unit axis from the town centre out through that side
	jx : number                   -- its junction's centre (the side faces it: sideNode)
	jy : number
	dist : number                 -- from its junction's centre (outside the twin zones)
	kind : string                 -- "roundabout" / "crossroads"
	why : string                  -- crossroads: why
	node : integer                -- the side-middle grid node (removed with its edges by the roundabout's proposal)
	far : {string : integer}      -- "in" / "left" / "right" -> the far grid node of each removed edge
	farPos : {string : {number}}
	farEdge : {string : integer}  -- role -> the removed edge to that far node
	ghosts : {string : SquareStressLightGhost}  -- role -> a lit far node's config before the removal (nc.ghost; the join restores its states)
	before : {integer : boolean}  -- street nodes near it before the build
	seq : integer                 -- its scan in ShowState.scans
	res : {integer : boolean}
	ms : number
	inner : {string : ArmEnd}     -- the roundabout's arm ends by role (in / left / right)
	outer : ArmEnd                -- its outward arm end: the junction link's target
	joined : integer              -- inner joins made (of 3)
	broken : string               -- read or joins failed: why
	inK : integer                 -- its inward arm's reach: index into logic.ENTRY_IN_REACHES (nil: not built)
	ring : integer                -- its ring: sqst_entry_ring (2: 3 lanes, 1: 2 lanes; nil: not built)
	locked : integer              -- its own streets locked after the build (lockEntry; nil: not yet)
	lockOk : boolean              -- every one of them locked
	lockSent : boolean            -- its lock step ran
	lockPending : boolean         -- its build-time lock is in flight (not answered yet)
	lockChecked : boolean         -- the read said so when not all locked (once)
	builtUs : integer             -- when its build was answered (rt.nowUs)
end

--- A placement built in the build phase; its arms are read after the settle.
local record ShowPlace
	tag : string
	case_ : SquareStressJunctionCase  -- what was built (a redraw after a refusal replaces the planned case)
	label : string                -- its type (reach log per type)
	where : string                -- position, angle, reach and params for its log line
	x : number
	y : number
	est : number                  -- the reach estimate (logic.showcaseReach)
	wideR : number                -- the snapshot / measuring circle
	scanR : number                -- arm ends are read within this
	measured : number             -- measured reach (nil: not measured)
	measureText : string
	resList : {{integer}}         -- its build's resultEntities (bbox when measured at the read)
	gap : number
	before : {integer : boolean}  -- street nodes near it before the build
	seq : integer                 -- its scan in ShowState.scans
	res : {integer : boolean}     -- its build's result entities (log evidence)
	ms : number
	built : boolean
	group : integer               -- its group (zone id g<N>)
	lightsOff : boolean           -- plain crossing drawn without lights
	redrawn : boolean             -- the check refused its planned draw and it was redrawn (its set may no longer match)
	onArms : function(clusters : {SquareStressArmCluster}, ends : {ArmEnd}) : string
end

local record ShowTask
	kind : string                 -- "zones" (Smart Lanes' acknowledgement), "ebuild" / "elock" / "eread" / "elink" (town entries), "gbuild",
	                              -- "settle", "read" (a placement's arms), "glink"
	entry : ShowEntry
	group : integer
	k : integer                   -- glink: the town's position in its group
	arm : Arm
	pl : ShowPlace
	members : {ShowTask}          -- glink, a group's first task: every link of its one proposal (itself first)
	grouped : boolean             -- glink: linked by its group's proposal (its own step only finishes)
	solo : boolean                -- glink: its group was refused (or it could not join): sent on its own
end

local record ShowState
	name : string
	spec : SquareStressShowcaseSpec                -- which variant (stress_logic SHOWCASE_SPEC / LIGHTS_SPEC)
	ctx : Context
	seed : integer
	files : {string : string}
	layout : SquareStressShowcaseLayout
	points : {SquareStressGridPoint}               -- the towns' map positions (createGrid)
	created : {integer : integer}                  -- town index -> town entity
	tasks : {ShowTask}
	ours : {integer : boolean}                     -- street nodes of our placements
	built : integer
	refused : integer
	linked : integer
	unlinked : integer
	builtBy : {string : integer}                   -- kind -> junctions built
	plannedBy : {string : integer}
	builtAb : {string : integer}                   -- A/B mode -> junctions built
	plannedAb : {string : integer}
	zones : {SquareStressShowcaseZone}             -- per group (logic.showcaseZones, map positions)
	problems : {string}
	groupLinked : {integer : {integer : boolean}}  -- group index -> its town positions linked
	avoid : {{{number}}}                           -- link roads built so far (rankTownNodes)
	scans : {Scan}                                 -- every placement's scan, in send order (newEnds)
	reach : {string : {number}}                    -- type label -> {placed, over the estimate, worst measured - estimate}
	reachOrder : {string}
	setPlaces : {integer : {ShowPlace}}            -- set -> its twins' placements (the match on the zone lines)
	setOrder : {integer}
	skippedTowns : {integer : boolean}             -- town index -> skipped by createGrid (no land)
	skipped : integer
	lostSets : {integer : boolean}                 -- sets with a skipped town in any twin (match=no reason=town)
	lostLinks : {integer : boolean}                -- sets with an unlinked arm in any twin (match=no reason=link, zone_match lines after the links)
	zonesRun : string                              -- run id of the zones sent to Smart Lanes (nil: not sent)
	linksPlanned : boolean                         -- the glink tasks are grouped (planLinkGroups)
	tm : {string : number}                         -- timing: phase -> ms (logic.TIMING_PHASES), t0 / jT0 / lT0 (us), pending jobs
	entries : {ShowEntry}                          -- Lights showcase: every live town's entry
	entryOf : {integer : ShowEntry}                -- town index -> its entry
	entryFile : string                             -- the roundabout's construction resource (nil: not found)
	lostEntries : {integer : boolean}              -- sets whose towns' entries differ between twins (match=no reason=entry)
	entryStep : integer                            -- the ladder step (entryLadder) the entries start from: the
	                                               -- shortest one an entry needed so far (nil: 1)
	entryDir : integer                             -- the entry ring's sqst_entry_dir (1 anticlockwise, 2 clockwise), read
	                                               -- once at the first entry with its streets (nil: not yet)
	aborted : boolean                              -- a bench stopped at its zones ack (nothing more built)
	lostGeom : {integer : boolean}                 -- bench sets with a twin failing its geometry check (match=no reason=geometry)
end

--- Seed of a new run: the wall clock and the session clock (so two runs in one second differ).
local function newSeed() : integer
	local okT, t = pcall(os.time)
	local s = (okT and t ~= nil) and t or 0
	return logic.showcaseSeed(s * 1000 + math.floor(rt.nowUs() / 1000))
end

--- " bbox=Nm" from the BOUNDING_VOLUME of a build's construction (its farthest corner from (x, y);
--- log evidence next to the node measurement), "" when none can be read.
local function conBoxText(res : {{integer}}, x : number, y : number) : string
	local ok, t = pcall(function() : string
		for _, er in ipairs(res or {}) do
			local e = er[1]
			if comp(e, api.type.ComponentType.CONSTRUCTION) ~= nil then
				local bv = comp(e, api.type.ComponentType.BOUNDING_VOLUME) as Engine.Component.BoundingVolume
				if bv ~= nil and bv.bbox ~= nil then
					local a, b = bv.bbox.min, bv.bbox.max
					local far = 0.0
					for _, cx in ipairs({ a.x, b.x }) do
						for _, cy in ipairs({ a.y, b.y }) do far = math.max(far, math.sqrt((cx - x) ^ 2 + (cy - y) ^ 2)) end
					end
					return string.format(" bbox=%.0fm", far)
				end
			end
		end
		return ""
	end)
	return ok and t or ""
end

--- Right after a placement's build callback: its measured reach (the farthest new street node within
--- its wide circle + SHOW_HALF_W; nil without new nodes), and the "reach est=..m measured=..m" text.
--- Sets where its arm ends are read: within the measured reach + SHOW_ARM_MARGIN. late: measured at
--- the read instead (no new node seen at the callback; nodes a later build added are left out, laterOwns).
local function measurePlace(s : ShowState, pl : ShowPlace, res : {{integer}}, late? : boolean)
	local far, n = 0.0, 0
	for node in pairs(nodesNear(pl.x, pl.y, pl.wideR)) do
		if not pl.before[node] then
			local p = nodePos(node)
			if p ~= nil and late and laterOwns(node, p, s.scans, pl.seq) then p = nil end
			if p ~= nil then
				n = n + 1
				far = math.max(far, math.sqrt((p[1] - pl.x) ^ 2 + (p[2] - pl.y) ^ 2))
			end
		end
	end
	local box = conBoxText(res, pl.x, pl.y)
	if n == 0 then
		pl.measureText = string.format("reach est=%.0fm measured=?%s", pl.est, box)
		return
	end
	pl.measured = far + SHOW_HALF_W
	pl.scanR = math.min(pl.wideR, pl.measured + SHOW_ARM_MARGIN)
	pl.measureText = string.format("reach est=%.0fm measured=%.0fm%s%s%s", pl.est, pl.measured, pl.measured >= pl.wideR and "+" or "",
		late and " (at the read)" or "", box)
	local st = s.reach[pl.label]
	if st == nil then
		st = { 0, 0, -math.huge }
		s.reach[pl.label] = st
		s.reachOrder[#s.reachOrder + 1] = pl.label
	end
	st[1] = st[1] + 1
	if pl.measured > pl.est then st[2] = st[2] + 1 end
	st[3] = math.max(st[3], pl.measured - pl.est)
end

--- "[SQST] showcase reach: Roundabout 7 measured, 0 over the estimate (worst -20m); ..." (one line).
local function reachSummary(s : ShowState) : string
	local parts : {string} = {}
	for _, label in ipairs(s.reachOrder) do
		local st = s.reach[label]
		parts[#parts + 1] = string.format("%s %d measured, %d over the estimate (worst %+.0fm)", label, st[1], st[2], st[3])
	end
	return string.format("[SQST] %s reach: %s", s.name, #parts > 0 and table.concat(parts, "; ") or "nothing measured")
end

local function placeText(case_ : SquareStressJunctionCase, x : number, y : number, angle : number, reach : number, lights : string) : string
	return string.format("at %.0f,%.0f angle=%.0f reach=%.0fm%s [%s]", x, y, math.deg(angle), reach, lights, logic.showcaseParamText(case_))
end

--- Pre-check and build the placement `pl` (pl.group, pl.lightsOff, pl.gap set); finish() on the
--- build's callback (the next placement goes at once). Its "read" task, after the settle, reads the new
--- arm ends and passes their clusters to pl.onArms, which returns the text for the placement's log
--- line. A placement the check refuses gets one more check if retry(verdict) offers another case (and
--- the note for the log: "redrawn"); pl.case_ is what was built.
local function showPlace(s : ShowState, pl : ShowPlace, tag : string, case_ : SquareStressJunctionCase, x : number, y : number,
		angle : number, reach : number, seedI : integer, finish : function(),
		retry? : function(verdict : string) : (SquareStressJunctionCase, string))
	local name = s.name
	local lights = ""
	if case_.file == logic.SHOWCASE_PLAIN_FILE then
		lights = pl.lightsOff and " lights=off" or (case_.params.sqst_x_lights == 2 and " lights=yes" or " lights=game")
	end
	local where = placeText(case_, x, y, angle, reach, lights)
	local verdict = precheck(junctionProposal(s.files[case_.file], case_, x, y, seedI, angle), s.ctx)
	if verdict ~= nil and verdict ~= "ok" and retry ~= nil then
		local okR, c2, note = pcall(retry, verdict)
		if okR and c2 ~= nil and s.files[c2.file] ~= nil then
			-- the refused params stay in the log: that type and settings can be tried alone in game
			rt.log(string.format("[SQST] %s %s %s refused by the check: %s; %s", name, tag, where, verdict, tostring(note)))
			pl.redrawn = true
			local first = verdict
			case_, reach = c2, logic.showcaseReach(c2)
			where = string.format("%s (%s)", placeText(case_, x, y, angle, reach, lights), tostring(note))
			verdict = precheck(junctionProposal(s.files[case_.file], case_, x, y, seedI, angle), s.ctx)
			if verdict ~= nil and verdict ~= "ok" then
				verdict = string.format("%s (first: %s)", verdict, first)
			else
				s.problems[#s.problems + 1] = string.format("%s: %s, then %s (the refused params are in the log)", tag, first, tostring(note))
			end
		end
	end
	if verdict ~= nil and verdict ~= "ok" then
		s.refused = s.refused + 1
		rt.log(string.format("[SQST] %s %s %s refused by the check: %s", name, tag, where, verdict))
		s.problems[#s.problems + 1] = string.format("%s: %s", tag, verdict)
		finish()
		return
	end
	local file = s.files[case_.file]
	pl.case_ = case_
	pl.tag, pl.label, pl.where, pl.x, pl.y, pl.est = tag, case_.label, where, x, y, reach
	pl.wideR = reach + SHOW_MEASURE
	pl.scanR = reach + SHOW_SCAN
	pl.before = nodesNear(x, y, pl.wideR)
	s.scans[#s.scans + 1] = { x = x, y = y, r = pl.wideR, before = pl.before }
	pl.seq = #s.scans
	local t0 = rt.nowUs()
	rt.send(name, api.cmd.makeWorldBuildProposalCmd(junctionProposal(file, case_, x, y, seedI, angle), s.ctx, false, true, false),
		function(success : boolean, data : any, res : {{integer}})
			local ms = (rt.nowUs() - t0) / 1000
			if not success then
				s.refused = s.refused + 1
				rt.log(string.format("[SQST] %s %s %s build failed ms=%.0f %s", name, tag, where, ms, errText(data)))
				s.problems[#s.problems + 1] = string.format("%s: build failed", tag)
				finish()
				return
			end
			s.built = s.built + 1
			local gr = s.layout.groups[pl.group]
			local slot = gr ~= nil and (gr.slot or gr.kind) or "?"
			s.builtBy[slot] = (s.builtBy[slot] or 0) + 1
			if gr ~= nil and gr.ab ~= nil then s.builtAb[gr.ab] = (s.builtAb[gr.ab] or 0) + 1 end
			pl.built, pl.ms, pl.res, pl.resList = true, ms, resultIds(res), res
			local okM, err : boolean, any = pcall(measurePlace, s, pl, res)
			if not okM then pl.measureText = "measure error: " .. tostring(err) end
			finish()
		end)
end

--- What a refused build's proposal data collided with (collisionText: "(hits 3 streets, ...)"), "" when
--- nothing is listed (2026-10-12: two link Collisions in the Lights showcase logged no entity kinds).
local function resultHits(data : any, labels? : {integer : string}) : string
	local ok, t = pcall(function() : string
		return collisionText((data as WorldBuildProposalCommandData).resultProposalData as ProposalData, labels)
	end)
	return ok and t ~= nil and t or ""
end

--- Sends the proposal of make(try, why)'s builder (why: the previous refusal's error text; make's 4th
--- result names a variant route for the log); a refused one is made and sent again LINK_RETRY_MS later,
--- up to `tries` times; then done(linked).
local function showLink(s : ShowState, tag : string, make : function(try : integer, why : string) : Builder, {{number}}, string, string,
		tries : integer, done : function(ok : boolean))
	local name = s.name
	local function attempt(k : integer, why : string)
		local okP, proposal, seg, err, variant = pcall(function() : SimpleProposal, {{number}}, string, string
			local b, sg, e, v = make(k, why)
			if b == nil then return nil, sg, e, v end
			return assemble(b), sg, e, v
		end)
		if not okP or proposal == nil then
			local text = okP and tostring(err) or tostring(proposal)
			rt.log(string.format("[SQST] %s %s: not linked (%s)", name, tag, text))
			s.problems[#s.problems + 1] = string.format("%s: not linked (%s)", tag, text)
			done(false)
			return
		end
		local via = variant ~= nil and string.format(" (%s)", tostring(variant)) or ""
		local t0 = rt.nowUs()
		rt.send(name, api.cmd.makeWorldBuildProposalCmd(proposal as SimpleProposal, s.ctx, false, true, false), function(success : boolean, data : any)
			if success then
				if seg ~= nil then s.avoid[#s.avoid + 1] = seg as {{number}} end
				local line = string.format("[SQST] %s %s linked ms=%.0f%s", name, tag, (rt.nowUs() - t0) / 1000, via)
				if variant ~= nil then rt.log(line) else rt.detail(line) end
				done(true)
			elseif k < tries then
				local e = errText(data) .. resultHits(data)
				rt.log(string.format("[SQST] %s %s: link refused%s (%s); trying again in %.0f s (%d/%d)", name, tag, via, e,
					LINK_RETRY_MS / 1000, k + 1, tries))
				rt.later(name .. ":relink", LINK_RETRY_MS, function() attempt(k + 1, e) end)
			else
				rt.log(string.format("[SQST] %s %s: link refused %d times (%s%s)", name, tag, tries, errText(data), resultHits(data)))
				s.problems[#s.problems + 1] = string.format("%s: link refused", tag)
				done(false)
			end
		end)
	end
	attempt(1, nil)
end

local function collision(why : string) : boolean
	return why ~= nil and why:find("Collision", 1, true) ~= nil
end

--- An arm's heading (unit vector, the mean of its ends' headings), nil when unknown.
local function armHeading(ends : {ArmEnd}) : {number}
	local hx, hy = 0.0, 0.0
	for _, e in ipairs(ends) do
		if e.dir ~= nil then hx, hy = hx + e.dir[1], hy + e.dir[2] end
	end
	local l = math.sqrt(hx * hx + hy * hy)
	if l <= 0 then return nil end
	return { hx / l, hy / l }
end

--- Sets each cluster's measured heading (hx, hy) from its ends (logic.assignArms matches by it).
local function clusterHeadings(clusters : {SquareStressArmCluster}, ends : {ArmEnd})
	for _, cl in ipairs(clusters) do
		local list : {ArmEnd} = {}
		for _, m in ipairs(cl.members) do list[#list + 1] = ends[m] end
		local h = armHeading(list)
		if h ~= nil then cl.hx, cl.hy = h[1], h[2] end
	end
end

--- Whether node c is its arm's own town's: within the town's grid square + OWN_TOWN_MARGIN, and (when
--- the game names one) the closest town of its spot is the arm's town. nil, or why not.
local function notOwnTown(arm : Arm, c : SquareStressNodeCand) : string
	local area : SquareStressLockArea = { town = arm.town, label = arm.townName, x = arm.townPos[1], y = arm.townPos[2], half = arm.townHalf or 0 }
	if #logic.ownTownNodes({ c }, area) == 0 then
		return string.format("node %d at %.0f,%.0f is outside %s's grid", c.id, c.x, c.y, tostring(arm.townName))
	end
	local okT, t = pcall(function() : integer return api.engine.util.town.getClosestTown(api.type.Vec3f.new(c.x, c.y, 0)) end)
	if okT and type(t) == "number" and t >= 0 and arm.town ~= nil and t ~= arm.town then
		return string.format("node %d at %.0f,%.0f: its closest town is %d, not %s (%d)", c.id, c.x, c.y, t, tostring(arm.townName), arm.town)
	end
	return nil
end

local SIDE_TOL <const> = 15.0         -- square layout: the grid node at the middle of its facing side is looked for this close

--- Town ti's grid: its centre, grid half-size and node search radius (its size's spacing x SHOW_TOWN_R).
local function townGrid(s : ShowState, ti : integer) : {number}, number, number
	local p = s.points[ti]
	local lt = s.layout.towns[ti]
	local size = lt ~= nil and logic.TOWN_SIZES[lt.size or 1] or logic.TOWN_SIZES[1]
	return { p.x, p.y }, logic.gridHalfOfSize(lt ~= nil and lt.size or 1), size.spacing * SHOW_TOWN_R
end

--- The grid node at the middle of a town's side facing (jx, jy) (square layout), shared by the junction link
--- (its target) and the town entry (the node its roundabout replaces): the town's own street nodes (townNodes
--- within r of its centre tp, logic.ownTownNodes) nearest logic.sideCentre within SIDE_TOL. Returns the node
--- (nil: none that close), the side's middle, the count of own nodes and a log note on the nearest of them
--- (" nearest=N at Dm", "" when none; for the fallback lines). The octree is asked around the town
--- centre, never with a small circle around the point: it matches an edge by its position, not its extent, so
--- SIDE_TOL around the node finds none of its 75 m streets (Lights showcase seed 4951, 2026-10-12: all 96
--- entries "no grid node at the side's middle" at the right spot, while the links found every node this way).
local function sideNode(s : ShowState, town : integer, label : string, tp : {number}, half : number, r : number,
		jx : number, jy : number) : SquareStressNodeCand, {number}, integer, string
	local area : SquareStressLockArea = { town = town, label = label, x = tp[1], y = tp[2], half = half }
	local cands = logic.ownTownNodes(townNodes(tp[1], tp[2], r, s.ours, streetMap()), area)
	local pt = logic.sideCentre(tp[1], tp[2], half, jx, jy)
	local c = logic.nodeAt(cands, pt, SIDE_TOL)
	local note = ""
	if c == nil then
		local near = logic.nodeAt(cands, pt, math.huge)
		if near ~= nil then
			note = string.format(" nearest=%d at %.0fm", near.id, math.sqrt((near.x - pt[1]) ^ 2 + (near.y - pt[2]) ^ 2))
		end
	end
	return c, pt, #cands, note
end

--- Arm to its town. A town link ALWAYS ends on a node of the arm's own town (user 2026-10-12, seed
--- 718344: a north arm was linked to a corner stub of the east town; SHOWCASE.md "Square layout").
--- Square layout (spec.square, Lights showcase): one straight road along the arm to the node at the middle
--- of the grid's facing side, on its central street (logic.sideCentre); no other target and no bend: a
--- refused link is sent again as it is, then the arm stays unlinked. Otherwise (Showcase) each try a
--- fresh node of the town's own grid (logic.ownTownNodes: the nearest dead end not tried yet, within the
--- town's search radius arm.townR); once a try was refused with a collision, the nearest such node (no
--- large-street preference) and, for a single end, through a point SHOW_LEAD along the arm's heading
--- first. Links are locked country roads (linkProposal lock, country) when the spec locks the streets.
--- The road lanes of an arm's link pieces: the bench group's (0: the arm's own, nil), else the spec's linkLanes.
local function armLanes(s : ShowState, arm : Arm) : integer
	if arm.linkLanes ~= nil then return arm.linkLanes > 0 and arm.linkLanes or nil end
	return s.spec.linkLanes
end

local function showToTown(s : ShowState, arm : Arm) : function(try : integer, why : string) : Builder, {{number}}, string, string
	return function(try : integer, why : string) : Builder, {{number}}, string, string
		if arm.town == nil or arm.townPos == nil then return nil, nil, "town missing", nil end
		if collision(why) then arm.collided = true end
		local tp = arm.townPos
		local r = arm.townR or 600.0
		local lock = s.spec.lockStreets == true
		local c : SquareStressNodeCand = nil
		if arm.entryNode ~= nil then
			-- the town's entry roundabout: its outward arm end (outside the grid square, ours: no own-town check)
			local p = nodePos(arm.entryNode) or arm.entryPos
			c = { id = arm.entryNode, x = p[1], y = p[2], z = p[3] or 0, deg = 1, large = true, score = 0 }
			-- a bench test with its own link road (linkLanes > 0) falls back on a refusal: try 2 copies of the arm's
			-- street, try 3 the country road of the arm's lanes (sheet 4 v1, 2026-10-13: every 1 + 1 country link from a
			-- town small arm to its entry was refused, Construction Not Possible, 108 of 108)
			local country, lanes, variant = lock, armLanes(s, arm), nil as string
			if try ~= nil and try > 1 and arm.linkLanes ~= nil and arm.linkLanes > 0 then
				if try == 2 then
					country, variant = false, "copies of the arm's street"
				else
					lanes, variant = nil, "the country road of the arm's lanes"
				end
			end
			local b, seg = linkBuilder(arm, c, nil, lock, country, lanes, arm.pairLanes)
			return b, seg, nil, variant
		end
		if s.spec.square then
			local pt : {number}
			local n : integer
			local note : string
			-- the side facing its junction's centre, as the town's entry chose it (planEntries; the arm end lies
			-- on the same axis in the square layout, but a leftover arm may not)
			c, pt, n, note = sideNode(s, arm.town, arm.townName, tp, arm.townHalf or 0, r, arm.jx or arm.x, arm.jy or arm.y)
			if c == nil then
				return nil, nil, string.format("no node of %s at the middle of its grid's side %.0f,%.0f (own nodes=%d%s)", tostring(arm.townName),
					pt[1], pt[2], n, note), nil
			end
		else
			local area : SquareStressLockArea = { town = arm.town, label = arm.townName, x = tp[1], y = tp[2], half = arm.townHalf or 0 }
			local cands = logic.ownTownNodes(townNodes(tp[1], tp[2], r, s.ours, streetMap()), area)
			local ranked = logic.rankTownNodes(cands, { arm.x, arm.y }, tp, r, s.avoid, arm.collided)
			for _, cand in ipairs(ranked) do
				if not arm.tried[cand.id] then c = cand break end
			end
			if c == nil then return nil, nil, string.format("no node of %s left, candidates=%d", tostring(arm.townName), #ranked), nil end
		end
		arm.tried[c.id] = true
		local bad = notOwnTown(arm, c)
		if bad ~= nil then return nil, nil, bad, nil end
		local via : {number} = nil
		local variant : string = nil
		if arm.collided and not s.spec.square then
			variant = "nearest town node"
			local h = armHeading(arm.ends)
			if #arm.ends == 1 and h ~= nil then
				local e = arm.ends[1]
				via = { e.pos[1] + h[1] * SHOW_LEAD, e.pos[2] + h[2] * SHOW_LEAD }
				variant = string.format("nearest town node, %.0fm along the arm first", SHOW_LEAD)
			end
		end
		local b, seg = linkBuilder(arm, c, via, lock, lock, armLanes(s, arm), arm.pairLanes)
		return b, seg, nil, variant
	end
end

--- The second chance of a placement the check refused (showPlace's retry): after "Construction Not
--- Possible" a fresh draw of its type within its planned reach (logic.showcaseRedraw: same arms, angle
--- and arm road); a group is never moved (its towns surround it). nil: no second chance.
local function placeRetry(case_ : SquareStressJunctionCase, reach : number, seedI : integer,
		spec : SquareStressShowcaseSpec) : function(verdict : string) : SquareStressJunctionCase, string
	return function(verdict : string) : SquareStressJunctionCase, string
		if verdict:find("Construction Not Possible", 1, true) ~= nil then
			local c = logic.showcaseRedraw(case_, reach, seedI * 31 + 7, spec)
			if c == nil then return nil, nil end
			return c, "redrawn"
		end
		return nil, nil
	end
end

--- An arm of a group with the town it leads to (its own search radius from the town's size).
local function townArm(s : ShowState, arm : Arm, ti : integer)
	arm.town, arm.townName = s.created[ti], s.points[ti].name
	arm.townPos, arm.townHalf, arm.townR = townGrid(s, ti)
	-- Lights showcase: a built entry roundabout takes the link at its outward arm end (its side-middle node is gone)
	local e = s.entryOf ~= nil and s.entryOf[ti] or nil
	if e ~= nil and e.kind == "roundabout" and e.outer ~= nil then arm.entryNode, arm.entryPos = e.outer.node, e.outer.pos end
end

--- A group's arms read after the settle: matched to its towns by their measured headings (a town
--- without an arm within MAX_ARM_DEG takes the nearest free arm, logged); one "glink" task per arm
--- that reaches a town, appended to the run (job.total grows). Returns the read's log text.
local function groupArms(s : ShowState, job : SquareStressJob, gi : integer, x : number, y : number, tag : string,
		clusters : {SquareStressArmCluster}, ends : {ArmEnd}) : string
	local g = s.layout.groups[gi]
	local targets : {{number}} = {}
	for k, ti in ipairs(g.towns) do targets[k] = { s.points[ti].x, s.points[ti].y } end
	local assign = logic.assignArms(x, y, clusters, targets, MAX_ARM_DEG)
	-- a skipped town takes no leftover arm (it would hold back one a live town needs)
	local skip : {integer : boolean} = {}
	for k, ti in ipairs(g.towns) do
		if s.skippedTowns[ti] then skip[k] = true end
	end
	local extra = logic.assignLeftovers(x, y, clusters, targets, assign, skip)
	for _, e in ipairs(extra) do
		rt.log(string.format("[SQST] %s %s: %s has no arm within %.0f deg; linked to the nearest free arm (%.0f deg off)", s.name, tag,
			s.points[g.towns[math.floor(e[2])]].name, MAX_ARM_DEG, e[3]))
	end
	local reached, live = 0, 0
	for _, ti in ipairs(g.towns) do
		if not s.skippedTowns[ti] then live = live + 1 end
	end
	for c = 1, #clusters do
		local k = assign[c]
		if k ~= nil and s.created[g.towns[k]] ~= nil then
			local arm = armOf(clusters[c], ends, { cell = g.name }, x, y, g.place.case_.label)
			townArm(s, arm, g.towns[k])
			arm.linkLanes, arm.pairLanes = g.linkLanes, g.pairLanes
			s.tasks[#s.tasks + 1] = { kind = "glink", group = gi, k = k, arm = arm }
			job.total = job.total + 1
			reached = reached + 1
		end
	end
	-- a town skipped for want of land is no link: its arm stays unlinked (towns_skipped in the summary)
	if reached < live then
		s.unlinked = s.unlinked + live - reached
		-- a live town without an arm is an unlinked town too: its set's twins differ (match=no reason=link)
		s.lostLinks[g.set or -gi] = true
		s.problems[#s.problems + 1] = string.format("%s: %d of %d towns without an arm", tag, live - reached, live)
	end
	return string.format("towns=%d reached=%d%s%s", live, reached, #extra > 0 and string.format(" (%d by the nearest arm)", #extra) or "",
		live < #g.towns and string.format(" skipped=%d", #g.towns - live) or "")
end

--- Whether the twins of `set` still match as built (logic.showcaseMatch): nil, or the reason(s).
local function setReason(s : ShowState, set : integer) : string
	local twins : {SquareStressShowcaseTwin} = {}
	for _, pl in ipairs(s.setPlaces[set] or {}) do
		twins[#twins + 1] = { built = pl.built, redrawn = pl.redrawn == true,
			params = pl.case_ ~= nil and logic.showcaseParamText(pl.case_) or nil }
	end
	local r = logic.showcaseMatch(twins, s.lostSets[set] == true, s.lostLinks[set] == true, (s.lostEntries or {})[set] == true)
	-- the bench's geometry check (benchGeometry)
	if (s.lostGeom or {})[set] then r = r ~= nil and (r .. ",geometry") or "geometry" end
	return r
end

local function flowWord(v : string) : string
	return (tostring(v or "-"):gsub("%s+", "_"))
end

--- "interchanges=a/b roundabouts=a/b plain=a/b" (the spec's kinds; per = "%d/%d") or "interchanges=a ..." (one count).
local function kindText(spec : SquareStressShowcaseSpec, a : {string : integer}, b? : {string : integer}) : string
	local out : {string} = {}
	-- each kind once (the mixed Lights showcase lists x three times: its share of the turns)
	local seen : {string : boolean} = {}
	for _, k in ipairs(logic.specKinds(spec)) do
		if not seen[k] then
			seen[k] = true
			local key = (spec.kindLog or {})[k] or k
			if b ~= nil then
				out[#out + 1] = string.format("%s=%d/%d", key, a[k] or 0, b[k] or 0)
			else
				out[#out + 1] = string.format("%s=%d", key, a[k] or 0)
			end
		end
	end
	return table.concat(out, " ")
end

--- " shapes 2x2_X=6/6 3x3_X=6/6 ..." per type label of a layout (built / planned: the zones built by now; nil
--- zones: planned only), in the order of first appearance; "" for a single type.
local function shapesText(layout : SquareStressShowcaseLayout, zones? : {SquareStressShowcaseZone}) : string
	local order : {string} = {}
	local planned, built : {string : integer}, {string : integer} = {}, {}
	for gi, g in ipairs(layout.groups) do
		local lbl = flowWord(g.place.case_.label)
		if planned[lbl] == nil then
			order[#order + 1] = lbl
			planned[lbl], built[lbl] = 0, 0
		end
		planned[lbl] = planned[lbl] + 1
		if zones ~= nil and zones[gi] ~= nil and zones[gi].built then built[lbl] = built[lbl] + 1 end
	end
	if #order < 2 then return "" end
	local parts : {string} = {}
	for _, lbl in ipairs(order) do
		parts[#parts + 1] = zones ~= nil and string.format("%s=%d/%d", lbl, built[lbl], planned[lbl]) or string.format("%s=%d", lbl, planned[lbl])
	end
	return " shapes " .. table.concat(parts, " ")
end

--- The run's towns as lock areas: each town with its grid (centre = its point, half by its size) and,
--- with zones (one per group, map positions), its junction's zone {x, y, r} (every street there is
--- locked with the town's, stress_towns scanTown) and its streets looked for out to that junction.
local function showAreas(layout : SquareStressShowcaseLayout, points : {SquareStressGridPoint}, created : {integer : integer},
		skipped : {integer : boolean}, zones? : {SquareStressShowcaseZone}) : {SquareStressLockArea}
	local out : {SquareStressLockArea} = {}
	local zonesOf : {integer : {{number}}} = {}
	if zones ~= nil then
		for gi, g in ipairs(layout.groups) do
			local z = zones[gi]
			if z ~= nil and z.built then
				for _, ti in ipairs(g.towns) do
					zonesOf[ti] = zonesOf[ti] or {}
					table.insert(zonesOf[ti], { z.x, z.y, z.r or 0 })
				end
			end
		end
	end
	for ti = 1, #layout.towns do
		local t, p = created[ti], points[ti]
		if t ~= nil and p ~= nil and not (skipped or {})[ti] then
			local a : SquareStressLockArea = { town = t, label = p.name, x = p.x, y = p.y, half = logic.gridHalfOfSize(layout.towns[ti].size),
				target = layout.towns[ti].pop }
			if zonesOf[ti] ~= nil then
				a.zones = zonesOf[ti]
				local far = 0.0
				for _, z in ipairs(a.zones) do far = math.max(far, math.sqrt((z[1] - p.x) ^ 2 + (z[2] - p.y) ^ 2)) end
				a.reach = far
			end
			out[#out + 1] = a
		end
	end
	return out
end

--- The run's timing (SHOWCASE.md "Timing"): ms since the press.
local function sinceMs(us : number) : number
	return (rt.nowUs() - us) / 1000
end

--- The "[SQST] <id> timing ..." line and the total in minutes, once: after the summary, when no timed job
--- of the run is left (the lock passes, the depots, the growth).
local function timingDone(s : ShowState)
	if (s.tm.pending or 0) > 0 or s.tm.summary == nil or s.tm.logged ~= nil then return end
	s.tm.logged = 1
	local total = sinceMs(s.tm.t0)
	rt.log(logic.timingLine(s.name, s.tm, total))
	rt.log(string.format("[SQST] %s finished in %s min (seed %d)", s.name, logic.minutesText(total), s.seed))
	-- the bench orchestrator (gui/stress_bench_run.tl) goes on from here
	if jn.onRunFinished ~= nil then
		local okF, errF : boolean, any = pcall(jn.onRunFinished, s.name, s.seed, s.layout, s.zones)
		if not okF then rt.log("[SQST] " .. s.name .. " finished hook error: " .. tostring(errF)) end
	end
end

--- A timed job of the run queued: its onDone(ms) adds ms to `phase` and logs the timing when it was the last.
local function timed(s : ShowState, phase : string) : function(ms : number)
	s.tm.pending = (s.tm.pending or 0) + 1
	return function(ms : number)
		s.tm[phase] = (s.tm[phase] or 0) + (ms or 0)
		s.tm.pending = s.tm.pending - 1
		timingDone(s)
	end
end

--- After the links: (lockStreets) every town street locked once more (the link nodes' replaced edges,
--- anything grown since) and the corner stubs no link uses removed, job "<name>_lock"; then (bus lines) every
--- route's depot built while the towns are still small, job "<name>_depots" (seed 718344: after the growth
--- every depot spot collided with buildings; the lines later reuse these depots: stress_buslines
--- prebuildDepots); then (growFactor) every town grows: level weights shifted up, the spec's factor and
--- build-out passes (one pass: no leak check between), job "<name>_grow" (towns.densify). Serial jobs: the
--- bus lines queued later wait. Each reports its ms to the run's timing line.
local function growTowns(s : ShowState, routes : {SquareStressBusRoute})
	local sp = s.spec
	if s.built == 0 then return end
	local areas = showAreas(s.layout, s.points, s.created, s.skippedTowns, s.zones)
	if #areas == 0 then return end
	if sp.lockStreets then towns.lockTowns(s.name .. "_lock", areas, { pass = "links", stubs = true, onDone = timed(s, "locks") }) end
	if not sp.noBusLines and #routes > 0 then
		buslines.prebuildDepots(s.name .. "_depots", routes, timed(s, "depots"))
	end
	if sp.growFactor == nil then return end
	rt.log(string.format("[SQST] %s grow queued towns=%d factor=x%g passes=%d weights=%s locked=%s%s (Grow's own options x%g / %d passes; after the links, before the bus lines)",
		s.name, #areas, sp.growFactor, sp.growPasses or 1, sp.denseWeights ~= nil and logic.listText(sp.denseWeights) or "town's own",
		tostring(sp.lockStreets == true), sp.growTarget ~= nil and string.format(" target=%d", math.floor(sp.growTarget)) or "",
		sp.growFactor, sp.growPasses or 1))
	towns.densify(s.name .. "_grow", areas, { factor = sp.growFactor, passes = sp.growPasses or 1, weights = sp.denseWeights,
		target = sp.growTarget, onDone = timed(s, "density") })
end

--- After the last step: the summary lines (per kind), the bus routes across every group (each with its
--- road network), the Lights showcase's town growth, and the problems dialog.
local function showSummary(s : ShowState)
	local nGroups = #s.layout.groups
	local sp = s.spec
	local abText : {string} = {}
	for _, m in ipairs(logic.specModes(sp)) do abText[#abText + 1] = string.format("%s=%d/%d", m.ab, s.builtAb[m.ab] or 0, s.plannedAb[m.ab] or 0) end
	-- an arm left unlinked (link refused, or no node of its own town to end on) is known only now: every
	-- built twin of its set gets a late verdict line (its zone line was written at the read)
	for gi, g in ipairs(s.layout.groups) do
		local set = g.set or -gi
		local z = s.zones[gi]
		if (s.lostLinks[set] or (s.lostEntries or {})[set] or (s.lostGeom or {})[set]) and z ~= nil and z.built then
			z.reason = setReason(s, set)
			rt.log(logic.showcaseZoneMatchLine(z))
		end
	end
	local mismatch = 0
	for _, set in ipairs(s.setOrder) do
		if setReason(s, set) ~= nil then mismatch = mismatch + 1 end
	end
	-- the junctions phase ends with the first link (or here when there was none), the links phase here
	if s.tm.lT0 ~= nil then
		s.tm.links = sinceMs(s.tm.lT0)
	elseif s.tm.jT0 ~= nil then
		s.tm.junctions = sinceMs(s.tm.jT0)
	end
	local mins = logic.minutesText(sinceMs(s.tm.t0))
	rt.log(string.format("[SQST] %s summary seed=%d groups=%d built=%d refused=%d %s %s links=%d linked=%d unlinked=%d towns_skipped=%d sets_mismatch=%d minutes=%s",
		s.name, s.seed, nGroups, s.built, s.refused, kindText(sp, s.builtBy, s.plannedBy) .. shapesText(s.layout, s.zones), table.concat(abText, " "), s.linked + s.unlinked,
		s.linked, s.unlinked, s.skipped, mismatch, mins))
	rt.log(reachSummary(s))
	if s.entries ~= nil and #s.entries > 0 then
		local rb, cr, broken, joined = 0, 0, 0, 0
		for _, e in ipairs(s.entries) do
			if e.kind == "roundabout" then rb = rb + 1 else cr = cr + 1 end
			if e.broken ~= nil then broken = broken + 1 end
			joined = joined + (e.joined or 0)
		end
		rt.log(string.format("[SQST] %s entries roundabout=%d crossroads=%d broken=%d joins=%d/%d", s.name, rb, cr, broken, joined, 3 * rb))
	end
	local routes : {SquareStressBusRoute} = {}
	-- every junction zone: a route's stops and depots stay out of all of them (2026-10-12: a depot beside a
	-- Roundabout Interchange's ramp, red no-entry sign at its gate)
	local zones : {{number}} = {}
	for _, z in ipairs(s.zones) do zones[#zones + 1] = { z.x, z.y, z.r or 0 } end
	-- no bus lines (Lights showcase: spec.noBusLines): no routes at all
	for _, r in ipairs(sp.noBusLines and {} as {{integer}} or logic.showcaseRoutes(s.layout, s.groupLinked, logic.TEST_ROUTES_MAX)) do
		local rr = route(s.points, s.created, r[1], r[2], (sp.title or "Showcase") .. " ", 1)
		if rr ~= nil then
			-- each town's own size (its grid: 400 m Small, 600 m Medium, 800 m Large), from the layout
			local la, lb = s.layout.towns[r[1]], s.layout.towns[r[2]]
			if la ~= nil then rr.a.half = logic.gridHalfOfSize(la.size) end
			if lb ~= nil then rr.b.half = logic.gridHalfOfSize(lb.size) end
			rr.net = string.format("group %d", r[3])
			rr.zones = zones
			-- the twin the line serves (FLOW_BUS twin= pair= ab=, gui/stress_flow_log.tl)
			local tz = s.zones[r[3]]
			if tz ~= nil then rr.twin, rr.pair, rr.ab = tz.id, tz.pair, tz.ab end
			routes[#routes + 1] = rr
		end
	end
	local text = logic.showcaseSummary(s.builtBy, s.plannedBy, s.builtAb, s.plannedAb, s.linked, s.linked + s.unlinked, #routes, s.seed,
		s.skipped, sp)
	text = text .. string.format(" Built in %s min%s.", mins, (s.built > 0 and sp.growFactor ~= nil) and " (the growth follows)" or "")
	rt.log("[SQST] " .. text)
	-- the depots and the growth first (serial), so the bus lines' stops go onto the grown towns
	growTowns(s, routes)
	queueTraffic(s.name, sp.title or "Showcase", routes)
	s.tm.summary = 1
	timingDone(s)
	if #s.problems > 0 then
		local shown : {string} = {}
		for k = 1, math.min(#s.problems, 10) do shown[k] = "- " .. s.problems[k] end
		if #s.problems > 10 then shown[#shown + 1] = string.format("... and %d more (see the log)", #s.problems - 10) end
		rt.warn(sp.title or "Showcase", string.format("%s\n%s", text, table.concat(shown, "\n")))
	end
end

--- The Showcase's first step: waits until Smart Lanes holds the zones sent before the towns (stress_slzones
--- waitAck: at once without Smart Lanes, at most ACK_TIMEOUT_MS otherwise), so no junction is built before
--- its twin mode is known there. Logs "[SQST] showcase zones ack=yes|timeout|absent|unsent run= ms=".
local function waitZones(s : ShowState, finish : function())
	slzones.waitAck(s.zonesRun, function(res : string, ms : number)
		rt.log(string.format("[SQST] %s zones ack=%s run=%s ms=%.0f", s.name, res, s.zonesRun or "-", ms))
		-- a bench without its zones in Smart Lanes would compare untreated twins: it stops here (the Showcases go on)
		-- (absent: no Smart Lanes at all, the preflight's business; offline tests build that way)
		if s.spec.bench and (res == "timeout" or res:sub(1, 8) == "refused:") then
			s.aborted = true
			rt.log(string.format("[SQST] %s stopped: Smart Lanes %s the zones (ack=%s)", s.name,
				res:sub(1, 8) == "refused:" and "refused" or "did not acknowledge", res))
			if jn.onRunAborted ~= nil then
				pcall(jn.onRunAborted, s.name, string.format("Smart Lanes did not take the twins' zones (ack=%s)", res))
			end
		end
		finish()
	end)
end

--- Lights showcase: the light at a junction node: "N:pref=yes|no|auto|?,light=yes|no" and whether it is
--- lit (preference YES, or a BASE_NODE_TRAFFIC_LIGHT component: as Smart Lanes reads lit=yes).
local function litOf(n : integer) : string, boolean
	local pref = "?"
	local okP, p = pcall(function() : TrafficLightPreference
		local cfg = comp(n, api.type.ComponentType.BASE_NODE_CONFIG) as Engine.Component.BaseNodeConfig
		return cfg.trafficLightPreference
	end)
	if okP and p ~= nil then
		local E = api.type.enum.TrafficLightPreference
		if p == E.YES then pref = "yes" elseif p == E.NO then pref = "no" elseif p == E.AUTO then pref = "auto" end
	end
	local okL, light = pcall(function() : boolean
		return comp(n, api.type.ComponentType.BASE_NODE_TRAFFIC_LIGHT) ~= nil
	end)
	local lit = pref == "yes" or (okL and light)
	return string.format("%d:pref=%s,light=%s", n, pref, (okL and light) and "yes" or "no"), lit
end

--- Lights showcase read: " lit=<node:pref,light ...>" for its log line, and the junction nodes without a
--- light (the construction's Yes did not take, and AUTO made none yet: before 1950, or not yet).
local function litCheck(joins : {integer}) : string, {integer}
	local parts : {string} = {}
	local dark : {integer} = {}
	for _, n in ipairs(joins) do
		local t, lit = litOf(n)
		parts[#parts + 1] = t
		if not lit then dark[#dark + 1] = n end
	end
	return string.format(" lit=%s", #parts > 0 and table.concat(parts, ";") or "none"), dark
end

--- The bench's geometry check of a built twin (BENCH.md "As built": every variant must present what it tests):
--- a lane drop has a 2-street node whose two streets differ in road lanes; a roundabout / channelized junction one-way
--- streets (its ring, its slip lanes), a ring built with mid nodes (square_roundabouts' sqrb_dev_ring_mid, the entry
--- ring's sqst_entry_mid; Sheet 4) also at least 4 per gap nodes joining two one-way streets only (mids=); an interchange one-way carriageways and ramps; a plain
--- crossing a junction node. Reads only the new nodes of the build (not in `before`) within r of its centre. Returns ok,
--- a log text.
local function benchGeometry(pl : ShowPlace, g : SquareStressShowcaseGroup) : boolean, string
	local map = streetMap()
	local oneWay, two, best : integer, integer, string = 0, 0, nil
	local mids = 0
	local seen : {integer : boolean} = {}
	for n in pairs(nodesNear(pl.x, pl.y, pl.scanR or (pl.est or 100))) do
		if not (pl.before or {})[n] then
			local list = map[n] or {}
			if #list == 2 then
				two = two + 1
				local a, b = twoWayLanes(list[1]), twoWayLanes(list[2])
				if a ~= nil and b ~= nil and a ~= b and best == nil then best = string.format("%d>%d", math.max(a, b), math.min(a, b)) end
				if a == nil and b == nil then mids = mids + 1 end
			end
			for _, e in ipairs(list) do
				if not seen[e] then
					seen[e] = true
					local okE, be = pcall(comp, e, api.type.ComponentType.BASE_EDGE)
					if okE and be ~= nil and twoWayLanes(e) == nil then oneWay = oneWay + 1 end
				end
			end
		end
	end
	local p = pl.case_ ~= nil and pl.case_.params or {}
	if p.sqst_x_shape == 4 then
		return best ~= nil, string.format("what=lane_drop two_street_nodes=%d lanes=%s", two, best or "same")
	end
	-- mid nodes asked for: square_roundabouts' sqrb_dev_ring_mid n (n per gap) or the entry ring's sqst_entry_mid n + 1;
	-- 4 arms, so 4 n such nodes
	local perGap = 0
	if p.sqrb_dev_ring_mid ~= nil and p.sqrb_dev_ring_mid >= 1 then perGap = math.floor(p.sqrb_dev_ring_mid) end
	if p.sqst_entry_mid ~= nil and p.sqst_entry_mid >= 2 then perGap = math.floor(p.sqst_entry_mid) - 1 end
	if g.kind == "rb" and perGap > 0 then
		return oneWay >= 3 and mids >= 4 * perGap, string.format("what=one_way_streets n=%d mids=%d", oneWay, mids)
	end
	if g.kind == "rb" then return oneWay >= 3, string.format("what=one_way_streets n=%d", oneWay) end
	if g.kind == "ix" then return oneWay >= 4, string.format("what=one_way_streets n=%d", oneWay) end
	return true, "what=junction"
end

--- The read of a built placement after the settle: measured now if not at its callback, its arm ends
--- (minus nodes a later build added), the zone line, its log line, its lights off when drawn so (Lights
--- showcase: on when the junction has none).
local function readPlace(s : ShowState, pl : ShowPlace, finish : function())
	if pl.measured == nil then pcall(measurePlace, s, pl, pl.resList, true) end
	local ends, newN, joins, inRes = newEnds(pl.x, pl.y, pl.scanR, pl.before, s.ours, s.scans, pl.seq, pl.res)
	local clusters = logic.clusterEnds(endPoints(ends), pl.gap)
	clusterHeadings(clusters, ends)
	-- an error here must still finish the step (else the queue waits out the serial timeout)
	local okA, armText = pcall(pl.onArms, clusters, ends)
	if not okA then s.problems[#s.problems + 1] = string.format("%s: arms error", pl.tag) end
	-- the zone as built (a redraw changes the type label; r measured when it could be)
	local z = s.zones[pl.group]
	if z ~= nil then
		z.label, z.x, z.y, z.r = pl.label, pl.x, pl.y, pl.measured or pl.est
		-- its arms' measured headings: the traffic log measures out along them (stress_flow withMeasure)
		local arms : {{number}} = {}
		for _, cl in ipairs(clusters) do
			if cl.hx ~= nil and cl.hy ~= nil then arms[#arms + 1] = { cl.hx, cl.hy } end
		end
		z.arms = arms
		-- the set's match as built (every twin's build is done by now: the reads follow the settle)
		local g = s.layout.groups[pl.group]
		local live = 0
		for _, ti in ipairs(g.towns) do
			if not s.skippedTowns[ti] then live = live + 1 end
		end
		z.towns = live
		z.reason = setReason(s, g.set or -pl.group)
		z.built = true
		rt.log(logic.showcaseZoneLine(z, pl.measured ~= nil))
	end
	local lit, dark = "", {} as {integer}
	local grp = s.layout.groups[pl.group]
	local forceLit = s.spec.litOnly or (grp ~= nil and grp.litYes == true)
	if forceLit or s.spec.bench then
		local okL, t, d = pcall(litCheck, joins)
		if okL then lit, dark = t, d else lit = " lit=error" end
		-- the bench: every twin's lit junction nodes (BENCH.md "treatment"; sl twins of rings lose theirs later) and its
		-- geometry check (a twin that does not present what its test tests: its set is no match, reason=geometry)
		if s.spec.bench and grp ~= nil and z ~= nil then
			local okG, gOk, gText = pcall(benchGeometry, pl, grp)
			if not okG then gOk, gText = true, "what=unread" end
			rt.log(string.format("[SQST] BENCH_TWIN id=%s test=%s ab=%s nodes=%d lit_nodes=%d phase=read geometry=%s %s%s", z.id, tostring(grp.test),
				tostring(grp.ab), #joins, #joins - #dark, gOk and "ok" or "bad", gText, grp.geom ~= nil and (" geom=" .. grp.geom) or ""))
			if not gOk then
				s.lostGeom[grp.set or -pl.group] = true
				s.problems[#s.problems + 1] = string.format("%s: geometry does not present its test (%s)", pl.tag, gText)
			end
		end
		if not forceLit then dark = {} end
	end
	rt.log(string.format("[SQST] %s %s %s built ms=%.0f nodes=%d ends=%d arms=%d %s %s res_nodes=%d%s%s%s", s.name, pl.tag, pl.where, pl.ms,
		newN, #ends, #clusters, okA and tostring(armText) or ("arms error: " .. tostring(armText)), pl.measureText or "", inRes,
		pl.lightsOff and string.format(" lights off at %d", #joins) or "", lit,
		#dark > 0 and string.format(" lights forced on at %d", #dark) or ""))
	if pl.lightsOff then
		lightsOff(s.name, joins, finish)
	elseif #dark > 0 then
		-- every twin the same way (the game twin included), so the twins stay alike; Smart Lanes may not
		-- re-plan its phases on a light set after its write (TESTING.md checks the c / d twins)
		s.problems[#s.problems + 1] = string.format("%s: no light at the read; set to Yes (its Smart Lanes phases may be missing)", pl.tag)
		setLights(s.name, dark, api.type.enum.TrafficLightPreference.YES, finish)
	else
		finish()
	end
end

--- "Group 1a Crossroads -> Grid S4" (a link's tag in the log).
local function linkTag(arm : Arm) : string
	return string.format("%s %s -> %s", arm.cell, arm.caseLabel, arm.townName)
end

--- A glink task done: counted, its arm pair remembered for the bus routes, or its set marked unlinked.
local function linkDone(s : ShowState, task : ShowTask, ok : boolean)
	if ok then
		s.linked = s.linked + 1
		s.groupLinked[task.group] = s.groupLinked[task.group] or {}
		s.groupLinked[task.group][task.k] = true
	else
		s.unlinked = s.unlinked + 1
		local g = s.layout.groups[task.group]
		s.lostLinks[g.set or -task.group] = true
	end
end

--- Groups the run's glink tasks from index i on (all of them are queued by then: every read comes before
--- the first link) into proposals of up to LINK_GROUP_MAX links that stay LINK_GROUP_GAP clear of each
--- other (logic.groupLinks over each link's footprint: its arm end to its town's centre, widened by the
--- town's grid with its corner stubs + 60 m); each group's first task leads it (task.members).
local function planLinkGroups(s : ShowState, i : integer)
	s.linksPlanned = true
	local idx : {integer} = {}
	local items : {{number}} = {}
	for k = i, #s.tasks do
		local t = s.tasks[k]
		if t.kind == "glink" and t.arm ~= nil then
			local tp = t.arm.townPos or { t.arm.x, t.arm.y }
			idx[#idx + 1] = k
			items[#items + 1] = { t.arm.x, t.arm.y, tp[1], tp[2], (t.arm.townHalf or 300.0) * 1.42 + 60.0 }
		end
	end
	local groups = logic.groupLinks(items, logic.LINK_GROUP_GAP, logic.LINK_GROUP_MAX)
	for _, g in ipairs(groups) do
		if #g > 1 then
			local lead = s.tasks[idx[g[1]]]
			lead.members = {}
			for _, j in ipairs(g) do lead.members[#lead.members + 1] = s.tasks[idx[j]] end
		end
	end
	rt.detail(string.format("[SQST] %s links: %d in %d proposals (up to %d links each, %.0fm apart)", s.name, #idx, #groups,
		logic.LINK_GROUP_MAX, logic.LINK_GROUP_GAP))
end

--- A link group's ONE proposal: every member's link (its first try, showToTown) in one builder
--- (mergeBuilders: each link with its node configs), sent once. Accepted: every member linked (their own
--- steps only finish). Refused, or a member could not be made or merged: those members go one by one
--- (task.solo: their own steps send them as before, with retries), the refusal logged with its collision
--- hits. after(true) when the leader is linked, after(false) when it goes on its own.
local function sendGroup(s : ShowState, lead : ShowTask, after : function(handled : boolean))
	local builders : {Builder} = {}
	local segs : {{{number}}} = {}
	local inGroup : {ShowTask} = {}
	for _, t in ipairs(lead.members) do
		local okM, b, seg = pcall(showToTown(s, t.arm), 1, nil)
		if okM and b ~= nil then
			builders[#builders + 1] = b
			segs[#segs + 1] = seg
			inGroup[#inGroup + 1] = t
		else
			t.solo = true
			t.arm.tried = {}
		end
	end
	local function alone(why : string)
		local tags : {string} = {}
		for _, t in ipairs(inGroup) do
			t.solo = true
			t.arm.tried = {}   -- each tries its first node again on its own
			tags[#tags + 1] = linkTag(t.arm)
		end
		if why ~= nil then
			rt.log(string.format("[SQST] %s link group of %d %s; one by one: %s", s.name, #inGroup, why, table.concat(tags, "; ")))
		end
		after(false)
	end
	if #inGroup < 2 then alone(nil) return end
	local merged, conflict = mergeBuilders(builders)
	if merged == nil then alone("not merged (" .. tostring(conflict) .. ")") return end
	local okA, proposal = pcall(assemble, merged)
	if not okA then alone("not assembled (" .. tostring(proposal) .. ")") return end
	local t0 = rt.nowUs()
	rt.send(s.name, api.cmd.makeWorldBuildProposalCmd(proposal as SimpleProposal, s.ctx, false, true, false), function(success : boolean, data : any)
		local ms = (rt.nowUs() - t0) / 1000
		if not success then
			alone(string.format("refused (%s%s)", errText(data), resultHits(data)))
			return
		end
		for k, t in ipairs(inGroup) do
			t.grouped = true
			if segs[k] ~= nil then s.avoid[#s.avoid + 1] = segs[k] end
			rt.detail(string.format("[SQST] %s %s linked ms=%.0f (one proposal of %d links)", s.name, linkTag(t.arm), ms, #inGroup))
			linkDone(s, t, true)
		end
		after(lead.grouped == true)
	end)
end

---------------------------------------------------------------------------
-- Town entries (Lights showcase; SHOWCASE.md "Town entries must not be the bottleneck")

--- Every live town's entry: the middle of its grid's side facing its junction (logic.sideCentre), the axis
--- out through it. kind "crossroads" with why when the entry construction is missing or the year is before
--- its streets (logged now).
local function planEntries(s : ShowState, cx : number, cy : number)
	s.entries, s.entryOf, s.lostEntries = {}, {}, {}
	local okY, year = pcall(api.engine.util.getYear)
	local early = okY and type(year) == "number" and year < logic.ENTRY_FROM_YEAR
	for gi, g in ipairs(s.layout.groups) do
		local jx, jy = cx + g.place.x, cy + g.place.y
		for _, ti in ipairs(g.towns) do
			local p = s.points[ti]
			if s.created[ti] ~= nil and p ~= nil and not s.skippedTowns[ti] and s.entryOf[ti] == nil then
				local tp, half = townGrid(s, ti)
				local pt = logic.sideCentre(tp[1], tp[2], half, jx, jy)
				local e : ShowEntry = { ti = ti, name = p.name, set = g.set or -gi, x = pt[1], y = pt[2], jx = jx, jy = jy,
					out = logic.entryOutward(p.x, p.y, pt[1], pt[2]), dist = math.sqrt((pt[1] - jx) ^ 2 + (pt[2] - jy) ^ 2), kind = "crossroads",
					joined = 0 }
				if s.entryFile == nil or early then
					e.why = s.entryFile == nil and "entry construction not found" or string.format("before %d: no one-way ring street yet", logic.ENTRY_FROM_YEAR)
					rt.detail(logic.entryLine(s.name, e.name, e.kind, string.format("(%s) at %.0f,%.0f", e.why, e.x, e.y)))
				end
				s.entries[#s.entries + 1] = e
				s.entryOf[ti] = e
			end
		end
	end
end

--- An entry left a crossroads (its set's twins differ only when another twin got its roundabout:
--- entriesMixed) or a roundabout broken (not read, not joined: its set's twins differ).
local function entryLost(s : ShowState, e : ShowEntry, kind : string, why : string)
	e.kind, e.why = kind, why
	if kind ~= "crossroads" then s.lostEntries[e.set] = true end
	s.problems[#s.problems + 1] = string.format("%s entry: %s (%s)", e.name, kind, why)
end

--- The roundabout's proposal: the construction centred on the side-middle node's spot, rotation 0 (every
--- zero +0, junctionTransf), plus the removal of that node and its three grid edges, the far nodes' configs
--- without them (remove + add). Atomic: refused, the crossroads stays as it is.
local function entryProposal(s : ShowState, e : ShowEntry, edges : {integer}) : SimpleProposal
	local case_ : SquareStressJunctionCase = { id = logic.ENTRY_CASE.id, label = logic.ENTRY_CASE.label, file = logic.ENTRY_CASE.file,
		params = { sqst_entry_dir = s.entryDir or 1, sqst_entry_ring = e.ring or logic.ENTRY_RINGS[1] } }
	-- the inward arm (towards the central street) ends at ENTRY_IN_REACHES[e.inK]; the others at ENTRY_REACH
	local ax = logic.axisIndex({ -e.out[1], -e.out[2] })
	if ax ~= nil then
		case_.params.sqst_entry_in_axis = ax + 1
		case_.params.sqst_entry_in_reach = e.inK or 1
	end
	local p = junctionProposal(s.entryFile, case_, e.x, e.y, s.seed, 0.0)
	local gone : {integer : boolean} = {}
	for _, x in ipairs(edges) do gone[x] = true end
	local cfgRemove : {integer} = {}
	local cfgAdd : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
	e.ghosts = {}
	for _, role in ipairs({ "in", "left", "right" }) do
		local n = e.far[role]
		-- a lit far node loses this leg's connections and crosswalk now; the join adds a leg in the same
		-- direction later: remember the old states for it (read before nodeConfigEntry rewrites the config)
		e.ghosts[role] = nc.ghost(n, e.farEdge ~= nil and e.farEdge[role] or nil)
		local entry, changed = rt.nodeConfigEntry(n, nil, gone)
		if entry ~= nil and changed > 0 then
			cfgRemove[#cfgRemove + 1] = n
			cfgAdd[#cfgAdd + 1] = entry
		end
	end
	p.streetProposal.edgesToRemove = edges
	p.streetProposal.nodesToRemove = { e.node }
	if #cfgAdd > 0 then
		p.streetProposal.nodeConfigsToRemove = cfgRemove
		p.streetProposal.nodeConfigsToAdd = cfgAdd
	end
	return p
end

--- The map's driving side (logic.drivingSide) from the first of `edges` whose road lanes read as a clean
--- two-way split; nil and why when none does.
local function drivingSideOf(edges : {integer}) : string, string
	local why = "no two-way street"
	for _, x in ipairs(edges) do
		local ok, side = pcall(function() : string
			local be = comp(x, api.type.ComponentType.BASE_EDGE) as {string : any}
			local lcs = be ~= nil and be.laneConfigs as {any} or nil
			if lcs == nil then return nil end
			local all : {{any}} = {}
			local anyModes = false
			for i, lcAny in ipairs(lcs) do
				local lc = lcAny as {string : any}
				local tm = lc.transportModes as {integer : boolean}
				local road = false
				if tm ~= nil then
					for k, v in pairs(tm) do
						if v then
							anyModes = true
							if k == 2 or k == 3 or k == 4 then road = true end   -- CAR, BUS, TRUCK (stress_nodecfg MODES)
						end
					end
				end
				all[i] = { lc.forward == true, road }
			end
			local fw : {boolean} = {}
			for i, a in ipairs(all) do
				-- without readable modes: every lane but the two sidewalks
				if (anyModes and a[2] == true) or (not anyModes and i > 1 and i < #all) then fw[#fw + 1] = a[1] as boolean end
			end
			return logic.drivingSide(fw)
		end)
		if ok and side ~= nil then return side, nil end
		if not ok then why = "lanes unreadable" end
	end
	return nil, why
end

-- An entry's streets are locked once it is this old (and before any later step reads it): past Smart Lanes' write
-- on the new ring (log session 2026-10-13_0045_top-up-158690: WRITE ring= -> LIGHTS -> VERIFY within ~1 s of the
-- build), so every entry sees the same order: build, Smart Lanes' write, lock (Smart Lanes then re-plans the swapped
-- streets: covered by the settle). The town hung streets on unlocked arms within 12-51 s in that run.
local ENTRY_LOCK_AGE_MS <const> = 2000

local ENTRY_POINT_TOL <const> = 2.5   -- m: a new node this close to one of the entry's own points is that point

--- The entry's own points from its geometry (rotation 0): ring[k] at the ring's radius and arm[k] at its reach, on
--- axis k (+x, +y, -x, -y; the inward one at ENTRY_IN_REACHES[e.inK]).
local function entryPoints(e : ShowEntry) : {{number}}, {{number}}
	local axes : {{number}} = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
	local rr = logic.ENTRY_RING_RADIUS[e.ring or logic.ENTRY_RINGS[1]] or logic.ENTRY_RING_RADIUS[1]
	local inAx = logic.axisIndex({ -e.out[1], -e.out[2] })
	local ring, arm : {{number}}, {{number}} = {}, {}
	for k, a in ipairs(axes) do
		local reach = (k == inAx) and (logic.ENTRY_IN_REACHES[e.inK or 1] or logic.ENTRY_REACH) or logic.ENTRY_REACH
		ring[k] = { e.x + a[1] * rr, e.y + a[2] * rr }
		arm[k] = { e.x + a[1] * reach, e.y + a[2] * reach }
	end
	return ring, arm
end

--- Which of pts (1..#pts) the position p is (within ENTRY_POINT_TOL), nil when none.
local function pointIndex(p : {number}, pts : {{number}}) : integer
	if p == nil then return nil end
	for k, q in ipairs(pts) do
		if (p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2 <= ENTRY_POINT_TOL * ENTRY_POINT_TOL then return k end
	end
	return nil
end

--- The new nodes at the entry's own points: ringNode[k], armNode[k] (nil where none stands).
local function entryNodes(e : ShowEntry) : {integer : integer}, {integer : integer}
	local ringPts, armPts = entryPoints(e)
	local ringNode, armNode : {integer : integer}, {integer : integer} = {}, {}
	for n in pairs(nodesNear(e.x, e.y, logic.ENTRY_REACH + logic.ENTRY_SCAN)) do
		if not e.before[n] then
			local p = nodePos(n)
			local kr, ka = pointIndex(p, ringPts), pointIndex(p, armPts)
			if kr ~= nil then ringNode[kr] = n elseif ka ~= nil then armNode[ka] = n end
		end
	end
	return ringNode, armNode
end

--- An entry's own streets, sorted: the ring (edges between two of its ring nodes) and the arms (a ring node to the
--- arm end on the same axis), found by the construction's geometry, so a town street hung on an arm end (2026-10-13
--- review: a short one has both ends near the centre too) is never taken for its own.
local function entryStreets(e : ShowEntry) : {integer}
	local map = streetMap()
	local ringNode, armNode = entryNodes(e)
	local ringOf, armOf : {integer : integer}, {integer : integer} = {}, {}
	for k, n in pairs(ringNode) do ringOf[n] = k end
	for k, n in pairs(armNode) do armOf[n] = k end
	local list : {integer} = {}
	local seen : {integer : boolean} = {}
	for n in pairs(ringOf) do
		for _, x in ipairs(map[n] or {}) do
			local be = comp(x, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
			if not seen[x] and be ~= nil then
				local a, b = be.node0, be.node1
				local ringRing = ringOf[a] ~= nil and ringOf[b] ~= nil
				local arm = (ringOf[a] ~= nil and armOf[b] == ringOf[a]) or (ringOf[b] ~= nil and armOf[a] == ringOf[b])
				if ringRing or arm then
					seen[x] = true
					list[#list + 1] = x
				end
			end
		end
	end
	table.sort(list)
	return list
end

--- Locks a built entry's own streets (one lockEdgeList: one proposal, retried once by it), then done(). Sets
--- e.locked (streets locked) and e.lockOk; logged `kind=roundabout locked=N of M streets age=..s` (detail; a
--- shortfall, an error or fewer than 8 streets at log level).
--- firstTry (the build's own callback, 2026-10-13: run 6 lost three arms to town streets in the 3-4 s before the
--- lock): when not every street locks yet (still the construction's, or not readable), the entry is left for the
--- later lock (lockDue) instead of being marked, logged as detail only.
local function lockEntry(s : ShowState, e : ShowEntry, done : function(), firstTry? : boolean)
	e.lockSent = true
	if firstTry then e.lockPending = true end
	local age = e.builtUs ~= nil and (rt.nowUs() - e.builtUs) / 1e6 or -1
	-- done runs once, and never inside the pcall (lockEdges may answer synchronously: the rest of the chain
	-- would run inside it, and an error there would read as a failed lock)
	local called, answered, inCall = false, false, true
	local function once()
		if called then return end
		called = true
		done()
	end
	local list : {integer} = {}
	local okL, err : boolean, any = pcall(function()
		list = entryStreets(e)
		towns.lockEdgeList(s.name, e.name .. " entry", list, function(locked : integer, failed : integer, already : integer)
			answered = true
			e.lockPending = false
			e.locked = locked
			e.lockOk = #list > 0 and locked == #list
			local line = logic.entryLine(s.name, e.name, "roundabout", string.format("locked=%d of %d streets%s%s age=%.1fs", locked, #list,
				(already or 0) > 0 and string.format(" (%d already)", already) or "", failed > 0 and string.format(" failed=%d", failed) or "", age))
			if firstTry and not e.lockOk then
				e.lockSent = false   -- the later lock tries again
				rt.detail(line .. " (at the build: the later lock tries again)")
			elseif not e.lockOk or #list < 8 then rt.log(line) else rt.detail(line) end
			-- answered synchronously: done runs after the pcall below; asynchronously: now
			if not inCall then once() end
		end)
	end)
	inCall = false
	if not okL and not answered then
		e.locked, e.lockOk = 0, false
		e.lockPending = false
		if firstTry then e.lockSent = false end
		rt.log(logic.entryLine(s.name, e.name, "roundabout", "not locked: " .. tostring(err)))
	end
	if not okL or answered then once() end
end

--- How many of the edges are roadDevelopmentLocked now (fresh reads; a gone edge counts as not).
local function countLocked(list : {integer}) : integer
	local n = 0
	for _, x in ipairs(list) do
		local be = comp(x, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
		local ok, l = pcall(function() : boolean return be ~= nil and be.roadDevelopmentLocked == true end)
		if ok and l then n = n + 1 end
	end
	return n
end

--- Locks several entries' streets in ONE lockEdgeList call (the closing lock step: the last set no longer waits for
--- one proposal after another), then reads each entry's streets fresh (the lock gave them new ids) and counts the
--- locked ones; done() once.
local function lockMany(s : ShowState, list : {ShowEntry}, done : function())
	local all : {integer} = {}
	local seenEdge : {integer : boolean} = {}
	local now = rt.nowUs()
	local ages : {number} = {}
	for k, e in ipairs(list) do
		e.lockSent = true
		ages[k] = e.builtUs ~= nil and (now - e.builtUs) / 1e6 or -1
		local okS, l = pcall(entryStreets, e)
		for _, x in ipairs(okS and l or {}) do
			if not seenEdge[x] then
				seenEdge[x] = true
				all[#all + 1] = x
			end
		end
	end
	local called = false
	local function finishAll()
		if called then return end
		called = true
		for k, e in ipairs(list) do
			local okS, l = pcall(entryStreets, e)
			local mine = okS and l or {}
			e.locked = countLocked(mine)
			e.lockOk = #mine > 0 and e.locked == #mine
			local line = logic.entryLine(s.name, e.name, "roundabout", string.format("locked=%d of %d streets age=%.1fs (one lock for %d entries)",
				e.locked, #mine, ages[k], #list))
			if not e.lockOk or #mine < 8 then rt.log(line) else rt.detail(line) end
		end
		done()
	end
	local answered, inCall = false, true
	local okL, err : boolean, any = pcall(function()
		towns.lockEdgeList(s.name, string.format("%d entries", #list), all, function(_l : integer, _f : integer, _a : integer)
			answered = true
			if not inCall then finishAll() end
		end)
	end)
	inCall = false
	if not okL and not answered then rt.log(string.format("[SQST] %s entries: one lock for %d entries failed: %s", s.name, #list, tostring(err))) end
	if not okL or answered then finishAll() end
end

--- Locks every built entry not locked yet that is at least minAgeMs old, one after another, then done().
local function lockDue(s : ShowState, minAgeMs : number, done : function())
	local due : {ShowEntry} = {}
	local now = rt.nowUs()
	for _, e in ipairs(s.entries or {}) do
		if e.kind == "roundabout" and not e.lockSent and e.builtUs ~= nil and (now - e.builtUs) / 1000 >= minAgeMs then due[#due + 1] = e end
	end
	if #due == 0 then done() return end
	if #due == 1 then lockEntry(s, due[1], done) return end
	lockMany(s, due, done)
end

--- The last entries' lock (the "elock" task after every entry build): waits until the youngest built entry is
--- ENTRY_LOCK_AGE_MS old, then locks all the rest.
local LOCK_POLL_MS <const> = 500     -- the closing lock step re-checks build-time locks still in flight this often
local LOCK_POLL_MAX <const> = 40     -- ... at most this many times (20 s), then goes on (those entries say so at the read)
local function lockRest(s : ShowState, done : function(), polls? : integer)
	local wait = 0.0
	local now = rt.nowUs()
	local pending = false
	for _, e in ipairs(s.entries or {}) do
		if e.kind == "roundabout" and e.lockPending then pending = true end
		if e.kind == "roundabout" and not e.lockSent and e.builtUs ~= nil then
			wait = math.max(wait, ENTRY_LOCK_AGE_MS - (now - e.builtUs) / 1000)
		end
	end
	-- a build-time lock still in flight may end partial: wait for its answer, so the later lock can retry it
	if pending and (polls or 0) < LOCK_POLL_MAX then
		rt.later(s.name .. ":elockpoll", LOCK_POLL_MS, function()
			local okP, errP : boolean, any = pcall(lockRest, s, done, (polls or 0) + 1)
			if not okP then
				rt.log(string.format("[SQST] %s entries: lock step error: %s", s.name, tostring(errP)))
				done()
			end
		end)
		return
	end
	if wait <= 0 then lockDue(s, 0, done) return end
	rt.later(s.name .. ":elock", wait, function()
		local okD, errD : boolean, any = pcall(lockDue, s, 0, done)
		if not okD then
			rt.log(string.format("[SQST] %s entries: lock step error: %s", s.name, tostring(errD)))
			done()
		end
	end)
end

--- The ring (sqst_entry_ring) and inward reach (ENTRY_IN_REACHES index) of pre-check ladder step `step` (1-based):
--- every reach on logic.ENTRY_RINGS[1] (the 3-lane ring), then on the next ring.
local function entryLadder(step : integer) : integer, integer
	local n = #logic.ENTRY_IN_REACHES
	local ri = math.floor((step - 1) / n) + 1
	return logic.ENTRY_RINGS[ri] or logic.ENTRY_RINGS[#logic.ENTRY_RINGS], (step - 1) % n + 1
end

--- "3 lanes 46m" (a ladder step in the log).
local function ladderText(ring : integer, inK : integer) : string
	return string.format("%d lanes %.0fm", logic.ENTRY_RING_LANES[ring] or 0, logic.ENTRY_IN_REACHES[inK] or 0)
end

--- An entry's build step: finds the side-middle node (3 grid edges, the far nodes in, left, right far enough
--- for the roundabout's arms, their junction areas and a join), pre-checks and sends the proposal; anything off
--- leaves the crossroads (logged `kind=crossroads (why)`, a collision naming the entry's own nodes and edges it
--- hits). finish() on its callback.
local function buildEntry(s : ShowState, e : ShowEntry, finish : function())
	if s.entryFile == nil or e.why ~= nil then finish() return end
	local function keep(why : string)
		entryLost(s, e, "crossroads", why)
		rt.log(logic.entryLine(s.name, e.name, "crossroads", string.format("(%s) at %.0f,%.0f", why, e.x, e.y)))
		finish()
	end
	local map = streetMap()
	local tp, half, townR = townGrid(s, e.ti)
	local c, _, own, note = sideNode(s, s.created[e.ti], e.name, tp, half, townR, e.jx, e.jy)
	if c == nil then keep(string.format("no grid node at the side's middle (own nodes=%d%s)", own, note)) return end
	-- the roundabout is centred on the node it replaces (sideNode takes one up to 15 m off the side's middle):
	-- its proposal, scan, read and log lines all use e.x, e.y from here on
	e.x, e.y = c.x, c.y
	e.dist = math.sqrt((c.x - e.jx) ^ 2 + (c.y - e.jy) ^ 2)
	local edges = map[c.id] or {}
	if #edges ~= 3 then keep(string.format("the side-middle node %d has %d streets, not 3", c.id, #edges)) return end
	if s.entryDir == nil then
		-- once per run, so every twin's ring turns the same way
		local side, why = drivingSideOf(edges)
		s.entryDir = side == "left" and 2 or 1
		if side ~= nil then rt.drivingSide = side end
		rt.log(string.format("[SQST] %s entries: driving side %s, ring %s", s.name, side or ("not read (" .. tostring(why) .. "), right assumed"),
			s.entryDir == 2 and "clockwise" or "anticlockwise"))
	end
	if hasObjects(edges) then keep("a stop on the side-middle streets") return end
	local far : {integer} = {}
	local pts : {{number}} = {}
	for _, x in ipairs(edges) do
		local be = comp(x, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
		local f = be ~= nil and (be.node0 == c.id and be.node1 or be.node0) or nil
		local fp = f ~= nil and nodePos(f) or nil
		if fp == nil then keep("a side-middle street unreadable") return end
		far[#far + 1], pts[#pts + 1] = f, fp
	end
	local roles, bad = logic.entryRoles(c.x, c.y, e.out, pts)
	if roles == nil or roles["out"] ~= nil then keep("the side-middle streets are not the ring and the central street: " .. tostring(bad or "one leads out")) return end
	e.node, e.far, e.farPos, e.farEdge = c.id, {}, {}, {}
	for role, i in pairs(roles) do
		local d = math.sqrt((pts[i][1] - c.x) ^ 2 + (pts[i][2] - c.y) ^ 2)
		if d < logic.ENTRY_REACH + logic.ENTRY_FAR_CLEAR + logic.ENTRY_MIN_JOIN then
			keep(string.format("the block is too small (%s node %.0fm away, the roundabout reaches %.0fm + %.0fm of junction + %.0fm)", role, d,
				logic.ENTRY_REACH, logic.ENTRY_FAR_CLEAR, logic.ENTRY_MIN_JOIN))
			return
		end
		e.far[role], e.farPos[role], e.farEdge[role] = far[i], pts[i], edges[i]
	end
	-- what a collision hits, named for the log (2026-10-12: "hits 12 other BASE_NODE" with no clue which)
	local labels : {integer : string} = { [c.id] = "side-middle node (removed)" }
	for role, n in pairs(e.far) do labels[n] = string.format("%s far node (%d streets)", role, #(map[n] or {})) end
	for _, x in ipairs(edges) do labels[x] = "side-middle street (removed)" end
	-- the ladder (entryLadder): the 3-lane ring with the inward arm from 46 m down to the shortest, then the 2-lane
	-- ring the same way, until the check passes (2026-10-13: 46 m hit the inward crossroads in all 96). An entry that
	-- needs a later step moves the start for the later ones; a set whose entries end up on different steps is no
	-- match (entriesMixed: reason=entry)
	local reaches = logic.ENTRY_IN_REACHES
	local nSteps = #logic.ENTRY_RINGS * #reaches
	local start = math.max(1, math.min(s.entryStep or 1, nSteps))
	local verdict : string = nil
	local refused : {string} = {}
	local stepAt = start
	for step = start, nSteps do
		stepAt = step
		e.ring, e.inK = entryLadder(step)
		verdict = precheck(entryProposal(s, e, edges), s.ctx, labels)
		if verdict == nil or verdict == "ok" then break end
		refused[#refused + 1] = ladderText(e.ring, e.inK)
	end
	if verdict ~= nil and verdict ~= "ok" then
		e.inK, e.ring = nil, nil
		keep(string.format("roundabout refused by the check: %s (tried %s)", verdict, table.concat(refused, ", ")))
		return
	end
	if stepAt > start then
		local r0, k0 = entryLadder(start)
		rt.log(string.format("[SQST] %s entries: %s refused by the check (%s), %s from now on", s.name, ladderText(r0, k0),
			table.concat(refused, ", "), ladderText(e.ring, e.inK)))
	end
	s.entryStep = stepAt
	local r = logic.ENTRY_REACH + logic.ENTRY_SCAN
	e.before = nodesNear(e.x, e.y, r)
	s.scans[#s.scans + 1] = { x = e.x, y = e.y, r = r, before = e.before }
	e.seq = #s.scans
	local t0 = rt.nowUs()
	rt.send(s.name, api.cmd.makeWorldBuildProposalCmd(entryProposal(s, e, edges), s.ctx, false, true, false),
		function(success : boolean, data : any, res : {{integer}})
			e.ms = (rt.nowUs() - t0) / 1000
			if not success then
				keep(string.format("roundabout refused: %s%s", errText(data), resultHits(data, labels)))
				return
			end
			e.kind, e.res = "roundabout", resultIds(res)
			rt.log(logic.entryLine(s.name, e.name, "roundabout", string.format("at %.0f,%.0f node=%d removed=%d from_junction=%.0fm ms=%.0f reach=%.0fm in_reach=%.0fm ring_lanes=%d",
				e.x, e.y, c.id, #edges, e.dist, e.ms, logic.ENTRY_REACH, logic.ENTRY_IN_REACHES[e.inK] or logic.ENTRY_REACH,
				logic.ENTRY_RING_LANES[e.ring] or 0)))
			-- its streets are locked ENTRY_LOCK_AGE_MS later, in a later ebuild step or the elock step (lockDue):
			-- unlocked, the town hung its own streets on the arm ends and split the arms before the joins
			-- (2026-10-13, session 2026-10-13_0045_top-up-158690: 12 entries "arms not read", 10 broken joins)
			e.builtUs = rt.nowUs()
			-- locked at once (before Smart Lanes' pass ~10 frames later: it then writes the ring once, on the locked
			-- streets); not every street locked yet: the later lock (lockDue) tries again. Not waited for.
			lockEntry(s, e, function() end, true)
			finish()
		end)
end

--- After the settle: the roundabout's four arm ends by role (logic.entryRoles); an "elink" task joins its
--- inner three to the grid. Returns whether that task was queued.
--- The entry's arm ends by its geometry: the dead end (exactly one street) at each arm-end point (entryNodes), as
--- newEnds' ArmEnd (node, its edge, position, whether traffic on it drives towards the end, heading).
local function entryArmEnds(e : ShowEntry) : {ArmEnd}
	local out : {ArmEnd} = {}
	local map = streetMap()
	local _, armNode = entryNodes(e)
	for k = 1, 4 do
		local n = armNode[k]
		local list = n ~= nil and map[n] or nil
		local p = n ~= nil and nodePos(n) or nil
		if list ~= nil and #list == 1 and p ~= nil then
			local be = comp(list[1], api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
			local q = be ~= nil and nodePos(be.node0 == n and be.node1 or be.node0) or nil
			local dir : {number} = nil
			if q ~= nil then
				local dl = math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2)
				if dl > 0 then dir = { (p[1] - q[1]) / dl, (p[2] - q[2]) / dl } end
			end
			out[#out + 1] = { node = n, edge = list[1], pos = p, out = be ~= nil and be.node1 == n, dir = dir }
		end
	end
	return out
end

--- final false: an arm missing returns "missing" without a verdict (the caller may remove a stray street and read
--- again); final true (or nothing missing): the verdict as before. Returns "ok", "missing", "broken" or "skip".
local function readEntry(s : ShowState, e : ShowEntry, job : SquareStressJob, final? : boolean) : string
	if e.kind ~= "roundabout" then return "skip" end
	-- its streets should be locked by now (lockDue / the elock step); not all locked: said, read and joined anyway
	-- (the joins read each arm end fresh), listed, its set no match (the town may have built on it)
	if not e.lockOk and not e.lockChecked then
		e.lockChecked = true
		local why = string.format("its streets not all locked (%s)", e.lockPending and "its build-time lock never answered"
			or (e.lockSent and string.format("%d locked", e.locked or 0) or "lock never ran"))
		rt.log(logic.entryLine(s.name, e.name, "roundabout", why))
		s.problems[#s.problems + 1] = string.format("%s entry: %s", e.name, why)
		s.lostEntries[e.set] = true
	end
	-- every new node near it goes into s.ours as before (newEnds); the arm ends themselves come from the
	-- construction's geometry (entryNodes): a dead end at each arm-end point, so a town stub's own dead end near an
	-- arm (2026-10-13 review: a 20 m sideways stub read as the "left" arm) is never taken for an arm
	newEnds(e.x, e.y, logic.ENTRY_REACH + logic.ENTRY_SCAN, e.before, s.ours, s.scans, e.seq, e.res)
	local ends = entryArmEnds(e)
	local roles, bad = logic.entryRoles(e.x, e.y, e.out, endPoints(ends))
	if roles == nil or roles["out"] == nil or roles["in"] == nil or roles["left"] == nil or roles["right"] == nil then
		if not final then return "missing" end
		local found : {string} = {}
		for _, r in ipairs({ "out", "in", "left", "right" }) do if roles ~= nil and roles[r] ~= nil then found[#found + 1] = r end end
		e.broken = string.format("arms not read (ends=%d%s%s)", #ends, #found > 0 and (" found=" .. table.concat(found, ",")) or "",
			bad ~= nil and (": " .. bad) or "")
		entryLost(s, e, "roundabout", e.broken)
		rt.log(logic.entryLine(s.name, e.name, "roundabout", e.broken))
		return "broken"
	end
	e.outer = ends[roles["out"]]
	e.inner = { ["in"] = ends[roles["in"]], left = ends[roles["left"]], right = ends[roles["right"]] }
	rt.detail(logic.entryLine(s.name, e.name, "roundabout", string.format("read ends=4 outer=%d", e.outer.node)))
	s.tasks[#s.tasks + 1] = { kind = "elink", entry = e }
	job.total = job.total + 1
	return "ok"
end

--- Whether a street edge has a town building on one of its parcels (getSegment2ParcelData: never getParcelData,
--- docs/findings.md "Organic Towns probe"); nil when that can't be read.
local function edgeHasBuildings(x : integer) : boolean
	local ok, has = pcall(function() : boolean
		local pd = (api.engine.system.parcelSystem.getSegment2ParcelData() as {integer : any})[x] as {string : {integer}}
		if pd == nil then return false end
		local b2 = api.engine.system.townBuildingSystem.getParcel2BuildingMap() as {integer : integer}
		for _, side in ipairs({ pd.leftEntities or {}, pd.rightParcels or {} }) do
			for _, parcel in ipairs(side) do
				if b2[parcel] ~= nil then return true end
			end
		end
		return false
	end)
	if not ok then return nil end
	return has
end

--- An entry whose arm read missed an end (a town street hung on it before the lock, 2026-10-13 run 6): at each of
--- its arm-end points (entryPoints: the construction's geometry, so the end's own arm is known) a node with exactly
--- two streets, the arm (to the ring node on the same axis) and one other: that other one is removed with its far
--- node in one proposal when it is unlocked, carries no objects and no town building, its far node is a dead end,
--- neither node belongs to a construction or to a later build (laterOwns), and the arm end is a role the read missed;
--- the arm end's config re-pointed without it. done(true) once it went through; any other shape: done(false),
--- nothing sent (the reason logged). Every read guarded; logged `kind=roundabout stray street ...`.
local function removeStray(s : ShowState, e : ShowEntry, missing : {string : boolean}, done : function(removed : boolean))
	local why : {string} = {}
	local okF, edgesToRemove, nodesToRemove, armEnds : boolean, {integer}, {integer}, {integer} = pcall(function() : {integer}, {integer}, {integer}
		local map = streetMap()
		local ringNode, armNode = entryNodes(e)
		local _, armPts = entryPoints(e)
		local rmE, rmN, ends : {integer}, {integer}, {integer} = {}, {}, {}
		for k, n in pairs(armNode) do
			local roles = logic.entryRoles(e.x, e.y, e.out, { armPts[k] })
			local role : string = nil
			for r in pairs(roles or {}) do role = r end
			local list = map[n] or {}
			if role ~= nil and missing[role] and #list == 2 then
				local own, other : integer, integer = nil, nil
				for _, x in ipairs(list) do
					local be = comp(x, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge
					if be ~= nil and (be.node0 == ringNode[k] or be.node1 == ringNode[k]) then own = x else other = x end
				end
				local be = other ~= nil and comp(other, api.type.ComponentType.BASE_EDGE) as Engine.Component.BaseEdge or nil
				local far = be ~= nil and (be.node0 == n and be.node1 or be.node0) or nil
				local reason : string = nil
				if own == nil or be == nil then reason = "no own arm and one other street"
				elseif be.roadDevelopmentLocked == true then reason = "the other street is locked"
				elseif hasObjects({ other }) then reason = "the other street has objects"
				elseif #(map[far] or {}) ~= 1 then reason = "the other street does not end in a dead end"
				elseif inConstruction(n) or inConstruction(far) then reason = "a construction's node"
				elseif laterOwns(n, nodePos(n), s.scans, e.seq) or laterOwns(far, nodePos(far), s.scans, e.seq) then reason = "a later build's node"
				else
					local b = edgeHasBuildings(other)
					if b == nil then reason = "its parcels unreadable" elseif b then reason = "town buildings on it" end
				end
				if reason ~= nil then
					why[#why + 1] = string.format("%s arm end %d: %s", role, n, reason)
				else
					rmE[#rmE + 1], rmN[#rmN + 1], ends[#ends + 1] = other, far, n
				end
			end
		end
		return rmE, rmN, ends
	end)
	if okF and (edgesToRemove == nil or #edgesToRemove == 0) and #why > 0 then
		rt.log(logic.entryLine(s.name, e.name, "roundabout", "stray street not removed: " .. table.concat(why, "; ")))
	end
	if not okF or edgesToRemove == nil or #edgesToRemove == 0 then done(false) return end
	local okP, p : boolean, any = pcall(function() : SimpleProposal
		local gone : {integer : boolean} = {}
		for _, x in ipairs(edgesToRemove) do gone[x] = true end
		local proposal = api.type.SimpleProposal.new()
		proposal.streetProposal.edgesToRemove = edgesToRemove
		proposal.streetProposal.nodesToRemove = nodesToRemove
		local cfgRemove : {integer} = {}
		local cfgAdd : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
		for _, n in ipairs(armEnds) do
			local entry, changed = rt.nodeConfigEntry(n, nil, gone)
			if entry ~= nil and changed > 0 then
				cfgRemove[#cfgRemove + 1] = n
				cfgAdd[#cfgAdd + 1] = entry
			end
		end
		if #cfgAdd > 0 then
			proposal.streetProposal.nodeConfigsToRemove = cfgRemove
			proposal.streetProposal.nodeConfigsToAdd = cfgAdd
		end
		return proposal
	end)
	if not okP then done(false) return end
	local ids : {string} = {}
	for k, x in ipairs(edgesToRemove) do ids[k] = string.format("%d (arm end %d)", x, armEnds[k]) end
	rt.send(s.name, api.cmd.makeWorldBuildProposalCmd(p as SimpleProposal, s.ctx, false, true, false), function(success : boolean, data : any)
		rt.log(logic.entryLine(s.name, e.name, "roundabout", string.format("stray street %s %s", table.concat(ids, ", "),
			success and "removed" or ("not removed: " .. errText(data)))))
		done(success)
	end)
end

--- One inner join: the roundabout's arm end `role` to the far grid node of that role (linkBuilder: a short
--- copy of the arm's country road, both nodes replaced, every new node configured).
local function entryJoin(s : ShowState, e : ShowEntry, role : string) : Builder, {{number}}
	local en = e.inner[role]
	-- the arm end read fresh: its edge id may have changed since the read (the lock swapped it for a locked copy);
	-- an end that is no longer a dead end (a town street hung on it before the lock) is not joined (2026-10-13, log
	-- session 2026-10-13_0045_top-up-158690: a stale edge id threw "can't be cast" in the segment copy)
	local list = streetMap()[en.node]
	if list == nil or #list ~= 1 then
		error(string.format("arm end %d has %d streets now, not 1", en.node, list ~= nil and #list or 0))
	end
	en.edge = list[1]
	local okP, p = pcall(nodePos, en.node)
	if okP and p ~= nil then en.pos = p end
	local fp = nodePos(e.far[role]) or e.farPos[role]
	local arm : Arm = { ends = { en }, x = en.pos[1], y = en.pos[2], tried = {}, try = 1, cell = e.name, caseLabel = role }
	local c : SquareStressNodeCand = { id = e.far[role], x = fp[1], y = fp[2], z = fp[3] or 0, deg = 2, large = false, score = 0 }
	local b, seg = linkBuilder(arm, c, nil, s.spec.lockStreets == true, false)
	local g = e.ghosts ~= nil and e.ghosts[role] or nil
	if g ~= nil then
		g.result = nil
		b.ghosts[e.far[role]] = g
	end
	return b, seg
end

--- The entry's three joins in ONE proposal (mergeBuilders); refused: each on its own with retries
--- (showLink). A join left out breaks the entry (its set: match=no reason=entry).
local function linkEntry(s : ShowState, e : ShowEntry, finish : function())
	local roles = { "in", "left", "right" }
	local joinedRole : {string : boolean} = {}
	local function done()
		if e.joined < 3 then
			e.broken = string.format("joined %d of 3 to the grid", e.joined)
			entryLost(s, e, "roundabout", e.broken)
		end
		-- lit far nodes: whether the joined leg got the removed leg's light states back (nc.configs). Not carried
		-- (2026-10-13, log session 2026-10-13_0045_top-up-158690: every one: the inward T had a connection the
		-- ghost lacked, Smart Lanes re-planned it after the removal; the ring corners had lost their light, 0
		-- phases): the joined node's light is switched off (the game's own proposal, as the Lights setting), so no
		-- leg drives through a phase that never locks it; the same in every twin. A node that can't be found
		-- at its spot stays as it is (listed).
		local lights : {string} = {}
		local off : {integer} = {}
		for _, role in ipairs(roles) do
			local g = e.ghosts ~= nil and e.ghosts[role] or nil
			if g ~= nil then
				-- joined without a verdict (its join's configs not written through the ghost): not carried either
				local r : string = nil
				if joinedRole[role] then r = g.result or "unmapped (no verdict)" end
				if r ~= nil and r ~= "carried" then
					local fp = e.farPos[role]
					local n : integer = nil
					for x in pairs(fp ~= nil and nodesNear(fp[1], fp[2], 1.0) or {}) do n = x end
					if n ~= nil then
						off[#off + 1] = n
						lights[#lights + 1] = string.format("%s:off (%s)", role, r)
					else
						lights[#lights + 1] = string.format("%s:%s, node not found", role, r)
						s.problems[#s.problems + 1] = string.format("%s entry: lights at the %s join %s", e.name, role, g.result)
					end
				else
					lights[#lights + 1] = role .. ":" .. tostring(r or "not joined")
				end
			end
		end
		-- " (broken)" stays last (tools/flow_report.py counts the broken entries by it)
		rt.log(logic.entryLine(s.name, e.name, "roundabout", string.format("joined=%d/3%s%s", e.joined,
			#lights > 0 and (" lights=" .. table.concat(lights, ",")) or "", e.joined < 3 and " (broken)" or "")))
		if #off == 0 then finish() return end
		-- a refused switch-off is tried once more LOCK_RETRY_MS later (a pending light or lane write refuses it);
		-- refused again: listed, and the set is no match (its twins may differ there)
		lightsOff(s.name, off, function(refused : {integer})
			if #refused == 0 then finish() return end
			rt.later(s.name .. ":elights", logic.LOCK_RETRY_MS, function()
				lightsOff(s.name, refused, function(again : {integer})
					if #again > 0 then
						local ids : {string} = {}
						for _, n in ipairs(again) do ids[#ids + 1] = tostring(n) end
						s.problems[#s.problems + 1] = string.format("%s entry: lights not switched off at node %s (refused twice)", e.name,
							table.concat(ids, ", "))
						s.lostEntries[e.set] = true
						rt.log(logic.entryLine(s.name, e.name, "roundabout", "lights off refused twice at " .. table.concat(ids, ", ")))
					end
					finish()
				end)
			end)
		end)
	end
	local function alone(k : integer)
		if k > #roles then done() return end
		local role = roles[k]
		showLink(s, string.format("entry %s %s", e.name, role), function(_try : integer, _why : string) : Builder, {{number}}, string, string
			local b, seg = entryJoin(s, e, role)
			return b, seg, nil, nil
		end, LINK_TRIES, function(ok : boolean)
			if ok then
				e.joined = e.joined + 1
				joinedRole[role] = true
			end
			alone(k + 1)
		end)
	end
	local okB, merged, why = pcall(function() : Builder, string
		local list : {Builder} = {}
		for _, role in ipairs(roles) do list[#list + 1] = (entryJoin(s, e, role)) end
		return mergeBuilders(list)
	end)
	if not okB or merged == nil then
		local text = okB and tostring(why) or tostring(merged as any)
		rt.detail(string.format("[SQST] %s entry %s joins not merged (%s); one by one", s.name, e.name, text))
		alone(1)
		return
	end
	local okA, proposal = pcall(assemble, merged)
	if not okA then alone(1) return end
	local t0 = rt.nowUs()
	rt.send(s.name, api.cmd.makeWorldBuildProposalCmd(proposal as SimpleProposal, s.ctx, false, true, false), function(success : boolean, data : any)
		if success then
			e.joined = 3
			for _, role in ipairs(roles) do joinedRole[role] = true end
			rt.detail(string.format("[SQST] %s entry %s joined ms=%.0f (one proposal)", s.name, e.name, (rt.nowUs() - t0) / 1000))
			done()
		else
			rt.log(string.format("[SQST] %s entry %s joins refused (%s%s); one by one", s.name, e.name, errText(data), resultHits(data)))
			alone(1)
		end
	end)
end

--- Whether the entries of a set's towns differ between its twins (some roundabout, some crossroads): read
--- after every entry build (they come first), so the zone lines say match=no reason=entry.
local function entriesMixed(s : ShowState)
	local kinds : {integer : {string : boolean}} = {}
	for _, e in ipairs(s.entries or {}) do
		kinds[e.set] = kinds[e.set] or {}
		-- a roundabout counts with its inward arm's reach: twins with different reaches differ too
		kinds[e.set][e.kind == "roundabout" and ("roundabout/" .. tostring(e.ring) .. "/" .. tostring(e.inK)) or e.kind] = true
	end
	for set, k in pairs(kinds) do
		local n = 0
		for _ in pairs(k) do n = n + 1 end
		if n > 1 then s.lostEntries[set] = true end
	end
end

--- The game year (nil when unreadable).
local function gameYear() : integer
	local ok, y = pcall(api.engine.util.getYear)
	if ok and type(y) == "number" then return math.floor(y as number) end
	return nil
end

--- A Showcase run of `spec` (SHOWCASE_SPEC / LIGHTS_SPEC): towns, then every group's junction, one settle,
--- the reads, the links, (growth,) the bus lines. seed: the run's seed (nil: a fresh one; tests and
--- reproducing a logged run pass it).
local function buildRun(spec : SquareStressShowcaseSpec, seedArg? : integer) : boolean
	local title = spec.title or "Showcase"
	local name = spec.id or "showcase"
	local tm : {string : number} = { t0 = rt.nowUs() }
	local busy = rt.busyJob(TEST_JOBS)
	if busy ~= nil then
		rt.warn(title, "A test is already running (" .. busy .. "). Wait for it to finish.")
		return false
	end
	if jn.benchActive and not spec.bench then
		rt.warn(title, "A bench run is in progress: wait for it to finish (Towns tab > Bench shows its phase).")
		return false
	end
	local files : {string : string} = {}
	local missing : {string} = {}
	for _, kind in ipairs(logic.specKinds(spec)) do
		for _, t in ipairs(logic.specTypes(spec, kind)) do
			if files[t.file] == nil then
				local f = resolve(t.file)
				if f == nil then missing[#missing + 1] = t.file else files[t.file] = f end
			end
		end
	end
	if #missing > 0 then
		rt.warn(title, "Constructions not found (is Roundabouts & Interchanges enabled?): " .. table.concat(missing, ", "))
		return false
	end
	local cx, cy, mapW, mapH = 0.0, 0.0, 0.0, 0.0
	pcall(function()
		local box = api.engine.terrain.getBoundingBox()
		cx, cy = (box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2
		mapW, mapH = box.max.x - box.min.x, box.max.y - box.min.y
	end)
	if mapW <= 0 or mapH <= 0 then
		rt.warn(title, "The map size could not be read; nothing was built.")
		return false
	end
	local seed = seedArg or newSeed()
	if spec.litOnly then jn.lastLightsSeed = seed else jn.lastSeed = seed end
	local layout = spec.layoutFn ~= nil and spec.layoutFn(mapW, mapH, MAP_MARGIN, seed) or logic.showcaseLayout(mapW, mapH, MAP_MARGIN, seed, spec)
	local nGroups, nTowns, byKind, byAb = logic.showcaseCounts(layout, spec)
	if nGroups == 0 then
		rt.warn(title, string.format("Nothing fits this map (%.1f x %.1f km). Use a larger map.", mapW / 1000, mapH / 1000))
		return false
	end
	-- the bus lines come last: never skipped for money (Keep balance tops the balance up)
	local was = rt.keepBalance
	rt.keepBalance = true
	rt.log(string.format("[SQST] %s keep_balance=on (was %s)", name, was and "on" or "off"))
	local abText : {string} = {}
	for _, m in ipairs(logic.specModes(spec)) do abText[#abText + 1] = string.format("%s=%d", m.ab, byAb[m.ab] or 0) end
	local extra = ""
	if spec.litOnly then
		-- the game makes automatic lights only from 1950; the construction asks for Yes, which is unverified before then
		local year = gameYear()
		extra = string.format(" lights=yes year=%s", year ~= nil and tostring(year) or "?")
		if year ~= nil and year < logic.LIGHTS_LIT_FROM then
			rt.log(string.format("[SQST] %s year=%d before %d: no automatic lights; every crossing asks for Yes", name, year, logic.LIGHTS_LIT_FROM))
			rt.warn(title, string.format("The year is %d: the game builds no traffic lights before %d by itself. The Lights showcase asks for a light at every crossing (Yes) and sets one at the read when none stands, but lights before %d are untested. For certain lights, jump to %d or later first (Game tab > Date).",
				year, logic.LIGHTS_LIT_FROM, logic.LIGHTS_LIT_FROM, logic.LIGHTS_LIT_FROM))
		end
	end
	if spec.growFactor ~= nil then
		extra = extra .. string.format(" grow=x%g passes=%d%s", spec.growFactor, spec.growPasses or 1,
			spec.growTarget ~= nil and string.format(" grow_target=%d", math.floor(spec.growTarget)) or "")
	end
	if spec.shapeLabel ~= nil then extra = extra .. string.format(" shape=%d/%d (%s)", spec.shape or 1, #logic.LIGHTS_SHAPES, spec.shapeLabel)
	elseif spec.perType ~= nil then
		-- the spec's own shapes: each distinct kind's types in turn (the mixed spec: every LIGHTS_SHAPES shape)
		local labels : {string} = {}
		local seenKind : {string : boolean} = {}
		for _, kd in ipairs(logic.specKinds(spec)) do
			if not seenKind[kd] then
				seenKind[kd] = true
				for _, t in ipairs(logic.specTypes(spec, kd)) do labels[#labels + 1] = t.label end
			end
		end
		extra = extra .. string.format(" shapes=%s per_shape=%d", (table.concat(labels, ","):gsub(" ", "_")), spec.perType)
	end
	if spec.variant ~= nil then extra = extra .. " variant=" .. spec.variant end
	if spec.demandMix then
		-- sets per demand (the light plans A/B: tools/flow_report.py splits by the zone lines' demand=) and the town sizes
		local seen : {integer : boolean} = {}
		local nB, nU = 0, 0
		for _, g in ipairs(layout.groups) do
			if g.set ~= nil and not seen[g.set] then
				seen[g.set] = true
				if g.demand == "unbalanced" then nU = nU + 1 else nB = nB + 1 end
			end
		end
		extra = extra .. string.format(" demand=balanced:%d,unbalanced:%d pops=busy:%d,small:%d,tiny:%d unbalanced_sides=E,W:busy,N:small,S:tiny", nB, nU,
			math.floor(logic.LIGHTS_PLANS_POPS.busy), math.floor(logic.LIGHTS_PLANS_POPS.small), math.floor(logic.LIGHTS_PLANS_POPS.tiny))
	end
	if spec.noBusLines then extra = extra .. " bus_lines=no" end
	-- Lights showcase town entries: a roundabout (our own construction) at each town's side middle (SHOWCASE.md
	-- "Town entries"), else the grid's crossroads as before
	local entryFile : string = nil
	if spec.entries then
		entryFile = resolve(logic.ENTRY_CASE.file)
		extra = extra .. (entryFile ~= nil and " entries=roundabout" or " entries=crossroads (entry construction not found)")
		if spec.linkLanes ~= nil then extra = extra .. string.format(" link_lanes=%d", spec.linkLanes) end
	end
	rt.log(string.format("[SQST] %s: seed=%d map=%.0fx%.0fm groups=%d sets=%d %s twins %s towns=%d (%s)%s", name, seed, mapW, mapH, nGroups,
		layout.groups[nGroups].set or 0, kindText(spec, byKind), table.concat(abText, " "), nTowns, logic.specSizeText(spec), extra))
	-- the twins' zones go to Smart Lanes before anything is built (the towns take far longer than the event;
	-- the build job's first step waits for the acknowledgement: waitZones)
	-- one zone list for the channel, the run (readPlace updates it as built) and the traffic log
	-- (slzones.current: gui/stress_flow_log.tl samples the zones whose zone line was written, and restarts
	-- on a new list: a Lights showcase too)
	local zones0 = logic.showcaseZones(layout, cx, cy)
	local zonesRun = slzones.sendSet(zones0, seed)
	local small = logic.TOWN_SIZES[1]
	towns.createGrid({
		name = name .. "_towns",
		label = string.format("Creating %s towns", title:lower()),
		cols = nTowns,
		rows = 1,
		spacing = small.spacing,
		size = small,
		useCamera = true,
		cx = cx,
		cy = cy,
		connect = 1,
		-- Showcase towns: the grid built locked (stress_towns "Town growth locked into the grid")
		streets = spec.lockStreets and 3 or 2,
		points = layout.towns,
		skipNoLand = true,   -- a town without land is left out, the Showcase goes on (its arm unlinked)
		batch = true,        -- grids several per proposal, their locks across towns, every town in one command
	}, function(created : {integer : integer}, points : {SquareStressGridPoint}, skippedTowns : {integer : boolean}, timing : {string : number})
		for k, v in pairs(timing or {}) do tm[k] = v end
		-- the run's counters and lists in one table: the build step below must stay well within Lua
		-- 5.1's limit of 60 upvalues per function (tests/square_stress_test/test_showcase.lua checks it)
		local s : ShowState = { name = name, spec = spec, ctx = context(), seed = seed, files = files, layout = layout, points = points,
			created = created, tasks = {}, ours = {}, built = 0, refused = 0, linked = 0, unlinked = 0, builtBy = {}, plannedBy = byKind,
			builtAb = {}, plannedAb = byAb, zones = zones0, problems = {}, groupLinked = {}, avoid = {}, scans = {}, reach = {},
			reachOrder = {}, setPlaces = {}, setOrder = {}, skippedTowns = skippedTowns or {}, skipped = 0, lostSets = {}, lostLinks = {},
			zonesRun = zonesRun, tm = tm, entries = {}, entryOf = {}, lostEntries = {}, entryFile = entryFile, lostGeom = {} }
		-- towns skipped for want of land: their sets no longer match (their routes drop out by groupLinked)
		local skippedNames : {string} = {}
		for ti = 1, #layout.towns do
			if s.skippedTowns[ti] then
				s.skipped = s.skipped + 1
				skippedNames[#skippedNames + 1] = layout.towns[ti].name
			end
		end
		for gi, g in ipairs(layout.groups) do
			for _, ti in ipairs(g.towns) do
				if s.skippedTowns[ti] then s.lostSets[g.set or -gi] = true end
			end
		end
		if s.skipped > 0 then
			s.problems[#s.problems + 1] = string.format("%d town%s skipped: no land (%s)", s.skipped, s.skipped == 1 and "" or "s",
				table.concat(skippedNames, ", "))
		end
		-- build phase (every group's junction, the twins of a set back to back: the layout lists them
		-- together), one settle, the reads; the reads append the arm links
		local reads : {ShowTask} = {}
		s.tasks[1] = { kind = "zones" }
		-- the town entries first (the towns are still small: fewest houses in the way), read before the junctions
		if spec.entries then
			planEntries(s, cx, cy)
			for _, e in ipairs(s.entries) do
				s.tasks[#s.tasks + 1] = { kind = "ebuild", entry = e }
				reads[#reads + 1] = { kind = "eread", entry = e }
			end
			-- the last entries' streets locked once they are ENTRY_LOCK_AGE_MS old, before the junctions
			s.tasks[#s.tasks + 1] = { kind = "elock" }
		end
		for gi, g in ipairs(layout.groups) do
			local pl : ShowPlace = { built = false, group = gi, lightsOff = g.place.lightsOff == true,
				gap = g.kind == "ix" and ARM_GAP or SHOW_ARM_GAP }
			s.tasks[#s.tasks + 1] = { kind = "gbuild", group = gi, pl = pl }
			local set = g.set or -gi
			if s.setPlaces[set] == nil then
				s.setPlaces[set] = {}
				s.setOrder[#s.setOrder + 1] = set
			end
			table.insert(s.setPlaces[set], pl)
			reads[#reads + 1] = { kind = "read", pl = pl }
		end
		s.tasks[#s.tasks + 1] = { kind = "settle" }
		for _, t in ipairs(reads) do s.tasks[#s.tasks + 1] = t end
		-- the towns' own seed streets locked before anything else (serial: before the build job below)
		if spec.lockStreets then
			towns.lockTowns(name .. "_lock", showAreas(layout, points, created, s.skippedTowns), { pass = "towns", onDone = timed(s, "locks") })
		end

		rt.enqueue(name, #s.tasks, function(i : integer, job : SquareStressJob)
			local function finish()
				logic.resume(job)
				if i == job.total then showSummary(s) end
			end

			-- a bench stopped at its zones (waitZones): the job ends here, nothing more is built
			if s.aborted then
				job.total = i
				logic.resume(job)
				return
			end
			local task = s.tasks[i]
			if task == nil then finish() return end

			if task.kind == "zones" then
				s.tm.jT0 = rt.nowUs()
				waitZones(s, finish)
				return
			end

			if task.kind == "ebuild" then
				-- the entries built ENTRY_LOCK_AGE_MS ago or more locked first, then this one built
				lockDue(s, ENTRY_LOCK_AGE_MS, function()
					-- runs in a lock command's callback: an error must not stall the serial job until its timeout
					local okB, errB : boolean, any = pcall(buildEntry, s, task.entry, finish)
					if not okB then
						rt.log(logic.entryLine(s.name, task.entry.name, "crossroads", "(entry build error: " .. tostring(errB) .. ")"))
						finish()
					end
				end)
				return
			end
			if task.kind == "elock" then
				lockRest(s, finish)
				return
			end
			if task.kind == "eread" then
				-- an arm end missing: a town street hung on it is removed (removeStray) and the arms read once more
				local e = task.entry
				local finished = false
				local function once()
					if finished then return end
					finished = true
					finish()
				end
				local readDone = false
				local function finalRead()
					if readDone then return end
					readDone = true
					local okR, res = pcall(readEntry, s, e, job, true)
					if not okR then
						e.broken = "arms not read (read error: " .. tostring(res) .. ")"
						pcall(entryLost, s, e, "roundabout", e.broken)
						rt.log(logic.entryLine(s.name, e.name, "roundabout", e.broken))
					else
						rt.detail(logic.entryLine(s.name, e.name, "roundabout", "read again after the stray street check: " .. tostring(res)))
					end
					once()
				end
				local okF, first = pcall(readEntry, s, e, job, false)
				if not okF then
					finalRead()
				elseif first == "missing" then
					local missing : {string : boolean} = {}
					pcall(function()
						local roles = logic.entryRoles(e.x, e.y, e.out, endPoints(entryArmEnds(e)))
						for _, r in ipairs({ "out", "in", "left", "right" }) do
							if roles == nil or roles[r] == nil then missing[r] = true end
						end
					end)
					local okR, errR : boolean, any = pcall(removeStray, s, e, missing, function(_removed : boolean) finalRead() end)
					if not okR then
						rt.log(logic.entryLine(s.name, e.name, "roundabout", "stray street check failed: " .. tostring(errR)))
						finalRead()
					end
				else
					once()
				end
				return
			end
			if task.kind == "elink" then
				linkEntry(s, task.entry, finish)
				return
			end

			if task.kind == "settle" then
				-- every entry is built by now: a set whose towns' entries differ is no match (reason=entry)
				if s.entries ~= nil then entriesMixed(s) end
				-- One wait after the build phase: Smart Lanes rewrites each new junction's lanes and lights
				-- right after its build, and a link touching a node whose light change is still pending is
				-- refused (docs/findings.md "invalid entity"); the last build waits INLINE_SETTLE_MS, the
				-- earlier ones longer.
				-- the town entries' roundabouts are read after it too (their arm ends, Smart Lanes' writes)
				local nEntries = 0
				for _, e in ipairs(s.entries or {}) do
					if e.kind == "roundabout" then nEntries = nEntries + 1 end
				end
				if s.built == 0 and nEntries == 0 then finish() return end
				rt.detail(string.format("[SQST] %s: %d junctions built%s; reading their arms in %.0f s", s.name, s.built,
					nEntries > 0 and string.format(" (and %d town entries)", nEntries) or "", INLINE_SETTLE_MS / 1000))
				if s.spec.bench then
					-- the bench: then Smart Lanes idle (its queue empty: BENCH.md SL-5), at most BENCH_IDLE_MS more
					rt.later(s.name .. ":settle", INLINE_SETTLE_MS, function() slzones.waitIdle(s.name .. ":idle", BENCH_IDLE_MS, function(res : string, ms : number)
						rt.log(string.format("[SQST] %s smart_lanes idle=%s ms=%.0f (before the reads)", s.name, res, ms))
						finish()
					end) end)
					return
				end
				rt.later(s.name .. ":settle", INLINE_SETTLE_MS, finish)
				return
			end

			if task.kind == "read" then
				if not task.pl.built then finish() return end   -- refused or failed: its towns stay unlinked
				readPlace(s, task.pl, finish)
				return
			end

			if task.kind == "gbuild" then
				local gi = task.group
				local g = s.layout.groups[gi]
				local case_ = g.place.case_
				local x, y = cx + g.place.x, cy + g.place.y
				local tag = string.format("%s %s", g.name, case_.label)
				task.pl.onArms = function(clusters : {SquareStressArmCluster}, ends : {ArmEnd}) : string
					return groupArms(s, job, gi, x, y, tag, clusters, ends)
				end
				-- the construction seed and a redraw's seed by the set, so the twins stay identical
				local seedI = s.seed + (g.set or gi)
				showPlace(s, task.pl, tag, case_, x, y, g.place.angle, g.place.reach, seedI, finish,
					placeRetry(case_, g.place.reach, seedI, s.spec))
				return
			end

			-- glink: a group arm to its town; far-apart links share one proposal (planLinkGroups, sendGroup)
			if s.tm.lT0 == nil then
				if s.tm.jT0 ~= nil then s.tm.junctions = sinceMs(s.tm.jT0) end
				s.tm.lT0 = rt.nowUs()
			end
			if task.grouped then finish() return end
			if not s.linksPlanned then planLinkGroups(s, i) end
			local function alone()
				showLink(s, linkTag(task.arm), showToTown(s, task.arm), NODE_TRIES, function(ok : boolean)
					linkDone(s, task, ok)
					finish()
				end)
			end
			if task.members ~= nil and not task.solo then
				sendGroup(s, task, function(handled : boolean)
					if handled then finish() else alone() end
				end)
				return
			end
			alone()
		end, { serial = true, label = string.format("Building the %s", title:lower()) })
	end)
	return true
end

--- Showcase: towns, then every group's junction, one settle, the reads, the links, the bus lines.
--- seed: the run's seed (nil: a fresh one; tests and reproducing a logged run pass it).
function jn.buildShowcase(seedArg? : integer)
	buildRun(logic.SHOWCASE_SPEC, seedArg)
end

--- The Lights showcase's shape of the next press (1-based into LIGHTS_SHAPES; the session counter).
--- Lights showcase: every lit shape on one map (stress_logic.lightsMixedSpec: 2x2 X, 3x3 X, 3x2 X, T 2x2, three
--- sets each, the game and Smart Lanes twins), towns grown to about LIGHTS_TARGET_POP people after the links; no
--- bus lines; one press, no options. shape: one shape with its four twins instead (lightsSpec(shape): tests,
--- reproducing an earlier run with its seed).
function jn.buildLightsShowcase(seedArg? : integer, shape? : integer)
	local spec = shape ~= nil and logic.lightsSpec(shape) or logic.LIGHTS_SPEC
	buildRun(spec, seedArg)
end

--- Light plans A/B (stress_logic.lightsPlansSpec, SHOWCASE.md "Light plans A/B"): a 2x2 X and a 3x3 X lit crossroads,
--- three sets each, every set as three twins: the game's light plan, Smart Lanes' axis plan (sl_phases) and the axis
--- plan with its timing kept adjusted (sl_auto); balanced sets (towns of about LIGHTS_PLANS_TARGET_POP people) and
--- unbalanced ones (north town small, south town tiny) in turn. The Lights showcase's build otherwise. (The console
--- variant "classic", sl_classic as the third twin, is gone with Smart Lanes' classic patterns, 2026-10-16.)
function jn.buildLightPlans(seedArg? : integer)
	buildRun(logic.LIGHTS_PLANS_SPEC, seedArg)
end

--- A bench sheet (stress/stress_bench.tl, plans/square_stress_test/BENCH.md): its tests packed onto the map and
--- built with the Lights showcase's towns, entries, links, locks and growth. false when it did not start (busy,
--- nothing fits, constructions missing: said in a dialog). The orchestrator (gui/stress_bench_run.tl) calls it.
function jn.buildBench(sheet : SquareStressBenchSheet, seedArg? : integer) : boolean
	return buildRun(bench.spec(sheet), seedArg)
end

return jn
