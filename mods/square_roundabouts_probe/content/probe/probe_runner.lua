-- DEV ONLY (never upload): Roundabouts placement probe, batch runner.
-- Pure Lua: everything that touches the game comes in through `deps`, so the runner is
-- unit-tested offline with fakes. The probe script calls runner:step(batch) once per GUI update,
-- so the work is spread over many frames and the game keeps drawing.
--
-- deps = {
--   evaluate = function(combo) : result   (grid.resultLine documents the result fields; may raise)
--   log = function(line)
--   now = function() : seconds            (wall clock, for rate/ETA; may be coarse, e.g. os.time)
--   clock = function() : seconds | nil     (optional, for per-combo ms)
--   collect = function()                  (optional, called between progress lines)
--   skip = function(job) : reason | nil    (optional, search jobs: skip the job, e.g. no tuning rule)
--   ship = function(job) : {effR, effSize} (optional, search jobs: the shipped geometry's choice)
-- }
--
-- Search jobs (grid.expand of a search block: job.search.cands) take one engine call per
-- candidate, spread over steps like plain combos: a T line per candidate, then an S line. With
-- job.search.first the job stops at the first accepted candidate (early exit).

local grid = ug_require "square_roundabouts_probe::/probe/probe_grid.lua"

local runner = {}
runner.__index = runner

--- opts = { combos, deps, header = {{key, value, mode?}}, progressEvery = 250, logOk = true, subset = "name" }
function runner.new(opts)
	local self = setmetatable({}, runner)
	self.combos = opts.combos or {}
	self.deps = opts.deps
	self.header = opts.header or {}
	self.progressEvery = opts.progressEvery or 250
	self.logOk = opts.logOk ~= false
	self.subset = opts.subset or "?"
	self.pos = 0
	self.calls = 0
	self.cur = nil -- the search job in progress: {cursor, accepted, acceptedLabels, rejected, best}
	self.jobs = { found = 0, none = 0, skipped = 0 }
	self.counts = { ok = 0, fail = 0, error = 0 }
	self.byMessage = {} -- first message (or error) -> count
	self.started = false
	self.finished = false
	self.steps = 0
	return self
end

function runner:total() return #self.combos end

function runner:start()
	self.started = true
	self.t0 = self.deps.now()
	local fields = { { "subset", self.subset }, { "total", #self.combos }, { "maxCalls", grid.maxCalls(self.combos) } }
	for _, f in ipairs(self.header) do fields[#fields + 1] = f end
	self.deps.log(grid.line("START", fields))
end

local function firstReason(r)
	if r.error then return "error: " .. tostring(r.error) end
	if r.messages and #r.messages > 0 then return tostring(r.messages[1]) end
	if r.critical then return "(critical, no message)" end
	return "(not ok, no message)"
end

--- Top reasons as "reason:count|reason:count" (most frequent first, at most n).
function runner:topReasons(n)
	local list = {}
	for reason, count in pairs(self.byMessage) do list[#list + 1] = { reason, count } end
	table.sort(list, function(a, b)
		if a[2] ~= b[2] then return a[2] > b[2] end
		return a[1] < b[1]
	end)
	local out = {}
	for i = 1, math.min(n or 5, #list) do out[i] = list[i][1] .. ":" .. list[i][2] end
	return out
end

function runner:evaluateOne(combo)
	local clock = self.deps.clock
	local c0 = clock and clock() or nil
	local okCall, r = pcall(self.deps.evaluate, combo)
	if not okCall then r = { ok = false, error = tostring(r) } end
	if type(r) ~= "table" then r = { ok = false, error = "evaluate returned " .. type(r) } end
	if c0 and r.ms == nil then
		local c1 = clock()
		if c1 then r.ms = math.floor((c1 - c0) * 1000 + 0.5) end
	end
	return r
end

function runner:progress()
	local elapsed = self.deps.now() - self.t0
	local rate = elapsed > 0 and self.pos / elapsed or nil
	local eta = rate and rate > 0 and (#self.combos - self.pos) / rate or nil
	self.deps.log(grid.line("PROGRESS", {
		{ "done", self.pos }, { "total", #self.combos },
		{ "ok", self.counts.ok }, { "fail", self.counts.fail }, { "errors", self.counts.error },
		{ "seconds", elapsed }, { "perSecond", rate }, { "eta", eta and math.floor(eta + 0.5) or nil },
		{ "steps", self.steps }, { "calls", self.calls },
		{ "found", self.jobs.found }, { "none", self.jobs.none }, { "skipped", self.jobs.skipped },
	}))
	if self.deps.collect then pcall(self.deps.collect) end
end

function runner:finish()
	self.finished = true
	local elapsed = self.deps.now() - self.t0
	self.deps.log(grid.line("END", {
		{ "subset", self.subset }, { "done", self.pos }, { "total", #self.combos },
		{ "ok", self.counts.ok }, { "fail", self.counts.fail }, { "errors", self.counts.error },
		{ "seconds", elapsed }, { "steps", self.steps }, { "calls", self.calls },
		{ "found", self.jobs.found }, { "none", self.jobs.none }, { "skipped", self.jobs.skipped },
		{ "top", self:topReasons(8), "l" },
	}))
end

--- Counts one engine verdict (plain combo or search candidate).
function runner:count(r)
	self.calls = self.calls + 1
	if r.error then
		self.counts.error = self.counts.error + 1
	elseif r.ok then
		self.counts.ok = self.counts.ok + 1
	else
		self.counts.fail = self.counts.fail + 1
	end
	if not r.ok then
		local reason = firstReason(r)
		self.byMessage[reason] = (self.byMessage[reason] or 0) + 1
	end
	if self.calls % self.progressEvery == 0 and self.pos < #self.combos then self:progress() end
end

--- Ends the current search job: S line, job counts.
function runner:endJob(job, skipped)
	local cur = self.cur or {}
	local ship
	if self.deps.ship then
		local okShip, v = pcall(self.deps.ship, job)
		if okShip then ship = v end
	end
	self.deps.log(grid.searchLine(self.pos, #self.combos, job, {
		tried = cur.cursor and (cur.cursor - 1) or 0,
		accepted = cur.accepted or 0,
		best = cur.best,
		acceptedLabels = cur.acceptedLabels,
		rejected = cur.rejected,
		skipped = skipped,
		ship = ship,
	}))
	if skipped then
		self.jobs.skipped = self.jobs.skipped + 1
	elseif cur.best then
		self.jobs.found = self.jobs.found + 1
	else
		self.jobs.none = self.jobs.none + 1
	end
	self.cur = nil
end

--- One engine call of the search job at self.pos + 1. Returns true when the job is done.
function runner:searchCall(job)
	local n = self.pos + 1
	if not self.cur then
		self.cur = { cursor = 1, accepted = 0, acceptedLabels = {}, rejected = {} }
		if self.deps.skip then
			local okSkip, reason = pcall(self.deps.skip, job)
			if not okSkip then reason = "skip check failed: " .. tostring(reason) end
			if reason then
				self.pos = n
				self:endJob(job, reason)
				return true
			end
		end
	end
	local cur = self.cur
	local cands = job.search.cands
	if cur.cursor > #cands then
		self.pos = n
		self:endJob(job)
		return true
	end
	local c = cands[cur.cursor]
	local trial = {
		entry = job.entry,
		indices = job.indices,
		labels = job.labels,
		key = job.key,
		dev = c.dev,
		params = grid.withDev(job.params, c.dev),
	}
	local r = self:evaluateOne(trial)
	self.deps.log(grid.trialLine(n, #self.combos, job, cur.cursor, r))
	self:count(r)
	if r.ok then
		cur.accepted = cur.accepted + 1
		cur.acceptedLabels[#cur.acceptedLabels + 1] = c.label
		cur.best = cur.best or cur.cursor
	else
		cur.rejected[#cur.rejected + 1] = c.label
	end
	cur.cursor = cur.cursor + 1
	if (r.ok and job.search.first) or cur.cursor > #cands then
		self.pos = n
		self:endJob(job)
		return true
	end
	return false
end

--- Runs up to `batch` combos. Returns true once the run is finished (END logged).
function runner:step(batch)
	if self.finished then return true end
	if not self.started then self:start() end
	self.steps = self.steps + 1
	local total = #self.combos
	-- `batch` engine calls per step (a skipped search job costs none, but counts as one so a long
	-- run of skips still yields to the game)
	for _ = 1, math.max(1, batch or 1) do
		if self.pos >= total then break end
		local combo = self.combos[self.pos + 1]
		if combo.search then
			self:searchCall(combo)
		else
			self.pos = self.pos + 1
			local r = self:evaluateOne(combo)
			if self.logOk or not r.ok then
				self.deps.log(grid.resultLine(self.pos, total, combo, r))
			end
			self:count(r)
		end
	end
	if self.pos >= total then
		self:finish()
		return true
	end
	return false
end

return runner
