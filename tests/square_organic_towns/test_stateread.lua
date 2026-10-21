-- The saved state off the frame path (2026-10-20, PLAN §75 "Follow-ups built"): ot_saved's change number (`rev`,
-- bumpRev / revOf) and Reader, and the game script's guiUpdate / handleEvent with them (fake engine, stubbed driver).
-- The twin-driver check (same events and logs as a full copy every frame) is in test_driver.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local SV = ug_require(F.DIR .. "ot_saved.lua")
local PV = ug_require(F.DIR .. "ot_prov.lua")

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local o = {}
	for k, x in pairs(v) do o[k] = deepCopy(x) end
	return o
end

local function ser(v)
	if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. ser(v[k]) end
	return "{" .. table.concat(parts, ",") .. "}"
end

--- A saved state with every key the header lists (normalized, as the game stores it).
local function fullState()
	local pv = PV.append(nil, 7, { PV.entry({ id = 345, src = "plain/ln", trig = "demand", year = 1932, p0 = { 100, 0 },
		p1 = { 200, 0 } }) })
	local raw = { v = SV.VERSION, known = { 1, 2, 3 }, fresh = true, nm = 1, nd = "en",
		rv = { { n = "Avon", x = 10, y = 20, k = "r" } },
		sq = { { st = 5, g = 6, n = "Stop", x = 1, y = 2, t = 3, k = "street" } },
		frames = { ["7"] = { a = 0.5, x = 10, y = 20, s = 1, st = 2, ic = 300, f = 1, lm = 2, e0 = 40, gk = 1, dv = 2,
			fy = 190012, sk = "900:120:400" } },
		cm = { p = { { t = 7, k = 1 } } }, sp = { m = 10, y = 190000, n = 1, y0 = 190000, h = { 3 } },
		lb = { ["7"] = "-" }, lbs = 1, sb = { { b = "Main", x = 1, y = 2, h = 3 } },
		dk = { { t = 9, p = 7, x = 5, y = 6 } }, wm = { { t = 11, p = 7, x = 7, y = 8 } }, wk = { 11 },
		rc = { ["7"] = { e = { 100, 200, 300 }, s = 1000, y = 190000, n0 = 500, k = 2 } },
		gx = { ["7"] = { 41, 42 } }, no = { ["7"] = "a,b,c" }, ui = { ["7"] = "1:5:-" }, pv = pv, rev = 12 }
	return SV.normalize(raw)
end

