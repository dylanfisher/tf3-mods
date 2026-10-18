-- pm_core.lua (Photo Mode, pure): safety-net recovery (which keys go back), marker parsing, mainMenuState copy,
-- snapshot, MSAA maximum, button style.

local core

before_each(function()
	reset_modules()
	core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
end)

local PLAYER = {
	textureQuality = 1, terrainTextureQuality = 0, numMSAASamples = 2, useSsao = false, ssrQuality = 0,
	resolutionScale = 0.75,
}

test("recover restores every key still at its boosted value", function()
	local boost = core.boostValues(8)
	local put, kept = core.recoverKeys(PLAYER, boost, boost)
	eq(put, PLAYER)
	eq(kept, {})
end)

test("recover keeps keys the player changed since", function()
	local boost = core.boostValues(8)
	local cur = core.boostValues(8)
	cur.ssrQuality = 1 -- changed by hand after the crash
	cur.numMSAASamples = 4
	local put, kept = core.recoverKeys(PLAYER, cur, boost)
	eq(put.ssrQuality, nil)
	eq(put.numMSAASamples, nil)
	eq(put.textureQuality, 1)
	eq(put.resolutionScale, 0.75)
	eq(kept, { "numMSAASamples", "ssrQuality" })
end)

test("recover skips keys whose original already was the maximum", function()
	local orig = core.boostValues(8)
	orig.useSsao = false
	local put, kept = core.recoverKeys(orig, core.boostValues(8), core.boostValues(8))
	eq(put, { useSsao = false })
	eq(kept, {})
end)

test("recover compares the float resolution scale with a tolerance", function()
	local cur = core.boostValues(8)
	cur.resolutionScale = 0.99999999
	local put = core.recoverKeys({ resolutionScale = 0.5 }, cur, core.boostValues(8))
	eq(put, { resolutionScale = 0.5 })
end)

test("markerOrig reads a marker and rejects broken ones", function()
	eq(core.markerOrig({ boosted = true, orig = { ssrQuality = 1, vsync = true } }), { ssrQuality = 1 })
	eq(core.markerOrig(nil), nil)
	eq(core.markerOrig({ boosted = false, orig = PLAYER }), nil)
	eq(core.markerOrig({ boosted = true }), nil)
	eq(core.markerOrig("junk"), nil)
end)

test("withMarker keeps other mods' mainMenuState keys", function()
	local mm = { other_mod = { x = 1 } }
	local t = core.withMarker(mm, { boosted = true })
	eq(t.other_mod, { x = 1 })
	eq(t.square_photo_mode, { boosted = true })
	eq(mm.square_photo_mode, nil, "input not modified")
	local cleared = core.withMarker(t, nil)
	eq(cleared, { other_mod = { x = 1 } })
	eq(core.withMarker(nil, 1), { square_photo_mode = 1 })
end)

test("snapshot takes only the graphics keys and skips unreadable ones", function()
	local src = { textureQuality = 2, shadowQuality = 2, grassQuality = 2, vsync = true, audio = 3 }
	local snap = core.snapshot(function(k)
		if k == "ssrQuality" then error("no such key") end
		return src[k]
	end)
	eq(snap, { textureQuality = 2, grassQuality = 2 }, "shadows are never snapshotted")
end)

test("maxOf picks the highest supported MSAA count", function()
	eq(core.maxOf({ 1, 2, 4, 8 }, 4), 8)
	eq(core.maxOf({}, 4), 4)
	eq(core.maxOf(nil, 4), 4)
	eq(core.boostValues(8).numMSAASamples, 8)
	eq(core.boostValues(nil).numMSAASamples, 4)
end)

-- Crash safety (plans/square_photo_mode/PLAN.md "Crash safety")

