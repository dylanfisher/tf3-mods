-- DEV ONLY (never upload): "DEV SQRB Bridge probe" (sqrb_probe_bridge.con.lua: the roundabout,
-- sqrb_probe_bridge_ix.con.lua: the Roundabout Interchange). Answers PLAN.md open item "Structure:
-- Embankment / Bridge": raised with the builder's Height, every edge gets an embankment; does a
-- bridge (or alignTerrain = false) place instead? PROBE.md "Phase 8: bridge probe".
--
-- Pure (no api.*), unit-tested in tests/square_roundabouts_probe/test_bridge.lua. Post-processes the
-- main mod's construction result (square_roundabouts_result.build of the real geometry), so the
-- square_roundabouts logic stays untouched:
--   structure Embankment       unchanged (what ships)
--   structure Bridge           every edge list without an edgeType becomes edgeType "BRIDGE" with
--                              the year's bridge (ramps.bridgeType: steel before 1970, concrete);
--                              lists that already are bridges (the interchange's) keep theirs
--   structure No align         every edge list gets alignTerrain = false (edge type unchanged; the
--                              field: base construction_util_serialized.d.tl:153, as base
--                              stations/air/airport.script.lua:683)
--   structure Bridge + no align  both
--   islands Drop               no island subconstruction (ground faces, models, colliders and its
--                              empty terrain alignment list), no top-level models / ground faces
-- Geometry is not touched, so the main mod's -0 normalisation (hx.positiveZeros) still holds.

local RB = "square_roundabouts::/infrastructure/street_construction/"
local ramps = ug_require(RB .. "square_roundabouts_ramps.lua")

local bridge = {}

bridge.KEYS = { structure = "sqrb_probe_structure", islands = "sqrb_probe_islands", bridgeType = "sqrb_probe_bridge_type" }
bridge.STRUCTURE_EMBANKMENT = 1
bridge.STRUCTURE_BRIDGE = 2
bridge.STRUCTURE_NO_ALIGN = 3
bridge.STRUCTURE_BRIDGE_NO_ALIGN = 4
bridge.STRUCTURE_LABELS = { "Embankment", "Bridge", "No align", "Bridge + no align" }
bridge.ISLANDS_KEEP = 1
bridge.ISLANDS_DROP = 2
bridge.ISLANDS_LABELS = { "Keep", "Drop" }
-- Probe bridge: which bridge type the Bridge structures use. Year = what the main mod would pick
-- (ramps.bridgeType). Pillar spacing (base .bridge.lua): concrete 60-84 m, steel 70-90 m, stone
-- 12-48 m (target 12), trestle 20-28 m; a roundabout's pieces are 15-30 m, so concrete and steel get
-- no pillars at all (in game 2026-10-22). Short concrete: the probe's own copy of concrete with
-- 12-24 m (../bridge/sqrb_probe_concrete_short.bridge.lua).
bridge.BRIDGE_TYPE_LABELS = { "Year", "Stone", "Trestle", "Steel", "Concrete", "Short concrete" }
bridge.BRIDGE_TYPE_NAMES = { false, "::/infrastructure/bridge/stone.bridge", "::/infrastructure/bridge/trestle.bridge",
	"::/infrastructure/bridge/steel.bridge", "::/infrastructure/bridge/concrete.bridge",
	"square_roundabouts_probe::/infrastructure/bridge/sqrb_probe_concrete_short.bridge" }

local function index(v, n, default)
	v = tonumber(v)
	if v and v == math.floor(v) and v >= 1 and v <= n then return v end
	return default
end

--- {structure, islands, year} from the construction params (year: the builder's params.year).
function bridge.readParams(params)
	params = params or {}
	return {
		structure = index(params[bridge.KEYS.structure], #bridge.STRUCTURE_LABELS, bridge.STRUCTURE_EMBANKMENT),
		islands = index(params[bridge.KEYS.islands], #bridge.ISLANDS_LABELS, bridge.ISLANDS_KEEP),
		year = tonumber(params.year),
		bridgeType = index(params[bridge.KEYS.bridgeType], #bridge.BRIDGE_TYPE_LABELS, 1),
	}
end

function bridge.asBridge(spec)
	return spec.structure == bridge.STRUCTURE_BRIDGE or spec.structure == bridge.STRUCTURE_BRIDGE_NO_ALIGN
end

function bridge.noAlign(spec)
	return spec.structure == bridge.STRUCTURE_NO_ALIGN or spec.structure == bridge.STRUCTURE_BRIDGE_NO_ALIGN
end

--- Applies spec to a construction result (square_roundabouts_result.build); returns it (changed in place).
function bridge.apply(res, spec)
	local name = bridge.BRIDGE_TYPE_NAMES[spec.bridgeType or 1] or ramps.bridgeType(spec.year)
	for _, el in ipairs(res.edgeLists or {}) do
		if bridge.asBridge(spec) and el.edgeType == nil then
			el.edgeType = "BRIDGE"
			el.edgeTypeName = name
		end
		if bridge.noAlign(spec) then el.alignTerrain = false end
	end
	if spec.islands == bridge.ISLANDS_DROP then
		res.subconstructions = nil
		res.models = {}
		res.groundFaces = {}
		res.terrainAlignmentLists = nil
	end
	return res
end

--- The probe's two params (appended to each probe entry's params).
function bridge.params()
	return {
		{
			key = bridge.KEYS.bridgeType,
			name = "Probe bridge",
			tooltip = "DEV. Bridge type for the Bridge structures.\nYear: the main mod's pick (steel before 1970, concrete).\nShort concrete: concrete with pillars every 12-24 m.",
			uiType = "ComboBox",
			values = bridge.BRIDGE_TYPE_LABELS,
			defaultIndex = 1,
		},
		{
			key = bridge.KEYS.structure,
			name = "Probe structure",
			tooltip = "DEV. Embankment: unchanged (what ships).\nBridge: every road a bridge (the year's bridge type).\nNo align: alignTerrain = false on every road.\nBridge + no align: both.",
			uiType = "ComboBox",
			values = bridge.STRUCTURE_LABELS,
			defaultIndex = bridge.STRUCTURE_EMBANKMENT, -- 1-based in a .con.lua (as the main entries)
		},
		{
			key = bridge.KEYS.islands,
			name = "Probe islands",
			tooltip = "DEV. Drop: no centre / splitter islands\n(their ground faces sit at ground level).",
			uiType = "Button",
			values = bridge.ISLANDS_LABELS,
			defaultIndex = bridge.ISLANDS_KEEP,
		},
	}
end

return bridge
