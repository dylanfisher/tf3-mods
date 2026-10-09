-- Bulk Bulldozer batch planning (PLAN "Architecture": bb_batch.tl). PURE: no api.* calls, so
-- the split policy and the orphan-node rule are unit-tested offline
-- (tests/square_bulk_bulldozer/test_batch.lua).
--
-- Split policy (PLAN "Commit and errors"): send the whole stroke as one command; when a command
-- fails, halve it and retry both halves (front of the queue, order kept), recursively down to
-- single items. A failing single is skipped. At most MAX_COMMANDS commands per stroke; whatever
-- is still queued then is skipped as "limit".

local batch : BulkBulldozerBatch = {}

batch.MAX_COMMANDS = 48

local function copy(items : {integer}, i0 : integer, i1 : integer) : {integer}
	local out : {integer} = {}
	for i = i0, i1 do out[#out + 1] = items[i] end
	return out
end

function batch.split(items : {integer}) : {integer}, {integer}
	local mid = #items // 2
	return copy(items, 1, mid), copy(items, mid + 1, #items)
end

function batch.newPlan(items : {integer}, cap? : integer) : BulkBulldozerBatchPlan
	local p : BulkBulldozerBatchPlan = {
		queue = {},
		cap = cap or batch.MAX_COMMANDS,
		sent = 0,
		done = {},
		failed = {},
		capSkipped = {},
	}
	if items ~= nil and #items > 0 then p.queue[1] = copy(items, 1, #items) end
	return p
end

function batch.nextBatch(p : BulkBulldozerBatchPlan) : {integer}
	if #p.queue == 0 then return nil end
	if p.sent >= p.cap then
		for _, b in ipairs(p.queue) do
			for _, e in ipairs(b) do p.capSkipped[#p.capSkipped + 1] = e end
		end
		p.queue = {}
		return nil
	end
	return table.remove(p.queue, 1)
end

function batch.report(p : BulkBulldozerBatchPlan, items : {integer}, success : boolean)
	p.sent = p.sent + 1
	if items == nil or #items == 0 then return end
	if success then
		for _, e in ipairs(items) do p.done[#p.done + 1] = e end
	elseif #items == 1 then
		p.failed[#p.failed + 1] = items[1]
	else
		local a, b = batch.split(items)
		table.insert(p.queue, 1, b)
		table.insert(p.queue, 1, a)
	end
end

function batch.orphanNodes(edgeEnds : {{integer}}, degree : {integer : integer},
		frozen : {integer : boolean}) : {integer}
	local removed : {integer : integer} = {}
	for _, ends in ipairs(edgeEnds or {}) do
		for k = 1, 2 do
			local n = ends[k]
			if n ~= nil and n >= 0 then removed[n] = (removed[n] or 0) + 1 end
		end
	end
	local out : {integer} = {}
	for n, cnt in pairs(removed) do
		local d = degree ~= nil and degree[n] or nil
		local isFrozen = frozen ~= nil and frozen[n] == true
		if d ~= nil and cnt >= d and not isFrozen then out[#out + 1] = n end
	end
	table.sort(out)
	return out
end

return batch
