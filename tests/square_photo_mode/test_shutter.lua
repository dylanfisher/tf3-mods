-- pm_shutter.lua (Photo Mode, pure): the screenshot shutter's primer and cooldown, driven by a fake clock and a
-- fake take(scale).

local SH

before_each(function()
	reset_modules()
	SH = ug_require "square_photo_mode::/photo_mode/pm_shutter.lua"
end)

local function fakeTake(fail)
	local t = { calls = {} }
	t.fn = function(scale)
		t.calls[#t.calls + 1] = scale
		if t.fail then return false, "boom" end
		return true
	end
	t.fail = fail
	return t
end

test("the first press sends a scale-1 primer; the real shot follows PRIMER_MS later from tick", function()
	local st, take = SH.new(), fakeTake()
	eq(SH.press(st, 4, 0, take.fn), "primer")
	eq(#take.calls, 1); eq(take.calls[1], 1)
	ok(SH.busy(st), "busy while the shot waits")
	eq(SH.tick(st, SH.PRIMER_MS - 1, take.fn), nil)
	eq(#take.calls, 1, "no shot before PRIMER_MS")
	eq(SH.tick(st, SH.PRIMER_MS, take.fn), "shot")
	eq(#take.calls, 2); eq(take.calls[2], 4, "the scale asked for")
	ok(SH.PRIMER_MS >= 500 and SH.PRIMER_MS <= 2000, "a short moment")
end)

test("the primer goes once: later 1x presses shoot at once, 2x / 4x after the announcement", function()
	local st, take = SH.new(), fakeTake()
	SH.press(st, 1, 0, take.fn)
	SH.tick(st, 1000, take.fn)
	local now = 1000
	for __ = 1, 50 do -- run out the cooldown
		now = now + 100
		if SH.tick(st, now, take.fn) == "ready" then break end
	end
	ok(not SH.busy(st))
	for __, scale in ipairs({ 2, 1, 4 }) do
		local before = #take.calls
		if scale == 1 then
			eq(SH.press(st, scale, now, take.fn), "shot")
		else
			-- round 11: the freeze is announced first, the shot follows ANNOUNCE_MS later from tick
			eq(SH.press(st, scale, now, take.fn), "announce")
			eq(#take.calls, before, "nothing sent with the announcement")
			ok(SH.busy(st), "busy while announced")
			eq(SH.tick(st, now + SH.ANNOUNCE_MS - 1, take.fn), nil)
			now = now + SH.ANNOUNCE_MS
			eq(SH.tick(st, now, take.fn), "shot")
		end
		eq(#take.calls, before + 1, "one call, no primer")
		eq(take.calls[#take.calls], scale)
		for __ = 1, 500 do
			now = now + 100
			if SH.tick(st, now, take.fn) == "ready" then break end
		end
	end
end)

test("cooldown: presses are ignored while a shot is saved; longer for bigger shots; counted after a stall", function()
	ok(SH.COOLDOWN_MS[1] < SH.COOLDOWN_MS[2] and SH.COOLDOWN_MS[2] < SH.COOLDOWN_MS[4])
	ok(SH.COOLDOWN_MS[4] >= 10000, "a 4x shot stalls ~9 s while it encodes")
	for __, scale in ipairs(SH.SCALES) do
		local st, take = SH.new(), fakeTake()
		st.primed = true
		if scale == 1 then
			eq(SH.press(st, scale, 0, take.fn), "shot")
		else
			eq(SH.press(st, scale, -SH.ANNOUNCE_MS, take.fn), "announce")
			eq(SH.tick(st, 0, take.fn), "shot")
		end
		eq(SH.press(st, 1, 10, take.fn), "busy")
		eq(#take.calls, 1, "the busy press sent nothing")
		-- the frame stalls 9 s before the next tick: the cooldown starts there
		eq(SH.tick(st, 9000, take.fn), nil)
		eq(SH.tick(st, 9000 + SH.COOLDOWN_MS[scale] - 1, take.fn), nil)
		ok(SH.busy(st))
		eq(SH.press(st, 2, 9000 + SH.COOLDOWN_MS[scale] - 1, take.fn), "busy")
		eq(SH.tick(st, 9000 + SH.COOLDOWN_MS[scale], take.fn), "ready")
		ok(not SH.busy(st))
		eq(SH.tick(st, 99999, take.fn), nil, "idle afterwards")
	end
end)

test("a press during the primer wait is ignored; unknown scales are refused", function()
	local st, take = SH.new(), fakeTake()
	eq(SH.press(st, 3, 0, take.fn), "bad")
	eq(SH.press(st, 0, 0, take.fn), "bad")
	eq(SH.press(st, nil, 0, take.fn), "bad")
	eq(#take.calls, 0)
	eq(SH.press(st, 2, 0, take.fn), "primer")
	eq(SH.press(st, 4, 500, take.fn), "busy")
	eq(SH.tick(st, 1000, take.fn), "shot")
	eq(take.calls[2], 2, "the first press's scale")
end)

test("a failing take reports an error and leaves the shutter usable", function()
	local st, take = SH.new(), fakeTake(true)
	local what, err = SH.press(st, 2, 0, take.fn)
	eq(what, "error"); eq(err, "boom")
	ok(not SH.busy(st)); eq(st.primed, false, "the primer is tried again next press")
	take.fail = false
	eq(SH.press(st, 2, 0, take.fn), "primer")
	take.fail = true
	eq(SH.tick(st, 1000, take.fn), "error")
	ok(not SH.busy(st), "no cooldown after a failed shot")
	take.fail = false
	eq(SH.press(st, 1, 1000, take.fn), "shot")
end)

test("round 11: the announcement is short, the measured freezes grow with the scale", function()
	ok(SH.ANNOUNCE_MS >= 100 and SH.ANNOUNCE_MS <= 1000, "a few frames")
	ok(SH.FREEZE_S[1] < SH.FREEZE_S[2] and SH.FREEZE_S[2] < SH.FREEZE_S[4])
	-- the cooldown starts after the freeze (the first tick after the call), so it is no shorter than needed
	ok(SH.COOLDOWN_MS[4] >= 10000)
end)

test("outputSize: viewport x scale; unusable sizes give nil", function()
	local w, h = SH.outputSize(2560, 1440, 4)
	eq(w, 10240); eq(h, 5760)
	eq(SH.outputSize(0, 1440, 1), nil)
	eq(SH.outputSize(0 / 0, 1440, 1), nil)
	eq(SH.outputSize(nil, 1440, 1), nil)
	eq(SH.outputSize(1e9, 1440, 1), nil)
end)