test("validValue accepts only the settings page's values, normalised", function()
	eq(core.validValue("ssrQuality", 2), 2)
	eq(core.validValue("ssrQuality", 2.0), 2)
	eq(core.validValue("ssrQuality", 3), nil)
	eq(core.validValue("ssrQuality", -1), nil)
	eq(core.validValue("ssrQuality", 1.5), nil)
	eq(core.validValue("ssrQuality", 0 / 0), nil)
	eq(core.validValue("ssrQuality", "2"), nil)
	eq(core.validValue("numMSAASamples", 8), 8)
	eq(core.validValue("numMSAASamples", 3), nil)
	eq(core.validValue("numMSAASamples", math.huge), nil)
	eq(core.validValue("useSsao", false), false)
	eq(core.validValue("useSsao", 1), nil)
	eq(core.validValue("resolutionScale", 0.75), 0.75)
	eq(core.validValue("resolutionScale", 1.0000001), 1)
	eq(core.validValue("resolutionScale", 0), nil)
	eq(core.validValue("resolutionScale", 2), nil)
	eq(core.validValue("vsync", true), nil, "not one of our keys")
	eq(core.validValue("shadowQuality", 1), nil, "shadows are never set")
	for __, key in ipairs({ "geometryQuality", "terrainQuality", "grassQuality" }) do
		eq(core.validValue(key, 1), 1, key)
	end
end)

test("markerOrig drops corrupt values and survives any marker shape", function()
	local nan = 0 / 0
	eq(core.markerOrig({ boosted = true, orig = { ssrQuality = 1.0, textureQuality = "high", terrainTextureQuality = nan,
		numMSAASamples = 7, useSsao = "yes", resolutionScale = 0.6 } }), { ssrQuality = 1, resolutionScale = 0.6 })
	eq(core.markerOrig({ boosted = true, orig = "junk" }), nil)
	eq(core.markerOrig({ boosted = true, orig = 5 }), nil)
	eq(core.markerOrig(42), nil)
	eq(core.markerOrig(true), nil)
	eq(core.markerOrig({ boosted = "true", orig = PLAYER }), nil)
	local raising = setmetatable({}, { __index = function() error("bad table") end })
	eq(core.markerOrig(raising), nil)
	eq(core.markerOrig({ boosted = true, orig = raising }), {})
	eq(core.markerOrig({ boosted = true, orig = PLAYER }), PLAYER)
end)

test("withMarker refuses a mainMenuState it can't copy whole", function()
	eq(core.withMarker("junk", { boosted = true }), nil)
	eq(core.withMarker(7, nil), nil)
	local unpairable = setmetatable({}, { __pairs = function() error("no pairs") end })
	eq(core.withMarker(unpairable, nil), nil)
end)

test("the switch gate refuses re-entry and keeps an off asked for meanwhile", function()
	local g = core.newGate()
	ok(core.gateEnter(g))
	eq(core.gateEnter(g), false, "a second switch while one runs")
	g.pendingOff = "pause menu"
	eq(core.gateLeave(g), "pause menu")
	eq(g.pendingOff, nil)
	ok(core.gateEnter(g), "free again")
	eq(core.gateLeave(g), nil)
end)

test("fmt never raises on a broken translation", function()
	eq(core.fmt("View %d", 3), "View 3")
	eq(core.fmt("%d s", 10), "10 s")
	-- more placeholders than arguments / a wrong type: no error, the text and the arguments are kept
	local s = core.fmt("View %d %d", 3)
	ok(s:find("View", 1, true) and s:find("3", 1, true) and not s:find("%", 1, true), s)
	s = core.fmt("Vue %d", "x")
	ok(s:find("Vue", 1, true) and s:find("x", 1, true) and not s:find("%", 1, true), s)
end)

