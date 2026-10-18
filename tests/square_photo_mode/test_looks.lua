-- pm_looks.lua (pure: looks per climate, ResNames, climate detection, easing, weather and time-lapse plans, sun
-- geometry and placement, the start plan), the generated look environments (content/environments/, written by
-- tools/gen_photo_looks.py) and gui/pm_weather.lua through gui/pm_sky.lua on a fake api (look switch and restore,
-- animations, time-lapse, sun placement, pause menu, game start). plans/square_photo_mode/LOOKS.md.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_photo_mode/"
local MOD_ROOT = here .. "../../mods/square_photo_mode/"

local P, L

before_each(function()
	reset_modules()
	P = ug_require "square_photo_mode::/photo_mode/pm_looks.lua"
	L = ug_require "square_photo_mode::/photo_mode/pm_light.lua"
end)

local function deg(r) return math.deg(r) end

---------------------------------------------------------------------------
-- Pure

--- Every sky + haze + water combination (nil = the climate's own), all three nil left out: the generated files.
local function combos()
	local out = {}
	for i = 0, #P.SKY_ORDER do
		for j = 0, #P.HAZE_ORDER do
			for k = 0, #P.WATER_ORDER do
				if i > 0 or j > 0 or k > 0 then
					out[#out + 1] = { P.SKY_ORDER[i], P.HAZE_ORDER[j], P.WATER_ORDER[k] }
				end
			end
		end
	end
	return out
end

test("looks: ResNames round-trip for every climate and sky + haze + water combination", function()
	eq(#P.SKY_ORDER, 8); eq(#P.HAZE_ORDER, 5); eq(#P.WATER_ORDER, 4)
	eq(#combos(), 9 * 6 * 5 - 1)
	for __, c in ipairs(P.CLIMATE_ORDER) do
		for __, x in ipairs(combos()) do
			local res = P.lookResName(c, x[1], x[2], x[3])
			local c2, s2, h2, w2 = P.parseOurs(res)
			eq(c2, c, res); eq(s2, x[1], res); eq(h2, x[2], res); eq(w2, x[3], res)
		end
	end
	-- keys are unique across the layers (a key names its layer)
	local seen = {}
	for __, layer in ipairs(P.LAYERS) do
		for __, k in ipairs(P.ORDER[layer]) do ok(seen[k] == nil, k); seen[k] = layer end
	end
	eq(P.parseOurs("square_photo_mode::/environments/sqpm_dry_nonsense.env"), nil)
	eq(P.parseOurs("square_photo_mode::/environments/sqpm_dry_orig_orig_orig.env"), nil, "orig x3 is the climate")
	eq(P.parseOurs("square_photo_mode::/environments/sqpm_dry_dramatic_orig.env"), nil, "round 11 names are gone")
	eq(P.parseOurs("square_photo_mode::/environments/sqpm_dry_dramatic_nonsense_orig.env"), nil)
	eq(P.parseOurs("square_photo_mode::/environments/sqpm_dry_soft_background_orig_orig.env"), nil,
		"a haze key in the sky's place")
	eq(P.parseOurs("::/climates/dry/dry.env"), nil)
	eq(P.parseOurs(nil), nil)
	eq(P.lookResName("dry", "dramatic", nil, nil), "square_photo_mode::/environments/sqpm_dry_dramatic_orig_orig.env")
	eq(P.lookResName("dry", nil, nil, "wild"), "square_photo_mode::/environments/sqpm_dry_orig_orig_wild.env")
	eq(P.lookResName("dry", "dramatic", "soft_background", "mirror"),
		"square_photo_mode::/environments/sqpm_dry_dramatic_soft_background_mirror.env")
	eq(P.lookResName("dry", nil, nil, nil), nil, "all the climate's own: no look")
	eq(P.lookResName("dry", "orig", "nonsense", "stormy"), nil, "unknown keys count as the climate's own")
	eq(P.lookKey(nil, "hazy_morning", "orig"), "orig_hazy_morning_orig")
end)

test("looks: climate from the game's environment ResName", function()
	eq(P.climateOf("::/climates/dry/dry.env"), "dry")
	eq(P.climateOf("::/climates/subarctic/subarctic.env"), "subarctic")
	local c, how = P.climateOf("square_photo_mode::/environments/sqpm_tropical_storybook_orig_clear.env")
	eq(c, "tropical"); eq(how, "ours")
	c, how = P.climateOf("urbangames_campaign_mission_05::norway.env")
	eq(c, "subarctic"); eq(how, "keyword")
	eq(P.climateOf("mission7_dry.env"), "dry")
	eq(P.climateOf("::/climates/subarctic/subarctic2.env"), "subarctic")
	eq(P.climateOf("somemod::/climates/mars/mars.env"), nil, "unknown climate: no looks")
	eq(P.climateOf(""), nil); eq(P.climateOf(nil), nil)
	eq(P.originalResName("::/climates/dry/dry.env", "dry"), "::/climates/dry/dry.env")
	eq(P.originalResName(P.lookResName("dry", "dramatic", nil, "wild"), "dry"), "::/climates/dry/dry.env", "never back to ours")
	eq(P.originalResName(nil, "temperate"), "::/climates/temperate/temperate.env")
	eq(P.originalResName(nil, nil), nil)
end)

test("looks: every generated environment exists, is a tool environment and matches its climate", function()
	local n = 0
	for __, c in ipairs(P.CLIMATE_ORDER) do
		for __, x in ipairs(combos()) do
			local path = MOD_ROOT .. "content/environments/sqpm_" .. c .. "_" .. P.lookKey(x[1], x[2], x[3]) .. ".env.lua"
			local f = io.open(path, "r")
			ok(f ~= nil, "missing " .. path .. " (run uv run tools/gen_photo_looks.py)")
			if f ~= nil then
				local src = f:read("*a")
				f:close()
				local env = { _ = function(s) return s end }
				local chunk = assert(load(src, "=" .. path, "t", env))
				chunk()
				local d = env.data()
				eq(d.isToolEnvironment, true, path .. ": hidden from the environment list")
				ok(P.isOurName(d.name), path .. ": name " .. tostring(d.name))
				near(d.light.latitude, P.CLIMATES[c].lat, 1e-6, path .. ": the climate's latitude")
				ok(d.atmosphere.cloudCoverage ~= nil and d.water ~= nil and d.skyBox ~= nil, path)
				for __, tex in ipairs({ d.skyBox.environmentTex.fileName, d.skyBox.moonTex.fileName, d.water.normalTex,
					d.water.depthColorTex }) do
					eq(tex:sub(1, 3), "::/", path .. ": absolute texture " .. tex)
				end
				n = n + 1
			end
		end
	end
	eq(n, 4 * (9 * 6 * 5 - 1), "round 15: 1076 files")
end)

local function loadLook(c, sky, haze, water)
	local path = MOD_ROOT .. "content/environments/sqpm_" .. c .. "_" .. P.lookKey(sky, haze, water) .. ".env.lua"
	local f = assert(io.open(path, "r"))
	local src = f:read("*a")
	f:close()
	local env = { _ = function(s) return s end }
	assert(load(src, "=" .. path, "t", env))()
	return env.data()
end

local function same(a, b, where)
	if type(a) ~= "table" or type(b) ~= "table" then eq(a, b, where) return end
	for k, v in pairs(a) do same(v, b[k], where .. "." .. tostring(k)) end
	for k in pairs(b) do ok(a[k] ~= nil, where .. "." .. tostring(k) .. " missing") end
end

--- Deep equality as a boolean (no assertion).
local function equal(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return a == b end
	for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

test("looks: a combination is its sky look's, its haze look's and its water look's changes", function()
	for __, c in ipairs(P.CLIMATE_ORDER) do
		for __, sk in ipairs(P.SKY_ORDER) do
			for __, hz in ipairs(P.HAZE_ORDER) do
				for __, wa in ipairs(P.WATER_ORDER) do
					local all = loadLook(c, sk, hz, wa)
					local s, h, w = loadLook(c, sk, nil, nil), loadLook(c, nil, hz, nil), loadLook(c, nil, nil, wa)
					local where = c .. " " .. sk .. "+" .. hz .. "+" .. wa
					-- atmosphere: the water look leaves it as the climate's; a field the sky changed is the sky's, else the haze's
					for k, v in pairs(all.atmosphere) do
						same(v, equal(s.atmosphere[k], w.atmosphere[k]) and h.atmosphere[k] or s.atmosphere[k],
							where .. " atmosphere." .. k)
						ok(equal(s.atmosphere[k], w.atmosphere[k]) or equal(h.atmosphere[k], w.atmosphere[k]),
							where .. " atmosphere." .. k .. ": changed by the sky and the haze")
					end
					-- light: the haze leaves it as the climate's; the sky's, except the water look's overcast fields (Wild)
					for k, v in pairs(all.light) do
						same(v, equal(s.light[k], h.light[k]) and w.light[k] or s.light[k], where .. " light." .. k)
					end
					same(all.water, w.water, where .. " water")
				end
			end
		end
	end
	-- the extremes reached the files
	local d = loadLook("temperate", nil, nil, "wild")
	eq(d.water.normalScale, 6.0); eq(d.water.roughness, 0.6); eq(d.light.hdrExposureOvercast, 0.75)
	eq(loadLook("temperate", nil, nil, "mirror").water.normalScale, 0.0)
	-- Misty valley and Soft background (round 12): absolute, so the same layer in every climate, also under overcast
	for __, c in ipairs(P.CLIMATE_ORDER) do
		local a = loadLook(c, nil, "misty_valley", nil).atmosphere
		eq(a.fogScaleLow, 24.0, c); eq(a.mieScaleHeight, 0.3, c); eq(a.mieScatteringScale, 0.9, c)
		eq(a.mieScatteringScaleOvercast, 0.9, c); eq(a.miePhaseGOvercast, 0.35, c)
		a = loadLook(c, nil, "soft_background", nil).atmosphere
		eq(a.fogScaleLow, 25.0, c); eq(a.mieScaleHeight, 0.4, c)
		eq(a.mieScatteringScale, 0.27, c); eq(a.mieScatteringScaleOvercast, 0.27, c)
		eq(a.mieAbsorptionScale, 0.0, c); eq(a.mieAbsorptionScaleOvercast, 0.0, c)
		eq(a.miePhaseG, 0.1, c); eq(a.miePhaseGOvercast, 0.1, c)
		-- the sky keeps its own Rayleigh: Dramatic + Soft background is Dramatic's sky over the soft veil
		local dr = loadLook(c, "dramatic", "soft_background", nil).atmosphere
		eq(dr.rayScatteringScale, loadLook(c, "dramatic", nil, nil).atmosphere.rayScatteringScale, c)
		eq(dr.mieScatteringScale, 0.27, c); eq(dr.sunBloom, 80, c)
	end
end)

test("round 15 looks: the new skies, haze and water reached the files and keep to their layer", function()
	for __, c in ipairs(P.CLIMATE_ORDER) do
		local base = loadLook(c, nil, nil, "mirror") -- the climate's atmosphere and light (water only changed)
		-- Golden glow: an ozone layer absorbing blue, a long sunset glow, a warm fill
		local g = loadLook(c, "golden_glow", nil, nil)
		same(g.atmosphere.absorptionCoeff, { 0.04, 0.3, 0.95 }, c .. " golden ozone")
		eq(g.atmosphere.absorptionScale, 0.012, c); eq(g.atmosphere.sunsetBoostParam, 0.5, c)
		ok(g.light.ambientDayColor[1] > g.light.ambientDayColor[3], c .. ": a warm fill")
		-- Cold blue: ozone absorbing red / green, a cool fill, half the sunset glow
		local cb = loadLook(c, "cold_blue", nil, nil)
		ok(cb.atmosphere.absorptionCoeff[3] < cb.atmosphere.absorptionCoeff[1], c .. ": ozone takes red, keeps blue")
		ok(cb.light.ambientDayColor[3] > cb.light.ambientDayColor[1], c .. ": a cool fill")
		near(cb.atmosphere.sunsetBoostScale, base.atmosphere.sunsetBoostScale * 0.5, 1e-6, c)
		-- Faded film: half a point less contrast (the tone mapper's saturation follows it), still in range
		local v = loadLook(c, "vintage", nil, nil)
		near(v.light.hdrContrastDay[1], base.light.hdrContrastDay[1] - 0.5, 1e-6, c)
		ok(v.light.hdrContrastDay[1] >= 0.5, c .. ": contrast within the generator's range")
		-- Neon dusk: green-absorbing ozone (magenta twilight), a strong sunset glow
		local nd = loadLook(c, "neon_dusk", nil, nil)
		ok(nd.atmosphere.absorptionCoeff[2] > nd.atmosphere.absorptionCoeff[1], c .. ": ozone takes green")
		eq(nd.atmosphere.sunsetBoostScale, 7.0, c)
		-- the sky looks leave the haze's and the water's fields alone
		for __, sk in ipairs({ g, cb, v, nd }) do
			eq(sk.atmosphere.mieScatteringScale, base.atmosphere.mieScatteringScale, c)
			same(sk.water, loadLook(c, "golden_glow", nil, nil).water, c .. " water")
		end
		-- Dust storm: a warm, blue-absorbing aerosol spread high, the same under clouds
		local d = loadLook(c, nil, "dust_storm", nil).atmosphere
		eq(d.mieScatteringScale, 0.2, c); eq(d.mieScatteringScaleOvercast, 0.2, c); eq(d.mieScaleHeight, 1.2, c)
		ok(d.mieAbsorptionCoeff[3] > d.mieAbsorptionCoeff[1], c .. ": the dust absorbs blue")
		eq(d.absorptionScale, base.atmosphere.absorptionScale, c .. ": the haze leaves the ozone (sky) alone")
		-- Tropical turquoise: the tropical depth colours in every climate, clearer water
		local w = loadLook(c, nil, nil, "turquoise").water
		eq(w.depthColorTex, "::/climates/tropical/depthColor.dds", c); eq(w.extinctionCoeff, 0.02, c)
	end
end)

test("round 15: the < / > arrows step through a layer's looks with Original first, wrapping round", function()
	eq(P.stepLook("sky", nil, 1), "soft_light", "Original -> the first look")
	eq(P.stepLook("sky", "soft_light", -1), nil, "the first look -> Original")
	eq(P.stepLook("sky", nil, -1), "legacy", "Original <- wraps to the last (round 16: the whole look Legacy ends the Sky menu)")
	eq(P.stepLook("sky", "neon_dusk", 1), "legacy", "round 16: the last sky look -> Legacy")
	eq(P.stepLook("sky", "legacy", 1), nil, "Legacy, the last -> wraps to Original")
	eq(P.stepLook("sky", "dramatic", 1), "storybook")
	eq(P.stepLook("haze", "orig", 1), "crisp_clear", "ORIG counts as Original")
	eq(P.stepLook("water", "turquoise", 1), nil)
	eq(P.stepLook("water", "nonsense", 1), "mirror", "an unknown key counts as Original")
	eq(P.stepLook("clouds", nil, 1), nil, "an unknown layer")
	-- a full round trip in each direction visits every look once and comes back
	for __, layer in ipairs(P.LAYERS) do
		for __, dir in ipairs({ 1, -1 }) do
			local k, seen = nil, 0
			for __ = 1, #P.MENU[layer] + 1 do
				k = P.stepLook(layer, k, dir)
				seen = seen + 1
			end
			eq(k, nil, layer .. " back at Original after " .. seen .. " steps")
		end
	end
end)

test("round 15 sliders: integer scales, the date, and the throttle on a fake clock", function()
	-- time in minutes, day as is, sun in whole degrees 0..359 (absolute sunRotation)
	eq(L.toSlider("time", 13 * 3600 + 25 * 60 + 40), 13 * 60 + 25)
	eq(L.fromSlider("time", 13 * 60 + 25), (13 * 60 + 25) * 60)
	eq(L.toSlider("time", 86399), 1439); eq(L.toSlider("time", -60), 1439, "wrapped")
	eq(L.toSlider("day", 172), 172); eq(L.toSlider("day", 366), 1, "wrapped"); eq(L.fromSlider("day", 400), 365, "clamped")
	eq(L.toSlider("sun", 0), 0); eq(L.toSlider("sun", -math.pi / 2), 270); eq(L.toSlider("sun", math.pi), 180)
	near(L.fromSlider("sun", 270), -math.pi / 2, 1e-9, "270 degrees is -pi/2 (sunRotation in (-pi, pi])")
	near(L.fromSlider("sun", 90), math.pi / 2, 1e-9)
	for i = 0, 359 do eq(L.toSlider("sun", L.fromSlider("sun", i)), i, "round trip " .. i) end
	eq(L.toSlider("time", nil), nil); eq(L.toSlider("clouds", 0.5), nil); eq(L.fromSlider("time", 0 / 0), nil)
	local m, d = L.dayToDate(1); eq(m, 1); eq(d, 1)
	m, d = L.dayToDate(172); eq(m, 6); eq(d, 21, "midsummer is 21 June")
	m, d = L.dayToDate(355); eq(m, 12); eq(d, 21)
	m, d = L.dayToDate(365); eq(m, 12); eq(d, 31)
	m, d = L.dayToDate(59); eq(m, 2); eq(d, 28)
	-- the throttle: the first value goes out at once, then at most one every 80 ms, the last one trailing
	local t = L.newThrottle(80, 400)
	local live = {}
	local function input(v, now) local w = L.throttleInput(t, v, now); if w then live[#live + 1] = w end end
	local function step(now)
		local v, kind = L.throttleStep(t, now)
		if kind == "live" then live[#live + 1] = v end
		return v, kind
	end
	-- a drag: a value every 16 ms (a frame) for 320 ms
	for i = 0, 20 do
		input(100 + i, i * 16)
		step(i * 16)
	end
	ok(#live >= 4 and #live <= 6, "about one write per 80 ms over 320 ms: " .. #live)
	eq(live[1], 100, "the first value at once")
	-- the mouse stops at 120 (t = 320 ms) and is held: the trailing write sends it within one interval
	local v, kind = step(330)
	ok(live[#live] == 120 or (v == nil and kind == nil), "trailing")
	step(400)
	eq(live[#live], 120, "the value the player stopped on went out")
	-- released: the final value once
	eq(L.throttleRelease(t, 500), 120)
	eq(L.throttleRelease(t, 510), nil, "only once")
	eq(step(2000), nil, "nothing after the release")
	-- no release seen (keyboard, gamepad): final after the settle time, once
	t = L.newThrottle(80, 400)
	live = {}
	input(5, 1000)
	eq(live[1], 5)
	v, kind = step(1200); eq(v, nil)
	v, kind = step(1400); eq(v, 5); eq(kind, "final")
	v, kind = step(2000); eq(v, nil, "settled once")
	-- a clock that never moves (Clock unreadable: 0): the first value goes out, the release still finishes
	t = L.newThrottle(80, 400)
	live = {}
	input(1, 0); input(2, 0); input(3, 0)
	eq(#live, 1); eq(step(0), nil)
	eq(L.throttleRelease(t, 0), 3)
	-- a clock that went back: written again (no stall)
	t = L.newThrottle(80, 400)
	live = {}
	input(1, 5000); input(2, 10)
	eq(#live, 2)
end)

test("easing: smoothstep rests at both ends and climbs monotonically", function()
	eq(P.smoothstep(0), 0); eq(P.smoothstep(1), 1); near(P.smoothstep(0.5), 0.5, 1e-12)
	eq(P.smoothstep(-1), 0); eq(P.smoothstep(2), 1)
	local prev = -1
	for i = 0, 20 do
		local v = P.smoothstep(i / 20)
		ok(v >= prev, "monotone at " .. i)
		prev = v
	end
	ok(P.smoothstep(0.05) < 0.05, "slow start")
	near(P.ease(2, 4, 0.5, "linear"), 3, 1e-12)
end)

test("weather plans: storm from a clear sky to rain, clearing back, low clouds", function()
	local p = P.weatherPlan("storm", { cloud = 0.6 })
	eq(p.from.cloud, 0.1, "starts clear"); eq(p.to.cloud, 1.0); eq(p.dur, 40)
	p = P.weatherPlan("storm", { cloud = 0.05 })
	eq(p.from.cloud, 0.05, "already clearer: from there")
	local v, done = P.weatherAt(p, 20)
	near(v.cloud, 0.05 + 0.95 * 0.5, 1e-9); eq(done, false)
	v, done = P.weatherAt(p, 40)
	eq(v.cloud, 1.0); eq(done, true)
	p = P.weatherPlan("clearing", { cloud = 0.3 })
	eq(p.from.cloud, 0.9); eq(p.to.cloud, 0.0)
	p = P.weatherPlan("lowclouds", { cloud = 0.2, cloudBase = 1500, cloudTop = 3600 }, 5)
	eq(p.dur, 5); eq(p.to.cloudBase, 500); eq(p.to.cloudTop, 1800); eq(p.to.cloud, 0.6)
	ok(p.to.cloudBase < p.to.cloudTop)
	eq(P.weatherPlan("nonsense", {}), nil)
end)

test("time-lapse: sunrise in the morning, sunset in the evening, run at the rate, polar fallback", function()
	local lat = P.CLIMATES.temperate.lat
	local p = P.lapsePlan("sunrise", 172, lat)
	ok(p.from < p.to and p.from > 2 * 3600 and p.to < 8 * 3600, "June sunrise " .. L.clockText(p.from) .. "-" .. L.clockText(p.to))
	p = P.lapsePlan("sunset", 172, lat)
	ok(p.from < p.to and p.from > 17 * 3600 and p.to < 22.5 * 3600, "June sunset " .. L.clockText(p.from) .. "-" .. L.clockText(p.to))
	local t, done = P.lapseAt(p, p.dur / 2)
	near(t, (p.from + p.to) / 2, 1e-6); eq(done, false)
	t, done = P.lapseAt(p, p.dur); eq(t, p.to); eq(done, true)
	p = P.lapsePlan("run", 172, lat, 3600)
	t, done = P.lapseAt(p, 6); eq(t, 3600 + 6 * P.RATE); eq(done, false)
	-- 80 degrees north in June: the sun never sets
	p = P.lapsePlan("sunset", 172, math.rad(80))
	eq(p.from, P.LAPSE.sunset.fallback[1]); eq(p.to, P.LAPSE.sunset.fallback[2])
	eq(P.lapsePlan("nonsense"), nil)
end)

test("sun geometry: south at noon, east in the morning, west in the evening, noon height", function()
	local lat = P.CLIMATES.temperate.lat
	local alt, az = P.solarPosition(172, 12 * 3600, lat)
	near(deg(az), 180, 0.01, "noon: south")
	near(alt, math.pi / 2 - lat + P.declination(172), 1e-9, "noon altitude")
	-- equinox (declination ~0): sunrise near 06:00 due east, sunset near 18:00 due west
	local day = 81
	ok(math.abs(P.declination(day)) < math.rad(1), "day 81 near the equinox")
	alt, az = P.solarPosition(day, 6 * 3600, lat)
	near(deg(alt), 0, 1.0); near(deg(az), 90, 1.5)
	alt, az = P.solarPosition(day, 18 * 3600, lat)
	near(deg(alt), 0, 1.0); near(deg(az), 270, 1.5)
	-- morning azimuths east of south, afternoon west of south
	local _, am = P.solarPosition(172, 9 * 3600, lat)
	local _, pm = P.solarPosition(172, 15 * 3600, lat)
	ok(am < math.pi and pm > math.pi, "am " .. deg(am) .. " pm " .. deg(pm))
	near(am + pm, 2 * math.pi, 1e-9, "symmetric round noon")
	-- the clock and the altitude agree with pm_light's sun time
	local tg = L.sunTime(172, math.rad(6), true, lat)
	alt = P.solarPosition(172, tg, lat)
	near(deg(alt), 6, 0.05)
end)

test("sun placement: the sun ends at the asked heading for every calibration", function()
	local cals = {
		{ north = math.pi / 2, sign = 1 }, { north = math.pi / 2, sign = -1 },
		{ north = -math.pi / 2, sign = 1 }, { north = 0, sign = -1 },
	}
	for __, cal in ipairs(cals) do
		for __, look in ipairs({ -3, -1.2, 0, 0.7, 2.9 }) do
			for __, az in ipairs({ 1.0, math.pi, 4.5 }) do
				for __, kind in ipairs(P.SUN_ORDER) do
					local off = P.SUN_PLACES[kind]
					local rot = P.placeSun(off, look, az, cal)
					ok(math.abs(rot) <= math.pi + 1e-9)
					near(P.wrapAngle(P.sunHeading(az, rot, cal) - (look + off)), 0, 1e-9, kind)
				end
			end
		end
	end
	-- default calibration: at noon (south) a camera looking south (heading -pi/2) needs no rotation for backlight
	near(P.placeSun(0, -math.pi / 2, math.pi), 0, 1e-12)
end)

test("start plan: back to the climate when the rendering environment or the marker says a look was on", function()
	eq(P.startPlan(nil, "Dry", "::/climates/dry/dry.env"), nil, "nothing of ours")
	local p = P.startPlan(nil, "Photo Mode look: Dramatic (Dry)", "::/climates/dry/dry.env")
	eq(p.to, "::/climates/dry/dry.env"); eq(p.why, "rendering")
	p = P.startPlan("dramatic", "Dry", "::/climates/dry/dry.env")
	eq(p.why, "marker")
	eq(P.startPlan("dramatic", "X", "somemod::/climates/mars/mars.env").to, "somemod::/climates/mars/mars.env")
	eq(P.startPlan("dramatic", "X", nil), nil, "no game ResName and no climate: nothing to switch to")
end)

test("marker: the look and cloud heights round-trip, junk dropped", function()
	local ov = L.newOverride({ time = 30000, timeMode = "Dynamic", cloud = 0.4, weatherMode = "Dynamic", day = 171,
		sun = 0, cloudBase = 1500, cloudTop = 3600 })
	L.change(ov, { cloudBase = 500, cloudTop = 1800 })
	local m = L.readMarker(L.marker(ov, nil, "dramatic"))
	eq(m.look, "dramatic"); eq(m.orig.cloudBase, 1500); eq(m.set.cloudTop, 1800)
	m = L.readMarker(L.marker(nil, nil, "misty_valley"))
	eq(m.look, "misty_valley"); eq(m.orig, nil)
	eq(L.marker(nil, nil, nil), nil)
	eq(L.readMarker({ v = 1, look = "../../x" }), nil)
	local put = L.recoverPlan(ov.orig, ov.set, ov.set)
	eq(put.cloudBase, 1500); eq(put.cloudTop, 3600)
end)

---------------------------------------------------------------------------
-- pm_weather through pm_sky on a fake api

local sky, fake

local FILE_ATMO = { cloudCoverage = 0, cloudBase = 1500, cloudTop = 3600, cloudScattering = 0.005, dayOfYear = 171,
	sunRotation = 0 }

local function copyAtmo(a)
	local o = {}
	for k, v in pairs(a) do o[k] = v end
	return o
end

local function newFake(gameRes)
	local f = {
		time = 30000, speed = 2, sent = {}, save = {}, now = 0,
		gs = { timeOfDayMode = "Dynamic", weatherMode = "Dynamic" },
		gameRes = gameRes or "::/climates/dry/dry.env",
		envSets = 0,
		eye = { x = 0, y = 0 }, centre = { x = 0, y = -100 }, -- looking south (heading -pi/2)
	}
	-- the repository: base climates and our looks, each with the file's atmosphere
	f.byId, f.ids = {}, {}
	local function add(res, name)
		local id = #f.byId + 1
		f.byId[id] = { res = res, name = name }
		f.ids[res] = id
	end
	for __, c in ipairs({ "dry", "temperate", "subarctic", "tropical" }) do
		add("::/climates/" .. c .. "/" .. c .. ".env", c)
		for __, x in ipairs(combos()) do
			add(P.lookResName(c, x[1], x[2], x[3]), "Photo Mode look: " .. P.lookKey(x[1], x[2], x[3]) .. " (" .. c .. ")")
		end
	end
	f.env = { name = "dry", atmosphere = copyAtmo(FILE_ATMO) }
	f.env.atmosphere.cloudCoverage = 0.4
	local function rec(x) f.sent[#f.sent + 1] = x end
	f.api = {
		type = {
			ComponentType = { GAME_TIME = "GAME_TIME", GAME_SPEED = "GAME_SPEED", GAME_SCRIPT = "GAME_SCRIPT" },
			Clock = { new = function() return { getTime = function() return f.now * 1000 end } end },
		},
		engine = {
			util = { getWorld = function() return 1 end },
			system = { gameScriptSystem = { getEntityForGameScript = function() return 9 end } },
			getComponent = function(e, t)
				if t == "GAME_TIME" then return { timeOfDaySec = f.time } end
				if t == "GAME_SPEED" then return { speedup = f.speed } end
				if t == "GAME_SCRIPT" then return { state = f.gs } end
			end,
		},
		cmd = {
			sendCommand = function(c) rec(c) c.apply() end,
			makeGameSetTimeOfDayCmd = function(s) return { k = "time", v = s, apply = function() f.time = s end } end,
			makeGameSetSpeedCmd = function(s) return { k = "speed", v = s, apply = function() f.speed = s end } end,
			makeGameSetCloudCoverageCmd = function(c) return { k = "cloudCmd", v = c, apply = function() end } end,
			makeScriptingSendEventCmd = function(src, id, name, p)
				return { k = id .. "." .. name, v = p.mode or p.weatherMode, apply = function()
					if id == "GameTime" then f.gs.timeOfDayMode = p.mode else f.gs.weatherMode = p.weatherMode end
				end }
			end,
		},
		res = {
			environmentRep = {
				find = function(res) return f.ids[res] or -1 end,
				get = function(id)
					local r = f.byId[id]
					return { name = r.name, res = r.res, atmosphere = copyAtmo(FILE_ATMO) }
				end,
			},
		},
		gui = {
			rendering = {
				getEnvironment = function()
					return { name = f.env.name, res = f.env.res, atmosphere = copyAtmo(f.env.atmosphere) }
				end,
				setEnvironment = function(e)
					f.env = { name = e.name, res = e.res, atmosphere = copyAtmo(e.atmosphere) }
					f.envSets = f.envSets + 1
				end,
			},
			game = {
				getEnvironment = function() return f.gameRes end,
				setEnvironment = function() error("game.setEnvironment must never be called (it persists into the save)") end,
				getGuiSaveData = function(k) return f.save[k] end,
				setGuiSaveData = function(k, d) f.save[k] = d end,
			},
			camera = {
				getEye = function() return f.eye end,
				getCenter = function() return f.centre end,
				getCameraData = function() return { w = math.pi / 2 } end,
			},
		},
	}
	return f
end

local function startSky(gameRes)
	fake = newFake(gameRes)
	reset_modules()
	P = ug_require "square_photo_mode::/photo_mode/pm_looks.lua"
	L = ug_require "square_photo_mode::/photo_mode/pm_light.lua"
	set_global("api", fake.api)
	sky = ug_require "square_photo_mode::/photo_mode/gui/pm_sky.lua"
	sky.persist = function() fake.save["square_photo_mode"] = { v = 1, views = {}, light = sky.saveMarker() } end
end

local function count(k)
	local n = 0
	for __, c in ipairs(fake.sent) do if c.k == k then n = n + 1 end end
	return n
end

local function run(seconds, fps)
	local dt = 1 / (fps or 60)
	local frames = math.floor(seconds / dt + 0.5)
	for __ = 1, frames do
		fake.now = fake.now + dt * 1000
		if sky.busy() then sky.stepFrame() end
	end
end

test("look: rendering-only switch keeps the live values; layers mix; back to the climate", function()
	startSky()
	eq(#sky.looks().sky, 9, "the 8 sky looks and Legacy (round 16)"); eq(#sky.looks().haze, 5); eq(#sky.looks().water, 4)
	sky.look("dramatic")
	eq(fake.env.res, "square_photo_mode::/environments/sqpm_dry_dramatic_orig_orig.env")
	eq(fake.env.atmosphere.cloudCoverage, 0.4, "live cloud cover carried over (the file has 0)")
	eq(sky.status().look, "dramatic_orig_orig")
	eq(sky.status().sky, "dramatic"); eq(sky.status().haze, nil); eq(sky.status().water, nil)
	eq(fake.save["square_photo_mode"].light.look, "dramatic_orig_orig", "marker")
	ok(not sky.active(), "a look needs no override")
	-- a haze layer on top keeps the sky (round 12: Dramatic + Soft background)
	sky.layer("haze", "soft_background")
	eq(fake.env.res, P.lookResName("dry", "dramatic", "soft_background", nil))
	eq(sky.status().sky, "dramatic"); eq(sky.status().haze, "soft_background")
	-- a water layer on top keeps both
	sky.layer("water", "wild")
	eq(fake.env.res, P.lookResName("dry", "dramatic", "soft_background", "wild"))
	eq(sky.status().water, "wild")
	-- the sky to another look keeps the haze and the water
	sky.layer("sky", "soft_light")
	eq(fake.env.res, P.lookResName("dry", "soft_light", "soft_background", "wild"))
	-- the sky and the haze back to the original: the water alone
	sky.layer("sky", nil)
	sky.layer("haze", "orig")
	eq(fake.env.res, P.lookResName("dry", nil, nil, "wild"))
	eq(sky.status().look, "orig_orig_wild")
	eq(fake.env.atmosphere.cloudCoverage, 0.4)
	-- the water back too: the climate itself
	sky.layer("water", "orig")
	eq(fake.env.res, "::/climates/dry/dry.env")
	eq(sky.status().look, nil)
	-- the longest key still fits the marker's 40 characters (pm_light.readMarker; round 15: 39)
	local longest = ""
	for __, x in ipairs(combos()) do
		local k = P.lookKey(x[1], x[2], x[3])
		if #k > #longest then longest = k end
	end
	ok(#longest <= 40, "longest key " .. longest .. " " .. #longest)
	sky.look("moonlit_night", "soft_background", "turquoise")
	eq(fake.save["square_photo_mode"].light.look, "moonlit_night_soft_background_turquoise")
	eq(L.readMarker(fake.save["square_photo_mode"].light).look, "moonlit_night_soft_background_turquoise")
	sky.look(nil, "misty_valley")
	eq(fake.env.res, P.lookResName("dry", nil, "misty_valley", nil))
	-- an unknown layer changes nothing
	local before = fake.envSets
	sky.layer("clouds", "storm")
	eq(fake.envSets, before)
	sky.look(nil)
	eq(fake.env.res, "::/climates/dry/dry.env")
	eq(fake.env.atmosphere.cloudCoverage, 0.4)
	eq(sky.status().look, nil)
	eq(fake.save["square_photo_mode"].light, nil, "marker cleared")
end)

test("look: an unknown climate offers none and switches nothing", function()
	startSky("somemod::/climates/mars/mars.env")
	eq(sky.looks(), nil)
	local before = fake.envSets
	sky.look("dramatic")
	sky.layer("water", "wild")
	eq(fake.envSets, before)
	eq(sky.status().look, nil)
end)

test("pause menu: animation stops, the look goes, then the override's values come back", function()
	startSky()
	sky.look("dramatic", "hazy_morning", "wild")
	sky.weather("storm")
	ok(sky.busy()); ok(sky.active())
	run(10)
	ok(fake.env.atmosphere.cloudCoverage > 0.1)
	sky.pauseMenu()
	ok(not sky.busy()); ok(not sky.active())
	eq(fake.env.res, "::/climates/dry/dry.env")
	near(fake.env.atmosphere.cloudCoverage, 0.4, 1e-9, "the player's cloud cover")
	eq(fake.gs.weatherMode, "Dynamic")
	eq(fake.save["square_photo_mode"].light, nil)
end)

test("weather: storm eases to rain, the sim's cloud cover about once a second, the marker every few seconds", function()
	startSky()
	sky.weather("storm")
	eq(fake.env.atmosphere.cloudCoverage, 0.1, "starts clear")
	local cmds0 = count("cloudCmd")
	local sets0 = fake.envSets
	run(20)
	local mid = fake.env.atmosphere.cloudCoverage
	ok(mid > 0.4 and mid < 0.7, "half way " .. mid)
	run(21)
	ok(not sky.busy(), "done")
	eq(fake.env.atmosphere.cloudCoverage, 1.0)
	local cmds = count("cloudCmd") - cmds0
	ok(cmds >= 38 and cmds <= 44, "about one sim command per second: " .. cmds)
	local sets = fake.envSets - sets0
	ok(sets <= 41 * 20 + 2, "at most 20 environment sets a second: " .. sets)
	eq(fake.save["square_photo_mode"].light.set.cloud, 1.0, "final value in the marker")
	sky.restore("checkbox")
	near(fake.env.atmosphere.cloudCoverage, 0.4, 1e-9)
end)

test("weather: a click on a cloud preset stops the animation; the same button again stops it too", function()
	startSky()
	sky.weather("clearing")
	run(5)
	sky.preset("storm")
	ok(not sky.busy())
	eq(fake.env.atmosphere.cloudCoverage, 1.0)
	sky.weather("lowclouds")
	ok(sky.busy())
	sky.weather("lowclouds")
	ok(not sky.busy(), "toggle off")
	sky.weather("lowclouds")
	run(9)
	eq(fake.env.atmosphere.cloudBase, 500); eq(fake.env.atmosphere.cloudTop, 1800)
	sky.restore("checkbox")
	eq(fake.env.atmosphere.cloudBase, 1500); eq(fake.env.atmosphere.cloudTop, 3600)
end)

test("time-lapse: sunset sweeps the clock and ends; the time comes back on untick", function()
	startSky()
	sky.lapse("sunset")
	local from = fake.time
	ok(from > 17 * 3600, "starts in the evening " .. L.clockText(from))
	run(20)
	ok(fake.time > from, "moving")
	run(30)
	ok(not sky.busy())
	ok(fake.time > 19 * 3600, "ends at dusk " .. L.clockText(fake.time))
	sky.restore("checkbox")
	eq(fake.time, 30000)
	-- run: until stopped; a time step button stops it
	sky.lapse("run")
	run(2)
	ok(sky.busy())
	sky.nudge("time", 3600)
	ok(not sky.busy(), "replaced by the click")
end)

test("round 15 sliders: a live set is quiet (no log, no save, no window refresh), the final set is a click", function()
	startSky()
	local changed, saves = 0, 0
	sky.changed = function() changed = changed + 1 end
	local persist = sky.persist
	sky.persist = function() saves = saves + 1; persist() end
	sky.begin()
	changed, saves = 0, 0
	local sets = fake.envSets
	sky.setLive({ sun = 0.5 }, "slider sun")
	sky.setLive({ day = 100 }, "slider day")
	sky.setLive({ time = 7 * 3600 }, "slider time")
	eq(fake.env.atmosphere.sunRotation, 0.5); eq(fake.env.atmosphere.dayOfYear, 100)
	eq(fake.envSets - sets, 2, "applied live")
	eq(sky.shown().time, 7 * 3600, "the window shows the live value")
	eq(changed, 0, "no window refresh while dragging"); eq(saves, 0, "no save-data write while dragging")
	sky.set({ sun = 0.6 }, "slider sun")
	eq(changed, 1, "the final set refreshes the window"); eq(saves, 1, "and saves the marker")
	-- a live time set stops a running time-lapse (as a click on a time button)
	sky.lapse("run")
	ok(sky.status().lapse == "run")
	sky.setLive({ time = 9 * 3600 }, "slider time")
	eq(sky.status().lapse, nil, "the slider took the clock over")
	sky.restore("checkbox")
	eq(fake.env.atmosphere.dayOfYear, 171); eq(fake.env.atmosphere.sunRotation, 0)
end)

test("seasons and sun placement: day set, sun rotation from the view and the sun's azimuth", function()
	startSky()
	sky.season("spring")
	eq(fake.env.atmosphere.dayOfYear, 80, "round 12: Spring sun, the March equinox")
	sky.season("winter")
	eq(fake.env.atmosphere.dayOfYear, 355)
	sky.preset("noon")
	-- camera looks south (eye 0,0 -> centre 0,-100), noon: the sun is due south, so backlight needs no rotation
	sky.placeSun("back")
	near(fake.env.atmosphere.sunRotation, 0, 0.01)
	sky.placeSun("front")
	near(math.abs(fake.env.atmosphere.sunRotation), math.pi, 0.01)
	sky.placeSun("side")
	near(math.abs(fake.env.atmosphere.sunRotation), math.pi / 2, 0.01)
	local first = fake.env.atmosphere.sunRotation
	sky.placeSun("side")
	near(fake.env.atmosphere.sunRotation, -first, 0.01, "the other side")
	sky.restore("checkbox")
	eq(fake.env.atmosphere.dayOfYear, 171); eq(fake.env.atmosphere.sunRotation, 0)
end)

test("game start: a rendering environment of ours or the marker's look goes back to the climate", function()
	startSky()
	sky.look("dramatic")
	sky.preset("night")
	local saved = fake.save["square_photo_mode"]
	-- the next load: the GUI state outlived it, the rendering environment is still ours
	reset_modules()
	set_global("api", fake.api)
	sky = ug_require "square_photo_mode::/photo_mode/gui/pm_sky.lua"
	sky.persist = function() fake.save["square_photo_mode"] = { v = 1, views = {}, light = sky.saveMarker() } end
	fake.save["square_photo_mode"] = saved
	sky.start()
	eq(fake.env.res, "::/climates/dry/dry.env")
	eq(fake.time, 30000, "the override's marker repaired too")
	eq(fake.save["square_photo_mode"].light, nil)
	-- nothing of ours: no switch at all
	local sets = fake.envSets
	sky.start()
	eq(fake.envSets, sets)
end)
