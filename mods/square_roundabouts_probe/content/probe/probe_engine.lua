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

--- Resource name of an entry's .con as the construction repository knows it, or nil.
function engine:resolveFile(entry)
	if self.files[entry] ~= nil then return self.files[entry] or nil end
	local file = grid.ENTRIES[entry].file
	local candidates = {
		grid.TARGET_MOD .. "::/" .. file,
		grid.TARGET_MOD .. "::" .. file,
		file,
	}
	for _, name in ipairs(candidates) do
		local ok, id = pcall(api.res.constructionRep.find, name)
		if ok and type(id) == "number" and id >= 0 then
			self.files[entry] = name
			self:info("entry " .. entry .. ": construction '" .. name .. "' id " .. tostring(id))
			return name
		end
	end
	self.files[entry] = false
	self:error("entry " .. entry .. ": no construction found (tried " .. table.concat(candidates, ", ") ..
		"); is square_roundabouts enabled for this game?")
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
end

--- World position at terrain height; logs it.
function engine:placement()
	local x, y = self.cfg.x, self.cfg.y
	local z = 0
	local okH, h = pcall(function() return api.engine.terrain.getHeightAt(api.type.Vec2f.new(x, y)) end)
	if okH and type(h) == "number" then z = h else self:error("getHeightAt failed: " .. tostring(h)) end
	local okW, water = pcall(function() return api.engine.terrain.isOnWater(api.type.Vec2f.new(x, y)) end)
	local okV, valid = pcall(function() return api.engine.terrain.isValidCoordinate(api.type.Vec2f.new(x, y)) end)
	if okW and water then self:error("probe position is on water; results will be about water, not geometry") end
	if okV and valid == false then self:error("probe position is outside the map") end
	self.x, self.y, self.z = x, y, z
	self.transf = api.type.Mat4f.new(
		api.type.Vec4f.new(1, 0, 0, 0),
		api.type.Vec4f.new(0, 1, 0, 0),
		api.type.Vec4f.new(0, 0, 1, 0),
		api.type.Vec4f.new(x, y, z, 1)
	)
	return x, y, z
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
	local ok, ctx = pcall(function()
		local c = api.type.Context.new()
		c.player = self.player
		c.checkTerrainAlignment = true
		c.cleanupStreetGraph = true
		c.gatherBuildings = true
		c.gatherFields = true
		return c
	end)
	if ok then return ctx end
	self:error("Context.new failed, using none: " .. tostring(ctx))
	return nil
end

--- One-time setup on the GUI thread. Returns false if there is nothing to probe.
function engine:setup()
	self:loadGeometry()
	self:loadPlayer()
	self:loadGlobals()
	self:placement()
	self.ctx = self:makeContext()
	local any = false
	for _, entry in ipairs(grid.ENTRY_ORDER) do
		if self:resolveFile(entry) ~= nil then any = true end
	end
	return any
end

--- Header fields for the START line.
function engine:header()
	return {
		{ "x", self.x }, { "y", self.y }, { "z", self.z },
		{ "context", self.cfg.context }, { "player", self.player },
		{ "main", self.files.main or "-" }, { "magic", self.files.magic or "-" },
		{ "channel", self.files.channel or "-" }, { "interchange", self.files.interchange or "-" },
		{ "geometry", self.modules.geom and "yes" or "no" },
	}
end

--- Construction params for a combo: global params, EXTRA_PARAMS, then the combo's sqrb_* values.
function engine:paramsFor(combo)
	local p = {}
	for k, v in pairs(self.globals or {}) do p[k] = v end
	for k, v in pairs(config.EXTRA_PARAMS) do p[k] = v end
	for k, v in pairs(combo.params) do p[k] = v end
	-- base helpers always give constructions a seed (mission_framework_util_entity.tl:99-102)
	if p.seed == nil then p.seed = 1 end
	return p
end

function engine:proposalFor(fileName, params)
	local sp = api.type.SimpleProposal.new()
	local ce = api.type.SimpleProposal.ConstructionEntity.new()
	ce.fileName = fileName
	ce.params = params
	ce.transf = self.transf
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
	local fileName = self.files[combo.entry]
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
		local ctx = self.ctx
		local okCall, pd = pcall(function()
			local sp = self:proposalFor(fileName, params)
			if ctx ~= nil then return api.engine.util.proposal.makeProposalData(sp, ctx) end
			return api.engine.util.proposal.makeProposalData(sp)
		end)
		if okCall and pd ~= nil then
			self.proposalSuccesses = self.proposalSuccesses + 1
			self.proposalFails = 0
			readProposalData(pd, r)
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
