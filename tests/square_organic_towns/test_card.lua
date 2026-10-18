-- The town window's Organic Towns card and the new-town notification (2026-10-17, rev 3; ot_card, ot_saved `no` / `ui`,
-- the driver's summary batches and notification). The ID lists mirrored in ot_card match their modules, every id has
-- its texts, the summary's round trip, bounds and hysteresis, the phase progress, name origins, the five sections from
-- plain inputs (including old saves without the new keys and garbage values), the notification's dedupe.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local CARD = ug_require(F.DIR .. "ot_card.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local CH = ug_require(F.DIR .. "ot_character.lua")
local FM = ug_require(F.DIR .. "ot_form.lua")
local MO = ug_require(F.DIR .. "ot_motif.lua")
local UP = ug_require(F.DIR .. "ot_upward.lua")
local PN = ug_require(F.DIR .. "ot_placename.lua")
local PA = ug_require(F.DIR .. "ot_params.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")

local function listEq(a, b, what)
	eq(#a, #b, what .. " length")
	for i = 1, #b do eq(a[i], b[i], what .. " " .. i) end
end

test("mirrored lists match their modules (kinds, forms, styles, motifs, phase thresholds, kind rules)", function()
	listEq(CARD.KIND_IDS, CH.IDS, "kinds")
	listEq(CARD.FORM_IDS, FM.IDS, "forms")
	listEq(CARD.STYLE_IDS, SV.STYLE_IDS, "styles")
	-- (ot_motif appends kinds registered later: the saved prefix is what the card decodes)
	for i = 1, #CARD.MOTIF_IDS do eq(CARD.MOTIF_IDS[i], MO.IDS[i], "motif " .. i) end
	eq(#CARD.MOTIF_IDS, #MO.IDS, "every motif")
	eq(CARD.MOTIF_BASE, MO.SAVE_BASE)
	eq(CARD.MOTIF_MAX, MO.MAX)
	eq(CARD.BLEND_MAT, UP.LV_BLEND_MAT)
	eq(CARD.MATURE_MAT, UP.LV_MATURE_MAT)
	eq(CARD.EARLY_MAT, UP.EARLY_MAT)
	for i, id in ipairs(UP.PHASES) do eq(CARD.PHASES[i], id, "phase " .. i) end
	for _, k in ipairs(CH.KINDS) do
		eq(CARD.NO_OFFSHOOTS[k.id] == true, k.offshoots == false, "offshoots of " .. k.id)
		eq(CARD.EARLY_KINDS[k.id] == true, k.levels == "early", "early levels of " .. k.id)
	end
	-- (every origin tag is a tag the name generator knows)
	local known = {}
	for _, t in ipairs(PN.TAGS) do known[t] = true end
	for t in pairs(CARD.ORIGIN_OF_TAG) do ok(known[t], "origin tag " .. t) end
end)

test("every id has its texts, in plain words", function()
	local function plain(s, what)
		ok(type(s) == "string" and #s > 0, what)
		for _, w in ipairs({ "LEVELS", "FILL", "capsBoost", "matL", "pb", "_" }) do
			ok(not s:find(w, 1, true), what .. " has no code word " .. w .. ": " .. s)
		end
	end
	for _, id in ipairs(CARD.KIND_IDS) do local a, b = CARD.kindText(id); plain(a, id); plain(b, id) end
	for _, id in ipairs({ "secluded", "coastal" }) do local a, b = CARD.kindText(id); plain(a, id); plain(b, id) end
	for _, id in ipairs(CARD.FORM_IDS) do local a, b = CARD.formText(id); plain(a, id); plain(b, id) end
	for _, id in ipairs(CARD.STYLE_IDS) do local a, b = CARD.styleText(id); plain(a, id); plain(b, id) end
	for _, id in ipairs(CARD.MOTIF_IDS) do plain(CARD.motifText(id), id) end
	for _, id in ipairs(CARD.PHASES) do local a, b = CARD.phaseText(id); plain(a, id); plain(b, id) end
	local seen = {}
	for _, o in pairs(CARD.ORIGIN_OF_TAG) do seen[o] = true end
	seen.character, seen.industry = true, true
	for o in pairs(seen) do plain(CARD.originText(o), "origin " .. o) end
	eq(CARD.kindText("nope"), nil)
	eq(CARD.formText(nil), nil)
end)

test("summary: round trip, bounds, unknown readiness, garbage", function()
	for _, ph in ipairs(CARD.PHASES) do
		for _, mat in ipairs({ -1, 0, 0.26, 0.5, 0.99, 1, 7, 0 / 0 }) do
			for _, r in ipairs({ false, 0, 0.42, 0.999, 1, 3.5 }) do
				local v = CARD.summary({ phase = ph, mat = mat, ready = r ~= false and r or nil })
				ok(SV.uiOk(v), "saved form: " .. tostring(v))
				ok(#v <= SV.UI_MAX, "short")
				local back = CARD.parseSummary(v)
				eq(back.phase, ph)
				ok(back.mat >= 0 and back.mat <= 1)
				if r == false then eq(back.ready, nil) else ok(back.ready >= 0 and back.ready <= 1) end
			end
		end
	end
	eq(CARD.parseSummary(CARD.summary({ phase = "blend", mat = 0.7, ready = 0.999 })).ready < 1, true, "not ready below 1")
	eq(CARD.parseSummary(CARD.summary({ phase = "blend", mat = 0.7, ready = 1 })).ready, 1)
	eq(CARD.summary({ phase = "nope", mat = 1 }), nil)
	eq(CARD.summary(nil), nil)
	eq(CARD.parseSummary("9:1:-"), nil)
	eq(CARD.parseSummary("x"), nil)
	eq(CARD.parseSummary(12), nil)
end)

test("summaryMoved: phase and ready changes write, small wobbles don't", function()
	local a = CARD.summary({ phase = "young", mat = 0.30 })
	eq(CARD.summaryMoved(nil, a), true, "first")
	eq(CARD.summaryMoved(a, a), false)
	eq(CARD.summaryMoved(a, CARD.summary({ phase = "young", mat = 0.35 })), false, "one step")
	eq(CARD.summaryMoved(a, CARD.summary({ phase = "young", mat = 0.40 })), true, "two steps")
	eq(CARD.summaryMoved(a, CARD.summary({ phase = "blend", mat = 0.30 })), true, "phase")
	local r = CARD.summary({ phase = "mature", mat = 1, ready = 0.96 })
	eq(CARD.summaryMoved(r, CARD.summary({ phase = "mature", mat = 1, ready = 1 })), true, "became ready")
	eq(CARD.summaryMoved(r, CARD.summary({ phase = "mature", mat = 1 })), true, "readiness gone")
	eq(CARD.summaryMoved(r, nil), false)
end)

test("phase progress: young -> blend / densify / early, blend -> mature, none after", function()
	local n, p = CARD.phaseProgress("young", 0.25)
	eq(n, "blend"); near(p, 0.5)
	n, p = CARD.phaseProgress("young", 0.25, true)
	eq(n, "densify")
	n, p = CARD.phaseProgress("young", 0.1, "early")
	eq(n, "early"); near(p, 0.1 / CARD.EARLY_MAT)
	n, p = CARD.phaseProgress("blend", 0.7)
	eq(n, "mature"); near(p, 0.5)
	n, p = CARD.phaseProgress("blend", 5)
	eq(p, 1)
	for _, ph in ipairs({ "mature", "densify", "early", "low" }) do eq(CARD.phaseProgress(ph, 0.95), nil, ph) end
	n, p = CARD.phaseProgress("young", 0 / 0)
	eq(p, 0)
end)

test("name origins: codes from the generator's info, sentence ids, garbage", function()
	eq(CARD.originCode({ genTag = "bend", specTag = "oak", shape = "frame" }), "bend,oak,frame")
	eq(CARD.originOf("bend,oak,frame"), "bend", "the generic first")
	eq(CARD.originOf("-,oak,frame"), "trees", "else the stem")
	eq(CARD.originOf("bend,oak,character"), "character")
	eq(CARD.originOf("-,-,industry"), "industry")
	eq(CARD.originCode({ genTag = "small", specTag = nil, shape = "plain" }), nil, "no origin: nothing saved")
	eq(CARD.originCode({ genTag = "BAD!", specTag = "river", shape = "x y" }), "-,river,-")
	eq(CARD.originCode(nil), nil)
	eq(CARD.originOf("a,b"), nil)
	eq(CARD.originOf(("a"):rep(60) .. ",river,frame"), nil)
	ok(SV.originOk(CARD.originCode({ genTag = "confluence", specTag = "mainvalley", shape = "qualifier" })))
	-- every code the generator can produce fits the saved limit
	for _, a in ipairs(PN.TAGS) do
		for _, b in ipairs({ "mainvalley", "confluence" }) do
			local c = CARD.originCode({ genTag = a, specTag = b, shape = "qualifier" })
			if c then ok(SV.originOk(c), c) end
		end
	end
end)

local function baseInput()
	return { town = 7, fresh = true, rciOn = true, satellitesOn = true, names = {}, offs = {},
		init = { 300, 100, 100 }, sf = { 1, 1, 1 }, uses = { 250, 90, 60 } }
end

local function texts(sec)
	local out = {}
	for _, l in ipairs(sec and sec.lines or {}) do
		out[#out + 1] = l.text or ((l.key or "") .. (l.value and type(l.value) == "string" and (": " .. l.value) or "")
			.. (l.tip and (" (" .. l.tip .. ")") or ""))
	end
	return table.concat(out, " | ")
end

test("growth by deliveries: off, no deliveries, rows with the pull and the lean", function()
	local inp = baseInput()
	inp.rciOn = false
	ok(texts(CARD.rciSection(inp)):find("Off in the mod settings", 1, true))
	eq(CARD.rciSection(inp).lines[1].kind, "hint", "an explanation: the base info hint")
	inp = baseInput()
	ok(texts(CARD.rciSection(inp)):find("No deliveries yet", 1, true), "no saved usage, no live supply")
	inp.supply = { line = 0, res = { 0, 0 }, com = { 0, 0 }, ind = { 0, 0 } }
	ok(texts(CARD.rciSection(inp)):find("No deliveries yet", 1, true), "nothing delivered")
	-- industrial deliveries pull toward industry
	inp.rc = { e = { 100, 0, 900 } }
	local sec = CARD.rciSection(inp)
	-- (a legend note, then per district a key / value row "now → aim" and a thin bar with the aim as its mark)
	eq(sec.lines[1].kind, "note")
	ok(sec.lines[1].text:find("→", 1, true), "the legend explains the arrow")
	eq(sec.lines[2].kind, "row")
	eq(sec.lines[2].key, "Residential")
	eq(sec.lines[3].kind, "bar")
	near(sec.lines[3].value, 0.625, 1e-9)
	ok(sec.lines[3].mark >= 0 and sec.lines[3].mark <= 1)
	eq(sec.lines[3].color, "res")
	eq(sec.lines[3].text, nil, "no text over the bar")
	ok(type(sec.lines[3].tip) == "string" and #sec.lines[3].tip > 0, "the bar explains itself")
	eq(sec.lines[6].key, "Industrial")
	local function ascii(v) return (tostring(v):gsub("\226\134\146", "->")) end
	ok(sec.lines[6].value == "15% → 70%", ascii(sec.lines[6].value))
	eq(sec.lines[7].color, "ind")
	near(sec.lines[7].mark, 0.7, 0.006)
	-- the aim below the built share reads too (the first pass showed nothing then)
	ok(sec.lines[2].value == "63% → 18%", "aim below now: " .. ascii(sec.lines[2].value))
	eq(CARD.aimText(0.452, 0.448), "45%, on its aim")
	ok(CARD.aimText(0 / 0, 2) == "0% → 100%", "garbage clamped: " .. ascii(CARD.aimText(0 / 0, 2)))
	ok(texts(sec):find("toward industry", 1, true), texts(sec))
	-- a weighted town that leans industrial and sits at its aim
	inp.init = { 140, 100, 760 }
	inp.rc = { e = { 0, 0, 1000 } }
	local aim = { 0.12, 0.12, 0.76 }
	inp.init = { aim[1] * 1000, aim[2] * 1000, aim[3] * 1000 }
	sec = CARD.rciSection(inp)
	ok(texts(sec):find("already matches", 1, true), texts(sec))
	ok(texts(sec):find("leans industrial", 1, true), texts(sec))
	-- garbage reads: no crash, a plain line
	inp = baseInput()
	inp.uses = { 0 / 0, "x", -1 }
	inp.rc = { e = { 1, 2, 3 } }
	ok(texts(CARD.rciSection(inp)):find("No deliveries yet", 1, true))
	inp = baseInput()
	inp.init, inp.sf = nil, nil
	inp.rc = { e = { 500, 500, 0 } }
	ok(#CARD.rciSection(inp).lines >= 4, "without the town's target: the built mix stands in")
end)

test("character: kind, form, style, motifs; secluded, coastal, deep; nothing saved", function()
	local inp = baseInput()
	inp.frame = { ck = CH.INDEX.hilltop, f = FM.INDEX.linear, st = 5, mo = MO.INDEX.crescent + MO.SAVE_BASE * MO.INDEX.ring_road }
	local sec = CARD.characterSection(inp)
	local t = texts(sec)
	ok(t:find("Town type: Hilltop village", 1, true) and t:find("Form: Long and narrow", 1, true)
		and t:find("Streets: Mediterranean hill town", 1, true) and t:find("Features: Crescent, Ring road", 1, true), t)
	-- (key / value rows, each description visibly under its row as a note and as the row's tooltip)
	local kinds = {}
	for _, l in ipairs(sec.lines) do kinds[#kinds + 1] = l.kind end
	eq(table.concat(kinds, " "), "row note row note row note row", "town type, form, streets with notes; features")
	eq(sec.lines[1].tip, (select(2, CARD.kindText("hilltop"))))
	eq(sec.lines[2].text, (select(2, CARD.kindText("hilltop"))))
	eq(sec.lines[3].tip, (select(2, CARD.formText("linear"))))
	eq(sec.lines[4].text, (select(2, CARD.formText("linear"))))
	eq(sec.headline, "Hilltop village")
	-- without a kind the header shows the form: no Form row repeating it, its description opens the section
	inp.frame = { f = FM.INDEX.clustered, st = 3 }
	sec = CARD.characterSection(inp)
	eq(sec.headline, "Clustered")
	ok(not texts(sec):find("Form:", 1, true), texts(sec))
	eq(sec.lines[1].kind, "note")
	eq(sec.lines[1].text, (select(2, CARD.formText("clustered"))))
	eq(sec.lines[2].key, "Streets")
	eq(sec.lines[3].text, (select(2, CARD.styleText("EU_ORGANIC"))))
	eq(CARD.kindOf({ fd = 1 }), "deep_forest")
	eq(CARD.kindOf({ ch = 1 }), "secluded")
	eq(CARD.kindOf({ cs = 1 }), "coastal")
	eq(CARD.kindOf({ ck = 99 }), nil)
	inp.frame = { a = 0, x = 1, y = 2 }
	ok(texts(CARD.characterSection(inp)):find("ordinary town", 1, true))
	inp.frame = nil
	eq(CARD.characterSection(inp), nil)
	eq(#CARD.motifs(-3), 0); eq(#CARD.motifs(1.5), 0); eq(#CARD.motifs("x"), 0)
end)

test("growth phase: from the summary, a bar toward the next phase, old saves show none", function()
	local inp = baseInput()
	inp.frame = { a = 0, x = 0, y = 0 }
	inp.ui = CARD.summary({ phase = "young", mat = 0.25 })
	local sec = CARD.phaseSection(inp)
	-- (the name is in the header: the description visibly, then the next phase with the percentage and its bar)
	eq(sec.headline, "Young")
	eq(sec.lines[1].kind, "text")
	eq(sec.lines[1].text, (select(2, CARD.phaseText("young"))))
	eq(sec.lines[2].kind, "row")
	eq(sec.lines[2].key, "Next: Growing up")
	eq(sec.lines[2].value, "50%")
	eq(sec.lines[3].kind, "bar")
	eq(sec.lines[3].color, "growth")
	eq(sec.lines[3].mark, nil)
	near(sec.lines[3].value, 0.5, 1e-9)
	ok(sec.lines[3].tip:find("50% of the way", 1, true), sec.lines[3].tip)
	for _, l in ipairs(sec.lines) do ok(l.key ~= "Young" and l.text ~= "Young", "the name isn't repeated") end
	inp.ui = CARD.summary({ phase = "mature", mat = 1 })
	eq(#CARD.phaseSection(inp).lines, 1, "no bar after mature")
	inp.ui = CARD.summary({ phase = "densify", mat = 1 })
	eq(CARD.phaseSection(inp).lines[1].text, (select(2, CARD.phaseText("densify"))), "a final phase: its description only")
	inp.ui = nil
	ok(texts(CARD.phaseSection(inp)):find("Not measured yet", 1, true), "a new map's town before its first check")
	eq(CARD.phaseSection(inp).lines[1].kind, "hint")
	inp.fresh = false
	eq(CARD.phaseSection(inp), nil, "an older save's town: no phase")
	-- a dense kind's young town heads for the early phase
	inp = baseInput()
	inp.frame = { ck = CH.INDEX.harbour_cove }
	inp.ui = CARD.summary({ phase = "young", mat = 0.1 })
	local v = CARD.view(inp)
	local found = false
	for _, s in ipairs(v.sections) do
		for _, l in ipairs(s.lines) do if l.kind == "bar" and l.tip and l.tip:find("67%", 1, true) then found = true end end
		for _, l in ipairs(s.lines) do if l.kind == "row" and l.key == "Next: Dense from the start" then found = found and true end end
	end
	ok(found, "early progress: 2 of 3 steps to EARLY_MAT")
end)

test("family: parent and offshoots as town buttons, gone towns left out, readiness lines", function()
	local inp = baseInput()
	inp.frame = { a = 0, x = 0, y = 0 }
	inp.offs = { { t = 20, p = 7, kind = "district" }, { t = 21, p = 7, kind = "works" }, { t = 22, p = 7, kind = "district" },
		{ t = 7, p = 3, kind = "district" }, "junk", { t = "x" } }
	inp.names = { [20] = "Upper Ash", [21] = "Ash Ironworks", [3] = "Ashby" }
	local sec = CARD.familySection(inp)
	local towns = {}
	for _, l in ipairs(sec.lines) do
		if l.kind == "towns" then for _, tw in ipairs(l.towns) do towns[#towns + 1] = tw.id end end
	end
	eq(towns, { 3, 20, 21 }, "the parent, then the offshoots still there")
	ok(texts(sec):find("A residential district, founded by:", 1, true))
	ok(not texts(sec):find("offshoot when", 1, true), "an offshoot has no readiness of its own")
	-- a parent town's readiness
	inp = baseInput()
	inp.frame = { a = 0, x = 0, y = 0 }
	inp.ui = CARD.summary({ phase = "blend", mat = 0.6, ready = 0.62 })
	ok(texts(CARD.familySection(inp)):find("Not ready for an offshoot yet: 60% of the way.", 1, true), texts(CARD.familySection(inp)))
	inp.ui = CARD.summary({ phase = "blend", mat = 0.6, ready = 1 })
	ok(texts(CARD.familySection(inp)):find("Ready for an offshoot", 1, true))
	inp.ui = CARD.summary({ phase = "blend", mat = 0.6 })
	ok(texts(CARD.familySection(inp)):find("No offshoots yet", 1, true))
	eq(CARD.familySection(inp).lines[1].kind, "hint", "an empty state: the base info hint")
	inp.satellitesOn = false
	ok(texts(CARD.familySection(inp)):find("Satellite towns are off", 1, true))
	inp.satellitesOn = true
	inp.frame = { ck = CH.INDEX.island_town }
	local v = CARD.view(inp)
	local all = {}
	for _, s in ipairs(v.sections) do all[#all + 1] = texts(s) end
	ok(table.concat(all, " "):find("no offshoots", 1, true), "a kind that founds none")
	-- the button cap
	inp = baseInput()
	inp.frame = { a = 0, x = 0, y = 0 }
	for i = 1, 40 do inp.offs[i] = { t = 100 + i, p = 7 }; inp.names[100 + i] = "T" .. i end
	local n = 0
	for _, l in ipairs(CARD.familySection(inp).lines) do if l.kind == "towns" then n = n + #l.towns end end
	eq(n, CARD.MAX_TOWN_BUTTONS)
end)

test("view: hidden in the map editor and without data; header summary; name origin; old saves", function()
	eq(CARD.view(nil).hidden, true)
	local inp = baseInput()
	eq(CARD.view(inp).hidden, true, "no data of ours")
	inp.frame = { ck = CH.INDEX.garden_city, f = FM.INDEX.sprawling }
	inp.ui = CARD.summary({ phase = "low", mat = 0.8 })
	inp.origin = "-,oak,frame"
	local v = CARD.view(inp)
	eq(v.hidden, false)
	eq(v.summary, "Garden city", "the header row: character left")
	eq(v.summaryValue, "Stays low", "phase right")
	local titles = {}
	for _, s in ipairs(v.sections) do titles[#titles + 1] = s.title end
	eq(titles, { "Growth by deliveries", "Character", "Growth phase", "Family", "Name origin" })
	inp.mapEditor = true
	eq(CARD.view(inp).hidden, true)
	-- an offshoot town known only from the lists (no frame yet): the family alone
	inp = baseInput()
	inp.offs = { { t = 7, p = 3 } }
	inp.names = { [3] = "Ashby" }
	v = CARD.view(inp)
	eq(v.hidden, false)
	ok(type(v.summary) == "string" and #v.summary > 0)
	eq(v.summaryValue, nil, "nothing on the right without both")
	ok(CARD.logText(inp):find("parent=3", 1, true), CARD.logText(inp))
	eq(CARD.logText(nil), "-")
end)

test("spacing: nothing touches (a gap under each headline, around bars, between groups)", function()
	local KINDS = { "row", "bar", "text", "note", "hint", "towns" }
	for _, k in ipairs(KINDS) do ok(CARD.gapBefore(nil, k) > 0, "under the headline: " .. k) end
	for _, prev in ipairs(KINDS) do
		for _, k in ipairs(KINDS) do
			local g = CARD.gapBefore(prev, k)
			ok(type(g) == "number" and g >= 0 and g <= 8, prev .. " -> " .. k)
			if prev == "bar" or prev == "note" or prev == "hint" or k == "bar" or k == "text" or k == "hint" then
				ok(g > 0, "gap " .. prev .. " -> " .. k)
			end
		end
	end
	eq(CARD.gapBefore("row", "note"), 0, "a description sits right under its row")
	ok(CARD.gapBefore("row", "bar") < CARD.gapBefore("bar", "row"), "a row's bar closer than the next group")
	-- every section of a full view: a bar is always preceded by its row
	local inp = baseInput()
	inp.frame = { ck = CH.INDEX.hilltop, f = FM.INDEX.linear, st = 5 }
	inp.rc = { e = { 100, 0, 900 } }
	inp.ui = CARD.summary({ phase = "young", mat = 0.25 })
	for _, s in ipairs(CARD.view(inp).sections) do
		for i, l in ipairs(s.lines) do
			if l.kind == "bar" then eq(s.lines[i - 1] and s.lines[i - 1].kind, "row", s.title .. " bar " .. i) end
		end
	end
end)

test("card GUI: base pieces; inline style only for the thin bar and the fixed gaps; no stylesheet of ours", function()
	local fh = assert(io.open(here .. "../../mods/square_organic_towns/content/organic_towns/gui/ot_card.script.tl", "r"))
	local src = fh:read("a")
	fh:close()
	local code = src:gsub("%-%-[^\n]*", "")
	for _, w in ipairs({ "ProgressDisplay", "secondary", "extraValue" }) do
		ok(not code:find(w, 1, true), "no " .. w)
	end
	for _, w in ipairs({ "builtin.ProgressBar", "thresholds", "font-scale-annotation", "makeInfoHint",
		"card-children-separator", "makeHorizontalSpacer", "selectEntity", "gapBefore" }) do
		ok(code:find(w, 1, true), "uses " .. w)
	end
	-- (the only inline sheets: barSheet and the gap spacer; never read back)
	local n = 0
	for _ in code:gmatch("styleSheet%s*=") do n = n + 1 end
	eq(n, 2, "two inline sheet uses")
	ok(not code:find("%.color[^%w_]") or not code:find("Sheet[%w_]*%.color"), "no sheet read back")
	local dir = here .. "../../mods/square_organic_towns/content/organic_towns/gui/"
	ok(io.open(dir .. "ot_card.css.lua", "r") == nil, "no stylesheet of the card")
end)

test("notification: dedupe by session and saved claims, params, texts with odd names", function()
	eq(CARD.shouldNotify(nil, nil, 5), true)
	eq(CARD.shouldNotify({}, { [5] = true }, 5), false, "sent this session")
	eq(CARD.shouldNotify({ dk = { { t = 5, p = 1 } } }, {}, 5), false, "a saved district")
	eq(CARD.shouldNotify({ wm = { { t = 5, p = 1 } } }, {}, 5), false, "a saved Works")
	eq(CARD.shouldNotify({ wk = { 5 } }, {}, 5), false)
	eq(CARD.shouldNotify({ dk = { { t = 6, p = 1 } }, wk = "x" }, {}, 5), true)
	eq(CARD.shouldNotify({}, {}, nil), false)
	local p = CARD.noteParams(12.0, 3, "works", "100% Mill {x}", ("P"):rep(100), 4)
	eq(p.town, 12); eq(p.kind, "works"); eq(#p.parentName, 64); eq(p.rev, 4)
	local title, desc = CARD.noteText(p)
	eq(title, "New Works town: 100% Mill {x}")
	ok(desc:find("100% Mill {x}", 1, true))
	title = CARD.noteText(CARD.noteParams(1, 2, "district", "Old", "P"), "Renamed", "Q")
	eq(title, "New district: Renamed", "the current name")
	eq(CARD.noteParams(1, 2, "weird").kind, "district")
	eq(CARD.fmt("{a} {b}", { a = "%1" }), "%1 {b}")
end)

test("saved state: name origins and summaries normalised, capped, idempotent; old saves keep working", function()
	local s0 = SV.normalize({ v = 1, known = {}, frames = {} })
	eq(s0.no, nil); eq(s0.ui, nil)
	eq(SV.origin(s0, 1), nil); eq(SV.ui(s0, 1), nil)
	local s, changed = SV.applyNames(s0, { done = 1, no = { { t = 4, o = "bend,oak,frame" }, { t = 5, o = "BAD" }, "x" } })
	eq(changed, true)
	eq(SV.origin(s, 4), "bend,oak,frame")
	eq(SV.origin(s, 5), nil)
	local s2, ch2 = SV.applyNames(s, { done = 1, no = { { t = 9, o = "lake,-,plain" } } })
	eq(ch2, false, "names once")
	eq(SV.origin(s2, 9), nil)
	-- summaries
	local v = CARD.summary({ phase = "blend", mat = 0.6, ready = 0.3 })
	local u, chu = SV.applyUi(s, { towns = { { t = 4, v = v }, { t = 8, v = "bad" } } })
	eq(chu, true); eq(SV.ui(u, 4), v); eq(SV.ui(u, 8), nil)
	local u2, chu2 = SV.applyUi(u, { towns = { { t = 4, v = v } } })
	eq(chu2, false, "idempotent")
	eq(SV.origin(u2, 4), "bend,oak,frame", "kept through other events")
	local u3 = SV.applyRci(u2, { town = 4, e = { 1, 2, 3 }, s = 100, y = 190000 })
	eq(SV.ui(u3, 4), v, "kept through other events")
	-- the cap
	local big = { v = 1, known = {}, frames = {}, ui = {} }
	for i = 1, SV.UI_CAP do big.ui[tostring(i)] = "1:0:-" end
	local b2, chb = SV.applyUi(big, { towns = { { t = SV.UI_CAP + 5, v = "1:0:-" }, { t = 3, v = "2:12:-" } } })
	eq(chb, true)
	eq(SV.ui(b2, SV.UI_CAP + 5), nil, "no new town past the cap")
	eq(SV.ui(b2, 3), "2:12:-", "a known town still updates")
	local many = {}
	for i = 1, SV.UI_BATCH + 10 do many[i] = { t = 9000 + i, v = "1:1:-" } end
	local b3 = SV.applyUi(nil, { towns = many })
	local n = 0
	for _ in pairs(b3.ui) do n = n + 1 end
	eq(n, SV.UI_BATCH, "a batch at most")
	eq(SV.applyUi(nil, "x").ui, nil)
end)

test("driver: summaries noted at checks on a new map, written in batches only when they moved", function()
	local events, logs = {}, {}
	local E = { nowUs = function() return 0 end, log = function(l) logs[#logs + 1] = l end,
		sendEvent = function(id, name, p) events[#events + 1] = { id = id, name = name, p = p } end,
		year = function() return 1960 end, name = function(t) return "T" .. t end, towns = function() return { 1, 2 } end }
	local d = D.new(E)
	d.opts = PA.parse({}, {})
	d.saved = { v = 1, known = {}, frames = {} }
	local m = { buildings = 300, caps = { actual = 1200 }, dem = { mat = 0.3 } }
	d.newMap = false
	d:uiNote(1, m)
	eq(d.uiPending, nil, "an older save: nothing")
	d.newMap = true
	d:uiNote(1, m)
	d:townState(2).paceRatio = 0.5
	d:uiNote(2, m)
	d:uiTick(1e6, d.saved)
	eq(#events, 1)
	eq(events[1].name, SV.EV_UI)
	eq(#events[1].p.towns, 2)
	local p1 = CARD.parseSummary(events[1].p.towns[1].v)
	eq(p1.phase, "young"); eq(p1.ready, nil)
	eq(CARD.parseSummary(events[1].p.towns[2].v).ready, 0.5)
	local nCard = 0
	for _, l in ipairs(logs) do if l:find("CARD", 1, true) and l:find("event=summary", 1, true) then nCard = nCard + 1 end end
	eq(nCard, 1, "one CARD line for the first batch")
	-- the same values again: nothing; not before UI_FLUSH_S either
	d:uiNote(1, m)
	d:uiTick(2e6, d.saved)
	eq(#events, 1, "too early")
	d:uiTick(2e6 + D.UI_FLUSH_S * 1e6, d.saved)
	eq(#events, 1, "unchanged")
	-- grown: written
	d:uiNote(1, { buildings = 600, caps = { actual = 3000 }, dem = { mat = 0.8 } })
	d:uiTick(3e6 + 2 * D.UI_FLUSH_S * 1e6, d.saved)
	eq(#events, 2)
	eq(#events[2].p.towns, 1)
	-- a reload: the saved summary counts as sent
	local d2 = D.new(E)
	d2.opts = PA.parse({}, {})
	d2.newMap = true
	local saved = SV.applyUi(nil, { towns = events[2].p.towns })
	d2.saved = saved
	d2:uiNote(1, { buildings = 600, caps = { actual = 3000 }, dem = { mat = 0.8 } })
	d2:uiTick(1e9, saved)
	eq(#events, 2, "nothing new after a reload")
	-- the batch cap
	local d3 = D.new(E)
	d3.opts = PA.parse({}, {})
	d3.newMap = true
	d3.saved = { v = 1, known = {}, frames = {} }
	for t = 1, SV.UI_BATCH + 5 do d3:uiNote(t, m) end
	d3:uiTick(1e6, d3.saved)
	eq(#events[#events].p.towns, SV.UI_BATCH)
	d3:uiTick(1e6 + D.UI_FLUSH_S * 1e6, d3.saved)
	eq(#events[#events].p.towns, 5, "the rest next time")
end)
