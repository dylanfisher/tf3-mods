-- DEV ONLY (never upload): Roundabouts Showcase, the run's state machine. Pure Lua: everything that
-- touches the game comes in through `deps`, so the runner is unit-tested offline with fakes.
-- showcase.script.lua calls runner:step() once per GUI update.
--
-- deps = {
--   log = function(line)
--   now = function() : seconds
--   measure = function(combo) : fp, err          (sc_footprint.measure with the real modules)
--   check = function(placement) : { ok, skip = reason | nil, reasons = {...} }
--             (off map / water -> skip; makeProposalData errors, collisions, buildings -> not ok)
--   send = function(placement, done)              sends the build; done(success, messages) later
--   clock = function() : seconds | nil            (optional, CPU clock: slices the layout)
-- }
-- Phases: measure -> layout -> plan -> build -> done (dry run: plan -> done).

local config = ug_require "square_roundabouts_showcase::/showcase/sc_config.lua"
local combos = ug_require "square_roundabouts_showcase::/showcase/sc_combos.lua"
local layout = ug_require "square_roundabouts_showcase::/showcase/sc_layout.lua"
local preview = ug_require "square_roundabouts_showcase::/showcase/sc_preview.lua"

local runner = {}
runner.__index = runner

local function clean(s)
	return (tostring(s):gsub("[\r\n]+", " "))
end
runner.clean = clean

local function fmt(v)
	if type(v) == "number" then
		if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
		return string.format("%.2f", v)
	end
	if type(v) == "table" then return table.concat(v, "|") end
	return tostring(v)
end

