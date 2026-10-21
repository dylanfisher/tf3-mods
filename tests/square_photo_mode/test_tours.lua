-- Round 22 (pm_driver.lua D.startTab, pm_cam.lua tourModeOf / sourcesFor): the Aerials and Tour tabs. Aerials over
-- the saved views (a route in list order), the Tour's Wander that roams across the map or over the saved views,
-- the Start buttons. A fake camera API and a stubbed pm_world, as test_driver.lua.

local driver, cam, fake, world

local function newFake()
	local f = { view = { x = 0, y = 0, z = 500, w = 0, q = 0.5 }, sets = 0, follow = -1, now = 0 }
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
				followEntity = function(e) f.follow = e end,
				enterFollowCameraCockpit = function() end,
				leaveFollowCameraCockpit = function() end,
				focusPosition = function() f.follow = -1 end,
				setManualCamera = function() end,
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
		rnd = cam and cam.newRng and cam.newRng(3) or function() return 0 end,
		pick = function(kind) return world.subjects[kind] end,
		exists = function() return true end,
		alive = function() return true end,
		mapBounds = function() return world.bounds end,
		clearCache = function() end,
		groundAt = function() return 0 end,
		flightCandidates = function() return world.cands or {} end,
	}
	world.bounds = { -20000, -20000, 20000, 20000 }
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", world)
	cam = ug_require "square_photo_mode::/photo_mode/pm_cam.lua"
	world.rnd = cam.newRng(3)
	driver = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua"
	driver.S.aerialLook = "down"
end)

local function step(ms)
	fake.now = fake.now + ms
	driver.step()
end

local function run(seconds)
	for __ = 1, math.floor(seconds * 10) do
		step(100)
		ok(fake.view.x == fake.view.x and fake.view.y == fake.view.y and fake.view.z == fake.view.z, "finite view")
	end
end

local function views(list)
	driver.viewsProvider = function() return list end
end

local function logged(text)
	local n = 0
	for __, e in ipairs(log_entries()) do if e.msg:find(text, 1, true) then n = n + 1 end end
	return n
end

test("cam: the Tour tab's mode, the sources of each Where, the Stay", function()
	eq(cam.tourModeOf("shots", "map", false), "ground")
	eq(cam.tourModeOf("shots", "map", true), "mixed")
	eq(cam.tourModeOf("shots", "views", true), "ground", "no flights between saved views")
	eq(cam.tourModeOf("shots", "here", true), "place")
	eq(cam.tourModeOf("wander", "map", false), "wander")
	eq(cam.tourModeOf("wander", "here", false), "wander")
	eq(cam.sourcesFor("views", cam.DEFAULT_SOURCES), { views = true })
	eq(cam.sourcesFor("map", { random = true, views = true }), { shots = false, random = true, places = false },
		"the map leaves the saved views out")
	eq(cam.sourcesFor("map", { views = true }), { shots = true, random = false, places = false }, "never none")
	local own = { random = true }
	eq(cam.sourcesFor(nil, own), own, "no Where: the ticked sources as they are")
	eq(cam.staySeconds(1), 30)
	eq(cam.staySeconds(99), 60, "the default")
end)

test("the Tour tab's choices set the range preset; unknown values ignored", function()
	driver.setTourStyle("wander")
	eq(driver.S.rangeSel, cam.preset("wander"))
	driver.setTourStyle("dance")
	eq(driver.S.tourStyle, "wander")
	driver.setTourStyle("shots")
	driver.setTourWhere("here")
	eq(driver.S.rangeSel, cam.preset("place"))
	driver.setTourWhere("moon")
	eq(driver.S.tourWhere, "here")
	driver.setTourWhere("map")
	driver.setTourFlights(true)
	eq(driver.S.rangeSel, cam.preset("mixed"))
	driver.setAerialWhere("views")
	eq(driver.S.aerialWhere, "views")
	driver.setAerialWhere("sea")
	eq(driver.S.aerialWhere, "views")
end)

