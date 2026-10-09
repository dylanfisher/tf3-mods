-- bb_batch: split-on-failure planner (halve, recurse to singles, cap 48) and orphan nodes
-- (PLAN Phase 3).

local batch = ug_require "square_bulk_bulldozer::/bulk_bulldozer/bb_batch.tl"

local function range(n)
	local t = {}
	for i = 1, n do t[i] = i end
	return t
end

-- Drives a plan like bb_commit does: a batch fails when it contains any bad item.
local function run(items, bad, cap)
	local p = batch.newPlan(items, cap)
	local cmds = 0
	while true do
		local b = batch.nextBatch(p)
		if b == nil then break end
		local good = true
		for _, e in ipairs(b) do if bad[e] then good = false end end
		batch.report(p, b, good)
		cmds = cmds + 1
		assert(cmds < 1000, "runaway plan")
	end
	return p, cmds
end

local function sorted(t)
	local c = {}
	for i, v in ipairs(t) do c[i] = v end
	table.sort(c)
	return c
end

test("constants: cap 48", function()
	eq(batch.MAX_COMMANDS, 48)
	eq(batch.newPlan({ 1 }).cap, 48)
end)

test("split: halves keep order, odd sizes", function()
	local a, b = batch.split({ 1, 2, 3, 4, 5 })
	eq(a, { 1, 2 })
	eq(b, { 3, 4, 5 })
	a, b = batch.split({ 7 })
	eq(a, {})
	eq(b, { 7 })
end)

test("empty plan sends nothing", function()
	local p, cmds = run({}, {})
	eq(cmds, 0)
	eq(#p.done + #p.failed + #p.capSkipped, 0)
end)

test("all good: one command for the whole stroke", function()
	local p, cmds = run(range(50), {})
	eq(cmds, 1)
	eq(p.done, range(50))
	eq(p.failed, {})
	eq(p.sent, 1)
end)

test("all fail: recurses to every single (2n-1 commands)", function()
	local bad = {}
	for i = 1, 8 do bad[i] = true end
	local p, cmds = run(range(8), bad)
	eq(cmds, 15)
	eq(p.done, {})
	eq(sorted(p.failed), range(8))
	eq(p.capSkipped, {})
end)

test("one bad item at each position: everything else removed, few commands", function()
	for n = 1, 12 do
		for pos = 1, n do
			local p, cmds = run(range(n), { [pos] = true })
			eq(p.failed, { pos }, string.format("n=%d pos=%d", n, pos))
			eq(#p.done, n - 1)
			local expect = {}
			for i = 1, n do if i ~= pos then expect[#expect + 1] = i end end
			eq(p.done, expect, "done keeps the stroke order")
			ok(cmds <= 2 * math.ceil(math.log(math.max(n, 2)) / math.log(2)) + 1,
				string.format("n=%d pos=%d took %d commands", n, pos, cmds))
		end
	end
end)

test("cap: never more than 48 commands; the rest is skipped, nothing lost", function()
	local bad = {}
	for i = 1, 100 do bad[i] = true end
	local p, cmds = run(range(100), bad)
	eq(cmds, 48)
	eq(p.sent, 48)
	ok(#p.capSkipped > 0)
	eq(#p.done + #p.failed + #p.capSkipped, 100)
	eq(batch.nextBatch(p), nil, "finished stays finished")
end)

test("cap is per plan: a smaller budget is respected", function()
	local p, cmds = run(range(4), { [1] = true, [4] = true }, 3)
	eq(cmds, 3)
	eq(#p.done + #p.failed + #p.capSkipped, 4)
end)

-- Orphan nodes. Network:  1 —A— 2 —B— 3,  2 —C— 4 (node 2 has degree 3).
local DEG = { [1] = 1, [2] = 3, [3] = 1, [4] = 1 }

test("orphan nodes: dead end removed, shared node kept", function()
	eq(batch.orphanNodes({ { 1, 2 } }, DEG, {}), { 1 })
end)

test("orphan nodes: node whose every edge goes is removed", function()
	eq(batch.orphanNodes({ { 1, 2 }, { 2, 3 }, { 2, 4 } }, DEG, {}), { 1, 2, 3, 4 })
	eq(batch.orphanNodes({ { 1, 2 }, { 2, 3 } }, DEG, {}), { 1, 3 }, "2 keeps edge C")
end)

test("orphan nodes: frozen (construction-owned) never", function()
	eq(batch.orphanNodes({ { 1, 2 }, { 2, 3 } }, DEG, { [1] = true }), { 3 })
	eq(batch.orphanNodes({ { 1, 2 }, { 2, 3 }, { 2, 4 } }, DEG, { [2] = true }), { 1, 3, 4 })
end)

test("orphan nodes: unknown degree and invalid ids are kept", function()
	eq(batch.orphanNodes({ { 1, 9 } }, DEG, {}), { 1 }, "9 has no degree")
	eq(batch.orphanNodes({ { -1, 3 } }, DEG, {}), { 3 })
	eq(batch.orphanNodes({}, DEG, {}), {})
	eq(batch.orphanNodes(nil, nil, nil), {})
end)
