-- Supply Gaps markers (PLAN "Rendering, track A"): world markers on gap buildings through
-- api.gui.mission.setMarkerAtEntity(key, entity, type, scaling, isSelectable, fireSelectEntity)
-- (api/tealdef/api/gui.d.tl:685-745), as base mission/mission_sim.script.tl:1072-1084. GUI thread only.
-- Keys are KEY_PREFIX .. entity, so we only ever remove our own (the mission framework likewise
-- removes only the keys it knows, mission_sim.script.tl:1137-1144).
-- Each tick sends only the difference (model.diff). Every engine call is in pcall; a failing call is
-- counted and the first ERR_LOGS are logged.
--
-- Kinds: unreached gaps get TYPE ("arrow"), starved gaps TYPE_STARVED ("question_red"); both render in
-- free play (Phase 2 in-game test). A building whose kind changes gets its marker removed and set
-- again with the new type. Models: base/content/assets/markers/marker_{arrow,question_red}.mdl. The engine maps
-- types to models through a fixed table (MarkerManager m_type2modelName: arrow, exclamation, question,
-- question_red, locate; an unknown type asserts and shows the default yellow model, verified in game
-- 2026-10-10 with "exclamation_red"), so a mod cannot add its own marker type or colour.

local model = ug_require "square_supply_gaps::/supply_gaps/sg_model.tl" as SupplyGapsModel

local markers : SupplyGapsMarkers = {}

markers.KEY_PREFIX = "sqsg:"
markers.TYPE = "arrow"
markers.TYPE_STARVED = "question_red"
markers.SCALE = 0.75

markers.shown = {}
markers.typeOf = {}

local LOG_PREFIX <const> = "[SQSG] "
local ERR_LOGS <const> = 20
local errLogged = 0

--- pcall for a function without results: ok, error text.
local function try(fn : function()) : boolean, string
	local ok, e = pcall(function() : boolean
		fn()
		return true
	end)
	if ok then return true, nil end
	return false, tostring(e)
end

local function err(where : string, msg : any)
	errLogged = errLogged + 1
	if errLogged <= ERR_LOGS then
		log.message(LOG_PREFIX .. "ERR " .. where .. " " .. tostring(msg))
	end
end

local function addOne(e : integer, typ : string) : boolean
	local ok, msg = try(function()
		-- isSelectable + fireSelectEntity: a click on the marker opens the building's window.
		api.gui.mission.setMarkerAtEntity(markers.KEY_PREFIX .. tostring(e), e, typ, markers.SCALE, true, true)
	end)
	if not ok then err("marker " .. tostring(e), msg) end
	return ok
end

local function removeOne(e : integer) : boolean
	local ok, msg = try(function()
		api.gui.mission.removeMarker(markers.KEY_PREFIX .. tostring(e))
	end)
	if not ok then err("remove " .. tostring(e), msg) end
	return ok
end

local function typeFor(e : integer, kinds : {integer : string}) : string
	if kinds ~= nil and kinds[e] == model.STARVED then return markers.TYPE_STARVED end
	return markers.TYPE
end

function markers.apply(next : {integer}, kinds? : {integer : string}) : SupplyGapsMarkerStats
	local stats : SupplyGapsMarkerStats = { added = 0, removed = 0, errors = 0, shown = 0, retyped = 0 }
	-- Kind changed (unreached <-> starved): remove now, the diff below adds it back with the new type.
	for __, e in ipairs(next or {}) do
		if markers.shown[e] and (markers.typeOf[e] or markers.TYPE) ~= typeFor(e, kinds) then
			if not removeOne(e) then stats.errors = stats.errors + 1 end
			markers.shown[e], markers.typeOf[e] = nil, nil
			stats.retyped = stats.retyped + 1
		end
	end
	local d = model.diff(markers.shown, next)
	for __, e in ipairs(d.remove) do
		if not removeOne(e) then stats.errors = stats.errors + 1 end
		markers.shown[e], markers.typeOf[e] = nil, nil
		stats.removed = stats.removed + 1
	end
	local addSet : {integer : boolean} = {}
	for __, e in ipairs(d.add) do addSet[e] = true end
	-- Add in `next` order (nearest first).
	for __, e in ipairs(next or {}) do
		if addSet[e] then
			addSet[e] = nil
			local typ = typeFor(e, kinds)
			if addOne(e, typ) then
				markers.shown[e] = true
				markers.typeOf[e] = typ
				stats.added = stats.added + 1
			else
				stats.errors = stats.errors + 1
			end
		end
	end
	for __ in pairs(markers.shown) do stats.shown = stats.shown + 1 end
	return stats
end

function markers.clearAll() : SupplyGapsMarkerStats
	local stats : SupplyGapsMarkerStats = { added = 0, removed = 0, errors = 0, shown = 0, retyped = 0 }
	for __, e in ipairs(model.sortedKeys(markers.shown)) do
		if not removeOne(e) then stats.errors = stats.errors + 1 end
		stats.removed = stats.removed + 1
	end
	markers.shown, markers.typeOf = {}, {}
	return stats
end

function markers.forget() : integer
	local n = 0
	for __ in pairs(markers.shown) do n = n + 1 end
	markers.shown, markers.typeOf = {}, {}
	return n
end

return markers