test("Wander across the map: wanders round one interesting place for the Stay, then glides on to the next", function()
	world.subjects.town = { entity = 1, x = 6000, y = 0, kind = "town", why = "random" }
	world.subjects.station = { entity = 2, x = -6000, y = 4000, kind = "station", why = "random" }
	world.subjects.place = { x = 0, y = -7000, kind = "place", why = "random place" }
	world.subjects.bridge = { entity = 3, x = 9000, y = 9000, kind = "train", why = "bridge" }
	fake.view = { x = 0, y = 0, z = 300, w = 0, q = 0.4 }
	driver.setTourStyle("wander")
	driver.setTourWhere("map")
	driver.setStayChoice(1) -- 30 s
	clear_logs()
	driver.startTab("tour")
	ok(driver.S.tour ~= nil and driver.S.tour.roam, "a roaming tour")
	local w1 = driver.S.wander
	ok(w1 ~= nil and not w1.manual, "a tour wander")
	ok(w1.glideS > cam.GLIDE_SECONDS, "a far place: a longer glide " .. w1.glideS)
	ok(w1.bump > 0, "rising on the way")
	local c1 = { x = w1.w.x, y = w1.w.y }
	ok(c1.x ~= 0 or c1.y ~= 0, "a place of the map, not the view's centre")
	run(w1.glideS + 29)
	eq(driver.S.wander, w1, "still at the first place during its Stay")
	run(2)
	local w2 = driver.S.wander
	ok(w2 ~= w1 and w2 ~= nil, "on to the next place")
	ok(w2.w.x ~= c1.x or w2.w.y ~= c1.y, "a different place")
	eq(logged("tour roam 2 (stay over)"), 1)
	-- the glide leaves from the view the wander sent last: no jump at the hand-over
	local before = { x = fake.view.x, y = fake.view.y }
	step(16)
	ok(math.abs(fake.view.x - before.x) < 60 and math.abs(fake.view.y - before.y) < 60, "no jump at the hand-over")
	run(w2.glideS + 40)
	ok(driver.S.tour ~= nil, "goes on")
	fake.view.x = fake.view.x + 500 -- the player pans
	step(16)
	eq(driver.S.tour, nil)
	eq(driver.S.wander, nil)
end)

test("Wander over the saved views: round each view in list order, the eye on the view's side; none: a status", function()
	driver.setTourStyle("wander")
	driver.setTourWhere("views")
	views({})
	driver.startTab("tour")
	eq(driver.S.tour, nil)
	ok(driver.S.status ~= nil and driver.S.status:find("Save a view first", 1, true), tostring(driver.S.status))
	views({ { id = 7, x = 2000, y = 0, d = 300, a = 0, p = 0.4 }, { id = 8, x = -2000, y = 3000, d = 300, a = 1, p = 0.4 } })
	driver.setStayChoice(1)
	clear_logs()
	driver.startTab("tour")
	local w = driver.S.wander
	ok(w ~= nil, "wandering")
	eq({ w.w.x, w.w.y }, { 2000, 0 }, "the first view first")
	run(w.glideS + 31)
	eq({ driver.S.wander.w.x, driver.S.wander.w.y }, { -2000, 3000 }, "then the second")
	run(driver.S.wander.glideS + 31)
	eq({ driver.S.wander.w.x, driver.S.wander.w.y }, { 2000, 0 }, "then again from the top")
	eq(logged("(view 7)"), 2)
end)

