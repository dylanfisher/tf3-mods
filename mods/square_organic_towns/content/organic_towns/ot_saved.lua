-- Organic Towns: the per-save game-script state (pure). PLAN.md section 5: lazily initialised, tiny, and
-- nothing in the world depends on it (removing the mod leaves plain town streets).
--
-- state = { v = 1,
--           known = { townId, ... } | nil   towns present when the mod first saw this save ("New towns only"
--                                           leaves them alone); empty on a fresh map; nil until initialised
--           fresh = bool                    the first sight was a fresh map (log only)
--           nm = 1 | nil                    landscape names done on this map (ot_names; never run twice)
--           nd = "<dir>" | nil              the name list's language folder the names phase found (stop names reuse it)
--           rv = { { n, s, x, y, k } } | nil   generated names (ot_placename, 2026-10-14): the named rivers ("r") and lakes
--                                           ("l") at their towns (n = the name, s = the stem stop names use when it
--                                           differs, x / y = the town, rounded); at most WATER_CAP
--           sq = { { st, g, n, x, y, t } }  new player Road Stops waiting for a landscape stop name (ot_names stop part:
--                                           station, its group, the group's name at the build, position, os.time());
--                                           written by handleEvent (onPostBuildProposal), drained by the driver's
--                                           "stops" events; at most STOP_CAP
--           frames = { ["<townId>"] = { a = axis rad, x, y, s = shape index (ot_shape.IDS) or nil,
--                      sa = shape axis rad or nil, st = style index (ot_style.IDS) or nil,
--                      ic = the town's initial land use capacity sum at that build or nil (the fill's brake:
--                      makeTownDevelopAtCmd raises it, ot_driver FILL_CAP),
--                      f = town form index (ot_form.IDS) or nil (frames from before forms: no form),
--                      sx, sy = the town's satellite village site or nil (ot_satellite, 2026-10-13),
--                      ch = 1 for a character town (ot_map / ot_form CHARACTER, 2026-10-13) or nil,
--                      br = 1 once the town built its river bridge (ot_bridge, 2026-10-13) or nil,
--                      gl = the grid look the town's plan was made with (ot_grid, 2026-10-13) or nil,
--                      mo = the town's drawn motifs (ot_motif.encode: indices into ot_motif.IDS, 2026-10-13 M0) or
--                           nil (frames from before motifs, or none drawn: no motifs),
--                      rr = the ring road's radius (m, ot_motif_town, M3) or nil,
--                      ld = 1 once the town laid its country lane ahead (ot_lead, 2026-10-13) or nil,
--                      lw = the level-weight strength the mod set on the town x 4 (1..4; ot_upward.levelDecide,
--                           2026-10-14 late; from 2026-10-15 the tilt x 4, -4..4 without 0: below 0 a hold toward
--                           level 1) or nil (the game's default, or a player's own weights: never touched),
--                      ls = the sig (ot_upward.levelSig) of the level weights the mod last sent (2026-10-15, LEVELS by
--                           maturity; the era makes rows of one tilt differ) or nil,
--                      fd = 1 for a deep forest town (ot_forest deepPick, 2026-10-14) or nil,
--                      b0 = the town's offshoot size (ot_driver offshootSize) at that first build, its starting size
--                           for the offshoots' readiness (ot_satpace, 2026-10-14) or nil (frames from before),
--                      ck = the town's strong character kind (index into ot_character.IDS, 2026-10-14) or nil (none;
--                           frames from before: none),
--                      dz = the densify trait (ot_character, 2026-10-14): 1 densify, 2 drawn and not; nil not drawn yet,
--                      og = 1 when the town's plan has the organic ring geometry (wobbling rings, ot_style
--                           ORGANIC_RINGS, 2026-10-14 §56) or nil (frames from before: the old even rings stay),
--                      px, py, ph, pr, pn = a deferred roundabout pair (ot_ring, 2026-10-14 §56): the first ring's
--                           centre, the street's heading (rad), its radius and the plans left, or nil (none);
--                      sk = the town's landscape-aware skeleton (ot_skeleton, §63, 2026-10-15): its arms as
--                           "<heading deg x 10>:<reach x 100>:<cap m>" joined by ";", decided before its first build
--                           (at most SKEL_MAX chars) or nil (frames from before, or no arms to steer: the arms as the
--                           shape draws them);
--                      lm = 1 when the town's streets get the §65 lock (ot_driver LOCK_DEFAULT "mod": every street
--                           the mod builds locked, 2026-10-15), 2 the §69 steering lock (ot_lockpol: many streets locked,
--                           chiefly early and where direction matters, the branches' tips open; 2026-10-15) or nil
--                           (frames from before §65, or the legacy lock: the shape lock as before),
--                      e0 = the town's street edges that were not the mod's at its first build (its core, §65: the
--                           game-built edge count is the rest) or nil (frames from before),
--                      gk = 1 when the game's own streets in the town are locked too (§67, ot_glock: its houseless
--                           game / core streets rebuilt locked, valves left open) or nil (frames from before §67: the
--                           §65 lock only),
--                      dv = 2 when the town's seeded decisions use ot_rng.decide's well-mixed draw (§68, 2026-10-15)
--                           or nil (frames from before §68: the re-derived picks keep rng.unit, as they were made),
--                      fy = the game year x 100 of the town's first frame (§70, 2026-10-15: the lock maturity's age,
--                           ot_lockpol.maturity) or nil (frames from before §70: no age part),
--                      pk = the deferred pair's kind (2026-10-14 §57, the roundabout town's hubs): 2 across the town
--                           ("opposite"), 1 a hub's twin along its street (both ways), nil an older street twin
--                           (outward only) } }
--           cm = { p = { { t = townId, k = kind index } } } | nil   the map's strong characters (ot_character.select,
--                                           2026-10-14), saved once when the map's pick ran (an empty p: none picked);
--                                           nil: a save from before (no strong characters on that map)
--           sp = { m, y, n, y0, h } | nil   the offshoots' map-wide pacing (ot_satpace, 2026-10-14): m = the map's size
--                                           (persons / 4) at the last founding, y = its game year x 100, n = foundings,
--                                           y0 = the game year x 100 of the first, h = their elapsed years (at most
--                                           PACE_HIST); nil (a save from before): counted from the towns' starting sizes
--           lb = { ["<townId>"] = "<weights>" | "-" }  the towns' level-to-capacity weights when the mod first saw this
--                                           new map (2026-10-14, ot_upward.levelSig: "-" none, else 12 numbers): the
--                                           engine's own baseline (generated towns carry custom weights the mod never
--                                           sent, findings towns.md); weights that differ from it later and aren't ours
--                                           are the player's. nil (a save from before, or an old map): any custom
--                                           weights count as the player's
--           lbs = 1 | nil                   the baseline was taken (even when no town had weights)
--           sb = { { b, x, y, h } }              stop names that are the base of their street section (ot_stopname sections,
--                                           2026-10-14): later stops on the section take variants; at most STOPBASE_CAP
--           dk = { { t = townId, p = parentId, x, y } }  district towns the mod created (ot_district, 2026-10-14; x, y =
--                                           the site, from 2026-10-14 late: entries before have none); frames: dp = how
--                                           many the parent founded, cs = 1 for a coastal hugger (ot_form COASTAL)
--           wm = { { t = townId, p = parentId, x, y } }  the Works towns' parent and site (2026-10-14 late; `wk` stays
--                                           the plain id list): the load check (M.offshootCheck) drops entries whose
--                                           town is not where its record says (the created-town race of run
--                                           2026-10-14_0119_sqot claimed other parents' towns)
--           rc = { ["<townId>"] = { e = { r, c, i }, s, y, n0, k } } | nil   the supply-driven district weighting ("Town
--                                           growth: By deliveries", ot_rci, §66, 2026-10-15): e = the smoothed usage x 1000,
--                                           s = the town's total target (persons) at its last step, y = that step's game
--                                           year x 100, n0 = its initial capacity sum when the weighting first wrote (the
--                                           ceiling's base), k = the steps written; at most RCI_CAP towns. nil (a save from
--                                           before, or the setting on Game default): no town weighted
--           gx = { ["<townId>"] = { edgeId, ... } } | nil   the game streets the mod rebuilt locked (§67, ot_glock): their
--                                           new edge ids, so a reload still tells them from the mod's own locked
--                                           streets; at most GX_TOWN_CAP per town (oldest dropped), GX_TOWNS towns
--           no = { ["<townId>"] = "<genTag>,<specTag>,<shape>" } | nil   why a town got its generated name (2026-10-17, the
--                                           town window's Organic Towns card, ot_card.originOf): the name parts' site tags
--                                           and the name's shape (ot_placename.nameTown info), saved once with the names
--                                           event; at most ORIGIN_CAP towns, each at most ORIGIN_MAX chars. nil (a save
--                                           from before, or Game names): no name origin shown
--           ui = { ["<townId>"] = "<phase>:<maturity>:<readiness>" } | nil   the card's per-town summary (2026-10-17,
--                                           ot_card.summary): the growth phase index (ot_card.PHASES), the level maturity
--                                           and the offshoot readiness in twentieths ("-" unknown), written in batches by
--                                           the driver (EV_UI) only when a value moved; at most UI_CAP towns
--           pv = "<entries>" | nil          street provenance (§75 follow-up, 2026-10-19; one string 2026-10-20, ot_prov):
--                                           the street edges the mod built, "<town>,<edge>,<src>,<trig>,<year>,<x0>,<y0>,
--                                           <dx>,<dy>,<mx>,<my>" joined by ";", oldest first; at most ot_prov.TOWN_N a
--                                           town and ot_prov.TOTAL_MAX chars in all (the oldest go first). One string, as
--                                           guiUpdate copies the whole state (every frame until 2026-10-20, now on a
--                                           change: M.Reader). Read by the console lookup
--                                           (ot_prov.who). nil: a save from before (no record, no work)
--           rev = n | nil                   the state's change number (2026-10-20, M.Reader): handleEvent bumps it with every
--                                           state:set (M.bumpRev), so guiUpdate copies the whole state only when it moved
--                                           (read from the GAME_SCRIPT component's state_native). nil: a save from before
--                                           (or no change since): the first change writes 1
--           wk = { townId, ... }                 industrial satellite towns ("Works") the mod created (ot_works,
--                                           2026-10-13): never a second one for their parent, the map quota
--                                           plan frame (and town shape, street style) fixed at the town's first
--                                           increment, so its grid never turns or shifts later (string keys:
--                                           sparse integer keys don't survive the save's table conversion) }
--
-- Writes happen only in the game script's handleEvent (engine side) on events the driver sends from
-- guiUpdate (and on the game's onPostBuildProposal for new player Road Stops: addStops) (makeScriptingSendEventCmd, the square_problem_radar / square_supply_gaps pattern). Every apply
-- is idempotent: handleEvent may run in more than one simulation Lua state (docs/findings.md).

local SH = ug_require "square_organic_towns::/organic_towns/ot_shape.lua"
local FM = ug_require "square_organic_towns::/organic_towns/ot_form.lua"
local MO = ug_require "square_organic_towns::/organic_towns/ot_motif.lua"
local PV = ug_require "square_organic_towns::/organic_towns/ot_prov.lua"

local M = {}

M.VERSION = 1
-- style index -> id for saved frames (same order as ot_style.IDS; ot_style can't be required here: it requires
-- ot_shape, kept light). Append only.
M.STYLE_IDS = { "NA_GRID", "NA_SUBURB", "EU_ORGANIC", "EU_EXTENSION", "MED_HILL", "MED_ENSANCHE", "JP_DENSE", "NORDIC",
	"SUPERBLOCK" }
M.EVENT_ID = "square_organic_towns"
M.EV_INIT = "square_organic_towns.init"
M.EV_FRAME = "square_organic_towns.frame"
M.EV_SAT = "square_organic_towns.sat"
M.EV_BRIDGE = "square_organic_towns.bridge"
M.EV_NAMES = "square_organic_towns.names"
M.EV_STOPS = "square_organic_towns.stops"
M.EV_LEAD = "square_organic_towns.lead"
M.EV_WORKS = "square_organic_towns.works"
M.EV_STOPBASE = "square_organic_towns.stopbase"
M.EV_LEVELS = "square_organic_towns.levels"
M.EV_LEVELBASE = "square_organic_towns.levelbase"
M.EV_PACE = "square_organic_towns.pace"
M.EV_CHARS = "square_organic_towns.chars"
M.EV_DENSE = "square_organic_towns.dense"
M.EV_PAIR = "square_organic_towns.pair"
M.EV_RCI = "square_organic_towns.rci"
M.EV_GLOCK = "square_organic_towns.glock"
M.EV_UI = "square_organic_towns.ui"
M.EV_PROV = "square_organic_towns.prov"
M.GX_TOWN_CAP = 800
M.GX_TOWNS = 4000
M.CHARS_CAP = 16
M.PACE_HIST = 64
M.LEVELBASE_MAX = 4000
M.LEVELSIG_MAX = 160
M.SKEL_MAX = 160          -- the frame's `sk` text at most this long (ot_skeleton.SAVE_MAX)
M.STOPBASE_CAP = 300
M.WORKS_CAP = 64
M.STOP_CAP = 64
M.WATER_CAP = 32
M.GS_NAME = "square_organic_towns::/organic_towns/organic_towns.gs"
M.MAX_FRAMES = 4000
M.MAX_KNOWN = 20000
M.RCI_CAP = 4000
M.ORIGIN_CAP = 4000
M.ORIGIN_MAX = 48
M.UI_CAP = 4000
M.UI_MAX = 16
M.UI_BATCH = 64           -- towns per summary event at most

-- a fresh map: the game clock has barely moved when the mod first looks (GAME_TIME.gameTime in ms)
M.FRESH_GAME_TIME = 120000
M.REV_KEY = "rev"          -- the change number's key (M.bumpRev, M.Reader)
M.REV_WRAP = 1000000000    -- it wraps to 1 past this (a whole number in any float)

local function isList(t)
	return type(t) == "table"
end

-- a finite number or nil (§70 `fy`; `finite` below is local to the later functions)
local function finiteNum(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end

--- The state's change number (`rev`): a whole number 1..REV_WRAP, or nil (none yet / not a state).
function M.revOf(raw)
	if type(raw) ~= "table" then return nil end
	local r = finiteNum(raw[M.REV_KEY])
	if r == nil or r < 1 or r > M.REV_WRAP or r ~= math.floor(r) then return nil end
	return r
end

--- Bumps s's change number (handleEvent, right before every state:set); returns s.
function M.bumpRev(s)
	if type(s) ~= "table" then return s end
	s[M.REV_KEY] = (M.revOf(s) or 0) % M.REV_WRAP + 1
	return s
end

--- A clean copy of a raw state (nil / foreign / older layouts -> an uninitialised v1 state).
function M.normalize(raw)
	local s = { v = M.VERSION, frames = {} }
	-- (the change number survives even a foreign layout, so the next bump never repeats a number a reader cached)
	s.rev = M.revOf(raw)
	if type(raw) ~= "table" or raw.v ~= M.VERSION then return s end
	if isList(raw.known) then
		s.known = {}
		for i = 1, math.min(#raw.known, M.MAX_KNOWN) do
			local id = tonumber(raw.known[i])
			if id then s.known[#s.known + 1] = id end
		end
	end
	s.fresh = raw.fresh == true
	if type(raw.wk) == "table" then
		s.wk = {}
		for i = 1, math.min(#raw.wk, M.WORKS_CAP) do
			local id = tonumber(raw.wk[i])
			if id then s.wk[#s.wk + 1] = id end
		end
	end
	if type(raw.dk) == "table" then
		s.dk = {}
		for i = 1, math.min(#raw.dk, M.WORKS_CAP) do
			local e = raw.dk[i]
			if type(e) == "table" and tonumber(e.t) then
				s.dk[#s.dk + 1] = { t = tonumber(e.t), p = tonumber(e.p) or -1, x = tonumber(e.x), y = tonumber(e.y) }
			end
		end
	end
	if type(raw.wm) == "table" then
		s.wm = {}
		for i = 1, math.min(#raw.wm, M.WORKS_CAP) do
			local e = raw.wm[i]
			if type(e) == "table" and tonumber(e.t) then
				s.wm[#s.wm + 1] = { t = tonumber(e.t), p = tonumber(e.p) or -1, x = tonumber(e.x), y = tonumber(e.y) }
			end
		end
	end
	if type(raw.sb) == "table" then
		s.sb = {}
		for i = 1, math.min(#raw.sb, M.STOPBASE_CAP) do
			local e = raw.sb[i]
			if type(e) == "table" and type(e.b) == "string" and #e.b <= 64 and tonumber(e.x) and tonumber(e.y) then
				s.sb[#s.sb + 1] = { b = e.b, x = tonumber(e.x), y = tonumber(e.y), h = tonumber(e.h) or 0 }
			end
		end
	end
	if tonumber(raw.lbs) == 1 then s.lbs = 1 end
	if type(raw.lb) == "table" then
		s.lb = {}
		local n = 0
		for k, v in pairs(raw.lb) do
			if n >= M.LEVELBASE_MAX then break end
			if tonumber(k) and type(v) == "string" and #v <= M.LEVELSIG_MAX then
				s.lb[tostring(k)] = v
				n = n + 1
			end
		end
	end
	s.rc = M.normRci(raw.rc)
	s.gx = M.normGlock(raw.gx)
	s.pv = PV.norm(raw.pv)
	s.sp = M.normPace(raw.sp)
	s.cm = M.normChars(raw.cm)
	if tonumber(raw.nm) == 1 then s.nm = 1 end
	if type(raw.nd) == "string" and #raw.nd <= 16 then s.nd = raw.nd end
	s.rv = M.normWaters(raw.rv)
	s.no = M.normOrigins(raw.no)
	s.ui = M.normUi(raw.ui)
	if type(raw.sq) == "table" then
		s.sq = {}
		for i = 1, math.min(#raw.sq, M.STOP_CAP) do
			local e = raw.sq[i]
			if type(e) == "table" and tonumber(e.st) then
				s.sq[#s.sq + 1] = { st = tonumber(e.st), g = tonumber(e.g) or -1, n = type(e.n) == "string" and e.n or nil,
					x = tonumber(e.x), y = tonumber(e.y), t = tonumber(e.t) or 0,
					k = (e.k == "rail" or e.k == "harbor" or e.k == "street") and e.k or nil }
			end
		end
	end
	if type(raw.frames) == "table" then
		for k, f in pairs(raw.frames) do
			if type(f) == "table" and tonumber(f.a) and tonumber(f.x) and tonumber(f.y) then
				s.frames[tostring(k)] = { a = tonumber(f.a), x = tonumber(f.x), y = tonumber(f.y), s = tonumber(f.s),
					sa = tonumber(f.sa), st = tonumber(f.st), ic = tonumber(f.ic), f = tonumber(f.f), sx = tonumber(f.sx),
					sy = tonumber(f.sy), ch = tonumber(f.ch), br = tonumber(f.br), gl = tonumber(f.gl), mo = tonumber(f.mo),
					rr = tonumber(f.rr), ld = tonumber(f.ld), wp = tonumber(f.wp), dp = tonumber(f.dp), cs = tonumber(f.cs),
					lw = tonumber(f.lw), ls = (type(f.ls) == "string" and #f.ls <= M.LEVELSIG_MAX) and f.ls or nil,
					fd = tonumber(f.fd), b0 = tonumber(f.b0), ck = tonumber(f.ck), dz = tonumber(f.dz),
					og = tonumber(f.og), px = tonumber(f.px), py = tonumber(f.py), ph = tonumber(f.ph), pr = tonumber(f.pr),
					pn = tonumber(f.pn), pk = tonumber(f.pk), lm = tonumber(f.lm), e0 = tonumber(f.e0),
					gk = tonumber(f.gk), dv = tonumber(f.dv), fy = finiteNum(f.fy),
					sk = (type(f.sk) == "string" and #f.sk <= M.SKEL_MAX) and f.sk or nil }
			end
		end
	end
	return s
end

function M.initialised(raw)
	return type(raw) == "table" and raw.v == M.VERSION and isList(raw.known)
end

--- The init event's param: fresh map -> no known towns (every town is styled), else every current town.
function M.initParam(townIds, gameTime)
	local fresh = (tonumber(gameTime) or 0) < M.FRESH_GAME_TIME
	local known = {}
	if not fresh then
		for i, t in ipairs(townIds) do
			if i > M.MAX_KNOWN then break end
			known[#known + 1] = t
		end
	end
	return { known = known, fresh = fresh }
end

--- handleEvent "init": returns the new state and whether it changed. Only the first init counts.
function M.applyInit(raw, param)
	local s = M.normalize(raw)
	if s.known ~= nil then return s, false end
	if type(param) ~= "table" or not isList(param.known) then return s, false end
	s.known = {}
	for i = 1, math.min(#param.known, M.MAX_KNOWN) do
		local id = tonumber(param.known[i])
		if id then s.known[#s.known + 1] = id end
	end
	s.fresh = param.fresh == true
	return s, true
end

--- handleEvent "frame" { town, a, x, y }: the first frame for a town wins (a second one is ignored).
function M.applyFrame(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" then return s, false end
	local town, a, x, y = tonumber(param.town), tonumber(param.a), tonumber(param.x), tonumber(param.y)
	if not (town and a and x and y) then return s, false end
	local k = tostring(town)
	if s.frames[k] then return s, false end
	local n = 0
	for _ in pairs(s.frames) do n = n + 1 end
	if n >= M.MAX_FRAMES then return s, false end
	s.frames[k] = { a = a, x = x, y = y, s = tonumber(param.s), sa = tonumber(param.sa), st = tonumber(param.st),
		ic = tonumber(param.ic), f = tonumber(param.f), ch = tonumber(param.ch), gl = tonumber(param.gl),
		mo = tonumber(param.mo), rr = tonumber(param.rr), cs = tonumber(param.cs), fd = tonumber(param.fd),
		b0 = tonumber(param.b0), ck = tonumber(param.ck), og = tonumber(param.og), lm = tonumber(param.lm),
		e0 = tonumber(param.e0), gk = tonumber(param.gk), dv = tonumber(param.dv),
		fy = finiteNum(param.fy),
		sk = (type(param.sk) == "string" and #param.sk <= M.SKEL_MAX) and param.sk or nil }
	return s, true
end

--- A clean copy of a saved / sent strong-character record (`cm`), or nil.
function M.normChars(c)
	if type(c) ~= "table" or type(c.p) ~= "table" then return nil end
	local out = { p = {} }
	for i = 1, math.min(#c.p, M.CHARS_CAP) do
		local e = c.p[i]
		if type(e) == "table" and tonumber(e.t) and tonumber(e.k) then
			out.p[#out.p + 1] = { t = math.floor(tonumber(e.t)), k = math.floor(tonumber(e.k)) }
		end
	end
	return out
end

--- handleEvent "chars" { p = { { t, k } } }: the map's strong characters, once (the first record wins; idempotent).
function M.applyChars(raw, param)
	local s = M.normalize(raw)
	if s.cm ~= nil then return s, false end
	local c = M.normChars(param)
	if c == nil then return s, false end
	s.cm = c
	return s, true
end

--- The saved strong characters: { [townId] = kind index } and true, or nil (none saved: a map from before).
function M.chars(raw)
	if type(raw) ~= "table" then return nil end
	local c = M.normChars(raw.cm)
	if c == nil then return nil end
	local out = {}
	for _, e in ipairs(c.p) do out[e.t] = e.k end
	return out, true
end

--- handleEvent "dense" { town, v = 1 | 2 }: the town's densify draw (on its frame; no frame: ignored; the first wins).
function M.applyDense(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" then return s, false end
	local town, v = tonumber(param.town), tonumber(param.v)
	if not town or (v ~= 1 and v ~= 2) then return s, false end
	local f = s.frames[tostring(town)]
	if f == nil or f.dz ~= nil then return s, false end
	f.dz = v
	return s, true
end

--- handleEvent "pair" { town, x, y, h, r, n, k }: the town's deferred roundabout pair (on its frame; no frame: ignored); n
--- <= 0 or no x clears it; k = 2 an "opposite" twin (§57).
function M.applyPair(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" then return s, false end
	local town = tonumber(param.town)
	if not town then return s, false end
	local f = s.frames[tostring(town)]
	if f == nil then return s, false end
	local x, y, h, r, n = tonumber(param.x), tonumber(param.y), tonumber(param.h), tonumber(param.r), tonumber(param.n)
	if x and y and h and r and n and n > 0 then
		f.px, f.py, f.ph, f.pr, f.pn = x, y, h, r, math.floor(n)
		f.pk = (tonumber(param.k) == 1 or tonumber(param.k) == 2) and tonumber(param.k) or nil
	else
		if f.px == nil and f.pn == nil then return s, false end
		f.px, f.py, f.ph, f.pr, f.pn, f.pk = nil, nil, nil, nil, nil, nil
	end
	return s, true
end

local function finite(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end

--- A clean copy of a saved / sent pacing record (`sp`), or nil.
function M.normPace(p)
	if type(p) ~= "table" then return nil end
	local out = { m = finite(p.m), y = finite(p.y), n = finite(p.n), y0 = finite(p.y0), h = {} }
	if out.n then out.n = math.max(0, math.floor(out.n)) end
	if type(p.h) == "table" then
		for i = 1, math.min(#p.h, M.PACE_HIST) do
			local v = finite(p.h[i])
			if v then out.h[#out.h + 1] = v end
		end
	end
	if out.m == nil and out.n == nil then return nil end
	return out
end

--- handleEvent "pace" { m, y, n, y0, h }: the offshoots' pacing record (ot_satpace) replaces the saved one (the
--- latest wins; a refund lowers n again). Idempotent.
function M.applyPace(raw, param)
	local s = M.normalize(raw)
	local p = M.normPace(param)
	if p == nil then return s, false end
	local o = s.sp
	if o and o.m == p.m and o.y == p.y and o.n == p.n and o.y0 == p.y0 and #o.h == #p.h then
		local same = true
		for i = 1, #p.h do if o.h[i] ~= p.h[i] then same = false end end
		if same then return s, false end
	end
	s.sp = p
	return s, true
end

--- handleEvent "sat" { town, x, y }: the town's satellite site on its frame (the first one wins; no frame: ignored).
function M.applySat(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" then return s, false end
	local town, x, y = tonumber(param.town), tonumber(param.x), tonumber(param.y)
	if not (town and x and y) then return s, false end
	local f = s.frames[tostring(town)]
	if f == nil or f.sx ~= nil then return s, false end
	f.sx, f.sy = x, y
	return s, true
end

--- handleEvent "bridge" { town }: the town built its river bridge (on its frame; no frame: ignored; idempotent).
function M.applyBridge(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" then return s, false end
	local town = tonumber(param.town)
	if not town then return s, false end
	local f = s.frames[tostring(town)]
	if f == nil or f.br ~= nil then return s, false end
	f.br = 1
	return s, true
end

--- handleEvent "lead" { town }: the town laid its country lane ahead (on its frame; no frame: ignored; idempotent).
function M.applyLead(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" then return s, false end
	local town = tonumber(param.town)
	if not town then return s, false end
	local f = s.frames[tostring(town)]
	if f == nil or f.ld ~= nil then return s, false end
	f.ld = 1
	return s, true
end

--- handleEvent "levels" { town, k4, sig }: the mod set the town's level weights at tilt k4 / 4 (-4..4 without 0; 1..4
--- before 2026-10-15), or cleared them (k4 = 0: back to the game's default, `lw` / `ls` removed); sig = the weights'
--- ot_upward.levelSig (`ls`, optional). On its frame; no frame: ignored; idempotent.
function M.applyLevels(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" then return s, false end
	local town, k4 = tonumber(param.town), tonumber(param.k4)
	if not town or not k4 then return s, false end
	local f = s.frames[tostring(town)]
	if f == nil then return s, false end
	k4 = math.floor(k4 + 0.5)
	local v = (k4 ~= 0 and k4 >= -4 and k4 <= 4) and k4 or nil
	local sig = (v ~= nil and type(param.sig) == "string" and #param.sig <= M.LEVELSIG_MAX) and param.sig or nil
	if f.lw == v and f.ls == sig then return s, false end
	f.lw, f.ls = v, sig
	return s, true
end

local function rciEntry(e)
	if type(e) ~= "table" then return nil end
	local s, y = tonumber(e.s), tonumber(e.y)
	if not (finite(s) and finite(y)) or s < 0 then return nil end
	local ev = nil
	if type(e.e) == "table" then
		local a, b, c = tonumber(e.e[1]), tonumber(e.e[2]), tonumber(e.e[3])
		if finite(a) and finite(b) and finite(c) then
			ev = { math.max(0, math.min(1000, math.floor(a + 0.5))), math.max(0, math.min(1000, math.floor(b + 0.5))),
				math.max(0, math.min(1000, math.floor(c + 0.5))) }
		end
	end
	if ev == nil then return nil end
	local n0, k = tonumber(e.n0), tonumber(e.k)
	return { e = ev, s = math.floor(s + 0.5), y = math.floor(y + 0.5),
		n0 = (finite(n0) and n0 > 0) and math.floor(n0 + 0.5) or nil, k = finite(k) and math.max(0, math.floor(k)) or 0 }
end

--- A clean copy of the saved weighting table (`rc`), or nil.
function M.normRci(raw)
	if type(raw) ~= "table" then return nil end
	local out, n = {}, 0
	for key, e in pairs(raw) do
		if n >= M.RCI_CAP then break end
		local t = tonumber(key)
		local v = t and rciEntry(e) or nil
		if v then
			out[tostring(math.floor(t))] = v
			n = n + 1
		end
	end
	return out
end

--- handleEvent "rci" { town, e = { r, c, i } (x 1000), s, y, n0, k }: a town's weighting state after a written step
--- (§66). The newest wins; n0 is kept from the first (a later event can't raise the ceiling's base). Idempotent.
function M.applyRci(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" then return s, false end
	local town = tonumber(param.town)
	local v = town and rciEntry(param) or nil
	if v == nil then return s, false end
	s.rc = s.rc or {}
	local key = tostring(math.floor(town))
	local old = s.rc[key]
	if old == nil then
		local n = 0
		for _ in pairs(s.rc) do n = n + 1 end
		if n >= M.RCI_CAP then return s, false end
	end
	if old and old.n0 then v.n0 = old.n0 end
	if old and old.s == v.s and old.y == v.y and old.k == v.k and old.n0 == v.n0 and old.e[1] == v.e[1]
		and old.e[2] == v.e[2] and old.e[3] == v.e[3] then return s, false end
	s.rc[key] = v
	return s, true
end

--- A clean copy of the saved game-street locks (`gx`, §67), or nil.
function M.normGlock(raw)
	if type(raw) ~= "table" then return nil end
	local out, n = {}, 0
	for key, list in pairs(raw) do
		if n >= M.GX_TOWNS then break end
		local t = tonumber(key)
		if t and type(list) == "table" then
			local l = {}
			for i = 1, math.min(#list, M.GX_TOWN_CAP) do
				local id = tonumber(list[i])
				if id then l[#l + 1] = math.floor(id) end
			end
			out[tostring(math.floor(t))] = l
			n = n + 1
		end
	end
	return out
end

--- handleEvent "glock" { town, ids = { edgeId } }: the game streets rebuilt locked in town (§67). Appends the new ids
--- (each once: idempotent), the oldest dropped past GX_TOWN_CAP.
function M.applyGlock(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" or type(param.ids) ~= "table" then return s, false end
	local town = tonumber(param.town)
	if town == nil then return s, false end
	s.gx = s.gx or {}
	local key = tostring(math.floor(town))
	local list = s.gx[key]
	if list == nil then
		local n = 0
		for _ in pairs(s.gx) do n = n + 1 end
		if n >= M.GX_TOWNS then return s, false end
		list = {}
	end
	local have = {}
	for _, id in ipairs(list) do have[id] = true end
	local changed = false
	for i = 1, math.min(#param.ids, M.GX_TOWN_CAP) do
		local id = tonumber(param.ids[i])
		if id and not have[math.floor(id)] then
			have[math.floor(id)] = true
			list[#list + 1] = math.floor(id)
			changed = true
		end
	end
	while #list > M.GX_TOWN_CAP do table.remove(list, 1) end
	if not changed then return s, false end
	s.gx[key] = list
	return s, true
end

--- handleEvent "prov" { town, add = { entry, ... } } (§75 follow-up, ot_prov): the street edges the mod built in town,
--- appended to the record (each edge once: idempotent), the oldest dropped past ot_prov.TOWN_N / TOTAL_MAX.
function M.applyProv(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" or type(param.add) ~= "table" then return s, false end
	local pv, changed = PV.add(s.pv, param.town, param.add)
	if not changed then return s, false end
	s.pv = pv
	return s, true
end

--- The saved game-street locks of town t: { [edgeId] = true } (empty without).
function M.glocked(raw, t)
	local out = {}
	if type(raw) ~= "table" or type(raw.gx) ~= "table" then return out end
	local list = raw.gx[tostring(t)]
	if type(list) ~= "table" then return out end
	for i = 1, math.min(#list, M.GX_TOWN_CAP) do
		local id = tonumber(list[i])
		if id then out[id] = true end
	end
	return out
end

--- The saved weighting of town t: { e = {3} (0..1), s, y (game year), n0, k } or nil.
function M.rci(raw, t)
	if type(raw) ~= "table" or type(raw.rc) ~= "table" then return nil end
	local v = rciEntry(raw.rc[tostring(t)])
	if v == nil then return nil end
	return { e = { v.e[1] / 1000, v.e[2] / 1000, v.e[3] / 1000 }, s = v.s, y = v.y / 100, n0 = v.n0, k = v.k }
end

--- handleEvent "levelbase" { towns = { { t = townId, c = "<weights>" | "-" } } }: the engine's level weights of every
--- town at the mod's first sight of a new map (`lb`, `lbs` = 1). Only the first event counts (idempotent): a town's
--- baseline never changes later.
function M.applyLevelBase(raw, param)
	local s = M.normalize(raw)
	if s.lbs == 1 then return s, false end
	if type(param) ~= "table" or type(param.towns) ~= "table" then return s, false end
	s.lbs = 1
	s.lb = {}
	local n = 0
	for _, e in ipairs(param.towns) do
		if n >= M.LEVELBASE_MAX then break end
		if type(e) == "table" and tonumber(e.t) and type(e.c) == "string" and #e.c <= M.LEVELSIG_MAX then
			s.lb[tostring(math.floor(tonumber(e.t)))] = e.c
			n = n + 1
		end
	end
	return s, true
end

--- The saved level baseline: { [townId] = sig } or nil (none taken on this map).
function M.levelBase(raw)
	local s = M.normalize(raw)
	if s.lbs ~= 1 then return nil end
	local out = {}
	for k, v in pairs(s.lb or {}) do out[tonumber(k)] = v end
	return out
end

--- handleEvent "works" { parent, town, kind, x, y }: the mod created the industrial satellite town `town` for `parent`
--- (the town id in `wk`, parent and site in `wm`, the parent's frame gets `wp`), or with kind = "district" a district town
--- (ot_district: `dk` with the site, the parent's frame counts them in `dp`); idempotent, at most WORKS_CAP each.
--- kind = "drop" (2026-10-14 late, the load check M.offshootCheck): `town` leaves `dk` / `wk` / `wm`, its parent's frame
--- loses the count / `wp`; the town stays an ordinary town.
function M.applyWorks(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" then return s, false end
	local parent, town = tonumber(param.parent), tonumber(param.town)
	if param.kind == "drop" then
		if not town then return s, false end
		local changed, wasD, wasW = false, nil, false
		local function strip(list, idOf)
			if list == nil then return nil end
			local keep = {}
			for _, e in ipairs(list) do
				if idOf(e) == town then changed = true else keep[#keep + 1] = e end
			end
			return keep
		end
		for _, e in ipairs(s.dk or {}) do if e.t == town then wasD = e.p end end
		for _, id in ipairs(s.wk or {}) do if id == town then wasW = true end end
		s.dk = strip(s.dk, function(e) return e.t end)
		s.wk = strip(s.wk, function(e) return e end)
		s.wm = strip(s.wm, function(e) return e.t end)
		if wasD then
			local f = s.frames[tostring(wasD)]
			if f and f.dp then f.dp = f.dp > 1 and f.dp - 1 or nil end
		end
		if wasW then
			for _, f in pairs(s.frames) do if f.wp == town then f.wp = nil end end
		end
		return s, changed
	end
	if not (parent and town) then return s, false end
	local district = param.kind == "district"
	for _, id in ipairs(s.wk or {}) do if id == town then return s, false end end
	for _, e in ipairs(s.dk or {}) do if e.t == town then return s, false end end
	local x, y = tonumber(param.x), tonumber(param.y)
	if x then x = math.floor(x + 0.5) end
	if y then y = math.floor(y + 0.5) end
	if district then
		s.dk = s.dk or {}
		if #s.dk >= M.WORKS_CAP then return s, false end
		s.dk[#s.dk + 1] = { t = town, p = parent, x = x, y = y }
	else
		s.wk = s.wk or {}
		if #s.wk >= M.WORKS_CAP then return s, false end
		s.wk[#s.wk + 1] = town
		s.wm = s.wm or {}
		if #s.wm < M.WORKS_CAP then s.wm[#s.wm + 1] = { t = town, p = parent, x = x, y = y } end
	end
	local f = s.frames[tostring(parent)]
	if f then
		if district then f.dp = math.min(9, (f.dp or 0) + 1)
		elseif f.wp == nil then f.wp = town end
	end
	return s, true
end

-- the load check (2026-10-14 late)
M.OFFSHOOT_SITE_R = 900    -- m: a town with a saved site must stand within this of it
M.OFFSHOOT_MAX_D = 2600    -- m: a town without one (older entries) within this of its parent's centre

--- The saved Works / district entries whose town is not where the record says (run 2026-10-14_0119_sqot: several
--- parents claimed one new town). posOf(id) -> x, y (the town's centre), nil, "unknown" (a town without a readable
--- position: kept) or nil (no such town). Returns a list of
--- { t, p, kind = "district" | "works", why = "gone" | "site" | "far", d }; entries it cannot judge are kept.
function M.offshootCheck(raw, posOf)
	local out = {}
	if type(raw) ~= "table" or posOf == nil then return out end
	local function parentPos(p)
		local f = type(raw.frames) == "table" and raw.frames[tostring(p)] or nil
		if type(f) == "table" and tonumber(f.x) and tonumber(f.y) then return tonumber(f.x), tonumber(f.y) end
		if p and p > 0 then return posOf(p) end
		return nil
	end
	local function judge(t, p, sx, sy, kind)
		local x, y = posOf(t)
		if x == nil then
			if y ~= "unknown" then out[#out + 1] = { t = t, p = p, kind = kind, why = "gone", d = -1 } end
			return
		end
		if sx and sy then
			local d = math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2)
			if d > M.OFFSHOOT_SITE_R then out[#out + 1] = { t = t, p = p, kind = kind, why = "site", d = d } end
			return
		end
		local px, py = parentPos(p)
		if px == nil then return end
		local d = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
		if d > M.OFFSHOOT_MAX_D then out[#out + 1] = { t = t, p = p, kind = kind, why = "far", d = d } end
	end
	if type(raw.dk) == "table" then
		for i = 1, math.min(#raw.dk, M.WORKS_CAP) do
			local e = raw.dk[i]
			if type(e) == "table" and tonumber(e.t) then
				judge(tonumber(e.t), tonumber(e.p) or -1, tonumber(e.x), tonumber(e.y), "district")
			end
		end
	end
	if type(raw.wk) == "table" then
		local meta = {}
		if type(raw.wm) == "table" then
			for _, e in ipairs(raw.wm) do if type(e) == "table" and tonumber(e.t) then meta[tonumber(e.t)] = e end end
		end
		local parentOf = {}
		if type(raw.frames) == "table" then
			for k, f in pairs(raw.frames) do
				if type(f) == "table" and tonumber(f.wp) and tonumber(k) then parentOf[tonumber(f.wp)] = tonumber(k) end
			end
		end
		for i = 1, math.min(#raw.wk, M.WORKS_CAP) do
			local t = tonumber(raw.wk[i])
			if t then
				local m = meta[t]
				local p = (m and tonumber(m.p)) or parentOf[t] or -1
				judge(t, p, m and tonumber(m.x), m and tonumber(m.y), "works")
			end
		end
	end
	return out
end

--- A view of raw without the towns in drop ({ [id] = true }): `dk` / `wk` / `wm` filtered (a shallow copy; frames
--- shared). raw itself when nothing to drop is in it.
function M.withoutOffshoots(raw, drop)
	if type(raw) ~= "table" or drop == nil or next(drop) == nil then return raw end
	local hit = false
	for _, e in ipairs(type(raw.dk) == "table" and raw.dk or {}) do if type(e) == "table" and drop[tonumber(e.t)] then hit = true end end
	for _, id in ipairs(type(raw.wk) == "table" and raw.wk or {}) do if drop[tonumber(id)] then hit = true end end
	if not hit then return raw end
	local v = {}
	for k, val in pairs(raw) do v[k] = val end
	if type(raw.dk) == "table" then
		v.dk = {}
		for _, e in ipairs(raw.dk) do if not (type(e) == "table" and drop[tonumber(e.t)]) then v.dk[#v.dk + 1] = e end end
	end
	if type(raw.wk) == "table" then
		v.wk = {}
		for _, id in ipairs(raw.wk) do if not drop[tonumber(id)] then v.wk[#v.wk + 1] = id end end
	end
	return v
end

--- handleEvent "stopbase" { b, x, y, h }: a stop named by the mod that is the base of its street section (ot_stopname
--- sections, 2026-10-14): name, position (m, whole metres), height. Idempotent by name; the oldest drops beyond
--- STOPBASE_CAP. Names only: nothing in the world depends on it.
function M.applyStopBase(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" or type(param.b) ~= "string" or #param.b > 64 or not (tonumber(param.x) and tonumber(param.y)) then
		return s, false
	end
	s.sb = s.sb or {}
	for _, e in ipairs(s.sb) do if e.b == param.b then return s, false end end
	s.sb[#s.sb + 1] = { b = param.b, x = math.floor(tonumber(param.x) + 0.5), y = math.floor(tonumber(param.y) + 0.5),
		h = math.floor((tonumber(param.h) or 0) * 10 + 0.5) / 10 }
	while #s.sb > M.STOPBASE_CAP do table.remove(s.sb, 1) end
	return s, true
end

--- The saved stop section bases (a list; empty when none).
function M.stopBases(raw)
	if type(raw) ~= "table" or type(raw.sb) ~= "table" then return {} end
	return M.normalize(raw).sb or {}
end

--- The district towns the mod created ({ [id] = parent id }).
function M.districtSet(raw)
	local set = {}
	if type(raw) ~= "table" or type(raw.dk) ~= "table" then return set end
	for _, e in ipairs(raw.dk) do
		if type(e) == "table" and tonumber(e.t) then set[tonumber(e.t)] = tonumber(e.p) or -1 end
	end
	return set
end

--- The industrial satellite towns the mod created ({ [id] = true }).
function M.worksSet(raw)
	local set = {}
	if type(raw) ~= "table" or type(raw.wk) ~= "table" then return set end
	for _, id in ipairs(raw.wk) do
		local n = tonumber(id)
		if n then set[n] = true end
	end
	return set
end

--- The water names list (normalised, at most WATER_CAP; nil when none).
function M.normWaters(list)
	if type(list) ~= "table" then return nil end
	local out = {}
	for i = 1, math.min(#list, M.WATER_CAP) do
		local e = list[i]
		if type(e) == "table" and type(e.n) == "string" and #e.n <= 48 and tonumber(e.x) and tonumber(e.y)
			and (e.k == "r" or e.k == "l") then
			local st = (type(e.s) == "string" and #e.s <= 48 and e.s ~= e.n) and e.s or nil
			out[#out + 1] = { n = e.n, s = st, x = math.floor(tonumber(e.x) + 0.5), y = math.floor(tonumber(e.y) + 0.5), k = e.k }
		end
	end
	return #out > 0 and out or nil
end

--- handleEvent "names" { done = 1, nd, rv }: landscape / generated names done on this map (idempotent; works on an
--- uninitialised state too).
function M.applyNames(raw, param)
	local s = M.normalize(raw)
	if s.nm == 1 or type(param) ~= "table" or tonumber(param.done) ~= 1 then return s, false end
	s.nm = 1
	if type(param.nd) == "string" and #param.nd <= 16 then s.nd = param.nd end
	s.rv = M.normWaters(param.rv)
	-- (2026-10-17, the card's name origins: { { t = townId, o = "<genTag>,<specTag>,<shape>" } })
	if type(param.no) == "table" then
		local out, n = {}, 0
		for i = 1, math.min(#param.no, M.ORIGIN_CAP) do
			local e = param.no[i]
			local t = type(e) == "table" and tonumber(e.t) or nil
			if t and M.originOk(e.o) then
				out[tostring(math.floor(t))] = e.o
				n = n + 1
			end
		end
		if n > 0 then s.no = out end
	end
	return s, true
end

--- Is v a saved name origin ("<tag>,<tag>,<shape>": lower-case words, "-" for none, at most ORIGIN_MAX chars)?
function M.originOk(v)
	return type(v) == "string" and #v <= M.ORIGIN_MAX and v:match("^[a-z_%-]+,[a-z_%-]+,[a-z_%-]+$") ~= nil
end

--- A clean copy of the saved name origins (`no`), or nil.
function M.normOrigins(raw)
	if type(raw) ~= "table" then return nil end
	local out, n = {}, 0
	for k, v in pairs(raw) do
		if n >= M.ORIGIN_CAP then break end
		local t = tonumber(k)
		if t and M.originOk(v) then
			out[tostring(math.floor(t))] = v
			n = n + 1
		end
	end
	return n > 0 and out or nil
end

--- The saved name origin of town t ("<genTag>,<specTag>,<shape>") or nil.
function M.origin(raw, t)
	if type(raw) ~= "table" or type(raw.no) ~= "table" then return nil end
	local v = raw.no[tostring(t)]
	return M.originOk(v) and v or nil
end

--- Is v a saved card summary ("<phase>:<maturity>:<readiness>", readiness "-" when unknown)?
function M.uiOk(v)
	return type(v) == "string" and #v <= M.UI_MAX and v:match("^%d:%d+:[%d%-]+$") ~= nil
end

--- A clean copy of the saved card summaries (`ui`), or nil.
function M.normUi(raw)
	if type(raw) ~= "table" then return nil end
	local out, n = {}, 0
	for k, v in pairs(raw) do
		if n >= M.UI_CAP then break end
		local t = tonumber(k)
		if t and M.uiOk(v) then
			out[tostring(math.floor(t))] = v
			n = n + 1
		end
	end
	return n > 0 and out or nil
end

--- handleEvent "ui" { towns = { { t = townId, v = "<phase>:<maturity>:<readiness>" } } }: the card's summaries of the
--- towns whose values moved (the newest wins; a new town only while under UI_CAP). Idempotent.
function M.applyUi(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" or type(param.towns) ~= "table" then return s, false end
	local changed = false
	local n = 0
	for _ in pairs(s.ui or {}) do n = n + 1 end
	for i = 1, math.min(#param.towns, M.UI_BATCH) do
		local e = param.towns[i]
		local t = type(e) == "table" and tonumber(e.t) or nil
		if t and M.uiOk(e.v) then
			local key = tostring(math.floor(t))
			s.ui = s.ui or {}
			local old = s.ui[key]
			if old ~= e.v and (old ~= nil or n < M.UI_CAP) then
				if old == nil then n = n + 1 end
				s.ui[key] = e.v
				changed = true
			end
		end
	end
	return s, changed
end

--- The saved card summary of town t or nil.
function M.ui(raw, t)
	if type(raw) ~= "table" or type(raw.ui) ~= "table" then return nil end
	local v = raw.ui[tostring(t)]
	return M.uiOk(v) and v or nil
end

--- The saved water names (generated names) or nil.
function M.waters(raw)
	if type(raw) ~= "table" then return nil end
	return M.normWaters(raw.rv)
end

--- handleEvent onPostBuildProposal: new Road Stops { {st, g, n, x, y} } queued for a stop name (each station once; at
--- most STOP_CAP waiting). Returns the new state and whether it changed.
function M.addStops(raw, found, now)
	local s = M.normalize(raw)
	if type(found) ~= "table" or #found == 0 then return s, false end
	s.sq = s.sq or {}
	local queued = {}
	for _, e in ipairs(s.sq) do queued[e.st] = true end
	local changed = false
	for _, f in ipairs(found) do
		if #s.sq >= M.STOP_CAP then break end
		local st = tonumber(f.st)
		if st and not queued[st] then
			queued[st] = true
			-- (k: a new station construction's kind, "rail" | "harbor" | "street"; nil = a Road Stop)
			local k = (f.k == "rail" or f.k == "harbor" or f.k == "street") and f.k or nil
			s.sq[#s.sq + 1] = { st = st, g = tonumber(f.g) or -1, n = type(f.n) == "string" and f.n or nil,
				x = tonumber(f.x), y = tonumber(f.y), t = tonumber(now) or 0, k = k }
			changed = true
		end
	end
	return s, changed
end

--- handleEvent "stops" { done = { st, ... } }: drops those stations from the stop queue.
function M.applyStopsDone(raw, param)
	local s = M.normalize(raw)
	if type(param) ~= "table" or type(param.done) ~= "table" or s.sq == nil then return s, false end
	local drop = {}
	for i = 1, math.min(#param.done, M.STOP_CAP * 2) do
		local st = tonumber(param.done[i])
		if st then drop[st] = true end
	end
	local keep = {}
	for _, e in ipairs(s.sq) do if not drop[e.st] then keep[#keep + 1] = e end end
	if #keep == #s.sq then return s, false end
	s.sq = keep
	return s, true
end

--- The stop queue (a list; empty when none).
function M.stopQueue(raw)
	if type(raw) ~= "table" or type(raw.sq) ~= "table" then return {} end
	return M.normalize(raw).sq or {}
end

--- Were the landscape names done on this map?
function M.namesDone(raw)
	return type(raw) == "table" and tonumber(raw.nm) == 1
end

--- Set of known town ids (nil while uninitialised).
function M.knownSet(raw)
	if not M.initialised(raw) then return nil end
	local set = {}
	for _, id in ipairs(raw.known) do
		local n = tonumber(id)
		if n then set[n] = true end
	end
	return set
end

--- Deep forest towns on the saved frames (`fd`, ot_forest deepPick): count, and the set { [townId] = true }.
function M.deepTowns(raw)
	local n, set = 0, {}
	if type(raw) ~= "table" or type(raw.frames) ~= "table" then return n, set end
	for k, f in pairs(raw.frames) do
		if type(f) == "table" and tonumber(f.fd) == 1 then
			n = n + 1
			local id = tonumber(k)
			if id then set[id] = true end
		end
	end
	return n, set
end

--- The saved plan frame of a town as ot_inputs wants it ({ axis, origin = {x, y} }), or nil.
function M.frame(raw, town)
	if type(raw) ~= "table" or type(raw.frames) ~= "table" then return nil end
	local f = raw.frames[tostring(town)]
	if type(f) ~= "table" or not (tonumber(f.a) and tonumber(f.x) and tonumber(f.y)) then return nil end
	local out = { axis = tonumber(f.a), origin = { tonumber(f.x), tonumber(f.y) } }
	local si = tonumber(f.s)
	if si and SH.IDS[si] then
		out.shape = SH.IDS[si]
		out.shapeAxis = tonumber(f.sa)
	end
	local sti = tonumber(f.st)
	if sti and M.STYLE_IDS[sti] then out.style = M.STYLE_IDS[sti] end
	out.initial = tonumber(f.ic)
	local fi = tonumber(f.f)
	if fi and FM.IDS[fi] then out.form = FM.IDS[fi] end
	if tonumber(f.sx) and tonumber(f.sy) then out.sat = { tonumber(f.sx), tonumber(f.sy) } end
	out.character = tonumber(f.ch) == 1 or nil
	out.bridge = tonumber(f.br) == 1 or nil
	out.gridLook = tonumber(f.gl)
	-- (motifs, ot_motif: a frame without `mo` has none; frames from before M0 too)
	out.motifs = MO.decode(f.mo)
	-- (the ring road's radius, M3: the ring stays where it was picked as the town grows)
	out.ringR = tonumber(f.rr)
	out.lead = tonumber(f.ld) == 1 or nil
	out.works = tonumber(f.wp)
	out.districts = tonumber(f.dp)
	out.coastal = tonumber(f.cs) == 1 or nil
	-- (a deep forest town, ot_forest deepPick, 2026-10-14: deep from its first build on, whatever the draw says later)
	out.deep = tonumber(f.fd) == 1 or nil
	-- (the level-weight strength the mod set, 2026-10-14 late: 0.25..1, nil = none of ours)
	local lw = tonumber(f.lw)
	out.levels = (lw and lw ~= 0 and lw >= -4 and lw <= 4) and lw / 4 or nil
	-- (the sig of the weights sent, 2026-10-15: `ours` by sig, the era makes one tilt's rows differ)
	out.levelSig = type(f.ls) == "string" and f.ls or nil
	-- (its starting size for the offshoots' readiness, ot_satpace, 2026-10-14)
	out.start = tonumber(f.b0)
	-- (its strong character kind, ot_character, 2026-10-14: an index into ot_character.IDS; the densify draw)
	out.charKind = tonumber(f.ck)
	out.densify = tonumber(f.dz)
	-- (the organic ring geometry, 2026-10-14 §56: a frame without it keeps the even rings its plan was made with)
	out.organicRings = tonumber(f.og) == 1 or nil
	-- (the landscape-aware skeleton, §63: a frame without it keeps the arms its shape draws)
	out.skel = (type(f.sk) == "string" and #f.sk <= M.SKEL_MAX) and f.sk or nil
	-- (the town's lock, §65: `lm` = 1 every mod street locked; a frame without it keeps the legacy shape lock)
	-- (§69: `lm` = 2 the steering lock, ot_lockpol)
	out.lockMode = (tonumber(f.lm) == 1 and "mod") or (tonumber(f.lm) == 2 and "steer") or nil
	-- (its core: the street edges not the mod's at its first build, §65)
	out.core = tonumber(f.e0)
	-- (the game's streets locked too, §67: a frame without `gk` keeps the §65 lock only)
	out.gameLock = tonumber(f.gk) == 1 or nil
	-- (the decision draws, §68: 2 = rng.draw; a frame without `dv` keeps the rng.unit picks it was made with)
	out.drawV = tonumber(f.dv) == 2 and 2 or nil
	-- (the game year of its first frame, §70: the lock maturity's age; a frame without `fy` has no age part)
	out.year = finite(f.fy) and tonumber(f.fy) / 100 or nil
	-- (a deferred roundabout pair, ot_ring 2026-10-14 §56)
	if tonumber(f.px) and tonumber(f.py) and tonumber(f.ph) and tonumber(f.pr) and (tonumber(f.pn) or 0) > 0 then
		out.pendingPair = { x = tonumber(f.px), y = tonumber(f.py), h = tonumber(f.ph), R = tonumber(f.pr), n = tonumber(f.pn),
			k = (tonumber(f.pk) == 1 or tonumber(f.pk) == 2) and tonumber(f.pk) or nil }
	end
	return out
end

--- The frame event's param for a town from the style and master plan of its first increment (ic: the town's
--- initial land use capacity sum then, or nil; b0: its offshoot size then, or nil; ex = { lock = "mod" | other,
--- core = its street edges not the mod's then } or nil, §65).
function M.frameParam(town, style, mp, ic, b0, ex)
	local o = mp and mp.origin or (style and style.centre)
	if not (o and style and style.axis) then return nil end
	local out = { town = town, a = math.floor(style.axis * 1e6 + 0.5) / 1e6, x = math.floor(o[1] * 1000 + 0.5) / 1000,
		y = math.floor(o[2] * 1000 + 0.5) / 1000 }
	for i, id in ipairs(M.STYLE_IDS) do
		-- only a style the town got from its site (or its strong character's, 2026-10-14) is saved (forced / dev styles
		-- follow the setting)
		if id == style.id and (style.styleSource == "site" or style.styleSource == "character") then out.st = i end
	end
	-- (a strong character, ot_character 2026-10-14: its kind index; stays after a reload)
	if tonumber(style.charIndex) then out.ck = math.floor(style.charIndex) end
	local sh = style.shape
	if sh and SH.INDEX[sh.id] then
		out.s = SH.INDEX[sh.id]
		out.sa = math.floor((sh.axis or 0) * 1e6 + 0.5) / 1e6
	end
	if tonumber(ic) and ic > 0 then out.ic = math.floor(ic + 0.5) end
	if finite(b0) and b0 > 0 then out.b0 = math.floor(b0 + 0.5) end
	if ex and ex.lock == "mod" then out.lm = 1 end
	if ex and ex.lock == "steer" then out.lm = 2 end
	if ex and finite(ex.core) and ex.core >= 0 then out.e0 = math.floor(ex.core + 0.5) end
	if ex and (ex.lock == "mod" or ex.lock == "steer") and ex.gameLock then out.gk = 1 end
	-- (§70: the game year of the first frame, x 100)
	if ex and finite(ex.year) and ex.year > 0 then out.fy = math.floor(ex.year * 100 + 0.5) end
	-- (§68: the town's decisions drawn with rng.draw; a reload keeps them)
	if style.drawV == 2 then out.dv = 2 end
	if style.form and FM.INDEX[style.form.id] then out.f = FM.INDEX[style.form.id] end
	if style.form and style.form.character then out.ch = 1 end
	-- (a coastal hugger, 2026-10-14: the strong shore form stays after a reload, whatever the map's ranking says then)
	if style.form and style.form.coastal then out.cs = 1 end
	-- (a deep forest town, 2026-10-14: stays deep after a reload)
	if style.deep then out.fd = 1 end
	-- (the grid look its plan was made with: a reload keeps the same plan; real map run 2026-10-13_0232_sqot-dev: the
	-- look dropped right after the head start saved the frame, so later increments followed another plan)
	if tonumber(style.gridLook) and style.gridLook ~= 0 then out.gl = math.floor(style.gridLook * 1000 + 0.5) / 1000 end
	-- (the organic ring geometry, 2026-10-14 §56: wobbling rings, the ring road's radius profile)
	if style.ringWobble then out.og = 1 end
	-- (the landscape-aware skeleton, §63: its arms stay after a reload, whatever the trees read then)
	if type(style.skelKey) == "string" and #style.skelKey > 0 and #style.skelKey <= M.SKEL_MAX then out.sk = style.skelKey end
	-- (the drawn motifs, ot_motif; forced (dev) and derived ones are not saved; none drawn: no field)
	out.mo = MO.encode(style.motifs)
	-- (the ring road's radius, M3 ot_motif_town: the core's extent when it was picked)
	for _, m in ipairs(style.motifs or {}) do
		local R = m.id == "ring_road" and not m.forced and (m.ringR or m.ringR0) or nil
		if tonumber(R) then out.rr = math.floor(R * 10 + 0.5) / 10 end
	end
	return out
end

---------------------------------------------------------------------------
-- The per-frame read (2026-10-20, PLAN §75 "Follow-ups built", "The saved state off the frame path"). guiUpdate used to
-- copy the whole saved state with state:get() every frame (Main Thread, ~110 Hz; TICKCOST getMaxUs 180-330 us before
-- the provenance record `pv`, which only the console lookup reads). Now it reads the change number (`rev`, M.bumpRev in
-- handleEvent) and copies the whole state only when needed, passing the last copy again otherwise:
--   * a full read (state:get(), as before) when there is no copy yet, when the native number differs from the number
--     inside the last copy (either side may lag: until both agree every frame reads in full, as before), and at least
--     every READ_REFRESH_S (a save loaded into the same Lua state, anything that changed the state without a bump);
--   * after the driver sent an event (Reader:expect; ot_engine.sentN), every frame until the copy's number moved, at most
--     READ_WATCH_S: the driver sees its own changes as soon as the old path did, even if the native number lagged the
--     copy (only the player's new Road Stops, onPostBuildProposal, rely on the native number alone);
--   * any error of the number read (no game-script entity, no component, no state_native, not a number) switches the
--     reader to full reads every frame for the session (`mode` "get", the old path), with the reason once;
--   * so does a cost check every READ_CHECK_N frames: the window's number reads plus its copies must cost less than a
--     copy every frame (the session's mean copy); otherwise the old path is cheaper.
-- The driver gets the same table (read-only: the driver never writes into it, test_driver "state reader") or, after
-- a change, the new copy; a full read that fails gives nil, as before. `miss` counts full reads whose copy disagreed
-- with the native number read just before (TICKCOST revMiss: whether the two views lag each other in game).
M.READ_REV = true          -- false: always the old path (full read every frame)
M.READ_REFRESH_S = 2       -- s: a full read at least this often
M.READ_WATCH_S = 2         -- s: after a sent event, full reads until the copy's number moved, at most this long
M.READ_CHECK_N = 2000      -- frames per cost check (~20 s at 110 Hz)
M.READ_FULL_MIN = 4        -- copies the session needs before the cost check compares

local Reader = {}
Reader.__index = Reader

--- A reader for one game script's Lua state (o.mode "get": the old path from the start).
function M.newReader(o)
	o = o or {}
	local mode = (o.mode == "get" or not M.READ_REV) and "get" or "rev"
	return setmetatable({ mode = mode, has = false, cache = nil, rev = nil, fullAt = 0, why = nil, watchUntil = nil,
		watchBase = nil, n = 0, revSum = 0, fullN = 0, allFullN = 0, allFullSum = 0, miss = 0 }, Reader)
end

local function us(v)
	v = tonumber(v) or 0
	if v ~= v or v < 0 or v == math.huge then return 0 end
	return v
end

--- Back to the old path for the session; returns the reason (once).
function Reader:fallBack(why)
	self.mode, self.why = "get", tostring(why)
	self.has, self.cache, self.rev, self.watchUntil = false, nil, nil, nil
	return self.why
end

--- The driver sent an event this frame (now = us): full reads until the copy's number moved (READ_WATCH_S at most).
function Reader:expect(now)
	if self.mode ~= "rev" then return end
	self.watchUntil = us(now) + M.READ_WATCH_S * 1e6
	self.watchBase = self.rev
end

--- The cost check (every READ_CHECK_N number reads): the reason when the reader fell back, else nil.
function Reader:check()
	if self.n < M.READ_CHECK_N then return nil end
	local n, revMean, fullN = self.n, self.revSum / self.n, self.fullN
	self.n, self.revSum, self.fullN = 0, 0, 0
	if self.allFullN < M.READ_FULL_MIN then return nil end
	local fullMean = self.allFullSum / self.allFullN
	-- per frame: the number read every frame plus the copies' share, against a copy every frame (the old path)
	if fullMean > 0 and revMean + fullN / n * fullMean >= fullMean then
		return self:fallBack(string.format("rev read %.0f us + %d copies in %d frames vs copy %.0f us", revMean, fullN, n,
			fullMean))
	end
	return nil
end

--- One frame. getFull() = the whole state (state:get(); may error), readRev() = the saved change number (nil: none yet;
--- errors when it can't be read), now() = us. Returns the state (nil when the full read failed, as before), whether
--- a full read ran, and a fallback reason the frame the reader fell back (else nil).
function Reader:read(getFull, readRev, now)
	if self.mode ~= "rev" then
		local okG, v = pcall(getFull)
		return okG and v or nil, true, nil
	end
	local t0 = us(now())
	local okR, rev = pcall(readRev)
	local t1 = us(now())
	local why = nil
	if not okR then
		why = self:fallBack("rev read: " .. tostring(rev))
	elseif rev ~= nil and type(rev) ~= "number" then
		why = self:fallBack("rev read: a " .. type(rev))
	end
	if why ~= nil then
		local okG, v = pcall(getFull)
		return okG and v or nil, true, why
	end
	self.n = self.n + 1
	self.revSum = self.revSum + math.max(0, t1 - t0)
	if self.watchUntil ~= nil and (t1 >= self.watchUntil or (self.has and self.rev ~= self.watchBase)) then
		self.watchUntil = nil   -- (the copy moved since the send, or the watch timed out)
	end
	if self.has and self.watchUntil == nil and rev == self.rev and t1 >= self.fullAt
		and t1 - self.fullAt < M.READ_REFRESH_S * 1e6 then
		return self.cache, false, self:check()
	end
	local okG, v = pcall(getFull)
	local t2 = us(now())
	self.fullN = self.fullN + 1
	self.allFullN = self.allFullN + 1
	self.allFullSum = self.allFullSum + math.max(0, t2 - t1)
	if okG then
		self.has, self.cache, self.rev, self.fullAt = true, v, M.revOf(v), t2
		if self.rev ~= rev then self.miss = self.miss + 1 end
	else
		self.has, self.cache, self.rev = false, nil, nil
		v = nil
	end
	if self.watchUntil ~= nil and self.has and self.rev ~= self.watchBase then self.watchUntil = nil end
	return v, true, self:check()
end

return M
