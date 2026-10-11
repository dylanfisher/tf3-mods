-- DEV ONLY (never upload): Roundabouts Showcase, everything that talks to the game. GUI thread only
-- (showcase.script.lua guiUpdate). Every engine call is wrapped in pcall.
--
-- API evidence (copied from square_roundabouts_probe's probe_engine.lua where it applies):
--   * api.res.constructionRep.find(resName) : id (-1 if missing)        api/res.d.tl:26-29
--     .get(id) : ConstructionDesc {params : {ScriptParam}, updateScript : ScriptRef {fileName, params}}
--     api/type.d.tl:1667-1707, ScriptParam 2948-2978, ScriptRef 1375-1390; read like base
--     gui/construction/construction.tl:1240 and construction_react_util.tl:930-968.
--   * The construction's own updateFn, resolved like base util.useFn (scripts/util.tl:5-28:
--     loaderHelper:useFn(ref), then the `game` table path), called as fn(captureParams, params)
--     (docs/findings.md "Script function signatures"); result.edgeLists[].edges = {pos, tangent}
--     pairs (docs/wiki/modding/constructions/basics.md "Edge Lists").
--   * getGlobalConstructionParams()                                   api/engine/util.d.tl:815-817
--   * SimpleProposal + ConstructionEntity{fileName, params, transf, name, playerEntity}
--     api/type.d.tl:2827-2860; base mission_framework_util_entity.tl:98-113
--   * makeProposalData(SimpleProposal, Context) : ProposalData {errorState, collisionInfo, costs}
--     api/engine/util.d.tl:925, api/type.d.tl:2693-2760 (SimpleProposal: probe PROBE.md)
--   * api.cmd.makeWorldBuildProposalCmd(proposal, context, ignoreErrors, playerInitiated, doDust)
--     api/cmd.d.tl:953-962; api.cmd.sendCommand(cmd, callback(data, success)) 598-600. From the GUI
--     state the command runs in the next simulation step and the callback a frame later
--     (cmd.d.tl:1-10); sent from guiUpdate as square_roundabouts_lanes_probe / square_smart_lanes
--     (docs/findings.md "Junction lane connections"). Never from build events. ignoreErrors = false.
--   * api.gui.camera.getCameraData() : Vec5f {x, y, distance, ...}     api/gui.d.tl:434
--   * api.engine.terrain.getHeightAt / isOnWater / isValidCoordinate(Vec2f)
--   * api.res.streetTemplateRep.find / get(id).laneConfigs[].width (street widths for the footprints;
--     read like square_roundabouts_probe's engine.describeTemplate)

local config = ug_require "square_roundabouts_showcase::/showcase/sc_config.lua"
local combos = ug_require "square_roundabouts_showcase::/showcase/sc_combos.lua"
local footprint = ug_require "square_roundabouts_showcase::/showcase/sc_footprint.lua"
local layout = ug_require "square_roundabouts_showcase::/showcase/sc_layout.lua"
local runnerMod = ug_require "square_roundabouts_showcase::/showcase/sc_runner.lua"
local shapeMod = ug_require "square_roundabouts_showcase::/showcase/sc_shape.lua"

local engine = {}
engine.__index = engine

local function field(obj, key)
	if obj == nil then return nil end
	local ok, v = pcall(function() return obj[key] end)
	if ok then return v end
	return nil
end

--- A native list (Lua table or vector userdata) as a plain Lua list.
local function toList(v)
	local out = {}
	if v == nil then return out end
	local ok = pcall(function() for _, x in ipairs(v) do out[#out + 1] = x end end)
	if not ok or #out == 0 then
		out = {}
		pcall(function() for i = 1, #v do out[#out + 1] = v[i] end end)
	end
	return out
end
engine.toList = toList

local function count(v)
	if v == nil then return 0 end
	local ok, n = pcall(function() return #v end)
	return ok and n or 0
end

function engine.new(cfg, log)
	local self = setmetatable({}, engine)
	self.cfg = cfg
	self.out = log
	self.fns = {}
	return self
end

function engine:log(kind, fields) self.out(runnerMod.line(kind, fields)) end

-- Setup ---------------------------------------------------------------------------------------------

--- Resource name of an entry's .con as the construction repository knows it, and its id, or nil.
function engine:resolve(e)
	local candidates = {
		config.TARGET_MOD .. "::/" .. e.file,
		config.TARGET_MOD .. "::" .. e.file,
		e.file,
	}
	for _, name in ipairs(candidates) do
		local ok, id = pcall(api.res.constructionRep.find, name)
		if ok and type(id) == "number" and id >= 0 then return name, id end
	end
	self:log("ERROR", { { "entry", e.id }, { "msg", "construction not found; is square_roundabouts enabled?" },
		{ "tried", candidates } })
	return nil
end

--- The entry model from the construction rep (generic: whatever params the .con defines).
function engine:readEntry(e, resName, id)
	local okD, desc = pcall(api.res.constructionRep.get, id)
	if not okD or desc == nil then
		self:log("ERROR", { { "entry", e.id }, { "msg", "constructionRep.get failed" }, { "err", desc } })
		return nil
	end
	local plain, ignored = {}, {}
	for _, p in ipairs(toList(field(desc, "params"))) do
		local vals = {}
		for i, v in ipairs(toList(field(p, "values"))) do vals[i] = tostring(v) end
		local key = field(p, "key")
		if type(key) == "string" and key:find(config.PARAM_KEY_PATTERN) then
			plain[#plain + 1] = { key = key, name = field(p, "name"), values = vals, defaultIndex = field(p, "defaultIndex") }
		else
			ignored[#ignored + 1] = tostring(key)
		end
	end
	if #ignored > 0 then self:log("INFO", { { "entry", e.id }, { "msg", "params left at their defaults" }, { "keys", ignored } }) end
	local us = field(desc, "updateScript")
	local captureParams = field(us, "params")
	-- a plain copy of the closure params (e.g. the highway entries' types list)
	local cp = nil
	if captureParams ~= nil then
		cp = {}
		pcall(function()
			for k, v in pairs(captureParams) do
				if type(v) == "table" or type(v) == "userdata" then cp[k] = toList(v) else cp[k] = v end
			end
		end)
	end
	local desc2 = field(desc, "description")
	local model = {
		id = e.id, symbol = e.symbol, file = resName,
		name = tostring(field(desc2, "name") or e.id),
		script = field(us, "fileName"),
		captureParams = cp,
		params = combos.paramsFromList(plain),
	}
	local parts = {}
	for _, p in ipairs(model.params) do parts[#parts + 1] = p.key .. "(" .. p.n .. ",d" .. p.default .. ")" end
	self:log("ENTRY", { { "entry", e.id }, { "id", id }, { "file", resName }, { "script", model.script },
		{ "params", #model.params }, { "keys", parts }, { "combinations", combos.countOf(model) } })
	if #model.params == 0 then
		self:log("WARN", { { "entry", e.id }, { "msg", "no params read from the rep; only the defaults will be built" } })
	end
	return model
end

function engine:loadGlobals()
	local globals = {}
	local ok, g = pcall(api.engine.util.construction.getGlobalConstructionParams)
	if ok and g ~= nil then
		pcall(function() for k, v in pairs(g) do globals[k] = v end end)
	else
		self:log("ERROR", { { "msg", "getGlobalConstructionParams failed" }, { "err", g } })
	end
	self.globals = globals
end

function engine:loadPlayer()
	local ok, p = pcall(api.engine.util.getPlayer)
	self.player = ok and p or -1
end

function engine:makeContext()
	local ok, ctx = pcall(function()
		local c = api.type.Context.new()
		c.player = self.player
		for k, v in pairs(config.CONTEXT_FLAGS) do c[k] = v end
		return c
	end)
	if ok then return ctx end
	self:log("ERROR", { { "msg", "Context.new failed; using none" }, { "err", ctx } })
	return nil
end

--- The layout centre: the camera's look-at point or the X / Y settings.
function engine:centre()
	local x, y = self.cfg.x, self.cfg.y
	if self.cfg.pos == "camera" then
		local ok, d = pcall(api.gui.camera.getCameraData)
		if ok and d ~= nil and layout.finite(d.x) and layout.finite(d.y) then
			x, y = d.x, d.y
		else
			self:log("ERROR", { { "msg", "camera position unavailable; using the X / Y settings" } })
		end
	end
	return x, y
end

--- Resolves the selected entries. Returns the entry models (possibly empty).
function engine:setup()
	self:loadPlayer()
	self:loadGlobals()
	self.ctx = self:makeContext()
	local models = {}
	for _, id in ipairs(self.cfg.entries) do
		local e = config.entryById(id)
		if e then
			local name, rid = self:resolve(e)
			if name then
				local m = self:readEntry(e, name, rid)
				if m then models[#models + 1] = m end
			end
		end
	end
	return models
end

-- Footprints ----------------------------------------------------------------------------------------

--- The updateFn of a script reference, resolved like base util.useFn; cached (false = unavailable).
function engine:updateFn(ref)
	if type(ref) ~= "string" or ref == "" then return nil end
	if self.fns[ref] ~= nil then return self.fns[ref] or nil end
	local ok, fn = pcall(function()
		loaderHelper:useFn(ref)
		local a, b = ref:match("^(.-)@(.+)$")
		local t = game[a]
		for part in b:gmatch("[^.]+") do t = t[part] end
		return t
	end)
	if ok and type(fn) == "function" then
		self.fns[ref] = fn
		self:log("INFO", { { "msg", "footprints from the construction's own updateFn" }, { "ref", ref } })
		return fn
	end
	self.fns[ref] = false
	self:log("WARN", { { "msg", "updateFn not resolvable; footprints from the geometry module" }, { "ref", ref }, { "err", fn } })
	return nil
end

--- Construction params of a combo: the global params, then the combo's values, a seed.
function engine:paramsFor(combo, seed)
	local p = {}
	for k, v in pairs(self.globals or {}) do p[k] = v end
	for k, v in pairs(combo.params) do p[k] = v end
	p.seed = seed or 1
	return p
end

--- Full width (m) of a street template: the sum of its laneConfigs widths (sidewalks included),
-- read from api.res.streetTemplateRep (api/res.d.tl:147, StreetTemplate.laneConfigs api/type.d.tl);
-- nil if unknown. Cached, one INFO line per template.
function engine:streetWidth(template)
	self.widths = self.widths or {}
	if self.widths[template] ~= nil then return self.widths[template] or nil end
	local ok, w = pcall(function()
		local id = api.res.streetTemplateRep.find(template)
		if type(id) ~= "number" or id < 0 then return nil end
		local tpl = api.res.streetTemplateRep.get(id)
		local sum = 0
		for _, lc in ipairs(toList(field(tpl, "laneConfigs"))) do sum = sum + (tonumber(field(lc, "width")) or 0) end
		return sum > 0 and sum or nil
	end)
	local width = ok and w or nil
	self.widths[template] = width or false
	self:log("INFO", { { "template", template }, { "width", width or ("unknown, using " .. footprint.DEFAULT_WIDTH) } })
	return width
end

--- Footprint of a combo (the runner's deps.measure). Returns fp, warning-or-nil.
function engine:measure(combo)
	local params = self:paramsFor(combo)
	local fn = self:updateFn(combo.entry.script)
	local opts = { widthOf = function(t) return self:streetWidth(t) end }
	local err
	if fn then
		local ok, res = pcall(fn, combo.entry.captureParams or {}, params)
		if ok and type(res) == "table" then
			local fp, e2 = footprint.fromResult(res, opts)
			if fp then return fp, nil end
			err = "updateFn result: " .. tostring(e2)
		else
			err = "updateFn failed: " .. tostring(res)
		end
	end
	local fp, e3 = footprint.measure(combo, ug_require, opts, config.FALLBACK_SIZE)
	if fp.source == "geometry" then
		if err then return fp, err end
		return fp, nil
	end
	return fp, (err and (err .. "; ") or "") .. tostring(e3)
end

-- Placement -----------------------------------------------------------------------------------------

local function vec2(x, y) return api.type.Vec2f.new(x, y) end

--- World corners of a placement's box (and its centre).
function engine.corners(p)
	local c, s = layout.cosSin(p.rot)
	local out = { { p.x, p.y } }
	for _, k in ipairs({ { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } }) do
		local lx, ly = k[1] * p.fp.w / 2, k[2] * p.fp.h / 2
		out[#out + 1] = { p.x + c * lx - s * ly, p.y + s * lx + c * ly }
	end
	return out
end

--- The 16 transf numbers of a placement (origin, rotation, terrain z), every zero +0; nil + reason
-- if anything is not finite.
function engine.transfNumbers(p, z)
	local c, s = layout.cosSin(p.rot)
	local t = { c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, p.ox, p.oy, z, 1 }
	for i, v in ipairs(t) do
		if not layout.finite(v) then return nil, "transf[" .. i .. "] not finite" end
		t[i] = layout.plusZero(v)
	end
	return t
end

function engine:transf(p)
	local z = 0
	local okH, h = pcall(function() return api.engine.terrain.getHeightAt(vec2(p.ox, p.oy)) end)
	if okH and layout.finite(h) then z = h end
	local t, err = engine.transfNumbers(p, z)
	if not t then return nil, err end
	local V = api.type.Vec4f.new
	return api.type.Mat4f.new(V(t[1], t[2], t[3], t[4]), V(t[5], t[6], t[7], t[8]), V(t[9], t[10], t[11], t[12]),
		V(t[13], t[14], t[15], t[16]))
end

function engine:proposal(p, transf, n)
	local combo = p.mirrored and p.item.mirror and p.item.mirror.combo or p.item.combo
	local sp = api.type.SimpleProposal.new()
	local ce = api.type.SimpleProposal.ConstructionEntity.new()
	ce.fileName = combo.entry.file
	ce.params = self:paramsFor(combo, n)
	ce.transf = transf
	ce.name = ""
	ce.playerEntity = self.player
	sp.constructionsToAdd = { ce }
	return sp
end

--- The runner's deps.check: skip (off map / water), or the engine's verdict on the proposal.
function engine:check(p)
	for _, q in ipairs(engine.corners(p)) do
		local okV, valid = pcall(api.engine.terrain.isValidCoordinate, vec2(q[1], q[2]))
		if okV and valid == false then return { skip = "off map" } end
		local okW, water = pcall(api.engine.terrain.isOnWater, vec2(q[1], q[2]))
		if okW and water then return { skip = "water" } end
	end
	local transf, terr = self:transf(p)
	if not transf then return { skip = terr } end
	self.seq = (self.seq or 0) + 1
	local okP, pd = pcall(function()
		local sp = self:proposal(p, transf, self.seq)
		if self.ctx ~= nil then return api.engine.util.proposal.makeProposalData(sp, self.ctx) end
		return api.engine.util.proposal.makeProposalData(sp)
	end)
	if not okP or pd == nil then
		return { ok = false, reasons = { "makeProposalData failed: " .. tostring(pd) } }
	end
	local es = field(pd, "errorState")
	local reasons = {}
	for _, m in ipairs(toList(field(es, "messages"))) do reasons[#reasons + 1] = tostring(m) end
	if es == nil then reasons[#reasons + 1] = "no errorState" end
	if field(es, "critical") == true then reasons[#reasons + 1] = "critical" end
	local ci = field(pd, "collisionInfo")
	local nColl = count(field(ci, "collisionEntities"))
	local nBld = count(field(ci, "buildingEntities"))
	if nColl > 0 then reasons[#reasons + 1] = "collision with " .. nColl .. " existing entities" end
	if nBld > 0 then reasons[#reasons + 1] = "would remove " .. nBld .. " buildings" end
	if #reasons > 0 then
		local res = { ok = false, reasons = reasons }
		if nColl > 0 then
			local okH, hits = pcall(function() return self:collisionHits(p, field(ci, "collisionEntities")) end)
			if okH then res.hits = hits end
		end
		return res
	end
	p.transf, p.seq = transf, self.seq
	return { ok = true, cost = field(pd, "costs") }
end

-- Collision feedback ---------------------------------------------------------------------------

--- A short type text of an existing entity (never raises): con(<file>) / edge / node / other.
function engine.kindOf(id)
	local CT = api.type.ComponentType
	local okC, con = pcall(function() return api.engine.getComponent(id, CT.CONSTRUCTION) end)
	if okC and con ~= nil then
		local fn = field(con, "fileName")
		return "con(" .. tostring(fn and tostring(fn):match("([^/]+)%.con$") or fn) .. ")"
	end
	local okE, edge = pcall(function() return api.engine.getComponent(id, CT.BASE_EDGE) end)
	if okE and edge ~= nil then return "edge" end
	local okN, node = pcall(function() return api.engine.getComponent(id, CT.BASE_NODE) end)
	if okN and node ~= nil then return "node" end
	return "other"
end

--- Describes the entities a refused placement collides with: the placement that built each one
-- (from the build callbacks' result entities) with the model's clearance to it (sc_shape: buffered
-- roads, so a positive value means the model thought there was room), or the entity's type.
-- Returns { {text, owner, model, kind, z} }.
function engine:collisionHits(p, list)
	local hits = {}
	local seen = {}
	for _, e in ipairs(toList(list)) do
		local id = type(e) == "number" and e or field(e, "entity")
		local owner = id and self.owner and self.owner[id]
		if owner and not seen[owner] then
			seen[owner] = true
			local model, kind, z
			if p.fp.shape and owner.fp.shape then
				model, kind, z = shapeMod.clearance(p, owner, 60, layout.cosSin)
			end
			hits[#hits + 1] = { owner = owner, model = model, kind = kind, z = z,
				text = tostring(id) .. ":" .. runnerMod.comboOf(owner).key .. (model and string.format("@%.1fm", model) or "") }
		elseif not owner and #hits < 8 then
			hits[#hits + 1] = { text = tostring(id) .. ":" .. engine.kindOf(id) }
		end
	end
	return hits
end

--- The runner's deps.send: a fresh proposal of the checked placement, sent as a build command. The
-- result entities of a successful build are remembered (owner map, for the collision feedback).
function engine:send(p, done)
	local sp = self:proposal(p, p.transf, p.seq)
	local cmd = api.cmd.makeWorldBuildProposalCmd(sp, self.ctx, false, true, false)
	api.cmd.sendCommand(cmd, function(data, success, resultEntities)
		local msgs = {}
		pcall(function()
			for _, m in ipairs(toList(data.resultProposalData.errorState.messages)) do msgs[#msgs + 1] = tostring(m) end
		end)
		if success then
			self.owner = self.owner or {}
			pcall(function()
				local list = resultEntities
				if list == nil then list = data.resultEntities end
				for _, pair in ipairs(toList(list)) do
					local id = type(pair) == "number" and pair or (type(pair) == "table" and pair[1]) or field(pair, "entity")
					if type(id) == "number" then self.owner[id] = p end
				end
			end)
		end
		done(success == true, msgs)
	end)
	p.transf = nil
end

return engine