test("Wander across the map with nothing to show: no tour, a status; no next place later: it stays and retries", function()
	world.bounds = nil
	driver.setTourStyle("wander")
	driver.setTourWhere("map")
	driver.startTab("tour")
	eq(driver.S.tour, nil)
	ok(driver.S.status ~= nil)
	world.bounds = { -20000, -20000, 20000, 20000 }
	world.subjects.town = { entity = 1, x = 3000, y = 0, kind = "town", why = "random" }
	driver.setStayChoice(1)
	clear_logs()
	driver.startTab("tour")
	local w = driver.S.wander
	ok(w ~= nil)
	world.subjects.town = nil -- the town is the only subject; gone now
	run(w.glideS + 31)
	eq(driver.S.wander, w, "stays")
	eq(logged("tries again"), 1)
end)

test("Aerials over the saved views: one flight along the views in list order, no legs, a turn before a sharp one", function()
	driver.setAerialWhere("views")
	views({})
	driver.startTab("aerial")
	eq(driver.S.tour, nil, "no saved views: no flight")
	views({ { id = 1, x = 0, y = 0, d = 300, a = 0, p = 0.4 }, { id = 2, x = 4000, y = 0, d = 300, a = 0, p = 0.4 },
		{ id = 3, x = 4000, y = 4000, d = 300, a = 0, p = 0.4 }, { id = 4, x = 4100, y = 4050, d = 300, a = 0, p = 0.4 } })
	clear_logs()
	driver.startTab("aerial")
	step(16)
	local fl = driver.S.flight
	ok(fl ~= nil and fl.route ~= nil, "a route flight")
	eq(fl.legMs, nil, "no legs")
	eq({ fl.path[1].x, fl.path[1].y }, { 0, 0 }, "starts over the first view")
	eq({ fl.path[2].x, fl.path[2].y }, { 4000, 0 }, "heads for the second")
	run(400) -- far enough round the loop for the turn back to the first view
	eq(driver.S.flight, fl, "one flight all along")
	ok(logged("(saved view 3)") >= 1, "the third view")
	eq(logged("(saved view 4)"), 0, "a view 140 m from the last one is passed over")
	ok(logged("(turning to saved view") >= 1, "a turning waypoint before the turn back")
	-- every waypoint turn within the flight's limit
	for i = 2, #fl.path - 1 do
		local a, b, c = fl.path[i - 1], fl.path[i], fl.path[i + 1]
		local turn = math.abs(cam.angleDiff(cam.atan2(b.y - a.y, b.x - a.x), cam.atan2(c.y - b.y, c.x - b.x)))
		ok(turn <= ug_require("square_photo_mode::/photo_mode/pm_flight.lua").FLY.maxTurn + 1e-6,
			"waypoint " .. i .. " turn " .. turn)
	end
	ok(#fl.path < 40, "a bounded path: " .. #fl.path)
end)

test("Start buttons: a tab's button stops its own tour, the other tab's switches to its tour", function()
	world.subjects.town = { entity = 1, x = 3000, y = 0, kind = "town", why = "random" }
	world.cands = { { x = 8000, y = 8000, w = 1, why = "town" } }
	driver.setTourStyle("shots")
	driver.startTab("tour")
	ok(driver.tabRunning("tour") and not driver.tabRunning("aerial"))
	eq(driver.S.tour.mode, "ground")
	driver.startTab("aerial")
	ok(driver.tabRunning("aerial"), "switched to the aerials")
	step(16)
	ok(driver.S.flight ~= nil)
	driver.startTab("aerial")
	eq(driver.S.tour, nil, "stopped")
end)

test("Shots over the saved views: the hops play the views whatever sources are ticked", function()
	views({ { id = 5, x = 100, y = 200, d = 300, a = 0.5, p = 0.4 } })
	driver.setTourStyle("shots")
	driver.setTourWhere("views")
	driver.startTab("tour")
	ok(driver.S.tour ~= nil)
	eq(driver.S.tour.sources, { views = true })
	step(16)
	ok(driver.S.hop ~= nil, "a hop")
	run(cam.GLIDE_SECONDS + 0.5)
	ok(math.abs(fake.view.x - 100) < 60 and math.abs(fake.view.y - 200) < 60, "at the saved view")
end)
