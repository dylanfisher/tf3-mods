-- SQPERF probe helpers, shared by probe_hud.script.tl and probe_gui.script.tl (plain Lua, pre-5.3).
-- probe(ctx): logs "try" BEFORE touching api.type.Clock and "ok" after, at most 3 times per context
-- and Lua state, so after a hard crash the last [SQPERF-PROBE] "try" line names the context. The
-- thread column of stdout.txt shows which thread ran it.

local U = {}
local MOD = "square_sqperf_probe"
local PREFIX = "[SQPERF-PROBE] "
local MAX_PER_CTX = 3

function U.log(msg)
	if log ~= nil and log.message ~= nil then log.message(PREFIX .. msg) else print(PREFIX .. msg) end
end

--- probe_stage: 1 = HUD icon + onStep, 2 = HUD icon only, 3 = onStep only, 4 = Off (1-based index).
function U.stage()
	local ok, v = pcall(function()
		local all = api.engine.config.getModParams()
		local mine = all ~= nil and all[MOD] or nil
		return mine ~= nil and mine.probe_stage or nil
	end)
	if ok and type(v) == "number" then return v end
	return 1
end

function U.hudOn(stage) return stage == 1 or stage == 2 end
function U.stepOn(stage) return stage == 1 or stage == 3 end

local seen = {}

--- shared: a Clock created elsewhere (GUI render) read here too; inst: an SQPERF instrument to run
--- one start/stop with (timed, so it reads its module's Clock in this context).
function U.probe(ctx, shared, inst)
	local n = (seen[ctx] or 0) + 1
	seen[ctx] = n
	if n > MAX_PER_CTX then return end
	U.log("ctx=" .. ctx .. " try n=" .. n)
	local ok, msg = pcall(function()
		local c = api.type.Clock.new()
		local t1 = c:getTime()
		local t2 = c:getTime()
		local parts = { "new+read us=" .. tostring(t1) .. "," .. tostring(t2) }
		if shared ~= nil then parts[#parts + 1] = "shared_us=" .. tostring(shared:getTime()) end
		if inst ~= nil then
			local t0 = inst:start()
			parts[#parts + 1] = "sqperf_ms=" .. string.format("%.4f", inst:stop("probe_" .. ctx, t0))
		end
		local okMem, kb = pcall(collectgarbage, "count")
		if okMem then parts[#parts + 1] = "mem_kb=" .. string.format("%d", math.floor(kb)) end
		return table.concat(parts, " ")
	end)
	if ok then
		U.log("ctx=" .. ctx .. " ok n=" .. n .. " " .. msg)
	else
		U.log("ctx=" .. ctx .. " error n=" .. n .. " " .. tostring(msg))
	end
end

--- Timer and SQPERF overhead on the GUI thread (render), measured with the Clock itself.
function U.bench(clock, sqperf)
	local ok, msg = pcall(function()
		local N = 20000
		local t0 = clock:getTime()
		for _ = 1, N do clock:getTime() end
		local getTimeUs = (clock:getTime() - t0) / N
		t0 = clock:getTime()
		for _ = 1, N do os.clock() end
		local osClockUs = (clock:getTime() - t0) / N
		local function work(x) return x end
		t0 = clock:getTime()
		for i = 1, N do work(i) end
		local plainUs = (clock:getTime() - t0) / N
		local inst = sqperf.new({ mod = MOD, ctx = "gui", enabled = false })
		local wrapped = inst:wrap("bench", work)
		t0 = clock:getTime()
		for i = 1, N do wrapped(i) end
		local wrapUs = (clock:getTime() - t0) / N
		t0 = clock:getTime()
		for _ = 1, N do inst:hit("bench_hit") end
		local hitUs = (clock:getTime() - t0) / N
		return string.format("getTime_us=%.3f os_clock_us=%.3f sqperf_wrap_overhead_us=%.3f sqperf_hit_us=%.3f n=%d",
			getTimeUs, osClockUs, wrapUs - plainUs, hitUs, N)
	end)
	U.log("ctx=render bench " .. (ok and msg or ("error " .. tostring(msg))))
end

return U
