-- Round 16b: the Weather tab's Foreground (gui/pm_foreground.lua): the low cloud veil and the rain set through pm_sky
-- and put back on every exit (untick, pause menu) when still ours; a value changed elsewhere
-- ends the item.

local M, fk, sets

local function setup()
	reset_modules()
	fk = { now = 0, at = { cloudBase = 1500, cloudTop = 3600, cloudScattering = 0.005, cloudCoverage = 0.3 },
		eye = { x = 0, y = 0, z = 250 }, centre = { x = 300, y = 0, z = 4 }, dust = {} }
	sets = {}
	set_global("api", {
		type = {
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec3f = { new = function(x, y, z) return { x = x, y = y, z = z } end },
			Vec4f = { new = function(a, b, c, d) return { a, b, c, d } end },
			Mat4f = { new = function(...) return { ... } end },
		},
		engine = { terrain = { getHeightAt = function() return 10 end } },
		gui = {
			rendering = {
				getEnvironment = function() return { atmosphere = fk.at } end,
				spawnDust = function(a, b, t) fk.dust[#fk.dust + 1] = { a, b, t } end,
			},
			camera = { getEye = function() return fk.eye end, getCenter = function() return fk.centre end },
		},
	})
	local function apply(v, why, quiet)
		sets[#sets + 1] = { v = v, why = why, quiet = quiet }
		for k, x in pairs(v) do
			if k == "cloud" then fk.at.cloudCoverage = x else fk.at[k] = x end
		end
	end
	stub_module("square_photo_mode::/photo_mode/gui/pm_sky.lua", {
		set = function(v, why) apply(v, why, false) end,
		setLive = function(v, why) apply(v, why, true) end,
	})
	stub_module("square_photo_mode::/photo_mode/gui/pm_world.lua", { nowMs = function() return fk.now end,
		rnd = function() return 0.5 end })
	M = ug_require "square_photo_mode::/photo_mode/gui/pm_foreground.lua"
end

before_each(setup)

test("round 16b: veil values around the eye; restorePlan puts back only what is still ours", function()
	local v = M.veilValues(250, 0.3)
	eq(v.cloudBase, 250 - M.VEIL.below)
	eq(v.cloudTop, 250 + M.VEIL.above)
	eq(v.cloud, M.VEIL.cover)
	eq(M.veilValues(10, 0.9).cloudBase, 0, "never below sea level")
	eq(M.veilValues(10, 0.9).cloud, 0.9, "keeps more cover")
	local put, kept = M.restorePlan({ cloudBase = 1500, cloudTop = 3600 }, { cloudBase = 220, cloudTop = 310 },
		{ cloudBase = 220, cloudTop = 900 })
	eq(put.cloudBase, 1500)
	eq(put.cloudTop, nil)
	eq(kept[1], "cloudTop")
end)

test("round 16b: veil on sets through pm_sky, follows the eye quietly, off puts the player's values back", function()
	M.setVeil(true)
	ok(M.veilOn())
	eq(fk.at.cloudBase, 220)
	eq(fk.at.cloudScattering, M.VEIL.scattering)
	eq(sets[1].quiet, false)
	fk.eye = { x = 0, y = 0, z = 400 }
	fk.now = 1200
	M.step()
	eq(fk.at.cloudBase, 370, "followed the eye")
	eq(sets[#sets].quiet, true)
	M.setVeil(false)
	eq(fk.at.cloudBase, 1500)
	eq(fk.at.cloudTop, 3600)
	eq(fk.at.cloudScattering, 0.005)
	near(fk.at.cloudCoverage, 0.3, 1e-9)
end)

test("round 16b: rain sets the cover past the shader's 0.8 and puts it back; the pause menu ends everything", function()
	M.setRain(true)
	ok(fk.at.cloudCoverage > M.RAIN.threshold)
	M.setVeil(true)
	ok(M.busy())
	M.stopAll("pause menu")
	ok(not M.busy())
	near(fk.at.cloudCoverage, 0.3, 1e-9, "the player's cover back")
	eq(fk.at.cloudBase, 1500)
end)

test("round 16b: a value changed elsewhere ends the item and is not overwritten", function()
	M.setVeil(true)
	fk.at.cloudBase = 900 -- a slider moved
	fk.now = 1500
	M.step()
	ok(not M.veilOn())
	eq(fk.at.cloudBase, 900)
	M.setRain(true)
	fk.at.cloudCoverage = 0.1
	fk.now = 1600
	M.step()
	fk.now = 3700
	M.step()
	ok(not M.rainOn())
	eq(fk.at.cloudCoverage, 0.1)
end)

test("round 17: Dust is gone (the user: bad and too subtle); reset forgets everything", function()
	eq(M.setDust, nil)
	eq(M.DUST, nil)
	M.setVeil(true)
	M.reset()
	ok(not M.busy())
end)

test("round 16b: the Foreground rows", function()
	local function mk(kind) return function(...) return { kind = kind, args = { ... } } end end
	local rows = M.rows({ heading = mk("heading"), row = function(w) return w end, checkBox = mk("check"), note = mk("note") })
	eq(#rows, 4)
	eq(rows[2].kind, "check")
end)

test("round 16b: veil and rain in either order: the player's cover comes back at the end", function()
	M.setVeil(true)
	M.setRain(true)
	ok(fk.at.cloudCoverage > M.RAIN.threshold)
	M.setRain(false)
	near(fk.at.cloudCoverage, M.VEIL.cover, 1e-9, "the veil's own cover")
	M.setVeil(false)
	near(fk.at.cloudCoverage, 0.3, 1e-9)
	M.setRain(true)
	M.setVeil(true)
	M.setVeil(false)
	ok(fk.at.cloudCoverage > M.RAIN.threshold, "the rain keeps its cover")
	M.setRain(false)
	near(fk.at.cloudCoverage, 0.3, 1e-9)
end)
