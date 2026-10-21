-- Organic Towns: street provenance (§75 follow-up, 2026-10-19; PLAN.md 6.2 "Side streets and parallel streets (§75)",
-- "Follow-ups"). From a player's screenshot, tell whether a street is the mod's (and which plan piece made it) or the
-- game's own growth / the town's original layout.
--
-- The driver (Driver:provNote, after every successful build) logs one debug line per built edge
--   [SQOT] PROV town=<id> name=<town> edge=<entity> n=<node0>,<node1> a=<x>,<y> b=<x>,<y> len=<m> src=<source>
--          key=<plan piece key> trig=<demand|head|force|...> seq=<the town's build number this session> year=<game year>
--          lock=<0|1>
-- (at most LINES_MAX per build, then one `more=`) and sends the record to the game script (ot_saved `pv`, event
-- "square_organic_towns.prov"), so a lookup works in later sessions too: from the first build with this version on.
--
-- Source (`src`): "<kind>[/<piece>]"
--   kind  = a near-miss join "nm:<tee|cross|pair>" (+ "c" a pair's corner), else the job's kind for a satellite seed /
--           grow ("sat"), country lane ahead ("lead"), Works link ("works"), river bridge ("bridge"), wedge frame
--           ("frame"), else the plan piece's origin (ot_select.origin: "plain" a lattice / grid piece, "arm" a shaped
--           arm's spoke / row, "ring" a ring arc, "crescent", "link" a connector, "m:<motif>" a motif's piece)
--   piece = the plan piece key's leading letters (organic lattice: "sp" spoke, "sr" secondary radial, "bk" back row,
--           "ln" cross lane, "tip" spoke tip, "rg" ring; "conn" connector; grid growers their own keys); left out when
--           it repeats the kind ("frame", not "frame/frame")
--
-- Saved record (`pv`, 2026-10-20, performance-safe): ONE string for the whole map, entries in build order (oldest
-- first) joined by ";":
--   "<town>,<edge>,<src>,<trig>,<year>,<x0>,<y0>,<dx>,<dy>,<mx>,<my>"
-- (src "plain/<piece>" stored as "/<piece>"; trig one letter for the common ones, TRIG; dx, dy = the far end from the
-- near end; mx, my = the Hermite middle's offset from the chord's middle, usually 0; whole metres). ~40 chars an
-- entry. Bounds: at most TOWN_N entries a town (its oldest go first) and TOTAL_MAX chars in all (the oldest of the
-- map go first), so a long game never grows it. Why one string: the driver's guiUpdate copies the whole saved state
-- (state:get(), TICKCOST getMaxUs; every frame until 2026-10-20, now only when it changed, ot_saved Reader); one string is one memcpy of at most TOTAL_MAX bytes, where a table of
-- per-town strings or entries would add a Lua object each. Appends touch only the end (and one town's oldest entries);
-- nothing runs per tick. A save from before has no `pv` (nil: no work); the per-town tables of the first dev build
-- (2026-10-19) are converted once, bounded (CONVERT_MAX).
--
-- Console (the key below Esc; docs/console.md "Organic Towns: who built this street?"):
--   ug_require("square_organic_towns::/organic_towns/ot_prov.lua").who()            the street under the cursor
--   ug_require("square_organic_towns::/organic_towns/ot_prov.lua").who(<edge id>)   an edge entity
--   ug_require("square_organic_towns::/organic_towns/ot_prov.lua").who(<x>, <y>)    the street nearest a point
-- prints "[SQOT] WHO ..." lines (stdout.txt; the console also echoes the returned text). Every failure prints a WHO
-- line too. Pure parts tested in test_prov; every loop capped.

local M = {}

M.TOTAL_MAX = 32768     -- chars of the whole record at most (~800 edges, ~45 km of street; the oldest go first)
M.TOWN_N = 120          -- entries of one town at most (its oldest go first)
M.SRC_MAX = 24          -- chars of a source at most
M.LINES_MAX = 24        -- PROV lines per build at most
M.ENTRIES_MAX = 4000    -- entries parsed at most (TOTAL_MAX / the shortest entry)
M.ADD_MAX = 400         -- entries of one event at most
M.CONVERT_MAX = 2000    -- entries converted from the per-town tables of 2026-10-19 at most
M.NEAR_M = 12           -- m: a record lies this close to the street (a split or rebuilt edge)
M.PICK_R = 40           -- m: the street nearest a point within this (by its curve)
M.SEARCH_R = 300        -- m: the octree circle for that: it matches an edge by its middle, not its extent
                        --    (findings roads.md "Octree edge search"), so PICK_R + half the longest street edge
M.EDGES_MAX = 3000      -- edges read around a point at most
M.GS_NAME = "square_organic_towns::/organic_towns/organic_towns.gs"

M.PIECES = { sp = "spoke", sr = "secondary radial", bk = "back row", ln = "cross lane", tip = "spoke tip",
	rg = "ring arc", conn = "connector", frame = "wedge frame" }
M.TRIG = { demand = "d", head = "h", force = "f", offshoot = "o" }
M.TRIG_WORDS = { d = "demand", h = "head", f = "force", o = "offshoot" }

local floor = math.floor

local function round(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then return 0 end
	local r = floor(v + 0.5)
	if r == 0 then return 0 end   -- (no "-0")
	return r
end

local function num(v)
	return tostring(round(v))
end

--- A source as stored: no separators, at most SRC_MAX chars ("-" when empty).
function M.clean(src)
	src = tostring(src or "")
	src = src:gsub("[^%w:_%-%./@#]", "_")
	if #src > M.SRC_MAX then src = src:sub(1, M.SRC_MAX) end
	if src == "" then return "-" end
	return src
end

--- The plan piece key's leading letters ("ln3:2:1:2" -> "ln", "conn:12" -> "conn"), or nil.
function M.keyHead(key)
	if type(key) ~= "string" then return nil end
	local h = key:match("^(%a+)")
	return h
end

--- The source of a built spec edge e (ot_plan / ot_nearmiss fields: nearMiss, nearMissKind, nearMissCorner, origin, key)
--- in a job of kind jobKind ("sat" | "lead" | "works" | "bridge" | "frame" | nil a plan).
function M.source(jobKind, e)
	e = e or {}
	local kind
	if e.nearMiss then
		kind = "nm:" .. tostring(e.nearMissKind or "?") .. (e.nearMissCorner and "c" or "")
	elseif jobKind then
		kind = jobKind
	else
		kind = tostring(e.origin or "plain")
	end
	local h = (not e.nearMiss) and M.keyHead(e.key) or nil
	if h and h ~= kind then kind = kind .. "/" .. h end
	return M.clean(kind)
end

local function fin(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then return nil end
	return v
end

--- One saved entry without its town (a string without ";") from { id, src, trig, year, p0, p1, t0, t1 } (positions
--- {x, y}, the tangents for the Hermite middle; none: the chord's), or nil.
function M.entry(r)
	local id = fin(r and r.id)
	if id == nil or id < 0 or r.p0 == nil or r.p1 == nil then return nil end
	local x0, y0, x1, y1 = fin(r.p0[1]), fin(r.p0[2]), fin(r.p1[1]), fin(r.p1[2])
	if not (x0 and y0 and x1 and y1) then return nil end
	local mx, my = 0, 0
	if r.t0 and r.t1 and fin(r.t0[1]) and fin(r.t1[1]) then
		mx = (r.t0[1] - r.t1[1]) / 8
		my = ((fin(r.t0[2]) or 0) - (fin(r.t1[2]) or 0)) / 8
	end
	local src = M.clean(r.src)
	if src:sub(1, 6) == "plain/" then src = src:sub(6) end   -- ("/ln": the commonest kind, short)
	local trig = tostring(r.trig or "-")
	trig = M.TRIG[trig] or M.clean(trig):sub(1, 6)
	local ix0, iy0 = round(x0), round(y0)
	return table.concat({ tostring(floor(id)), src, trig, num(r.year), ix0, iy0, num(x1 - ix0), num(y1 - iy0),
		num((x0 + x1) / 2 + mx - (ix0 + round(x1)) / 2), num((y0 + y1) / 2 + my - (iy0 + round(y1)) / 2) }, ",")
end

--- One record part as an entry table { town, id, src, trig, year, pts = { {x, y} x 3 } }, or nil (malformed).
function M.parseOne(part)
	local f = {}
	for v in part:gmatch("[^,]+") do
		f[#f + 1] = v
		if #f > 11 then return nil end
	end
	if #f ~= 11 then return nil end
	local town, id = tonumber(f[1]), tonumber(f[2])
	local c = {}
	for i = 6, 11 do c[#c + 1] = tonumber(f[i]) end
	if not (town and id) or #c ~= 6 then return nil end
	local src = f[3]
	if src:sub(1, 1) == "/" then src = "plain" .. src end
	local x0, y0 = c[1], c[2]
	local x1, y1 = x0 + c[3], y0 + c[4]
	return { town = floor(town), id = id, src = src, trig = M.TRIG_WORDS[f[4]] or f[4], year = tonumber(f[5]),
		pts = { { x0, y0 }, { (x0 + x1) / 2 + c[5], (y0 + y1) / 2 + c[6] }, { x1, y1 } } }
end

--- The entries of the record string, oldest first (at most ENTRIES_MAX, malformed ones skipped).
function M.parse(str)
	local out = {}
	if type(str) ~= "string" then return out end
	local n = 0
	for part in str:gmatch("[^;]+") do
		n = n + 1
		if n > M.ENTRIES_MAX then break end
		local r = M.parseOne(part)
		if r then out[#out + 1] = r end
	end
	return out
end

--- Does str hold an entry starting with prefix p ("<town>,<edge>,")?
local function has(str, p)
	if str:sub(1, #p) == p then return true end
	return str:find(";" .. p, 1, true) ~= nil
end

--- The start positions of town t's entries in str (oldest first, at most cap + 1 counted is enough).
local function townStarts(str, t, cap)
	local out = {}
	local p = tostring(t) .. ","
	if str:sub(1, #p) == p then out[1] = 1 end
	local from = 1
	for _ = 1, M.ENTRIES_MAX do
		local i = str:find(";" .. p, from, true)
		if i == nil then break end
		out[#out + 1] = i + 1
		from = i + 1
		if #out > cap + M.ADD_MAX then break end
	end
	return out
end

--- str cut to at most max chars, the oldest whole entries first.
function M.trim(str, max)
	max = max or M.TOTAL_MAX
	if type(str) ~= "string" then return "" end
	if #str <= max then return str end
	local cut = str:find(";", #str - max, true)   -- (the first boundary that leaves at most max chars)
	if cut == nil then return "" end
	return str:sub(cut + 1)
end

--- The record str with town t's new entries (strings from M.entry) appended, each edge of a town once (idempotent:
--- handleEvent may run in more than one simulation state); then town t's oldest past townN (default TOWN_N) and the
--- map's oldest past max chars (default TOTAL_MAX) dropped. Work: a few plain finds over str, no parse of the record.
--- Returns the new string, changed.
function M.append(str, t, entries, max, townN)
	max, townN = max or M.TOTAL_MAX, townN or M.TOWN_N
	str = type(str) == "string" and str or ""
	t = tonumber(t)
	if t == nil or t ~= t or type(entries) ~= "table" then return str, false end
	t = floor(t)
	local parts = {}
	if str ~= "" then parts[1] = str end
	local seen = {}
	local added = 0
	for i = 1, math.min(#entries, M.ADD_MAX) do
		local e = entries[i]
		local id = type(e) == "string" and e:match("^(%d+),") or nil
		if id and not seen[id] and not e:find(";", 1, true) then
			local full = tostring(t) .. "," .. e
			local p = tostring(t) .. "," .. id .. ","
			if M.parseOne(full) and not has(str, p) then
				seen[id] = true
				parts[#parts + 1] = full
				added = added + 1
			end
		end
	end
	if added == 0 then return str, false end
	local out = table.concat(parts, ";")
	-- the town's own cap: its oldest entries out (one rebuild)
	local starts = townStarts(out, t, townN)
	local drop = #starts - townN
	if drop > 0 then
		local keep, from = {}, 1
		for i = 1, drop do
			local s0 = starts[i]
			local e0 = out:find(";", s0, true)
			if s0 > from then keep[#keep + 1] = out:sub(from, s0 - 1) end
			from = e0 and (e0 + 1) or (#out + 1)
		end
		keep[#keep + 1] = out:sub(from)
		out = table.concat(keep):gsub("^;+", ""):gsub(";;+", ";"):gsub(";+$", "")
	end
	return M.trim(out, max), true
end

--- A clean copy of the saved record (`pv`): the string cut to TOTAL_MAX (no parse: a load costs nothing), the per-town
--- tables of the first dev build (2026-10-19) converted once (at most CONVERT_MAX entries, by year), or nil.
function M.norm(raw)
	if type(raw) == "string" then
		if raw == "" then return nil end
		local s = M.trim(raw, M.TOTAL_MAX)
		if s == "" then return nil end
		return s
	end
	if type(raw) ~= "table" then return nil end
	local all, n, towns = {}, 0, 0
	for k, v in pairs(raw) do
		towns = towns + 1
		if towns > 1000 or n >= M.CONVERT_MAX then break end
		local t = tonumber(k)
		if t and type(v) == "string" then
			local c = 0
			for part in v:gmatch("[^;]+") do
				c = c + 1
				if c > M.ENTRIES_MAX or n >= M.CONVERT_MAX then break end
				local f = {}
				for x in part:gmatch("[^,]+") do
					f[#f + 1] = x
					if #f > 11 then break end
				end
				-- (v1: edge, src, trig, seq, year, x0, y0, xm, ym, x1, y1)
				local id, x0, y0, xm, ym, x1, y1 = tonumber(f[1]), tonumber(f[6]), tonumber(f[7]), tonumber(f[8]),
					tonumber(f[9]), tonumber(f[10]), tonumber(f[11])
				if #f == 11 and id and x0 and y0 and xm and ym and x1 and y1 then
					local e = M.entry({ id = id, src = f[2], trig = f[3], year = tonumber(f[5]), p0 = { x0, y0 },
						p1 = { x1, y1 } })
					if e then
						-- (the middle as stored: its offset from the chord's)
						local fe = {}
						for x in e:gmatch("[^,]+") do fe[#fe + 1] = x end
						fe[9], fe[10] = num(xm - (x0 + x1) / 2), num(ym - (y0 + y1) / 2)
						n = n + 1
						all[n] = { y = tonumber(f[5]) or 0, i = n, s = floor(t) .. "," .. table.concat(fe, ",") }
					end
				end
			end
		end
	end
	if n == 0 then return nil end
	table.sort(all, function(a, b) if a.y ~= b.y then return a.y < b.y end return a.i < b.i end)
	local parts = {}
	for i = 1, n do parts[i] = all[i].s end
	local s = M.trim(table.concat(parts, ";"), M.TOTAL_MAX)
	if s == "" then return nil end
	return s
end

--- The saved record with town t's new entries (ot_saved.applyProv). pv: the normalized record (a string) or nil.
--- Returns pv, changed.
function M.add(pv, t, entries)
	if tonumber(t) == nil or type(entries) ~= "table" or #entries == 0 then return pv, false end
	local s, changed = M.append(pv, t, entries)
	if not changed then return pv, false end
	if s == "" then return nil, true end
	return s, true
end

--- The record's size: chars, entries (a count of separators: cheap, for the TICKCOST line).
function M.size(pv)
	if type(pv) ~= "string" or pv == "" then return 0, 0 end
	local _, seps = pv:gsub(";", ";")
	return #pv, seps + 1
end

--- The entry of edge id in the record pv: entry, town key; nil when none (the newest, when a game reused the id).
function M.find(pv, id)
	id = tonumber(id)
	if id == nil or type(pv) ~= "string" then return nil end
	local best = nil
	for _, r in ipairs(M.parse(pv)) do
		if r.id == id then best = r end
	end
	if best then return best, tostring(best.town) end
	return nil
end

local function segDist(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local t = 0
	if l2 > 1e-9 then t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / l2)) end
	local cx, cy = ax + dx * t, ay + dy * t
	return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

--- Distance from (x, y) to an entry's two chords (end, middle, end).
function M.dist(r, x, y)
	local p = r.pts
	return math.min(segDist(x, y, p[1][1], p[1][2], p[2][1], p[2][2]), segDist(x, y, p[2][1], p[2][2], p[3][1], p[3][2]))
end

--- The entry nearest (x, y) within maxD (default NEAR_M) in the record pv: entry, town key, distance; nil when none.
function M.nearest(pv, x, y, maxD)
	x, y, maxD = tonumber(x), tonumber(y), tonumber(maxD) or M.NEAR_M
	if x == nil or y == nil or type(pv) ~= "string" then return nil end
	local best, bd = nil, maxD
	for _, r in ipairs(M.parse(pv)) do
		local d = M.dist(r, x, y)
		if d <= bd then best, bd = r, d end
	end
	if best == nil then return nil end
	return best, tostring(best.town), bd
end

--- A record entry as words: "plain/ln" -> "plan piece, cross lane".
function M.describe(r)
	if r == nil then return "-" end
	local src = tostring(r.src or "-")
	local kind, piece = src:match("^([^/]+)/?(.*)$")
	local words = kind or src
	if kind and kind:sub(1, 3) == "nm:" then
		local k = kind:sub(4)
		local corner = k:sub(-1) == "c"
		if corner then k = k:sub(1, -2) end
		words = "near-miss join (" .. k .. (corner and ", corner" or "") .. ")"
	elseif kind and kind:sub(1, 2) == "m:" then
		words = "motif " .. kind:sub(3)
	elseif kind == "plain" then
		words = "plan piece"
	end
	if piece and piece ~= "" then words = words .. ", " .. (M.PIECES[piece] or ("key " .. piece)) end
	return string.format("%s, year %s, trigger %s", words, tostring(r.year or "-"), tostring(r.trig or "-"))
end

---------------------------------------------------------------------------
-- console lookup (engine reads, every one pcall-guarded; read-only)

local function out(lines, l)
	lines[#lines + 1] = "[SQOT] WHO " .. l
	print("[SQOT] WHO " .. l)
end

local function gameScriptNative()
	local e = api.engine.system.gameScriptSystem.getEntityForGameScript(M.GS_NAME)
	if e == nil or e < 0 then return nil end
	local gs = api.engine.getComponent(e, api.type.ComponentType.GAME_SCRIPT)
	if gs == nil then return nil end
	return gs.state_native
end

--- The saved record (`pv`) from our game script's state (state_native; the town window card's way): the record string,
--- or nil; second value: why not ("no game script", "no record", or the error).
function M.savedPv()
	local ok, pv = pcall(function()
		local st = gameScriptNative()
		if st == nil then return "no game script state" end
		local v = st:find("pv")
		if v == nil then return nil end
		if type(v) ~= "string" and type(v) ~= "table" then v = v:asTable() end
		return { v = v }
	end)
	if not ok then return nil, tostring(pv) end
	if type(pv) == "string" then return nil, pv end
	if pv == nil then return nil, "no record on this save yet" end
	if type(pv.v) == "table" then return M.norm(pv.v), nil end   -- (the 2026-10-19 dev layout)
	return pv.v, nil
end

--- The saved game-street locks (`gx`, §67) as { [edge id] = town key }, or {}.
function M.savedGlocks()
	local ok, gx = pcall(function()
		local st = gameScriptNative()
		if st == nil then return nil end
		local v = st:find("gx")
		if v == nil then return nil end
		if type(v) == "table" then return v end
		return v:asTable()
	end)
	local set = {}
	if ok and type(gx) == "table" then
		local towns = 0
		for k, list in pairs(gx) do
			towns = towns + 1
			if towns > 2000 then break end
			if type(list) == "table" then
				for i = 1, math.min(#list, 4000) do
					local id = tonumber(list[i])
					if id then set[id] = k end
				end
			end
		end
	end
	return set
end

--- A street edge's ends, Hermite middle and locked flag ({ id, p0, pm, p1, locked, street }), or nil.
function M.edgeInfo(id)
	local ok, r = pcall(function()
		local be = api.engine.getComponent(id, api.type.ComponentType.BASE_EDGE)
		if be == nil then return nil end
		local p0, p1, t0, t1 = be.position0, be.position1, be.tangent0, be.tangent1
		return { id = id, p0 = { p0.x, p0.y }, p1 = { p1.x, p1.y },
			pm = { (p0.x + p1.x) / 2 + (t0.x - t1.x) / 8, (p0.y + p1.y) / 2 + (t0.y - t1.y) / 8 },
			locked = be.roadDevelopmentLocked == true,
			street = api.engine.getComponent(id, api.type.ComponentType.BASE_EDGE_STREET) ~= nil }
	end)
	if ok then return r end
	return nil
end

--- The street edge nearest (x, y) by its curve within PICK_R: id, its info; nil and (found, nearest distance) when none.
--- The octree circle is SEARCH_R: it matches an edge by its middle (findings roads.md), so a long street under the
--- cursor has its middle well outside PICK_R (2026-10-20_0228_sqot-sqrl: "no street within 40 m" on a street).
function M.nearestEdge(x, y)
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), M.SEARCH_R,
		api.type.ComponentType.BASE_EDGE)
	if not ok or list == nil then return nil, 0, nil, tostring(list) end
	local best, bi, bd = nil, nil, math.huge
	local n = math.min(#list, M.EDGES_MAX)
	for i = 1, n do
		local info = M.edgeInfo(list[i])
		if info and info.street then
			local d = M.dist({ pts = { info.p0, info.pm, info.p1 } }, x, y)
			if d < bd then best, bi, bd = list[i], info, d end
		end
	end
	if best == nil or bd > M.PICK_R then return nil, n, best and bd or nil end
	return best, bi
end

local function whoBody(lines, a, b)
	local x, y, id = nil, nil, nil
	if type(a) == "number" and type(b) == "number" then x, y = a, b
	elseif type(a) == "number" then id = floor(a)
	else
		local ok, p = pcall(function() return api.gui.mouse.getTerrainPosition() end)
		if ok and p then x, y = p.x, p.y end
	end
	if id == nil then
		if x == nil then
			out(lines, "no point: hover the map, or pass an edge id / x, y")
			return
		end
		local found, n, nd, err = M.nearestEdge(x, y)
		if found == nil then
			out(lines, string.format("no street within %d m of %.0f,%.0f (%d edges within %d m%s%s)", M.PICK_R, x, y,
				n or 0, M.SEARCH_R, nd and string.format(", the nearest street %.0f m", nd) or "",
				err and ("; octree error " .. err) or ""))
			return
		end
		id = found
	end
	local info = M.edgeInfo(id)
	if info == nil then
		out(lines, "edge=" .. tostring(id) .. " is no edge (gone, or not an edge entity)")
		return
	end
	local where = string.format("edge=%d a=%.0f,%.0f b=%.0f,%.0f locked=%s", id, info.p0[1], info.p0[2], info.p1[1],
		info.p1[2], tostring(info.locked))
	local pv, why = M.savedPv()
	local r, town = M.find(pv, id)
	if r then
		out(lines, where .. " ours=yes town=" .. tostring(town) .. " src=" .. tostring(r.src) .. " (" .. M.describe(r) .. ")")
		return
	end
	local rn, tn, d = M.nearest(pv, info.pm[1], info.pm[2], M.NEAR_M)
	if rn and M.dist(rn, info.p0[1], info.p0[2]) <= M.NEAR_M * 2 and M.dist(rn, info.p1[1], info.p1[2]) <= M.NEAR_M * 2 then
		out(lines, where .. string.format(" ours=likely town=%s src=%s (%s; recorded as edge %d, %.0f m off: split or rebuilt since)",
			tostring(tn), tostring(rn.src), M.describe(rn), rn.id, d))
		return
	end
	local _, entries = M.size(pv)
	local gx = M.savedGlocks()
	if gx[id] then
		out(lines, where .. " ours=no town=" .. tostring(gx[id]) .. " (a game street the mod rebuilt locked, §67)")
	elseif info.locked then
		out(lines, where .. " ours=probably (locked: the mod's lock, but no record: built before provenance records,"
			.. " 2026-10-19, or older than the record's newest " .. entries .. " entries)")
	else
		out(lines, where .. " ours=no (no record, not locked: the game's own growth or the town's original layout; or an"
			.. " open tip the mod built before the records began, 2026-10-19" .. (pv == nil and ("; " .. tostring(why)) or "")
			.. ")")
	end
end

--- Console: who built this street? who() the street under the cursor, who(edgeId), who(x, y). Prints "[SQOT] WHO"
--- lines (always at least one: an error prints its reason) and returns them joined.
function M.who(a, b)
	local lines = {}
	local ok, err = pcall(whoBody, lines, a, b)
	if not ok then out(lines, "error " .. tostring(err)) end
	if #lines == 0 then out(lines, "no answer (please report)") end
	return table.concat(lines, "\n")
end

return M