--- "[SQRB-SHOW] KIND k=v k=v" (values with spaces quoted).
function runner.line(kind, fields)
	local parts = { config.PREFIX, kind }
	for _, f in ipairs(fields or {}) do
		if f[2] ~= nil then
			local v = clean(fmt(f[2]))
			if v:find("[%s=]") then v = '"' .. v:gsub('"', "'") .. '"' end
			parts[#parts + 1] = f[1] .. "=" .. v
		end
	end
	return table.concat(parts, " ")
end

--- opts = { cfg, entries (models), deps, centre = {x, y} }
function runner.new(opts)
	local self = setmetatable({}, runner)
	self.cfg = opts.cfg
	self.entries = opts.entries
	self.deps = opts.deps
	self.cx, self.cy = opts.centre and opts.centre[1] or 0, opts.centre and opts.centre[2] or 0
	self.phase = "enumerate"
	self.counts = { built = 0, failed = 0, refused = 0, skipped = 0, sent = 0, dropped = 0, retried = 0 }
	self.reasons = {}
	self.inFlight = 0
	self.fps = {}
	return self
end

function runner:log(kind, fields) self.deps.log(runner.line(kind, fields)) end

function runner:reason(kind, text)
	local k = kind .. ": " .. clean(text)
	self.reasons[k] = (self.reasons[k] or 0) + 1
end

function runner:topReasons(n)
	local list = {}
	for k, v in pairs(self.reasons) do list[#list + 1] = { k, v } end
	table.sort(list, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
	local out = {}
	for i = 1, math.min(n, #list) do out[i] = list[i][1] .. " x" .. list[i][2] end
	return out
end

function runner:isKaleido() return self.cfg.pattern == "kaleido4" or self.cfg.pattern == "kaleido8" end

function runner:enumerate()
	self.combos = combos.enumerate(self.entries, self.cfg.combos, self.cfg.cap, self.cfg.seed, config.HARD_CAP)
	-- footprints to measure: every combo, plus the mirror images for a kaleidoscope
	self.queue, self.mirrors = {}, {}
	for _, c in ipairs(self.combos) do self.queue[#self.queue + 1] = c end
	if self:isKaleido() then
		for i, c in ipairs(self.combos) do
			local m = combos.mirrorOf(c)
			if m then
				self.mirrors[i] = m
				self.queue[#self.queue + 1] = m
			end
		end
	end
	self.qpos = 0
	self:log("COMBOS", { { "mode", self.cfg.combos }, { "count", #self.combos }, { "cap", self.cfg.cap },
		{ "mirrors", self:isKaleido() and #self.queue - #self.combos or 0 }, { "footprints", #self.queue } })
	self.phase = "measure"
end

function runner:measureSome(n)
	for _ = 1, n do
		if self.qpos >= #self.queue then break end
		self.qpos = self.qpos + 1
		local c = self.queue[self.qpos]
		if not self.fps[c.key] then
			local ok, fp, err = pcall(self.deps.measure, c)
			if not ok then fp, err = nil, fp end
			if not fp then
				self:log("WARN", { { "key", c.key }, { "footprint", "failed" }, { "err", err } })
				self:reason("footprint", err)
			elseif err then
				self:log("WARN", { { "key", c.key }, { "footprint", fp.source }, { "err", err } })
				self:reason("footprint " .. fp.source, err)
			end
			self.fps[c.key] = fp or false
		end
	end
	if self.qpos >= #self.queue then self.phase = "layout" end
end

function runner:buildItems()
	local items = {}
	local entryIndex = {}
	for i, e in ipairs(self.entries) do entryIndex[e.id] = i end
	for i, c in ipairs(self.combos) do
		local fp = self.fps[c.key]
		if fp then
			local e = c.entry
			local ci = combos.colourParam(e)
			local mi = combos.mirrorParam(e)
			local item = {
				combo = c, fp = fp, entry = e.id, entryIndex = entryIndex[e.id], symbol = e.symbol or "?",
				colour = e.id .. ":" .. (ci and e.params[ci].labels[c.values[ci]] or "-"),
				side = mi and c.values[mi] or 1,
			}
			local m = self.mirrors[i]
			if m and self.fps[m.key] then item.mirror = { combo = m, fp = self.fps[m.key] } end
			items[#items + 1] = item
		else
			self.counts.dropped = self.counts.dropped + 1
			self:reason("dropped", "no footprint")
		end
	end
	return items
end

--- Starts the layout: in a coroutine that yields every LAYOUT_SLICE seconds (deps.clock) when the
-- runtime has coroutines and a clock, else in one go.
function runner:startLayout()
	local items = self:buildItems()
	local cfg = self.cfg
	local opts = {
		pattern = cfg.pattern, gap = cfg.gap, rotation = cfg.rotation, seed = cfg.seed,
		cx = self.cx, cy = self.cy, maxRadius = cfg.radius, cap = cfg.cap, fill = cfg.fill,
	}
	self.layoutItems, self.layoutOpts = items, opts
	self.layoutSlices, self.layoutSeconds = 0, 0
	local clock = self.deps.clock
	if type(coroutine) == "table" and clock then
		opts.tick = function()
			if clock() - self.sliceStart > config.LAYOUT_SLICE then coroutine.yield() end
		end
		self.layoutCo = coroutine.create(function() return layout.run(items, opts) end)
	end
end

--- One slice of the layout; finishes it when the coroutine is done (or failed: then in one go).
function runner:stepLayout()
	if not self.layoutItems then self:startLayout() end
	local clock = self.deps.clock
	local t0 = clock and clock() or 0
	self.sliceStart = t0
	self.layoutSlices = self.layoutSlices + 1
	local placements, dropped
	if self.layoutCo then
		local ok, a, b = coroutine.resume(self.layoutCo)
		if not ok then
			self:log("WARN", { { "msg", "layout coroutine failed; laying out in one go" }, { "err", a } })
			self.layoutCo, self.layoutOpts.tick = nil, nil
			placements, dropped = layout.run(self.layoutItems, self.layoutOpts)
		elseif coroutine.status(self.layoutCo) ~= "dead" then
			if clock then self.layoutSeconds = self.layoutSeconds + clock() - t0 end
			return
		else
			placements, dropped = a, b
		end
	else
		placements, dropped = layout.run(self.layoutItems, self.layoutOpts)
	end
	if clock then self.layoutSeconds = self.layoutSeconds + clock() - t0 end
	self:doLayout(self.layoutItems, placements, dropped)
end

function runner:doLayout(items, placements, dropped)
	local cfg = self.cfg
	self.placements = placements
	for _, d in ipairs(dropped) do
		self.counts.dropped = self.counts.dropped + 1
		self:reason("dropped", d.reason)
		-- the cap is only counted (it can be many)
		if d.reason ~= "cap" then
			self:log("DROP", { { "key", d.item.combo.key }, { "reason", d.reason } })
		end
	end
	-- density: footprint area / the layout's bounding box
	local fill, bw, bh = layout.fill(placements)
	self.fill = fill
	local minFp, maxFp = nil, nil
	for _, it in ipairs(items) do
		local a = it.fp.w * it.fp.h
		if not minFp or a < minFp.w * minFp.h then minFp = it.fp end
		if not maxFp or a > maxFp.w * maxFp.h then maxFp = it.fp end
	end
	self:log("LAYOUT", { { "pattern", cfg.pattern }, { "rotation", layout.rotationMode(cfg.pattern, cfg.rotation) },
		{ "items", #items }, { "placed", #placements }, { "dropped", #dropped },
		{ "smallest", minFp and string.format("%.0fx%.0f", minFp.w, minFp.h) or "-" },
		{ "largest", maxFp and string.format("%.0fx%.0f", maxFp.w, maxFp.h) or "-" },
		{ "fill", string.format("%.1f%%", fill * 100) }, { "roadFill", string.format("%.1f%%", layout.roadFill(placements) * 100) },
		{ "extent", string.format("%.0fx%.0f", bw, bh) },
		{ "repeats", cfg.fill and "on" or "off" }, { "layoutSeconds", self.layoutSeconds },
		{ "slices", self.layoutSlices },
		{ "cx", self.cx }, { "cy", self.cy } })
	self.ppos = 0
	self.phase = "plan"
end

function runner.placementFields(n, total, p)
	local c = p.mirrored and p.item.mirror and p.item.mirror.combo or p.item.combo
	return {
		{ "n", n .. "/" .. total }, { "key", c.key }, { "mirror", p.mirrored and "yes" or nil },
		{ "x", p.x }, { "y", p.y }, { "rot", p.rot }, { "ox", p.ox }, { "oy", p.oy },
		{ "w", math.floor(p.fp.w + 0.5) }, { "h", math.floor(p.fp.h + 0.5) }, { "fp", p.fp.source },
		{ "what", combos.describe(c) },
	}
end

function runner:plan()
	local total = #self.placements
	local stop = math.min(total, config.MAX_PLAN_LINES)
	-- a chunk of PLAN lines per update keeps each frame short
	for _ = 1, 50 do
		if self.ppos >= stop then break end
		self.ppos = self.ppos + 1
		self:log("PLAN", runner.placementFields(self.ppos, total, self.placements[self.ppos]))
	end
	if self.ppos < stop then return end
	for _, l in ipairs(preview.render(self.placements, self.cx, self.cy, config.PREVIEW_COLS, config.PREVIEW_ROWS)) do
		self.deps.log(config.PREFIX .. " PREVIEW " .. l)
	end
	if self.cfg.mode ~= "build" then
		self:summary("dry run: nothing built")
		self.phase = "done"
		return
	end
	self.placements = runner.interleave(self.placements, config.BUCKET)
	self.bpos = 0
	self.flying = {}
	self.nextProgress = config.PROGRESS_EVERY
	self.t0 = self.deps.now()
	self:log("BUILD_START", { { "placements", total }, { "maxInFlight", math.max(1, self.cfg.batch or 1) },
		{ "flightMargin", config.FLIGHT_MARGIN } })
	self.phase = "build"
end

--- Moves a refused / skipped placement to the nearest free spot (not in a kaleidoscope: a moved
-- copy would break the symmetry). The refused spot stays blocked. Returns true if it was moved.
--- Collision feedback of a refusal: "id:key@model|..." texts (inFlight marked), and per element kind
-- the count and smallest model clearance (SUMMARY collisionKinds=: tune sc_footprint.KERB_BY_KIND).
function runner:noteHits(hits)
	if not hits or #hits == 0 then return nil end
	local texts = {}
	self.kinds = self.kinds or {}
	for _, h in ipairs(hits) do
		local t = h.text
		if h.owner and self.flying and self.flying[h.owner] then t = t .. "(inFlight)" end
		texts[#texts + 1] = t
		if h.model then
			local k = h.kind or "?"
			local agg = self.kinds[k] or { n = 0, min = math.huge, raised = 0 }
			agg.n = agg.n + 1
			if h.model < agg.min then agg.min = h.model end
			if h.z and math.abs(h.z) > 1 then agg.raised = agg.raised + 1 end
			self.kinds[k] = agg
		end
	end
	return texts
end

function runner:kindsText()
	if not self.kinds then return nil end
	local out = {}
	for k, a in pairs(self.kinds) do out[#out + 1] = string.format("%s:n%d,min%.1fm,raised%d", k, a.n, a.min, a.raised) end
	table.sort(out)
	return out
end

function runner:retry(p, n, why, hitText)
	if self:isKaleido() or (p.retries or 0) >= config.MAX_RETRIES then return false end
	if not self.packer then self.packer = layout.packerOf(self.placements, self.cfg.gap) end
	local okR, q = pcall(layout.relocate, self.packer, p, { cx = self.cx, cy = self.cy, maxRadius = self.cfg.radius })
	if not okR or not q then return false end
	q.retries = (p.retries or 0) + 1
	table.insert(self.placements, n + 1, q)
	self.counts.retried = self.counts.retried + 1
	self:log("RETRY", { { "n", n }, { "key", runner.comboOf(p).key }, { "why", why }, { "hits", hitText }, { "try", q.retries },
		{ "fromX", p.x }, { "fromY", p.y }, { "x", q.x }, { "y", q.y }, { "moved", math.sqrt((q.x - p.x) ^ 2 + (q.y - p.y) ^ 2) } })
	return true
end

function runner.comboOf(p) return p.mirrored and p.item.mirror and p.item.mirror.combo or p.item.combo end

function runner:buildOne(p, n)
	local total = #self.placements
	local fields = runner.placementFields(n, total, p)
	local okC, res = pcall(self.deps.check, p)
	if not okC then res = { ok = false, reasons = { "check failed: " .. clean(res) } } end
	if res.skip then
		if self:retry(p, n, res.skip) then return end
		self.counts.skipped = self.counts.skipped + 1
		self:reason("skipped", res.skip)
		fields[#fields + 1] = { "reason", res.skip }
		self:log("SKIP", fields)
		return
	end
	if not res.ok then
		local why = res.reasons and res.reasons[1] or "refused"
		local hitText = self:noteHits(res.hits)
		if self:retry(p, n, why, hitText) then return end
		self.counts.refused = self.counts.refused + 1
		self:reason("refused", why)
		fields[#fields + 1] = { "reasons", res.reasons or {} }
		fields[#fields + 1] = { "hits", hitText }
		self:log("REFUSED", fields)
		return
	end
	self.inFlight = self.inFlight + 1
	self.counts.sent = self.counts.sent + 1
	self.flying[p] = self.deps.now()
	local key = runner.comboOf(p).key
	local done = false
	local okS, err = pcall(self.deps.send, p, function(success, msgs)
		if done then return end
		done = true
		self.inFlight = self.inFlight - 1
		self.flying[p] = nil
		if success then
			self.counts.built = self.counts.built + 1
			self:log("DONE", { { "n", n .. "/" .. #self.placements }, { "key", key }, { "success", true } })
		else
			self.counts.failed = self.counts.failed + 1
			local why = msgs and msgs[1] or "command failed"
			self:reason("failed", why)
			self:log("FAILED", { { "n", n .. "/" .. #self.placements }, { "key", key }, { "msgs", msgs or {} } })
		end
	end)
	if not okS then
		if not done then
			done = true
			self.inFlight = self.inFlight - 1
			self.flying[p] = nil
		end
		self.counts.failed = self.counts.failed + 1
		self:reason("failed", "send: " .. clean(err))
		fields[#fields + 1] = { "err", err }
		self:log("FAILED", fields)
		return
	end
	self:log("BUILD", fields)
end

--- The queue reordered so consecutive placements are far apart: round-robin over bucket x bucket
-- cells (cells in a fixed order, each cell keeping its pattern order). Pure, deterministic.
function runner.interleave(placements, bucket)
	local cells, keys = {}, {}
	for _, p in ipairs(placements) do
		local k = math.floor(p.x / bucket) .. ":" .. math.floor(p.y / bucket)
		if not cells[k] then cells[k] = {} keys[#keys + 1] = k end
		local c = cells[k]
		c[#c + 1] = p
	end
	table.sort(keys)
	-- spread neighbouring cells apart too: take the cells in a strided order
	local order, n = {}, #keys
	local stride = math.max(1, math.floor(math.sqrt(n) + 0.5))
	for start = 1, stride do
		for k = start, n, stride do order[#order + 1] = keys[k] end
	end
	local out = {}
	local i = 1
	while #out < #placements do
		for _, k in ipairs(order) do
			local p = cells[k][i]
			if p then out[#out + 1] = p end
		end
		i = i + 1
	end
	return out
end

--- Is p (grown by FLIGHT_MARGIN more) touching a build still in flight?
function runner:conflicts(p)
	local g = (self.cfg.gap or 0) + 2 * config.FLIGHT_MARGIN
	for q in pairs(self.flying) do
		if layout.overlaps(p, q, g) then return true end
	end
	return false
end

function runner:rate()
	local s = self.deps.now() - (self.t0 or 0)
	return s, s > 0 and self.counts.built / s or nil
end

--- Up to "Per update" builds in flight; a placement is checked and sent only when no build in flight
-- is within FLIGHT_MARGIN of it (its check then sees every built neighbour). The first such one
-- among the next WINDOW queued placements is taken; at most "Per update" checks per GUI update.
function runner:build()
	local now = self.deps.now()
	for _, t in pairs(self.flying) do
		if now - t > config.CALLBACK_TIMEOUT then
			self:summary("gave up waiting for " .. self.inFlight .. " callbacks")
			self.phase = "done"
			return
		end
	end
	local maxIn = math.max(1, self.cfg.batch or 1)
	local list = self.placements
	local checks = 0
	while self.inFlight < maxIn and checks < maxIn do
		local found
		for j = self.bpos + 1, math.min(#list, self.bpos + config.WINDOW) do
			local p = list[j]
			if not p._done and not self:conflicts(p) then found = j break end
		end
		if not found then break end
		local p = list[found]
		p._done = true
		checks = checks + 1
		self:buildOne(p, found)
		while list[self.bpos + 1] and list[self.bpos + 1]._done do self.bpos = self.bpos + 1 end
	end
	if self.bpos >= self.nextProgress then
		self.nextProgress = self.bpos + config.PROGRESS_EVERY
		local secs, rate = self:rate()
		self:log("PROGRESS", { { "done", self.bpos }, { "total", #list }, { "sent", self.counts.sent },
			{ "built", self.counts.built }, { "refused", self.counts.refused }, { "skipped", self.counts.skipped },
			{ "retried", self.counts.retried }, { "failed", self.counts.failed }, { "inFlight", self.inFlight },
			{ "seconds", secs }, { "buildsPerSecond", rate } })
	end
	if self.bpos >= #list and self.inFlight == 0 then
		self:summary("build finished")
		self.phase = "done"
	end
end

function runner:summary(note)
	self:log("SUMMARY", {
		{ "note", note }, { "combos", self.combos and #self.combos or 0 },
		{ "placements", self.placements and #self.placements or 0 },
		{ "built", self.counts.built }, { "failed", self.counts.failed }, { "refused", self.counts.refused },
		{ "skipped", self.counts.skipped }, { "retried", self.counts.retried }, { "dropped", self.counts.dropped },
		{ "inFlight", self.inFlight }, { "fill", self.fill and string.format("%.1f%%", self.fill * 100) or nil },
		{ "seconds", self.t0 and (self.deps.now() - self.t0) or nil },
		{ "buildsPerSecond", self.t0 and select(2, self:rate()) or nil },
		{ "top", self:topReasons(8) }, { "collisionKinds", self:kindsText() },
	})
end

--- One GUI update's worth of work. Returns true once the run is done.
function runner:step()
	if self.phase == "done" then return true end
	if self.phase == "enumerate" then self:enumerate()
	elseif self.phase == "measure" then self:measureSome(config.MEASURE_PER_UPDATE)
	elseif self.phase == "layout" then self:stepLayout()
	elseif self.phase == "plan" then self:plan()
	elseif self.phase == "build" then self:build()
	end
	return self.phase == "done"
end

return runner
