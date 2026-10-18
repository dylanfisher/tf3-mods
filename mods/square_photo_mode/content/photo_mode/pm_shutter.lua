-- pm_shutter.lua (Photo Mode, pure): the screenshot shutter's timing (rev 2 item 2, plans/square_photo_mode/PLAN.md
-- "Shutter"). No api calls and no clock: the driver (gui/pm_driver.lua) passes the time in ms and a take(scale)
-- function (api.gui.camera.takeScreenshot in a pcall), the tests a fake clock and a fake take.
--
-- What the game does (docs/findings/map-camera.md "Screenshots", session 2026-10-13_0339_sqpq):
--   - takeScreenshot(scale) writes viewport x scale pixels to the game's screenshots folder, never with the UI.
--   - The first request of a game session writes no file: once per session a scale-1 primer goes first and the
--     real shot follows PRIMER_MS later (from the driver's step, never a blocking wait).
--   - A request right after a big shot is dropped, and no API reports when a file is written: after each shot
--     the shutter stays busy for COOLDOWN_MS[scale], counted from the first tick after the request (a 4x shot
--     stalls the frame ~9 s while it encodes, so that tick may come only after the stall).
--   - Round 11 (session 2026-10-14_0055_session): takeScreenshot itself blocks until the file is written (the
--     game's "Screenshot: wrote" comes before our own line logged right after the call): 4x froze the game
--     ~11 s (file name 17-59-26, written at :37, two "Possible hang detected"), 2x ~3 s, 1x under a second. A
--     status set in the same frame never shows before the freeze, so a 2x / 4x press first ANNOUNCES (the
--     window shows "the game freezes for ...") and the shot goes ANNOUNCE_MS later from tick. The cooldown
--     starts at the first tick after the call, i.e. after the freeze: it needs no lengthening.
--
-- State: { primed, pending (scale waiting for the primer), dueAt, cooling (scale being saved), untilMs }.

local M = {}

M.SCALES = { 1, 2, 4 }
M.PRIMER_MS = 1000
-- Round 11: how long the "the game freezes" status shows before a 2x / 4x shot (a few rendered frames).
M.ANNOUNCE_MS = 300
-- Round 11: the freeze measured in game per scale (s; session 2026-10-14_0055_session, 2560x1440).
M.FREEZE_S = { [1] = 1, [2] = 3, [4] = 11 }
M.COOLDOWN_MS = { [1] = 2000, [2] = 4000, [4] = 12000 }

function M.new()
	return { primed = false, pending = nil, dueAt = nil, cooling = nil, untilMs = nil }
end

function M.validScale(scale)
	return M.COOLDOWN_MS[scale] ~= nil
end

--- True while a press is ignored: a shot waits for its primer or the last one is still being saved.
function M.busy(st)
	return st.pending ~= nil or st.cooling ~= nil
end

local function shoot(st, scale, take)
	local okTake, err = take(scale)
	if not okTake then return "error", err end
	st.cooling, st.untilMs = scale, nil
	return "shot"
end

--- A press of the shutter at time now (ms). Returns what happened:
---   "primer" the session's primer was sent; the shot follows from tick after PRIMER_MS
---   "announce" a 2x / 4x shot follows from tick after ANNOUNCE_MS (round 11: the freeze is announced first)
---   "shot"   the shot was requested now
---   "busy"   ignored: a shot is pending or still being saved
---   "bad"    not one of M.SCALES
---   "error"  take failed (second value: its error); the state is as before the press
function M.press(st, scale, now, take)
	if not M.validScale(scale) then return "bad" end
	if M.busy(st) then return "busy" end
	if not st.primed then
		local okTake, err = take(1)
		if not okTake then return "error", err end
		st.primed = true
		st.pending, st.dueAt = scale, now + M.PRIMER_MS
		return "primer"
	end
	if scale > 1 then
		st.pending, st.dueAt = scale, now + M.ANNOUNCE_MS
		return "announce"
	end
	return shoot(st, scale, take)
end

--- One driver step at time now (ms). Returns nil (nothing happened), "shot" (the pending shot was requested),
--- "error" (it failed; second value: its error) or "ready" (the cooldown is over: the file should be written).
function M.tick(st, now, take)
	if st.pending ~= nil then
		if now < st.dueAt then return nil end
		local scale = st.pending
		st.pending, st.dueAt = nil, nil
		return shoot(st, scale, take)
	end
	if st.cooling ~= nil then
		-- the first tick after the request starts the cooldown (after a stall, if the shot stalled the frame)
		if st.untilMs == nil then
			st.untilMs = now + M.COOLDOWN_MS[st.cooling]
			return nil
		end
		if now < st.untilMs then return nil end
		st.cooling, st.untilMs = nil, nil
		return "ready"
	end
	return nil
end

--- The output size in pixels of a shot at scale for a viewport w x h, or nil when w / h aren't usable.
function M.outputSize(w, h, scale)
	if type(w) ~= "number" or type(h) ~= "number" or w ~= w or h ~= h or w < 1 or h < 1 or w > 1e5 or h > 1e5 then
		return nil
	end
	return math.floor(w) * scale, math.floor(h) * scale
end

return M
