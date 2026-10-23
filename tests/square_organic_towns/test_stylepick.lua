-- The player's street style pick in the town window card (2026-10-21, PLAN "Street style pick"): the saved frame's `ps`
-- (ot_saved.applyStyle: valid / invalid ids, unknown town, idempotency, Automatic clears it, older frames without `st`,
-- normalize keeps it), the frame() read-back, ot_style.resolve's precedence (dev style > the player's pick > the "Town
-- style" setting's forced grid > the saved style > character / site), the card model (the dropdown's options and
-- selected value, Automatic named after the town's own style, the pending pick, read-only when the mod is off) and the
-- card GUI (the base ComboBox, the event sent from its handler, one log line, nothing sent for the shown value).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local SV = ug_require(F.DIR .. "ot_saved.lua")
local CARD = ug_require(F.DIR .. "ot_card.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local CH = ug_require(F.DIR .. "ot_character.lua")

local function idx(id)
	for i, v in ipairs(SV.STYLE_IDS) do if v == id then return i end end
	error("no style " .. tostring(id))
end

local function framed(extra)
	local s = SV.normalize(nil)
	s.known = {}
	s.frames["7"] = { a = 0.5, x = 10, y = 20, st = idx("EU_ORGANIC") }
	for k, v in pairs(extra or {}) do s.frames["7"][k] = v end
	return s
end

test("applier: valid ids set the pick, Automatic clears it, invalid ids and unknown towns change nothing, idempotent", function()
	local s, changed, was, now = SV.applyStyle(framed(), { town = 7, ps = idx("NA_GRID") })
	ok(changed, "set")
	eq(s.frames["7"].ps, idx("NA_GRID"))
	eq(was, nil); eq(now, idx("NA_GRID"))
	eq(s.frames["7"].st, idx("EU_ORGANIC"), "the town's own style stays")
	eq(s.frames["7"].a, 0.5, "the axis stays")
	local s2, changed2 = SV.applyStyle(s, { town = 7, ps = idx("NA_GRID") })
	eq(changed2, false, "the same pick again: no change (handleEvent may run in more than one state)")
	eq(s2.frames["7"].ps, idx("NA_GRID"))
	local s3, changed3, was3 = SV.applyStyle(s, { town = "7", ps = idx("NORDIC") })
	ok(changed3, "another pick")
	eq(was3, idx("NA_GRID"))
	eq(s3.frames["7"].ps, idx("NORDIC"))
	local s4, changed4 = SV.applyStyle(s3, { town = 7, ps = 0 })
	ok(changed4, "Automatic")
	eq(s4.frames["7"].ps, nil, "cleared")
	eq(select(2, SV.applyStyle(s4, { town = 7, ps = 0 })), false, "Automatic again: no change")
	for _, bad in ipairs({ -1, #SV.STYLE_IDS + 1, 1.5, "x", 0 / 0, math.huge, true }) do
		local sb, cb = SV.applyStyle(s, { town = 7, ps = bad })
		eq(cb, false, "invalid ps " .. tostring(bad))
		eq(sb.frames["7"].ps, idx("NA_GRID"), "kept for " .. tostring(bad))
	end
	eq(select(2, SV.applyStyle(s, { town = 7 })), false, "no ps")
	eq(select(2, SV.applyStyle(s, { town = 99, ps = 1 })), false, "a town without a frame")
	eq(select(2, SV.applyStyle(s, { town = 7.5, ps = 1 })), false, "not a town id")
	eq(select(2, SV.applyStyle(s, nil)), false, "no param")
	eq(select(2, SV.applyStyle(nil, { town = 7, ps = 1 })), false, "no state")
	local s5 = SV.applyStyle(s, { town = 99, ps = 1 })
	eq(s5.frames["99"], nil, "no frame made for an unknown town")
end)

test("applier on an older frame without `st`; normalize keeps a valid pick and drops a broken one; read-back", function()
	local s = SV.normalize(nil)
	s.known = {}
	s.frames["3"] = { a = 0, x = 1, y = 2 }
	local s2, changed = SV.applyStyle(s, { town = 3, ps = idx("MED_HILL") })
	ok(changed)
	local fr = SV.frame(s2, 3)
	eq(fr.playerStyle, "MED_HILL")
	eq(fr.style, nil, "no own style saved")
	-- (normalize, as every applier runs it: the pick survives the next unrelated event)
	local s3 = SV.applyDense(s2, { town = 3, v = 1 })
	eq(s3.frames["3"].ps, idx("MED_HILL"), "kept through another applier")
	eq(SV.normalize({ v = 1, known = {}, frames = { ["3"] = { a = 0, x = 1, y = 2, ps = 42 } } }).frames["3"].ps, nil)
	eq(SV.normalize({ v = 1, known = {}, frames = { ["3"] = { a = 0, x = 1, y = 2, ps = "2" } } }).frames["3"].ps, 2)
	-- frame(): the own style and the pick apart (resolve needs both)
	local f2 = SV.frame(framed({ ps = idx("SUPERBLOCK") }), 7)
	eq(f2.style, "EU_ORGANIC"); eq(f2.playerStyle, "SUPERBLOCK")
	eq(SV.frame(framed({ ps = 77 }), 7).playerStyle, nil, "a broken saved pick reads as none")
	eq(SV.frame(framed(), 7).playerStyle, nil, "an older save: no pick")
	-- the pick never comes from frameParam (a first frame has none)
	local p = SV.frameParam(7, { axis = 0, centre = { 0, 0 }, id = "NA_GRID", styleSource = "player" }, nil)
	eq(p.st, nil, "a player style isn't the town's own style")
	eq(p.ps, nil)
end)

local function inputs(o)
	local r = { townId = 11, year = 1975, nameList = "::/names/france/france.names", pos = { 0, 0 }, capacity = 900,
		terrain = T.stats(F.flat, 0, 0, 600, 24), forceStyle = o.force, forceFrom = o.from,
		frame = o.frame }
	local inp = I.build(r)
	inp.wide = T.wide(F.flat, 0, 0, 2000)
	inp.autoStyle = o.force == nil
	if o.kind then
		inp.charKind, inp.charForm, inp.charMotifs = o.kind, CH.formFor(o.kind), CH.motifsFor(o.kind)
		inp.charSite = { region = inp.region }
	end
	return inp
end

test("resolve: dev style > the player's pick > the setting's forced grid > the saved style", function()
	local frame = { axis = 0.3, origin = { 0, 0 } }
	-- the setting's grid, no pick: forced as before (no outer zone)
	local p = ST.resolve(inputs({ force = "NA_GRID", from = "setting", frame = frame }))
	eq(p.id, "NA_GRID"); eq(p.styleSource, "forced"); eq(p.outer, nil, "a forced style has no outer zone")
	-- the player's pick wins over the setting, with its own outer zone as any town of that style
	local fp = { axis = 0.3, origin = { 0, 0 }, playerStyle = "EU_ORGANIC" }
	p = ST.resolve(inputs({ force = "NA_GRID", from = "setting", frame = fp }))
	eq(p.id, "EU_ORGANIC"); eq(p.styleSource, "player")
	eq(p.outer and p.outer.id, "EU_EXTENSION", "the EU organic town's extension ring")
	near(p.axis, 0.3, 1e-9, "the saved axis stays")
	-- a dev style (forceFrom nil) wins over the pick
	p = ST.resolve(inputs({ force = "JP_DENSE", frame = fp }))
	eq(p.id, "JP_DENSE"); eq(p.styleSource, "forced")
	-- over the saved own style
	local fs = { axis = 0.3, origin = { 0, 0 }, style = "MED_HILL", playerStyle = "NORDIC" }
	p = ST.resolve(inputs({ frame = fs }))
	eq(p.id, "NORDIC"); eq(p.styleSource, "player")
	fs.playerStyle = nil
	p = ST.resolve(inputs({ frame = fs }))
	eq(p.id, "MED_HILL"); eq(p.styleSource, "saved", "no pick: the own style")
	-- the setting's grid still wins over a saved own style without a pick (as before)
	p = ST.resolve(inputs({ force = "NA_GRID", from = "setting", frame = fs }))
	eq(p.id, "NA_GRID"); eq(p.styleSource, "forced")
	-- a broken pick: ignored
	p = ST.resolve(inputs({ frame = { axis = 0.3, origin = { 0, 0 }, style = "MED_HILL", playerStyle = "NOPE" } }))
	eq(p.id, "MED_HILL")
	-- over a strong character's own style; the character's knobs still apply
	local kind = "hilltop"
	p = ST.resolve(inputs({ kind = kind, frame = { axis = 0.3, origin = { 0, 0 }, playerStyle = "NA_SUBURB" } }))
	eq(p.id, "NA_SUBURB"); eq(p.styleSource, "player")
	eq(p.charKind, kind, "the character stays")
	-- every style can be picked
	for _, id in ipairs(SV.STYLE_IDS) do
		p = ST.resolve(inputs({ force = "NA_GRID", from = "setting", frame = { axis = 0, origin = { 0, 0 }, playerStyle = id } }))
		eq(p.id, id, "pick " .. id)
	end
end)

local function cardInput(frame, o)
	o = o or {}
	return { town = 7, fresh = true, rciOn = false, satellitesOn = true, names = {}, offs = {}, frame = frame,
		stylePick = o.pick ~= false, forcedStyle = o.forced, pendingStyle = o.pending, mapEditor = o.mapEditor }
end

local function styleLine(sec)
	for i, l in ipairs(sec and sec.lines or {}) do if l.kind == "style" then return l, sec.lines[i + 1] end end
	return nil
end

test("card model: the dropdown's options and selected value, Automatic named after the own style, the note follows", function()
	eq(CARD.EVENT_ID, SV.EVENT_ID); eq(CARD.EV_STYLE, SV.EV_STYLE)
	local l, note = styleLine(CARD.characterSection(cardInput({ a = 0, x = 0, y = 0, st = idx("EU_ORGANIC") })))
	ok(l ~= nil, "a dropdown on a town the mod manages")
	eq(l.key, "Streets")
	eq(#l.options, #SV.STYLE_IDS + 1, "Automatic and the nine styles")
	eq(l.options[1].value, "0")
	eq(l.options[1].text, "Automatic (Old European)")
	for i, id in ipairs(SV.STYLE_IDS) do
		local n, d = CARD.styleText(id)
		eq(l.options[i + 1].value, tostring(i)); eq(l.options[i + 1].text, n); eq(l.options[i + 1].tip, d)
	end
	eq(l.selected, "0", "no pick: Automatic")
	eq(l.from, "EU_ORGANIC")
	eq(l.town, 7)
	ok(l.tip:find("new streets", 1, true) and l.tip:find("already built", 1, true), l.tip)
	ok(l.tip:find("\n", 1, true), "wrapped")
	eq(note.kind, "note"); eq(note.text, (select(2, CARD.styleText("EU_ORGANIC"))))
	-- a pick: selected, the note follows it
	l, note = styleLine(CARD.characterSection(cardInput({ a = 0, x = 0, y = 0, st = idx("EU_ORGANIC"), ps = idx("NORDIC") })))
	eq(l.selected, tostring(idx("NORDIC")))
	eq(l.from, "NORDIC")
	eq(note.text, (select(2, CARD.styleText("NORDIC"))))
	eq(l.options[1].text, "Automatic (Old European)", "Automatic still names the own style")
	-- the setting's forced grid: the own style shown is the grid (the saved one isn't in effect)
	l = styleLine(CARD.characterSection(cardInput({ a = 0, x = 0, y = 0, st = idx("EU_ORGANIC") }, { forced = "NA_GRID" })))
	eq(l.options[1].text, "Automatic (North American grid)")
	eq(l.from, "NA_GRID")
	-- an older frame without a saved style and no forced setting: plain Automatic, no note
	l, note = styleLine(CARD.characterSection(cardInput({ a = 0, x = 0, y = 0 })))
	eq(l.options[1].text, "Automatic")
	eq(l.selected, "0")
	ok(note == nil or note.kind ~= "note", "no description to show")
	-- a pick sent and not read back yet: shown
	l = styleLine(CARD.characterSection(cardInput({ a = 0, x = 0, y = 0, st = 3 }, { pending = idx("SUPERBLOCK") })))
	eq(l.selected, tostring(idx("SUPERBLOCK")))
	l = styleLine(CARD.characterSection(cardInput({ a = 0, x = 0, y = 0, st = 3, ps = 2 }, { pending = 0 })))
	eq(l.selected, "0", "Automatic pending")
	-- garbage pick: Automatic
	l = styleLine(CARD.characterSection(cardInput({ a = 0, x = 0, y = 0, st = 3, ps = 99 })))
	eq(l.selected, "0")
	-- the mod off: the read-only row as before (with the pick in effect)
	local sec = CARD.characterSection(cardInput({ a = 0, x = 0, y = 0, st = 3, ps = idx("NORDIC") }, { pick = false }))
	eq(styleLine(sec), nil)
	eq(sec.lines[1].kind, "row"); eq(sec.lines[1].key, "Streets"); eq(sec.lines[1].value, "Nordic")
	-- no frame: no section; the map editor: no card
	eq(CARD.characterSection(cardInput(nil)), nil)
	ok(CARD.view(cardInput({ a = 0, x = 0, y = 0 }, { mapEditor = true })).hidden)
	-- spacing as a row
	eq(CARD.gapBefore("style", "note"), 0)
	eq(CARD.gapBefore("note", "style"), CARD.gapBefore("note", "row"))
end)

test("card GUI: the base ComboBox, the event sent from its handler, one log line, nothing for the shown value", function()
	local nodes, recipes, sent = {}, {}, {}
	local function node(kind) return function(p) local n = { kind = kind, p = p or {} } nodes[#nodes + 1] = n return n end end
	local b = { type = { Orientation = { Vertical = 1, Horizontal = 0 }, ImageViewScaling = { AutoFit = 0 } } }
	for _, k in ipairs({ "BoxLayout", "FlowLayout", "Component", "TextView", "Button", "ImageView", "ProgressBar",
		"ComboBox", "ComboBoxItem" }) do b[k] = node(k) end
	stub_module("::/gui/main/react.lua", {
		RegisterRecipe = function(name, fn) recipes[name] = fn return fn end,
		RegisterPluginRecipe = function(_, name, fn) recipes[name] = fn return fn end,
		getCurrentRecipeId = function() return 1 end,
		fireEvent = function() end,
	})
	stub_module("::/gui/main/builtin.lua", b)
	stub_module("::/gui/main/content_card.tl", {
		ContentCard = function() return { kind = "ContentCard" } end,
		makeRecipeAndParam = function(r, p) return { r = r, p = p } end,
	})
	stub_module("::/gui/main/gui_react_util.tl", {})
	stub_module("::/gui/main/engine_react_util.tl", {
		useStepStateTimer = function(fn) local v = fn() return { old = function() return v end } end })
	stub_module("::/gui/main/styleutil.tl", { makeStyle = function(t) return { style = t } end })
	stub_module("::/gui/main/color_util.tl", { withTransparencyRaw = function(c, a) return { c[1], c[2], c[3], a } end })
	stub_module("::/gui/entity_window/town/town_eow.script.tl", { TownEowExtensionPoint = {} })
	set_global("api", {
		engine = { config = { getModParams = function() return {} end }, entityExists = function() return true end,
			system = { gameScriptSystem = { getEntityForGameScript = function() return -1 end } },
			getComponent = function() return { name = "Ashby Vale" } end },
		type = { ComponentType = {} },
		gui = { genericRep = { find = function() return -1 end, get = function() return nil end } },
		cmd = {
			makeScriptingSendEventCmd = function(src, id, name, p) return { src = src, id = id, name = name, p = p } end,
			sendCommand = function(cmd, cb) sent[#sent + 1] = cmd; eq(cb, nil, "no callback") end,
		},
	})
	reset_modules()
	local M = ug_require(F.DIR .. "gui/ot_card.script.tl")
	ok(M.SquareOrganicTownsCard ~= nil)
	local sec = CARD.characterSection(cardInput({ a = 0, x = 0, y = 0, st = idx("EU_ORGANIC") }))
	local view = { summary = "Clustered", sections = { sec } }
	nodes = {}
	recipes.SquareOrganicTownsCardBody({ view = view })
	local box, items = nil, 0
	for _, n in ipairs(nodes) do
		if n.kind == "ComboBox" then box = n end
		if n.kind == "ComboBoxItem" then
			items = items + 1
			ok(n.p.content.kind == "TextView" and n.p.content.p.meta.tooltip ~= nil, "each item carries its tooltip")
		end
	end
	ok(box ~= nil, "the base ComboBox")
	eq(items, #SV.STYLE_IDS + 1)
	eq(box.p.value, "0")
	ok(box.p.meta.tooltip:find("new streets", 1, true), "the dropdown's tooltip")
	clear_logs()
	box.p.onValueChange("0")
	eq(#sent, 0, "the shown value: nothing sent")
	box.p.onValueChange("42")
	box.p.onValueChange("x")
	eq(#sent, 0, "not an option: nothing sent")
	box.p.onValueChange(tostring(idx("NA_GRID")))
	eq(#sent, 1, "one event")
	eq(sent[1].id, SV.EVENT_ID); eq(sent[1].name, SV.EV_STYLE)
	eq(sent[1].p.town, 7); eq(sent[1].p.ps, idx("NA_GRID"))
	local lines = {}
	for _, e in ipairs(log_entries()) do
		local m = type(e) == "table" and (e.msg or e.message or e[2]) or e
		if tostring(m):find("[SQOT] STYLE event=pick", 1, true) then lines[#lines + 1] = tostring(m) end
	end
	eq(#lines, 1, "one log line")
	ok(lines[1] and lines[1]:find("town=7", 1, true) and lines[1]:find("from=EU_ORGANIC", 1, true)
		and lines[1]:find("to=NA_GRID", 1, true) and lines[1]:find("name=Ashby_Vale", 1, true), tostring(lines[1]))
	box.p.onValueChange(tostring(0 + 0))
	eq(#sent, 1, "Automatic is the shown value here")
	-- a picked town: Automatic sends 0
	nodes = {}
	recipes.SquareOrganicTownsCardBody({ view = { sections = { CARD.characterSection(cardInput({ a = 0, x = 0, y = 0,
		st = 3, ps = 1 })) } } })
	for _, n in ipairs(nodes) do if n.kind == "ComboBox" then box = n end end
	box.p.onValueChange("0")
	eq(#sent, 2); eq(sent[2].p.ps, 0, "Automatic clears the pick")
end)