test("every graphics key is in exactly one stage", function()
	local seen = {}
	for i, stage in ipairs(core.STAGES) do
		for __, key in ipairs(stage) do
			eq(seen[key], nil, key .. " twice")
			seen[key] = i
		end
	end
	for __, key in ipairs(core.KEYS) do ok(seen[key] ~= nil, key .. " in no stage") end
	eq(seen.textureQuality, 1, "textures first")
	eq(seen.numMSAASamples, 3, "MSAA after the image stages")
	ok(core.STAGE_DELAY_FRAMES >= 2)
	eq(#core.STAGES, 6)
	eq(core.STAGES[1], { "textureQuality", "terrainTextureQuality" })
	eq(core.STAGES[2], { "useSsao", "ssrQuality" })
	eq(core.STAGES[3], { "numMSAASamples", "resolutionScale" })
	eq(core.STAGES[4], { "geometryQuality" })
	eq(core.STAGES[5], { "terrainQuality" })
	eq(core.STAGES[6], { "grassQuality" })
end)

-- Geometry, terrain and grass crashed once switched together in one call and passed one key at a time
-- (docs/findings/map-camera.md "Changing render-buffer settings at runtime crashes"): each alone, at 2.
test("geometry, terrain and grass: one stage each, boosted to 2, snapshotted and restored", function()
	for __, key in ipairs({ "geometryQuality", "terrainQuality", "grassQuality" }) do
		local n = 0
		for __, stage in ipairs(core.STAGES) do
			for __, k in ipairs(stage) do if k == key then n = n + 1; eq(#stage, 1, key .. " not alone") end end
		end
		eq(n, 1, key)
		eq(core.boostValues(8)[key], 2)
		eq(core.validValue(key, 1), 1)
		eq(core.validValue(key, 3), nil)
	end
	local orig = core.markerOrig({ boosted = true, orig = { geometryQuality = 0, grassQuality = 1, textureQuality = 1 } })
	eq(orig, { geometryQuality = 0, grassQuality = 1, textureQuality = 1 })
	local put = core.recoverKeys(orig, core.boostValues(8), core.boostValues(8))
	eq(put, { geometryQuality = 0, grassQuality = 1, textureQuality = 1 })
end)

-- Changing shadowQuality at runtime crashed the renderer (docs/findings/map-camera.md "Changing render-buffer
-- settings at runtime crashes"): never touched.
test("shadowQuality: in no stage, not boosted, not snapshotted; an old marker with it restores nothing for it", function()
	for __, stage in ipairs(core.STAGES) do
		for __, key in ipairs(stage) do ok(key ~= "shadowQuality", "a stage sets shadowQuality") end
	end
	for __, stage in ipairs(core.RESTORE_STAGES) do
		for __, key in ipairs(stage) do ok(key ~= "shadowQuality", "a restore stage sets shadowQuality") end
	end
	for __, key in ipairs(core.KEYS) do ok(key ~= "shadowQuality", "shadowQuality in KEYS") end
	eq(core.boostValues(8).shadowQuality, nil)
	eq(core.validValue("shadowQuality", 1), nil, "shadows are never set")
	-- a marker written by an older build (with shadowQuality) is still accepted, without shadows
	local orig = core.markerOrig({ boosted = true, orig = { shadowQuality = 0, textureQuality = 1 } })
	eq(orig, { textureQuality = 1 })
	local cur = core.boostValues(8)
	cur.shadowQuality = 2
	local put = core.recoverKeys({ shadowQuality = 0, textureQuality = 1 }, cur, core.boostValues(8))
	eq(put, { textureQuality = 1 }, "recovery never sets shadows")
	for i = 1, #core.RESTORE_STAGES do
		local ch = core.restoreChanges(i, { shadowQuality = 2 }, { shadowQuality = 0 })
		eq(ch, {})
	end
end)

test("stageChanges lists only the keys not yet at their highest, in stage order", function()
	local boost = core.boostValues(8)
	local cur = { useSsao = true, ssrQuality = 1 }
	local changes, names = core.stageChanges(2, cur, boost)
	eq(changes, { ssrQuality = 2 })
	eq(names, { "ssrQuality" })
	changes, names = core.stageChanges(2, { useSsao = false, ssrQuality = 0 }, boost)
	eq(changes, { useSsao = true, ssrQuality = 2 })
	eq(names, { "useSsao", "ssrQuality" })
	local c2, n2 = core.stageChanges(3, { numMSAASamples = 8, resolutionScale = 1.0000001 }, boost)
	eq(c2, {})
	eq(n2, {})
	eq(select(2, core.stageChanges(99, cur, boost)), {})
end)

-- Rev 1 feedback round 2 (2026-10-13): the staged restore, the hidden HUD filter

test("restore stages: the switch stages in reverse, every key once", function()
	eq(#core.RESTORE_STAGES, #core.STAGES)
	for i, st in ipairs(core.RESTORE_STAGES) do eq(st, core.STAGES[#core.STAGES + 1 - i]) end
	eq(core.RESTORE_STAGES[1], { "grassQuality" }, "grass first")
	eq(core.RESTORE_STAGES[4], { "numMSAASamples", "resolutionScale" }, "anti-aliasing and scale after the mesh keys")
	eq(core.RESTORE_STAGES[#core.RESTORE_STAGES], { "textureQuality", "terrainTextureQuality" }, "textures last")
	local orig = { numMSAASamples = 1, resolutionScale = 0.75, textureQuality = 1, terrainTextureQuality = 2 }
	local cur = { numMSAASamples = 8, resolutionScale = 1.0, textureQuality = 2, terrainTextureQuality = 2 }
	local ch, names = core.restoreChanges(4, cur, orig)
	eq(ch, { numMSAASamples = 1, resolutionScale = 0.75 }); eq(names, { "numMSAASamples", "resolutionScale" })
	ch, names = core.restoreChanges(#core.RESTORE_STAGES, cur, orig)
	eq(ch, { textureQuality = 1 }); eq(names, { "textureQuality" }, "a key already the player's is left out")
	ch, names = core.restoreChanges(5, cur, orig)
	eq(names, {}, "keys missing from the snapshot are not touched")
end)

test("hidden HUD filter: every toggle off; recognised until the player changes one", function()
	local types, carriers = { 10, 11, 12 }, { 0, 1 }
	local f = core.hiddenHudFilter(types, carriers)
	eq(f.preFilters, { [10] = "Hidden", [11] = "Hidden", [12] = "Hidden" })
	eq(f.preFilterTvCarriers, { [0] = "Hidden", [1] = "Hidden" })
	eq(f.showCosts, false); eq(f.showIncome, false); eq(f.showEventIcons, false); eq(f.showCargoFlow, false)
	ok(core.isHiddenHudFilter(f, types, carriers))
	local g = core.deepCopy(f)
	g.preFilters[11] = "Default"
	eq(core.isHiddenHudFilter(g, types, carriers), false, "the player showed stations again")
	g = core.deepCopy(f)
	g.showIncome = true
	eq(core.isHiddenHudFilter(g, types, carriers), false)
	eq(core.isHiddenHudFilter(nil, types, carriers), false)
	eq(core.isHiddenHudFilter({ showCosts = false }, types, carriers), false, "malformed: not ours")
end)

test("deepCopy copies nested tables and stops at the depth limit", function()
	local t = { a = { b = { c = 1 } }, n = 2 }
	local c = core.deepCopy(t)
	eq(c, t)
	c.a.b.c = 5
	eq(t.a.b.c, 1, "a copy")
	eq(core.deepCopy("x"), "x")
	local deep = {}
	local cur = deep
	for __ = 1, 20 do cur.next = {} cur = cur.next end
	ok(core.deepCopy(deep) ~= nil)
end)

test("round 11: hudPreFilter builds the HUD icon filter as the base selector does", function()
	local core = ug_require "square_photo_mode::/photo_mode/pm_core.lua"
	local types, carriers = { 1, 4, 5, 13 }, { 0, 1 }
	local r = core.hudPreFilter(nil, types, carriers, 1)
	eq(r.preFilter, types); eq(r.showCosts, true); eq(r.showIncome, true)
	r = core.hudPreFilter({ preFilters = { [13] = "Hidden" }, showCosts = false, showIncome = true }, types, carriers, 1)
	eq(r.preFilter, { 1, 4, 5 }); eq(r.preFilterTvCarriers, nil); eq(r.showCosts, false)
	r = core.hudPreFilter({ preFilters = {}, preFilterTvCarriers = { [0] = "Hidden" } }, types, carriers, 1)
	eq(r.preFilterTvCarriers, { 1 })
	-- every carrier hidden: the vehicles go too
	r = core.hudPreFilter({ preFilters = {}, preFilterTvCarriers = { [0] = "Hidden", [1] = "Hidden" } }, types, carriers, 1)
	eq(r.preFilter, { 4, 5, 13 }); eq(r.preFilterTvCarriers, nil)
	-- the hidden filter: nothing
	local h = core.hiddenHudFilter(types, carriers)
	r = core.hudPreFilter(h, types, carriers, 1)
	eq(#r.preFilter, 0); eq(r.showCosts, false); eq(r.showIncome, false)
end)
