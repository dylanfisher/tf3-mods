-- pm_driver.lua (Photo Mode camera driver) against a fake camera API and a stubbed pm_world: jumps, shots,
-- orbit (and its stop when the player moves the camera), tour glides, follow / cockpit bookkeeping.

local driver, cam, fake, world

local function newFake()
	-- releaseBy: the call that ends a follow in this fake (nil: none does; the game's answer is unknown)
	local f = { view = { x = 0, y = 0, z = 500, w = 0, q = 0.5 }, sets = 0, follow = -1, now = 0, calls = {},
		releaseBy = "focusPosition" }
	local function release(name)
		f.calls[#f.calls + 1] = name
		if f.releaseBy == name then f.follow = -1 end
	end
	f.api = {
		type = {
			Vec5f = { new = function(x, y, z, w, q) return { x = x, y = y, z = z, w = w, q = q } end },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Clock = { new = function() return { getTime = function() return f.now * 1000 end } end },
		},
		gui = {
			camera = {
				getCameraData = function() local v = f.view return { x = v.x, y = v.y, z = v.z, w = v.w, q = v.q } end,
				setCameraData = function(v) f.view = v; f.sets = f.sets + 1 end,
				getFollowEntity = function() return { f.follow, 0 } end,
				followEntity = function(e, jump) f.follow = e; f.calls[#f.calls + 1] = "follow" .. tostring(e) end,
				enterFollowCameraCockpit = function(e) f.calls[#f.calls + 1] = "cockpit" .. tostring(e) end,
				leaveFollowCameraCockpit = function()
					f.calls[#f.calls + 1] = "leave"
					if f.releaseBy == "leaveFollowCameraCockpit" then f.follow = -1 end
				end,
				focusPosition = function(pos, d) release("focusPosition") end,
				setManualCamera = function(c, d) release("setManualCamera") end,
			},
		},
	}
	return f
end

before_each(function()
	reset_modules()
	fake = newFake()
	set_global("api", fake.api)
	world = {
		subjects = {},
		nowMs = function() return fake.now end,
		rnd = function() return 0 end,
		pick = function(kind) return world.subjects[kind] end,
		exists = function() return true end,
		alive = function(s) return world.gone == nil or not world.gone[s.entity] end,
		mapBounds = function() return world.bounds end,
		clearCache = function() end,
		groundAt = function(x, y) return world.ground and world.ground(x, y) or 0 end,
		flightCandidates = function() return world.cands or {} end,
	}
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", world)
	cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
	driver = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua"
	-- round 13: the driver starts in Aerials ("round 13: Aerials is the default tour mode" checks that); the tests
	-- below were written for the hop tour and pick Aerials themselves where they fly
	driver.S.tourMode, driver.S.rangeSel = "ground", cam.preset("ground")
	-- round 15: High is the default Look ("round 15: High is the default Aerials look" checks it); the flight tests
	-- below were written for Down and pick High themselves where they need it
	driver.S.aerialLook = "down"
end)

local function step(ms)
	fake.now = fake.now + ms
	driver.step()
end

test("jump frames a subject; nothing found sets a status", function()
	world.subjects.train = { entity = 7, x = 100, y = 50, z = 3, kind = "train", follow = true, why = "random" }
	eq(driver.jump("train"), true)
	eq(fake.view.x, 100); eq(fake.view.z, 120); eq(fake.view.q, 0.30)
	eq(driver.S.subject.entity, 7)
	eq(driver.jump("ship"), false)
	ok(driver.S.status ~= nil)
end)

test("an airborne aircraft is followed, not framed", function()
	world.subjects.plane = { entity = 9, x = 1, y = 2, z = 900, kind = "plane", follow = true, airborne = true }
	driver.jump("plane")
	eq(fake.follow, 9)
	eq(fake.sets, 0)
end)

test("orbit turns the view each frame and stops when the player zooms", function()
	driver.toggleOrbit()
	step(16)
	step(16)
	ok(fake.view.w > 0, "turned")
	local sets = fake.sets
	fake.view.z = 200 -- the player zooms
	step(16)
	eq(driver.S.orbit, false)
	eq(fake.sets, sets, "no set after the stop")
end)

test("shot keeps the centre", function()
	fake.view = { x = 10, y = 20, z = 500, w = 1, q = 0.5 }
	driver.shot("eye")
	eq(fake.view.x, 10); eq(fake.view.z, 25); eq(fake.view.w, 1); eq(fake.view.q, 0.04)
end)

test("tour stops when the map has nothing to show", function()
	driver.toggleTour()
	step(16)
	eq(driver.S.tour, nil)
	ok(driver.S.status ~= nil)
end)

test("follow and cockpit need a subject; stopAll leaves the cockpit", function()
	driver.toggleFollow()
	ok(driver.S.status ~= nil)
	eq(driver.S.follow, nil)
	world.subjects.road = { entity = 5, x = 0, y = 0, kind = "road", follow = true }
	driver.jump("road") -- round 20: a jump follows the vehicle at once
	eq(fake.follow, 5)
	driver.toggleCockpit()
	eq(driver.S.cockpit, 5)
	driver.stopAll("test")
	eq(driver.S.cockpit, nil)
	eq(fake.calls[#fake.calls], "leave")
end)

test("an idle step reads neither the camera nor the clock", function()
	local reads, clockReads = 0, 0
	local get = fake.api.gui.camera.getCameraData
	fake.api.gui.camera.getCameraData = function() reads = reads + 1 return get() end
	world.nowMs = function() clockReads = clockReads + 1 return fake.now end
	for __ = 1, 5 do step(16) end
	eq(reads, 0); eq(clockReads, 0); eq(fake.sets, 0)
	driver.toggleOrbit()
	step(16)
	eq(reads, 1); eq(clockReads, 1)
	driver.toggleOrbit()
	eq(reads, 1, "round 16: the button lets the orbit slow to a stop")
	driver.toggleOrbit()
	eq(reads, 2, "round 15: one read by the hand-back line as the orbit ends (round 16: a second press stops it)")
	step(16)
	step(16)
	eq(reads, 2, "idle again after the orbit stopped")
end)

test("orbit reuses its scratch views from frame to frame", function()
	driver.toggleOrbit()
	step(16)
	local last = driver.S.last
	ok(last ~= nil)
	step(16)
	step(16)
	eq(driver.S.last, last, "the same scratch table, no new view per frame")
	ok(fake.view.w > 0)
end)

test("a failing setCameraData stops the moves with one log line", function()
	fake.api.gui.camera.setCameraData = function() error("boom") end
	clear_logs()
	driver.toggleOrbit()
	step(16)
	step(16)
	step(16)
	eq(driver.S.orbit, false)
	local errors = 0
	for __, e in ipairs(log_entries()) do
		if e.msg:find("setCameraData ERROR", 1, true) then errors = errors + 1 end
	end
	eq(errors, 1)
end)

test("a vanished subject is never followed or ridden", function()
	world.subjects.road = { entity = 5, x = 0, y = 0, kind = "road", follow = true }
	driver.jump("road")
	fake.follow = -1 -- round 20: the jump's own follow, ended by the game
	driver.followEnded()
	world.gone = { [5] = true } -- sold, or its id now belongs to something else
	fake.calls = {}
	driver.toggleFollow()
	eq(driver.S.follow, nil)
	driver.toggleCockpit()
	eq(driver.S.cockpit, nil)
	eq(#fake.calls, 0, "no followEntity / enterFollowCameraCockpit call")
	ok(driver.S.status ~= nil)
	-- an airborne aircraft that is gone by the time of the follow
	world.subjects.plane = { entity = 9, x = 1, y = 2, z = 900, kind = "plane", follow = true, airborne = true }
	world.gone[9] = true
	eq(driver.jump("plane"), false)
	eq(fake.follow, -1)
end)

test("views sent to the camera are clamped; a NaN view is never sent", function()
	world.bounds = { -1000, -1000, 1000, 1000 }
	driver.goTo({ x = 5000, y = -5000, d = 0, a = 0, p = 9 }, "test")
	eq(fake.view.x, 1000); eq(fake.view.y, -1000)
	eq(fake.view.z, cam.SAFE.dMin); eq(fake.view.q, cam.SAFE.pMax)
	local sets = fake.sets
	driver.goTo({ x = 0 / 0, y = 0, d = 100, a = 0, p = 0.5 }, "test")
	eq(fake.sets, sets, "not sent")
end)

test("a NaN camera read stops orbit with one log line, nothing sent", function()
	driver.toggleOrbit()
	step(16)
	local sets = fake.sets
	fake.view = { x = 0 / 0, y = 0, z = 500, w = 0, q = 0.5 }
	clear_logs()
	step(16)
	step(16)
	eq(driver.S.orbit, false)
	eq(fake.sets, sets)
	local errors = 0
	for __, e in ipairs(log_entries()) do
		if e.msg:find("setCameraData ERROR", 1, true) then errors = errors + 1 end
	end
	eq(errors, 1)
end)

test("the game ending our cockpit leaves it as the base tool does", function()
	world.subjects.train = { entity = 7, x = 0, y = 0, kind = "train", follow = true }
	driver.jump("train")
	driver.toggleCockpit()
	eq(driver.S.cockpit, 7)
	driver.followEnded()
	eq(driver.S.cockpit, nil)
	eq(fake.calls[#fake.calls], "leave")
	driver.stopAll("test")
	eq(fake.calls[#fake.calls], "leave", "no second leave from stopAll")
end)

test("a step with no clock (dt 0) and a glide of zero length stay finite", function()
	world.nowMs = function() return 0 end
	world.subjects.town = { entity = 3, x = 0, y = 0, kind = "town" }
	fake.view = { x = 0, y = 0, z = 900, w = 0, q = 0.52 }
	driver.toggleOrbit()
	driver.toggleTour()
	for __ = 1, 5 do driver.step() end
	ok(fake.view.x == fake.view.x and fake.view.z == fake.view.z, "finite")
end)

-- Rev 1 feedback (2026-10-13)

local function readyViews(list)
	driver.viewsProvider = function() return list end
end

--- Only the saved views ticked as the tour's source.
local function viewsOnly()
	driver.setTourSource("views", true)
	driver.setTourSource("random", false)
	driver.setTourSource("places", false)
	driver.setTourSource("shots", false)
end

test("saved-views tour with no views: not started, a status says why", function()
	readyViews({})
	viewsOnly()
	driver.toggleTour()
	eq(driver.S.tour, nil)
	ok(driver.S.status ~= nil)
	-- the list emptied during a tour: stops at the next hop
	local list = { { id = 1, x = 0, y = 0, d = 300, a = 0, p = 0.5 } }
	readyViews(list)
	driver.toggleTour()
	step(16)
	list[1] = nil
	step(cam.GLIDE_SECONDS * 1000 + 16)
	for __ = 1, 12 do step(1000) end
	eq(driver.S.tour, nil)
end)

test("follow off releases the follow camera, trying the calls in stages", function()
	world.subjects.road = { entity = 5, x = 0, y = 0, kind = "road", follow = true }
	driver.jump("road") -- round 20: a jump follows the vehicle at once
	eq(fake.follow, 5)
	-- this game ends a follow only with setManualCamera: focusPosition first, then setManualCamera
	fake.releaseBy = "setManualCamera"
	fake.calls = {}
	clear_logs()
	driver.toggleFollow()
	eq(driver.S.follow, nil)
	eq(fake.calls[1], "focusPosition")
	ok(driver.busy(), "release checked in the next frames")
	for __ = 1, 10 do step(16) end
	eq(fake.follow, -1)
	eq(driver.busy(), false)
	local released = false
	for __, e in ipairs(log_entries()) do
		if e.msg:find("follow released by setManualCamera", 1, true) then released = true end
	end
	ok(released, "logged which call worked")
end)

test("follow release gives up after the last call with a status; a jump releases too", function()
	world.subjects.road = { entity = 5, x = 0, y = 0, kind = "road", follow = true }
	world.subjects.town = { entity = 3, x = 900, y = 0, kind = "town" }
	driver.jump("road") -- round 20: a jump follows the vehicle at once
	fake.releaseBy = nil
	driver.toggleFollow()
	for __ = 1, 20 do step(16) end
	eq(driver.busy(), false)
	ok(driver.S.status ~= nil, "the player is told to move the camera")
	eq(fake.calls[#fake.calls], "leave", "the last call tried")
	-- a jump while following: the follow is released, the camera lands on the new subject
	fake.follow = -1
	driver.jump("road") -- round 20: a jump follows the vehicle at once
	fake.releaseBy = "focusPosition"
	driver.jump("town")
	eq(fake.view.x, 900)
	for __ = 1, 5 do step(16) end
	eq(fake.follow, -1)
	eq(fake.view.x, 900, "still at the town")
end)

test("a release runs while photo mode is off and stays idle afterwards", function()
	world.subjects.road = { entity = 5, x = 0, y = 0, kind = "road", follow = true }
	driver.jump("road") -- round 20: a jump follows the vehicle at once
	driver.stopAll("click")
	ok(driver.busy())
	for __ = 1, 5 do step(16) end
	eq(driver.busy(), false)
	local reads = 0
	local get = fake.api.gui.camera.getCameraData
	fake.api.gui.camera.getCameraData = function() reads = reads + 1 return get() end
	for __ = 1, 5 do step(16) end
	eq(reads, 0, "idle again")
end)

test("Anything jumps to whatever pm_world picks for 'any'", function()
	world.subjects.any = { entity = 11, x = 40, y = 50, kind = "station", why = "any station" }
	eq(driver.jump("any"), true)
	eq(fake.view.x, 40)
	world.subjects.any = nil
	eq(driver.jump("any"), false)
	ok(driver.S.status ~= nil)
end)

-- Rev 1 feedback round 2 (2026-10-13): hops, hold timer, drift, flights, framings, tour window

test("tour glides to subjects at tour framing and skips kinds with none", function()
	world.subjects.town = { entity = 3, x = 2000, y = 0, kind = "town" }
	driver.setKenBurns(false)
	driver.toggleTour()
	step(16)
	ok(driver.S.hop ~= nil, "hop started")
	local glideMs = cam.GLIDE_SECONDS * 1000
	ok(glideMs >= 4000 and glideMs <= 5000, "a slow 4-5 s glide")
	step(glideMs / 2)
	ok(fake.view.x > 0 and fake.view.x < 2000, "half-way: " .. fake.view.x)
	ok(fake.view.z > 500, "rises mid-way")
	step(glideMs / 2 + 100)
	near(fake.view.x, 2000, 1e-6)
	local f = cam.TOUR_FRAME
	ok(fake.view.z >= f.dMin and fake.view.z <= f.dMax, "eye level .. a bit wider than low angle: " .. fake.view.z)
	ok(fake.view.q >= f.pMin and fake.view.q <= f.pMax, "pitch " .. fake.view.q)
	ok(driver.S.hop.arrived ~= nil, "arrived: the hold runs")
	ok(driver.S.tour ~= nil, "still touring")
	fake.view.x = 2500 -- the player pans
	step(16)
	eq(driver.S.tour, nil)
	eq(driver.S.hop, nil)
end)

test("the hold timer starts when the camera has arrived, not at the hop start", function()
	world.subjects.town = { entity = 3, x = 2000, y = 0, kind = "town" }
	driver.setTourChoice(1) -- 5 s
	driver.toggleTour()
	step(16)
	local h = driver.S.hop
	local t0 = h.t0
	-- 5 s after the hop start the camera is still gliding (4.5 s) / just arrived: no next hop
	step(5000)
	eq(driver.S.hop, h, "same hop 5 s after its start")
	eq(driver.S.tour.nextAt, t0 + cam.GLIDE_SECONDS * 1000 + 5000, "hold = 5 s from the arrival")
	step(cam.GLIDE_SECONDS * 1000 + 5000 - 5000 - 100)
	eq(driver.S.hop, h, "not yet")
	step(200)
	ok(driver.S.hop ~= h, "the next hop after glide + 5 s")
end)

test("a hop's start view is its own table, not the step's scratch", function()
	world.subjects.town = { entity = 3, x = 2000, y = 0, kind = "town" }
	driver.toggleOrbit()
	step(16)
	driver.toggleTour()
	step(16)
	local from = driver.S.hop.hop.from
	local fromX = from.x
	step(500)
	step(500)
	eq(from.x, fromX, "from not overwritten by later frames")
end)

test("Ken Burns drift: slow, steady during the hold; the next hop glides on from the drift", function()
	world.rnd = (function() local r = cam.newRng(5) return r end)()
	world.subjects.train = { entity = 7, x = 500, y = 500, kind = "train", follow = true }
	driver.toggleTour() -- every 10 s (default), drift on (default)
	step(16)
	step(cam.GLIDE_SECONDS * 1000 + 16)
	local h = driver.S.hop
	ok(h.hop.to.rates ~= nil, "drift rates")
	local arrive = { x = fake.view.x, y = fake.view.y, z = fake.view.z, w = fake.view.w, q = fake.view.q }
	for __ = 1, 50 do step(100) end -- 5 s into the hold
	local turn = math.abs(cam.angleDiff(arrive.w, fake.view.w))
	ok(turn + math.abs(fake.view.z - arrive.z) + math.abs(fake.view.x - arrive.x) > 0.01, "drifting")
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	-- at most the orbit's full amount at the fastest pace over the 5 s (the eye-space solver adds no turn)
	ok(turn <= F.KB.orbit * F.KB.speedMax / F.KB.refS * 6 + 1e-3, "a slow turn: " .. turn)
	ok(driver.S.tour ~= nil, "the drift doesn't stop the tour")
	for __ = 1, 60 do step(100) end -- past the hold
	ok(driver.S.hop ~= h, "next hop")
	ok(driver.S.hop.hop.from.base ~= nil, "it glides from the still-moving drift")
end)

test("Ken Burns off: the hold stands still", function()
	world.subjects.train = { entity = 7, x = 500, y = 500, kind = "train", follow = true }
	driver.setKenBurns(false)
	driver.toggleTour()
	step(16)
	step(cam.GLIDE_SECONDS * 1000 + 16)
	local x, w = fake.view.x, fake.view.w
	for __ = 1, 30 do step(100) end
	eq(fake.view.x, x); eq(fake.view.w, w)
end)

test("saved-views tour plays the list in order, loops, follows a reorder", function()
	local list = {
		{ id = 1, x = 100, y = 0, d = 300, a = 0, p = 0.5 },
		{ id = 2, x = 200, y = 0, d = 300, a = 0, p = 0.5 },
		{ id = 3, x = 300, y = 0, d = 300, a = 0, p = 0.5 },
	}
	readyViews(list)
	viewsOnly()
	driver.setTourChoice(1) -- 5 s
	driver.toggleTour()
	local seen = {}
	local lastHop = nil
	local function nextHop()
		for __ = 1, 200 do
			step(100)
			local h = driver.S.hop
			if h ~= nil and h ~= lastHop then
				lastHop = h
				local to = h.hop.to.base or h.hop.to
				seen[#seen + 1] = to.x
				return
			end
		end
		error("no next hop")
	end
	nextHop(); nextHop(); nextHop(); nextHop()
	eq(seen, { 100, 200, 300, 100 }, "list order, then from the start")
	local b = lastHop.hop.to.base
	eq(b.d, 300); eq(b.p, 0.5)
	list[2], list[3] = list[3], list[2]
	nextHop(); nextHop()
	eq(seen[5], 300); eq(seen[6], 200)
end)

test("the tour range frames random subjects inside the chosen bounds", function()
	world.subjects.town = { entity = 3, x = 2000, y = 0, kind = "town" }
	driver.setTourMode("mixed")
	driver.setRange("pf", 3); driver.setRange("pt", 3); driver.setRange("df", 3); driver.setRange("dt", 3)
	driver.setKenBurns(false)
	driver.toggleTour()
	step(16)
	step(cam.GLIDE_SECONDS * 1000 + 16)
	local r = cam.tourRange(driver.S.rangeSel)
	ok(fake.view.z >= r.dMin - 1e-6 and fake.view.z <= r.dMax + 1e-6, "d " .. fake.view.z)
	ok(fake.view.q >= r.pMin - 1e-6 and fake.view.q <= r.pMax + 1e-6, "p " .. fake.view.q)
	driver.setTourMode("ground")
	eq(driver.S.rangeSel, cam.preset("ground"), "a preset sets the range")
end)

test("the tour hides the window (labels, pause as asked) and shows it when it stops", function()
	world.subjects.town = { entity = 3, x = 2000, y = 0, kind = "town" }
	local calls = {}
	driver.onTourHide = function(on, o)
		calls[#calls + 1] = tostring(on) .. ":" .. (o and (tostring(o.cameraMode) .. "," .. tostring(o.hideLabels) .. ","
			.. tostring(o.pause)) or "nil")
	end
	eq(driver.setTourCamera, nil, "round 9: no camera mode for tours")
	eq(driver.S.tourLabels, true, "hidden labels during tours are the default")
	eq(driver.S.tourPause, false, "no pause by default")
	driver.setTourPause(true)
	driver.toggleTour()
	eq(calls, { "true:nil,true,true" })
	ok(driver.busy(), "the step runs while the window is hidden")
	step(16)
	step(16)
	fake.view.z = fake.view.z * 2 -- the player zooms
	step(16)
	eq(driver.S.tour, nil)
	eq(calls[#calls], "false:nil", "shown again")
	driver.toggleTour()
	driver.stopAll("pause menu")
	eq(calls[#calls], "false:nil", "and on every stop")
end)

test("Aerials: a glide up onto the moving drone, then a continuous flight; finite views inside the map; stops on input", function()
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.rnd = (function() local r = cam.newRng(8) return r end)()
	driver.setTourMode("aerial")
	driver.setLegChoice(4) -- 5 min: one leg for the whole minute below
	driver.toggleTour()
	step(16)
	local fl = driver.S.flight
	ok(fl ~= nil, "a flight")
	ok(#fl.path >= 2, "waypoints ahead")
	step(cam.GLIDE_SECONDS * 1000)
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	local prev = nil
	local speeds = {}
	for i = 1, 600 do -- 60 s of flight
		step(100)
		ok(fake.view.x == fake.view.x and fake.view.z == fake.view.z, "finite")
		ok(fake.view.x >= -10000 and fake.view.x <= 10000 and fake.view.y >= -10000 and fake.view.y <= 10000)
		local __, __, ez = F.eyeOf({ x = fake.view.x, y = fake.view.y, d = fake.view.z, a = fake.view.w, p = fake.view.q }, 0, 0)
		ok(ez >= 40 - 1e-6, "eye above the ground: " .. ez)
		if prev ~= nil then speeds[#speeds + 1] = math.sqrt((fake.view.x - prev.x) ^ 2 + (fake.view.y - prev.y) ^ 2) / 0.1 end
		prev = { x = fake.view.x, y = fake.view.y }
	end
	-- round 11: the drone's clock starts with the glide, which arrives on it already flying (no stop at the end)
	ok(speeds[2] > F.FLY.speed * 0.7, "arrives on the moving drone: " .. speeds[2])
	ok(speeds[#speeds] > F.FLY.speed * 0.6 and speeds[#speeds] < F.FLY.speed * 2, "cruising: " .. speeds[#speeds])
	ok(driver.S.tour ~= nil and driver.S.flight == fl, "one continuous flight")
	fake.view.x = fake.view.x + 400 -- the player pans
	step(16)
	eq(driver.S.tour, nil)
end)

test("Aerials: the next leg starts over a new area far away", function()
	world.bounds = { -20000, -20000, 20000, 20000 }
	world.rnd = (function() local r = cam.newRng(5) return r end)()
	world.cands = { { x = 12000, y = 12000, w = 1, why = "town" }, { x = -12000, y = 9000, w = 1, why = "water" } }
	driver.setTourMode("aerial")
	driver.setLegChoice(1) -- 30 s
	driver.toggleTour()
	step(16)
	local first = driver.S.flight
	ok(first ~= nil)
	local start = first.path[1]
	for __ = 1, (cam.GLIDE_SECONDS + 31) * 10 do step(100) end
	local second = driver.S.flight
	ok(second ~= nil and second ~= first, "a new leg")
	local p = second.path[1]
	ok(math.sqrt((p.x - start.x) ^ 2 + (p.y - start.y) ^ 2) >= 3000, "over a new area")
	ok(driver.S.tour ~= nil, "still touring")
end)

-- Round 11 (user: "When jumping to the aerials location to start, ease in and out of the aerial speed so it
-- doesn't slow down between"): the glide into a leg and between legs keeps the drone's speed.
local function aerialRun(seed, legChoice, frames, dtMs)
	world.bounds = { -30000, -30000, 30000, 30000 }
	world.rnd = cam.newRng(seed)
	-- far candidates all round (new areas); none within a leg's waypoint range of the start
	world.cands = {}
	for i = 0, 7 do
		local a = i * math.pi / 4
		world.cands[#world.cands + 1] = { x = 9000 * math.cos(a), y = 9000 * math.sin(a), w = 1, why = "town" }
	end
	driver.setTourMode("aerial")
	driver.setLegChoice(legChoice)
	driver.toggleTour()
	local track = {}
	for i = 1, frames do
		step(dtMs)
		track[i] = { x = fake.view.x, y = fake.view.y, fl = driver.S.flight, glide = driver.S.flight ~= nil
			and fake.now < driver.S.flight.flyT0 }
	end
	return track
end

local function speedsOf(track, dt)
	local v = {}
	for i = 2, #track do
		v[i] = { x = (track[i].x - track[i - 1].x) / dt, y = (track[i].y - track[i - 1].y) / dt }
		v[i].s = math.sqrt(v[i].x ^ 2 + v[i].y ^ 2)
	end
	return v
end

test("Aerials: from leg to leg the speed never dips: the glide leaves the flying drone and lands on the next one", function()
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	local dt = 0.05
	local track = aerialRun(5, 1, math.floor((cam.GLIDE_SECONDS * 2 + 40) / dt), dt * 1000)
	local v = speedsOf(track, dt)
	-- the second leg's glide: from the first leg's last 3 s to the second leg's first 5 s after its glide
	local first, second, gStart, gEnd = track[2].fl, nil, nil, nil
	for i = 2, #track do
		if track[i].fl ~= nil and track[i].fl ~= first and second == nil then second, gStart = track[i].fl, i end
		if second ~= nil and track[i].fl == second and not track[i].glide and gEnd == nil then gEnd = i end
	end
	ok(second ~= nil and gEnd ~= nil, "a second leg after its glide")
	eq(second.cruise, true, "the second leg flies at cruise from its start")
	local lo, hi = gStart - math.floor(3 / dt), math.min(#track, gEnd + math.floor(5 / dt))
	local minS, peakA = math.huge, 0
	for i = lo, hi do minS = math.min(minS, v[i].s) end
	ok(minS > F.FLY.speed * 0.7, string.format("no dip below 70%% of cruise through the glide: %.1f m/s", minS))
	-- the hand-overs: the acceleration grows from (about) zero, no step to the glide's own (the smootherstep);
	-- a smoothstep glide jumps to ~its peak acceleration in one frame
	local acc = {}
	for i = lo + 1, hi do
		acc[i] = math.sqrt(((v[i].x - v[i - 1].x) / dt) ^ 2 + ((v[i].y - v[i - 1].y) / dt) ^ 2)
		peakA = math.max(peakA, acc[i])
	end
	ok(peakA > 50, "the glide does accelerate: " .. peakA)
	for __, i in ipairs({ gStart, gStart + 1, gEnd, gEnd + 1 }) do
		ok(acc[i] < 0.2 * peakA, string.format("no acceleration step at the hand-over (frame %d): %.1f of peak %.1f",
			i, acc[i], peakA))
	end
	-- the new area lies ahead of the first leg's drone, its path goes on in the glide's direction
	local p = second.path[1]
	local jump = cam.atan2(p.y - track[gStart - 1].y, p.x - track[gStart - 1].x)
	ok(math.abs(cam.angleDiff(second.heading, jump)) <= 0.26, "the new leg heads on in the glide's direction")
end)

test("Aerials: the first glide arrives on the drone at speed and eases into cruise (no stop, then start)", function()
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	local dt = 0.05
	local track = aerialRun(8, 4, math.floor((cam.GLIDE_SECONDS + 10) / dt), dt * 1000)
	local v = speedsOf(track, dt)
	local gEnd = nil
	for i = 2, #track do if track[i].fl ~= nil and not track[i].glide and gEnd == nil then gEnd = i end end
	ok(gEnd ~= nil, "the glide ended")
	-- from the last second of the glide to 6 s after it: never below 70 % of cruise, rising towards cruise
	for i = gEnd - math.floor(1 / dt), gEnd + math.floor(6 / dt) do
		ok(v[i].s > F.FLY.speed * 0.7, string.format("speed %.1f m/s at frame %d", v[i].s, i))
		-- after the glide: the drone's own speed (the glide may still be faster in its last second)
		if i > gEnd then ok(v[i].s < F.FLY.speed * 1.6, string.format("speed %.1f m/s at frame %d", v[i].s, i)) end
	end
	near(v[gEnd + math.floor(6 / dt)].s, F.FLY.speed, F.FLY.speed * 0.1, "at cruise once the ramp is over")
end)

test("tour sources: the ticked ones in turn; the last one can't be unticked", function()
	world.subjects.town = { entity = 3, x = 2000, y = 0, kind = "town" }
	world.subjects.place = { x = -2000, y = 0, kind = "place" }
	readyViews({ { id = 1, x = 500, y = 500, d = 300, a = 0, p = 0.5 } })
	driver.setTourSource("random", true)
	driver.setTourSource("places", true)
	driver.setTourSource("views", true)
	driver.setTourSource("shots", false)
	driver.setTourChoice(1)
	driver.setKenBurns(false)
	driver.toggleTour()
	local seen, lastHop = {}, nil
	for __ = 1, 1200 do
		step(100)
		local h = driver.S.hop
		if h ~= nil and h ~= lastHop then
			lastHop = h
			local to = h.hop.to.base or h.hop.to
			seen[#seen + 1] = driver.S.tour.src
			if #seen >= 6 then break end
		end
	end
	local has = {}
	for __, k in ipairs(seen) do has[k] = true end
	ok(has.random and has.places and has.views, "all three ticked sources used: " .. table.concat(seen, ","))
	for i = 2, #seen do ok(seen[i] ~= seen[i - 1], "in turn") end
	driver.stopAll("test")
	-- only one left: unticking it is refused, with a status line
	driver.setTourSource("random", false)
	driver.setTourSource("places", false)
	driver.S.status = nil
	driver.setTourSource("views", false)
	eq(driver.S.tourSources.views, true, "the last source stays ticked")
	ok(driver.S.status ~= nil, "says why")
	eq(cam.viewsOnly(driver.S.tourSources), true)
end)

test("flight subjects and leg: the last subject can't be unticked; flights ask for the ticked subjects", function()
	for __, k in ipairs(cam.FLIGHT_SUBJECTS) do if k ~= "rivers" then driver.setFlightSubject(k, false) end end
	eq(cam.ticked(driver.S.flightSubjects, cam.FLIGHT_SUBJECTS), { "rivers" })
	driver.setFlightSubject("rivers", false)
	eq(driver.S.flightSubjects.rivers, true, "the last subject stays ticked")
	local asked = nil
	local orig = world.flightCandidates
	world.flightCandidates = function(subjects) asked = subjects return {} end
	world.bounds = { -10000, -10000, 10000, 10000 }
	driver.setTourMode("aerial")
	driver.toggleTour()
	step(16)
	world.flightCandidates = orig
	ok(asked ~= nil and asked.rivers == true and asked.towns == false, "the ticked subjects")
	ok(driver.S.flight ~= nil, "flies anyway (waypoints ahead) when the map has none")
end)

test("Mixed: every third hop is a flight leg; a leg ends at cruise (the next glide leaves it flying)", function()
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.subjects.town = { entity = 3, x = 2000, y = 0, kind = "town" }
	driver.setTourMode("mixed")
	driver.setTourChoice(1)
	driver.toggleTour()
	local flights = 0
	local lastF = nil
	for __ = 1, 1200 do
		step(100)
		if driver.S.flight ~= nil and driver.S.flight ~= lastF then flights = flights + 1 lastF = driver.S.flight end
	end
	ok(flights >= 1, "a flight leg")
	ok(driver.S.tour ~= nil, "still touring")
	local fl = { legMs = 30000 }
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	local v1 = (driver.flightDist(fl, 30) - driver.flightDist(fl, 30 - 0.01)) / 0.01
	near(v1, F.FLY.speed, 1e-3, "a leg ends at cruise (round 11)")
	local vMid = (driver.flightDist(fl, 15) - driver.flightDist(fl, 15 - 0.01)) / 0.01
	near(vMid, F.FLY.speed, 1e-6, "full speed mid-leg")
end)

test("a photographer's shot is framed by its look heading, measured from the camera", function()
	-- this fake camera looks along angle + pi/2
	fake.api.gui.camera.getEye = function()
		local v = fake.view
		local look = v.w + math.pi / 2
		return { x = v.x - math.cos(look) * 100, y = v.y - math.sin(look) * 100 }
	end
	fake.api.gui.camera.getCenter = function() return { x = fake.view.x, y = fake.view.y } end
	fake.view = { x = 0, y = 0, z = 500, w = 0.4, q = 0.5 }
	world.subjects.bridge = { entity = 7, x = 100, y = 0, kind = "train", follow = true, why = "bridge",
		framing = { x = 100, y = 0, d = 150, p = 0.05, look = 1.0 } }
	driver.jump("bridge")
	near(driver.S.lookOffset, math.pi / 2, 1e-9, "measured")
	near(cam.angleDiff(fake.view.w + math.pi / 2, 1.0), 0, 1e-6, "the camera looks along the framing's heading")
	eq(fake.view.z, 150)
end)

test("a low view is raised over a hill between the eye and the subject", function()
	world.ground = function(x, y) return x < 0 and 60 or 0 end -- a 60 m hill west of x = 0
	world.subjects.bridge = { entity = 7, x = 50, y = 0, kind = "train", follow = true, why = "bridge",
		framing = { x = 50, y = 0, d = 150, p = 0.02, look = 0 } } -- eye at x = -100: on the hill
	driver.jump("bridge")
	ok(fake.view.z * math.sin(fake.view.q) >= 60 + 8 - 1e-6, "eye over the hill: " .. fake.view.q)
end)

test("the fastest vehicle is followed at its framing", function()
	world.subjects.fastest = { entity = 12, x = 10, y = 0, kind = "train", follow = true, why = "fastest", followShot = true,
		framing = { x = 10, y = 0, d = 120, p = 0.08, look = 0 } }
	driver.jump("fastest")
	eq(fake.follow, 12)
	eq(fake.view.z, 120)
end)

test("random places jump like subjects", function()
	world.subjects.place = { x = 300, y = -200, kind = "place", why = "random place" }
	eq(driver.jump("place"), true)
	eq(fake.view.x, 300)
	eq(fake.view.z, cam.FRAMING.place.d)
end)

-- Round 17 (user: "The interesting buttons should always be able to click through and get a new view each time")
test("round 17: 20 clicks on a one-subject pool land on 20 distinct views; the log says which", function()
	local variety = ug_require "square_photo_mode::/photo_mode/pm_variety.lua"
	local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
	local logs = {}
	local oldLog = core.log
	core.log = function(m) logs[#logs + 1] = m end
	local n = 0
	world.pick = function(kind)
		n = n + 1
		-- what pm_world hands over for its only bridge train: the same framing, the variant counting up
		return { entity = 7, x = 100, y = 0, kind = "train", follow = true, why = "bridge", poolKind = "bridge",
			poolN = 1, poolM = 1, variant = n - 1, framing = { x = 100, y = 0, d = 150, p = 0.05, look = 1.0 } }
	end
	local views = {}
	for i = 1, 20 do
		eq(driver.jump("bridge"), true)
		local v = { x = fake.view.x, y = fake.view.y, d = fake.view.z, a = fake.view.w, p = fake.view.q }
		for j, w in ipairs(views) do ok(not variety.same(v, w), "click " .. i .. " repeats click " .. j) end
		views[#views + 1] = v
	end
	core.log = oldLog
	local found = 0
	for __, m in ipairs(logs) do
		if m:find("interesting pick bridge #1 of 1, view variant 19", 1, true) then found = found + 1 end
	end
	eq(found, 1, "the 20th click's log line")
end)

test("round 17: the same subject without a variant twice in a row still gets a new view", function()
	world.subjects.skyline = { entity = 70, x = 0, y = 0, kind = "town", why = "skyline",
		framing = { x = 0, y = 0, d = 1100, p = 0.05, look = 0.3 } }
	driver.jump("skyline")
	local a = { x = fake.view.x, y = fake.view.y, z = fake.view.z, w = fake.view.w, q = fake.view.q }
	driver.jump("skyline")
	ok(a.z ~= fake.view.z or a.w ~= fake.view.w or a.q ~= fake.view.q, "not the identical view")
end)

-- Mouse look while flying, the horizon look and horizon shots (user feedback 2026-10-13)

local function flyAerials(seed)
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.rnd = (function() local r = cam.newRng(seed or 8) return r end)()
	driver.setTourMode("aerial")
	driver.toggleTour()
	step(16)
	step(cam.GLIDE_SECONDS * 1000)
	for __ = 1, 100 do step(100) end -- 10 s into the flight
end

test("Aerials: turning / tilting / zooming is mouse look, kept as an offset; the tour goes on", function()
	flyAerials()
	local fl = driver.S.flight
	clear_logs()
	fake.view.w = cam.wrapAngle(fake.view.w + 0.6) -- the player turns the camera
	step(100)
	ok(driver.S.tour ~= nil and driver.S.flight == fl, "still flying")
	ok(driver.S.look ~= nil and math.abs(driver.S.look.a - 0.6) < 1e-6, "offset kept")
	fake.view.q = fake.view.q + 0.1 -- tilt
	fake.view.z = fake.view.z * 1.3 -- zoom
	step(100)
	ok(driver.S.tour ~= nil, "still flying after tilt and zoom")
	ok(driver.S.look.p > 0.05 and driver.S.look.z > 0.2, "tilt and zoom kept")
	local logged = false
	for __, e in ipairs(log_entries()) do if e.msg:find("mouse look kept", 1, true) then logged = true end end
	ok(logged, "logged once")
	-- "Look returns to the path" (default on): back to the flight's own view after a few seconds
	for __ = 1, 100 do step(100) end
	ok(math.abs(driver.S.look.a) < 0.05, "decayed: " .. driver.S.look.a)
	ok(fake.view.z * math.sin(fake.view.q) >= 30 - 1e-6, "eye above the ground")
	-- a pan still stops the tour
	fake.view.x = fake.view.x + 400
	step(16)
	eq(driver.S.tour, nil)
end)

test("Aerials: with 'Look returns to the path' off the offset stays; hops still stop on a turn", function()
	driver.setLookReturn(false)
	flyAerials(9)
	fake.view.w = cam.wrapAngle(fake.view.w + 0.4)
	step(100)
	for __ = 1, 100 do step(100) end
	near(driver.S.look.a, 0.4, 1e-6)
	driver.stopAll("test")
	-- ground level: a turn stops the tour as before
	world.subjects.town = { entity = 3, x = 2000, y = 0, kind = "town" }
	driver.setTourMode("ground")
	driver.toggleTour()
	step(16)
	step(500)
	fake.view.w = cam.wrapAngle(fake.view.w + 0.4)
	step(16)
	eq(driver.S.tour, nil)
end)

test("Aerials look Horizon: high, nearly level, distance within the zoom limit", function()
	driver.setAerialLook("horizon")
	flyAerials(11)
	ok(driver.S.flight.look == "horizon")
	for __ = 1, 50 do
		step(100)
		ok(fake.view.q < 0.3, "nearly level: " .. fake.view.q)
		ok(fake.view.z <= cam.ZOOM_LIMIT + 1e-6, "within the zoom limit: " .. fake.view.z)
		ok(fake.view.x >= -10000 and fake.view.x <= 10000, "centre on the map")
	end
	driver.setAerialLook("sideways")
	eq(driver.S.aerialLook, "horizon", "unknown looks ignored")
end)

test("round 13: Aerials is the default tour mode (its preset ranges too)", function()
	reset_modules()
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", world)
	local c = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
	local d = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua"
	eq(c.TOUR_MODE_DEFAULT, "aerial")
	eq(d.S.tourMode, "aerial")
	eq(d.S.rangeSel, c.preset("wander"), "round 22: the ranges are the Tour tab's (Wander across the map)")
	eq(d.S.tourStyle, "wander", "round 22: Wander is the Tour tab's default style")
	eq(d.S.aerialLook, "high", "round 15: High is the default look")
end)

test("round 15: High is the default Aerials look; Down and Horizon stay choosable", function()
	reset_modules()
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", world)
	local c = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
	local d = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua"
	eq(c.AERIAL_LOOK_DEFAULT, "high")
	eq(d.S.aerialLook, "high")
	local found = false
	for __, k in ipairs(c.AERIAL_LOOKS) do if k == c.AERIAL_LOOK_DEFAULT then found = true end end
	ok(found, "the default is one of the looks")
	d.setAerialLook("down")
	eq(d.S.aerialLook, "down")
	d.setAerialLook("horizon")
	eq(d.S.aerialLook, "horizon")
end)

test("round 13: Aerials look High: the look-at point 1.6 km+ out on the sea, the eye about 1 km up, smooth over a jolt the height map doesn't show", function()
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	-- the game: the camera model with a 3 m jolt under the centre where getHeightAt shows none (a stripe every
	-- 40 m, as session 2026-10-14_0606_session's 3 frames)
	local function jolt(x, y) return (math.floor(x / 20) % 2 == 0) and 3 or 0 end
	world.ground = function(x, y) return 40 + 20 * math.sin(x / 300) * math.cos(y / 250) end
	local function centre()
		local v = fake.view
		return v.x, v.y, F.centreZ(world.ground(v.x, v.y) + jolt(v.x, v.y), v.z)
	end
	fake.api.gui.camera.getCenter = function() local x, y, z = centre() return { x = x, y = y, z = z } end
	fake.api.gui.camera.getEye = function()
		local v = fake.view
		local cx, cy, cz = centre()
		local e = F.gameElev(v.q, v.z)
		local L = v.z * math.cos(e)
		return { x = cx - math.cos(v.w) * L, y = cy - math.sin(v.w) * L, z = cz + v.z * math.sin(e) }
	end
	local function reports()
		local n = 0
		for __, e in ipairs(log_entries()) do if e.msg:find("eye spike %d") then n = n + 1 end end
		return n
	end
	driver.setAerialLook("high")
	eq(driver.S.aerialLook, "high")
	flyAerials(12)
	ok(driver.S.flight ~= nil and driver.S.flight.look == "high", "flying the High look")
	clear_logs()
	driver.S.smooth = F.newSmooth()
	for __ = 1, 600 do
		step(16)
		ok(fake.view.z >= F.HIGH.dMin - 1, "the look-at point far out: " .. fake.view.z)
		local __, __, cz = centre()
		near(cz, F.CAM.lift, 1e-9, "the game's centre at sea level")
		local ez = fake.api.gui.camera.getEye().z
		ok(ez > 850 and ez < 1300, "about 1 km up: " .. ez)
	end
	local m = driver.S.smooth
	ok(m.nD2 > 500, "measured: " .. m.nD2)
	ok(m.d2Max < 0.5, "eye d2 " .. m.d2Max)
	eq(reports(), 0)
	driver.stopAll("test")
	-- the Drone look over the same jolts: they step its eye (what the user saw)
	driver.setAerialLook("down")
	flyAerials(12)
	clear_logs()
	for __ = 1, 600 do step(16) end
	local n = reports()
	ok(n >= 1, "the Drone look jolts with the game's centre")
	driver.stopAll("test")
	local total
	for __, e in ipairs(log_entries()) do if e.msg:find("eye smoothness (tour total)", 1, true) then total = e.msg end end
	local spikes = total and tonumber(total:match("spikes=(%d+)"))
	ok(spikes ~= nil and spikes >= n, tostring(total))
	print(string.format("High d2 %.3f m; Drone: %d reports, %s", m.d2Max, n, total:match("d2 max=%S+") .. " spikes=" .. spikes))
end)

test("horizon shots: nearly level from above the current centre; the clamp is logged", function()
	fake.view = { x = 0, y = 0, z = 500, w = 0, q = 0.5 }
	clear_logs()
	driver.shot("horizon")
	ok(fake.view.q < 0.1, "nearly level"); near(fake.view.z * math.sin(fake.view.q), 250, 1e-6)
	ok(math.sqrt(fake.view.x ^ 2 + fake.view.y ^ 2) > 3000, "the centre pushed ahead")
	fake.view = { x = 0, y = 0, z = 500, w = 0, q = 0.5 }
	driver.shot("highhorizon")
	eq(fake.view.z, cam.ZOOM_LIMIT)
	local clamp = false
	for __, e in ipairs(log_entries()) do if e.msg:find("horizon clamped by zoom limit", 1, true) then clamp = true end end
	ok(clamp, "clamp logged")
	-- higher ground ahead: the eye height counts from the ground under the eye
	world.ground = function(x, y) return x > 1000 and 80 or 0 end
	fake.view = { x = 0, y = 0, z = 500, w = 0, q = 0.5 }
	driver.shot("horizon")
	near(fake.view.z * math.sin(fake.view.q), 250 - 80, 1, "eye 250 m over the ground under it")
end)

---------------------------------------------------------------------------
-- Round 6: "This place", camera mode hook, flight candidates once per leg

test("This place: every hop stays around the place, all around the circle; nearby subjects are targets", function()
	local P = ug_require "square_photo_mode::/photo_mode/pm_place.lua"
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.rnd = cam.newRng(21)
	fake.view = { x = 1000, y = 2000, z = 500, w = 0, q = 0.5 }
	local lookups = 0
	world.nearby = function(x, y, r)
		lookups = lookups + 1
		eq(x, 1000); eq(y, 2000); eq(r, P.radius(2))
		return { { entity = 77, x = 1050, y = 2000, kind = "building" },
			{ entity = 78, x = 1000, y = 1900, kind = "road", moving = true } }
	end
	world.subjectPosition = function(s) if s.entity == 78 then return 1010, 1910, 0 end return s.x, s.y, 0 end
	driver.setTourMode("place")
	eq(driver.S.rangeSel, cam.preset("place"))
	driver.setKenBurns(false)
	driver.toggleTour()
	ok(driver.S.tour ~= nil, "started")
	eq(lookups, 1, "the nearby subjects looked up once at the start")
	local plan = driver.S.tour.place.plan
	local sectors, targets = {}, {}
	clear_logs()
	for __ = 1, 3 * P.SECTORS do
		step(16) -- the hop starts
		local v = driver.S.hop.hop.to.base or driver.S.hop.hop.to
		ok(P.inside(plan, v.x, v.y, P.SUBJECT_SLACK), "around the place")
		sectors[plan.last] = true
		step(cam.GLIDE_SECONDS * 1000 + cam.tourSeconds(driver.S.tourChoice) * 1000 + 16)
		ok(driver.S.tour ~= nil, "keeps going until stopped")
	end
	for s = 1, P.SECTORS do ok(sectors[s], "slice " .. s .. " visited") end
	ok(lookups >= 3, "looked up again every few hops (vehicles move): " .. lookups)
	for __, e in ipairs(log_entries()) do
		local id = e.msg:match("tour place %a+ entity=(%d+)")
		if id then targets[id] = true end
	end
	ok(targets["77"] and targets["78"], "both subjects were targets")
	eq(driver.S.tour.mode, "place")
	driver.setTourMode("ground")
	eq(driver.S.tour.mode, "place", "a running place tour keeps its place")
end)

test("This place: a subject that moved out of the area or is gone is skipped", function()
	world.rnd = cam.newRng(4)
	world.nearby = function() return { { entity = 5, x = 10, y = 0, kind = "person", moving = true } } end
	world.subjectPosition = function() return nil end -- gone
	driver.setTourMode("place")
	driver.toggleTour()
	for __ = 1, 10 do
		step(16)
		local v = driver.S.hop.hop.to.base or driver.S.hop.hop.to
		ok(not (v.x == 10 and v.y == 0), "never the gone person")
		step(cam.GLIDE_SECONDS * 1000 + 20000)
	end
end)

test("Aerials: the flight candidates are looked up once per leg, never while flying", function()
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.rnd = cam.newRng(9)
	local calls = 0
	world.flightCandidates = function()
		calls = calls + 1
		return { { x = 2000, y = 0, w = 1, why = "town" }, { x = 4000, y = 1500, w = 1, why = "town" } }
	end
	driver.setTourMode("aerial")
	driver.setLegChoice(1) -- 30 s legs
	driver.toggleTour()
	step(16)
	eq(calls, 1, "one lookup for the first leg")
	local fl = driver.S.flight
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	ok(F.pathLength(fl.path) >= driver.flightDist(fl, 30) + F.FLY.lookAhead, "the whole leg's waypoints are known")
	for __ = 1, 300 do step(100) end -- 30 s: the rest of the first leg
	ok(calls <= 2, "at most the next leg's lookup: " .. calls)
end)

-- Round 7: eye space, Wander

local function bumpy(x, y)
	return 25 * math.sin(x / 31) + 18 * math.cos(y / 17) + 4 * math.sin((x + y) / 9)
end

--- The game's eye of the view we set (the camera model: the centre 4 m over the ground there; look offset 0 in
--- this fake).
local function engineEyeZ()
	local v = fake.view
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	local __, __, z = F.eyeOf({ x = v.x, y = v.y, d = v.z, a = v.w, p = v.q }, bumpy(v.x, v.y), 0)
	return z
end

test("eye space: a tour glide over bumpy ground moves the eye smoothly; a few height reads a frame", function()
	world.ground = bumpy
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.subjects.town = { entity = 3, x = 2000, y = 300, kind = "town" }
	local reads = 0
	local g = world.groundAt
	world.groundAt = function(x, y) reads = reads + 1 return g(x, y) end
	driver.setKenBurns(false)
	driver.toggleTour()
	step(16) -- the hop starts
	local ez, cz, maxReads = {}, {}, 0
	for __ = 1, math.floor(cam.GLIDE_SECONDS * 1000 / 16 * 0.8) do
		reads = 0
		step(16)
		maxReads = math.max(maxReads, reads)
		ez[#ez + 1] = engineEyeZ()
		cz[#cz + 1] = bumpy(fake.view.x, fake.view.y)
	end
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	ok(maxReads <= 2 + 2 * F.EYE.maxIters, "height reads per frame: " .. maxReads)
	local function jerk(list)
		local m = 0
		for i = 2, #list - 1 do m = math.max(m, math.abs(list[i + 1] - 2 * list[i] + list[i - 1])) end
		return m
	end
	ok(jerk(ez) * 20 < jerk(cz), "the eye's height smooth (" .. jerk(ez) .. ") while the ground under the centre jumps ("
		.. jerk(cz) .. ")")
	ok(driver.S.tour ~= nil)
end)

test("Wander (camera move): drifts around the middle of the view without cuts; stops on input or Orbit", function()
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.rnd = cam.newRng(6)
	fake.view = { x = 1000, y = 2000, z = 300, w = 0, q = 0.4 }
	local nearbyCalls = 0
	world.nearby = function() nearbyCalls = nearbyCalls + 1 return { { entity = 9, x = 1050, y = 2010, kind = "building" } } end
	driver.toggleWander()
	ok(driver.S.wander ~= nil and driver.S.wander.manual, "on")
	eq(nearbyCalls, 1)
	local xs, ys = {}, {}
	for __ = 1, 60 * 30 do
		step(16)
		xs[#xs + 1], ys[#ys + 1] = fake.view.x, fake.view.y
	end
	ok(driver.S.wander ~= nil, "still wandering after 30 s")
	eq(driver.S.hop, nil, "no hops, no cuts")
	local maxJump = 0
	for i = 2, #xs do maxJump = math.max(maxJump, math.sqrt((xs[i] - xs[i - 1]) ^ 2 + (ys[i] - ys[i - 1]) ^ 2)) end
	ok(maxJump < 5, "the centre glides, no jump: " .. maxJump)
	for i = 1, #xs, 60 do
		ok(math.abs(xs[i] - 1000) < 1500 and math.abs(ys[i] - 2000) < 1500, "around the place")
	end
	fake.view.z = fake.view.z * 1.5 -- the player zooms
	step(16)
	eq(driver.S.wander, nil, "player input stops it")
	driver.toggleWander()
	driver.toggleOrbit()
	eq(driver.S.wander, nil, "Orbit replaces it")
	eq(driver.S.orbit, true)
	driver.toggleWander()
	eq(driver.S.orbit, false, "and the other way round")
	driver.stopAll("window closed")
	eq(driver.S.wander, nil)
end)

test("Wander tour: continuous around the place, the look moving between nearby subjects; ends with the tour", function()
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.rnd = cam.newRng(12)
	fake.view = { x = 500, y = 500, z = 200, w = 1, q = 0.3 }
	world.nearby = function() return { { entity = 4, x = 520, y = 480, kind = "building" } } end
	driver.setTourMode("wander")
	eq(driver.S.rangeSel, cam.preset("wander"))
	driver.toggleTour()
	ok(driver.S.tour ~= nil and driver.S.wander ~= nil and not driver.S.wander.manual, "a wander tour")
	clear_logs()
	for __ = 1, 60 * 45 do step(16) end
	ok(driver.S.tour ~= nil, "keeps going")
	eq(driver.S.hop, nil); eq(driver.S.flight, nil)
	local looks = 0
	for __, e in ipairs(log_entries()) do if e.msg:find("wander look at", 1, true) then looks = looks + 1 end end
	ok(looks >= 4, "a new look target every few seconds: " .. looks)
	driver.setTourMode("ground")
	eq(driver.S.tour.mode, "wander", "a running wander tour keeps its mode")
	driver.toggleTour()
	eq(driver.S.tour, nil); eq(driver.S.wander, nil)
end)

-- Round 9: the game's camera model (session 2026-10-13_1755: the centre 4 m over the ground, the eye's elevation
-- the pitch blended towards straight down by k(distance)); hover off during automated moves

--- A fake game with the camera model (off(d): how far its elevation is off the model, rad; nil = exactly the
--- model), around the model's centre over the bumpy ground; look offset 0.
local function modelGame(off)
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	world.ground = bumpy
	local function centre()
		local v = fake.view
		return v.x, v.y, F.centreZ(bumpy(v.x, v.y), v.z)
	end
	local function eye()
		local v = fake.view
		local cx, cy, cz = centre()
		local e = F.gameElev(v.q, v.z) + (off and off(v.z) or 0)
		local L = v.z * math.cos(e)
		return cx - math.cos(v.w) * L, cy - math.sin(v.w) * L, cz + v.z * math.sin(e)
	end
	fake.api.gui.camera.getEye = function() local x, y, z = eye() return { x = x, y = y, z = z } end
	fake.api.gui.camera.getCenter = function() local x, y, z = centre() return { x = x, y = y, z = z } end
	return eye
end

local function logged(text)
	local n = 0
	for __, e in ipairs(log_entries()) do if e.msg:find(text, 1, true) then n = n + 1 end end
	return n
end

test("camera model: the residual measured from the game; its eye follows the plan smoothly over bumpy ground", function()
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	local eye = modelGame(function(d) return 0.01 end) -- the game a little off the model
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.subjects.town = { entity = 3, x = 2000, y = 300, kind = "town" }
	fake.view = { x = 0, y = 0, z = 300, w = 0.3, q = 0.35 }
	driver.setKenBurns(false)
	clear_logs()
	driver.toggleTour()
	step(16) -- the hop starts
	local pts, err, minQ = {}, 0, math.huge
	for __ = 1, math.floor(cam.GLIDE_SECONDS * 1000 / 16 * 0.8) do
		step(16)
		local x, y, z = eye()
		pts[#pts + 1] = { x, y, z, driver.S.eye.ez }
		err = math.max(err, math.abs(z - driver.S.eye.ez))
		minQ = math.min(minQ, fake.view.q)
	end
	eq(logged("camera model: first sample"), 1, "the first sample logged once")
	ok(driver.S.camRes > 0.001, "the residual measured: " .. driver.S.camRes)
	-- the 0.01 rad the game is off is corrected over a few seconds (slowly, so terrain noise can't get in): up to
	-- d * 0.01 m meanwhile, as smooth as the plan
	ok(err < 8, "the game's eye near where the plan puts it: " .. err)
	ok(minQ >= 0, "never a pitch below 0 sent: " .. minQ)
	local m = 0
	for i = 2, #pts - 1 do
		local a, b, c = pts[i - 1], pts[i], pts[i + 1]
		m = math.max(m, math.abs(c[3] - 2 * b[3] + a[3]) - math.abs(c[4] - 2 * b[4] + a[4]))
	end
	-- (the glide moves hundreds of m/s, 300-800 m away: half a metre is below 0.002 rad)
	ok(m < 0.5, "as smooth as the plan: its height's second difference at most " .. m .. " m a frame more")
	-- a refused sample keeps the estimate (the game's distance doesn't match the data: still easing)
	local before = driver.S.camRes
	local get = fake.api.gui.camera.getEye
	fake.api.gui.camera.getEye = function() local e = get() return { x = e.x, y = e.y, z = e.z + 500 } end
	step(16)
	eq(driver.S.camRes, before, "a sample whose distance doesn't match is refused")
	fake.api.gui.camera.getEye = get
end)

test("trace and smoothness: the first move's first 40 frames, every Wander with bursts later; eye smoothness lines", function()
	modelGame()
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.subjects.town = { entity = 3, x = 2000, y = 300, kind = "town" }
	fake.view = { x = 0, y = 0, z = 300, w = 0.3, q = 0.35 }
	driver.setKenBurns(false)
	driver.setTourChoice(1)
	clear_logs()
	driver.toggleTour()
	for __ = 1, 60 do step(16) end
	local traces = 0
	for __, e in ipairs(log_entries()) do
		if e.msg:find("cam trace f=", 1, true) then
			traces = traces + 1
			ok(e.msg:find("set=", 1, true) and e.msg:find("eye=", 1, true) and e.msg:find("centre=", 1, true)
				and e.msg:find("model=", 1, true) and e.msg:find("res=", 1, true), e.msg)
			ok(not e.msg:find("eye=-,", 1, true), "the eye read from the first frame on: " .. e.msg)
		end
	end
	eq(traces, 40, "the first 40 frames of the session's first move")
	for __ = 1, 60 * 30 do step(16) end -- more hops
	ok(logged("eye smoothness (hop)") >= 1, "one line per hop")
	driver.toggleTour()
	eq(logged("eye smoothness (tour total)"), 1, "and the move's total when it ends")
	-- a wander is traced every time: 40 frames, then 5-frame bursts (from frame 600 on)
	world.nearby = function() return {} end
	clear_logs()
	driver.toggleWander()
	for __ = 1, 700 do step(16) end
	eq(logged("cam trace f="), 45, "40 + a burst of 5")
	ok(logged("cam trace f=601 ") == 1, "the burst at frame 600")
	driver.toggleWander()
	eq(logged("eye smoothness (wander total)"), 1)
	local line
	for __, e in ipairs(log_entries()) do if e.msg:find("eye smoothness (wander total)", 1, true) then line = e.msg end end
	ok(line:find("d2 max=", 1, true) and line:find("jerk max=", 1, true) and line:find("frames=", 1, true), line)
end)

test("hover: off while a tour, a Wander or the Orbit runs; back when it ends by any path", function()
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.subjects.town = { entity = 3, x = 2000, y = 0, kind = "town" }
	world.nearby = function() return {} end
	local calls = {}
	driver.onAutoMode = function(on) calls[#calls + 1] = on end
	driver.toggleTour()
	eq(calls, { true }, "a tour: off")
	step(16)
	step(16)
	fake.view.z = fake.view.z * 2 -- the player zooms: the tour stops
	step(16)
	eq(calls, { true, false }, "back when the camera input stopped it")
	driver.toggleWander()
	driver.toggleOrbit() -- the Orbit replaces the Wander: still automated, no flicker
	eq(calls, { true, false, true }, "no back-and-forth when one move replaces another")
	driver.stopAll("pause menu")
	eq(calls, { true, false, true, false }, "the pause menu / window close")
	driver.toggleOrbit()
	driver.toggleOrbit()
	eq(calls[#calls], false, "the button")
	driver.setTourMode("aerial")
	driver.toggleTour()
	eq(calls[#calls], true, "Aerials too")
	driver.stopTour("pause key")
	eq(calls[#calls], false, "the pause key escape")
end)

test("round 8: a saved view in the shots pool is a tour hop to exactly that view; the jump goes there too", function()
	world.bounds = { -10000, -10000, 10000, 10000 }
	local saved = { kind = "saved", x = 300, y = 400, view = { x = 300, y = 400, d = 220, a = 1.1, p = 0.45 },
		why = "saved view 2" }
	world.subjects.saved = saved
	driver.setTourSource("random", false)
	driver.setTourSource("places", false)
	eq(cam.ticked(driver.S.tourSources, cam.TOUR_SOURCES), { "shots" })
	driver.setKenBurns(false)
	clear_logs()
	driver.toggleTour()
	step(16)
	local hopTo = driver.S.hop and driver.S.hop.hop.to
	ok(hopTo ~= nil, "a hop")
	eq({ hopTo.x, hopTo.y, hopTo.d, hopTo.a, hopTo.p }, { 300, 400, 220, 1.1, 0.45 }, "the saved view itself")
	local logged = false
	for __, e in ipairs(log_entries()) do if e.msg:find("tour shots saved (saved view 2)", 1, true) then logged = true end end
	ok(logged, "logged as a shot")
	driver.stopAll("test")
	world.subjects.any = saved
	eq(driver.jump("any"), true)
	local got = { fake.view.x, fake.view.y, fake.view.z, fake.view.w, fake.view.q }
	for i, want in ipairs({ 300, 400, 220, 1.1, 0.45 }) do ok(math.abs(got[i] - want) < 1e-6, i .. ": " .. got[i]) end
end)

test("shutter: the primer then the real shot from step, the scale passed, logs and statuses; busy while saving", function()
	local shots = {}
	fake.api.gui.camera.takeScreenshot = function(scale) shots[#shots + 1] = scale end
	fake.api.gui.camera.getSize = function() return { x = 2560, y = 1440 } end
	clear_logs()
	eq(driver.screenshot(2), "primer")
	eq(#shots, 1); eq(shots[1], 1, "a scale-1 primer first")
	-- round 11: a 2x / 4x shot freezes the game: said before it happens
	eq(driver.S.status, "Saving the 2x screenshot: the game freezes for a few seconds.")
	ok(driver.shutterBusy() and driver.busy(), "the step runs even with the window closed")
	step(500)
	eq(#shots, 1)
	step(600)
	eq(#shots, 2); eq(shots[2], 2, "the real shot at the scale asked for")
	-- takeScreenshot returns once the file is written
	eq(driver.S.status, "The screenshot is in the game's screenshots folder.")
	local logs = {}
	for __, e in ipairs(log_entries()) do logs[#logs + 1] = e.msg end
	local all = table.concat(logs, "\n")
	ok(all:find("screenshot primer", 1, true), all)
	ok(all:find("screenshot scale=2 viewport=2560x1440 out=5120x2880 call ms=", 1, true), all)
	eq(driver.screenshot(1), "busy")
	eq(#shots, 2, "ignored while saving")
	ok(driver.S.status:find("Wait", 1, true))
	for __ = 1, 100 do step(100) end
	eq(driver.shutterBusy(), false)
	eq(driver.S.status, "The screenshot is in the game's screenshots folder.")
	eq(driver.screenshot(4), "announce", "no second primer; the freeze said first")
	eq(driver.S.status, "Saving the 4x screenshot: the game freezes for 10 seconds or more.")
	eq(#shots, 2, "not yet: the window shows the status first")
	step(400)
	eq(shots[3], 4)
	eq(driver.screenshot(1), "busy")
	for __ = 1, 200 do step(100) end
	eq(driver.screenshot(1), "shot", "1x: at once, no announcement")
end)

test("shutter: a failing takeScreenshot sets the error status with one log line; stopAll keeps the primer", function()
	fake.api.gui.camera.takeScreenshot = function() error("no screenshot") end
	clear_logs()
	eq(driver.screenshot(1), "error")
	eq(driver.S.status, "The screenshot could not be taken.")
	local n = 0
	for __, e in ipairs(log_entries()) do if e.msg:find("screenshot scale=1 ERROR", 1, true) then n = n + 1 end end
	eq(n, 1)
	eq(driver.shutterBusy(), false)
	local shots = {}
	fake.api.gui.camera.takeScreenshot = function(scale) shots[#shots + 1] = scale end
	driver.screenshot(1)
	step(1000)
	driver.stopAll("test")
	for __ = 1, 30 do step(100) end
	eq(driver.screenshot(2), "announce", "primed once per session, not per stopAll")
	eq(driver.viewportSize(), nil, "no getSize in this fake: nil, no error")
end)

test("round 11: stopMoves (a right click on our view tool) ends the camera moves, not a follow", function()
	eq(driver.stopMoves("right click"), false, "nothing running")
	driver.toggleOrbit()
	eq(driver.stopMoves("right click"), true)
	eq(driver.S.orbit, false)
	world.subjects.road = { entity = 5, x = 0, y = 0, kind = "road", follow = true }
	driver.jump("road") -- round 20: a jump follows the vehicle at once
	eq(driver.stopMoves("right click"), false)
	eq(fake.follow, 5, "a follow stays")
end)

test("round 12: an eye spike (one frame's game eye off the plan) is reported with the solver state before it; none on a smooth glide", function()
	local glitch = nil
	local eye = modelGame(function(d) return 0 end)
	local getEye = fake.api.gui.camera.getEye
	fake.api.gui.camera.getEye = function()
		local e = getEye()
		if glitch then e.z = e.z + glitch end
		return e
	end
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.subjects.town = { entity = 3, x = 2000, y = 300, kind = "town" }
	fake.view = { x = 0, y = 0, z = 300, w = 0.3, q = 0.35 }
	driver.setKenBurns(false)
	driver.setTourChoice(1)
	clear_logs()
	driver.toggleTour()
	for __ = 1, 200 do step(16) end
	eq(logged("eye spike"), 0, "the plan's own glide over bumpy ground: no spike")
	glitch = 8
	step(16)
	glitch = nil
	step(16)
	ok(logged("eye spike 1/") == 1, "reported")
	ok(logged("eye spike   #") >= 3, "with the frames before it")
	local line
	for __, e in ipairs(log_entries()) do if e.msg:find("eye spike   #", 1, true) then line = e.msg end end
	ok(line:find("plan=", 1, true) and line:find("sent=", 1, true) and line:find("lift=", 1, true)
		and line:find("blend=", 1, true) and line:find("reads=", 1, true), line)
	driver.toggleTour()
	local total
	for __, e in ipairs(log_entries()) do if e.msg:find("eye smoothness (tour total)", 1, true) then total = e.msg end end
	ok(total:find("look d2 max=", 1, true), total)
end)

-- Round 13: the smooth camera removed; the eye spike metric at the frames' own times; restores

test("round 13: the smooth camera is gone from the driver", function()
	eq(driver.toggleSmoothCam, nil); eq(driver.smoothClick, nil); eq(driver.stopSmoothCam, nil)
	eq(driver.S.smoothCam, nil)
end)

test("round 13: uneven frame times are no eye spike (the eye read shows last frame's view, paired with its dt)", function()
	modelGame(function(d) return 0 end)
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.subjects.town = { entity = 3, x = 2000, y = 300, kind = "town" }
	fake.view = { x = 0, y = 0, z = 300, w = 0.3, q = 0.35 }
	driver.setKenBurns(false)
	driver.setTourChoice(1)
	clear_logs()
	driver.toggleTour()
	-- 15 ms frames with a 31 ms hitch every 7th (the 0434 session's glides)
	for i = 1, 200 do step(i % 7 == 0 and 31 or 15) end
	eq(logged("eye spike"), 0, "a timed glide with hitches: no spike")
	driver.toggleTour()
	local total
	for __, e in ipairs(log_entries()) do if e.msg:find("eye smoothness (tour total)", 1, true) then total = e.msg end end
	local d2 = tonumber(total:match("d2 max=([%d.]+)"))
	ok(d2 ~= nil and d2 < 0.5, total)
end)

test("round 13: eye spike reports: at most a few per move, so a later move still gets its own; a look jolt reports too", function()
	local glitch = nil
	modelGame(function(d) return 0 end)
	local getEye = fake.api.gui.camera.getEye
	fake.api.gui.camera.getEye = function()
		local e = getEye()
		if glitch then e.z = e.z + glitch end
		return e
	end
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.subjects.town = { entity = 3, x = 2000, y = 300, kind = "town" }
	fake.view = { x = 0, y = 0, z = 300, w = 0.3, q = 0.35 }
	driver.setKenBurns(false)
	driver.setTourChoice(1)
	clear_logs()
	driver.toggleTour()
	for __ = 1, 20 do step(16) end
	-- round 13b: one report per jolt: a glitch every 4 frames is one jolt ...
	for __ = 1, 5 do
		glitch = 8
		step(16)
		glitch = nil
		for __ = 1, 3 do step(16) end
	end
	eq(logged("eye spike " .. "1/"), 1)
	eq(logged("eye spike " .. "2/"), 0, "the frames of one jolt: one report")
	-- ... separate jolts get their own, up to the move's cap
	for __ = 1, 2 * driver.EYE_SPIKE.perMove do
		for __ = 1, driver.EYE_SPIKE.gap + 2 do step(16) end
		glitch = 8
		step(16)
		glitch = nil
	end
	local first = 0
	for __, e in ipairs(log_entries()) do if e.msg:find("eye spike %d") then first = first + 1 end end
	eq(first, driver.EYE_SPIKE.perMove, "capped per move")
	driver.toggleTour()
	driver.toggleTour()
	for __ = 1, 20 do step(16) end
	glitch = 8
	step(16)
	glitch = nil
	step(16)
	local second = 0
	for __, e in ipairs(log_entries()) do if e.msg:find("eye spike %d") then second = second + 1 end end
	ok(second > first, "the next move reports again")
	local line
	for __, e in ipairs(log_entries()) do if e.msg:find("eye spike %d") then line = e.msg end end
	ok(line:find("raw=", 1, true) and line:find("read-sent=", 1, true), line)
	-- a look jolt alone (the game's centre off for one frame, the eye on its path) reports too
	driver.toggleTour()
	driver.toggleTour()
	for __ = 1, 20 do step(16) end
	local getCenter = fake.api.gui.camera.getCenter
	fake.api.gui.camera.getCenter = function() local c = getCenter() return { x = c.x, y = c.y + 80, z = c.z } end
	step(16)
	fake.api.gui.camera.getCenter = getCenter
	step(16)
	local third, jolt = 0, nil
	for __, e in ipairs(log_entries()) do
		if e.msg:find("eye spike %d") then third = third + 1 jolt = e.msg end
	end
	ok(third > second, "reported")
	local lookD2 = tonumber(jolt:match("look d2=([%d.]+)"))
	ok(lookD2 ~= nil and lookD2 > driver.EYE_SPIKE.look, jolt)
	driver.toggleTour()
end)

-- The DEV orbit cutscene's fake game: subject 5 is a road vehicle whose one carriage is 51; eyeAt(t) gives the
-- engine eye. Returns a table with the played maps / files and the speed commands.
local function orbitGame(eyeAt, comps)
	stub_module("square_photo_mode_dev::/square_photo_mode_dev_presence.lua", {})
	reset_modules()
	stub_module("square_photo_mode_dev::/square_photo_mode_dev_presence.lua", {})
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", world)
	driver = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua"
	local g = { playing = false, plays = {}, speeds = {}, speed = 4, t = 0 }
	fake.api.type.ComponentType = { CARRIAGE_LIST = "CL", GAME_SPEED = "GS", CARRIAGE = "C",
		MODEL_INSTANCE_LIST = "MIL", STATION_GROUP = "SG" }
	fake.api.engine = {
		getComponent = function(e, t)
			if t == "GS" then return { speedup = g.speed } end
			local c = (comps or { [5] = { CL = { carriages = { 51 } } } })[e]
			return c and c[t] or nil
		end,
		util = { getWorld = function() return 0 end },
	}
	fake.api.cmd = { makeGameSetSpeedCmd = function(sp) return { speed = sp } end,
		sendCommand = function(c) g.speeds[#g.speeds + 1] = c.speed end }
	fake.api.gui.mission = {
		playCutscene = function(file, lang, map)
			g.plays[#g.plays + 1] = { file = file, map = map }
			g.playing = true
			g.speed = 1 -- the cutscene runs the game at speed 1
		end,
		isCutscenePlaying = function() return g.playing end,
	}
	fake.api.gui.fireReactEvent = function() end
	fake.api.gui.camera.getEye = function() local x, y, z = eyeAt(g.t) return { x = x, y = y, z = z } end
	fake.api.gui.camera.getCenter = function() return { x = 100, y = 0, z = 10 } end
	world.position = function() return 100, 900, 10 end
	world.subjects.road = { entity = 5, x = 100, y = 900, z = 10, kind = "road", follow = true }
	driver.jump("road")
	clear_logs()
	return g
end

local function lineWith(text)
	for __, e in ipairs(log_entries()) do if e.msg:find(text, 1, true) then return e.msg end end
	return nil
end

test("round 13 DEV: with the DEV mod, Orbit after a jump plays the orbit cutscene attached to the vehicle's carriage (map { [ANCHOR] = carriage }); attached, the player's game speed back", function()
	local g = orbitGame(function(t) return 100 + 120 * math.cos(t), 900 + 120 * math.sin(t), 60 end)
	local C = ug_require "square_photo_mode::/photo_mode/gui/pm_cutscene.lua"
	local sets = fake.sets
	driver.toggleOrbit()
	eq(#g.plays, 1, "played")
	eq(g.plays[1].map[C.ANCHOR], 51, "the anchor is the vehicle's carriage, not the vehicle (5)")
	eq(driver.S.orbit, false, "no normal orbit meanwhile")
	for i = 1, 60 do g.t = i * 0.02 step(16) end
	eq(fake.sets, sets, "no setCameraData while the cutscene plays")
	eq(#g.plays, 1, "attached: no stop file")
	ok(lineWith("cutscene orbit attached: eye-subject 130.0 m"), "the verdict, once")
	g.playing = false
	step(16)
	eq(driver.S.cutscene, nil)
	local endLine = lineWith("cutscene orbit end")
	ok(endLine and endLine:find("eye-subject distance 130.0-130.0 m", 1, true), tostring(endLine))
	ok(endLine:find("game speed back to the player's 4 (the cutscene left 1)", 1, true), endLine)
	eq(g.speeds, { 4 }, "the player's speed from before the cutscene")
	ok(logged("cutscene orbit t=") >= 3)
end)

test("round 20: a pause right after a cutscene ends (the skip's Esc) is undone once; a play meanwhile takes the player's speed", function()
	local g = orbitGame(function(t) return 100 + 120 * math.cos(t), 900 + 120 * math.sin(t), 60 end)
	g.speed = 1 -- the player's game runs at 1
	driver.toggleOrbit()
	for i = 1, 10 do g.t = i * 0.02 step(16) end
	g.playing = false
	step(16)
	eq(g.speeds, {}, "game speed 1 kept")
	ok(driver.busy(), "the end is watched")
	eq(driver.playerSpeed(), 1)
	g.speed = 0 -- paused right after the end (2026-10-14_2150_r19-test: the next play read 0)
	eq(driver.playerSpeed(), 1, "a play now takes the player's speed, not the 0 read")
	step(16)
	eq(g.speeds, { 1 }, "put back once")
	ok(lineWith("the game speed went to 0"), "logged with the time since the end")
	step(16)
	eq(g.speeds, { 1 }, "the watch is over")
	-- the pause menu ends the watch (it pauses on purpose); so does SPEED_WATCH_MS
	g.speed = 1
	driver.toggleOrbit()
	for i = 1, 10 do g.t = i * 0.02 step(16) end
	g.playing = false
	step(16)
	driver.stopAll("pause menu")
	g.speed = 0
	step(16)
	eq(g.speeds, { 1 }, "no command after the pause menu")
	g.speed = 1
	driver.toggleOrbit()
	for i = 1, 10 do g.t = i * 0.02 step(16) end
	g.playing = false
	step(16)
	step(driver.SPEED_WATCH_MS + 100)
	g.speed = 0
	step(16)
	eq(g.speeds, { 1 }, "a pause after the watch is the player's")
end)

test("round 20: a jump to a vehicle or person follows it at once; a photographer's framing stays still", function()
	world.subjects.road = { entity = 5, x = 0, y = 0, kind = "road", follow = true }
	driver.jump("road")
	eq(driver.S.follow, 5)
	eq(fake.follow, 5)
	driver.stopAll("test")
	for __ = 1, 20 do step(16) end
	fake.follow = -1
	world.subjects.bridge = { entity = 7, x = 0, y = 0, kind = "train", follow = true,
		framing = { x = 0, y = 0, d = 300, p = 0.4, look = 0 } }
	driver.jump("bridge")
	eq(driver.S.follow, nil, "a framing waits for its subject")
	eq(fake.follow, -1)
end)

test("round 13 DEV / 17: an orbit whose attachment the engine can't resolve (eye circling the map origin) is logged once and said; the player ends it", function()
	local g = orbitGame(function(t) return 120 * math.cos(t), 120 * math.sin(t), 50 end)
	local C = ug_require "square_photo_mode::/photo_mode/gui/pm_cutscene.lua"
	driver.toggleOrbit()
	for i = 1, 60 do g.t = i * 0.02 step(16) end
	eq(#g.plays, 1, "round 17: no stop file (the user cancels it)")
	eq(logged("cutscene orbit NOT attached"), 1)
	ok(driver.S.status:find("Esc", 1, true), "the status says so")
	g.playing = false
	step(16)
	local endLine = lineWith("cutscene orbit end")
	ok(endLine and endLine:find("detached", 1, true), tostring(endLine))
end)

test("round 13 DEV: a subject with no carriage or model transform plays the normal orbit (no cutscene, logged why)", function()
	local g = orbitGame(function() return 0, 0, 0 end, { [5] = {} })
	driver.toggleOrbit()
	eq(#g.plays, 0)
	ok(lineWith("not attachable (no carriage or model transform"), "logged")
	eq(driver.S.orbit, true, "the normal orbit")
	driver.toggleOrbit()
end)

---------------------------------------------------------------------------
-- Round 14: shot presets share one anchor

local function viewNow()
	local v = fake.view
	return { x = v.x, y = v.y, z = v.z, w = v.w, q = v.q }
end
local function sameView(a, b, what)
	for __, k in ipairs({ "x", "y", "z", "w", "q" }) do near(a[k], b[k], 0.01, (what or "") .. " " .. k) end
end
local function anchorLines(kind)
	local n = 0
	for __, e in ipairs(log_entries()) do if e.msg:find("shot anchor " .. kind, 1, true) then n = n + 1 end end
	return n
end

test("round 14: Eye level -> High horizon -> Eye level comes back to the identical view", function()
	world.bounds = { -10000, -10000, 10000, 10000 }
	world.ground = function(x, y) return 20 + 0.01 * x end
	fake.view = { x = 10, y = 20, z = 500, w = 1, q = 0.5 }
	clear_logs()
	driver.shot("eye")
	local first = viewNow()
	eq(first.x, 10); eq(first.w, 1)
	driver.shot("highhorizon")
	ok(math.abs(fake.view.x - 10) + math.abs(fake.view.y - 20) > 1000, "the horizon shot's centre is pushed ahead")
	driver.shot("eye")
	sameView(viewNow(), first, "eye again")
	-- every preset in turn, then the first again
	for __, k in ipairs({ "low", "horizon", "drone", "bird", "highhorizon", "low" }) do driver.shot(k) end
	driver.shot("eye")
	sameView(viewNow(), first, "after a run of presets")
	eq(anchorLines("new"), 1, "one anchor for the whole run")
	ok(anchorLines("kept") >= 8)
end)

test("round 14: a zoom or tilt of the player's keeps the anchor; a pan or a turn takes a new one", function()
	world.bounds = { -10000, -10000, 10000, 10000 }
	fake.view = { x = 100, y = 200, z = 500, w = 0.5, q = 0.5 }
	driver.shot("drone")
	local drone = viewNow()
	fake.view.z, fake.view.q = fake.view.z * 1.4, fake.view.q + 0.2 -- the player zooms and tilts
	driver.shot("highhorizon")
	driver.shot("drone")
	sameView(viewNow(), drone, "zoom / tilt kept the anchor")
	-- a pan: the next shot is framed where the player looks now
	fake.view.x, fake.view.y = fake.view.x + 300, fake.view.y - 40
	clear_logs()
	driver.shot("eye")
	eq(fake.view.x, drone.x + 300); eq(fake.view.y, drone.y - 40)
	ok(lineWith("shot anchor new (camera moved)"), "logged")
	-- a turn
	local eye = viewNow()
	fake.view.w = fake.view.w + 0.4
	driver.shot("low")
	near(fake.view.w, eye.w + 0.4, 1e-9)
	ok(lineWith("shot anchor new (camera turned)"), "logged")
end)

test("round 14: a jump or an automated move takes a new anchor", function()
	world.bounds = { -10000, -10000, 10000, 10000 }
	fake.view = { x = 0, y = 0, z = 500, w = 0, q = 0.5 }
	driver.shot("eye")
	world.subjects.train = { entity = 7, x = 100, y = 50, z = 3, kind = "train", why = "random" }
	driver.jump("train")
	clear_logs()
	driver.shot("eye")
	eq(fake.view.x, 100); eq(fake.view.y, 50)
	ok(lineWith("shot anchor new (jump)"), "logged")
	driver.toggleOrbit()
	step(16)
	driver.toggleOrbit()
	clear_logs()
	local w = fake.view.w
	driver.shot("low")
	near(fake.view.w, w, 1e-9, "framed from where the orbit left the camera")
	ok(lineWith("shot anchor new (camera move)"), "logged")
end)

test("round 14: the anchor survives a NaN read and a missing one", function()
	eq(cam.shotAnchor(nil, nil), nil)
	local a, why = cam.shotAnchor(nil, { x = 1, y = 2, a = 0.3, d = 50 })
	eq(a.x, 1); eq(why, "first")
	local st = { anchor = { x = 1, y = 2, a = 0.3 }, sent = { x = 0 / 0, y = 2, a = 0.3 } }
	a, why = cam.shotAnchor(st, { x = 5, y = 5, a = 0.3, d = 50 })
	eq(a.x, 5); eq(why, "no shot sent")
	a, why = cam.shotAnchor(nil, { x = 0 / 0, y = 2, a = 0.3 })
	eq(a, nil)
end)

test("round 14 DEV: the orbit's pace: an even eye around a moving subject reads 31.4 m/s with no spread; a pulsing one shows it", function()
	-- the subject drives along x at 10 m/s; the eye circles it at the orbit's rate (even) ...
	local O = { r = 120, T = 24 }
	local w = 2 * math.pi / O.T
	local g = orbitGame(function(t) return 100 + 10 * t + O.r * math.cos(w * t), 900 + O.r * math.sin(w * t), 60 end)
	world.position = function() return 100 + 10 * g.t, 900, 10 end
	driver.toggleOrbit()
	for i = 1, 300 do g.t = i * 0.016 fake.now = fake.now + 16 driver.step() end
	g.playing = false
	step(16)
	local line = lineWith("cutscene orbit pace")
	ok(line ~= nil, "pace logged")
	local lo, hi, mean, spread = line:match("pace around the subject ([%d.]+)%-([%d.]+) m/s mean ([%d.]+) spread (%d+) %%")
	near(tonumber(mean), 2 * math.pi * 120 / 24, 0.2, line)
	ok(tonumber(spread) <= 1, line)
	-- ... and one that crawls at each key and rushes between (round 13's speed 1 keys): a big spread
	g = orbitGame(function(t)
		local k = math.floor(t)
		local u = t - k
		local s = k + u * u * (3 - 2 * u) -- eased per 1 s segment
		return 100 + O.r * math.cos(w * s), 900 + O.r * math.sin(w * s), 60
	end)
	driver.toggleOrbit()
	for i = 1, 300 do g.t = i * 0.016 fake.now = fake.now + 16 driver.step() end
	g.playing = false
	step(16)
	line = lineWith("cutscene orbit pace")
	spread = tonumber(line:match("spread (%d+) %%"))
	ok(spread >= 30, line)
end)

test("round 14: the centre fit: frames where the game's centre leaves the model are counted, with the base height and water there", function()
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	-- the game's centre 6 m over getHeightAt + 4 on stripes (a cut the alignments made: the base height shows it)
	local function jolt(x, y) return (math.floor(x / 30) % 3 == 0) and 6 or 0 end
	world.ground = function(x, y) return 40 + 20 * math.sin(x / 300) * math.cos(y / 250) end
	world.baseGroundAt = function(x, y) return world.ground(x, y) + jolt(x, y) end
	world.waterAt = function() return false end
	local function centre()
		local v = fake.view
		return v.x, v.y, F.centreZ(world.ground(v.x, v.y) + jolt(v.x, v.y), v.z)
	end
	fake.api.gui.camera.getCenter = function() local x, y, z = centre() return { x = x, y = y, z = z } end
	fake.api.gui.camera.getEye = function()
		local v = fake.view
		local cx, cy, cz = centre()
		local e = F.gameElev(v.q, v.z)
		local L = v.z * math.cos(e)
		return { x = cx - math.cos(v.w) * L, y = cy - math.sin(v.w) * L, z = cz + v.z * math.sin(e) }
	end
	driver.setAerialLook("down")
	clear_logs()
	flyAerials(12)
	for __ = 1, 300 do step(16) end
	local spike = lineWith("eye spike 1/")
	ok(spike ~= nil and spike:find("base=", 1, true) and spike:find("water=false", 1, true), tostring(spike))
	driver.stopAll("test")
	local line = lineWith("centre fit (tour)")
	ok(line ~= nil, "one line per move")
	local n, off, base, water = line:match("frames=(%d+) off>1m=(%d+) %([%d.]+ %%%) base height fits (%d+), on water (%d+)")
	ok(tonumber(n) > 300, line)
	ok(tonumber(off) > 10, line)
	eq(tonumber(base), tonumber(off), "every off frame fits the base height: " .. line)
	eq(tonumber(water), 0)
	ok(line:find("worst +6.0 m", 1, true), line)
end)

---------------------------------------------------------------------------
-- Round 15: the "fast movement" report (session 2026-10-14_0658_session): nothing of ours sets the camera after a
-- move ends; the hand-back line tells the distance the player gets back

local function logCount(pat)
	local n = 0
	for __, e in ipairs(log_entries()) do if e.msg:find(pat, 1, true) then n = n + 1 end end
	return n
end

test("round 15: after a move ends nothing sets the camera; no 'camera set with no move active' line", function()
	clear_logs()
	driver.toggleOrbit()
	for __ = 1, 30 do step(16) end
	driver.toggleOrbit()
	for __ = 1, 200 do
		if not driver.S.orbit then break end
		step(16)
	end
	eq(driver.S.orbit, false, "round 16: slowed to a stop")
	local sets = fake.sets
	for __ = 1, 300 do step(16) end
	eq(fake.sets, sets, "no set while idle")
	world.subjects.train = { entity = 7, x = 100, y = 50, z = 3, kind = "train", follow = true, why = "random" }
	driver.jump("train")
	driver.shot("eye")
	for __ = 1, 60 do step(16) end
	eq(logCount("camera set with no move active"), 0, "the player's clicks are no stray sets")
end)

test("round 15: a hand-back line at every move end and every shot (distance, eye height, pan speed)", function()
	fake.api.gui.camera.getEye = function() local v = fake.view return { x = v.x, y = v.y, z = 100 } end
	fake.api.gui.camera.getCenter = function() local v = fake.view return { x = v.x, y = v.y, z = 0 } end
	clear_logs()
	driver.toggleOrbit()
	step(16)
	driver.toggleOrbit()
	driver.toggleOrbit() -- round 16: the second press stops it at once
	eq(logCount("hand-back (camera move ended): d=500 m, the eye 100 m over the look-at point, d/height=5.0"), 1)
	ok(logCount("the keys pan ~600 m/s (1.2 x d)") == 1, "the pan speed to expect")
	driver.shot("eye")
	eq(logCount("hand-back (shot eye): d=25 m"), 1)
	-- no camera fakes: nothing raises, no line
	fake.api.gui.camera.getEye = nil
	clear_logs()
	driver.shot("low")
	eq(logCount("hand-back"), 0)
end)

---------------------------------------------------------------------------
-- Round 15 DEV: the cutscene aerial chain (pm_cutscene C.FLY; TESTING.md CD4)

-- The fake game for the chain: anchors on a 50 m grid, the cutscene's clock advanced per step, a second play
-- restarting it (replace = true) or not; the eye exactly above the running plan.
local function flyGame(replace)
	stub_module("square_photo_mode_dev::/square_photo_mode_dev_presence.lua", {})
	reset_modules()
	stub_module("square_photo_mode_dev::/square_photo_mode_dev_presence.lua", {})
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", world)
	driver = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua"
	local C = ug_require "square_photo_mode::/photo_mode/gui/pm_cutscene.lua"
	driver.S.tourMode = "aerial"
	driver.S.aerialLook = "down" -- round 21: the High look never plays the cutscene flight
	world.flyCandidates = function(x, y, r)
		local out = {}
		for gx = math.floor((x - r) / 50) * 50, x + r, 50 do
			for gy = math.floor((y - r) / 50) * 50, y + r, 50 do
				if (gx - x) ^ 2 + (gy - y) ^ 2 <= r * r then
					out[#out + 1] = { entity = math.floor((gx + 50000) * 100000 + gy + 50000), x = gx, y = gy, z = 5 }
				end
			end
		end
		return out
	end
	world.flyStatsText = function() return "fake" end
	local g = { playing = false, plays = {}, speeds = {}, speed = 2, el = 0, auto = {} }
	fake.api.type.ComponentType = { GAME_SPEED = "GS" }
	fake.api.engine = {
		getComponent = function(e, t) if t == "GS" then return { speedup = g.speed } end return nil end,
		util = { getWorld = function() return 0 end },
	}
	fake.api.cmd = { makeGameSetSpeedCmd = function(sp) return { speed = sp } end,
		sendCommand = function(c) g.speeds[#g.speeds + 1] = c.speed end }
	fake.api.gui.mission = {
		playCutscene = function(file, lang, map)
			g.plays[#g.plays + 1] = { file = file, map = map }
			if not g.playing or replace then g.el = 0 end
			g.playing = true
			g.speed = 1
		end,
		isCutscenePlaying = function() return g.playing end,
		getCutsceneElapsedTime = function() return g.el end,
	}
	local function eye()
		local c = driver.S.cutscene
		if c == nil or c.plan == nil then return 0, 0, 0 end
		return C.flyEyeAt(c.plan, g.el)
	end
	fake.api.gui.camera.getEye = function() local x, y, z = eye() return { x = x, y = y, z = z } end
	fake.api.gui.camera.getCenter = function() local x, y, z = eye() return { x = x + 600, y = y, z = 5 } end
	driver.onAutoMode = function(on) g.auto[#g.auto + 1] = on end
	fake.view = { x = 0, y = 0, z = 500, w = math.pi, q = 0.5 }
	g.C = C
	-- one frame: the cutscene's clock on; the end of a flight stops it (a replaced one restarted at 0)
	g.frame = function()
		if g.playing then
			g.el = g.el + 0.05
			if g.el >= C.flyDuration() then g.playing = false end
		end
		step(50)
	end
	clear_logs()
	return g
end

test("round 15 DEV: Aerials with the DEV mod plays a chain of attached flights; a second play replacing the running one hands over seamlessly", function()
	local g = flyGame(true)
	local sets = fake.sets
	driver.toggleTour()
	eq(driver.S.tour, nil, "no normal tour")
	ok(driver.S.cutscene ~= nil and driver.S.cutscene.kind == "fly")
	eq(#g.plays, 1)
	eq(g.plays[1].file, g.C.flyFile(0), "heading east (the look from eye to centre)")
	local m = g.plays[1].map
	for i = 1, g.C.FLY.keys do ok(m[g.C.FLY.anchorBase + i - 1] ~= nil, "placeholder " .. i .. " mapped") end
	eq(g.auto, { true }, "an automated move: hover off, the world lock")
	for __ = 1, 8000 do
		if driver.S.cutscene == nil then break end
		g.frame()
	end
	eq(driver.S.cutscene, nil, "the chain ended")
	eq(#g.plays, g.C.FLY.chain, "one play per flight")
	eq(logged("cutscene fly chain: a second playCutscene REPLACES"), g.C.FLY.chain - 1)
	eq(logged("cutscene fly attached"), g.C.FLY.chain)
	ok(logged("cutscene fly key ") >= g.C.FLY.chain * (g.C.FLY.keys - 2), "a line as keys pass")
	ok(lineWith("cutscene fly end (chain done) after 4 flight(s)"), "the end")
	ok(lineWith("game speed back to the player's 2 (the cutscene left 1)"))
	eq(g.speeds, { 2 })
	eq(fake.sets, sets, "no setCameraData meanwhile")
	eq(g.auto, { true, false })
	ok(lineWith("eye smoothness (cutscene fly)"))
	-- each flight starts where the last ended (the last anchor), same heading
	for i = 2, #g.plays do eq(g.plays[i].file, g.C.flyFile(0)) end
end)

test("round 15 DEV: a second play that does not replace the running one: the chain plays it after the end; the hand-over logged", function()
	local g = flyGame(false)
	driver.toggleTour()
	for __ = 1, 8000 do
		if driver.S.cutscene == nil then break end
		g.frame()
	end
	eq(driver.S.cutscene, nil)
	eq(logged("does NOT replace"), g.C.FLY.chain - 1)
	eq(#g.plays, 1 + 2 * (g.C.FLY.chain - 1), "the lead's play, then again after the end")
	eq(logged("cutscene fly hand-over:"), g.C.FLY.chain - 1)
	ok(lineWith("cutscene fly end (chain done) after 4 flight(s)"))
end)

test("round 15 DEV: Esc (the game's skip) ends the chain early; the window / pause menu plays no further flight", function()
	local g = flyGame(true)
	driver.toggleTour()
	for __ = 1, 100 do g.frame() end
	g.playing = false -- skipped at 5 s
	g.frame()
	eq(driver.S.cutscene, nil)
	eq(#g.plays, 1)
	ok(lineWith("cutscene fly end (ended early at 5.0 of 75 s: Esc / skip or input)"))
	eq(g.speeds, { 2 })
	-- the pause menu during a flight: it plays out, nothing follows
	local g2 = flyGame(true)
	driver.toggleTour()
	for __ = 1, 10 do g2.frame() end
	driver.stopAll("pause menu")
	for __ = 1, 8000 do
		if driver.S.cutscene == nil then break end
		g2.frame()
	end
	eq(#g2.plays, 1, "no further flight")
	ok(lineWith("cutscene fly end (pause menu)"))
end)

test("round 21 DEV: the High look flies the scripted flight, never the 250 m cutscene flight", function()
	local g = flyGame(true)
	world.cands = { { x = 100, y = 100, kind = "town" } }
	driver.S.aerialLook = "high"
	driver.toggleTour()
	eq(#g.plays, 0, "no cutscene")
	ok(lineWith("cutscene fly skipped: the High look flies the scripted flight"), "logged")
	ok(driver.S.tour ~= nil, "the scripted tour")
	driver.toggleTour()
end)

test("round 21 DEV: a flight that does not attach leaves its first anchor out of every later plan", function()
	local g = flyGame(true)
	-- the eye stays at the origin: never above the plan
	fake.api.gui.camera.getEye = function() return { x = 0, y = 0, z = 250 } end
	fake.view = { x = -1700, y = -5000, z = 500, w = math.pi, q = 0.5 }
	driver.toggleTour()
	eq(#g.plays, 1)
	local first = g.plays[1].map[g.C.FLY.anchorBase]
	ok(first ~= nil)
	for __ = 1, 20 do g.frame() end
	ok(lineWith("cutscene fly NOT attached"), "the verdict")
	ok(lineWith("left out of later flights (1 so far)"), "the anchor remembered")
	local seen = false
	for __, c in ipairs(driver.flyFind(-1700, -5000, 100000)) do if c.entity == first then seen = true end end
	ok(not seen, "the bad anchor is no candidate any more")
	driver.stopAll("test")
end)

test("round 15 DEV: no anchors anywhere: the normal Aerials tour (logged why)", function()
	local g = flyGame(true)
	world.flyCandidates = function() return {} end
	world.cands = { { x = 100, y = 100, kind = "town" } }
	driver.toggleTour()
	eq(#g.plays, 0)
	ok(lineWith("cutscene fly plan (start): none"), "logged")
	ok(driver.S.tour ~= nil, "the normal tour instead")
	driver.toggleTour()
end)

---------------------------------------------------------------------------
-- Round 16: the settle (the "fast camera" after a move: a far / flat view eases in to a normal one), the eased
-- orbit, the DEV orbit around a static anchor, the DEV aerial's variety and map edge

-- the fake's eye: the camera model's (pm_flight gameElev) around the view's centre on flat ground
local function modelEye()
	local F = ug_require "square_photo_mode::/photo_mode/pm_flight.lua"
	fake.api.gui.camera.getEye = function()
		local v = fake.view
		local e = F.gameElev(v.q, v.z)
		local h = v.w + math.pi
		return { x = v.x + math.cos(h) * v.z * math.cos(e), y = v.y + math.sin(h) * v.z * math.cos(e), z = 4 + v.z * math.sin(e) }
	end
	fake.api.gui.camera.getCenter = function() local v = fake.view return { x = v.x, y = v.y, z = 4 } end
end

-- an orbit ended at once (two presses) on the view `v`
local function endOrbitOn(v)
	driver.toggleOrbit()
	step(16)
	fake.view = v
	driver.S.last = nil -- the move's own last view (not the player's input)
	driver.toggleOrbit()
	driver.toggleOrbit()
end

test("round 16: the settle: a flat, far view a move hands back eases in to 550 m at pitch 0.6 over 1.5 s; the player's pan goes on", function()
	modelEye()
	clear_logs()
	endOrbitOn({ x = 100, y = 200, z = 900, w = 0.3, q = 0.05 })
	eq(driver.S.orbit, false)
	local line = lineWith("settle (button): d 900 -> 550 m, pitch 0.050 -> 0.600")
	ok(line ~= nil, "logged")
	ok(line:find("the keys will pan ~660 m/s instead of ~1080", 1, true), line)
	ok(driver.busy(), "stepped with the window closed too")
	local sets = fake.sets
	step(16)
	ok(fake.sets > sets, "eases")
	for i = 1, 200 do
		if driver.S.settle == nil then break end
		if i == 20 then fake.view.x = fake.view.x + 40 end -- the player pans meanwhile
		local before = fake.view.z
		step(16)
		ok(fake.view.z <= before + 1e-9, "only closer")
	end
	eq(driver.S.settle, nil, "done")
	near(fake.view.z, 550, 1e-6)
	near(fake.view.q, 0.6, 1e-6)
	near(fake.view.x, 140, 1e-6, "the pan kept")
	near(fake.view.w, 0.3, 1e-9, "the angle kept")
	ok(lineWith("hand-back (settled): d=550 m"), "the settled hand-back")
	eq(logged("camera set with no move active"), 0)
	local after = fake.sets
	for __ = 1, 30 do step(16) end
	eq(fake.sets, after, "nothing after it")
end)

test("round 16: the settle's limits: a view like the game's own, the player's zoom (ending the move or during the settle), a cutscene, stopAll", function()
	local d1, p1 = driver.settleTarget({ d = 1700, p = 0.15 })
	eq(d1, 550); eq(p1, 0.6)
	d1, p1 = driver.settleTarget({ d = 500, p = 0.07 })
	eq(d1, 500, "the Wander's hand-back: nearer is not needed"); eq(p1, 0.6)
	eq(driver.settleTarget({ d = 500, p = 0.5 }), nil, "the game's usual view")
	eq(driver.settleTarget({ d = 250, p = 0.04 }), nil, "an eye-level shot nearby")
	eq(driver.settleTarget({ d = 900, p = 1.2 }), nil, "a steep bird's eye pans like the game's own at that height")
	eq(driver.settleTarget(nil), nil)
	modelEye()
	clear_logs()
	-- the usual view: no settle
	driver.toggleOrbit()
	step(16)
	driver.toggleOrbit()
	driver.toggleOrbit()
	eq(driver.S.settle, nil)
	eq(logged("settle ("), 0)
	-- a move ended by the player's zoom: their distance stays
	driver.toggleOrbit()
	step(16)
	fake.view = { x = 0, y = 0, z = 900, w = 0, q = 0.05 }
	step(16)
	eq(driver.S.orbit, false)
	eq(driver.S.settle, nil, "no settle after the player's zoom")
	-- a zoom during the settle ends it
	endOrbitOn({ x = 0, y = 0, z = 900, w = 0, q = 0.05 })
	ok(driver.S.settle ~= nil)
	step(16)
	step(16)
	fake.view.z = fake.view.z * 0.7
	step(16)
	eq(driver.S.settle, nil)
	ok(lineWith("settle ended by the player's zoom"))
	-- stopAll (the pause menu, the window closing) cancels it; a shot replaces it
	endOrbitOn({ x = 0, y = 0, z = 900, w = 0, q = 0.05 })
	driver.stopAll("pause menu")
	eq(driver.S.settle, nil)
	endOrbitOn({ x = 0, y = 0, z = 900, w = 0, q = 0.05 })
	driver.shot("eye")
	eq(driver.S.settle, nil, "a shot replaces it")
end)

test("round 16: the orbit eases in, slows to a stop at the button, and logs its smoothness", function()
	modelEye()
	clear_logs()
	driver.toggleOrbit()
	local steps = {}
	local last = fake.view.w
	for __ = 1, 150 do
		step(16)
		steps[#steps + 1] = cam.angleDiff(last, fake.view.w)
		last = fake.view.w
	end
	local full = cam.ORBIT_RAD_PER_S * 0.016
	ok(steps[2] < 0.05 * full, "starts gently: " .. steps[2])
	ok(steps[40] > steps[10] and steps[10] > steps[2], "speeds up")
	near(steps[150], full, 1e-9, "full speed after the ease")
	driver.toggleOrbit()
	ok(lineWith("orbit slowing to a stop (button)"))
	eq(driver.S.orbit, true, "still turning")
	local prev = full
	for __ = 1, 200 do
		if not driver.S.orbit then break end
		step(16)
		local s = cam.angleDiff(last, fake.view.w)
		last = fake.view.w
		ok(s <= prev + 1e-12, "slows")
		prev = s
	end
	eq(driver.S.orbit, false)
	ok(lineWith("orbit off (button: slowed to a stop)"))
	local sm = lineWith("eye smoothness (orbit)")
	ok(sm ~= nil, "measured")
	local d2 = tonumber(sm:match("d2 max=([%d.]+)"))
	ok(d2 < 0.05, sm)
end)

test("round 16 DEV: Orbit with no subject jumped to circles the static anchor nearest the view's centre (close views only)", function()
	stub_module("square_photo_mode_dev::/square_photo_mode_dev_presence.lua", {})
	reset_modules()
	stub_module("square_photo_mode_dev::/square_photo_mode_dev_presence.lua", {})
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", world)
	driver = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua"
	local C = ug_require "square_photo_mode::/photo_mode/gui/pm_cutscene.lua"
	local plays = {}
	fake.api.type.ComponentType = { CARRIAGE_LIST = "CL", GAME_SPEED = "GS", CARRIAGE = "C",
		MODEL_INSTANCE_LIST = "MIL", STATION_GROUP = "SG" }
	fake.api.engine = {
		getComponent = function(e, t)
			if t == "GS" then return { speedup = 2 } end
			if t == "MIL" and (e == 77 or e == 78) then return { fatInstances = { {} } } end
			return nil
		end,
		util = { getWorld = function() return 0 end },
	}
	fake.api.cmd = { makeGameSetSpeedCmd = function(sp) return { speed = sp } end, sendCommand = function() end }
	fake.api.gui.mission = {
		playCutscene = function(file, lang, map) plays[#plays + 1] = { file = file, map = map } end,
		isCutscenePlaying = function() return #plays > 0 end,
	}
	fake.api.gui.fireReactEvent = function() end
	world.flyCandidates = function(x, y, r)
		return { { entity = 78, x = x + 150, y = y, z = 3, kind = "CONSTRUCTION" },
			{ entity = 77, x = x + 18, y = y + 24, z = 5, kind = "MODEL_INSTANCE_LIST" } }
	end
	world.flyStatsText = function() return "fake" end
	clear_logs()
	fake.view = { x = 10, y = 20, z = 300, w = 0, q = 0.5 }
	-- round 17: a subject jumped to long ago, far from the view now, is stale: dropped, the middle is orbited
	driver.S.lastJump = { entity = 5, x = 5000, y = 5000, z = 0, kind = "road" }
	world.subjectPosition = function(su) return su.x, su.y, 0 end
	eq(driver.orbitTarget(), "centre")
	driver.toggleOrbit()
	eq(driver.S.lastJump, nil, "the stale subject dropped")
	eq(#plays, 1, "the cutscene orbit")
	eq(plays[1].file, C.ORBIT_FILE)
	eq(plays[1].map[C.ANCHOR], 77, "the nearest static anchor")
	ok(lineWith("cutscene orbit: static anchor 77 (MODEL_INSTANCE_LIST) 30 m from the view's centre"))
	eq(driver.S.orbit, false)
	driver.S.cutscene = nil
	-- a far view: the manual (eased) orbit
	plays = {}
	fake.view = { x = 10, y = 20, z = 800, w = 0, q = 0.5 }
	driver.toggleOrbit()
	eq(#plays, 0)
	eq(driver.S.orbit, true)
	ok(lineWith("cutscene orbit: the view is 800 m out"))
	driver.toggleOrbit() -- not turned yet: stops at once
	eq(driver.S.orbit, false)
	-- no anchor near: the manual orbit
	world.flyCandidates = function() return {} end
	fake.view = { x = 10, y = 20, z = 300, w = 0, q = 0.5 }
	driver.toggleOrbit()
	eq(#plays, 0)
	eq(driver.S.orbit, true)
	ok(lineWith("cutscene orbit: no static anchor within 40 m"))
	ok(driver.S.status:find("middle of the view", 1, true), "round 17: the status says what it orbits")
	eq(driver.orbitTarget(), "centre")
end)

test("round 16 DEV: Aerials starts over a place of interest, a new one each start, every flight's view on the map", function()
	local g = flyGame(true)
	world.bounds = { -6000, -6000, 6000, 6000 }
	world.cands = { { x = -2500, y = -2000, w = 2, why = "town" }, { x = 2000, y = 1500, w = 1, why = "station" },
		{ x = 500, y = 2500, w = 1.5, why = "river" }, { x = -2000, y = 2000, w = 1, why = "industry" } }
	local s = 7
	world.rnd = function() s = (s * 1103515245 + 12345) % 2147483648 return s / 2147483648 end
	local function decode(e)
		local gy = e % 100000 - 50000
		return (e - (gy + 50000)) / 100000 - 50000, gy
	end
	local starts = {}
	for run = 1, 3 do
		clear_logs()
		local n0 = #g.plays
		driver.toggleTour()
		ok(driver.S.cutscene ~= nil, "run " .. run)
		local line = lineWith("cutscene fly plan (start): over ")
		ok(line ~= nil, "a place of interest")
		starts[run] = line:match("over (%a+)")
		for __ = 1, 8000 do
			if driver.S.cutscene == nil then break end
			g.frame()
		end
		eq(driver.S.cutscene, nil)
		ok(lineWith("cutscene fly end (chain done) after 4 flight(s)"))
		-- every anchor's view on the map: decode the anchors from the entity maps, with the file's heading and turn
		for i = n0 + 1, #g.plays do
			local h, k = g.plays[i].file:match("sqpm_fly_(%d)_(%d)%.lua$")
			h, k = tonumber(h), tonumber(k) - g.C.FLY.turns
			for j = 1, g.C.FLY.keys do
				local x, y = decode(g.plays[i].map[g.C.FLY.anchorBase + j - 1])
				ok(g.C.viewInside(world.bounds, x, y, g.C.keyAngle(h, k, j), g.C.reachFor(world.bounds)),
					string.format("run %d flight %d anchor %d at %.0f,%.0f", run, i, j, x, y))
			end
		end
	end
	ok(starts[1] ~= starts[2] and starts[2] ~= starts[3], "a new place each start: " .. table.concat(starts, ", "))
end)
