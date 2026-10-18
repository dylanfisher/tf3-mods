-- Round 16b: the Lens (pm_lensdef.lua: buckets, plan, generated keyframe files; gui/pm_lens.lua: the play, the
-- checks, the screenshot, the end with the player's game speed).

local L

before_each(function()
	reset_modules()
	L = ug_require "square_photo_mode::/photo_mode/pm_lensdef.lua"
end)

local KEYDIR = "mods/square_photo_mode/content/mission/keyframes/en/"

local function loadFile(name)
	local f = io.open(KEYDIR .. name .. ".lua", "r")
	if f == nil then return nil end
	local text = f:read("*a")
	f:close()
	local env = setmetatable({}, { __index = _G })
	local chunk = assert(load(text, "@" .. name, "t", env))
	return chunk()(), text
end

local function look(k)
	return math.cos(k.angle) * math.cos(k.pitch), math.sin(k.angle) * math.cos(k.pitch), math.sin(k.pitch)
end

test("round 16b: lenses: fovY = 2 atan(12 / mm), the campaign's 85 mm value, distances keep the frame height", function()
	near(L.fovY(4), 2 * math.atan(12 / 135), 1e-12)
	near(2 * math.atan(12 / 85), 0.28049921989441, 1e-6, "the campaign's 0.2805 is 85 mm on a 24 mm frame")
	near(L.GAME_FOV, 1.0471975803375, 1e-6, "the campaign's usual fovY and the animal models' cameraConfig fov 60")
	for i = 1, #L.LENSES do
		for s = 1, #L.SIZES do
			local d = L.distance(i, s)
			if d ~= nil then
				near(2 * d * math.tan(L.fovY(i) / 2), L.SIZES[s], 1e-6, "frame height at the subject")
				ok(d >= L.D_MIN and d <= L.D_MAX)
			end
		end
	end
	eq(L.distance(5, 6), nil, "400 mm at 640 m would be 10.7 km away: no file")
	ok(L.distance(5, 5) > 5000, "400 mm: far back")
	ok(L.distance(1, 1) < 15, "12 mm: close")
end)

test("round 16b: every generated file exists, is attached to the placeholder with all locks, looks at the aim point", function()
	local all = L.allFiles()
	eq(#all, 3625, "file count (report it when it changes; round 17: 24 headings x 5 elevations)")
	local full = os.getenv("TEST_FULL") ~= nil
	for n, f in ipairs(all) do
		if full or n % 9 == 1 or f.name:find("lensorbit", 1, true) then
			local r = loadFile(f.name)
			ok(r ~= nil, "missing " .. f.name .. ": run uv run tools/gen_lens_keyframes.py")
			eq(#r.camera, #f.keys, f.name)
			for i, k in ipairs(r.camera) do
				local want = f.keys[i]
				eq(k.attachment.entity, L.ANCHOR)
				ok(k.attachment.lockYaw == false and k.attachment.lockPitch == false and k.attachment.lockRoll == false,
					"round 18: every lock off (the camera rides rigidly in the anchor's frame)")
				near(k.fovY, want.fovY, 1e-5)
				near(k.time, want.time, 1e-5)
				for a = 1, 3 do near(k.position[a], want.position[a], 1e-3, f.name) end
				-- looks at (0, 0, AIM_Z) relative to the anchor
				local x, y, z = k.position[1], k.position[2], k.position[3] - L.AIM_Z
				local d = math.sqrt(x * x + y * y + z * z)
				local lx, ly, lz = look(k)
				near((lx * -x + ly * -y + lz * -z) / d, 1, 1e-5, "looks at the subject: " .. f.name)
				ok(k.speed > 0, "speed")
			end
			-- consecutive keys never equal (a zero-length spline: CameraAction's "result.length > .0f")
			for i = 2, #r.camera do
				local a, b = r.camera[i - 1].position, r.camera[i].position
				ok((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2 > 0.01, "keys apart: " .. f.name)
			end
		end
	end
end)

test("round 16b: the hold's speed is its chord over its time (the game's Auto Set Speed); no -0 literal", function()
	local r, text = loadFile(L.holdName(4, 3, 2, 5))
	local a, b = r.camera[1], r.camera[2]
	local chord = math.sqrt((a.position[1] - b.position[1]) ^ 2 + (a.position[2] - b.position[2]) ^ 2
		+ (a.position[3] - b.position[3]) ^ 2)
	near(a.speed, chord / L.HOLD_S, 1e-5)
	near(b.speed, chord / L.HOLD_S, 1e-5)
	ok(not text:find("[^%d%.e]%-0[,%s]"), "no -0")
	eq(L.path("x"), "square_photo_mode::/mission/keyframes/x.lua")
end)

test("round 17: plan: the nearest heading (15 deg), elevation and size; the eye on the look line through the subject", function()
	local aim = { x = 1000, y = 2000, z = 50 }
	-- the player's eye 300 m from the subject, 22 degrees up, heading 100 degrees (looking towards the subject)
	local th, el, d0 = math.rad(100), math.rad(22), 300
	local eye = { x = aim.x - math.cos(el) * math.cos(th) * d0, y = aim.y - math.cos(el) * math.sin(th) * d0,
		z = aim.z + L.AIM_Z + math.sin(el) * d0 }
	local p = assert(L.plan(4, eye, aim))
	eq(p.h, 7, "100 deg -> 105 deg")
	eq(L.ELEVS[p.e], 20, "22 deg -> 20")
	near(p.d0, 300, 1e-6)
	-- the view's frame height at the subject 2 x 300 x tan 30 = 346 m -> 320 m (nearest in ratio), round 20: at
	-- 135 mm that stands 1.8 km out, over L.FAR_D: 160 m (900 m out)
	eq(L.SIZES[p.s], 160)
	ok(p.capped, "capped")
	near(p.d, 160 / (2 * math.tan(L.fovY(4) / 2)), 1e-6)
	ok(p.d > 2 * d0 and p.d <= L.FAR_D, "the telephoto stands back, within L.FAR_D")
	ok(L.text(p):find("tighter to stay within", 1, true))
	eq(p.file, L.path(L.holdName(4, p.s, p.e, 7)))
	local ex, ey, ez = p.eye.x - aim.x, p.eye.y - aim.y, p.eye.z - aim.z - L.AIM_Z
	near(math.sqrt(ex * ex + ey * ey + ez * ez), p.d, 1e-6)
	near(math.atan(-ey, -ex), math.rad(105), 1e-9)
	local w = assert(L.plan(1, eye, aim))
	ok(w.d < d0, "12 mm closer than the player")
	local o = assert(L.plan(4, eye, aim, { orbit = true }))
	eq(o.file, L.path(L.orbitName(4, p.s, p.e)))
	near(o.eye.y, aim.y, 1e-6)
	ok(o.eye.x < aim.x)
	eq((L.plan(4, nil, aim)), nil)
end)

test("round 17: plan in the anchor's frame: the file's heading is the player's minus the anchor's yaw", function()
	local aim = { x = 0, y = 0, z = 0 }
	local th, el, d0 = math.rad(100), math.rad(20), 300
	local eye = { x = -math.cos(el) * math.cos(th) * d0, y = -math.cos(el) * math.sin(th) * d0, z = L.AIM_Z + math.sin(el) * d0 }
	local yaw = math.rad(70)
	local p = assert(L.plan(3, eye, aim, { yaw = yaw }))
	eq(p.h, 2, "100 - 70 = 30 deg in the anchor's frame")
	-- the world eye is the file's offset turned by the yaw: on the player's side (heading 100 deg)
	near(math.atan(-p.eye.y, -p.eye.x), math.rad(100), 1e-9)
	local t = L.turnedEye(p, aim, yaw)
	near(t.x, p.eye.x, 1e-9)
	near(t.y, p.eye.y, 1e-9)
	-- the map's edge: a 400 mm eye 5 km out leaves a 2 km map
	local b = { -1000, -1000, 1000, 1000 }
	local q, why = L.plan(5, eye, aim, { bounds = b })
	eq(q, nil)
	ok(why:find("off the map", 1, true))
	ok(L.plan(1, eye, aim, { bounds = b }) ~= nil, "12 mm stays on it")
end)

-- The engine as 0842 showed it, with lockYaw false (inferred: 0633): the key's position and its look both turn with
-- the anchor's yaw. Where the target shows in that camera, as a share of the frame height.
local function simulatedError(file, anchor, yaw, target)
	local r = loadFile(file)
	local k = r.camera[1]
	local c, s = math.cos(yaw), math.sin(yaw)
	local px, py, pz = k.position[1], k.position[2], k.position[3]
	local ex, ey, ez = anchor.x + c * px - s * py, anchor.y + s * px + c * py, anchor.z + pz
	local a = k.angle + yaw
	local fx, fy, fz = math.cos(a) * math.cos(k.pitch), math.sin(a) * math.cos(k.pitch), math.sin(k.pitch)
	local vx, vy, vz = target.x - ex, target.y - ey, target.z - ez
	local depth = vx * fx + vy * fy + vz * fz
	local qx, qy, qz = vx - depth * fx, vy - depth * fy, vz - depth * fz
	return math.sqrt(qx * qx + qy * qy + qz * qz) / (2 * depth * math.tan(k.fovY / 2))
end

test("round 17: aim: for random views the player's centre lands within L.ACCEPT of the frame of the lens shot's middle", function()
	local seed = 7
	local function r() seed = (seed * 16807) % 2147483647 return seed / 2147483647 end
	local played, refused = 0, 0
	for __, lens in ipairs({ 1, 3, 5 }) do
		for __ = 1, 40 do
			local target = { x = (r() - 0.5) * 4000, y = (r() - 0.5) * 4000, z = 4 }
			local th, el, d0 = r() * 2 * math.pi, math.rad(5 + 40 * r()), 40 + 700 * r()
			local eye = { x = target.x - math.cos(el) * math.cos(th) * d0, y = target.y - math.cos(el) * math.sin(th) * d0,
				z = target.z + math.sin(el) * d0 }
			local cands = {}
			for __ = 1, 25 do
				local a, rad = r() * 2 * math.pi, 1000 * r()
				cands[#cands + 1] = { x = target.x + rad * math.cos(a), y = target.y + rad * math.sin(a), z = 0,
					yaw = (r() - 0.5) * 2 * math.pi }
			end
			if r() < 0.5 then cands[#cands + 1] = { x = target.x + 1, y = target.y - 1, z = 0, yaw = (r() - 0.5) * 6 } end
			local cd, p, err = L.choose(lens, eye, target, cands, {})
			if cd ~= nil and err <= L.ACCEPT then
				played = played + 1
				local sim = simulatedError(p.name, cd, cd.yaw, target)
				ok(sim <= L.ACCEPT + 1e-6, string.format("lens %d: the engine's view puts the centre %.3f off", lens, sim))
				near(sim, err, 1e-3, "the plan's error is the simulated one")
				-- and the look comes from about the player's side (15 deg buckets: within 7.5 deg, one more bucket
				-- when round 18's neighbour search took one)
				local dth = math.abs(((p.theta - p.wantTheta) + math.pi) % (2 * math.pi) - math.pi)
				ok(dth <= math.rad(7.5 + 15 * math.abs(p.dh)) + 1e-9, "heading within 7.5 deg (+15 per bucket step)")
				ok(math.abs(p.dh) <= 1 and math.abs(p.de) <= 1, "at most one bucket step each way")
			else
				refused = refused + 1
			end
		end
	end
	ok(played > 40, "most views with an anchor near the centre play: " .. played)
	ok(refused > 0, "far anchors are refused: " .. refused)
end)

test("round 18: choose: a neighbouring heading / elevation bucket wins when it centres the view better", function()
	eq(L.ACCEPT, 0.2, "round 18: 0.05 -> 0.2 (the 1729 session: 17 of 29 starts refused at 5-24 %)")
	-- the anchor 60 m behind the player's centre, 10 degrees off the player's look: the plain bucket's line from the
	-- anchor misses the centre; one bucket over passes nearer
	local target = { x = 0, y = 0, z = 4 }
	local eye = { x = -800, y = 0, z = 4 + 800 * math.tan(math.rad(12)) }
	local anchor = { x = 60, y = 25, z = 0, yaw = 0 }
	local plain = assert(L.plan(4, eye, anchor, { yaw = 0 }))
	local errPlain = L.centreError(plain, anchor, target)
	local cd, p, err = L.choose(4, eye, target, { anchor }, {})
	ok(cd == anchor)
	ok(err <= errPlain + 1e-9, string.format("never worse than the plain buckets (%.3f vs %.3f)", err, errPlain))
	ok(p.dh ~= 0 or p.de ~= 0 or err == errPlain, "a shifted bucket or the plain one")
	-- an orbit never shifts the heading (it circles)
	local _, po = L.choose(4, eye, target, { anchor }, { orbit = true })
	eq(po.dh, 0)
	-- a shift past the elevation list is no plan
	eq(L.plan(4, { x = -800, y = 0, z = 4 + 800 * math.tan(math.rad(60)) }, anchor, { de = 1 }), nil)
end)

test("round 16b: plan: a hill in the line of sight raises the elevation; no clear one keeps the highest", function()
	local aim = { x = 0, y = 0, z = 0 }
	local eye = { x = -300, y = 0, z = L.AIM_Z + 300 * math.tan(math.rad(6)) }
	-- a ridge 200 m high everywhere farther than 1 km from the subject
	local function ground(x, y) return (x * x + y * y > 1000 ^ 2) and 200 or 0 end
	local p = assert(L.plan(5, eye, aim, { ground = ground }))
	eq(L.ELEVS[p.e], 12, "5 deg would cross the ridge 1 km out; 12 clears it")
	ok(p.raised)
	local p2 = assert(L.plan(5, eye, aim, { ground = function() return 1e6 end }))
	eq(p2.e, #L.ELEVS)
	local p3 = assert(L.plan(5, eye, aim, { ground = function() return 0 end }))
	eq(p3.e, 1)
	eq(p3.raised, false)
end)

test("round 16b: the yaw-turned reading and the fov from two projected points", function()
	local p = { offset = { -100, 0, 10 } }
	local t = L.turnedEye(p, { x = 0, y = 0, z = 0 }, math.pi / 2)
	near(t.x, 0, 1e-9)
	near(t.y, -100, 1e-9)
	near(t.z, 10, 1e-9)
	-- a point 50 m up at 1000 m, looked at level, on a 1000 px screen with fov 60 deg: dy = 500 tan(atan(0.05)) / tan(30)
	local dy = 500 * 0.05 / math.tan(math.rad(30))
	near(L.fovFromScreen(1000, 50, 0, dy, 1000), math.rad(60), 1e-9)
	eq(L.fovFromScreen(1000, 50, 0, 0, 1000), nil)
end)

---------------------------------------------------------------------------
-- gui/pm_lens.lua against a fake api and a stubbed driver / world

local M, drv, fk

local function setup(opts)
	opts = opts or {}
	reset_modules()
	fk = { now = 0, playing = false, elapsed = 0, plays = {}, speed = 4, speedSet = {}, events = {}, eye = { x = -400, y = 0, z = 150 },
		centre = { x = 0, y = 0, z = 4 }, shots = {} }
	set_global("api", {
		type = {
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			ComponentType = { GAME_SPEED = "GAME_SPEED", MODEL_INSTANCE_LIST = "MIL", CARRIAGE_LIST = "CL", CARRIAGE = "C",
				STATION_GROUP = "SG" },
		},
		engine = {
			getComponent = function(e, t)
				if t == "GAME_SPEED" then return { speedup = fk.speed } end
				-- round 18: a leaning model (25 degrees about x) for the tilt filter
				if t == "MIL" and opts.tiltEntity ~= nil and e == opts.tiltEntity then
					return { fatInstances = { { transf = { 1, 0, 0, 0, 0, 0.906, 0.423, 0, 0, -0.423, 0.906, 0, 5, 0, 0, 1 } } } }
				end
				return nil
			end,
			util = { getWorld = function() return 1 end },
			terrain = { getHeightAt = function() return 0 end },
		},
		cmd = {
			makeGameSetSpeedCmd = function(s) return { speed = s } end,
			sendCommand = function(c) if c.speed then fk.speedSet[#fk.speedSet + 1] = c.speed fk.speed = c.speed end end,
		},
		gui = {
			fireReactEvent = function(n, v) fk.events[#fk.events + 1] = n .. "=" .. tostring(v) end,
			camera = {
				getEye = function() return fk.eye end,
				getCenter = function() return fk.centre end,
				getSize = function() return { x = 1920, y = 1080 } end,
				world2Screen = function(p) return { x = 960, y = 540 - p.z } end,
			},
			mission = {
				playCutscene = function(file, res, map)
					fk.plays[#fk.plays + 1] = { file = file, res = res, map = map }
					if opts.failPlay then error("bad file") end
				end,
				isCutscenePlaying = function() return fk.playing end,
				getCutsceneElapsedTime = function() return fk.elapsed end,
			},
		},
	})
	local world = {
		nowMs = function() return fk.now end,
		rnd = function() return 0.5 end,
		position = function() return nil end,
		fatPosition = function(e) return 5, 0, 0 end,
		flyCandidates = function(x, y, r)
			if opts.noAnchor then return {} end
			if opts.far then return { { entity = 79, x = x + 3000, y = y + 3000, z = 0, kind = "X" } } end
			if opts.picks then return { { entity = 80, x = x + 1, y = y, z = 0, kind = "X" } } end
			if opts.offBy then return { { entity = 81, x = x, y = y + opts.offBy, z = 0, kind = "X" } } end
			return { { entity = 77, x = 5, y = 0, z = 0, kind = "CONSTRUCTION" }, { entity = 78, x = 40, y = 0, z = 0, kind = "X" } }
		end,
		flyStatsText = function() return "stats" end,
		mapBounds = function() return opts.bounds end,
		pick = function(kind)
			fk.pickN = (fk.pickN or 0) + 1
			return { entity = 900 + fk.pickN, x = fk.pickN * 1000, y = 0, z = 0, kind = kind, why = "random" }
		end,
	}
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", world)
	drv = { S = { version = 0, cutscene = nil, subject = nil, lastJump = nil }, statuses = {}, stops = 0 }
	drv.setStatus = function(t) drv.statuses[#drv.statuses + 1] = t or "(clear)" drv.S.version = drv.S.version + 1 end
	drv.stopMoves = function() drv.stops = drv.stops + 1 end
	drv.screenshot = function(scale) fk.shots[#fk.shots + 1] = scale return "shot" end
	-- round 20: the player's speed (the speed now: no cutscene end watched here) and the watch after an end
	drv.playerSpeed = function()
		return api.engine.getComponent(api.engine.util.getWorld(), api.type.ComponentType.GAME_SPEED).speedup
	end
	drv.watchSpeed = function(want, left, why) fk.watched = { want = want, left = left, why = why } end
	stub_module("square_photo_mode::/photo_mode/gui/pm_driver.lua", drv)
	M = ug_require "square_photo_mode::/photo_mode/gui/pm_lens.lua"
end

local function tick(ms)
	fk.now = fk.now + ms
	if drv.S.cutscene ~= nil then drv.S.cutscene.step(fk.now) end
end

test("round 16b: start plays the planned file with the anchor nearest to the centre mapped to the placeholder", function()
	setup()
	ok(M.start())
	eq(#fk.plays, 1)
	local pl = fk.plays[1]
	ok(pl.file:find("sqpm_lens_t_", 1, true), pl.file)
	eq(pl.res, true)
	eq(pl.map[L.ANCHOR], 77, "the candidate 5 m from the centre")
	eq(drv.stops, 1, "moves stopped first")
	eq(drv.S.cutscene.kind, "lens")
	eq(fk.events[1], "disableToolActions=true")
	ok(drv.statuses[#drv.statuses]:find("Esc", 1, true))
end)

test("round 16b: check, fov line, screenshot at 2.5 s, then the end puts the player's speed back", function()
	setup()
	M.S.shot = 3 -- 2x
	ok(M.start())
	local plan = drv.S.cutscene.plan
	fk.playing = true
	fk.speed = 1 -- the cutscene's
	tick(16)
	-- the eye where the plan wants it
	fk.eye = { x = plan.eye.x, y = plan.eye.y, z = plan.eye.z }
	tick(600)
	tick(500)
	eq(#fk.shots, 0, "not before 2.5 s")
	fk.elapsed = 2.6
	tick(16)
	eq(fk.shots[1], 2)
	fk.playing = false
	tick(16)
	eq(drv.S.cutscene, nil)
	eq(fk.speedSet[1], 4, "the player's speed back")
	eq(fk.events[#fk.events], "disableToolActions=false")
	local saw = false
	for __, e in ipairs(log_entries()) do
		local m = tostring(e.msg)
		if m:find("attached, in the anchor's frame", 1, true) then saw = true end
	end
	ok(saw, "the check line says attached")
end)

test("round 17: a drift is kept; an eye at the raw offsets is said, never stopped; a play that never starts ends", function()
	setup()
	ok(M.start())
	fk.playing = true
	tick(16)
	-- a drifted eye is kept (round 17: 0842 stopped attached tele shots)
	fk.eye = { x = 99999, y = 0, z = 400 }
	tick(600)
	ok(not fk.plays[#fk.plays].file:find("sqpm_stop", 1, true), "a drift is no reason to stop")
	-- the eye at the file's raw offsets around the map origin: not attached
	setup()
	ok(M.start())
	fk.playing = true
	tick(16)
	local p = drv.S.cutscene.plan
	fk.eye = { x = p.offset[1] - 2, y = p.offset[2], z = p.offset[3] } -- nearer the raw offsets than the plan (anchor at 5, 0)
	tick(600)
	ok(not fk.plays[#fk.plays].file:find("sqpm_stop", 1, true), "round 17: never stopped on our own (the user cancels)")
	ok(drv.statuses[#drv.statuses]:find("Esc", 1, true), "the status says it did not attach: press Esc")
	ok(drv.S.cutscene ~= nil, "still playing")
	setup()
	ok(M.start())
	tick(3100)
	eq(drv.S.cutscene, nil, "never started: given up")
	ok(drv.statuses[#drv.statuses] ~= "(clear)")
end)

test("round 16b: no anchor, a running cutscene or a failing play: nothing starts", function()
	setup({ noAnchor = true })
	eq(M.start(), false)
	eq(#fk.plays, 0)
	setup({ failPlay = true })
	eq(M.start(), false)
	eq(drv.S.cutscene, nil)
	setup()
	drv.S.cutscene = { kind = "fly" }
	eq(M.start(), false)
	setup()
	ok(M.start())
	M.reset()
	eq(drv.S.cutscene, nil, "a new game drops it")
end)

test("round 16b: the lens rows build with the window's helpers", function()
	setup()
	local function mk(kind) return function(...) return { kind = kind, args = { ... } } end end
	local UI = { heading = mk("heading"), labelled = mk("labelled"), dropdown = mk("dropdown"), choiceGroup = mk("choice"),
		grid = mk("grid"), button = mk("button"), note = mk("note") }
	local rows = M.rows(UI)
	eq(#rows, 13, "round 19: the Vehicle row")
	eq(rows[2].args[2].args[3], L.LENS_DEFAULT)
	eq(rows[4].args[1], "Vehicle", "round 19")
	eq(rows[7].args[1][1].args[1], "Lens view", "round 17: a short label on a natural-width button (one line)")
	eq(rows[7].args[1][1].args[5], false, "not a fixed-width grid cell")
	-- after a failed try the button's tooltip leads with the reason
	M.S.why = "No object"
	rows = M.rows(UI)
	ok(rows[7].args[1][1].args[2]:find("No object", 1, true))
end)

test("round 17: no anchor near the middle: the status line and the button's tooltip say why", function()
	setup({ noAnchor = true })
	eq(M.start(), false)
	ok(drv.statuses[#drv.statuses]:find("Jump to a town, station or vehicle", 1, true))
	ok(M.S.why ~= nil)
	-- only a far anchor: refused (it would frame something else)
	setup({ far = true })
	eq(M.start(), false)
	eq(#fk.plays, 0)
	ok(M.S.why ~= nil)
	ok(M.S.why:find("close enough to the middle", 1, true), "round 18: says the objects are too far off the middle: " .. tostring(M.S.why))
end)

test("round 17: World: the player's speed (paused stays paused) once it plays, or paused, or normal", function()
	setup()
	fk.speed = 0 -- the player paused
	ok(M.start())
	fk.playing = true
	fk.speed = 1 -- the cutscene's
	tick(16)
	eq(fk.speedSet[#fk.speedSet], 0, "paused again: the player's")
	setup()
	M.setWorld(3)
	fk.speed = 0
	ok(M.start())
	fk.playing = true
	fk.speed = 1
	tick(16)
	eq(#fk.speedSet, 0, "normal: the cutscene's 1 kept")
	-- a paused orbit whose camera stands still: normal speed back
	setup()
	M.setWorld(2)
	M.setMove(2)
	ok(M.start())
	fk.playing = true
	tick(16)
	eq(fk.speedSet[#fk.speedSet], 0)
	tick(1000)
	tick(500)
	eq(fk.speedSet[#fk.speedSet], 1, "the frozen orbit runs at normal speed")
	ok(drv.statuses[#drv.statuses]:find("paused", 1, true))
end)

test("round 17: an end before the attach check logs its reason", function()
	setup()
	ok(M.start())
	fk.playing = true
	tick(16)
	fk.playing = false
	tick(300)
	eq(drv.S.cutscene, nil)
	-- round 20: the end is handed to the driver's speed watch with the player's speed and what the end read
	eq(fk.watched.why, "lens")
	eq(fk.watched.want, fk.speedSet[#fk.speedSet] or fk.watched.left)
	local saw = false
	for __, e in ipairs(log_entries()) do
		if tostring(e.msg):find("before the attach check", 1, true) then saw = true end
	end
	ok(saw)
end)

test("round 17: the lens tour: a scene, a cut to the next after the interval, Esc ends it with the speed back", function()
	setup({ picks = true })
	fk.speed = 2
	M.toggleTour()
	ok(M.S.tour ~= nil)
	eq(#fk.plays, 1)
	ok(fk.plays[1].file:find("sqpm_lens_", 1, true))
	fk.playing = true
	tick(16)
	tick(M.TOUR_EVERYS[M.S.tourEvery] * 1000)
	eq(#fk.plays, 2, "the next scene replaces the playing one")
	eq(M.S.tour.n, 2)
	ok(M.S.tour.recent[1] ~= nil)
	tick(16)
	fk.playing = false
	tick(16)
	tick(16)
	eq(M.S.tour, nil, "Esc ended it")
	eq(fk.speedSet[#fk.speedSet], 2, "the player's speed back")
	-- a scene view of a subject: the eye frames it from 8-30 degrees up
	local eye, c = M.sceneView({ x = 100, y = 200, z = 10, kind = "town" }, function() return 0.5 end)
	eq(c.x, 100)
	ok(eye.z > c.z)
end)

test("round 18: a leaning static anchor is skipped (every lock is off: it would lean the view)", function()
	setup({ tiltEntity = 77 })
	near(M.tiltOf(77), math.rad(25), 0.01)
	eq(M.tiltOf(78), nil, "unreadable: kept")
	M.start()
	ok(#fk.plays == 0 or fk.plays[1].map[L.ANCHOR] ~= 77, "the leaning one is never the anchor")
	setup()
	ok(M.start())
	eq(fk.plays[1].map[L.ANCHOR], 77, "upright: taken")
end)

test("round 18: the cutscene bar's Stop: the stop file over a lens view; the lens tour ends", function()
	setup()
	ok(M.start())
	fk.playing = true
	tick(16)
	M.stopFromBar()
	ok(fk.plays[#fk.plays].file:find("sqpm_stop", 1, true), "the stop file played over it")
	fk.playing = false
	tick(16)
	eq(drv.S.cutscene, nil, "the end follows")
	setup({ picks = true })
	M.toggleTour()
	ok(M.S.tour ~= nil)
	fk.playing = true
	tick(16)
	M.stopFromBar()
	eq(M.S.tour, nil, "the tour ended")
	-- a DEV flight plays no further flight
	setup()
	drv.S.cutscene = { kind = "fly" }
	M.stopFromBar()
	eq(drv.S.cutscene.stopWhy, "stop button")
end)

test("round 16b: the driver steps a cutscene that brings its own step", function()
	reset_modules()
	stub_module("square_photo_mode::/photo_mode/gui/pm_driver.lua", nil)
	set_global("api", { type = { Clock = { new = function() return { getTime = function() return 0 end } end } },
		gui = { camera = {} } })
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", { nowMs = function() return 0 end,
		clearCache = function() end, rnd = function() return 0 end })
	local D = ug_require "square_photo_mode::/photo_mode/gui/pm_driver.lua"
	local n = 0
	D.S.cutscene = { kind = "lens", step = function() n = n + 1 end }
	D.step()
	eq(n, 1)
	D.S.cutscene = nil
end)

test("round 19: plan: a size bucket step (ds) frames tighter / wider; past the list is no plan", function()
	local aim = { x = 0, y = 0, z = 0 }
	local eye = { x = -700, y = 0, z = L.AIM_Z + 700 * math.tan(math.rad(25)) }
	local p0 = assert(L.plan(5, eye, aim, {}))
	local pm = assert(L.plan(5, eye, aim, { ds = -1 }))
	eq(pm.s, p0.s - 1)
	near(pm.d, p0.d / 2, 1e-6, "the sizes double: half the distance")
	eq(pm.ds, -1)
	-- round 20: the player's 891 m frame would stand 5.3 km out: capped at L.FAR_D (80 m, 1333 m out); a wider
	-- step goes past it: no plan
	eq(L.SIZES[p0.s], 80)
	ok(p0.d <= L.FAR_D)
	local pw, whyW = L.plan(5, eye, aim, { ds = 1 })
	eq(pw, nil, "400 mm at 160 m: 2.7 km out")
	ok(whyW:find("over 1500 m out", 1, true), whyW)
	eq(L.plan(5, eye, aim, { ds = -9 }), nil)
	ok(L.text(pm):find("framed tighter", 1, true))
	-- the map's edge: the player's size stands off a 2 km map, a tighter one fits (the 2019 session's refusals)
	local b = { -1000, -1000, 1000, 1000 }
	local okP, why = L.plan(5, eye, aim, { bounds = b })
	eq(okP, nil)
	ok(why:find("off the map", 1, true))
	ok(L.plan(5, eye, aim, { bounds = b, ds = -1 }) ~= nil)
	-- an orbit needs its whole circle on the map
	eq(L.plan(5, eye, aim, { bounds = b, orbit = true }), nil)
	ok(L.plan(5, eye, aim, { bounds = b, orbit = true, ds = -1 }) ~= nil, "the 400 mm orbit plays tighter")
end)

test("round 19: a 400 mm hold or orbit off the map at the player's size plays tighter and says so", function()
	for __, move in ipairs({ 1, 2 }) do
		setup({ bounds = { -1000, -1000, 1000, 1000 } })
		M.setLens(5)
		M.setMove(move)
		fk.eye = { x = -700, y = 0, z = 330 }
		ok(M.start(), "move " .. move)
		local plan = drv.S.cutscene.plan
		ok(plan.ds < 0, "framed tighter: " .. plan.ds)
		ok(drv.statuses[#drv.statuses]:find("Framed tighter", 1, true), drv.statuses[#drv.statuses])
	end
end)

test("round 19: an object off the middle: a wider frame or the nearest object plays; a far one is still refused", function()
	local found = {}
	-- a close view (a ~115 m frame): one or two sizes wider bring the object's centre in; farther off, the nearest
	for __, off in ipairs({ 15, 25, 40, 60, 100, 150, 200, 300, 400 }) do
		setup({ offBy = off })
		M.S.fov0 = L.GAME_FOV
		-- round 20: 50 mm (135 mm stops at 160 m: L.FAR_D)
		local cd, plan, err, how, note = M.prepare(3, { x = -100, y = 0, z = 40 }, { x = 0, y = 0, z = 4 }, false, nil)
		if cd ~= nil then
			ok(err <= L.ACCEPT_ANY)
			if plan.ds > 0 and err <= L.ACCEPT then
				found.wider = true
				ok(note:find("Framed wider", 1, true), note)
			end
		end
	end
	ok(found.wider, "some offset plays wider")
	-- nothing within the limit at any size (a tight limit stands in for a bare landscape): the nearest plays
	setup({ offBy = 60 })
	M.S.fov0 = L.GAME_FOV
	local keep = M.L.ACCEPT
	M.L.ACCEPT = 0.01
	local cd, plan, err, how, note = M.prepare(4, { x = -100, y = 0, z = 40 }, { x = 0, y = 0, z = 4 }, false, nil)
	M.L.ACCEPT = keep
	ok(cd ~= nil and err > 0.01 and err <= L.ACCEPT_ANY)
	ok(note:find("nearest", 1, true), note)
	ok(how:find("NEAREST OBJECT", 1, true))
	setup({ far = true })
	eq(M.start(), false, "4 km off: refused")
end)

test("round 19: Vehicle Steady leaves the followed vehicle out of the anchors (and the tour's)", function()
	setup()
	drv.S.subject = { entity = 4242 }
	local seen = {}
	local prep = M.prepare
	M.prepare = function(i, eye, c, orbit, subj) seen[#seen + 1] = subj return prep(i, eye, c, orbit, subj) end
	ok(M.start())
	eq(seen[1], drv.S.subject, "Ride along: the followed vehicle is a candidate")
	setup()
	drv.S.subject = { entity = 4242 }
	M.setVehicle(2)
	seen = {}
	prep = M.prepare
	M.prepare = function(i, eye, c, orbit, subj) seen[#seen + 1] = subj or false return prep(i, eye, c, orbit, subj) end
	ok(M.start())
	eq(seen[1], false, "Steady: none")
end)
