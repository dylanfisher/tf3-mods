-- DEV ONLY (never upload): Roundabouts placement probe, the part that asks the engine.
-- Runs on the GUI thread (probe.script.lua guiUpdate). Builds a SimpleProposal with one
-- ConstructionEntity per combo and asks api.engine.util.proposal.makeProposalData for its
-- ProposalData, WITHOUT sending a command: nothing is ever built (there is no api.cmd call in
-- this mod).
--
-- API evidence (PROBE.md "How it works"):
--   * makeProposalData(proposal, context?) : ProposalData        api/engine/util.d.tl:925
--     The Teal declaration says Proposal, but the native function takes a SimpleProposal:
--     .cache/subscribed/move_it_probe_overpass/content/tools/overpass_probe/overpass_probe.script.tl:325-330
--     ("Build 40408 requires SimpleProposal here"), called from a GUI construction tool.
--   * ProposalData.errorState {critical, messages, warnings, infos}, collisionInfo, costs,
--     toAddData                                                    api/type.d.tl:2693-2760
--     The GUI shows errorState.messages for a proposal: base gui/entity_window/bridge_and_tunnel.tl:131-134
--   * SimpleProposal / SimpleProposal.ConstructionEntity{fileName, params, transf, name, playerEntity}
--                                                                 api/type.d.tl:2827-2860
--     built like base mission/mission_framework/mission_framework_util_entity.tl:98-113 and
--     .cache/game/mods/release/urbangames_campaign_mission_05/content/mission/tasks/drilling/send_vehicle.tl:29-45
--   * getConstructionResult(resName, templateIndex, params)      api/engine/util.d.tl:809-814
--     (-1 = no template, as base gui/construction/construction_react_util.tl:1031 and
--     construction.tl:3655); getGlobalConstructionParams()        api/engine/util.d.tl:815-817,
--     used for the builder preview params in construction.tl:3668-3672
--   * api.engine.terrain.getHeightAt / isOnWater(Vec2f)           api/engine.d.tl:1725-1745,1811
--   * api.res.constructionRep.find(resName) : id, -1 if missing   api/res.d.tl:26-29
--   * api.res.streetTemplateRep.find(resName) / .get(id) : StreetTemplate  api/res.d.tl:147,
--     fields api/type.d.tl:5471-5531 (LaneConfig 5369-5382); read like base
--     base/mod.script.tl:406 (Phase 7d, R3/R4: one INFO line per highway template, read only)

local grid = ug_require "square_roundabouts_probe::/probe/probe_grid.lua"
local config = ug_require "square_roundabouts_probe::/probe/probe_config.lua"
local geomInfo = ug_require "square_roundabouts_probe::/probe/probe_geom.lua"

local engine = {}
engine.__index = engine

local RB_DIR = "square_roundabouts::/infrastructure/street_construction/"

