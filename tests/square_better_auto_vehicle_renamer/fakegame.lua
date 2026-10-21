-- Fake game for the Better Auto Vehicle Renamer sweep tests: vehicles, models, lines, a reader as bavr_sweep.lua
-- wants it, a state store that copies on get / set (the worst case of state:get()), and an update loop that
-- applies the queued renames the way the engine would (a later tick). Updates use Sweep.stepLazy, so every test runs
-- the per-state fast path and the lazy register read the game script uses; g.gets counts the reads, g.calls the
-- reader calls (read = one vehicle's component reads; lines / lineVehicles = the line watch). g.noLineWatch = true
-- hides reader.lines / lineVehicles (the fallback: line names re-read once per cycle); g.listFail / g.linesFail make
-- reader.list / reader.lines fail (nil).

local Sweep = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_sweep.lua"
local Reg = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_register.lua"
local Settings = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_settings.lua"
-- The render tests were written for the first layout (Model + number, automatic separators, no year): pin
-- those three settings unless a test sets them; the defaults test reads Settings.parse directly.
local function P(t, ...)
	local m = { ["bavr.format"] = 1, ["bavr.partSep"] = 1, ["bavr.year"] = 1 }
	for k, v in pairs(t or {}) do m[k] = v end
	return Settings.parse(m, ...)
end


local G = {}

local function copy(t)
	if type(t) ~= "table" then return t end
	local r = {}
	for k, v in pairs(t) do r[k] = copy(v) end
	return r
end
G.copy = copy

-- carriers
G.ROAD, G.RAIL, G.TRAM, G.AIR, G.WATER = 0, 1, 2, 3, 4

function G.new(opts)
	opts = opts or {}
	local g = {
		now = opts.now or 100000,
		vehicles = {},   -- id -> { carrier, line, model, pt, name, depot, year, exp, parts, wagons }
		order = {},      -- ids in list order
		models = {
			[1] = { name = "Mercedes-Benz Citaro", key = "vehicle/bus/citaro.mdl", pax = true },
			[2] = { name = "Scania R", key = "vehicle/truck/scania_r.mdl", pax = false },
			[3] = { name = "Class 101", key = "vehicle/train/class101.mdl" },
			[4] = { name = "Sternwheeler", key = "vehicle/ship/sternwheeler.mdl" },
			[5] = { name = "AW101", key = "vehicle/helicopter/aw101.mdl", heli = true },
			[6] = { name = "DC-3", key = "vehicle/plane/dc3.mdl" },
			[7] = { name = "Tatra T3", key = "vehicle/tram/t3.mdl", pax = true },
			[8] = { name = "Solaris Urbino", key = "vehicle/bus/urbino.mdl", pax = true },
		},
		lines = { [900] = "Bus 12", [901] = "Harbor Express" },
		calls = { read = 0, modelInfo = 0, lineName = 0, list = 0, exists = 0, lines = 0, lineVehicles = 0 },
		saved = nil,     -- the stored state (a copy)
		sets = 0,
		gets = 0,        -- register reads (state:get())
		sent = {},       -- every rename sent: { id, name }
		params = opts.params or {},
		share = opts.share,
		nextId = 1000,
	}
	g.cfg = P(g.params)
	g.rt = Sweep.newRuntime()
	local reader = {}
	function reader.list()
		g.calls.list = g.calls.list + 1
		if g.listFail then return nil end -- (the real reader's failed read)
		local out = {}
		for i, id in ipairs(g.order) do out[i] = id end
		return out
	end
	function reader.read(id, buf)
		g.calls.read = g.calls.read + 1
		local v = g.vehicles[id]
		if v == nil then return false end
		buf.carrier, buf.depot, buf.line, buf.model = v.carrier, v.depot, v.line, v.model
		buf.pt, buf.name, buf.year = v.pt, v.name, v.year
		-- reader.wantParts: the expiry (game ms past the lifespan), the part count and the unpowered parts
		buf.exp, buf.parts, buf.wagons = v.exp, v.parts, v.wagons
		return true
	end
	function reader.modelInfo(m)
		g.calls.modelInfo = g.calls.modelInfo + 1
		return g.models[m]
	end
	function reader.lineName(li)
		g.calls.lineName = g.calls.lineName + 1
		return g.lines[li]
	end
	function reader.lines()
		g.calls.lines = g.calls.lines + 1
		if g.linesFail then return nil end
		local out = {}
		for li in pairs(g.lines) do out[#out + 1] = li end
		table.sort(out)
		return out
	end
	function reader.lineVehicles(li)
		g.calls.lineVehicles = g.calls.lineVehicles + 1
		local out = {}
		for _, id in ipairs(g.order) do
			local v = g.vehicles[id]
			if v ~= nil and v.line == li then out[#out + 1] = id end
		end
		return out
	end
	function reader.exists(id)
		g.calls.exists = g.calls.exists + 1
		return g.vehicles[id] ~= nil and not g.vehicles[id].vanish
	end
	g.reader = setmetatable({}, { __index = function(_, k)
		if g.noLineWatch and (k == "lines" or k == "lineVehicles") then return nil end
		return reader[k]
	end, __newindex = reader })
	return setmetatable(g, { __index = G })
end

local DEFAULT_WORD = { [0] = "Road Vehicle", [1] = "Train", [2] = "Tram", [3] = "Aircraft", [4] = "Ship" }

--- Buy a vehicle (default name), returns its id. fields: carrier, model, line, pt, name, id, year, exp, parts, wagons.
function G:buy(f)
	f = f or {}
	local id = f.id or self.nextId
	self.nextId = math.max(self.nextId, id) + 1
	local carrier = f.carrier or G.ROAD
	self.vehicles[id] = { carrier = carrier, model = f.model or 1, line = f.line, pt = f.pt or self.now,
		name = f.name or (DEFAULT_WORD[carrier] .. " " .. id), year = f.year, exp = f.exp, parts = f.parts,
		wagons = f.wagons }
	self.order[#self.order + 1] = id
	return id
end

function G:sell(id)
	self.vehicles[id] = nil
	for i, v in ipairs(self.order) do
		if v == id then
			table.remove(self.order, i)
			break
		end
	end
end

function G:name(id) return self.vehicles[id] and self.vehicles[id].name end

--- One game-script update: fresh state (copy), a step, the renames applied (unless hold), state stored when dirty.
function G:update(dtMs, hold)
	self.now = self.now + (dtMs or 200)
	-- share: one state table kept across updates (state:get() returning the same table), else a copy per update
	-- the register is read lazily (Sweep.stepLazy): fetch counts the reads (state:get() in game)
	local function fetch()
		self.gets = self.gets + 1
		if self.share then
			self.live = self.live or Reg.validate(copy(self.saved))
			return self.live
		end
		return Reg.validate(copy(self.saved))
	end
	local t0 = os.clock()
	local phase, st = Sweep.stepLazy(self.rt, self.cfg, self.reader, self.now, fetch)
	self.stepS = os.clock() - t0
	assert(st ~= nil or not self.rt.dirty, "dirty without a state read")
	for i = 1, self.rt.nops do
		local id, name = self.rt.ops[2 * i - 1], self.rt.ops[2 * i]
		self.sent[#self.sent + 1] = { id, name }
		if not hold and self.vehicles[id] then self.vehicles[id].name = name end
	end
	if self.rt.dirty then
		self.saved = self.share and st or copy(st)
		self.sets = self.sets + 1
	end
	return phase, st
end

--- Run updates until n complete cycles ("end" phases) passed, at most maxUpdates.
function G:cycles(n, maxUpdates, dtMs)
	local ends = 0
	for _ = 1, maxUpdates or 10000 do
		local phase = self:update(dtMs)
		if phase == "end" then
			ends = ends + 1
			if ends >= n then return true end
		end
	end
	return false
end

function G:answer(a)
	local st = Reg.validate(copy(self.saved))
	Reg.answer(st, a, self.now)
	self.saved = copy(st)
end

function G:state() return Reg.validate(copy(self.saved)) end

function G:rec(id) return Reg.get(self:state(), id) end

function G:setParams(p)
	self.params = p
	self.cfg = P(p)
end

--- A reload: fresh runtime caches; the saved state stays, but the rename lease is dropped (the game script's first
--- init of a new load does that, bavr_game.lua: no Lua state of the last load lives on).
function G:reload()
	self.rt = Sweep.newRuntime()
	if self.saved ~= nil then self.saved.lo, self.saved.le, self.saved.lq = nil, nil, nil end
end

return G