--- A fake engine side: the master state, get() copies it (state:get()), the native number may lag the copy.
local function fakeState(master)
	local S = { master = master, t = 0, gets = 0, revs = 0, lag = 0, hist = {} }
	function S.get()
		S.gets = S.gets + 1
		return deepCopy(S.master)
	end
	function S.rev()
		S.revs = S.revs + 1
		return S.hist[#S.hist - S.lag] or SV.revOf(S.master)
	end
	function S.now() return S.t end
	function S.set(s)   -- handleEvent: apply, bump, set
		S.master = SV.bumpRev(s)
	end
	function S.frame() S.hist[#S.hist + 1] = SV.revOf(S.master) end
	return S
end

test("rev: revOf / bumpRev, kept by normalize (also a foreign layout), wraps, an old save without one", function()
	eq(SV.revOf(nil), nil)
	eq(SV.revOf({}), nil, "a save from before: none")
	eq(SV.revOf({ rev = 0 }), nil)
	eq(SV.revOf({ rev = 2.5 }), nil)
	eq(SV.revOf({ rev = 0 / 0 }), nil)
	eq(SV.revOf({ rev = "7" }), 7)
	eq(SV.bumpRev({}).rev, 1, "the first change writes 1")
	eq(SV.bumpRev({ rev = 41 }).rev, 42)
	eq(SV.bumpRev({ rev = SV.REV_WRAP }).rev, 1)
	eq(SV.normalize({ v = SV.VERSION, rev = 9 }).rev, 9)
	eq(SV.normalize({ v = 99, rev = 9 }).rev, 9, "a foreign layout keeps the number: never repeated")
	eq(SV.normalize(nil).rev, nil)
	local s, changed = SV.applyUi({ v = SV.VERSION, rev = 5 }, { towns = { { t = 7, v = "1:5:-" } } })
	ok(changed)
	eq(s.rev, 5, "an apply keeps it; handleEvent bumps")
	-- every key survives normalize with the number (the fixture below is complete)
	local st = fullState()
	for _, k in ipairs({ "known", "fresh", "nm", "nd", "rv", "sq", "frames", "cm", "sp", "lb", "lbs", "sb", "dk", "wm",
		"wk", "rc", "gx", "no", "ui", "pv", "rev" }) do
		ok(st[k] ~= nil, "fixture key " .. k)
	end
end)

test("reader: the same data as a full copy every frame (every key), one copy per change and per refresh", function()
	local S = fakeState(fullState())
	local R = SV.newReader()
	eq(R.mode, "rev")
	local fulls = 0
	local step = 1e6 / 110
	for f = 1, 2000 do
		if f % 300 == 0 then   -- an event: the card summary and a provenance entry
			local s = SV.applyUi(S.master, { towns = { { t = 7, v = tostring(f % 4) .. ":5:-" } } })
			s = SV.applyProv(s, { town = 7, add = { PV.entry({ id = 1000 + f, src = "lead", trig = "demand",
				year = 1933, p0 = { f, 0 }, p1 = { f + 50, 0 } }) } })
			S.set(s)
		end
		S.frame()
		local saved, full = R:read(S.get, S.rev, S.now)
		if full then fulls = fulls + 1 end
		eq(ser(saved), ser(S.master), "frame " .. f)
		S.t = S.t + step
	end
	eq(R.mode, "rev")
	-- 6 changes, a refresh every 2 s (~18 s; a change restarts it): 9-17 copies, not 2000
	ok(fulls >= 9 and fulls <= 17, "full copies " .. fulls)
	eq(S.gets, fulls)
end)

test("reader: the native number lagging or leading the copy: copies until both agree; the driver's own sends at once", function()
	for _, lag in ipairs({ 2, 5 }) do
		-- the number lags the copy (a change the driver did not send: a player's Road Stop): seen `lag` frames later
		-- at most, then the data is the old path's
		local S = fakeState(fullState())
		S.lag = lag
		local R = SV.newReader()
		local late = 0
		for f = 1, 50 do
			if f == 20 then S.set(SV.applyUi(S.master, { towns = { { t = 7, v = "2:9:-" } } })) end
			S.frame()
			local saved = R:read(S.get, S.rev, S.now)
			if ser(saved) ~= ser(S.master) then late = late + 1 end
			S.t = S.t + 9000
		end
		eq(late, lag, "lag " .. lag)
		eq(R.miss, 0, "the copies always agreed with the number read with them")
		-- the same change after the driver sent its event (Reader:expect): copied every frame until it shows, so
		-- it reaches the driver the frame it reaches state:get()
		local S2 = fakeState(fullState())
		S2.lag = lag
		local R2 = SV.newReader()
		for f = 1, 50 do
			if f == 18 then R2:expect(S2.t) end
			if f == 20 then S2.set(SV.applyUi(S2.master, { towns = { { t = 7, v = "2:9:-" } } })) end
			S2.frame()
			local saved = R2:read(S2.get, S2.rev, S2.now)
			eq(ser(saved), ser(S2.master), "expected change, lag " .. lag .. " frame " .. f)
			S2.t = S2.t + 9000
		end
		eq(R2.watchUntil, nil, "the watch ended when the copy moved")
		ok(R2.miss >= 1, "the lag shows in revMiss")
	end
	-- a watch with no change (an idempotent event): full copies for READ_WATCH_S, then cached again
	local S = fakeState(fullState())
	local R = SV.newReader()
	R:read(S.get, S.rev, S.now)
	R:expect(S.t)
	local g0 = S.gets
	for _ = 1, 400 do
		S.t = S.t + 9000
		R:read(S.get, S.rev, S.now)
	end
	local watched = math.ceil(SV.READ_WATCH_S * 1e6 / 9000)
	ok(S.gets - g0 >= watched - 1 and S.gets - g0 <= watched + 3, "copies " .. (S.gets - g0) .. " ~ " .. watched)
	-- the copy lags the number (get() still the old state for 3 frames): read again every frame until it caught up
	local old, oldFor = nil, 0
	local S3 = fakeState(fullState())
	local R3 = SV.newReader()
	local get = function()
		S3.gets = S3.gets + 1
		if oldFor > 0 then oldFor = oldFor - 1 return deepCopy(old) end
		return deepCopy(S3.master)
	end
	R3:read(get, S3.rev, S3.now)
	old = deepCopy(S3.master)
	S3.set(SV.applyUi(S3.master, { towns = { { t = 7, v = "3:9:-" } } }))
	oldFor = 3
	for _ = 1, 6 do
		S3.t = S3.t + 9000
		R3:read(get, S3.rev, S3.now)
	end
	eq(S3.gets, 1 + 4, "three stale copies, then the new one, then cached")
	eq(ser(R3.cache), ser(S3.master))
	eq(R3.miss, 3)
end)

test("reader: an old save (no number) caches; the first change re-reads; a nil state and a failing copy give nil", function()
	local S = fakeState({ v = SV.VERSION, frames = {} })
	local R = SV.newReader()
	for _ = 1, 10 do
		R:read(S.get, S.rev, S.now)
		S.t = S.t + 9000
	end
	eq(S.gets, 1, "no number on either side: the copy stands")
	S.set(SV.applyUi(S.master, { towns = { { t = 7, v = "1:1:-" } } }))
	local saved = R:read(S.get, S.rev, S.now)
	eq(S.gets, 2)
	eq(saved.rev, 1)
	eq(saved.ui["7"], "1:1:-")
	-- no state at all (before init): nil, cached, as state:get() gave
	local S2 = fakeState(nil)
	local R2 = SV.newReader()
	eq(R2:read(S2.get, S2.rev, S2.now), nil)
	eq(R2:read(S2.get, S2.rev, S2.now), nil)
	eq(S2.gets, 1)
	-- a failing copy: nil (as the old pcall), tried again next frame
	local R3 = SV.newReader()
	local n = 0
	local bad = function() n = n + 1 error("copy failed") end
	eq(R3:read(bad, S.rev, S.now), nil)
	eq(R3:read(bad, S.rev, S.now), nil)
	eq(n, 2)
	eq(R3.mode, "rev")
	eq(R3:read(S.get, S.rev, S.now).rev, 1)
end)

test("reader: any error of the number read falls back to a full copy every frame for the session (reason once)", function()
	local S = fakeState(fullState())
	for _, badRev in ipairs({
		function() error("no game script entity") end,
		function() return "12" end,
		function() return {} end }) do
		local R = SV.newReader()
		local saved, full, why = R:read(S.get, badRev, S.now)
		eq(ser(saved), ser(S.master), "the data still comes")
		ok(full)
		ok(type(why) == "string" and why:find("rev read", 1, true), tostring(why))
		eq(R.mode, "get")
		local gets = S.gets
		for _ = 1, 5 do
			local s2, f2, w2 = R:read(S.get, function() error("never called again") end, S.now)
			eq(ser(s2), ser(S.master))
			ok(f2)
			eq(w2, nil, "the reason only once")
		end
		eq(S.gets, gets + 5, "a full copy every frame, as before")
	end
	-- READ_REV off or mode "get": the old path from the start, the number never read
	local R = SV.newReader({ mode = "get" })
	local revN = S.revs
	R:read(S.get, S.rev, S.now)
	eq(S.revs, revN)
	SV.READ_REV = false
	eq(SV.newReader().mode, "get")
	SV.READ_REV = true
end)

test("reader: the cost check falls back when the number read costs half a copy or copies run most frames", function()
	-- cheap number (2 us), dear copy (150 us), a change every 50 frames: stays (the number read every frame plus the
	-- copies must cost less than a copy every frame)
	local function run(revUs, getUs, changeEvery, frames)
		local S = fakeState(fullState())
		local R = SV.newReader()
		local whys = {}
		local rev = function() S.t = S.t + revUs return S.rev() end
		local get = function() S.t = S.t + getUs return S.get() end
		for f = 1, frames do
			if changeEvery and f % changeEvery == 0 then
				S.set(SV.applyUi(S.master, { towns = { { t = 7, v = tostring(f % 4) .. ":2:-" } } }))
			end
			S.frame()
			local saved, _, why = R:read(get, rev, S.now)
			eq(ser(saved), ser(S.master))
			if why then whys[#whys + 1] = why end
			S.t = S.t + 9000
		end
		return R, whys
	end
	local R1, w1 = run(2, 150, 50, SV.READ_CHECK_N * 2)
	eq(R1.mode, "rev")
	eq(#w1, 0)
	-- the number read as dear as a copy (getComponent copying the whole state, say): back to the old path
	local R2, w2 = run(150, 150, 50, SV.READ_CHECK_N + 5)
	eq(R2.mode, "get")
	eq(#w2, 1)
	ok(w2[1]:find("rev read 150 us + ", 1, true) and w2[1]:find("vs copy 150 us", 1, true), w2[1])
	-- dearer but still cheaper than a copy every frame: stays
	local R2b = run(100, 150, 50, SV.READ_CHECK_N + 5)
	eq(R2b.mode, "rev")
	-- a change every frame: copies on most frames on top of the number reads
	local R3, w3 = run(2, 150, 1, SV.READ_CHECK_N + 5)
	eq(R3.mode, "get")
	ok(w3[1]:find("copies in", 1, true), w3[1])
	-- NaN / negative clock steps don't break the means
	local S = fakeState(fullState())
	local R4 = SV.newReader()
	local clock = { 0 / 0, -5, 10 }
	local i = 0
	for _ = 1, 9 do R4:read(S.get, S.rev, function() i = i + 1 return clock[i % 3 + 1] end) end
	eq(R4.mode, "rev")
end)

---------------------------------------------------------------------------
-- the game script itself (fake api, a stub driver)

local function loadGs(o)
	o = o or {}
	reset_modules()
	local calls = { ticks = {}, notes = {} }
	local fakeDriver = {}
	function fakeDriver.tick(_, now, saved) calls.ticks[#calls.ticks + 1] = saved end
	function fakeDriver.costStage() return "idle" end
	function fakeDriver.costNote(_, now, us, getUs, at, full, mode)
		calls.notes[#calls.notes + 1] = { full = full, mode = mode, getUs = getUs }
	end
	local clock = 0
	stub_module("square_organic_towns::/organic_towns/ot_engine.lua", { nowUs = function() clock = clock + 10 return clock end })
	stub_module("square_organic_towns::/organic_towns/ot_driver.lua", { new = function(E)
		fakeDriver.E = E
		return fakeDriver
	end })
	stub_module("square_organic_towns::/organic_towns/ot_hooks.lua", {})
	local native = o.native
	set_global("api", {
		engine = {
			system = { gameScriptSystem = { getEntityForGameScript = function(name)
				calls.gsName = name
				return o.entity or 77
			end } },
			getComponent = function(e, ct)
				if o.componentError then error("getComponent asserted") end
				return { state_native = { find = function(_, k) return native and native(k) end } }
			end },
		type = { ComponentType = { GAME_SCRIPT = 99 } } })
	ug_require("square_organic_towns::/organic_towns/ot_gs.script.lua")
	return data(), calls
end

local function fakeGsState(master)
	local st = { master = master, gets = 0, sets = 0 }
	function st:get() self.gets = self.gets + 1 return deepCopy(self.master) end
	function st:set(s) self.sets = self.sets + 1 self.master = deepCopy(s) end
	return st
end

test("game script: handleEvent bumps the number with every set, not on an unchanged apply", function()
	local gs = loadGs()
	local st = fakeGsState({ v = SV.VERSION, frames = {} })
	gs.handleEvent(nil, st, "", SV.EVENT_ID, SV.EV_UI, { towns = { { t = 7, v = "1:1:-" } } })
	eq(st.sets, 1)
	eq(st.master.rev, 1)
	gs.handleEvent(nil, st, "", SV.EVENT_ID, SV.EV_UI, { towns = { { t = 7, v = "1:1:-" } } })
	eq(st.sets, 1, "idempotent: no set, no bump")
	eq(st.master.rev, 1)
	gs.handleEvent(nil, st, "", SV.EVENT_ID, SV.EV_PROV, { town = 7, add = { PV.entry({ id = 5, src = "lead",
		trig = "demand", year = 1930, p0 = { 0, 0 }, p1 = { 50, 0 } }) } })
	eq(st.master.rev, 2)
	ok(st.master.pv ~= nil)
end)

test("game script: guiUpdate passes the cached copy while the number stands, falls back on a read error", function()
	local st = fakeGsState(fullState())
	local gs, calls = loadGs({ native = function(k) if k == SV.REV_KEY then return SV.revOf(st.master) end end })
	for _ = 1, 5 do gs.guiUpdate(nil, st, nil) end
	eq(st.gets, 1, "one copy for five frames")
	eq(#calls.ticks, 5)
	for i = 1, 5 do eq(ser(calls.ticks[i]), ser(st.master)) end
	eq(calls.notes[1].full, true)
	eq(calls.notes[2].full, false)
	eq(calls.notes[2].mode, "rev")
	eq(calls.gsName, SV.GS_NAME)
	gs.handleEvent(nil, st, "", SV.EVENT_ID, SV.EV_UI, { towns = { { t = 7, v = "3:3:-" } } })
	local g0 = st.gets
	gs.guiUpdate(nil, st, nil)
	eq(st.gets, g0 + 1)
	eq(calls.ticks[6].ui["7"], "3:3:-")
	-- an engine read that errors: one STATEREAD warning, a full copy every frame from then on
	local st2 = fakeGsState(fullState())
	clear_logs()
	local gs2, calls2 = loadGs({ componentError = true })
	for _ = 1, 4 do gs2.guiUpdate(nil, st2, nil) end
	eq(st2.gets, 4)
	eq(#calls2.ticks, 4)
	eq(ser(calls2.ticks[4]), ser(st2.master))
	local warns = 0
	for _, e in ipairs(log_entries()) do
		local text = type(e) == "table" and (e.msg or e.message or e[2] or "") or tostring(e)
		if tostring(text):find("STATEREAD mode=get", 1, true) then warns = warns + 1 end
	end
	eq(warns, 1)
	eq(calls2.notes[4].mode, "get")
	-- no game-script entity (a negative id): the same
	local st3 = fakeGsState(fullState())
	local gs3 = loadGs({ entity = -1 })
	for _ = 1, 3 do gs3.guiUpdate(nil, st3, nil) end
	eq(st3.gets, 3)
end)