--- A native list (Lua table or vector userdata) as a plain list of strings.
local function toList(v)
	local out = {}
	if v == nil then return out end
	local ok = pcall(function()
		local n = #v
		for i = 1, n do out[#out + 1] = tostring(v[i]) end
	end)
	if not ok then
		out = {}
		pcall(function() for _, s in ipairs(v) do out[#out + 1] = tostring(s) end end)
	end
	return out
end
engine.toList = toList

local function count(v)
	if v == nil then return 0 end
	local ok, n = pcall(function() return #v end)
	return ok and n or nil
end

local function field(obj, key)
	if obj == nil then return nil end
	local ok, v = pcall(function() return obj[key] end)
	if ok then return v end
	return nil
end

--- new(cfg, log): cfg from config.fromModParams; log(line) writes one stdout line.
function engine.new(cfg, log)
	local self = setmetatable({}, engine)
	self.cfg = cfg
	self.log = log
	self.mode = "proposal"
	self.proposalFails = 0
	self.proposalSuccesses = 0
	self.files = {}
	self.modules = {}
	return self
end

function engine:info(text)
	self.log(grid.PREFIX .. " INFO " .. grid.clean(text))
end

function engine:error(text)
	self.log(grid.PREFIX .. " ERROR " .. grid.clean(text))
end

--- Resource name of an entry's .con as the construction repository knows it, or nil. file = one of
-- the entry's per-type files (grid.ENTRIES.highway.files; cached under the file), default its `file`.
function engine:resolveFile(entry, file)
	file = file or grid.ENTRIES[entry].file
	local cacheKey = file == grid.ENTRIES[entry].file and entry or file
	if self.files[cacheKey] ~= nil then return self.files[cacheKey] or nil end
	-- Phase 8: the DEV Bridge probe entries live in this mod (grid.ENTRIES[entry].mod)
	local mod = grid.ENTRIES[entry].mod or grid.TARGET_MOD
	local candidates = {
		mod .. "::/" .. file,
		mod .. "::" .. file,
		file,
	}
	for _, name in ipairs(candidates) do
		local ok, id = pcall(api.res.constructionRep.find, name)
		if ok and type(id) == "number" and id >= 0 then
			self.files[cacheKey] = name
			self:info("entry " .. entry .. ": construction '" .. name .. "' id " .. tostring(id))
			return name
		end
	end
	self.files[cacheKey] = false
	self:error("entry " .. entry .. ": no construction found (tried " .. table.concat(candidates, ", ") ..
		"); is " .. mod .. " enabled for this game?")
	return nil
end

--- The square_roundabouts geometry modules (for the effective radius), loaded once.
function engine:loadGeometry()
	local okG, geom = pcall(ug_require, RB_DIR .. "square_roundabouts_geometry.lua")
	local okM, magic = pcall(ug_require, RB_DIR .. "square_roundabouts_magic.lua")
	self.modules.geom = okG and geom or nil
	self.modules.magic = okM and magic or nil
	if not okG then self:error("geometry module not loadable: " .. tostring(geom)) end
	if not okM then self:error("magic module not loadable: " .. tostring(magic)) end
	-- Phase 5b / 5d entries (an older square_roundabouts has neither: logged, the rest still runs)
	local okC, channel = pcall(ug_require, RB_DIR .. "square_roundabouts_channel.lua")
	local okX, interchange = pcall(ug_require, RB_DIR .. "square_roundabouts_interchange.lua")
	self.modules.channel = okC and channel or nil
	self.modules.interchange = okX and interchange or nil
	if not okC then self:error("channel module not loadable: " .. tostring(channel)) end
	if not okX then self:error("interchange module not loadable: " .. tostring(interchange)) end
	-- Phase 7d: Highway Interchange (and its ramps module, for the template names)
	local okH, highway = pcall(ug_require, RB_DIR .. "square_roundabouts_highway.lua")
	local okR, ramps = pcall(ug_require, RB_DIR .. "square_roundabouts_ramps.lua")
	self.modules.highway = okH and highway or nil
	self.modules.ramps = okR and ramps or nil
	if not okH then self:error("highway module not loadable: " .. tostring(highway)) end
end

--- Street templates whose engine limits the Highway Interchange depends on (R3 / R4 in
-- INTERCHANGES.md): the ramps' template (highway_new_small), then the other highway templates.
function engine.templateNames(ramps)
	local names, seen = {}, {}
	local function add(t)
		if type(t) == "string" and not seen[t] then
			seen[t] = true
			names[#names + 1] = t
		end
	end
	if ramps then
		add(ramps.RAMP and ramps.RAMP.template)
		for _, h in ipairs(ramps.HIGHWAYS or {}) do add(h.template) end
	end
	if #names == 0 then add("::/infrastructure/street/highway/highway_new_small.street_template") end
	return names
end

local function fmtNum(v)
	if type(v) ~= "number" then return v == nil and "-" or tostring(v) end
	-- 4 significant digits: slopes such as 0.075 keep their precision
	return string.format("%.4g", v)
end

--- One INFO text for a street template read from api.res.streetTemplateRep (any field may be
-- missing: "-"). Pure apart from reading tpl's fields (pcall per field), so it is unit-tested.
function engine.describeTemplate(name, id, tpl)
	local parts = { "street template " .. tostring(name) .. " id " .. tostring(id) .. ":" }
	if tpl == nil then
		parts[#parts + 1] = "not found"
		return table.concat(parts, " ")
	end
	for _, k in ipairs({ "maxSlope", "maxSlopeShape", "maxSlopeBuild", "minCurveRadius", "minCurveRadiusBuild" }) do
		parts[#parts + 1] = k .. "=" .. fmtNum(field(tpl, k))
	end
	local coeffs = {}
	for i, v in ipairs(toList(field(tpl, "speedCoeffs"))) do coeffs[i] = fmtNum(tonumber(v) or v) end
	parts[#parts + 1] = "speedCoeffs=" .. (#coeffs > 0 and table.concat(coeffs, "/") or "-")
	local speeds = {}
	local lanes = field(tpl, "laneConfigs")
	pcall(function()
		for i = 1, #lanes do speeds[#speeds + 1] = fmtNum(field(lanes[i], "speed")) end
	end)
	parts[#parts + 1] = "laneSpeeds=" .. (#speeds > 0 and table.concat(speeds, "/") or "-")
	parts[#parts + 1] = "country=" .. fmtNum(field(tpl, "country"))
	return table.concat(parts, " ")
end

--- Logs the engine's limits of the highway templates once (read only; never raises).
function engine:logTemplates()
	for _, name in ipairs(engine.templateNames(self.modules.ramps)) do
		local okF, id = pcall(function() return api.res.streetTemplateRep.find(name) end)
		if not okF or type(id) ~= "number" or id < 0 then
			self:info(engine.describeTemplate(name, okF and id or ("error: " .. tostring(id)), nil))
		else
			local okG, tpl = pcall(function() return api.res.streetTemplateRep.get(id) end)
			self:info(engine.describeTemplate(name, id, okG and tpl or nil))
		end
	end
end

--- The camera's look-at point and the mouse's last terrain point (GUI thread; nil when unavailable).
function engine.cameraAndMouse()
	local cam, mouse
	pcall(function()
		local d = api.gui.camera.getCameraData()
		if d ~= nil then cam = { d.x, d.y, d.z } end -- x, y, distance (gui.d.tl:434)
	end)
	pcall(function()
		if api.gui.mouse.hasTerrainPosition == nil or api.gui.mouse.hasTerrainPosition() then
			local m = api.gui.mouse.getTerrainPosition()
			if m ~= nil then mouse = { m.x, m.y, m.z } end
		end
	end)
	return cam, mouse
end

local function xyText(v)
	if not v then return "-" end
	return string.format("%.2f/%.2f/%.2f", v[1], v[2], v[3] or 0)
end

--- Where to place: the Position setting, except that the spot subsets (p7_spot*) use the camera
-- centre when it is X / Y (a loaded save kept a new setting at its mod.json default: PROBE.md).
function engine.positionSource(cfg)
	local src = cfg.pos or "setting"
	if src == "setting" and type(cfg.subset) == "string" and cfg.subset:sub(1, 7) == "p7_spot" then return "camera" end
	return src
end

--- World position at terrain height; logs it.
function engine:placement()
	local x, y = self.cfg.x, self.cfg.y
	local cam, mouse = engine.cameraAndMouse()
	local src = engine.positionSource(self.cfg)
	self:info("position source " .. tostring(src) .. " (setting " .. tostring(self.cfg.pos) .. "); camera (x/y/distance) " ..
		xyText(cam) .. ", mouse (x/y/z) " .. xyText(mouse))
	if src == "camera" then
		if cam then x, y = cam[1], cam[2] else self:error("camera position unavailable; using the X / Y settings") end
	elseif src == "mouse" then
		if mouse then x, y = mouse[1], mouse[2] else self:error("mouse position unavailable; using the X / Y settings") end
	end
	local z = 0
	local okH, h = pcall(function() return api.engine.terrain.getHeightAt(api.type.Vec2f.new(x, y)) end)
	if okH and type(h) == "number" then z = h else self:error("getHeightAt failed: " .. tostring(h)) end
	local okW, water = pcall(function() return api.engine.terrain.isOnWater(api.type.Vec2f.new(x, y)) end)
	local okV, valid = pcall(function() return api.engine.terrain.isValidCoordinate(api.type.Vec2f.new(x, y)) end)
	if okW and water then self:error("probe position is on water; results will be about water, not geometry") end
	if okV and valid == false then self:error("probe position is outside the map") end
	self.x, self.y, self.z = x, y, z
	local c, s = engine.cosSin(0)
	self.transf = api.type.Mat4f.new(
		api.type.Vec4f.new(c, s, 0, 0),
		api.type.Vec4f.new(-s, c, 0, 0),
		api.type.Vec4f.new(0, 0, 1, 0),
		api.type.Vec4f.new(x, y, z, 1)
	)
	return x, y, z
end

-- The UI construction builder's transf at Rotation 0 is 1/-0/0/0/0/1/... (the 7e watcher logs): its rotation is -0,
-- so sin = -0 and a -0 in a tangent stays -0 in world space (docs/findings.md "Negative zero in
-- construction geometry": the engine refused the highway entry for exactly that, and a +0 identity
-- transf placed it). The probe copies it. false = the old +0 identity (the pre-2026-10-09 behaviour).
engine.BUILDER_ZERO = true

--- cos, sin of deg degrees as the builder makes them: deg 0 -> (1, -0) when engine.BUILDER_ZERO. Pure.
function engine.cosSin(deg)
	if deg == 0 and engine.BUILDER_ZERO then
		local z = 0.0
		deg = -z -- computed at run time: a -0 literal can share the +0 constant slot
	end
	local a = math.rad(deg)
	return math.cos(a), math.sin(a)
end

--- The global construction params (plain table copy), logged once.
function engine:loadGlobals()
	local globals = {}
	local ok, g = pcall(api.engine.util.construction.getGlobalConstructionParams)
	if ok and g ~= nil then
		pcall(function() for k, v in pairs(g) do globals[k] = v end end)
	else
		self:error("getGlobalConstructionParams failed: " .. tostring(g))
	end
	local keys = {}
	for k, v in pairs(globals) do keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
	table.sort(keys)
	self:info("global construction params: " .. (#keys > 0 and table.concat(keys, ",") or "(none)"))
	self.globals = globals
end

function engine:loadPlayer()
	local ok, p = pcall(api.engine.util.getPlayer)
	self.player = ok and p or -1
	if not ok then self:error("getPlayer failed: " .. tostring(p)) end
end

function engine:makeContext()
	if self.cfg.context ~= "player" then return nil end
	return self:contextFor("full")
end

-- p7_spot contexts (grid.SPOT_CONTEXTS): none; player only (as the GUI's bridge window,
-- bridge_and_tunnel.tl:187-190); player + terrain alignment check; full (every flag, the
-- "Player" setting).
engine.CONTEXT_FLAGS = {
	player = {},
	terrain = { checkTerrainAlignment = true },
	full = { checkTerrainAlignment = true, cleanupStreetGraph = true, gatherBuildings = true, gatherFields = true },
}

--- A proposal Context by name (cached), nil for "none" or when Context.new fails.
function engine:contextFor(name)
	local flags = engine.CONTEXT_FLAGS[name]
	if not flags then return nil end
	self.contexts = self.contexts or {}
	if self.contexts[name] ~= nil then return self.contexts[name] or nil end
	local ok, ctx = pcall(function()
		local c = api.type.Context.new()
		c.player = self.player
		for k, v in pairs(flags) do c[k] = v end
		return c
	end)
	if ok then
		self.contexts[name] = ctx
		return ctx
	end
	self.contexts[name] = false
	self:error("Context.new failed (" .. name .. "), using none: " .. tostring(ctx))
	return nil
end

--- p7_spot: transf and world origin of a place {rot, dx, dy, dz?} around the probe position (z = the
-- terrain height at the shifted origin, as the builder at Height 0; Phase 8: plus dz, as the builder's
-- Height, which reaches the construction only through the transf: PROBE.md "Phase 8: bridge probe").
function engine:transfFor(place)
	local x, y = self.x + (place.dx or 0), self.y + (place.dy or 0)
	local z = self.z
	pcall(function()
		local h = api.engine.terrain.getHeightAt(api.type.Vec2f.new(x, y))
		if type(h) == "number" then z = h end
	end)
	z = z + (tonumber(place.dz) or 0)
	local c, s = engine.cosSin(place.rot or 0)
	local t = api.type.Mat4f.new(
		api.type.Vec4f.new(c, s, 0, 0),
		api.type.Vec4f.new(-s, c, 0, 0),
		api.type.Vec4f.new(0, 0, 1, 0),
		api.type.Vec4f.new(x, y, z, 1)
	)
	return t, { x, y, z }
end

--- One-time setup on the GUI thread. Returns false if there is nothing to probe.
function engine:setup()
	self:loadGeometry()
	self:loadPlayer()
	self:loadGlobals()
	self:placement()
	self.ctx = self:makeContext()
	pcall(function() self:logTemplates() end)
	local any = false
	for _, entry in ipairs(grid.ENTRY_ORDER) do
		if self:resolveFile(entry) ~= nil then any = true end
		-- the Highway Interchange's per-type entries (Phase 7c2): logged once each
		for _, f in ipairs(grid.ENTRIES[entry].files or {}) do self:resolveFile(entry, f) end
	end
	return any
end

--- Header fields for the START line.
function engine:header()
	return {
		{ "x", self.x }, { "y", self.y }, { "z", self.z },
		{ "pos", self.cfg.pos }, { "context", self.cfg.context }, { "player", self.player },
		{ "main", self.files.main or "-" }, { "magic", self.files.magic or "-" },
		{ "channel", self.files.channel or "-" }, { "interchange", self.files.interchange or "-" },
		{ "highway", self.files.highway or "-" },
		{ "bridgeMain", self.files.bridge_main or "-" }, { "bridgeIx", self.files.bridge_ix or "-" },
		{ "geometry", self.modules.geom and "yes" or "no" },
	}
end

--- The construction file of a combo: the entry's, or (Highway Interchange, Phase 7c2) the per-type
-- entry's (grid.ENTRIES.highway.files by the combo's sqrb_hx_type), or nil if not found.
function engine:fileFor(combo)
	local e = grid.ENTRIES[combo.entry]
	if e.files then
		local f = e.files[tonumber(combo.params[e.fileAxis]) or 1] or e.file
		return self:resolveFile(combo.entry, f)
	end
	return self.files[combo.entry] or nil
end

--- Construction params for a combo: global params, EXTRA_PARAMS, then the combo's sqrb_* values.
function engine:paramsFor(combo)
	local p = {}
	for k, v in pairs(self.globals or {}) do p[k] = v end
	for k, v in pairs(config.EXTRA_PARAMS) do p[k] = v end
	for k, v in pairs(combo.params) do p[k] = v end
	-- Phase 7c3: the highway entry's Layout button for the combo's type (grid.ENTRIES.highway.layouts)
	local e = grid.ENTRIES[combo.entry]
	if e and e.layouts and e.fileAxis then
		local li = e.layouts[tonumber(combo.params[e.fileAxis]) or 1]
		if li then p[e.layoutKey] = li end
	end
	-- base helpers always give constructions a seed (mission_framework_util_entity.tl:99-102)
	if p.seed == nil then p.seed = 1 end
	return p
end

function engine:proposalFor(fileName, params, transf)
	local sp = api.type.SimpleProposal.new()
	local ce = api.type.SimpleProposal.ConstructionEntity.new()
	ce.fileName = fileName
	ce.params = params
	ce.transf = transf or self.transf
	ce.name = "SQRB probe"
	ce.playerEntity = self.player
	sp.constructionsToAdd = { ce }
	return sp
end

--- updateFn check: "ok", "nil" or "error: ...".
function engine:updateFnCheck(fileName, params)
	local ok, res = pcall(api.engine.util.construction.getConstructionResult, fileName, -1, params)
	if not ok then
		local ok0, res0 = pcall(api.engine.util.construction.getConstructionResult, fileName, 0, params)
		if ok0 then return res0 ~= nil and "ok (template 0)" or "nil (template 0)", res0 ~= nil end
		return "error: " .. tostring(res), false
	end
	if res == nil then return "nil", false end
	return "ok", true
end

function engine:fallBack(reason)
	if self.mode == "result_only" then return end
	self.mode = "result_only"
	self:error("makeProposalData keeps failing (" .. tostring(reason) ..
		"); from now on only the updateFn is checked (mode=result_only)")
end

--- Reads a ProposalData into the result table.
local function readProposalData(pd, r)
	local es = field(pd, "errorState")
	r.critical = field(es, "critical") == true
	r.messages = toList(field(es, "messages"))
	r.warnings = toList(field(es, "warnings"))
	r.infos = toList(field(es, "infos"))
	local ci = field(pd, "collisionInfo")
	r.collisions = count(field(ci, "collisionEntities"))
	r.buildings = count(field(ci, "buildingEntities"))
	r.added = count(field(pd, "toAddData"))
	r.cost = field(pd, "costs")
	if es == nil then r.messages[#r.messages + 1] = "probe: ProposalData has no errorState" end
	r.ok = es ~= nil and not r.critical and #r.messages == 0
end

--- Evaluates one combo (grid.resultLine documents the fields).
function engine:evaluate(combo)
	local r = { mode = self.mode }
	local fileName = self:fileFor(combo)
	if not fileName then
		r.ok = false
		r.error = "construction for entry '" .. combo.entry .. "' not found"
		return r
	end
	local params = self:paramsFor(combo)
	r.geom = geomInfo.forEntry(combo.entry, self.modules, combo.params)
	if r.geom.sane == false then
		-- never send degenerate geometry (dev overrides can force it): a NaN edge crashes the game
		r.ok = false
		r.messages = { "probe: degenerate geometry, not sent (" .. tostring(r.geom.insane) .. ")" }
		return r
	end

	if self.mode == "proposal" then
		local ctx, transf, origin = self.ctx, nil, nil
		if combo.place then
			ctx = self:contextFor(combo.place.ctx)
			transf, origin = self:transfFor(combo.place)
		end
		local okCall, pd = pcall(function()
			local sp = self:proposalFor(fileName, params, transf)
			if ctx ~= nil then return api.engine.util.proposal.makeProposalData(sp, ctx) end
			return api.engine.util.proposal.makeProposalData(sp)
		end)
		if okCall and pd ~= nil then
			self.proposalSuccesses = self.proposalSuccesses + 1
			self.proposalFails = 0
			readProposalData(pd, r)
			if combo.place then
				local okD, line = pcall(function() return self:detailLine(combo, r, pd, origin, params) end)
				self.log(okD and line or (grid.PREFIX .. " ERROR detail line: " .. grid.clean(line)))
			end
		else
			r.ok = false
			r.error = okCall and "makeProposalData returned nil" or tostring(pd)
			self.proposalFails = self.proposalFails + 1
			if self.proposalSuccesses == 0 and self.proposalFails >= config.PROPOSAL_FAILS_TO_FALL_BACK then
				self:fallBack(r.error)
			end
		end
	end

	local check = config.UPDATE_FN_CHECK
	if self.mode == "result_only" or check == "always" or (check == "on_fail" and not r.ok) then
		local text, fine = self:updateFnCheck(fileName, params)
		r.updateFn = text
		if self.mode == "result_only" and r.error == nil then
			r.mode = "result_only"
			r.ok = fine
		end
	end
	return r
end

-- p7_spot details ------------------------------------------------------------------------------

local CLASSIFY = {
	{ "BASE_EDGE_STREET", "street" }, { "BASE_EDGE", "edge" }, { "BASE_NODE", "node" },
	{ "CONSTRUCTION", "con" }, { "TOWN_BUILDING", "townbuilding" }, { "FIELD", "field" },
	{ "INDUSTRY", "industry" }, { "BRIDGE", "bridge" }, { "MODEL_INSTANCE_LIST", "models" },
	{ "TOWN", "town" }, { "STATION", "station" }, { "SUBCONSTRUCTION", "subcon" },
}

--- "id:type+type" for an entity: "new" for ids < 0 (entities of the proposal itself), the
-- component types it has otherwise (checked with entityExists first; never raises).
function engine.classify(id)
	if type(id) ~= "number" then return tostring(id) .. ":?" end
	if id < 0 then return tostring(id) .. ":new" end
	local okE, exists = pcall(api.engine.entityExists, id)
	if not okE or not exists then return tostring(id) .. ":gone" end
	local kinds = {}
	for _, c in ipairs(CLASSIFY) do
		local okC, comp = pcall(function() return api.engine.getComponent(id, api.type.ComponentType[c[1]]) end)
		if okC and comp ~= nil then
			local k = c[2]
			if k == "con" then
				local fn = field(comp, "fileName")
				if fn then k = k .. "(" .. tostring(fn):gsub("[%s|]", "_") .. ")" end
			end
			kinds[#kinds + 1] = k
		end
	end
	return tostring(id) .. ":" .. (#kinds > 0 and table.concat(kinds, "+") or "other")
end

local function entityOf(e)
	if type(e) == "number" then return e end
	return field(e, "entity")
end

local MAX_IDS = 16

--- The D line of a p7_spot combo: collisions (classified), buildings, auto removals, terrain
-- cut / fill of the proposal, and the terrain under every node of the build vs the node height
-- (relative to the origin): fill = node above terrain, cut = node below terrain.
function engine:detailLine(combo, r, pd, origin, params)
	local ci = field(pd, "collisionInfo")
	local coll = {}
	pcall(function()
		local list = field(ci, "collisionEntities")
		for i = 1, math.min(#list, MAX_IDS) do coll[#coll + 1] = engine.classify(entityOf(list[i])) end
	end)
	local blds = {}
	pcall(function()
		local list = field(ci, "buildingEntities")
		for i = 1, math.min(#list, MAX_IDS) do blds[#blds + 1] = engine.classify(entityOf(list[i])) end
	end)
	local autoRm = 0
	pcall(function() for _ in pairs(field(ci, "autoRemovalEntity2models")) do autoRm = autoRm + 1 end end)
	local cut, fill, nmod = 0, 0, 0
	pcall(function()
		local cf = field(pd, "terrainPreviewHeightModCutFill")
		for i = 1, #cf do
			cut = cut + (tonumber(field(cf[i], "x")) or 0)
			fill = fill + (tonumber(field(cf[i], "y")) or 0)
			nmod = nmod + 1
		end
	end)
	local tMin, tMax, fillMax, cutMax, water, off, nn = nil, nil, nil, nil, 0, 0, 0
	local nodes, nodeErr = geomInfo.nodes(combo.entry, self.modules, params)
	if nodes and origin then
		for _, p in ipairs(nodes) do
			local wx, wy, wz = geomInfo.toWorld(origin, combo.place.rot or 0, p)
			local v = api.type.Vec2f.new(wx, wy)
			local okV, valid = pcall(api.engine.terrain.isValidCoordinate, v)
			if okV and valid == false then
				off = off + 1
			else
				local okH, h = pcall(api.engine.terrain.getHeightAt, v)
				if okH and type(h) == "number" then
					nn = nn + 1
					local rel, d = h - origin[3], wz - h
					tMin, tMax = math.min(tMin or rel, rel), math.max(tMax or rel, rel)
					fillMax, cutMax = math.max(fillMax or d, d), math.max(cutMax or -d, -d)
				end
				local okW, w = pcall(api.engine.terrain.isOnWater, v)
				if okW and w then water = water + 1 end
			end
		end
	end
	local function n2(v) return v and string.format("%.2f", v) or nil end
	local p = combo.place
	return grid.line("D", {
		{ "key", combo.key }, { "rot", p.rot }, { "ctx", p.ctx }, { "dx", p.dx }, { "dy", p.dy }, { "dz", p.dz },
		{ "ox", n2(origin and origin[1]) }, { "oy", n2(origin and origin[2]) }, { "oz", n2(origin and origin[3]) },
		{ "ok", r.ok == true }, { "critical", r.critical }, { "msgs", r.messages or {}, "l" },
		{ "warnings", r.warnings or {}, "l" }, { "infos", r.infos or {}, "l" },
		{ "coll", #coll }, { "collIds", coll, "l" }, { "bld", #blds }, { "bldIds", blds, "l" }, { "autoRm", autoRm },
		{ "hmods", nmod }, { "cut", n2(cut) }, { "fill", n2(fill) }, { "cost", r.cost },
		{ "nodes", nn }, { "offMap", off }, { "water", water },
		{ "terrMin", n2(tMin) }, { "terrMax", n2(tMax) }, { "fillMax", n2(fillMax) }, { "cutMax", n2(cutMax) },
		{ "nodeErr", nodeErr, "q" },
	})
end

--- Search jobs: reason to skip a job (requireRule without a tuning rule), or nil.
function engine:skip(job)
	return geomInfo.needsRule(job.search and job.search.requireRule, self.modules, job.params)
end

--- Search jobs: what the shipped geometry (no dev overrides) builds for the base combo.
function engine:ship(job)
	local g = geomInfo.forEntry(job.entry, self.modules, job.params)
	return { effR = g.effR, effSize = g.effSize }
end

--- Do the dev overrides reach the engine's updateFn? The default main combo with an exact 20 m
-- and 60 m ring must cost differently (street length). Logs INFO or ERROR; returns false only
-- when both are placeable at the same cost (the overrides are dropped: search results would be
-- meaningless).
function engine:devCheck()
	if not self.files.main then return true end
	local base = grid.combo("main", { 1, 2, 5, 3, 1, 1, 1, 1, 1, 1, 1, 1 })
	local function at(r)
		local c = { entry = "main", key = base.key, labels = base.labels, params = grid.withDev(base.params, { radius = r }) }
		local okCall, res = pcall(function() return self:evaluate(c) end)
		return okCall and res or { ok = false, error = tostring(res) }
	end
	local r20, r60 = at(20), at(60)
	local text = string.format("dev override check (default combo, sqrb_dev_radius 20 / 60 m): ok=%s/%s cost=%s/%s",
		tostring(r20.ok), tostring(r60.ok), tostring(r20.cost), tostring(r60.cost))
	if r20.ok and r60.ok then
		if r20.cost ~= nil and r20.cost == r60.cost then
			self:error(text .. ": same cost, so the engine ignores the sqrb_dev_* params; stopping")
			return false
		end
		self:info(text .. ": overrides reach the updateFn")
		return true
	end
	self:error(text .. ": inconclusive (not both placeable); continuing")
	return true
end

return engine
