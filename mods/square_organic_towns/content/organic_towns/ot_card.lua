-- Organic Towns: the town window's "Organic Towns" card and the new-town notification (pure; 2026-10-17, rev 3).
--
-- The card (gui/ot_card.script.tl, ::TownEowExtensionPoint) polls a small input table (M.view's `input`, plain data)
-- from the saved game-script state (state_native, never the whole copy) and the town's own components, and this
-- module turns it into a display model: a summary line for the card's header and up to five sections of lines.
-- Every text is chosen here (all `_()` literals live in functions, so the game-script state that requires this module
-- for M.summary / M.originCode never calls `_`). Sections:
--   1. Growth by deliveries (ot_rci, §66): the built R/C/I shares, the aim from the saved smoothed usage (`rc` e; live
--      usage until the first written step), the lean (ot_rci.lean on the target mix) and the pull (the district whose
--      aim is furthest above its target share). Off when "Town growth" is Game default or Act on is Off.
--   2. Character: the strong kind (`ck`, ot_character.IDS), deep forest (`fd`), a secluded character town (`ch`), a
--      coastal hugger (`cs`); the form (`f`, ot_form.IDS), the street style (the player's pick `ps`, else the setting's
--      forced grid, else `st`; ot_saved.STYLE_IDS) as a dropdown where the player may change it (M.stylePick,
--      2026-10-21: the card sends ot_saved.EV_STYLE), the motifs (`mo`, ot_motif encode).
--   3. Growth phase: the driver's summary (`ui`, M.summary: phase, level maturity in twentieths) with the progress to the
--      next phase where one follows (ot_upward LV_BLEND_MAT / LV_MATURE_MAT / EARLY_MAT).
--   4. Family: the parent (`dk` / `wm` entries whose t is this town) and the offshoots (entries whose p is it), as town
--      buttons; the offshoot readiness from the summary (ot_satpace.readiness ratio, in twentieths).
--   5. Name origin: the saved generated-name parts (`no`: "<genTag>,<specTag>,<shape>", M.originCode) as one sentence.
-- The ID lists below mirror ot_character / ot_form / ot_saved / ot_motif / ot_upward (copied so the GUI state loads
-- one small module; tests/square_organic_towns/test_card.lua checks they match). Plain Lua, pre-5.3; loops bounded.

local RCI = ug_require "square_organic_towns::/organic_towns/ot_rci.lua"
local PA = ug_require "square_organic_towns::/organic_towns/ot_params.lua"

local M = {}

M.KIND_IDS = { "deep_forest", "hilltop", "clifftop", "harbour_cove", "waterfront", "street_village", "company_town",
	"garden_city", "island_town", "roundabout_town" }
M.FORM_IDS = { "clustered", "radiating", "sprawling", "linear", "wide", "fingers", "shore" }
-- the game script's event for the player's street style pick (ot_saved.EVENT_ID / EV_STYLE, mirrored: the card's state
-- loads no ot_saved)
M.EVENT_ID = "square_organic_towns"
M.EV_STYLE = "square_organic_towns.style"
M.STYLE_IDS = { "NA_GRID", "NA_SUBURB", "EU_ORGANIC", "EU_EXTENSION", "MED_HILL", "MED_ENSANCHE", "JP_DENSE", "NORDIC",
	"SUPERBLOCK" }
M.MOTIF_IDS = { "crescent", "hill_road", "hill_climb", "valley_fishbone", "harbour_crescent", "fishing_village",
	"ribbon_village", "village_green", "crossroads_hamlet", "ring_road", "station_quarter", "workers_terraces",
	"culdesac_pods", "switchbacks", "ridge_street", "headland_street", "bridgehead_quarter", "peninsula_tip" }
-- kinds that found no offshoots (ot_character offshoots = false) and kinds with early level weights (levels = "early")
M.NO_OFFSHOOTS = { deep_forest = true, hilltop = true, clifftop = true, harbour_cove = true, street_village = true,
	company_town = true, island_town = true }
M.EARLY_KINDS = { hilltop = true, harbour_cove = true, company_town = true, island_town = true }
M.MOTIF_BASE = 64         -- ot_motif.SAVE_BASE
M.MOTIF_MAX = 2           -- ot_motif.MAX
-- the growth phases (saved summary index: append only). young / blend / mature / densify / early as ot_upward.levelPhase;
-- low: a kind without level weights (deep forest, garden city: ot_character levels = "off")
M.PHASES = { "young", "blend", "mature", "densify", "early", "low" }
M.PHASE_INDEX = {}
for i, id in ipairs(M.PHASES) do M.PHASE_INDEX[id] = i end
M.BLEND_MAT = 0.5         -- ot_upward.LV_BLEND_MAT
M.MATURE_MAT = 0.9        -- ot_upward.LV_MATURE_MAT
M.EARLY_MAT = 0.15        -- ot_upward.EARLY_MAT
M.STEPS = 20              -- the summary's maturity / readiness in twentieths
M.MOVE_STEPS = 2          -- a new summary is written when a value moved this many steps (or the phase / ready changed)
M.PULL_MIN = 0.03         -- the aim this far above a district's target share pulls the town toward it
M.MAX_OFFS = 64           -- offshoot entries read at most (ot_saved.WORKS_CAP)
M.MAX_TOWN_BUTTONS = 12
M.NOTE_TYPE = "square_organic_towns::/organic_towns/notify/ot_new_town.script"
M.NOTE_DISMISS_MS = 60000
-- the bar colors (the GUI maps them to the base colors: district_colors.gres max, as the District Sizes chart above the
-- card, town_eow.script.tl:223-225; "growth": gameplay_colors.gres TownGrowth, as the Town Level bar)
M.DISTRICT_COLORS = { "res", "com", "ind" }
-- the gaps (px) the GUI puts between a section's lines (M.gapBefore), after a headline and around a separator; the base
-- layout's own 2 px gap leaves rows and bars nearly touching (docs/ui-guide.md "Spacing")
M.GAP = 6                 -- between groups (a row with its bar or its note, a sentence)
M.GAP_IN = 3              -- inside a group: a row and its bar
M.GAP_HEAD = 4            -- under a headline, and on both sides of a separator

local function finite(x)
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function num(x)
	x = tonumber(x)
	if x == nil or not finite(x) then return nil end
	return x
end

local function clamp(x, a, b)
	if x < a then return a end
	if x > b then return b end
	return x
end

local function pct(x) return math.floor(clamp(num(x) or 0, 0, 1) * 100 + 0.5) end

--- "{name}" placeholders filled from vars (plain replacement: names with % or {} stay as they are).
function M.fmt(s, vars)
	if type(s) ~= "string" then return "" end
	return (s:gsub("{([%w_]+)}", function(k)
		local v = vars and vars[k]
		if v == nil then return "{" .. k .. "}" end
		return tostring(v)
	end))
end

---------------------------------------------------------------------------
-- the driver's per-town summary (saved `ui`, ot_saved.applyUi)

--- The summary text of o = { phase = M.PHASES id, mat = level maturity 0..1, ready = offshoot readiness ratio or nil }:
--- "<phase index>:<maturity x 20>:<readiness x 20, at most 20, or ->"; nil for an unknown phase.
function M.summary(o)
	if type(o) ~= "table" then return nil end
	local p = M.PHASE_INDEX[o.phase or ""]
	if p == nil then return nil end
	local m = math.floor(clamp(num(o.mat) or 0, 0, 1) * M.STEPS + 0.5)
	local r = num(o.ready)
	local rs = r and tostring(math.floor(clamp(r, 0, 1) * M.STEPS + 1e-9)) or "-"
	return string.format("%d:%d:%s", p, m, rs)
end

--- A saved summary back: { phase, mat (0..1), ready (0..1, 1 = ready) or nil } or nil.
function M.parseSummary(v)
	if type(v) ~= "string" or #v > 16 then return nil end
	local p, m, r = v:match("^(%d):(%d+):([%d%-]+)$")
	if p == nil then return nil end
	local phase = M.PHASES[tonumber(p)]
	if phase == nil then return nil end
	local out = { phase = phase, mat = clamp(tonumber(m) / M.STEPS, 0, 1) }
	if r ~= "-" and tonumber(r) then out.ready = clamp(tonumber(r) / M.STEPS, 0, 1) end
	return out
end

--- Should a new summary replace the last one written (old: its text or nil)? The phase or the ready state changed, or the
--- maturity / readiness moved MOVE_STEPS (small wobbles of the town's persons write nothing).
function M.summaryMoved(old, new)
	if new == nil then return false end
	if old == nil then return true end
	if old == new then return false end
	local a, b = M.parseSummary(old), M.parseSummary(new)
	if a == nil or b == nil then return true end
	if a.phase ~= b.phase then return true end
	if math.abs(a.mat - b.mat) * M.STEPS >= M.MOVE_STEPS - 1e-9 then return true end
	if (a.ready == nil) ~= (b.ready == nil) then return true end
	if a.ready and b.ready then
		if (a.ready >= 1) ~= (b.ready >= 1) then return true end
		if math.abs(a.ready - b.ready) * M.STEPS >= M.MOVE_STEPS - 1e-9 then return true end
	end
	return false
end

--- The progress toward the next phase: next phase id and 0..1, or nil (no next phase: mature, densify, early, low).
function M.phaseProgress(phase, mat, densify)
	mat = clamp(num(mat) or 0, 0, 1)
	if phase == "young" then
		if densify == "early" then return "early", clamp(mat / M.EARLY_MAT, 0, 1) end
		return densify == true and "densify" or "blend", clamp(mat / M.BLEND_MAT, 0, 1)
	end
	if phase == "blend" then
		return "mature", clamp((mat - M.BLEND_MAT) / (M.MATURE_MAT - M.BLEND_MAT), 0, 1)
	end
	return nil
end

---------------------------------------------------------------------------
-- name origins (saved `no`)

-- the generated name's site tags (ot_placename.TAGS) -> the origin sentence id
M.ORIGIN_OF_TAG = {
	river = "river", brook = "brook", spring = "brook", ford = "ford", bridge = "ford", bend = "bend",
	confluence = "confluence", twin = "confluence", mouth = "mouth",
	lake = "lake", mere = "lake", pool = "lake", tarn = "lake", biglake = "lake",
	coast = "coast", sandy = "coast", rocky = "coast", lagoon = "coast", reef = "coast", dune = "coast",
	bay = "bay", bigbay = "bay", headland = "cape", spit = "cape", cliff = "cape", island = "island",
	narrows = "narrows", isthmus = "narrows",
	hill = "hill", hilltop = "hill", slope = "hill", ridge = "hill", rock = "hill", summit = "hill",
	mountain = "mountain", peak = "mountain", range = "mountain", pass = "mountain", foot = "mountain",
	divide = "mountain", mesa = "mountain", snow = "mountain",
	valley = "valley", vale = "valley", gorge = "valley", combe = "valley", mainvalley = "valley", wadi = "valley",
	falls = "falls", marsh = "marsh", fen = "marsh", mangrove = "marsh", moor = "moor", heath = "moor",
	forest = "forest", edge = "forest", clearing = "forest", boreal = "forest", tropic = "tropic", arid = "arid",
	plain = "field", field = "field", meadow = "field", market = "market", big = "market", church = "church",
	north = "north", south = "south", east = "east", west = "west", central = "central",
	upper = "upper", lower = "lower", old = "old", new = "new",
}
for _i, sp in ipairs({ "oak", "ash", "beech", "birch", "elm", "lime", "maple", "hazel", "alder", "willow", "poplar", "pine",
	"fir", "spruce", "larch", "yew", "holly", "apple", "elder", "palm", "cypress" }) do
	M.ORIGIN_OF_TAG[sp] = "trees"
end

local function tagWord(v)
	if type(v) ~= "string" or v == "" or #v > 15 or not v:match("^[a-z_]+$") then return "-" end
	return v
end

--- The saved origin code of a generated name's info (ot_placename.nameTown: genTag, specTag, shape):
--- "<genTag>,<specTag>,<shape>" ("-" for a missing part), or nil when nothing in it says where the name comes from.
function M.originCode(info)
	if type(info) ~= "table" then return nil end
	local code = tagWord(info.genTag) .. "," .. tagWord(info.specTag) .. "," .. tagWord(info.shape)
	if M.originOf(code) == nil then return nil end
	return code
end

--- The origin sentence id of a saved code, or nil: a character or industry name first, then the generic's tag, then the
--- stem's.
function M.originOf(code)
	if type(code) ~= "string" or #code > 48 then return nil end
	local g, s, shape = code:match("^([a-z_%-]+),([a-z_%-]+),([a-z_%-]+)$")
	if g == nil then return nil end
	if shape == "character" then return "character" end
	if shape == "industry" then return "industry" end
	return M.ORIGIN_OF_TAG[g] or M.ORIGIN_OF_TAG[s]
end

function M.originText(id)
	local T = {
		river = _("Named for the river it stands on."),
		brook = _("Named for a brook or spring nearby."),
		ford = _("Named for its river crossing."),
		bend = _("Named for the river bend it sits in."),
		confluence = _("Named for the meeting of two rivers."),
		mouth = _("Named for the river mouth by the sea."),
		lake = _("Named for the lake beside it."),
		coast = _("Named for its stretch of coast."),
		bay = _("Named for the bay it faces."),
		cape = _("Named for the headland or cliffs nearby."),
		island = _("Named for the island it stands on."),
		narrows = _("Named for the narrow strip of land or water nearby."),
		hill = _("Named for the hills it stands on."),
		mountain = _("Named for the mountains around it."),
		valley = _("Named for the valley it lies in."),
		falls = _("Named for the waterfall nearby."),
		marsh = _("Named for the marshland around it."),
		moor = _("Named for the open moor or heath around it."),
		forest = _("Named for the woods around it."),
		trees = _("Named for the trees that grow around it."),
		tropic = _("Named for its tropical surroundings."),
		arid = _("Named for the dry land around it."),
		field = _("Named for the open fields around it."),
		market = _("Named as a market town."),
		church = _("Named for its church."),
		north = _("Named for its place in the north of the map."),
		south = _("Named for its place in the south of the map."),
		east = _("Named for its place in the east of the map."),
		west = _("Named for its place in the west of the map."),
		central = _("Named for its place in the middle of the map."),
		upper = _("Named for lying upstream on its river."),
		lower = _("Named for lying downstream on its river."),
		old = _("Named as an old settlement."),
		new = _("Named as a new settlement."),
		character = _("Named for its special character."),
		industry = _("Named for the industry nearby."),
	}
	return T[id]
end

---------------------------------------------------------------------------
-- texts

function M.kindText(id)
	local T = {
		deep_forest = { _("Deep forest town"), _("Winds its streets between the trees and keeps its groves.") },
		hilltop = { _("Hilltop village"), _("Climbs its hill in tight, winding lanes.") },
		clifftop = { _("Clifftop town"), _("Runs in a strip along the top of its cliffs.") },
		harbour_cove = { _("Harbor cove"), _("Huddles densely around its sheltered harbor.") },
		waterfront = { _("Waterfront town"), _("Lines its shore with a long waterfront street.") },
		street_village = { _("Street village"), _("Grows along one main street through the country.") },
		company_town = { _("Company town"), _("Planned rows of streets beside its industry.") },
		garden_city = { _("Garden city"), _("Low houses on curving streets with green spaces between.") },
		island_town = { _("Island town"), _("Packs its streets onto its island.") },
		roundabout_town = { _("Roundabout town"), _("A planned new town that joins its streets with roundabouts.") },
		secluded = { _("Secluded town"), _("Far from the others, it grows in a style of its own.") },
		coastal = { _("Coast town"), _("Spreads along the waterline like a seaside resort.") },
	}
	local t = T[id]
	if t == nil then return nil end
	return t[1], t[2]
end

function M.formText(id)
	local T = {
		clustered = { _("Clustered"), _("Grows tight around its center.") },
		radiating = { _("Radiating"), _("Reaches out along the roads from its center.") },
		sprawling = { _("Sprawling"), _("Spreads out loosely, with meadows between.") },
		linear = { _("Long and narrow"), _("Stretches along one line, a valley or a road.") },
		wide = { _("Wide"), _("Grows broad and flat across its site.") },
		fingers = { _("Fingers"), _("Grows out in several long arms.") },
		shore = { _("Along the shore"), _("Follows the waterline in a strip.") },
	}
	local t = T[id]
	if t == nil then return nil end
	return t[1], t[2]
end

function M.styleText(id)
	local T = {
		NA_GRID = { _("North American grid"), _("Straight streets in a regular grid.") },
		NA_SUBURB = { _("Suburban"), _("Curving streets and cul-de-sacs around a grid.") },
		EU_ORGANIC = { _("Old European"), _("An irregular core with streets that bend and branch.") },
		EU_EXTENSION = { _("European extension"), _("Planned blocks added around an old core.") },
		MED_HILL = { _("Mediterranean hill town"), _("Lanes that follow the contours of the hill.") },
		MED_ENSANCHE = { _("Mediterranean blocks"), _("Even blocks on a planned grid.") },
		JP_DENSE = { _("Japanese dense"), _("Small, fine-grained blocks.") },
		NORDIC = { _("Nordic"), _("Loose streets that follow the land.") },
		SUPERBLOCK = { _("Superblocks"), _("Large blocks between wide main streets.") },
	}
	local t = T[id]
	if t == nil then return nil end
	return t[1], t[2]
end

function M.motifText(id)
	local T = {
		crescent = _("Crescent"),
		hill_road = _("Hillside road"),
		hill_climb = _("Street up the hill"),
		valley_fishbone = _("Valley fishbone"),
		harbour_crescent = _("Harbor front"),
		fishing_village = _("Fishing village"),
		ribbon_village = _("Ribbon village"),
		village_green = _("Village green"),
		crossroads_hamlet = _("Crossroads hamlet"),
		ring_road = _("Ring road"),
		station_quarter = _("Station quarter"),
		workers_terraces = _("Workers' terraces"),
		culdesac_pods = _("Cul-de-sacs"),
		switchbacks = _("Switchbacks"),
		ridge_street = _("Ridge street"),
		headland_street = _("Headland street"),
		bridgehead_quarter = _("Bridgehead quarter"),
		peninsula_tip = _("Peninsula tip"),
	}
	return T[id]
end

function M.phaseText(id)
	local T = {
		young = { _("Young"), _("Low houses spread out; new streets lead the growth.") },
		blend = { _("Growing up"), _("Taller buildings start to mix in.") },
		mature = { _("Mature"), _("Builds as high as the era allows.") },
		densify = { _("Densifying"), _("Its center builds up into a dense core.") },
		early = { _("Dense from the start"), _("Its site makes it build up early.") },
		low = { _("Stays low"), _("Its character keeps the buildings low.") },
	}
	local t = T[id]
	if t == nil then return nil end
	return t[1], t[2]
end

local function districtName(k)
	if k == 1 then return _("Residential") end
	if k == 2 then return _("Commercial") end
	return _("Industrial")
end

local function pullText(k)
	if k == 1 then return _("Deliveries are pulling this town toward homes.") end
	if k == 2 then return _("Deliveries are pulling this town toward shops and offices.") end
	return _("Deliveries are pulling this town toward industry.")
end

local function leanText(id)
	if id == "res" then return _("It leans residential.") end
	if id == "com" then return _("It leans commercial.") end
	if id == "ind" then return _("It leans industrial.") end
	return nil
end

---------------------------------------------------------------------------
-- the view

local function shares3(v)
	if type(v) ~= "table" then return nil end
	local a, b, c = num(v[1]), num(v[2]), num(v[3])
	if not (a and b and c) or a < 0 or b < 0 or c < 0 then return nil end
	local s = a + b + c
	if s <= 0 then return nil end
	return { a / s, b / s, c / s }
end

local function vec3(v, scale)
	if type(v) ~= "table" then return nil end
	local a, b, c = num(v[1]), num(v[2]), num(v[3])
	if not (a and b and c) then return nil end
	scale = scale or 1
	return { a * scale, b * scale, c * scale }
end

--- The value text of a district row: "41% → 45%" (built now → aim; reads both ways), "45%, on its aim" when they
--- round to the same percent.
function M.aimText(built, aim)
	local a, b = pct(built), pct(aim)
	if a == b then return string.format(_("%d%%, on its aim"), a) end
	return string.format(_("%d%% → %d%%"), a, b)
end

--- The "Delivery weighting" factor of the input (ot_params deliveryWeight; nil: the param's default, as the driver's
--- Driver:rciWeight), so the card's aim is the driver's (ot_rci.weightedAim).
function M.rciWeight(input)
	local f = type(input) == "table" and tonumber(input.rciWeight) or nil
	if f == nil then f = PA.KEYS.delivery_weighting.values[PA.KEYS.delivery_weighting.default] end
	return f
end

--- Section 1. input fields: rciOn, rc = { e = {3} x 1000 } or nil, supply = the live supply read (ot_rci.usage's sd,
--- used until the town's first written step) or nil, init, sf, uses ({3}), rciWeight (M.rciWeight).
function M.rciSection(input)
	local lines = {}
	if not input.rciOn then
		lines[1] = { kind = "hint", text = _("Off in the mod settings: the game evens out this town's mix.") }
		return { title = _("Growth by deliveries"), lines = lines }
	end
	local built = shares3(input.uses)
	local target = RCI.shares(input.init, input.sf)
	local e = (type(input.rc) == "table" and vec3(input.rc.e, 1 / 1000)) or RCI.usage(input.supply)
	local aim = e and RCI.weightedAim(e, M.rciWeight(input)) or nil
	if built == nil or aim == nil then
		lines[1] = { kind = "hint", text = _("No deliveries yet: this town grows the game's way for now.") }
		return { title = _("Growth by deliveries"), lines = lines }
	end
	-- (a visible legend first; then per district a key / value row "41% → 45%" and a thin bar in the district's color
	-- with the built share filled and the aim as the base threshold mark on it: a mark reads above or below the fill)
	lines[1] = { kind = "note", text = _("Share built now → the aim its deliveries set.") }
	local tip = _("The share built now. The mark on the bar\nis the aim from deliveries.")
	for k = 1, 3 do
		lines[#lines + 1] = { kind = "row", key = districtName(k), value = M.aimText(built[k], aim[k]), tip = tip }
		lines[#lines + 1] = { kind = "bar", value = clamp(built[k], 0, 1), mark = clamp(aim[k], 0, 1),
			color = M.DISTRICT_COLORS[k], tip = tip }
	end
	local ref = target or built
	local bestK, best = nil, M.PULL_MIN
	for k = 1, 3 do
		local d = aim[k] - ref[k]
		if d >= best then bestK, best = k, d end
	end
	if bestK then
		lines[#lines + 1] = { kind = "text", text = pullText(bestK) }
	else
		lines[#lines + 1] = { kind = "text", text = _("Its mix already matches its deliveries.") }
	end
	local lt = leanText(target and RCI.lean(target) or nil)
	if lt then lines[#lines + 1] = { kind = "text", text = lt } end
	return { title = _("Growth by deliveries"), lines = lines }
end

--- The motif ids of a saved `mo` value (ot_motif.decode).
function M.motifs(v)
	v = num(v)
	if v == nil or v <= 0 or v ~= math.floor(v) then return {} end
	local out = {}
	for _i = 1, M.MOTIF_MAX do
		if v <= 0 then break end
		local i = math.floor(v % M.MOTIF_BASE)
		v = math.floor(v / M.MOTIF_BASE)
		if M.MOTIF_IDS[i] then out[#out + 1] = M.MOTIF_IDS[i] end
	end
	return out
end

--- The town's kind id (strong kind, deep forest, secluded, coastal) from its saved frame, or nil.
function M.kindOf(fr)
	if type(fr) ~= "table" then return nil end
	local ck = num(fr.ck)
	if ck and M.KIND_IDS[ck] then return M.KIND_IDS[ck] end
	if num(fr.fd) == 1 then return "deep_forest" end
	if num(fr.ch) == 1 then return "secluded" end
	if num(fr.cs) == 1 then return "coastal" end
	return nil
end

--- The street style row's model (2026-10-21): the town's own style (`auto`: the "Town style" setting's forced grid,
--- input.forcedStyle, else the saved site / character style `st`, else unknown), the player's pick (`ps`, or the pick
--- just sent and not read back yet, input.pendingStyle: 0 = Automatic), the style in effect (the pick, else auto) and,
--- when the player may pick (input.stylePick: the mod acts on this town, not in the map editor), the dropdown's options:
--- "0" = Automatic (named after the town's own style when known: choosing it clears the pick), then "1".."9" =
--- STYLE_IDS with their names and descriptions as the items' tooltips. selected = the pick's value, else "0".
--- tip = the row's tooltip (wrapped with \n: the game never wraps a tooltip).
function M.stylePick(input)
	local fr = type(input) == "table" and input.frame or nil
	local out = {}
	if type(fr) ~= "table" then return out end
	local si = num(fr.st)
	local auto = (type(input.forcedStyle) == "string" and M.styleText(input.forcedStyle) and input.forcedStyle)
		or (si and M.STYLE_IDS[si]) or nil
	local pi = num(fr.ps)
	if num(input.pendingStyle) ~= nil then pi = num(input.pendingStyle) end
	local picked = pi and pi >= 1 and M.STYLE_IDS[math.floor(pi)] or nil
	out.auto, out.picked = auto, picked
	out.effective = picked or auto
	out.desc = out.effective and select(2, M.styleText(out.effective)) or nil
	if not input.stylePick or input.mapEditor then return out end
	out.tip = _("The street style for this town's new streets.\nStreets already built stay as they are.")
	local an = auto and M.styleText(auto) or nil
	local opts = { { value = "0", text = an and M.fmt(_("Automatic ({style})"), { style = an }) or _("Automatic"),
		tip = _("The town's own street style, from its site\nor the mod settings.") } }
	for i, id in ipairs(M.STYLE_IDS) do
		local n, d = M.styleText(id)
		opts[#opts + 1] = { value = tostring(i), text = n, tip = d }
	end
	out.options = opts
	out.selected = picked and tostring(math.floor(pi)) or "0"
	return out
end

--- Section 2 from the saved frame (input.frame), or nil when there is none. The header shows the kind, or the form
--- when there is no kind: that one has no row of its own here (its description opens the section instead). Every
--- entry with a description shows it visibly under its row (a note) and keeps it as the row's tooltip.
function M.characterSection(input)
	local fr = input.frame
	if type(fr) ~= "table" then return nil end
	local lines = {}
	local kind = M.kindOf(fr)
	local kn, kd = M.kindText(kind)
	local fi = num(fr.f)
	local fn, fd = M.formText(fi and M.FORM_IDS[fi] or nil)
	local function entry(key, value, desc)
		lines[#lines + 1] = { kind = "row", key = key, value = value, tip = desc }
		if desc then lines[#lines + 1] = { kind = "note", text = desc } end
	end
	if kn then
		entry(_("Town type"), kn, kd)
		if fn then entry(_("Form"), fn, fd) end
	elseif fn and fd then
		lines[#lines + 1] = { kind = "note", text = fd }
	end
	local pick = M.stylePick(input)
	if pick.options then
		-- (a town the mod manages: the street style as a dropdown, ot_card.script.tl; its description follows the selection)
		lines[#lines + 1] = { kind = "style", key = _("Streets"), options = pick.options, selected = pick.selected,
			tip = pick.tip, town = input.town, from = pick.effective }
		if pick.desc then lines[#lines + 1] = { kind = "note", text = pick.desc } end
	else
		local sn, sd = M.styleText(pick.effective)
		if sn then entry(_("Streets"), sn, sd) end
	end
	local names = {}
	for _i, id in ipairs(M.motifs(fr.mo)) do
		local t = M.motifText(id)
		if t then names[#names + 1] = t end
	end
	if #names > 0 then
		lines[#lines + 1] = { kind = "row", key = _("Features"), value = table.concat(names, ", ") }
	end
	if #lines == 0 then
		lines[1] = { kind = "text", text = _("An ordinary town of its region.") }
	end
	return { title = _("Character"), lines = lines, headline = kn or fn }
end

--- Section 3 from the summary (input.ui) and the frame's densify / kind; nil when the town has no frame. The phase's
--- name is in the header: here its description, and toward the next phase (where one follows) a row "Next: <phase>"
--- with the percentage and a thin bar (the Town Level card's progress, town_eow.script.tl:88-96).
function M.phaseSection(input)
	if type(input.frame) ~= "table" and input.ui == nil then return nil end
	local sm = M.parseSummary(input.ui)
	if sm == nil then
		-- (the driver measures phases only on a new map, `fresh`: an older save's towns show no phase)
		if not (input.fresh and type(input.frame) == "table") then return nil end
		return { title = _("Growth phase"), lines = { { kind = "hint", text = _("Not measured yet.") } } }
	end
	local name, desc = M.phaseText(sm.phase)
	local lines = { { kind = "text", text = desc } }
	local fr = type(input.frame) == "table" and input.frame or {}
	local dz = num(fr.dz) == 1
	local nextId, p = M.phaseProgress(sm.phase, sm.mat, input.early and "early" or dz)
	if nextId then
		local nextName = M.phaseText(nextId)
		local tip = string.format(_("%d%% of the way to the next phase"), pct(p))
		lines[#lines + 1] = { kind = "row", key = M.fmt(_("Next: {phase}"), { phase = nextName }),
			value = string.format("%d%%", pct(p)), tip = tip }
		lines[#lines + 1] = { kind = "bar", value = p, color = "growth", tip = tip }
	end
	return { title = _("Growth phase"), lines = lines, headline = name }
end

--- The town's family from the saved offshoot lists: { parent = id or nil, kind = "district" | "works" (this town's own,
--- when it is an offshoot), children = { { t, kind } } } (input.offs = { { t, p, kind } }, at most MAX_OFFS read).
function M.family(offs, town)
	local out = { children = {} }
	if type(offs) ~= "table" then return out end
	local seen = {}
	for i = 1, math.min(#offs, M.MAX_OFFS) do
		local e = offs[i]
		local t, p = type(e) == "table" and num(e.t) or nil, type(e) == "table" and num(e.p) or nil
		local kind = type(e) == "table" and (e.kind == "works" and "works" or "district") or nil
		if t and t == town and p and p >= 0 then
			out.parent, out.kind = p, kind
		elseif t and p == town and not seen[t] then
			seen[t] = true
			out.children[#out.children + 1] = { t = t, kind = kind }
		end
	end
	return out
end

--- Section 4. input: town, offs, names = { [id] = name } (only towns that still exist), ui, satellitesOn, noOffshoots
--- (the kind founds none). nil when the town has neither a frame nor family.
function M.familySection(input)
	local fam = M.family(input.offs, input.town)
	local names = type(input.names) == "table" and input.names or {}
	local lines = {}
	if fam.parent and names[fam.parent] then
		lines[#lines + 1] = { kind = "text", text = fam.kind == "works" and _("An industrial Works town, founded by:")
			or _("A residential district, founded by:") }
		lines[#lines + 1] = { kind = "towns", towns = { { id = fam.parent, name = names[fam.parent] } } }
	end
	local kids = {}
	for _i, c in ipairs(fam.children) do
		if names[c.t] and #kids < M.MAX_TOWN_BUTTONS then kids[#kids + 1] = { id = c.t, name = names[c.t] } end
	end
	if #kids > 0 then
		lines[#lines + 1] = { kind = "text", text = _("Its offshoots:") }
		lines[#lines + 1] = { kind = "towns", towns = kids }
	end
	if fam.parent == nil and type(input.frame) == "table" then
		if not input.satellitesOn then
			lines[#lines + 1] = { kind = "hint", text = _("Satellite towns are off in the mod settings.") }
		elseif input.noOffshoots then
			lines[#lines + 1] = { kind = "hint", text = _("Its character keeps it one place: no offshoots.") }
		else
			local sm = M.parseSummary(input.ui)
			if sm and sm.ready ~= nil then
				if sm.ready >= 1 then
					lines[#lines + 1] = { kind = "text", text = _("Ready for an offshoot when the map has room for one.") }
				else
					lines[#lines + 1] = { kind = "text", text = string.format(_("Not ready for an offshoot yet: %d%% of the way."),
						pct(sm.ready)) }
				end
			elseif #kids == 0 then
				lines[#lines + 1] = { kind = "hint", text = _("No offshoots yet.") }
			end
		end
	end
	if #lines == 0 then return nil end
	return { title = _("Family"), lines = lines }
end

--- Section 5 from the saved origin code (input.origin), or nil.
function M.originSection(input)
	local id = M.originOf(input.origin)
	local t = id and M.originText(id) or nil
	if t == nil then return nil end
	return { title = _("Name origin"), lines = { { kind = "text", text = t } } }
end

--- The extra gap (px) before a section line of kind `kind` that follows one of kind `prev` (nil: the first line,
--- under the headline): every bar, note, hint and town row ends its group; a row's bar sits just under it, a row's
--- note (its description) directly under it, plain rows of a list a little apart.
function M.gapBefore(prev, kind)
	-- (the street style dropdown row spaces as a row)
	if prev == "style" then prev = "row" end
	if kind == "style" then kind = "row" end
	if prev == nil then return M.GAP_HEAD end
	if kind == "bar" then return M.GAP_IN end
	if kind == "note" and prev == "row" then return 0 end
	if prev == "row" and kind == "row" then return M.GAP_IN end
	if prev == "text" and kind == "towns" then return M.GAP_IN end
	return M.GAP
end

--- Does the input carry anything of the mod's for this town (a frame, a weighting, a summary, a name origin, family)?
function M.hasData(input)
	if type(input) ~= "table" then return false end
	if type(input.frame) == "table" or type(input.rc) == "table" or input.ui ~= nil or input.origin ~= nil then return true end
	local fam = M.family(input.offs, input.town)
	return fam.parent ~= nil or #fam.children > 0
end

--- The card's display model: { hidden = bool, summary = header text (left), summaryValue = header value (right) or
--- nil, sections = { { title, lines } } }. Lines: { kind = "row", key, value or nil, tip or nil } (key left, value
--- right), { kind = "bar", value (0..1), mark (0..1, the aim: the base threshold mark) or nil, color (a DISTRICT_COLORS
--- id or "growth"), tip }, { kind = "text", text } (body), { kind = "note", text } (a description under its row, the
--- smaller annotation font), { kind = "hint", text } (an explanation / empty state: the base info hint),
--- { kind = "towns", towns = { { id, name } } }, { kind = "style", key, options = { { value, text, tip } }, selected =
--- an option's value, tip, town, from = the style in effect (an id or nil) } (key left, a dropdown right; M.stylePick).
function M.view(input)
	if type(input) ~= "table" or input.mapEditor or not M.hasData(input) then return { hidden = true, sections = {} } end
	local out = { hidden = false, sections = {} }
	local function add(s) if s then out.sections[#out.sections + 1] = s end end
	-- (the kind's offshoot and level rules, from the saved frame; a shallow copy, the poll's table stays as read)
	local kind = M.kindOf(input.frame)
	local inp = {}
	for k, v in pairs(input) do inp[k] = v end
	inp.noOffshoots = kind ~= nil and M.NO_OFFSHOOTS[kind] == true
	inp.early = kind ~= nil and M.EARLY_KINDS[kind] == true
	input = inp
	local ch = M.characterSection(input)
	local ph = M.phaseSection(input)
	add(M.rciSection(input))
	add(ch)
	add(ph)
	add(M.familySection(input))
	add(M.originSection(input))
	-- (the header row: the character left, the phase right, as the base Line "Transported" card's key / value row, so
	-- the card's collapse triangle sits under the right-hand value as in the base cards)
	out.summary = (ch and ch.headline) or (ph and ph.headline) or _("Shaped by Organic Towns")
	out.summaryValue = (ch and ch.headline and ph and ph.headline) or nil
	return out
end

--- One log line's fields for the card's first read of a town: "frame=1 rc=0 ui=1:8:- origin=bend,river,frame offs=2".
function M.logText(input)
	if type(input) ~= "table" then return "-" end
	local fam = M.family(input.offs, input.town)
	return string.format("frame=%d rc=%d ui=%s origin=%s parent=%s offshoots=%d rciOn=%s", type(input.frame) == "table" and 1 or 0,
		type(input.rc) == "table" and 1 or 0, tostring(input.ui or "-"), tostring(input.origin or "-"),
		tostring(fam.parent or "-"), #fam.children, tostring(input.rciOn == true))
end

---------------------------------------------------------------------------
-- the new-town notification

--- Should the driver post the notification for a town it just claimed? Not when it already did this session (sent =
--- { [id] = true }) or when the saved state already holds the town as an offshoot (claimed in an earlier session: a
--- reload or a second driver never posts twice).
function M.shouldNotify(saved, sent, town)
	town = num(town)
	if town == nil then return false end
	if type(sent) == "table" and sent[town] then return false end
	if type(saved) == "table" then
		for _i, key in ipairs({ "dk", "wm" }) do
			local list = saved[key]
			if type(list) == "table" then
				for i = 1, math.min(#list, M.MAX_OFFS) do
					local e = list[i]
					if type(e) == "table" and num(e.t) == town then return false end
				end
			end
		end
		if type(saved.wk) == "table" then
			for i = 1, math.min(#saved.wk, M.MAX_OFFS) do
				if num(saved.wk[i]) == town then return false end
			end
		end
	end
	return true
end

--- The notification's params (plain data): { town, parent, kind = "district" | "works", name, parentName, rev }.
function M.noteParams(town, parent, kind, name, parentName, rev)
	return { town = math.floor(tonumber(town) or -1), parent = math.floor(tonumber(parent) or -1),
		kind = kind == "works" and "works" or "district",
		name = type(name) == "string" and name:sub(1, 64) or "", parentName = type(parentName) == "string" and parentName:sub(1, 64) or "",
		rev = num(rev) }
end

--- The notification's title and description (names: the current ones when the towns still exist, else the sent ones).
function M.noteText(p, name, parentName)
	p = type(p) == "table" and p or {}
	local vars = { town = name or p.name or "", parent = parentName or p.parentName or "" }
	if p.kind == "works" then
		return M.fmt(_("New Works town: {town}"), vars),
			M.fmt(_("{parent} has grown an industrial Works town by its industry: {town}."), vars)
	end
	return M.fmt(_("New district: {town}"), vars), M.fmt(_("{parent} has grown a new residential district nearby: {town}."), vars)
end

return M
