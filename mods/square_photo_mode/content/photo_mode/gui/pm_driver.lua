-- Photo Mode: the camera driver (GUI thread only: window clicks and the plugin's react.onStep).
-- Pure math in ../pm_cam.lua; subjects from pm_world.lua.
--
-- Camera API (api/tealdef/api/gui.d.tl:426-500): getCameraData / setCameraData (Vec5f x, y, distance, angle,
-- pitch), followEntity(entity, jump), getFollowEntity, enterFollowCameraCockpit / leaveFollowCameraCockpit,
-- api.engine.terrain.getHeightAt.
--
--   jump     a subject is framed from cam.FRAMING (static view); a flying aircraft is followed instead
--            (its height is out of reach of a ground-centred view). Instant.
--   shot     a preset distance / pitch around the current centre. Instant.
--   orbit    turns the current view by cam.ORBIT_RAD_PER_S each frame (keeps the player's zoom and the follow
--            camera's moving centre). Stops when the player turns / tilts / zooms the camera.
--   follow   followEntity(last vehicle or person subject, false). Off (releaseFollow): setCameraData alone does
--            NOT end a follow (game log 2026-10-13_0325: "follow off (button)", the camera kept following until
--            the player moved it). The base game never ends a follow from Lua (the C++ FollowAction ends itself
--            on player input and fires "stoppedFollowAction", gui/main/free_cam_options.tl:25-28), so the release
--            tries the camera calls that set a new camera target, one per stage, checking getFollowEntity a few
--            frames after each: 1 focusPosition(centre, distance) (base line_warning.script.tl:194), 2
--            setManualCamera(centre, distance) (base mission_framework_react_util.tl:228), 3
--            leaveFollowCameraCockpit (the base FreeCamTool's pop, safe with no cockpit). After each call the
--            view is set again (focus / manual camera don't change the distance or angle: findings map-camera.md
--            "Camera zoom limit"). Logged: "follow released by <call>" or "follow still on after every call".
--   cockpit  enterFollowCameraCockpit(last vehicle); leave via the button, the window closing or the pause menu.
--   tour     modes (cam.TOUR_MODES): "ground" hops, "aerial" a continuous drone flight, "mixed" hops with a
--            flight leg every cam.MIXED_FLIGHT_EVERY hops. Hop sources (checkboxes, cam.TOUR_SOURCES): the
--            ticked ones in turn, one per hop (cam.tourNextSource; a source with nothing this hop is skipped).
--            "random" / "places" / "shots": the next kind of cam.SOURCE_KINDS[source] (kinds with nothing on
--            the map skipped), framed by cam.tourFrame within the tour's range (cam.tourRange) or by the
--            photographer's shot's own framing (pm_shots.lua); "views": the saved views in list order,
--            looping. Each hop: a cam.GLIDE_SECONDS glide, then the hold of N s, timed from the arrival. With
--            "Ken Burns drift" on, a slow drift whose speed ramps into and out of the glides
--            (velocity-continuous, pm_flight.lua). A flight: a spline through waypoints picked from the ticked
--            flight subjects (world.flightCandidates), its speed ramping in from rest, cam.legSeconds long;
--            in Aerials the next leg starts over a new area (a glide there), in Mixed the hops go on. Only
--            saved views ticked: no flights (the list order is kept).
--            "place" (round 6, pm_place.lua): the camera centre at the start, shot from all around it within the
--            area, nearby subjects (world.nearby, every pm_place.REFRESH_HOPS hops) as some of the targets.
--            The tour hides our window and the game UI (pm_hud.lua via D.onTourHide), so the step also runs while
--            the window is hidden (D.busy). Round 9: tours no longer try the game's free camera (camera mode).
--            Mouse look (user feedback 2026-10-13): during a flight (Aerials, Mixed legs) the player's turn /
--            tilt / zoom doesn't stop the tour; cam.flightInput reads it from the difference between the view
--            we set last frame and getCameraData, F.lookStep keeps it as an offset on top of the flight's view
--            (decaying back to the path when "Look returns to the path" is on). Only a pan (or Esc) stops it.
--            Look "horizon": the drone looks far ahead along its heading, nearly level (F.horizonAhead).
--            "wander" (round 7, pm_flight "Wander"): no cuts; the camera drifts around the place in the middle of
--            the view (the Area, the angle rows), its look wandering between nearby subjects and points of the
--            area. Also a camera move (D.toggleWander, Camera tab next to Orbit) around the current view.
--            Round 22 (the Aerials and Tour tabs, D.startTab; each picks where it goes, cam.tourModeOf): Aerials
--            "Saved views" fly along the saved views' centres in list order (S.tour.route, routeWaypoint: no
--            legs, a turning waypoint before a sharp turn); the Tour's Wander "Across the map" / "Saved views"
--            roams (S.tour.roam): it wanders round one place for the Stay, then glides to the next (roamPlace: a
--            subject of the map sources not shown lately, or the next saved view), the glide longer and higher
--            the farther it goes (startWander `at`).
--   eye      (round 7) every automated move (glides, Ken Burns, flights, wander) is planned as an eye pose with a
--            reference ground (pm_flight "Eye space") and sent through F.solveEye: the eye no longer bobs with
--            the terrain under the look-at point. The manual orbit turns around a fixed centre (its eye height
--            never changes) and stays a plain view. "eye check" log lines compare the planned eye with getEye.
--            Round 9: the game's camera model (pm_flight "The game's camera model", findings map-camera.md): its
--            centre 4 m above the ground, its eye at an elevation that depends on the pitch AND the distance; the
--            solver sends the pitch for the elevation wanted at each frame's distance (no lag), and only the
--            model's small residual is measured from getEye / getCenter (sampleCam) and corrected slowly. A
--            hop's views are in the game's pitch (sendPlanned gamePitch), wander and flights plan elevations.
--   hover    (round 9) while an automated move runs (tour of any mode, Wander, Orbit) the map's hover, tooltips
--            and click-to-select are off (D.onAutoMode -> pm_hud.setAutoHover), back when it ends by any path.
--   horizon  shots "Horizon" / "High horizon": the eye h m above the current centre, nearly level, the centre
--            pushed ahead (cam.horizonShot); past cam.ZOOM_LIMIT clamped, the pitch raised, logged.
--   look     the camera `angle` and the world heading it looks along differ by a constant measured once per
--            session from getEye / getCenter (cam.measureLookOffset), so the photographer's shots (which name
--            a look heading) face the right way; until measured it is taken as 0.
-- Any of orbit / tour stops when the camera differs from what we set last (cam.userMoved): the player moved it.
--
-- Per frame (D.step, while the window is open, a tour runs or a follow release is still being checked): idle
-- (no orbit / tour / release, or in the cockpit) returns before any api call or clock read. While a move runs:
-- one getCameraData, one setCameraData (a new Vec5f; a reused one is untested), getFollowEntity while
-- following; the eye-space solver's 4 getHeightAt (F.EYE: 1 clearance + 3 along the look ray; a flight 1-2 more
-- for its altitude and look point); getEye + getCenter (the camera model's residual and the smoothness metric),
-- and in the traced frames of a move one "cam trace" line (+ getHeightAboveTerrain, world2Screen, getSize).
-- The hop / flight views
-- are computed into scratch tables (pm_flight's own buffers and setBuf), so a hop frame allocates no Lua
-- tables. No log line per frame: a failing setCameraData stops the moves with one line. The tour's next pick
-- (pm_world, may build a list or run a 35 ms scan) runs once per hop, a flight's next waypoint about once a
-- minute, never per frame.
-- Shutter (rev 2 item 2): D.screenshot(scale) runs pm_shutter's state machine (the session's primer, the real
-- shot PRIMER_MS later from D.step, the cooldown after each shot) with api.gui.camera.takeScreenshot in a pcall;
-- D.step ticks it only while it is busy (no clock read otherwise). Statuses: taking, saving, saved, wait, error.
-- Log lines: "[PhotoMode] jump ...", "shot ...", "orbit on|off ...", "follow ...", "cockpit ...", "tour ...",
-- "screenshot ...".

local cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
local world = ug_require "square_photo_mode::/photo_mode/gui/pm_world.lua"
local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
local P = ug_require "square_photo_mode::/photo_mode/pm_place.lua"
local perf = (ug_require "square_photo_mode::/photo_mode/gui/pm_perf.lua").perf
local sqperf = ug_require "square_photo_mode::/sqperf/square_photo_mode.lua"
local shutter = ug_require "square_photo_mode::/photo_mode/pm_shutter.lua"
local cutscene = ug_require "square_photo_mode::/photo_mode/gui/pm_cutscene.lua"
local variety = ug_require "square_photo_mode::/photo_mode/pm_variety.lua"

local D = {}

-- Runtime state (one game at a time; reset by D.stopAll on window closed / pause menu / a new game).
local S = {
	last = nil,        -- the view we set last (cam view), for cam.userMoved
	lastStepMs = nil,
	orbit = false,
	follow = nil,      -- entity we asked the camera to follow
	cockpit = nil,     -- entity whose cockpit we entered
	subject = nil,     -- last jumped-to subject with follow = true (vehicle or person)
	tour = nil,        -- { idx = { [source] = kind index }, vidx, n, every (ms), nextAt, src (last source), mode }
	hop = nil,         -- the tour's current hop: { hop (pm_flight), t0 (ms), arrived (ms), range } or nil
	flight = nil,      -- the tour's current flight: { path, glide, t0, flyT0, legMs, h, phase } or nil
	leaving = nil,     -- what the next hop glides from (pm_flight.leaving), nil = the current view
	lookOffset = nil,  -- camera angle -> look heading, measured (cam.measureLookOffset); nil = not yet
	release = nil,     -- follow release being checked: { entity, stage, frames, view, why }
	tourChoice = cam.TOUR_DEFAULT,
	tourSources = cam.copySet(cam.DEFAULT_SOURCES), -- ticked hop sources (cam.TOUR_SOURCES)
	legChoice = cam.LEG_DEFAULT, -- flight leg length (cam.LEG_SECONDS)
	flightSubjects = cam.copySet(cam.DEFAULT_FLIGHT_SUBJECTS), -- what flights head for (cam.FLIGHT_SUBJECTS)
	tourMode = cam.TOUR_MODE_DEFAULT, -- cam.TOUR_MODES (round 13: Aerials; round 22: set by the tab's Start)
	-- the range choices (cam.tourRange; round 22: the preset of the Tour tab's default style and where)
	rangeSel = cam.preset(cam.tourModeOf("wander", "map", false)),
	kenBurns = true,   -- the hold drift
	aerialLook = cam.AERIAL_LOOK_DEFAULT, -- cam.AERIAL_LOOKS: what a flight looks at (taken at each flight's start; round 15: High)
	lookReturn = true, -- the mouse-look offset decays back to the flight's own view
	look = nil,        -- the player's mouse-look offset during a flight (F.lookStep), nil = none
	tourLabels = true, -- "Hide labels during tours" (pm_hud: the labels go while the tour runs; hover always does)
	tourPause = false, -- "Pause the game during the tour" (pm_sky's freeze, restored when the tour ends)
	areaChoice = P.AREA_DEFAULT, -- "This place" / "Wander": the area's radius (pm_place.AREAS)
	-- round 22: the Aerials and Tour tabs (cam.tourModeOf)
	tourStyle = "wander", -- Tour: cam.TOUR_STYLES (round 22, user: "tour style default should be wander")
	tourWhere = "map",   -- Tour: cam.TOUR_WHERES
	tourFlights = false, -- Tour: "Drone flight between shots" (the "mixed" mode)
	aerialWhere = "map", -- Aerials: cam.AERIAL_WHERES
	stayChoice = cam.STAY_DEFAULT, -- Wander across the map / over the saved views: cam.STAY_SECONDS
	wander = nil,      -- the wander move (manual or a tour): { w (pm_flight), t0, manual, subjects, nextAt, from }
	eye = nil,         -- the eye-space solver's state (pm_flight.newEye), per move
	eyeLogs = 0,       -- "eye check" log lines this move (at most EYE_LOGS)
	camRes = 0,        -- round 9: the camera model's residual (pm_flight "The game's camera model"); round 10: per move
	camResLogged = false, -- the session's "camera model: first sample" line written
	camResV = 0,       -- ... and its rate (pm_flight.resUpdate)
	curRead = nil,     -- this frame's getCameraData (D.step), for the camera sample
	noSample = false,  -- this frame's camera is not ours to measure (a follow)
	trace = nil,       -- round 8: the per-frame camera trace of this move: { n = lines, f = frames, max, bursts }
	traceMoves = 0,    -- moves traced this session
	smooth = nil,      -- round 9: the eye smoothness metric of this segment (pm_flight.newSmooth) ...
	smoothAll = nil,   -- ... and of the whole move; logged as "eye smoothness" lines
	smoothWhat = nil,  -- the move's kind for those lines ("tour", "wander")
	autoOn = false,    -- round 9: an automated move runs (hover off, D.onAutoMode)
	spikeLogs = 0,     -- round 12: "eye spike" reports this session (EYE_SPIKE_MAX)
	spikeMove = 0,     -- round 13: ... and this move (EYE_SPIKE_PER_MOVE)
	prevDt = nil,      -- round 13: the last sampled frame's dt (the eye read shows the view sent then)
	ring = nil,        -- round 12: the last frames' solver state for an "eye spike" report
	cutscene = nil,    -- round 13 DEV prototype (pm_cutscene): the orbit cutscene's state while one plays
	lastJump = nil,    -- round 13 DEV: the last subject jumped to (the attached orbit cutscene's subject)
	lastJumpView = nil, -- round 17: the view of the last jump (pm_variety.distinct: never the same one twice in a row)
	holdAuto = false,  -- a move is replacing another: no hover back-and-forth (switching)
	shotAnchor = nil,  -- round 14: { anchor = { x, y, a }, sent = { x, y, a }, reset = why } (cam.shotAnchor)
	orbitT0 = nil,     -- round 16: the orbit's first frame (ms; its speed eases in from there) ...
	orbitOut = nil,    -- ... and when the button asked it to stop (ms; it eases out, then stops)
	orbitSmooth = nil, -- round 16: the orbit's eye smoothness metric (pm_flight.newSmooth)
	settle = nil,      -- round 16: the view easing in after a move: { d0, d1, p0, p1, t0, why }
	autoCut = false,   -- round 16: the automated move running is one of our cutscenes (no settle after it)
	endWhy = nil,      -- round 16: why the last move ended (a player's zoom / tilt: no settle)
	status = nil,      -- translated text shown in the window (last result)
	shutter = shutter.new(), -- the screenshot shutter (pm_shutter.lua); kept across stopAll (one primer a session)
	version = 0,       -- bumped on every change the window shows
}
D.S = S

--- The saved views in list order (set by pm_window.lua, which owns the list); the "views" tour plays them.
D.viewsProvider = function() return {} end
-- Round 8: the saved views also join the pool of the tour's shots and of Anything (pm_world "saved").
world.savedViews = function()
	local okL, list = pcall(D.viewsProvider)
	return okL and type(list) == "table" and list or {}
end
--- Set by the plugin (pm_hud.tourHide + pm_sky freeze): a tour started (true, opts = { hideLabels, pause }) or
--- ended (false).
D.onTourHide = function() end
--- Set by the plugin (pm_hud.setAutoHover): an automated move (tour, Wander, Orbit) started (true) or the last
--- one ended (false), whatever ended it. Round 9 (user: "The tour still has hover and mouse interaction with it.
--- It should by default not."): the map's hover, tooltips and click-to-select are off meanwhile.
D.onAutoMode = function() end

-- Stages of the follow release (see the header): the call tried at each stage.
local RELEASE_CALLS = { "focusPosition", "setManualCamera", "leaveFollowCameraCockpit" }
local RELEASE_FRAMES = 3 -- frames to wait after a call before checking getFollowEntity
-- The saved-views tour drifts this much of a random tour's Ken Burns move around the player's view.
local KB_VIEWS_SCALE = 0.5
-- "eye check" lines per move (planned eye vs getEye: does the game place the centre on getHeightAt's ground?)
local EYE_LOGS = 3
-- Round 8: the per-frame camera trace ("cam trace" lines, TESTING.md U9): the first TRACE_FRAMES frames of a move,
-- for the first TRACE_MOVES moves of a session, or of every move while the "Debug: performance log" setting is On.
local TRACE_FRAMES, TRACE_MOVES = 40, 2
-- Round 9: an "eye smoothness" line every WANDER_SMOOTH_S seconds of a wander (a hop / flight leg: one each).
local WANDER_SMOOTH_S = 30

local function moving()
	return S.orbit or S.tour ~= nil or S.wander ~= nil
end

--- Round 14: the shot presets' anchor (cam.shotAnchor) is taken anew at the next shot: a jump, a follow, the
--- cockpit or an automated move moved the camera on its own.
local function resetShotAnchor(why)
	if S.shotAnchor ~= nil and S.shotAnchor.anchor ~= nil then S.shotAnchor = { reset = why } end
end

local bump
--- Runs fn (one move replacing another: stop the old, start the new) with the hover sync held, then syncs once.
local function switching(fn, ...)
	S.holdAuto = true
	local ok, err = pcall(fn, ...)
	S.holdAuto = false
	bump()
	if not ok then error(err, 0) end
end

--- Every change goes through bump: an automated move starting or ending (any path) tells the hud (not while one
--- move replaces another: S.holdAuto, see switching).
bump = function()
	S.version = S.version + 1
	if S.holdAuto then return end
	-- round 15: a cutscene of ours counts as an automated move too (hover off, the world lock, our tool)
	local auto = moving() or S.cutscene ~= nil
	if auto ~= S.autoOn then
		S.autoOn = auto
		if auto then
			resetShotAnchor("camera move")
			S.autoCut = S.cutscene ~= nil and not moving()
			S.settle = nil
		else
			local v = D.handBack ~= nil and D.handBack("camera move ended") or nil
			-- round 16: a far / flat view eases in to a normal one (not after a cutscene: the game hands back the
			-- player's own view)
			if D.settleStart ~= nil and not S.autoCut then D.settleStart(S.endWhy or "camera move ended", v) end
			S.autoCut = false
		end
		pcall(D.onAutoMode, auto)
	end
end

-- SQPERF sections of the tour (pm_perf.lua perf, ctx gui): one per hop / flight start / place lookup.
local SEC_ADVANCE, SEC_FLIGHT, SEC_PLACE = "tour_advance", "tour_flight_start", "place_subjects"

local function setStatus(text)
	S.status = text
	bump()
end
--- A notice in the window's status line; nil clears it.
D.setStatus = setStatus

local function getCam() return api.gui.camera.getCameraData() end

--- The current camera view, written into `out` (a scratch table) or a new table; nil when unreadable.
local function readView(out)
	local ok, d = pcall(getCam)
	if not ok or d == nil then return nil end
	local v = out or {}
	v.x, v.y, v.d, v.a, v.p = d.x, d.y, d.z, d.w, d.q
	return v
end
D.readView = function() return readView() end

-- Per-frame scratch views of D.step (never kept anywhere but S.last, see setView).
local curBuf, setBuf = {}, {}

--- Every setCameraData goes through cam.safeView: finite values only, distance / pitch in range, the centre on
--- the map (world.mapBounds), no -0. A view that isn't finite raises here (caught by setView's pcall) and is
--- never sent.
local function setCam(v)
	local x, y, d, a, p = cam.safeView(v, world.mapBounds())
	if x == nil then error("view not finite: " .. cam.viewText(v), 0) end
	-- round 10: never an eye past straight down (the camera model: a steep pitch far out passes pi / 2, the game's
	-- keys turn around; Bird's eye 1.30 at 900 m becomes ~1.25)
	local pm = F.pitchMaxAt(d)
	if cam.finite(pm) and p > pm then p = math.max(0, pm) + 0 end
	api.gui.camera.setCameraData(api.type.Vec5f.new(x, y, d, a, p))
end

-- Round 15 (user: "Bug with fast movement still there I think?"): a "camera set with no move active" line whenever
-- a per-frame path ("move") or an unnamed caller sets the camera while no automated move (tour, Wander, Orbit) or
-- follow release runs: Photo Mode must never touch the camera then (session 2026-10-14_0658_session: no per-frame
-- set after a move ended, D.step returns idle; this line proves it in every later session). At most STRAY_LOGS.
local STRAY_LOGS = 8

--- Sets the camera; S.last keeps `v` itself (D.step's setBuf too: it is only rewritten after the next frame's
--- cam.userMoved has compared it). quiet: no log line on failure (the step logs once itself). src: who sets it
--- ("move" per frame, "jump" / "shot" / "view" / "release" once, at the player's click).
local function setView(v, quiet, src)
	if (src == nil or src == "move") and not moving() and S.release == nil then
		S.strays = (S.strays or 0) + 1
		if S.strays <= STRAY_LOGS then
			core.log(string.format("camera set with no move active (%s, %d of at most %d lines) view=%s",
				tostring(src or "unnamed caller"), S.strays, STRAY_LOGS, cam.viewText(v)))
		end
	end
	-- round 16: a jump, shot or saved view replaces the settling view
	if src ~= "settle" and src ~= "move" then S.settle = nil end
	local ok, err = pcall(setCam, v)
	if not ok then
		if not quiet then core.log("setCameraData ERROR " .. tostring(err)) end
		return false, err
	end
	S.last = v
	return true
end

-- Round 15: the view the player gets back. The game's keyboard pan moves 1.1-1.3 x the camera's distance per
-- second (measured in session 2026-10-14_0434_session's smooth traces, PLAN.md "Round 13" item 2), so a view far
-- from its look-at point (a horizon shot at d 4000, a Wander at d ~500 with the eye 100-200 m up) pans several
-- times faster than the game's own camera at that eye height: the "hyper sensitive" camera after a tour or a shot
-- (inferred). One "hand-back" line at every move end and every shot / jump: d, the eye's height over the look-at
-- point, d / height and the pan speed to expect.
local PAN_PER_D = 1.2

--- Round 16: returns the view read (nil: unreadable), for the settle.
local function handBack(why)
	local v = readView()
	pcall(function()
		local e, c = api.gui.camera.getEye(), api.gui.camera.getCenter()
		if v == nil or e == nil or c == nil then return end
		local h = e.z - c.z
		core.log(string.format("hand-back (%s): d=%.0f m, the eye %.0f m over the look-at point, d/height=%.1f, "
			.. "pitch=%.3f; the keys pan ~%.0f m/s (%.1f x d)", why, v.d, h, v.d / math.max(h, 1), v.p, PAN_PER_D * v.d,
			PAN_PER_D))
	end)
	return v
end
D.handBack = handBack

-- Round 16 (user: "Fast camera bug still happens"; the round 15 data: the views tours and Wander hand back are far
-- from their look-at point with a flat look, d 466-654 m with the eye 100-220 m up, a High tour d ~1700 m, and the
-- keys pan ~1.2 x d per second: 2-5 x the game's own camera at that height; findings map-camera.md "The keyboard
-- pan scales with the camera's distance"). After a tour, Wander or Orbit ends (not after a cutscene, a shot or the
-- player's own zoom / tilt) a view farther than SETTLE.dFar, or farther than SETTLE.dFlat with an eye elevation
-- under SETTLE.eMin (the game's camera model, pm_flight.gameElev; the game's usual view: ~0.8 rad), eases in over
-- SETTLE.seconds (smootherstep) to the distance SETTLE.dTo at a pitch of at least SETTLE.pMin, around the same
-- look-at point. The player's pan and turn go on meanwhile (x, y, angle read each frame); a zoom or tilt of theirs
-- ends it. Logged: "settle (why): d a -> b m, pitch ..." and "settled: ..." (or "settle ended by ...").
local SETTLE = { seconds = 1.5, dFar = 1200, dFlat = 300, eMin = 0.6, dTo = 550, pMin = 0.6 }
D.SETTLE = SETTLE

--- The settled distance and pitch for view v (and v's eye elevation), or nil when v pans like the game's own.
function D.settleTarget(v)
	if v == nil or not (cam.finite(v.d) and cam.finite(v.p)) then return nil end
	local e = F.gameElev(v.p, v.d)
	if not (v.d > SETTLE.dFar or (v.d > SETTLE.dFlat and e < SETTLE.eMin)) then return nil end
	return math.min(v.d, SETTLE.dTo), math.max(v.p, SETTLE.pMin), e
end

function D.settleStart(why, v)
	S.settle = nil
	if type(why) == "string" and (why:find("zoom", 1, true) or why:find("tilt", 1, true)) then return end
	local d1, p1, e = D.settleTarget(v)
	if d1 == nil then return end
	S.settle = { d0 = v.d, d1 = d1, p0 = v.p, p1 = p1, t0 = nil, why = why }
	S.last = nil
	core.log(string.format("settle (%s): d %.0f -> %.0f m, pitch %.3f -> %.3f (eye elevation %.2f rad) over %.1f s: "
		.. "the keys will pan ~%.0f m/s instead of ~%.0f", tostring(why), v.d, d1, v.p, p1, e, SETTLE.seconds,
		PAN_PER_D * d1, PAN_PER_D * v.d))
end

local function settleStep(now)
	local st = S.settle
	local cur = readView()
	if cur == nil then S.settle = nil return end
	local last = S.last
	if last ~= nil then
		-- the player's zoom or tilt: their view wins (a pan or turn is kept below)
		local tol = cam.MOVE_TOL
		local zoom = math.abs(cur.d - last.d) > tol.dRel * math.max(last.d, 1)
		if zoom or math.abs(cur.p - last.p) > tol.p then
			S.settle = nil
			core.log(string.format("settle ended by the player's %s at d %.0f m", zoom and "zoom" or "tilt", cur.d))
			return
		end
	end
	st.t0 = st.t0 or now
	local u = cam.ease5((now - st.t0) / (SETTLE.seconds * 1000))
	local v = { x = cur.x, y = cur.y, a = cur.a, d = st.d0 + (st.d1 - st.d0) * u, p = st.p0 + (st.p1 - st.p0) * u }
	local ok = setView(v, true, "settle")
	if not ok or u >= 1 then
		S.settle = nil
		S.last = nil
		if ok then handBack("settled") else core.log("settle stopped: setCameraData failed") end
	end
end

local function ground(x, y)
	local z = world.groundAt ~= nil and world.groundAt(x, y) or nil
	return cam.finite(z) and z or nil
end

--- A view with its reference ground (the terrain under its centre, one getHeightAt) when it has none.
local function withGround(v)
	if v ~= nil and v.g == nil then v.g = ground(v.x, v.y) or 0 end
	return v
end

local lookOffset -- below
local solveBuf = {}

local function v3(fn)
	local ok, r = pcall(fn)
	if not ok or r == nil then return nil end
	return r.x, r.y, r.z
end

-- Round 12 (user: "tours still are jerky over terrain"; session 2026-10-14_0229_sqrl-sqst: a flight leg's eye
-- d2 max 24.9 m at 789 m/s although the drone flies 32 m/s, a new-area glide's 56 m at 3407 m/s, while every
-- traced frame and eye check matched the plan within 0.2 m: the jerks sit in frames no trace covered). An
-- "eye spike" report when one frame's eye d2 (the game's getEye) exceeds EYE_SPIKE_M: that frame and the solver
-- state of the last RING_N frames sent (planned eye, view sent and whether setCam clamped it, ground under the
-- centre, the look's leftover, a meeting-point blend, the clearance lift, guarded frames, height reads), at most
-- EYE_SPIKE_MAX reports a session.
-- Round 13 (session 2026-10-14_0434_session: the session's 12 reports were all spent in the first two clicks of
-- the smooth camera, none was left for the two tours): at most EYE_SPIKE_PER_MOVE reports a move, EYE_SPIKE_MAX a
-- session; the d2 is taken at the frames' own times (pm_flight smoothAdd: an uneven frame time alone is no
-- spike), and a look jolt over EYE_SPIKE_LOOK rad reports too (the place tour's hops: look d2 max 0.06 / 0.079).
-- Round 13b (session 2026-10-14_0606_session: the Aerials tour's 4 reports went to ONE jolt, frames 66-70, of the
-- game's centre 3 m off for three frames; the tour's worst frame, d2 30 m at f=1573, got none): one report per
-- jolt (the next only EYE_SPIKE_GAP frames after the last), up to EYE_SPIKE_PER_MOVE a move and EYE_SPIKE_MAX a
-- session; every frame over the threshold is counted in the smoothness lines (`spikes=`), reported or not.
local EYE_SPIKE_M, EYE_SPIKE_MAX, EYE_SPIKE_PER_MOVE, EYE_SPIKE_LOOK, RING_N = 1.5, 24, 8, 0.05, 4
local EYE_SPIKE_GAP = 30
D.EYE_SPIKE = { m = EYE_SPIKE_M, max = EYE_SPIKE_MAX, perMove = EYE_SPIKE_PER_MOVE, look = EYE_SPIKE_LOOK,
	gap = EYE_SPIKE_GAP }

--- Remembers this frame's solver state (sendPlanned) for a later "eye spike" report.
local function ringPush(dt, st, sent)
	local ring = S.ring
	if ring == nil then
		ring = { n = 0 }
		S.ring = ring
	end
	ring.n = ring.n + 1
	local i = (ring.n - 1) % RING_N + 1
	local r = ring[i] or {}
	ring[i] = r
	r.n, r.dt = ring.n, dt
	r.ex, r.ey, r.ez = st.ex, st.ey, st.ez
	r.x, r.y, r.d, r.a, r.p = sent.x, sent.y, sent.d, sent.a, sent.p
	local x, y, d, a, p = cam.safeView(sent, world.mapBounds())
	r.clamped = x == nil or math.abs(x - sent.x) > 1e-3 or math.abs(y - sent.y) > 1e-3 or math.abs(d - sent.d) > 1e-3
		or math.abs(p - sent.p) > 1e-4 or (cam.finite(F.pitchMaxAt(d)) and p > F.pitchMaxAt(d) + 1e-4)
	r.gC, r.err, r.lift, r.calls = st.gC, st.err, st.lift, st.calls
	r.blend = st.blend ~= nil
	r.guarded = st.guarded or 0
end

local function spikeText(r)
	local function n1(v) return cam.finite(v) and string.format("%.1f", v) or "-" end
	return string.format("#%d dt=%.4f plan=%s,%s,%s sent=%s,%s,%s,%.3f,%.3f%s g=%s err=%.4f lift=%s blend=%s guarded=%d reads=%s",
		r.n, r.dt or 0, n1(r.ex), n1(r.ey), n1(r.ez), n1(r.x), n1(r.y), n1(r.d), r.a or 0, r.p or 0,
		r.clamped and " CLAMPED" or "", n1(r.gC), r.err or 0, n1(r.lift), tostring(r.blend), r.guarded,
		tostring(r.calls))
end

--- After a sample: one frame's eye d2 over EYE_SPIKE_M is reported with the frames before it.
local function spikeCheck(m, cur, dt, ex, ey, ez, cx, cy, cz)
	local d2, lookD2 = m.lastD2, m.lookD2
	local spike = (d2 ~= nil and d2 > EYE_SPIKE_M) or (lookD2 ~= nil and lookD2 > EYE_SPIKE_LOOK)
	if not spike then return end
	m.spikes = (m.spikes or 0) + 1
	if S.smoothAll ~= nil and S.smoothAll ~= m then S.smoothAll.spikes = (S.smoothAll.spikes or 0) + 1 end
	-- round 13b: one report per jolt (its later frames are the same event)
	local fr = (S.smoothAll or m).frames -- the move's frame count (a segment's restarts)
	local lastF = S.spikeLastF
	S.spikeLastF = fr
	if lastF ~= nil and fr > lastF and fr - lastF < EYE_SPIKE_GAP then return end
	if S.spikeLogs >= EYE_SPIKE_MAX or (S.spikeMove or 0) >= EYE_SPIKE_PER_MOVE then return end
	S.spikeLogs = S.spikeLogs + 1
	S.spikeMove = (S.spikeMove or 0) + 1
	-- where the camera model puts the eye and centre for the view read (one height read, only here): an engine
	-- eye far from it means the game broke the model in this frame (its centre height, a clamp of its own)
	local mx, my, mz, mcz = nil, nil, nil, nil
	local baseZ, water = nil, nil
	pcall(function()
		local g = ground(cur.x, cur.y)
		mcz = F.centreZ(g, cur.d)
		mx, my, mz = F.eyeOf(cur, g, lookOffset(), S.camRes)
		-- round 14: the terrain's base height (no alignments) and water there (see "centre fit")
		baseZ = world.baseGroundAt ~= nil and world.baseGroundAt(cur.x, cur.y) or nil
		if world.waterAt ~= nil then water = world.waterAt(cur.x, cur.y) end
	end)
	local function n1(v) return cam.finite(v) and string.format("%.1f", v) or "-" end
	-- round 13: the view read against the view sent last frame (S.last until this frame's set): in the 0434
	-- session's glide spikes the game's distance differed from the one sent by 4-10 m
	local last = S.last
	local rs = "-"
	if last ~= nil and cur ~= nil and cam.finite(last.d) then
		rs = string.format("%.1f,%.1f,%.1f,%.4f,%.4f", cur.x - last.x, cur.y - last.y, cur.d - last.d,
			cam.angleDiff(last.a, cur.a), cur.p - last.p)
	end
	core.log(string.format("eye spike %d/%d (%s) f=%d d2=%s m raw=%s dt=%.4f look d2=%s eye=%.1f,%.1f,%.1f"
		.. " model=%s,%s,%s centre=%.1f,%.1f,%.1f model z=%s base=%s water=%s read=%s read-sent=%s",
		S.spikeLogs, EYE_SPIKE_MAX, S.smoothWhat or "move", m.frames, d2 and string.format("%.2f", d2) or "-",
		m.lastD2Raw and string.format("%.2f", m.lastD2Raw) or "-", dt or 0,
		lookD2 and string.format("%.4f", lookD2) or "-", ex, ey, ez, n1(mx), n1(my), n1(mz), cx or 0, cy or 0,
		cz or 0, n1(mcz), n1(baseZ), tostring(water), cur and cam.viewText(cur) or "-", rs))
	local ring = S.ring
	if ring == nil then return end
	for k = math.max(1, ring.n - RING_N + 1), ring.n do
		local r = ring[(k - 1) % RING_N + 1]
		if r ~= nil and r.n == k then core.log("eye spike   " .. spikeText(r)) end
	end
end

-- Round 14 (session 2026-10-14_0633_session: the Aerials Down look's 8 eye spike reports, every one but a model
-- residual and the player's own pan, sat where the game's centre was 1.6-8.4 m above getHeightAt + 4: under a
-- terrace / cut edge where getHeightAt dropped 5-13 m in a frame, and once over a river, g -12.5, the centre at
-- 12.4). The "centre fit" tally checks, every frame of a move, the game's centre (read now, for the view sent last
-- frame) against the camera model; where it is more than CENTRE_FIT_OFF m off, it also reads the terrain's base
-- height (getBaseHeightAt: without the alignments roads, tracks and industries cut into the terrain) and whether
-- the point is on water, so the next session tells which surface the game's centre sits on there. Logged as one
-- "centre fit" line per move (and base= / water= in the spike reports). One getHeightAt per frame, two more reads
-- in an off frame.
local CENTRE_FIT_OFF, CENTRE_FIT_BASE = 1.0, 0.6

local function centreFit(ex, ey, ez, cx, cy, cz)
	local fit = S.fit
	if fit == nil or not (cam.finite(cx) and cam.finite(cz) and cam.finite(ez)) then return end
	local g = ground(cx, cy)
	if g == nil then return end
	local dist = math.sqrt((ex - cx) ^ 2 + (ey - cy) ^ 2 + (ez - cz) ^ 2)
	local mz = F.centreZ(g, dist)
	local off = cz - mz
	fit.n = fit.n + 1
	if math.abs(off) <= CENTRE_FIT_OFF then return end
	fit.off = fit.off + 1
	local base = world.baseGroundAt ~= nil and world.baseGroundAt(cx, cy) or nil
	local water = nil
	if world.waterAt ~= nil then water = world.waterAt(cx, cy) end
	if base ~= nil and math.abs(cz - F.centreZ(base, dist)) <= CENTRE_FIT_BASE then fit.base = fit.base + 1 end
	if water then fit.water = fit.water + 1 end
	if math.abs(off) > math.abs(fit.max) then
		fit.max, fit.at = off, string.format("%.0f,%.0f g=%.1f base=%s water=%s d=%.0f", cx, cy, g,
			base ~= nil and string.format("%.1f", base) or "-", tostring(water), dist)
	end
end
D.centreFit = centreFit

--- The move's "centre fit" line (nothing when no frame was counted).
local function centreFitLine()
	local fit = S.fit
	S.fit = nil
	if fit == nil or fit.n == 0 then return end
	core.log(string.format("centre fit (%s): frames=%d off>%.0fm=%d (%.1f %%) base height fits %d, on water %d; worst %+.1f m at %s",
		S.smoothWhat or "move", fit.n, CENTRE_FIT_OFF, fit.off, 100 * fit.off / fit.n, fit.base, fit.water, fit.max,
		fit.at or "-"))
end

--- The game's camera this frame (round 9, pm_flight "The game's camera model"): getEye and getCenter against
--- getCameraData `cur`. The sample's residual (the offset measured less the model's) updates S.camRes slowly
--- (pm_flight.resUpdate); the eye feeds the smoothness metric. dt: seconds since the last frame (0: a move's
--- first frame). Returns the raw offset sample, the reason it was refused, and the eye / centre read.
local function sampleCam(cur, dt)
	local ex, ey, ez = v3(api.gui.camera.getEye)
	local cx, cy, cz = v3(api.gui.camera.getCenter)
	local smp, why = F.pitchSample(cur, ex, ey, ez, cx, cy, cz)
	local r = F.resSample(cur, smp)
	if not S.camResLogged and r ~= nil then
		S.camResLogged = true
		core.log(string.format("camera model: first sample offset %+.3f rad, model %+.3f, residual %+.3f (d=%.0f p=%.3f)",
			smp, smp - r, r, cur.d, cur.p))
	end
	S.camRes, S.camResV = F.resUpdate(S.camRes, S.camResV, r, dt)
	-- round 13: the eye read now shows the view sent LAST frame (session 2026-10-14_0434_session: each spike's
	-- model eye equals the plan of the frame before), which was planned for the last frame's dt; the metric pairs
	-- the eye's step with that dt (with this frame's, a long frame before showed as a spike on the next)
	local mdt = S.prevDt or 0
	S.prevDt = dt
	if S.smooth ~= nil and cam.finite(ez) then
		centreFit(ex, ey, ez, cx, cy, cz)
		F.smoothAdd(S.smooth, ex, ey, ez, mdt, cx, cy, cz)
		F.smoothAdd(S.smoothAll, ex, ey, ez, mdt, cx, cy, cz)
		spikeCheck(S.smooth, cur, mdt, ex, ey, ez, cx, cy, cz)
	end
	return smp, why, ex, ey, ez, cx, cy, cz
end
D.sampleCam = sampleCam

--- One "eye smoothness" line: the game's eye over a segment (a hop, a flight leg, a stretch of a wander) or the
--- whole move (TESTING.md V5). m: a pm_flight.newSmooth.
local function smoothLine(what, m)
	if m == nil or m.frames < 3 then return end
	local d2Max, d2Rms, accMax, jMax, jRms, n, worst, vMax, lookMax, lookWorst = F.smoothStats(m)
	core.log(string.format("eye smoothness (%s): frames=%d d2 max=%.3f rms=%.4f m acc max=%.1f m/s2"
		.. " jerk max=%.1f rms=%.2f m/s2 per frame worst f=%d speed max=%.0f m/s cuts=%d guarded=%d"
		.. " look d2 max=%.4f rad f=%d spikes=%d",
		what, n, d2Max, d2Rms, accMax, jMax, jRms, worst, vMax, m.cuts or 0, S.eye and S.eye.guarded or 0,
		lookMax, lookWorst, m.spikes or 0))
end

--- The segment's line (and a new segment).
local function smoothSegment(what)
	if S.smooth == nil then return end
	smoothLine(what, S.smooth)
	S.smooth = F.newSmooth()
end

--- The move's total line; the metric off.
local function smoothEnd()
	if S.smoothAll == nil then return end
	smoothLine((S.smoothWhat or "move") .. " total", S.smoothAll)
	centreFitLine()
	S.smooth, S.smoothAll = nil, nil
end

-- Wander traces (round 9): the first TRACE_FRAMES frames, then a burst of TRACE_BURST frames at each of these
-- frame counts (about 10 s, 30 s and 60 s in at 60 fps).
local TRACE_BURSTS, TRACE_BURST = { 600, 1800, 3600 }, 5

--- A move starts (kind: "tour" or "wander"): a fresh solver state, its eye checks, the smoothness metric, and
--- its camera trace (the first TRACE_MOVES moves of a session, every wander, every move with the debug log on).
local function newMove(kind)
	smoothEnd()
	-- round 10: the residual starts from 0 for every move (one measured at another distance says little here; the
	-- refitted model leaves ~0.001 rad)
	S.camRes, S.camResV = 0, 0
	S.eye = F.newEye(S.camRes)
	S.eyeLogs = 0
	S.trace = nil
	S.smoothWhat = kind or "tour"
	S.smooth, S.smoothAll = F.newSmooth(), F.newSmooth()
	S.fit = { n = 0, off = 0, base = 0, water = 0, max = 0, at = nil }
	S.ring = nil
	S.spikeMove = 0
	S.spikeLastF = nil
	S.prevDt = nil
	local debugOn = sqperf.readParam(core.MOD_ID, sqperf.PARAM_KEY) -- "Debug: performance log" On
	if S.traceMoves < TRACE_MOVES or debugOn or kind == "wander" then
		S.traceMoves = S.traceMoves + 1
		S.trace = { n = 0, f = 0, max = TRACE_FRAMES, bursts = kind == "wander" and TRACE_BURSTS or nil }
	end
end
D.newMove = newMove

--- This frame of the move is traced: the first tr.max frames, and the bursts.
local function traceNow(tr)
	tr.f = tr.f + 1
	if tr.f <= tr.max then return true end
	if tr.bursts == nil then return false end
	for __, b in ipairs(tr.bursts) do
		if tr.f > b and tr.f <= b + TRACE_BURST then return true end
	end
	return false
end

local function f1(v) return cam.finite(v) and string.format("%.1f", v) or "-" end
local function f3(v) return cam.finite(v) and string.format("%.3f", v) or "-" end

--- One "cam trace" line: the frame's getCameraData (read), the game's eye and centre and height above terrain,
--- the eye we plan, the view we send now (set), the ground under it, the measured offset (sample, or why it was
--- refused), the camera model's offset at the read (model) and the residual estimate (res), and where the game's
--- centre shows on the screen (world2Screen / getSize: the middle = 0.5,0.5).
local function traceLine(cur, smp, why, ex, ey, ez, cx, cy, cz, sent)
	local tr = S.trace
	tr.n = tr.n + 1
	local hat = nil
	pcall(function() hat = api.gui.camera.getHeightAboveTerrain() end)
	local sx, sy = nil, nil
	pcall(function()
		if cx == nil then return end
		local p = api.gui.camera.world2Screen(api.type.Vec3f.new(cx, cy, cz))
		local sz = api.gui.camera.getSize()
		if p ~= nil and sz ~= nil and sz.x > 0 and sz.y > 0 then sx, sy = p.x / sz.x, p.y / sz.y end
	end)
	local st = S.eye
	local model = F.gameElev(cur.p, cur.d, 0) - cur.p
	core.log(string.format("cam trace f=%d read=%s,%s,%s,%s,%s eye=%s,%s,%s centre=%s,%s,%s hat=%s plan=%s,%s,%s"
		.. " set=%s,%s,%s,%s,%s g=%s sample=%s%s model=%s res=%s scr=%s,%s",
		tr.f, f1(cur.x), f1(cur.y), f1(cur.d), f3(cur.a), f3(cur.p), f1(ex), f1(ey), f1(ez), f1(cx), f1(cy), f1(cz),
		f1(hat), f1(st and st.ex), f1(st and st.ey), f1(st and st.ez),
		f1(sent.x), f1(sent.y), f1(sent.d), f3(sent.a), f3(sent.p), f1(st and st.gC),
		f3(smp), why and ("(" .. why .. ")") or "", f3(model), f3(S.camRes), f3(sx), f3(sy)))
end

--- Sends a planned view (with its reference ground g) through the eye-space solver (pm_flight "Eye space"): the
--- eye goes where the plan puts it, whatever the terrain under the look-at point. dt: seconds since the last
--- frame. gamePitch: v's pitch is the game's (a framing, a saved view, a hop's drift: the eye where the game would
--- put it on the reference ground), else the eye-centre elevation (wander, flights). Round 9: the game's camera
--- this frame is sampled (getEye + getCenter) for the model's residual and the smoothness metric.
--- S.last = the view actually sent (solveBuf, rewritten only after the next frame's moved check).
local function sendPlanned(v, dt, gamePitch)
	if S.eye == nil then newMove(S.wander ~= nil and "wander" or "tour") end
	local smp, why, gex, gey, gez, gcx, gcy, gcz
	local cur = S.curRead
	if cur ~= nil and not S.noSample then
		smp, why, gex, gey, gez, gcx, gcy, gcz = sampleCam(cur, dt)
	end
	S.eye.res = S.camRes
	local off = lookOffset()
	local ex, ey, ez, h, p, L = F.poseOf(v, off, gamePitch, S.camRes)
	S.eye.maxL = F.rayInside(world.mapBounds(), ex, ey, h)
	local ok, err = pcall(F.solveEye, S.eye, ex, ey, ez, h, p, L, ez - (v.g or 0), ground, off, dt, solveBuf)
	if not ok then return false, err end
	pcall(ringPush, dt, S.eye, solveBuf)
	if S.trace ~= nil and cur ~= nil and traceNow(S.trace) then
		pcall(traceLine, cur, smp, why, gex, gey, gez, gcx, gcy, gcz, solveBuf)
	end
	return setView(solveBuf, true, "move")
end

--- One "eye check" line (at most EYE_LOGS per move): the eye we planned against getEye, the view sent, the game's
--- centre against our ground, the model's offset for the view sent and the residual, and the height reads of a
--- frame (TESTING.md V4).
local function eyeCheck(what)
	local st = S.eye
	if S.eyeLogs >= EYE_LOGS or st == nil or st.ex == nil then return end
	S.eyeLogs = S.eyeLogs + 1
	local ex, ey, ez = v3(api.gui.camera.getEye)
	if not cam.finite(ez) then return end
	local cx, cy, cz = v3(api.gui.camera.getCenter)
	local set = S.last or {}
	local model = (cam.finite(set.p) and cam.finite(set.d)) and (F.gameElev(set.p, set.d, 0) - set.p) or nil
	core.log(string.format("eye check (%s): planned %.1f,%.1f,%.1f engine %.1f,%.1f,%.1f dz=%.2f set=%s,%s,%s,%s,%s"
		.. " centre=%s,%s,%s g=%s model=%s res=%s lift=%.1f height reads=%d/frame",
		what, st.ex, st.ey, st.ez, ex, ey, ez, ez - st.ez, f1(set.x), f1(set.y), f1(set.d), f3(set.a), f3(set.p),
		f1(cx), f1(cy), f1(cz), f1(st.gC), f3(model), f3(S.camRes), st.lift or 0, st.calls or 0))
end

local function getFollow() return api.gui.camera.getFollowEntity() end

local function following()
	if S.follow == nil then return false end
	local ok, fe = pcall(getFollow)
	if not ok or fe == nil then return false end
	local e = fe[1]
	return e ~= nil and e == S.follow
end

local function leaveCockpit(why)
	if S.cockpit == nil then return end
	S.cockpit = nil
	-- leaveFollowCameraCockpit is safe when the cockpit already ended: the base FreeCamTool's pop calls it
	-- unconditionally, also after the game ended the follow itself (gui/main/free_cam_options.tl:26-47).
	local ok, err = pcall(api.gui.camera.leaveFollowCameraCockpit)
	core.log("cockpit off (" .. why .. ")" .. (ok and "" or (" ERROR " .. tostring(err))))
	bump()
end

local function followedEntity()
	local ok, fe = pcall(getFollow)
	if not ok or fe == nil then return nil end
	local okE, e = pcall(function() return fe[1] end)
	return okE and e or nil
end

--- One release call (stage 1..3) at the view `v` (or the current one), then that view set again.
local function releaseCall(stage, v)
	local name = RELEASE_CALLS[stage]
	local x, y, d, a, p = cam.safeView(v, world.mapBounds())
	if x == nil then return end
	local ok, err = pcall(function()
		if name == "focusPosition" then
			local z = world.groundAt ~= nil and world.groundAt(x, y) or 0
			api.gui.camera.focusPosition(api.type.Vec3f.new(x, y, cam.finite(z) and z or 0), d)
		elseif name == "setManualCamera" then
			api.gui.camera.setManualCamera(api.type.Vec2f.new(x, y), d)
		else
			api.gui.camera.leaveFollowCameraCockpit()
		end
	end)
	if not ok then core.log("follow release " .. name .. " ERROR " .. tostring(err)) end
	setView({ x = x, y = y, d = d, a = a, p = p }, true, "release")
end

--- Ends a follow we started: setCameraData alone keeps following (see the header), so the release runs the
--- staged calls, checked in D.step. keep: the view to stay at (default: the current one).
local function releaseFollow(why, keep)
	local e = S.follow
	if e == nil then return end
	S.follow = nil
	local v = keep or readView()
	S.release = { entity = e, stage = 1, frames = 0, view = v, why = why }
	core.log("follow off (" .. why .. ") followEntity=" .. tostring(followedEntity()))
	if v ~= nil then releaseCall(1, v) end
	if keep == nil then S.last = nil end
	bump()
end

--- Each frame while a release runs: done when getFollowEntity no longer returns our entity; else the next call
--- after RELEASE_FRAMES frames; after the last call, logged and given up (the player's own camera move ends it).
--- moving: our own move (glide / drift / orbit) sets the view this frame anyway, so a call doesn't re-set it.
local function releaseStep(moving)
	local r = S.release
	r.frames = r.frames + 1
	if r.frames < RELEASE_FRAMES then return end
	if followedEntity() ~= r.entity then
		core.log("follow released by " .. RELEASE_CALLS[r.stage] .. " (" .. r.why .. ")")
		S.release = nil
		return
	end
	if r.stage >= #RELEASE_CALLS then
		core.log("follow still on after every release call (" .. r.why .. ")")
		S.release = nil
		setStatus(_("The camera still follows. Move the camera to stop it."))
		return
	end
	r.stage = r.stage + 1
	r.frames = 0
	local v = (not moving and S.last) or r.view or readView()
	releaseCall(r.stage, moving and readView() or v)
end

local function stopFollow(why)
	releaseFollow(why, nil)
end

-- Round 16 (user: "Is there any way to do the orbiting with the nice movement of Aerials?"): the manual orbit
-- turns around a fixed centre, so the ground under its look-at point never changes (the tours' jolts came from a
-- moving centre over terrain, findings map-camera.md "Tour eye jolts from the game's centre"); what it lacked is
-- the tours' eased start and end: it started and stopped at full speed. Its speed now eases in over
-- ORBIT_EASE_MS, and the button lets it ease out; an "eye smoothness (orbit)" line at its end measures it.
local ORBIT_EASE_MS = 1500

--- The orbit's speed factor (0..1) at `now`, nil once it has slowed to a stop.
local function orbitFactor(now)
	S.orbitT0 = S.orbitT0 or now
	local f = cam.ease((now - S.orbitT0) / ORBIT_EASE_MS)
	if S.orbitOut ~= nil then
		local u = (now - S.orbitOut) / ORBIT_EASE_MS
		if u >= 1 then return nil end
		f = f * (1 - cam.ease(u))
	end
	return f
end
D.ORBIT_EASE_MS = ORBIT_EASE_MS

local function stopOrbit(why)
	if not S.orbit then return end
	S.orbit = false
	S.orbitT0, S.orbitOut = nil, nil
	S.endWhy = why
	core.log("orbit off (" .. why .. ")")
	if S.orbitSmooth ~= nil then smoothLine("orbit", S.orbitSmooth) end
	S.orbitSmooth = nil
	bump()
end

local function stopWander(why)
	if S.wander == nil then return end
	S.wander = nil
	S.eye = nil
	S.endWhy = why
	core.log("wander off (" .. why .. ")")
	smoothSegment("wander")
	smoothEnd()
	bump()
end

local function stopTour(why)
	if S.tour == nil then return end
	S.tour = nil
	S.hop = nil
	S.flight = nil
	S.leaving = nil
	S.eye = nil
	if S.wander ~= nil and not S.wander.manual then S.wander = nil end
	S.endWhy = why
	core.log("tour off (" .. why .. ")")
	smoothSegment(S.smoothWhat == "wander" and "wander" or "tour")
	smoothEnd()
	pcall(D.onTourHide, false)
	bump()
end

--- The tour off (the pause-key escape while the UI is hidden, pm_hud): the window and the UI show again.
D.stopTour = stopTour

--- Round 11: the back of our view tool's action (a right click, pm_hud H.onBack): the automated camera moves
--- (tour, Wander, Orbit) end; a follow or the cockpit stays. True when one was running. (Round 13: the smooth
--- camera that also ended here is removed.)
function D.stopMoves(why)
	local any = S.tour ~= nil or S.wander ~= nil or S.orbit
	stopTour(why)
	stopOrbit(why)
	stopWander(why)
	return any
end

--- Everything off: the window closed, the pause menu, a new game. Leaves the cockpit; a follow is released.
function D.stopAll(why)
	-- round 15 DEV: a cutscene can't be stopped by a mod; the chain plays no further flight
	if S.cutscene ~= nil and S.cutscene.kind == "fly" and S.cutscene.stopWhy == nil then
		S.cutscene.stopWhy = why
		core.log("cutscene fly: no further flight (" .. tostring(why) .. ")")
	end
	stopTour(why)
	stopOrbit(why)
	stopWander(why)
	leaveCockpit(why)
	stopFollow(why)
	S.hop = nil
	S.flight = nil
	S.leaving = nil
	S.last = nil
	S.subject = nil
	S.lastJump = nil
	S.status = nil
	S.shotAnchor = nil
	world.clearCache()
	bump()
	-- round 16: the pause menu, a new game, the window closing: no settle
	S.settle = nil
	-- round 20: the pause menu pauses on purpose and a new game has its own speed: no watch puts a speed back
	if why == "pause menu" or why == "new game" then S.speedWatch = nil end
end

local function startFollow(subject, jump)
	-- The entity may have gone since the pick (vehicle sold, person arrived) and its id may be reused: check it
	-- is still that kind of thing right before the call (world.alive: exists + its component, not in a depot).
	if not world.alive(subject) then
		core.log("followEntity skipped: entity " .. tostring(subject.entity) .. " gone")
		return false
	end
	local ok, err = pcall(api.gui.camera.followEntity, subject.entity, jump == true)
	if not ok then
		core.log("followEntity ERROR " .. tostring(err))
		return false
	end
	S.follow = subject.entity
	resetShotAnchor("follow")
	S.release = nil -- a new follow replaces whatever an earlier release was checking
	S.last = nil
	bump()
	return true
end

-- Status texts per subject kind when the map has none (shown in the window).
local function noneText(kind)
	local t = {
		vehicle = _("No vehicles on the map."),
		train = _("No trains running."),
		road = _("No buses, trucks or trams running."),
		plane = _("No aircraft in service."),
		ship = _("No ships running."),
		person = _("No people walking right now."),
		station = _("No stations yet."),
		town = _("No towns on this map."),
		industry = _("No industries on this map."),
		longest = _("No trains running."),
		bridge = _("No train on a bridge right now."),
		water = _("No train or road vehicle crossing water right now."),
		passing = _("No two trains passing each other right now."),
		tunnel = _("No train at a tunnel portal right now."),
		approach = _("No aircraft landing or taking off right now."),
		rush = _("No busy street right now."),
		skyline = _("No towns on this map."),
		viewpoint = _("No hill overlooking a town found."),
		departure = _("No train standing at a platform right now."),
		oldest = _("No vehicles on the map."),
		fastest = _("No train or road vehicle moving right now."),
		saved = _("No saved views yet."),
		any = _("Nothing to show on this map yet."),
	}
	return t[kind] or _("Nothing found.")
end

---------------------------------------------------------------------------
-- Look calibration and framing

--- The look offset (camera angle -> look heading): measured once per session from the current camera
--- (getCameraData angle, getEye, getCenter; any view that isn't straight down will do), else 0.
lookOffset = function()
	if S.lookOffset ~= nil then return S.lookOffset end
	local ok, off = pcall(function()
		local d = getCam()
		local e, c = api.gui.camera.getEye(), api.gui.camera.getCenter()
		return cam.measureLookOffset(d.w, e.x, e.y, c.x, c.y)
	end)
	if ok and off ~= nil then
		S.lookOffset = off
		core.log(string.format("look calibrated: look heading = camera angle %+.3f rad", off))
		return off
	end
	return 0
end
D.lookOffset = lookOffset

--- Keeps a low view's eye above the ground under it (a hill between the eye and the subject): raises the
--- pitch (cam.clearPitch). Two height reads per framed view, never per frame.
local function clear(v)
	if v == nil or v.p > 0.6 then return v end
	local gc = ground(v.x, v.y)
	if gc == nil then return v end
	local ex, ey = cam.eyeXY(v, lookOffset())
	local ge = ground(ex, ey)
	if ge ~= nil then v.p = cam.clearPitch(v.d, v.p, gc, ge, 8) end
	return v
end

--- A photographer's framing ({ x, y, d, p, look }, pm_shots.lua) as a camera view.
local function framingView(f)
	return { x = f.x, y = f.y, d = f.d, a = cam.angleFor(f.look, lookOffset()), p = f.p }
end

--- The target view of a subject (nil for one that is followed instead). tourRange: framed for the tour.
local function subjectView(s, tourRange)
	if s.airborne then return nil end
	-- a saved view (round 8): exactly as the player saved it
	if s.view ~= nil then return { x = s.view.x, y = s.view.y, d = s.view.d, a = s.view.a, p = s.view.p } end
	if s.framing ~= nil then return clear(framingView(s.framing)) end
	if tourRange ~= nil then return clear(cam.tourFrame(s.kind, s.x, s.y, world.rnd, tourRange)) end
	return clear(cam.frame(s.kind, s.x, s.y, world.rnd()))
end

--- Jump to a random / interesting subject of `kind` ("any": a random kind, world.pick). Returns true when the
--- camera moved.
function D.jump(kind)
	stopTour("jump")
	stopWander("jump")
	leaveCockpit("jump")
	local s = world.pick(kind)
	if s == nil then
		core.log("jump " .. kind .. ": none")
		setStatus(noneText(kind))
		return false
	end
	if s.follow then S.subject = s end
	S.lastJump = s -- round 13 DEV: the orbit cutscene's subject (any kind)
	resetShotAnchor("jump")
	local v = subjectView(s)
	-- round 17: a subject shown before (s.variant, pm_world's variety bag) or a view equal to the last jump's
	-- gets another perspective of it (pm_variety.distinct)
	local k = 0
	if v ~= nil then
		v, k = variety.distinct(v, s.variant, S.lastJumpView)
		if k > 0 then v = clear(v) end
	end
	if variety.INTERESTING[s.poolKind or kind] then
		core.log(string.format("interesting pick %s #%d of %d, view variant %d", tostring(s.poolKind or kind),
			s.poolN or 1, s.poolM or 1, k))
	end
	S.lastJumpView = v ~= nil and { x = v.x, y = v.y, d = v.d, a = v.a, p = v.p } or nil
	local moved
	if v == nil then
		S.follow = nil -- followEntity on the new subject replaces the old follow
		moved = startFollow(s, true)
		core.log(string.format("jump %s (%s) entity=%s airborne: follow", kind, tostring(s.why), tostring(s.entity)))
	else
		releaseFollow("jump", v)
		moved = setView(v, false, "jump")
		core.log(string.format("jump %s (%s) entity=%s kind=%s view=%s", kind, tostring(s.why), tostring(s.entity),
			s.kind, cam.viewText(v)))
		-- a fast vehicle leaves a static frame at once: follow it at the framed distance and angle. Round 20 (user:
		-- "jump to subject should auto follow"): every vehicle or person of a plain jump too; the photographer's
		-- framings (s.framing: a bridge, a tunnel portal, an approach) wait for their subject at a spot, so stay still
		local follow = s.followShot or (s.follow and s.framing == nil)
		if moved and follow and startFollow(s, false) then
			setView(v, true, "jump")
			S.last = nil
			core.log("follow on entity=" .. tostring(s.entity) .. " (" .. tostring(s.why) .. ")")
		end
	end
	setStatus(nil)
	return moved
end

--- A horizon shot (cam.HORIZON_SHOTS): the eye above the anchor's centre (round 14: cam.shotAnchor) at the shot's height over the ground
--- there, nearly level, the centre pushed ahead; the ground under the new centre read once to correct the
--- height (two getHeightAt). Clamped by the zoom limit: logged.
local function horizonView(cur, key)
	local off = lookOffset()
	local v = cam.horizonShot(cur, key, off, 0)
	if v == nil then return nil end
	local ge, gc = ground(cur.x, cur.y), ground(v.x, v.y)
	local clamped, want
	if ge ~= nil and gc ~= nil then
		v, clamped, want = cam.horizonShot(cur, key, off, ge - gc)
	else
		v, clamped, want = cam.horizonShot(cur, key, off, 0)
	end
	if clamped then
		core.log(string.format("horizon clamped by zoom limit d=%.0f p=%.3f (wanted d=%.0f p=%.3f)", v.d, v.p, want,
			cam.HORIZON_SHOTS[key].p))
	end
	return v
end

--- A shot preset around the shot anchor (round 14: cam.shotAnchor; the centre and angle the first shot of a run
--- started from, so switching between presets always comes back to the same view; horizon shots: see
--- horizonView).
function D.shot(key)
	stopTour("shot")
	stopWander("shot")
	local cur = readView()
	-- a followed vehicle moves the centre on its own: no anchor to keep while following
	if S.follow ~= nil then resetShotAnchor("follow") end
	local anchor, why = cam.shotAnchor(S.shotAnchor, cur)
	if anchor == nil then return end
	local base = { x = anchor.x, y = anchor.y, d = cur.d, a = anchor.a, p = cur.p }
	local v
	if cam.HORIZON_SHOTS[key] ~= nil then
		v = horizonView(base, key)
	else
		v = cam.shot(base, key)
	end
	if v == nil then return end
	core.log(string.format("shot anchor %s (%s) %.1f,%.1f a=%.3f", why == "kept" and "kept" or "new", why, anchor.x,
		anchor.y, anchor.a))
	if setView(v, false, "shot") then
		core.log("shot " .. key .. " view=" .. cam.viewText(v))
		handBack("shot " .. key)
		-- what the camera shows now (the clamps setCam applies: on the map, the angle wrapped)
		local x, y, __, a = cam.safeView(v, world.mapBounds())
		S.shotAnchor = { anchor = anchor, sent = { x = x or v.x, y = y or v.y, a = a or v.a } }
	end
	if S.follow ~= nil then S.last = nil end -- the follow camera moves the centre on its own
	bump()
end

function D.toggleOrbit()
	if S.orbit then
		-- round 16: the button lets the orbit slow to a stop (ORBIT_EASE_MS); a second press stops it at once
		if S.orbitOut == nil and S.orbitT0 ~= nil then
			S.orbitOut = world.nowMs()
			core.log("orbit slowing to a stop (button)")
			bump()
		else
			stopOrbit("button")
		end
		return
	end
	-- round 13 DEV prototype: with the DEV mod on, Orbit after a jump plays an orbit cutscene attached to that
	-- subject (pm_cutscene C.playOrbit; TESTING.md CB2); round 16: else around a static anchor at the view's
	-- centre when the view is close (the file's orbit is 130 m out)
	-- round 17 (user: "Does Orbit always orbit the same thing now?"): the jumped-to subject only while it is still
	-- in the middle of the view (D.orbitTarget); a stale one is dropped, and the DEV cutscene orbit takes a static
	-- anchor only right at the centre (0842 orbited one 237 m off every time).
	if S.cutscene ~= nil then return end
	local target = D.orbitTarget()
	if target == "centre" then S.lastJump = nil end
	if cutscene.devOn() then
		if target == "subject" and S.lastJump ~= nil and D.cutsceneOrbit(S.lastJump) then
			setStatus(_("Orbiting the subject you jumped to."))
			return
		end
		if target == "centre" and D.cutsceneOrbitHere ~= nil and D.cutsceneOrbitHere() then
			setStatus(_("Orbiting the middle of the view."))
			return
		end
	end
	switching(function()
		stopWander("orbit")
		S.orbit = true
		S.orbitT0, S.orbitOut = nil, nil
		S.orbitSmooth = F.newSmooth()
		S.last = nil
		core.log("orbit on (" .. target .. ")")
	end)
	setStatus(target == "subject" and _("Orbiting the subject you jumped to.") or _("Orbiting the middle of the view."))
end

-- Round 17: the jumped-to (or followed) subject counts as what Orbit circles while it is within this share of the
-- view's distance (at least ORBIT_SUBJECT_MIN m) of the view's centre; else Orbit circles the middle of the view.
local ORBIT_SUBJECT_SHARE, ORBIT_SUBJECT_MIN = 0.15, 30
D.ORBIT_SUBJECT_SHARE, D.ORBIT_SUBJECT_MIN = ORBIT_SUBJECT_SHARE, ORBIT_SUBJECT_MIN

--- What Orbit would circle now: "subject" (the followed / jumped-to subject, still in the middle) or "centre".
function D.orbitTarget()
	local s = S.follow ~= nil and S.subject or S.lastJump
	if s == nil then return "centre" end
	local cur = readView()
	if cur == nil then return "centre" end
	local ok, x, y = pcall(world.subjectPosition, s)
	if not ok then x, y = s.x, s.y end
	if type(x) ~= "number" or type(y) ~= "number" then return "centre" end
	local r = math.max(ORBIT_SUBJECT_MIN, ORBIT_SUBJECT_SHARE * (cur.d or 0))
	if (x - cur.x) ^ 2 + (y - cur.y) ^ 2 <= r * r then return "subject" end
	return "centre"
end

--- Follow on (the last vehicle / person subject) or off.
function D.toggleFollow()
	if S.follow ~= nil then stopFollow("button") return end
	local s = S.subject
	if s == nil or not world.alive(s) then
		S.subject = nil
		setStatus(_("Jump to a vehicle or a person first."))
		return
	end
	stopTour("follow")
	stopWander("follow")
	if startFollow(s, false) then core.log("follow on entity=" .. tostring(s.entity)) end
	setStatus(nil)
end

--- Cockpit view of the last vehicle subject, or leave it.
function D.toggleCockpit()
	if S.cockpit ~= nil then leaveCockpit("button") return end
	local s = S.subject
	-- world.alive right before the call: a removed vehicle's id may already belong to another entity.
	if s == nil or s.kind == "person" or not world.alive(s) then
		S.subject = nil
		setStatus(_("Jump to a vehicle first."))
		return
	end
	stopTour("cockpit")
	stopOrbit("cockpit")
	stopWander("cockpit")
	local ok, err = pcall(api.gui.camera.enterFollowCameraCockpit, s.entity)
	if not ok then
		core.log("cockpit ERROR " .. tostring(err))
		return
	end
	S.cockpit = s.entity
	resetShotAnchor("cockpit")
	S.follow = nil
	S.last = nil
	core.log("cockpit on entity=" .. tostring(s.entity))
	setStatus(nil)
end

--- The follow / cockpit camera ended by itself (base event "stoppedFollowAction", free_cam_options.tl).
function D.followEnded()
	if S.cockpit ~= nil or S.follow ~= nil then
		core.log("stoppedFollowAction: follow / cockpit ended by the game")
		-- as the base FreeCamTool does on this event (free_cam_options.tl:26-47): leave the cockpit camera
		if S.cockpit ~= nil then pcall(api.gui.camera.leaveFollowCameraCockpit) end
		S.cockpit = nil
		S.follow = nil
		S.last = nil
		bump()
	end
	S.release = nil
end

---------------------------------------------------------------------------
-- Bookmarks (the list itself lives in pm_window.lua, which saves it)

function D.currentView()
	return readView()
end

function D.goTo(view, why)
	stopTour(why or "view")
	stopWander(why or "view")
	leaveCockpit(why or "view")
	releaseFollow(why or "view", view)
	if setView(view, false, "view") then core.log("view " .. tostring(why) .. " " .. cam.viewText(view)) end
	bump()
end

---------------------------------------------------------------------------
-- Tour

function D.setTourChoice(choice)
	S.tourChoice = choice
	if S.tour ~= nil then S.tour.every = cam.tourSeconds(choice) * 1000 end
	bump()
end

--- A tour source checkbox (cam.TOUR_SOURCES key). Several may be ticked; unticking the last one is refused
--- (the box shows ticked again, a status line says why). A running tour uses the new set from its next hop.
function D.setTourSource(key, on)
	if not cam.toggleSet(S.tourSources, cam.TOUR_SOURCES, key, on) then
		setStatus(_("Keep at least one ticked."))
		return
	end
	core.log("tour sources " .. table.concat(cam.ticked(S.tourSources, cam.TOUR_SOURCES), ","))
	bump()
end

--- A flight subject checkbox (cam.FLIGHT_SUBJECTS key); the last one can't be unticked. Used from the next
--- waypoint on.
function D.setFlightSubject(key, on)
	if not cam.toggleSet(S.flightSubjects, cam.FLIGHT_SUBJECTS, key, on) then
		setStatus(_("Keep at least one ticked."))
		return
	end
	core.log("flight subjects " .. table.concat(cam.ticked(S.flightSubjects, cam.FLIGHT_SUBJECTS), ","))
	bump()
end

--- The flight leg length (index into cam.LEG_SECONDS); a running flight keeps its leg, the next one uses it.
function D.setLegChoice(choice)
	S.legChoice = choice
	bump()
end

--- Tour mode (preset): sets the range choices of its preset; a running tour switches at its next hop.
local function continuous(mode) return mode == "place" or mode == "wander" end

function D.setTourMode(mode)
	if cam.PRESETS[mode] == nil then return end
	S.tourMode = mode
	S.rangeSel = cam.preset(mode)
	-- a running tour switches at its next hop; "This place" and "Wander" need their place, so they start with the
	-- next tour (and a running one of them keeps its own mode)
	if S.tour ~= nil and not continuous(mode) and not continuous(S.tour.mode) then S.tour.mode = mode end
	core.log("tour mode " .. mode)
	bump()
end

--- Round 22: the Tour tab's choices set the mode its Start plays (cam.tourModeOf) and that mode's range preset; a
--- running tour keeps its own.
local function tourTabChanged(what)
	S.rangeSel = cam.preset(cam.tourModeOf(S.tourStyle, S.tourWhere, S.tourFlights))
	core.log("tour tab " .. what .. ": style=" .. S.tourStyle .. " where=" .. S.tourWhere .. " flights="
		.. tostring(S.tourFlights))
	bump()
end

local function oneOf(list, v)
	for __, k in ipairs(list) do if k == v then return true end end
	return false
end

function D.setTourStyle(style)
	if not oneOf(cam.TOUR_STYLES, style) then return end
	S.tourStyle = style
	tourTabChanged("style")
end

function D.setTourWhere(where)
	if not oneOf(cam.TOUR_WHERES, where) then return end
	S.tourWhere = where
	tourTabChanged("where")
end

function D.setTourFlights(on)
	S.tourFlights = on == true
	tourTabChanged("flights")
end

function D.setAerialWhere(where)
	if not oneOf(cam.AERIAL_WHERES, where) then return end
	S.aerialWhere = where
	core.log("aerial where " .. where)
	bump()
end

--- Wander across the map / over the saved views: seconds around each place (index into cam.STAY_SECONDS); a
--- running tour uses it from the next place on.
function D.setStayChoice(choice)
	S.stayChoice = choice
	if S.tour ~= nil and S.tour.roam then S.tour.stayMs = cam.staySeconds(choice) * 1000 end
	bump()
end

--- One range choice (key pf / pt / df / dt, index 1..3).
function D.setRange(key, idx)
	if S.rangeSel[key] == nil then return end
	S.rangeSel[key] = idx
	bump()
end

--- Aerials look (cam.AERIAL_LOOKS): "down", "horizon" or "high"; used from the next flight leg on.
function D.setAerialLook(look)
	for __, k in ipairs(cam.AERIAL_LOOKS) do
		if k == look then
			S.aerialLook = look
			core.log("aerial look " .. look)
			bump()
			return
		end
	end
end

--- "Look returns to the path": the mouse-look offset decays back to the flight's own view.
function D.setLookReturn(on)
	S.lookReturn = on == true
	bump()
end

function D.setKenBurns(on)
	S.kenBurns = on == true
	bump()
end

function D.setTourLabels(on)
	S.tourLabels = on == true
	bump()
end

function D.setTourPause(on)
	S.tourPause = on == true
	bump()
end

--- "This place": the area's radius (index into pm_place.AREAS); a running place tour keeps its plan.
function D.setAreaChoice(choice)
	S.areaChoice = choice
	bump()
end

--- The next subject of a subject source (cam.SOURCE_KINDS[source], cycled from where it stopped; kinds with
--- nothing on the map skipped). nil, nil when none of its kinds has anything.
local function tourNextSubject(source)
	local kinds = cam.SOURCE_KINDS[source] or {}
	local n = #kinds
	for __ = 1, n do
		S.tour.idx[source] = cam.tourNext(S.tour.idx[source] or math.floor(world.rnd() * n), n)
		local kind = kinds[S.tour.idx[source]]
		local s = world.pick(kind)
		if s ~= nil and not s.airborne then return kind, s end
	end
	return nil, nil
end

--- The next saved view of the "views" tour (list order, looping; the list may have changed since the last hop:
--- the index wraps), as a fresh table. nil when there are none.
local function tourNextView()
	local okL, list = pcall(D.viewsProvider)
	if not okL or type(list) ~= "table" or #list == 0 then return nil, nil end
	S.tour.vidx = cam.tourNext(S.tour.vidx, #list)
	local b = list[S.tour.vidx]
	return { x = b.x, y = b.y, d = b.d, a = b.a, p = b.p }, b.id
end

--- What the next hop starts from: the drift still running out, or the current view (static, with the ground
--- under its centre as its reference: that is where the game has its eye now).
local function hopFrom()
	if S.leaving ~= nil then return S.leaving end
	return withGround(readView())
end

--- The view a hop start stands for at its own start (a drifting place at its s0).
local function staticOf(from)
	return from.base ~= nil and F.kbView(from.base, from.rates, from.s0 or 0) or from
end

--- The flight's planned view (with its reference ground) at `dist` m along the path at flight time t (s); dt nil:
--- no smoothing (the start). Round 7 (eye space): the eye flies at the altitude above the ground a little ahead of
--- it (smoothed, so it climbs before a hill), looking at the path ahead (pitch towards the smoothed ground there)
--- or, look "horizon", along its heading nearly level; F.solveEye finds where that look meets the real ground (and
--- keeps the centre on the map). The player's mouse look (S.look) turns / tilts / zooms the planned view.
local function flightView(fl, dist, t, dt, out, noLook)
	local fly = F.FLY
	local horizon = fl.look == "horizon"
	local ex, ey, hx, hy = F.pathPoint(fl.path, dist)
	if ex == nil then return nil end
	local ge = ground(ex + hx * fly.groundAhead, ey + hy * fly.groundAhead) or fl.ge or 0
	fl.ge = dt ~= nil and F.smoothTo(fl.ge, ge, dt, fly.smooth) or ge
	local ez = fl.ge + F.altitude(t, fl.phase) + (horizon and (F.HORIZON.alt - fly.alt) or 0)
	local h, p, d
	if fl.look == "high" then
		-- round 13: the High look (pm_flight.HIGH): about 1 km up, the look-at point on the sea 1.6 km+ out, where the
		-- game's centre ignores the ground; the heading towards the path that far ahead
		ez, d = F.highPose(fl.ge, t, fl.phase)
		p = F.HIGH.elev
		local cx, cy = F.pathPoint(fl.path, dist + d * math.cos(p))
		if cx == nil then cx, cy = ex + hx, ey + hy end
		h = cam.atan2(cy - ey, cx - ex)
	elseif horizon then
		h = cam.atan2(hy, hx)
		p = F.HORIZON.pitch
		d = F.horizonAhead(ez - fl.ge) / math.cos(p)
	else
		local cx, cy = F.pathPoint(fl.path, dist + fly.lookAhead)
		if cx == nil then return nil end
		local gc = ground(cx, cy) or fl.gc or fl.ge
		fl.gc = dt ~= nil and F.smoothTo(fl.gc, gc, dt, fly.smooth) or gc
		local dx, dy = cx - ex, cy - ey
		local L = math.max(1, math.sqrt(dx * dx + dy * dy))
		h = cam.atan2(dy, dx)
		p = cam.clamp(cam.atan2(ez - fl.gc, L), fly.pMin, fly.pMax)
		d = L / math.cos(p)
	end
	local v = F.viewOfPose(ex, ey, ez, h, p, d, lookOffset(), out)
	if S.look ~= nil and not noLook then F.applyLook(v, S.look) end
	return v
end

-- Round 22: Aerials over the saved views: the drone flies from one saved view's centre to the next in list order,
-- looping (S.tour.route = { pts = { { x, y, id } }, i = the last one flown to }). A view closer than ROUTE_MIN_M
-- to the last waypoint is passed over (two views of one place); one that needs a turn sharper than FLY.maxTurn
-- gets a turning waypoint ROUTE_TURN_M ahead first, turned by maxTurn towards it (a spline through a turn back
-- would stop the drone and reverse it). No view far enough (a single one): a waypoint of the map's candidates.
local ROUTE_MIN_M, ROUTE_TURN_M = 400, 800

--- The route's next saved view at least ROUTE_MIN_M from `last` (nil: any), its index; nil when none is. Not
--- consumed (the caller sets route.i when it flies to it).
local function routePeek(route, last)
	local n = #route.pts
	for k = 1, n do
		local i = (route.i + k - 1) % n + 1
		local p = route.pts[i]
		if last == nil or (p.x - last.x) ^ 2 + (p.y - last.y) ^ 2 >= ROUTE_MIN_M * ROUTE_MIN_M then return p, i end
	end
	return nil, nil
end

--- The saved views as a route (their centres, list order), nil when there are none.
local function newRoute()
	local okL, list = pcall(D.viewsProvider)
	if not okL or type(list) ~= "table" then return nil end
	local pts = {}
	for __, b in ipairs(list) do
		if type(b) == "table" and cam.finite(b.x) and cam.finite(b.y) then pts[#pts + 1] = { x = b.x, y = b.y, id = b.id } end
	end
	return #pts > 0 and { pts = pts, i = 0 } or nil
end

--- The route's next waypoint after `last` (flying `heading`), inside the look's edge margin; nil: none far enough.
local function routeWaypoint(route, last, heading, look)
	local p, i = routePeek(route, last)
	if p == nil then return nil end
	local want = cam.atan2(p.y - last.y, p.x - last.x)
	local turn = cam.angleDiff(heading, want)
	local wp
	if math.abs(turn) > F.FLY.maxTurn then
		local h = heading + (turn > 0 and 1 or -1) * F.FLY.maxTurn
		wp = { x = last.x + math.cos(h) * ROUTE_TURN_M, y = last.y + math.sin(h) * ROUTE_TURN_M,
			why = "turning to saved view " .. tostring(p.id) }
	else
		route.i = i
		wp = { x = p.x, y = p.y, why = "saved view " .. tostring(p.id) }
	end
	local ib = F.inner(world.mapBounds(), F.viewMargin(look))
	if ib ~= nil then wp.x, wp.y = cam.clamp(wp.x, ib[1], ib[3]), cam.clamp(wp.y, ib[2], ib[4]) end
	return wp
end

--- Waypoints are added while the drone flies, so the path always reaches past the look-ahead point. One
--- candidate list per waypoint (about once a minute), never per frame.
local function extendPath(fl, dist, maxAdd)
	local fly = F.FLY
	local guard = 0
	while F.pathLength(fl.path) - dist < fly.lookAhead + fly.legMin and guard < (maxAdd or 4) do
		guard = guard + 1
		local n = #fl.path
		local last, prev = fl.path[n], fl.path[n - 1]
		local heading = prev ~= nil and cam.atan2(last.y - prev.y, last.x - prev.x) or fl.heading
		-- the leg's candidates, looked up once at its start (startFlight): no scan while flying
		-- round 16: the look's edge margin (no view out past the map edge) and the recent areas (no repeats)
		local wp = fl.route ~= nil and routeWaypoint(fl.route, last, heading, fl.look) or nil
		wp = wp or F.nextWaypoint(last, heading, fl.cands or {}, world.mapBounds(), world.rnd, F.viewMargin(fl.look))
		fl.path[n + 1] = wp
		F.rememberArea(wp.x, wp.y)
		core.log(string.format("tour flight waypoint %.0f,%.0f (%s)", wp.x, wp.y, tostring(wp.why)))
	end
end

--- Where a new Aerials leg starts: a candidate of the ticked flight subjects at least NEW_AREA_M away (the
--- farthest of a few random ones), else a random point of the inner map; nil without map bounds. Round 11:
--- heading (the drone's, when the glide leaves a flight) prefers one ahead, so the glide that leaves the flying
--- drone at its speed never has to turn back through a stop.
local NEW_AREA_M = 3000
local function newArea(fv, cands, heading)
	-- round 16: inside the look's edge margin; an area shown lately only when nothing else is left
	local ib = F.inner(world.mapBounds(), F.viewMargin(S.aerialLook))
	local best, bestD = nil, nil
	for __, c in ipairs(cands or {}) do
		if F.inside(ib, c.x, c.y) then
			local d = math.sqrt((c.x - fv.x) ^ 2 + (c.y - fv.y) ^ 2)
			-- a random far one, not always the farthest; one ahead of the drone first
			local ahead = heading ~= nil and d > 0
				and math.cos(cam.angleDiff(heading, cam.atan2(c.y - fv.y, c.x - fv.x))) > 0
			local score = (d >= NEW_AREA_M and 2 or 0) + (ahead and 1 or 0) + world.rnd()
				- (F.nearRecent(c.x, c.y) and 3 or 0)
			if bestD == nil or score > bestD then best, bestD = c, score end
		end
	end
	if best ~= nil then
		F.rememberArea(best.x, best.y)
		return { x = best.x, y = best.y, why = best.why }
	end
	if ib == nil then return nil end
	local x, y = ib[1] + (ib[3] - ib[1]) * world.rnd(), ib[2] + (ib[4] - ib[2]) * world.rnd()
	F.rememberArea(x, y)
	return { x = x, y = y, why = "random point" }
end

--- Round 11: the flight's planned view (an eye-centre elevation, as the flight sends it) at flight time t (s since
--- its glide began; the drone flies from then on), written into `out`; nil off the path. Its own clock (fl.lastT)
--- gives the height smoothing its step. No mouse look (the glide adds it once).
local flightDist
local function flightAt(fl, t, out)
	local dist = flightDist(fl, t)
	extendPath(fl, dist)
	local dt = fl.lastT ~= nil and math.max(0, t - fl.lastT) or nil
	fl.lastT = t
	return flightView(fl, dist, t, dt, out, true)
end

--- Round 11: a flight as a moving hop end (pm_flight.newHop, an eye-space hop): the drone at flight time
--- t0s + tau, with the static fields of its view at t0s (what a hop start stands for: staticOf, the glide's rise,
--- the log).
local function flightEnd(fl, t0s)
	local e = flightAt(fl, t0s, {})
	if e == nil then return nil end
	e.viewAt = function(tau, out) return flightAt(fl, t0s + tau, out) end
	e.flight = fl
	return e
end

--- Starts a flight: a glide up to the flight's first view, then the drone flies on for legS seconds.
--- elsewhere: the flight starts over a new area (newArea) instead of the current place (Aerials' next legs).
--- Round 11: the drone's clock starts with the glide, which arrives on the drone already moving (the moving hop
--- end, pm_flight.newHop, with the smootherstep), and a glide that leaves a flight (the last leg, still flying)
--- leaves it at its speed: a leg after a leg flies at cruise from its first metre, and the new area's path starts
--- in the direction of the glide (no turn back).
local function startFlight(now, legS, elsewhere)
	local from = hopFrom()
	if from == nil then S.tour.nextAt = now + S.tour.every return end
	local fv = staticOf(from)
	local start = { x = fv.x, y = fv.y }
	local heading = cam.lookOf(fv.a, lookOffset())
	-- one candidate lookup per leg (round 6): the new area and every waypoint of the leg come from it
	local okC, cands = pcall(world.flightCandidates, S.flightSubjects)
	cands = okC and type(cands) == "table" and cands or {}
	local cruise = false
	local route = S.tour ~= nil and S.tour.route or nil
	if route ~= nil then
		-- round 22: over the saved views: the flight starts above the first one (a glide there), heading for the
		-- next one; it has no legs (legS nil: it flies on from view to view)
		local p, i = routePeek(route, nil)
		route.i = i
		start = { x = p.x, y = p.y }
		local q = routePeek(route, p)
		if q ~= nil then heading = cam.atan2(q.y - p.y, q.x - p.x) end
		core.log(string.format("tour flight over the saved views (%d), from view %s at %.0f,%.0f", #route.pts,
			tostring(p.id), p.x, p.y))
	elseif elsewhere then
		local prev = from.flight
		local area = newArea(fv, cands, prev ~= nil and prev.endHeading or nil)
		if area ~= nil then
			start = { x = area.x, y = area.y }
			-- on in the direction of the glide, turned a little
			local jx, jy = area.x - fv.x, area.y - fv.y
			local along = (jx * jx + jy * jy) > 1 and cam.atan2(jy, jx) or world.rnd() * cam.TWO_PI
			heading = cam.wrapAngle(along + (world.rnd() - 0.5) * 0.5)
			core.log(string.format("tour flight new area %.0f,%.0f (%s)", area.x, area.y, tostring(area.why)))
		end
		-- leaving a flying drone: this leg is at cruise from the start
		cruise = prev ~= nil
	end
	local fl = { path = { start }, heading = heading, phase = world.rnd(), look = S.aerialLook, cands = cands,
		cruise = cruise, route = route }
	fl.legMs = legS and legS * 1000 or nil
	S.look = nil -- the glide starts from the view as it is, offset included
	-- the whole leg's waypoints now (at most 12; the glide's seconds fly too), so the frames of the flight only
	-- evaluate the spline
	extendPath(fl, legS and flightDist(fl, legS + cam.GLIDE_SECONDS) or 0, 12)
	-- round 11: the glide runs in eye space (the flight's own elevations; the current view converted exactly), so
	-- it ends on the very eye the flight sends next
	local first = flightEnd(fl, 0)
	if first == nil then S.tour.nextAt = now + S.tour.every return end
	fl.glide = F.newHop(from, first, cam.GLIDE_SECONDS, 0, cam.glideBump(fv, first), true)
	fl.t0 = now
	fl.flyT0 = now + cam.GLIDE_SECONDS * 1000
	S.flight, S.hop, S.leaving = fl, nil, nil
	core.log("tour flight" .. (legS and string.format(" leg %ds", legS) or "") .. (cruise and " at cruise" or "")
		.. " from " .. cam.viewText(fv))
end

--- The distance flown t s after the flight's glide began: the speed ramps in from rest (round 11: from the glide's
--- start, so the glide arrives on a moving drone), or is at cruise from the start (a leg after a leg). A leg no
--- longer ramps out: the next glide leaves the drone flying (round 11).
flightDist = function(fl, t)
	local fly, R = F.FLY, F.FLIGHT_RAMP_S
	if fl.cruise then return fly.speed * math.max(0, tonumber(t) or 0) end
	return fly.speed * F.rampIn(t, R)
end
D.flightDist = flightDist

--- A hop to `to` (a static view): from the drift still running out (or the current view), a glide, then the
--- hold (with the Ken Burns drift when it is on, kbScale of a random tour's move).
local function startHop(now, to, logWhat, kbScale, range)
	local t = S.tour
	local from = hopFrom()
	if from == nil or to == nil then
		t.nextAt = now + t.every
		return
	end
	withGround(to) -- the reference ground of the arrival (one getHeightAt per hop)
	local toEnd = to
	local kb = ""
	if S.kenBurns then
		local rates = F.kbRates(world.rnd, kbScale, lookOffset())
		toEnd = { base = to, rates = rates }
		kb = string.format(" kb=%s x%.1f", rates.move, rates.speed)
	end
	-- round 11: leaving a flying drone (from.viewAt), the glide blends with the smootherstep
	S.hop = { hop = F.newHop(from, toEnd, cam.GLIDE_SECONDS, t.every / 1000, cam.glideBump(staticOf(from), to),
		from.viewAt ~= nil),
		t0 = now, range = range }
	S.flight, S.leaving = nil, nil
	core.log(string.format("tour %s to=%s%s", logWhat, cam.viewText(to), kb))
end

--- "This place": the subjects near the place, looked up again every pm_place.REFRESH_HOPS hops (vehicles and
--- people move). world.nearby is a budgeted lookup (~15 ms of vehicle reads plus the octree query), per hop at
--- most, never per frame.
local function placeSubjects(pl)
	if world.nearby == nil then return {} end
	local t0 = perf:start()
	local ok, list = pcall(world.nearby, pl.plan.x, pl.plan.y, pl.plan.r)
	perf:stop(SEC_PLACE, t0)
	if not ok then core.log("place subjects ERROR " .. tostring(list)) end
	return ok and type(list) == "table" and list or {}
end

--- The next shot of a "This place" tour (pm_place.shot): a nearby subject (its position read again if it
--- moves; one that left the area or is gone is skipped) or a random point of the area.
local function placeAdvance(now)
	local t = S.tour
	local pl = t.place
	if t.n > 1 and (t.n - 1) % P.REFRESH_HOPS == 0 then pl.subjects = placeSubjects(pl) end
	local s = P.pickSubject(pl.plan, pl.subjects, world.rnd)
	if s ~= nil and (s.moving or s.kind == "person") and world.subjectPosition ~= nil then
		local okP, x, y, z = pcall(world.subjectPosition, s)
		if okP and x ~= nil and P.inside(pl.plan, x, y, P.SUBJECT_SLACK) then
			s.x, s.y, s.z = x, y, z
		else
			s = nil
		end
	end
	local range = cam.tourRange(S.rangeSel)
	local to, target = P.shot(pl.plan, range, world.rnd, s)
	to = clear(to)
	local what = target ~= nil and string.format("place %s entity=%s", tostring(target.kind), tostring(target.entity))
		or "place point"
	startHop(now, to, what, 1, range)
end

local function tourAdvanceNow(now)
	local t = S.tour
	t.n = (t.n or 0) + 1
	if t.mode == "place" and t.place ~= nil then
		placeAdvance(now)
		return
	end
	local sources = t.sources or S.tourSources
	local flights = t.mode == "aerial" or not cam.viewsOnly(sources)
	if flights and cam.hopKind(t.mode, t.n) == "flight" then
		local t0 = perf:start()
		-- round 22: a flight along the saved views has no legs (it flies on from view to view)
		startFlight(now, t.route == nil and cam.legSeconds(S.legChoice) or nil, t.mode == "aerial" and t.n > 1)
		perf:stop(SEC_FLIGHT, t0)
		return
	end
	local to, logWhat, kbScale
	local range = cam.tourRange(S.rangeSel)
	-- the next ticked source; one with nothing this hop is skipped, the next one tried
	local skip = {}
	while to == nil do
		local src = cam.tourNextSource(sources, t.src, skip)
		if src == nil then break end
		t.src = src
		if src == "views" then
			local id
			to, id = tourNextView()
			if to ~= nil then
				logWhat = "view " .. tostring(id)
				kbScale = KB_VIEWS_SCALE
			end
		else
			local kind, s = tourNextSubject(src)
			if s ~= nil then
				if s.follow then S.subject = s end
				to = subjectView(s, range)
				logWhat = string.format("%s %s (%s) entity=%s", src, kind, tostring(s.why), tostring(s.entity))
				-- a saved view drifts like the saved-views tour's (the player's own framing stays recognisable)
				kbScale = s.view ~= nil and KB_VIEWS_SCALE or 1
			end
		end
		if to == nil then skip[src] = true end
	end
	if to == nil then
		if cam.viewsOnly(sources) then
			stopTour("no saved views")
			setStatus(_("Save a view first, or tour random subjects."))
		else
			stopTour("nothing to show")
			setStatus(_("Nothing to show on this map yet."))
		end
		return
	end
	startHop(now, to, logWhat, kbScale, range)
end

--- The tour's next hop or flight (SQPERF "tour_advance": the pick, framing and any list build or scan of it).
local function tourAdvance(now)
	local t0 = perf:start()
	tourAdvanceNow(now)
	perf:stop(SEC_ADVANCE, t0)
end

---------------------------------------------------------------------------
-- Wander (round 7, pm_flight "Wander"): a camera move around the middle of the view and a tour mode.

local WANDER_SUBJECT_SHARE = 0.6
local wanderBuf = {}

--- The wander's next look target: a nearby subject (a moving one read again; gone or out of the area: skipped)
--- for about WANDER_SUBJECT_SHARE of the targets, else a point of the area (pm_place.placePoint). Per target
--- (every F.WANDER.lookS s), never per frame: one getHeightAt, at most one position read.
local function wanderPoint(wd)
	local w = wd.w
	local n = #wd.subjects
	if n > 0 and world.rnd() < WANDER_SUBJECT_SHARE then
		local s = wd.subjects[math.floor(world.rnd() * n) + 1]
		local x, y = s and s.x, s and s.y
		if s ~= nil and (s.moving or s.kind == "person") and world.subjectPosition ~= nil then
			local okP, px, py = pcall(world.subjectPosition, s)
			x, y = okP and px or nil, okP and py or nil
		end
		if x ~= nil and P.inside(w, x, y, P.SUBJECT_SLACK) then
			return x, y, ground(x, y), s.kind
		end
	end
	local x, y = P.placePoint(w, world.rnd)
	return x, y, ground(x, y), "point"
end

-- Round 22: Wander across the map / over the saved views: the glide to the next place is longer the farther it
-- goes (cam.GLIDE_SECONDS for a short move, up to ROAM_GLIDE_MAX times it), and rises on the way (cam.glideBump).
local ROAM_GLIDE_M, ROAM_GLIDE_MAX = 3000, 2.2
-- No next place found when the Stay is over: the wander stays and tries again this much later.
local ROAM_RETRY_MS = 15000
-- Places tried for one not shown lately (pm_flight.nearRecent).
local ROAM_TRIES = 4

--- Starts a wander around the centre of `cur` (radius r, pitch pMin .. pMax); manual: the Camera tab's move (no
--- tour). The eye starts where it is: a glide (cam.GLIDE_SECONDS) eases into the moving wander path.
--- at (round 22, a wander that roams): { x, y, from (the elevation view the glide starts at), bearing (where the
--- eye starts around the place; nil: on the side the camera comes from), stayS, why }: the wander goes round
--- (at.x, at.y) instead, after a glide there that rises with the distance.
local function startWander(cur, r, pMin, pMax, manual, at)
	local off = lookOffset()
	newMove("wander")
	-- the wander plans eye-centre elevations; the current view's pitch is the game's: as an elevation view (the
	-- camera model, round 9), so the glide in starts at the eye the game shows now
	local from = at ~= nil and at.from
		or F.elevView(withGround({ x = cur.x, y = cur.y, d = cur.d, a = cur.a, p = cur.p }), S.camRes)
	local x, y, g, bearing, glideS = cur.x, cur.y, from.g, cam.lookOf(cur.a, off) + cam.PI, cam.GLIDE_SECONDS
	if at ~= nil then
		x, y = at.x, at.y
		g = ground(x, y) or from.g
		bearing = at.bearing or cam.atan2(from.y - y, from.x - x)
		local travel = math.sqrt((x - from.x) ^ 2 + (y - from.y) ^ 2)
		glideS = cam.GLIDE_SECONDS * cam.clamp(1 + travel / ROAM_GLIDE_M, 1, ROAM_GLIDE_MAX)
	end
	local w = F.newWander(x, y, r, g, pMin, pMax, world.rnd, bearing)
	if w == nil then return false end
	local bumpM = 0
	if at ~= nil then bumpM = cam.glideBump(from, F.wanderView(w, 0, 0, off, {})) end
	local subjects = {}
	if world.nearby ~= nil then
		local t0 = perf:start()
		local ok, list = pcall(world.nearby, x, y, r)
		perf:stop(SEC_PLACE, t0)
		if ok and type(list) == "table" then subjects = list end
	end
	local now = world.nowMs()
	S.wander = { w = w, t0 = now, manual = manual, subjects = subjects, nextAt = 0, from = from, glideS = glideS,
		bump = bumpM, leaveAt = at ~= nil and now + (glideS + (at.stayS or 60)) * 1000 or nil }
	S.last = nil
	core.log(string.format("wander on (%s) %.0f,%.0f r=%.0f pitch %.2f-%.2f subjects=%d%s",
		manual and "camera move" or (at ~= nil and "tour roam" or "tour"), x, y, r, pMin, pMax, #subjects,
		at ~= nil and string.format(" glide %.1fs rise %.0fm stay %ds (%s)", glideS, bumpM, at.stayS or 60,
		tostring(at.why)) or ""))
	return true
end

--- Round 22: the next place a roaming wander goes round: { x, y, bearing, why }, nil when there is none. "views":
--- the next saved view in list order (the eye starts on its side: behind its centre, as the view was framed).
--- "map": a subject of the tour's sources in turn (as the hops pick them), one not shown lately when one of
--- ROAM_TRIES picks is. Per place (a minute or so), never per frame.
local function roamPlace(t)
	if t.where == "views" then
		local v, id = tourNextView()
		if v == nil then return nil end
		return { x = v.x, y = v.y, bearing = cam.lookOf(v.a, lookOffset()) + cam.PI, why = "view " .. tostring(id) }
	end
	local best = nil
	local skip = {}
	for __ = 1, ROAM_TRIES do
		local src = cam.tourNextSource(t.sources or S.tourSources, t.src, skip)
		if src == nil then break end
		t.src = src
		local kind, s = tourNextSubject(src)
		if s == nil then
			skip[src] = true
		elseif cam.finite(s.x) and cam.finite(s.y) then
			best = { x = s.x, y = s.y, why = string.format("%s %s (%s) entity=%s", src, tostring(kind), tostring(s.why),
				tostring(s.entity)) }
			if not F.nearRecent(s.x, s.y) then break end
		end
	end
	if best ~= nil then F.rememberArea(best.x, best.y) end
	return best
end

--- Round 22: a roaming wander moves on to its next place (from: the elevation view sent last; nil: the current
--- view). False when there is no place to go.
local function roamNext(from, why)
	local t = S.tour
	if from == nil then
		local cur = readView()
		if cur == nil then return false end
		from = F.elevView(withGround({ x = cur.x, y = cur.y, d = cur.d, a = cur.a, p = cur.p }), S.camRes)
	end
	local pl = roamPlace(t)
	if pl == nil then return false end
	local range = cam.tourRange(S.rangeSel)
	t.n = (t.n or 0) + 1
	core.log("tour roam " .. t.n .. " (" .. why .. ") to " .. pl.why)
	local ok = startWander(from, P.radius(S.areaChoice), range.pMin, range.pMax, false,
		{ x = pl.x, y = pl.y, from = from, bearing = pl.bearing, stayS = t.stayMs / 1000, why = pl.why })
	-- the camera trace for the tour's first place only (a trace per place would fill the log)
	if t.n > 1 then S.trace = nil end
	return ok
end

--- One frame of the wander; false when setting the view failed.
local function wanderStep(now, dt)
	local wd = S.wander
	local t = (now - wd.t0) / 1000
	if t >= wd.nextAt then
		local x, y, g, what = wanderPoint(wd)
		F.wanderSetTarget(wd.w, t, x, y, g)
		wd.nextAt = t + F.WANDER.lookS
		if wd.w.n > 1 then eyeCheck("wander") end
		core.log(string.format("wander look at %s %.0f,%.0f", tostring(what), x, y))
	end
	if t >= (wd.smoothAt or WANDER_SMOOTH_S) then
		wd.smoothAt = t + WANDER_SMOOTH_S
		smoothSegment("wander")
	end
	local v = F.wanderView(wd.w, t, dt, lookOffset(), wanderBuf)
	local G = wd.glideS or cam.GLIDE_SECONDS
	if t < G then v = cam.lerpView(wd.from, v, t / G, wd.bump or 0, setBuf) end
	local okSet, err = sendPlanned(v, dt)
	if not okSet then
		core.log("setCameraData ERROR " .. tostring(err) .. "; camera moves stopped")
		S.last = nil
		stopTour("camera error")
		stopWander("camera error")
		return false
	end
	-- round 22: a roaming wander's Stay is over: on to the next place (the glide starts at the view just sent)
	if wd.leaveAt ~= nil and now >= wd.leaveAt and S.tour ~= nil and S.tour.roam then
		local from = { x = v.x, y = v.y, d = v.d, a = v.a, p = v.p, g = v.g }
		if not roamNext(from, "stay over") then
			wd.leaveAt = now + ROAM_RETRY_MS
			core.log("tour roam: no next place; the wander stays and tries again in " .. ROAM_RETRY_MS / 1000 .. " s")
		end
	end
	return true
end

--- The Camera tab's Wander: around the middle of the view at its current scale (pm_flight.wanderAround), until
--- the player moves the camera or clicks it again.
function D.toggleWander()
	if S.wander ~= nil and S.wander.manual then stopWander("button") return end
	local cur = readView()
	if cur == nil then return end
	switching(function()
		stopTour("wander")
		stopOrbit("wander")
		leaveCockpit("wander")
		releaseFollow("wander", cur)
		local r, pMin, pMax = F.wanderAround(cur)
		startWander(cur, r, pMin, pMax, true)
	end)
end

-- Round 13 DEV prototype (gui/pm_cutscene.lua, only with the DEV mod square_photo_mode_dev): Orbit right after a
-- jump plays a game cutscene attached to the subject; its eye is measured like a tour's ("eye smoothness
-- (cutscene)"). TESTING.md CB2.
local CUTSCENE_START_GRACE_MS, CUTSCENE_MAX_MS = 3000, 60000

local function gameSpeed()
	local ok, sp = pcall(function()
		return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED).speedup
	end)
	return ok and type(sp) == "number" and sp or nil
end

-- Round 20 (user: "game keeps pausing after coming out of cut scenes, even if it was playing before";
-- 2026-10-14_2150_r19-test): a lens shot that ended with the game running ("game speed 1 kept (the player's: 1)",
-- 22:15:46) was followed 5 s later by a play that read speed 0 (22:15:51), and from then on every end put that
-- 0 back as "the player's". Something pauses the game after the end (inferred: the Esc that skipped the cutscene;
-- the binary's CameraAction names gamePause beside OnSkipCutscene). So for SPEED_WATCH_MS after a cutscene of ours
-- ends, the speed is watched: one that changes to neither the player's speed nor what the cutscene left is put back
-- once ("cutscene end: the game speed went to ..." with the time since the end), and a play started meanwhile takes
-- the player's speed, not the read one (D.playerSpeed).
local SPEED_WATCH_MS = 2500
D.SPEED_WATCH_MS = SPEED_WATCH_MS

--- A cutscene of ours ended: `want` is the player's speed from before it, `left` the speed read at the end.
function D.watchSpeed(want, left, why)
	if type(want) ~= "number" then return end
	local now = world.nowMs()
	S.speedWatch = { want = want, left = left, t0 = now, untilMs = now + SPEED_WATCH_MS, why = why or "cutscene" }
end

--- The player's game speed: while a cutscene end is still watched, the speed from before it; else the speed now.
function D.playerSpeed()
	local w = S.speedWatch
	if w ~= nil then return w.want end
	return gameSpeed()
end

local function speedWatchStep(now)
	local w = S.speedWatch
	if S.cutscene ~= nil or now > w.untilMs then
		S.speedWatch = nil
		return
	end
	local sp = gameSpeed()
	if sp == nil or sp == w.want or sp == w.left then return end
	S.speedWatch = nil
	pcall(function() api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(w.want)) end)
	core.log(string.format("%s end: the game speed went to %s %.0f ms after the end; the player's %s back", w.why,
		tostring(sp), now - w.t0, tostring(w.want)))
end

-- Round 13 DEV: an orbit cutscene attached to the last subject jumped to (pm_cutscene C.playOrbit): "cutscene
-- orbit" lines (the first frames, then about every 2 s, at most ORBIT_LINES) with the engine eye, the subject's
-- position and their distance / bearing: the distance stays near sqrt(R^2 + H^2) when the attachment works (and
-- the subject moves with the eye when it is a vehicle); a bearing that turns with the vehicle means the offsets
-- turn with the entity (lockYaw = false).
-- The attachment is checked from the eye-subject distance once the cutscene has played ORBIT_CHECK_MS: an
-- unresolved one (the keys at their raw offsets around the map origin, the engine logging "Invalid entity for
-- attachment" every frame) is logged once and said in the status line; round 17: never ended here (the player's Esc).
local ORBIT_LINES, ORBIT_EVERY_MS, ORBIT_CHECK_MS = 16, 2000, 400
-- Round 14 (session 2026-10-14_0633_session: "a strange glitchy movement like a pulse"): the orbit's pace, the
-- eye's speed around the subject (the eye's step minus the subject's, per second) from ORBIT_PACE_FROM_MS on: an
-- even orbit keeps 2 pi R / seconds (31.4 m/s); round 13's keys (speed 1 at every key) would swing between a crawl
-- at each key and ~1.5 x that between them. The end line gives min / mean / max and the spread (rms / mean).
local ORBIT_PACE_FROM_MS = 1000

--- Round 14: the attached orbit's even pace (m/s around the subject).
function D.orbitPace()
	return 2 * math.pi * cutscene.ORBIT.radius / cutscene.ORBIT.seconds
end

local function getComp(e, name)
	return api.engine.getComponent(e, api.type.ComponentType[name])
end
local function stationCon(st)
	return api.engine.system.streetConnectorSystem.getConstructionEntityForStation(st)
end

local function cutsceneOrbit(subject)
	local anchor, how = cutscene.anchorFor(subject and subject.entity, getComp, stationCon)
	if anchor == nil then
		core.log(string.format("cutscene orbit: subject %s entity=%s not attachable (%s): the normal orbit",
			tostring(subject and subject.kind), tostring(subject and subject.entity), tostring(how)))
		return false
	end
	local speedup = D.playerSpeed()
	local ok, info = cutscene.playOrbit(anchor)
	core.log(string.format("cutscene orbit: subject %s entity=%s anchor=%s (%s) map {[%d]=%s} r=%d h=%d %d s: %s %s",
		tostring(subject.kind), tostring(subject.entity), tostring(anchor), tostring(how), cutscene.ANCHOR,
		tostring(anchor), cutscene.ORBIT.radius, cutscene.ORBIT.height, cutscene.ORBIT.seconds,
		ok and "playing," or "NOT played:", tostring(info)))
	if not ok then return false end
	S.cutscene = { t0 = world.nowMs(), seen = false, smooth = F.newSmooth(), speedup = speedup, kind = "orbit",
		subject = subject, lines = 0, nextLine = 0, dMin = math.huge, dMax = 0, verdict = nil,
		pace = { n = 0, sum = 0, sq = 0, min = math.huge, max = 0 } }
	bump()
	return true
end
D.cutsceneOrbit = cutsceneOrbit

-- Round 16 DEV (user: "Is there any way to do the orbiting with the nice movement of Aerials?"): the smooth
-- camera is a cutscene (findings environment.md: 1361 frames, d2 max 0.72 m; the attached orbit 0633: d2 max
-- 1.04 m, its pulse fixed by round 14's Auto Set Speed keys, CC3). With the DEV mod on and no subject jumped to,
-- Orbit plays the attached orbit (sqpm_orbit.lua, 120 m out, 50 m up) around the static anchor nearest to the
-- view's centre (pm_world flyCandidates: a building, tree group or other entity with a fat model instance,
-- within ORBIT_ANCHOR_R), when the view is closer than CUTSCENE_ORBIT_MAX_D (the orbit's own distance is 130 m;
-- a farther view gets the manual orbit, which keeps its distance).
-- Round 17: ORBIT_ANCHOR_R 200 -> 40 m (0842: anchors 237, 163 and 138 m off the centre were orbited: "always the
-- same thing"); a farther one leaves the manual orbit around the centre.
local CUTSCENE_ORBIT_MAX_D, ORBIT_ANCHOR_R = 450, 40

function D.cutsceneOrbitHere()
	local cur = readView()
	if cur == nil or type(world.flyCandidates) ~= "function" then return false end
	if cur.d > CUTSCENE_ORBIT_MAX_D then
		core.log(string.format("cutscene orbit: the view is %.0f m out (over %d m): the manual orbit", cur.d,
			CUTSCENE_ORBIT_MAX_D))
		return false
	end
	local okC, cands = pcall(world.flyCandidates, cur.x, cur.y, ORBIT_ANCHOR_R)
	local best, bestD = nil, math.huge
	for __, c in ipairs(okC and type(cands) == "table" and cands or {}) do
		local d = (c.x - cur.x) ^ 2 + (c.y - cur.y) ^ 2
		if d < bestD and d <= ORBIT_ANCHOR_R ^ 2 then best, bestD = c, d end
	end
	if best == nil then
		core.log(string.format("cutscene orbit: no static anchor within %d m of the view's centre %.0f,%.0f (%s): the "
			.. "manual orbit", ORBIT_ANCHOR_R, cur.x, cur.y, tostring(select(2, pcall(world.flyStatsText)))))
		return false
	end
	core.log(string.format("cutscene orbit: static anchor %s (%s) %.0f m from the view's centre", tostring(best.entity),
		tostring(best.kind), math.sqrt(bestD)))
	return cutsceneOrbit({ entity = best.entity, x = best.x, y = best.y, z = best.z or 0,
		kind = "anchor " .. tostring(best.kind) })
end

--- Round 14: one frame of the orbit's pace (the eye's motion around the subject, the subject's own taken out).
local function orbitPace(c, now, dt, ex, ey, ez, sx, sy, sz)
	local pr = c.prev
	c.prev = { ex = ex, ey = ey, ez = ez, sx = sx, sy = sy, sz = sz }
	if pr == nil or not (dt and dt > 0) or now - c.t0 < ORBIT_PACE_FROM_MS then return end
	local rx = (ex - pr.ex) - (sx - pr.sx)
	local ry = (ey - pr.ey) - (sy - pr.sy)
	local rz = (ez - pr.ez) - (sz - pr.sz)
	local v = math.sqrt(rx * rx + ry * ry + rz * rz) / dt
	if not cam.finite(v) then return end
	local p = c.pace
	p.n, p.sum, p.sq = p.n + 1, p.sum + v, p.sq + v * v
	p.min, p.max = math.min(p.min, v), math.max(p.max, v)
end
D.orbitPaceAdd = orbitPace

--- Round 14: "pace min-max mean spread" of the orbit (nil before any frame counted).
local function paceText(p)
	if p == nil or p.n < 2 then return nil end
	local mean = p.sum / p.n
	local rms = math.sqrt(math.max(0, p.sq / p.n - mean * mean))
	return string.format("pace around the subject %.1f-%.1f m/s mean %.1f spread %.0f %% (an even orbit: %.1f m/s, "
		.. "spread 0)", p.min, p.max, mean, mean > 0 and 100 * rms / mean or 0, D.orbitPace())
end
D.paceText = paceText

local function orbitTrack(c, now, ex, ey, ez, dt)
	local subj = c.subject
	local okP, sx, sy, sz = pcall(function()
		-- a vehicle jumped to moves: read it live (a jump's subject keeps its pick-time position)
		if subj.follow and subj.kind ~= "person" and world.position ~= nil then return world.position(subj.entity) end
		return world.subjectPosition(subj)
	end)
	if not okP or not cam.finite(sx) or not cam.finite(ez) then return end
	local d = math.sqrt((ex - sx) ^ 2 + (ey - sy) ^ 2 + (ez - sz) ^ 2)
	c.dMin, c.dMax = math.min(c.dMin, d), math.max(c.dMax, d)
	orbitPace(c, now, dt, ex, ey, ez, sx, sy, sz)
	if c.verdict == nil and now - c.t0 >= ORBIT_CHECK_MS then
		local v = cutscene.attachVerdict(d)
		if v ~= "unsure" then
			c.verdict = v
			if v == "attached" then
				core.log(string.format("cutscene orbit attached: eye-subject %.1f m (the orbit's %.1f m)", d,
					cutscene.orbitDistance()))
			else
				-- round 17 (user: "I would prefer to cancel myself if it looks bad"): logged and said, never ended here
				core.log(string.format("cutscene orbit NOT attached: eye-subject %.1f m (the orbit's %.1f m): an unresolved "
					.. "attachment; left to the player (Esc)", d, cutscene.orbitDistance()))
				setStatus(_("The lens camera did not attach to the object: press Esc to end it."))
			end
		end
	end
	if c.lines < ORBIT_LINES and (c.lines < 3 or now >= c.nextLine) then
		c.lines = c.lines + 1
		c.nextLine = now + ORBIT_EVERY_MS
		-- round 14: the subject's heading since the last line and the bearing relative to it (with the yaw locked
		-- the bearing turns at the orbit's own rate whatever the vehicle does; unlocked it turns with the heading)
		local bearing = cam.atan2(ey - sy, ex - sx)
		local hd, rel = "", ""
		local ls = c.lineS
		if ls ~= nil and (sx - ls.x) ^ 2 + (sy - ls.y) ^ 2 > 1 then
			local h = cam.atan2(sy - ls.y, sx - ls.x)
			hd = string.format(" heading=%.3f", h)
			rel = string.format(" rel=%.3f", cam.angleDiff(h, bearing))
		end
		c.lineS = { x = sx, y = sy }
		core.log(string.format("cutscene orbit t=%.1f eye=%.1f,%.1f,%.1f subject=%.1f,%.1f,%.1f dist=%.1f bearing=%.3f dz=%.1f%s%s",
			(now - c.t0) / 1000, ex, ey, ez, sx, sy, sz, d, bearing, ez - sz, hd, rel))
	end
end

local function cutsceneStep(now, dt)
	local c = S.cutscene
	local playing = cutscene.playing()
	if playing then
		c.seen = true
		local ex, ey, ez = v3(api.gui.camera.getEye)
		local cx, cy, cz = v3(api.gui.camera.getCenter)
		if cam.finite(ez) then F.smoothAdd(c.smooth, ex, ey, ez, dt, cx, cy, cz) end
		if c.subject ~= nil and ez ~= nil then orbitTrack(c, now, ex, ey, ez, dt) end
	end
	local age = now - c.t0
	if (c.seen and not playing) or (not c.seen and age > CUTSCENE_START_GRACE_MS) or age > CUTSCENE_MAX_MS then
		S.cutscene = nil
		cutscene.finish()
		-- the cutscene sets the game speed to 1 and leaves it there: back to the player's speed from before it
		local sp = gameSpeed()
		local speedText
		if c.speedup ~= nil and sp ~= nil and sp ~= c.speedup then
			pcall(function() api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(c.speedup)) end)
			speedText = string.format("game speed back to the player's %s (the cutscene left %s)", tostring(c.speedup),
				tostring(sp))
		else
			speedText = string.format("game speed %s kept (the player's: %s)", tostring(sp), tostring(c.speedup))
		end
		D.watchSpeed(c.speedup, sp, "cutscene " .. (c.kind or "orbit"))
		core.log(string.format("cutscene %s end after %.1f s (%s), %s%s%s", c.kind or "orbit",
			age / 1000, c.seen and "played" or (age > CUTSCENE_MAX_MS and "timeout" or "never playing"),
			speedText, c.subject ~= nil and c.dMax > 0
				and string.format(", eye-subject distance %.1f-%.1f m (an attached orbit: %.1f)", c.dMin, c.dMax,
					cutscene.orbitDistance()) or "", c.verdict ~= nil and (", " .. c.verdict) or ""))
		local pt = paceText(c.pace)
		if pt ~= nil then core.log("cutscene orbit " .. pt) end
		smoothLine("cutscene", c.smooth)
		bump()
	end
end

---------------------------------------------------------------------------
-- Round 15 DEV: the cutscene aerial (pm_cutscene C.FLY / C.planFly; only with the DEV mod; TESTING.md CD4). With
-- the DEV mod on, Start in Aerials plays a chain of up to FLY.chain straight flights instead of the tour: each a
-- static keyframe file (one per heading) whose keys are attached to placeholders the GUI maps to anchors it picks
-- along a line from the view's centre in the look's direction. Logged: the plan (anchors, legs, the anchor search
-- per entity type), per key the eye against the anchor it should be above ("cutscene fly key"), the verdict, the
-- chain hand-over (does a second playCutscene replace a running one? the gap and the eye's jump if not), an early
-- end (Esc is the game's IA_SKIP_VOICEOVER_AND_CUTSCENE), the eye smoothness, the game speed back.

local FLY_CHECK_S, FLY_ATTACH_M = 0.4, 60
-- headings tried from the view's centre when no place of interest gives a flight: the look's first, then further
local FLY_TURNS = { 0, 1, -1, 2, -2, 3, -3, 4 }

local function statsText()
	local ok, t = pcall(world.flyStatsText)
	return ok and tostring(t) or "-"
end

local function boundsText()
	local b = world.mapBounds()
	if b == nil then return "map bounds unknown" end
	return string.format("map %.0fx%.0f m, view kept %.0f m on the map", b[3] - b[1], b[4] - b[2],
		cutscene.reachFor(b))
end

local function recentArea(x, y) return F.nearRecent(x, y) end

-- Round 21 (session 2026-10-14_2332_r20-test: five flights "NOT attached: eye 5350 m from the plan", every one over
-- the same first anchor 47716, a MODEL_INSTANCE_LIST at -1752,-5078, the eye at the world's origin instead, which
-- the user saw as the map cut off): an anchor whose flight did not attach is left out of every later plan this
-- game session (at most BAD_ANCHORS_MAX remembered).
local BAD_ANCHORS_MAX = 64
local badAnchors, badAnchorCount = {}, 0

local function rememberBadAnchor(e)
	if e == nil or badAnchors[e] or badAnchorCount >= BAD_ANCHORS_MAX then return end
	badAnchors[e] = true
	badAnchorCount = badAnchorCount + 1
end

--- pm_world flyCandidates without the anchors that did not attach.
local function flyFind(x, y, r)
	local out = {}
	for __, c in ipairs(world.flyCandidates(x, y, r) or {}) do
		if type(c) ~= "table" or not badAnchors[c.entity] then out[#out + 1] = c end
	end
	return out
end
D.flyFind = flyFind

--- Round 15's plan from the view's centre along the look (round 16: the fallback when no place of interest gives a
--- flight; the view kept on the map too).
local function flyPlanFrom(x, y, h0, why)
	if type(world.flyCandidates) ~= "function" then return nil end
	local last
	for __, k in ipairs(FLY_TURNS) do
		local h = (h0 + k) % cutscene.FLY.headings
		local plan, w = cutscene.planFly(x, y, h, flyFind, world.mapBounds(), 0)
		if plan ~= nil then
			core.log(string.format("cutscene fly plan (%s): from the view's centre %.0f,%.0f heading %d%s; %s; anchor "
				.. "search %s", why, x, y, h, k == 0 and "" or string.format(" (wanted %d)", h0), boundsText(), statsText()))
			return plan
		end
		last = w
	end
	core.log(string.format("cutscene fly plan (%s): none from %.0f,%.0f (%s); %s; anchor search %s", why, x, y,
		tostring(last), boundsText(), statsText()))
	return nil
end

--- Round 16: a flight over a place of interest not shown lately (pm_cutscene chooseStart). nil when none fits.
local function flyPlanArea(c, why)
	if type(world.flyCandidates) ~= "function" then return nil end
	local plan, info = cutscene.chooseStart(c.interests, flyFind, world.mapBounds(), world.rnd, recentArea)
	if plan == nil then
		core.log(string.format("cutscene fly plan (%s): no place of interest fits: %s; %s; anchor search %s", why,
			tostring(info), boundsText(), statsText()))
		return nil
	end
	local it = plan.interest or {}
	core.log(string.format("cutscene fly plan (%s): over %s at %.0f,%.0f, heading %d turn %+d (%s; %d areas shown "
		.. "lately avoided); %s; anchor search %s", why, tostring(it.why), it.x or 0, it.y or 0, plan.h, plan.t,
		tostring(info), F.recentCount(), boundsText(), statsText()))
	return plan
end

local function anchorsText(plan)
	local parts = {}
	for i, a in ipairs(plan.anchors) do
		parts[#parts + 1] = string.format("%d=%s %s %.0f,%.0f,%.0f", i, tostring(a.entity), tostring(a.kind or "?"),
			a.x, a.y, a.z or 0)
	end
	return table.concat(parts, "; ")
end

local function flyStart(c, plan, why)
	local ok, info = cutscene.playFly(plan)
	core.log(string.format("cutscene fly %d/%d (%s): heading %d turn %+d %s: %s; anchors %s; %s", c.n + 1,
		cutscene.FLY.chain, why, plan.h, plan.t or 0, tostring(info), ok and "playing" or "NOT played",
		anchorsText(plan), cutscene.flyText(plan)))
	if not ok then return false end
	c.n = c.n + 1
	c.plan = plan
	c.key = 0
	c.verdict = nil
	c.lastEl = nil
	-- round 16: remembered, so the next start (and the chain) goes elsewhere
	local mx, my = cutscene.flyMiddle(plan)
	F.rememberArea(mx, my)
	if plan.interest ~= nil then F.rememberArea(plan.interest.x, plan.interest.y) end
	return true
end

--- Starts the DEV cutscene aerial: round 16: over a place of interest not shown lately (towns, stations,
--- industries, rivers, water, hills, rail: the Aerials subjects), any heading that keeps the view on the map;
--- else round 15's line from the view's centre along the look. True when a flight plays.
local function cutsceneFly()
	local cur = readView()
	if cur == nil then return false end
	local okC, interests = pcall(world.flightCandidates, S.flightSubjects)
	local c = { kind = "fly", t0 = world.nowMs(), seen = false, smooth = F.newSmooth(), speedup = D.playerSpeed(), n = 0,
		lead = nil, gapFrom = nil, stopWhy = nil, cuts = 0,
		interests = okC and type(interests) == "table" and interests or {} }
	local plan = flyPlanArea(c, "start")
	if plan == nil then
		local ex, ey = v3(api.gui.camera.getEye)
		local cx, cy = v3(api.gui.camera.getCenter)
		local look = (ex ~= nil and cx ~= nil and (cx - ex) ^ 2 + (cy - ey) ^ 2 > 1) and cam.atan2(cy - ey, cx - ex)
			or (cur.a + math.pi)
		plan = flyPlanFrom(cur.x, cur.y, cutscene.flyIndex(look), "start")
	end
	if plan == nil then return false end
	if not flyStart(c, plan, "start") then return false end
	S.cutscene = c
	bump()
	return true
end
D.cutsceneFly = cutsceneFly

--- Round 16: the chain's next flight: on from the last anchor, turning away from the map edge and towards places
--- not shown lately (pm_cutscene chooseNext); when no turn keeps the view on the map, a cut to a new area.
local function flyNext(c, why)
	local p = c.plan
	local nxt, w = cutscene.chooseNext(p, c.interests, flyFind, world.mapBounds(), world.rnd, recentArea)
	if nxt ~= nil then
		core.log(string.format("cutscene fly plan (%s): on from the last anchor, heading %d turn %+d", why, nxt.h, nxt.t))
		return nxt
	end
	c.cuts = (c.cuts or 0) + 1
	core.log(string.format("cutscene fly plan (%s): no way on (%s): a cut to a new area", why, tostring(w)))
	return flyPlanArea(c, why .. ", cut")
end

local function flyFinish(c, why)
	S.cutscene = nil
	local sp = gameSpeed()
	local speedText
	if c.speedup ~= nil and sp ~= nil and sp ~= c.speedup then
		pcall(function() api.cmd.sendCommand(api.cmd.makeGameSetSpeedCmd(c.speedup)) end)
		speedText = string.format("game speed back to the player's %s (the cutscene left %s)", tostring(c.speedup),
			tostring(sp))
	else
		speedText = string.format("game speed %s kept (the player's: %s)", tostring(sp), tostring(c.speedup))
	end
	D.watchSpeed(c.speedup, sp, "cutscene fly")
	core.log(string.format("cutscene fly end (%s) after %d flight(s), %.1f s, %d cut(s) to a new area, %s", why, c.n,
		(world.nowMs() - c.t0) / 1000, c.cuts or 0, speedText))
	smoothLine("cutscene fly", c.smooth)
	bump()
end

--- One frame of the chain.
local function flyStep(now, dt)
	local c = S.cutscene
	local F_ = cutscene.FLY
	local playing = cutscene.playing()
	local el = cutscene.elapsed()
	local ex, ey, ez = v3(api.gui.camera.getEye)
	if playing then
		if c.gapFrom ~= nil and ex ~= nil then
			core.log(string.format("cutscene fly hand-over: %d frame(s) not playing between the flights, the eye "
				.. "jumped %.1f m", c.gapFrames or 0, math.sqrt((ex - c.gapFrom[1]) ^ 2 + (ey - c.gapFrom[2]) ^ 2
				+ (ez - c.gapFrom[3]) ^ 2)))
			c.gapFrom, c.gapFrames = nil, nil
		end
		c.seen = true
		if cam.finite(ez) then
			local cx, cy, cz = v3(api.gui.camera.getCenter)
			F.smoothAdd(c.smooth, ex, ey, ez, dt, cx, cy, cz)
			local pe = c.lastEye
			c.lastEye = { ex, ey, ez }
			local p = c.plan
			if el ~= nil and p ~= nil then
				-- the attachment verdict once, then a line as each key passes
				if c.verdict == nil and el >= FLY_CHECK_S then
					local px, py, pz = cutscene.flyEyeAt(p, el)
					local d = math.sqrt((ex - px) ^ 2 + (ey - py) ^ 2 + (ez - pz) ^ 2)
					c.verdict = d <= FLY_ATTACH_M and "attached" or "NOT attached"
					local a1 = p.anchors[1] or {}
					if c.verdict ~= "attached" then rememberBadAnchor(a1.entity) end
					core.log(string.format("cutscene fly %s: eye %.0f m from the plan at %.1f s (above anchor 1: "
						.. "%.0f,%.0f,%.0f)%s", c.verdict, d, el, px, py, pz, c.verdict == "attached" and ""
						or string.format("; anchor %s left out of later flights (%d so far)", tostring(a1.entity),
						badAnchorCount)))
				end
				local k = math.floor(el / F_.legS + 0.5)
				if k > c.key and k < F_.keys and math.abs(el - k * F_.legS) < 0.1 then
					c.key = k
					local a = p.anchors[k + 1]
					local hx, hy = 0, 0
					local cx2, cy2 = v3(api.gui.camera.getCenter)
					if cx2 ~= nil then hx, hy = cx2 - ex, cy2 - ey end
					core.log(string.format("cutscene fly key %d at %.2f s: eye %.0f,%.0f,%.0f, %.1f m from above anchor "
						.. "%d (%s); look heading %.3f (the file's %.3f)", k + 1, el, ex, ey, ez,
						math.sqrt((ex - a.x) ^ 2 + (ey - a.y) ^ 2 + (ez - (a.z or 0) - F_.height) ^ 2), k + 1,
						tostring(a.entity), cam.atan2(hy, hx), cam.wrapAngle(cutscene.keyAngle(p.h, p.t or 0, k + 1))))
				end
				-- the chain: the next flight played over the running one shortly before its end
				if c.lead == nil and c.stopWhy == nil and c.n < F_.chain and el >= cutscene.flyDuration() - F_.leadS then
					local nxt = flyNext(c, "lead")
					c.lead = { plan = nxt, el = el, prev = c.plan, prevKey = c.key, prevVerdict = c.verdict }
					if nxt ~= nil and not flyStart(c, nxt, string.format("over the running one at %.2f s", el)) then
						c.lead.plan = nil
					end
				elseif c.lead ~= nil and c.lead.verdict == nil and c.lead.plan ~= nil then
					-- the frame after: a second play restarts the clock (replaced) or not
					c.lead.verdict = el < 1 and "replaced" or "not replaced"
					core.log(string.format("cutscene fly chain: a second playCutscene %s the running one (elapsed "
						.. "%.2f -> %.2f s; the eye moved %.1f m this frame)", c.lead.verdict == "replaced" and "REPLACES"
						or "does NOT replace", c.lead.el, el, pe ~= nil and math.sqrt((ex - pe[1]) ^ 2 + (ey - pe[2]) ^ 2
						+ (ez - pe[3]) ^ 2) or -1))
					if c.lead.verdict == "replaced" then
						c.lead = nil
					else
						-- the running flight plays on: its plan back; the lead's plays after its end
						c.n, c.plan, c.key, c.verdict = c.n - 1, c.lead.prev, c.lead.prevKey, c.lead.prevVerdict
					end
				end
				c.lastEl = el
			end
		end
	end
	local age = now - c.t0
	if c.seen and not playing then
		local lastEl = c.lastEl or 0
		if c.gapFrom == nil then c.gapFrom, c.gapFrames = c.lastEye or { 0, 0, 0 }, 0 end
		c.gapFrames = c.gapFrames + 1
		if lastEl < cutscene.flyDuration() - 1 then
			-- ended long before its end: the player's skip (Esc, IA_SKIP_VOICEOVER_AND_CUTSCENE) or input
			flyFinish(c, string.format("ended early at %.1f of %.0f s: Esc / skip or input", lastEl, cutscene.flyDuration()))
			return
		end
		if c.stopWhy ~= nil or c.n >= F_.chain then
			flyFinish(c, c.stopWhy or "chain done")
			return
		end
		-- the next flight after the end (a lead that did not replace the running one is played again now)
		local nxt = c.lead ~= nil and c.lead.plan or flyNext(c, "after the end")
		c.lead = nil
		c.seen = false
		if nxt == nil or not flyStart(c, nxt, "after the end") then
			flyFinish(c, "no next flight")
		end
		c.t0Flight = now
		return
	end
	if not c.seen and age > CUTSCENE_START_GRACE_MS and (c.t0Flight == nil or now - c.t0Flight > CUTSCENE_START_GRACE_MS) then
		flyFinish(c, "never playing")
	elseif age > (F_.chain * (cutscene.flyDuration() + 30)) * 1000 then
		flyFinish(c, "timeout")
	end
end

--- Starts the tour of S.tourMode, or stops the running one. where (round 22, the tab's Where; nil: a tour of the
--- ticked sources, as before the Aerials and Tour tabs): "map" the tour's sources are the ticked map sources
--- (cam.sourcesFor), a wander roams between places of them; "views" the saved views: the hops play them, a
--- wander roams between them, an aerial flies along them; "here" the place in the middle of the view.
function D.toggleTour(where)
	if S.tour ~= nil then stopTour("button") return end
	if S.cutscene ~= nil then return end
	-- round 15 DEV: Aerials as a chain of cutscene flights (TESTING.md CD4); none planned: the normal tour. Round 21
	-- (user: "aerials high mode isn't working, never goes very high"; session 2026-10-14_2332_r20-test: every Start
	-- with the DEV mod played the cutscene flight, whose keys fly FLY.height 250 m over the anchors whatever the
	-- look): the High look always flies the scripted High flight (pm_flight highPose, ~1 km up).
	if S.tourMode == "aerial" and where ~= "views" and cutscene.devOn() then
		if S.aerialLook == "high" then
			core.log("cutscene fly skipped: the High look flies the scripted flight (the cutscene flight's keys are "
				.. cutscene.FLY.height .. " m over the ground)")
		elseif cutsceneFly() then
			return
		end
	end
	local place = nil
	local wanderAt = nil
	local sources = cam.sourcesFor(where, S.tourSources)
	local roam = S.tourMode == "wander" and (where == "map" or where == "views")
	local route = nil
	if roam then
		if where == "views" and newRoute() == nil then
			setStatus(_("Save a view first, or pick Across the map."))
			return
		end
	elseif S.tourMode == "aerial" and where == "views" then
		route = newRoute()
		if route == nil then
			setStatus(_("Save a view first, or pick Across the map."))
			return
		end
	elseif S.tourMode == "wander" then
		wanderAt = readView()
		if wanderAt == nil then
			setStatus(_("Nothing to show on this map yet."))
			return
		end
	elseif S.tourMode == "place" then
		-- the place = the camera centre now; the area from the "Area" row
		local cur = readView()
		local plan = cur ~= nil and P.newPlan(cur.x, cur.y, P.radius(S.areaChoice), world.rnd) or nil
		if plan == nil then
			setStatus(_("Nothing to show on this map yet."))
			return
		end
		place = { plan = plan }
		place.subjects = placeSubjects(place)
		core.log(string.format("tour place %.0f,%.0f r=%.0f subjects=%d", plan.x, plan.y, plan.r, #place.subjects))
	elseif S.tourMode ~= "aerial" and cam.viewsOnly(sources) then
		local okL, list = pcall(D.viewsProvider)
		if not okL or type(list) ~= "table" or #list == 0 then
			setStatus(where == "views" and _("Save a view first, or pick Across the map.")
				or _("Save a view first, or tour random subjects."))
			return
		end
	end
	leaveCockpit("tour")
	releaseFollow("tour", nil)
	-- the look offset is measured now, in the normal camera (camera mode may hand the view to the free camera)
	lookOffset()
	S.tour = { idx = {}, vidx = 0, n = 0, mode = S.tourMode, src = nil, place = place,
		every = cam.tourSeconds(S.tourChoice) * 1000, nextAt = 0,
		where = where, sources = where ~= nil and sources or nil, route = route, roam = roam,
		stayMs = cam.staySeconds(S.stayChoice) * 1000 }
	S.hop, S.flight, S.leaving = nil, nil, nil
	S.look = nil
	S.last = nil
	stopWander("tour") -- a manual wander would resume (and jump) after the tour
	if wanderAt == nil and not roam then newMove("tour") end -- a wander starts its own move (startWander)
	if wanderAt ~= nil then
		local range = cam.tourRange(S.rangeSel)
		startWander(wanderAt, P.radius(S.areaChoice), range.pMin, range.pMax, false)
	elseif roam and not roamNext(nil, "start") then
		S.tour = nil
		core.log("tour roam: no place to go (" .. tostring(where) .. ")")
		setStatus(_("Nothing to show on this map yet."))
		bump()
		return
	end
	core.log("tour on mode=" .. S.tourMode .. " where=" .. tostring(where) .. (roam and " (roams, stay "
		.. cam.staySeconds(S.stayChoice) .. "s)" or "") .. (route ~= nil and (" (route of " .. #route.pts .. " views)") or "")
		.. " sources=" .. table.concat(cam.ticked(sources, cam.TOUR_SOURCES), ",")
		.. " every=" .. tostring(cam.tourSeconds(S.tourChoice)) .. "s leg=" .. tostring(cam.legSeconds(S.legChoice))
		.. "s fly=" .. table.concat(cam.ticked(S.flightSubjects, cam.FLIGHT_SUBJECTS), ",")
		.. " look=" .. S.aerialLook .. " lookReturn=" .. tostring(S.lookReturn)
		.. " kenBurns=" .. tostring(S.kenBurns)
		.. " labels=" .. tostring(S.tourLabels) .. " pause=" .. tostring(S.tourPause))
	setStatus(nil)
	pcall(D.onTourHide, true, { hideLabels = S.tourLabels, pause = S.tourPause })
end

--- Round 22: the Start button of the Aerials ("aerial") or the Tour ("tour") tab: stops the running tour; when it
--- was the other tab's, starts this one (the Aerials tab's Where, or the Tour tab's mode and Where).
function D.startTab(kind)
	if S.tour ~= nil then
		local same = (S.tour.mode == "aerial") == (kind == "aerial")
		stopTour("button")
		if same then return end
	end
	if kind == "aerial" then
		S.tourMode = "aerial"
		D.toggleTour(S.aerialWhere)
	else
		S.tourMode = cam.tourModeOf(S.tourStyle, S.tourWhere, S.tourFlights)
		D.toggleTour(S.tourWhere)
	end
end

--- True while a tour of the Aerials ("aerial") or the Tour ("tour") tab runs.
function D.tabRunning(kind)
	return S.tour ~= nil and (S.tour.mode == "aerial") == (kind == "aerial")
end

---------------------------------------------------------------------------
-- Every frame while the window is open (plugin react.onStep, GUI thread).

--- A failed setCameraData inside the step: every move stops, logged once (not every frame).
local function stepSetFailed(err)
	core.log("setCameraData ERROR " .. tostring(err) .. "; camera moves stopped")
	S.last = nil
	stopTour("camera error")
	stopOrbit("camera error")
	stopWander("camera error")
end

--- One frame of the tour's hop; false when setting the view failed.
local function hopStep(now, orbitDa, dt)
	local h = S.hop
	local hop = h.hop
	if orbitDa ~= 0 then
		local tgt = hop.to.base or hop.to
		tgt.a = cam.wrapAngle(tgt.a + orbitDa)
	end
	local tau = (now - h.t0) / 1000
	-- a hop's views are framings in the game's pitch (round 8: their eye where the game puts it)
	-- round 11: a hop leaving a flight runs in eye space (pm_flight.newHop)
	local okSet, err = sendPlanned(F.hopView(hop, tau, setBuf, h.range.pMin, h.range.pMax, S.camRes), dt, not hop.elev)
	if not okSet then stepSetFailed(err) return false end
	if h.arrived == nil and tau >= hop.G then
		eyeCheck("hop arrived")
		-- the hold starts when the camera has arrived, not at the hop start
		h.arrived = h.t0 + hop.G * 1000
		S.tour.nextAt = h.arrived + S.tour.every
	end
	if h.arrived ~= nil and now >= S.tour.nextAt then
		smoothSegment("hop")
		S.leaving = F.leaving(hop, tau)
		S.hop = nil
		tourAdvance(now)
	end
	return true
end

--- One frame of a flight (its glide up first); false when setting the view failed.
local function flightStep(now, dt)
	local fl = S.flight
	local v
	local ended = false
	-- round 11: the drone's clock runs from the glide's start (the glide arrives on it moving)
	local t = (now - fl.t0) / 1000
	if now < fl.flyT0 then
		v = F.hopView(fl.glide, t, setBuf, nil, nil, S.camRes)
		if S.look ~= nil then F.applyLook(v, S.look) end
	else
		if fl.checked == nil and now - fl.flyT0 > 5000 then
			fl.checked = true
			eyeCheck("flight")
		end
		local dist = flightDist(fl, t)
		extendPath(fl, dist)
		fl.lastT = t
		v = flightView(fl, dist, t, dt, setBuf)
		ended = fl.legMs ~= nil and now - fl.flyT0 >= fl.legMs
	end
	if v ~= nil then
		-- the flight plans elevations; round 11: its glide too (an eye-space hop, pm_flight.newHop)
		local okSet, err = sendPlanned(v, dt, now < fl.flyT0 and not fl.glide.elev)
		if not okSet then stepSetFailed(err) return false end
	end
	if ended then
		-- round 11: the drone flies on while the next hop (Mixed) or the next leg over a new area (Aerials) glides
		-- away from it (a moving hop start), so the speed never drops to rest between them
		smoothSegment("flight")
		local __, __, hx, hy = F.pathPoint(fl.path, flightDist(fl, t))
		fl.endHeading = hx ~= nil and cam.atan2(hy, hx) or nil
		S.flight = nil
		S.leaving = flightEnd(fl, t)
		tourAdvance(now)
	end
	return true
end

---------------------------------------------------------------------------
-- Shutter (pm_shutter.lua)

--- The viewport's width and height in pixels (api.gui.camera.getSize, api/tealdef/api/gui.d.tl:499), or nil.
function D.viewportSize()
	local okSize, sz = pcall(function() return api.gui.camera.getSize() end)
	if not okSize or sz == nil then return nil end
	local w, h = shutter.outputSize(sz.x, sz.y, 1)
	return w, h
end

local function sizeText(scale)
	local w, h = D.viewportSize()
	if w == nil then return "viewport=?" end
	return string.format("viewport=%dx%d out=%dx%d", w, h, w * scale, h * scale)
end

-- Round 11: how long the last takeScreenshot call blocked (ms; it returns once the file is written, pm_shutter).
local shotMs = nil

local function takeShot(scale)
	local t0 = world.nowMs()
	local ok, err = pcall(function() api.gui.camera.takeScreenshot(scale) end)
	shotMs = world.nowMs() - t0
	return ok, err
end

--- Round 11: the status shown before a 2x / 4x shot freezes the game (pm_shutter "announce").
local function freezeText(scale)
	if scale == 4 then return _("Saving the 4x screenshot: the game freezes for 10 seconds or more.") end
	return _("Saving the 2x screenshot: the game freezes for a few seconds.")
end

local function shutterResult(what, scale, err)
	if what == "primer" then
		core.log("screenshot primer scale=1 (first of the session), scale=" .. scale .. " follows")
		setStatus(scale > 1 and freezeText(scale) or _("Taking the screenshot..."))
	elseif what == "announce" then
		core.log("screenshot scale=" .. scale .. " announced (the game freezes while it saves)")
		setStatus(freezeText(scale))
	elseif what == "shot" then
		-- takeScreenshot returns once the file is written (round 11): the call's time is the freeze
		core.log("screenshot scale=" .. scale .. " " .. sizeText(scale)
			.. (shotMs ~= nil and string.format(" call ms=%.0f", shotMs) or ""))
		setStatus(_("The screenshot is in the game's screenshots folder."))
	elseif what == "busy" then
		setStatus(_("Wait a moment: the last screenshot is still being saved."))
	elseif what == "error" then
		core.log("screenshot scale=" .. tostring(scale) .. " ERROR " .. tostring(err))
		setStatus(_("The screenshot could not be taken."))
	elseif what == "ready" then
		core.log("screenshot cooldown over")
		setStatus(_("The screenshot is in the game's screenshots folder."))
	end
end

--- The shutter: a screenshot at scale (1, 2 or 4) times the viewport size. Returns pm_shutter.press's result.
function D.screenshot(scale)
	local sh = S.shutter
	local what, err = shutter.press(sh, scale, world.nowMs(), takeShot)
	if what == "bad" then
		core.log("screenshot: unknown scale " .. tostring(scale))
		return what
	end
	shutterResult(what, (what == "primer" or what == "announce") and sh.pending or scale, err)
	return what
end

--- True while a press would be ignored (the window shows the buttons disabled).
function D.shutterBusy()
	return shutter.busy(S.shutter)
end

local function shutterStep()
	local sh = S.shutter
	local scale = sh.pending or sh.cooling
	local what, err = shutter.tick(sh, world.nowMs(), takeShot)
	if what ~= nil then shutterResult(what, scale, err) end
end

function D.step()
	-- The shutter's primer and cooldown (no clock read while it is idle).
	if shutter.busy(S.shutter) then shutterStep() end
	-- Round 20: the game speed after a cutscene of ours ended (D.watchSpeed).
	if S.speedWatch ~= nil then speedWatchStep(world.nowMs()) end
	-- Round 13 DEV prototype: an orbit cutscene plays (no camera of ours meanwhile).
	if S.cutscene ~= nil then
		local now = world.nowMs()
		local dt = S.lastStepMs and (now - S.lastStepMs) / 1000 or 0
		S.lastStepMs = now
		-- round 16b: a cutscene of another module (gui/pm_lens.lua) brings its own step
		if S.cutscene.step ~= nil then S.cutscene.step(now, dt)
		elseif S.cutscene.kind == "fly" then flyStep(now, dt) else cutsceneStep(now, dt) end
		return
	end
	-- Round 16: the view easing in after a move (the settle); any move, follow or the cockpit ends it.
	if S.settle ~= nil then
		if moving() or S.release ~= nil or S.cockpit ~= nil or S.follow ~= nil then
			S.settle = nil
		else
			S.lastStepMs = nil
			settleStep(world.nowMs())
			return
		end
	end
	-- Idle (the usual case while the window is open): no api call, no clock read.
	if S.release == nil and (S.cockpit ~= nil or not moving()) then
		S.lastStepMs = nil
		return
	end
	if S.release ~= nil then releaseStep(S.cockpit == nil and moving()) end
	if S.cockpit ~= nil or not moving() then
		S.lastStepMs = nil
		return
	end
	local now = world.nowMs()
	local dt = S.lastStepMs and (now - S.lastStepMs) / 1000 or 0
	S.lastStepMs = now
	local cur = readView(curBuf)
	S.curRead = cur
	if cur == nil then return end
	local isFollowing = S.follow ~= nil and following()
	if S.follow ~= nil and not isFollowing then
		S.follow = nil
		bump()
	end
	-- the camera model's residual is measured only from our own camera (not a follow)
	S.noSample = isFollowing
	-- During a flight the player's turn / tilt / zoom is mouse look (kept as an offset), only a pan stops it.
	if S.tour ~= nil and S.flight ~= nil and S.follow == nil and S.release == nil then
		local pan, da, dp, dz = cam.flightInput(S.last, cur)
		if pan then
			S.last = nil
			stopTour("camera moved: pan")
			stopOrbit("camera moved: pan")
			return
		end
		if (da ~= 0 or dp ~= 0 or dz ~= 0) and S.look == nil then
			core.log("tour flight: mouse look kept as an offset (" .. (S.lookReturn and "returns to the path" or "stays") .. ")")
		end
		if da ~= 0 or dp ~= 0 or dz ~= 0 then
			-- round 13: the player's own look input is not the camera's motion (session 2026-10-14_0434_session:
			-- the tour's "d2 max=32 m" sat in its last frames, the player's input that ended it)
			F.smoothCut(S.smooth)
			F.smoothCut(S.smoothAll)
		end
		if S.look ~= nil or da ~= 0 or dp ~= 0 or dz ~= 0 then
			S.look = F.lookStep(S.look, da, dp, dz, math.min(dt, 0.1), S.lookReturn)
		end
		flightStep(now, math.min(dt, 0.1))
		return
	end
	-- while a release is checked the old follow may still move the centre: only zoom / turn / tilt count then
	local moved, why = cam.userMoved(S.last, cur, isFollowing or S.release ~= nil)
	if moved then
		S.last = nil
		stopTour("camera moved: " .. why)
		stopOrbit("camera moved: " .. why)
		stopWander("camera moved: " .. why)
		return
	end
	local orbitDa = S.orbit and cam.ORBIT_RAD_PER_S * math.min(dt, 0.1) or 0
	if S.tour ~= nil then
		if S.wander ~= nil then
			wanderStep(now, math.min(dt, 0.1))
		elseif S.flight ~= nil then
			flightStep(now, math.min(dt, 0.1))
		elseif S.hop ~= nil then
			hopStep(now, orbitDa, math.min(dt, 0.1))
		elseif now >= (S.tour.nextAt or 0) then
			tourAdvance(now)
		end
		return
	end
	if S.wander ~= nil then
		wanderStep(now, math.min(dt, 0.1))
		return
	end
	if S.orbit then
		-- round 16: the turn eases in over ORBIT_EASE_MS and, after the button, out (then stops)
		local f = orbitFactor(now)
		if f == nil then
			stopOrbit("button: slowed to a stop")
			return
		end
		local okSet, err = setView(cam.orbitStep(cur, dt, cam.ORBIT_RAD_PER_S * f, setBuf), true, "move")
		if not okSet then stepSetFailed(err) return end
		if S.orbitSmooth ~= nil then
			local ex, ey, ez = v3(api.gui.camera.getEye)
			if cam.finite(ez) then
				local cx, cy, cz = v3(api.gui.camera.getCenter)
				F.smoothAdd(S.orbitSmooth, ex, ey, ez, S.prevOrbitDt or 0, cx, cy, cz)
			end
			-- the eye read shows the view sent last frame (findings map-camera.md): pair it with that frame's dt
			S.prevOrbitDt = math.min(dt, 0.1)
		end
	end
end

--- True while the driver needs D.step although the window is closed (a follow release still being checked,
--- a tour running with the window hidden, or the shutter's pending shot / cooldown).
function D.busy()
	return S.release ~= nil or S.tour ~= nil or S.cutscene ~= nil or S.settle ~= nil or shutter.busy(S.shutter)
		or S.speedWatch ~= nil
end

return D
