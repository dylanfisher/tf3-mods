-- DEV ONLY (never upload): Roundabouts lane probe, pure logic (no api.* calls), unit-tested in
-- tests/square_roundabouts_lanes_probe/. Used by lanes.script.lua.
--
-- Everything here works on plain tables or on the engine's userdata through field access and
-- ipairs only (as mods/square_full_refund/content/refund/refund.script.tl reads build-event
-- proposals), so the same code runs offline and in game.
--
-- Log format: one line per fact, "[SQRB-LANES] KIND k=v k=v ...". Values never contain spaces
-- (L.clean), lists are joined with "," and sub-fields with ":". plans/square_roundabouts/PHASE6.md
-- documents every KIND.

local L = {}

L.MOD_ID = "square_roundabouts_lanes_probe"
L.PREFIX = "[SQRB-LANES]"

-- Mod params (mod.json "params"; values are 1-based indices, docs/findings.md).
L.KEYS = { write = "sqrb_lanes_write" }
L.VALUES = { write = { false, true } }
L.DEFAULTS = { write = 1 }

-- Constructions we follow: file name fragment -> entry name. The vanilla roundabout is followed
-- too (baseline for the engine's automatic connections). Names as the engine reports them, e.g.
-- "/infrastructure/street_construction/square_roundabouts_magic.con" (stdout.txt, Phase 5 probe).
L.ENTRIES = {
	{ "street_construction/square_roundabouts_magic.con", "magic" },
	{ "street_construction/square_roundabouts_channel.con", "channel" },
	{ "street_construction/square_roundabouts_interchange.con", "interchange" },
	{ "street_construction/square_roundabouts.con", "main" },
	{ "street_construction/roundabout.con", "vanilla" },
}

-- Ring templates of the main entry (PLAN.md "Decisions", Phase 3 "Tram"): one-way, so a ring node
-- has one incoming and one outgoing ring segment. Matched as substrings (tram variants included).
L.RING_TEMPLATES = { "highway_new_small", "town_new_one_way_small", "town_new_one_way_medium" }

-- Search circle around a placed construction (m).
L.RADIUS_DEFAULT = 150
L.RADIUS_MIN = 40
L.RADIUS_MAX = 450
L.RADIUS_MARGIN = 15

--- Settings from this mod's raw mod params (nil or a table of 1-based indices).
function L.fromModParams(raw)
	raw = type(raw) == "table" and raw or {}
	local cfg = {}
	for name, key in pairs(L.KEYS) do
		local list = L.VALUES[name]
		local i = tonumber(raw[key])
		if i == nil or i < 1 or i > #list or i ~= math.floor(i) then i = L.DEFAULTS[name] end
		cfg[name] = list[i]
	end
	return cfg
end

--- A value safe for one log token: no whitespace, at most 160 characters.
function L.clean(v)
	local s = tostring(v)
	s = s:gsub("%s+", "_")
	if #s > 160 then s = s:sub(1, 157) .. "..." end
	return s
end

function L.num(x)
	if type(x) ~= "number" then return "nil" end
	if x == math.floor(x) and math.abs(x) < 1e9 then return string.format("%d", x) end
	return string.format("%.1f", x)
end

--- "[SQRB-LANES] KIND k=v ..." from an ordered list of {key, value} pairs.
function L.line(kind, fields)
	local parts = { L.PREFIX, kind }
	for _, kv in ipairs(fields or {}) do
		parts[#parts + 1] = kv[1] .. "=" .. L.clean(kv[2])
	end
	return table.concat(parts, " ")
end

--- Parses a line written by L.line: kind, {key = value}, ordered keys. nil if not ours.
function L.parse(text)
	local rest = text:match("%[SQRB%-LANES%] (.*)$")
	if not rest then return nil end
	local kind, body = rest:match("^(%S+)%s*(.*)$")
	local fields, order = {}, {}
	for k, v in body:gmatch("([%w_]+)=(%S*)") do
		fields[k] = v
		order[#order + 1] = k
	end
	return kind, fields, order
end

--- Which of our entries a construction file name is ("main", "magic", ...), or nil.
function L.entryOf(fileName)
	if type(fileName) ~= "string" then return nil end
	for _, e in ipairs(L.ENTRIES) do
		if fileName:find(e[1], 1, true) then return e[2] end
	end
	return nil
end

function L.isRingTemplate(tpl)
	if type(tpl) ~= "string" then return false end
	for _, t in ipairs(L.RING_TEMPLATES) do
		if tpl:find(t, 1, true) then return true end
	end
	return false
end

--- Short template name for logs: "town_new_small" from "street/town_new_small.lua".
function L.shortTemplate(tpl)
	if type(tpl) ~= "string" then return tostring(tpl) end
	local s = tpl:match("([^/:]+)$") or tpl
	return (s:gsub("%.lua$", ""))
end

--- Count of an engine list (Lua array or userdata vector), nil-safe.
function L.count(list)
	if list == nil then return 0 end
	local n = 0
	for _ in ipairs(list) do n = n + 1 end
	return n
end

--- One lane connection as "s0:l0>s1:l1:RT" (R = withRoad, T = withTram, "-" for false).
function L.connText(c)
	return string.format("%s:%s>%s:%s:%s%s", tostring(c.segment0), tostring(c.lane0),
		tostring(c.segment1), tostring(c.lane1), c.withRoad and "R" or "-", c.withTram and "T" or "-")
end

--- Every connection of a list, sorted, joined with ",". Used to compare configs over time.
function L.connsText(list)
	local out = {}
	for _, c in ipairs(list or {}) do out[#out + 1] = L.connText(c) end
	table.sort(out)
	return table.concat(out, ",")
end

--- Transport modes of a lane: the keys that are true, sorted ("" if none or unreadable).
function L.modesText(modes)
	local out = {}
	if type(modes) == "table" then
		for k, v in pairs(modes) do
			if v then out[#out + 1] = tostring(k) end
		end
	end
	table.sort(out)
	return table.concat(out, "+")
end

--- A segment's lane configs as "F|B:width:offset:modes" joined with ",".
function L.lanesText(laneConfigs)
	local out = {}
	for _, lc in ipairs(laneConfigs or {}) do
		local modes = ""
		local okModes, m = pcall(function() return lc.transportModes end)
		if okModes then
			local okText, t = pcall(L.modesText, m)
			if okText then modes = t end
		end
		out[#out + 1] = string.format("%s:%s:%s:%s", lc.forward and "F" or "B", L.num(lc.width),
			L.num(lc.offset), modes)
	end
	return table.concat(out, ",")
end

--- Translation of a Mat4f or a 16-number table (column-major: 13, 14, 15).
function L.translation(transf)
	if transf == nil then return nil end
	local ok, x, y, z = pcall(function() return transf[13], transf[14], transf[15] end)
	if not ok or type(x) ~= "number" or type(y) ~= "number" then return nil end
	return x, y, z
end

--- Centre and radius of the area to scan for a placed construction.
-- bbox: {min = {x, y}, max = {x, y}} or nil; transf: the construction's Mat4f or nil.
-- Returns x, y, r, source ("bbox" | "transf"), or nil if neither is usable.
function L.searchCircle(bbox, transf)
	local ok, x0, y0, x1, y1 = pcall(function()
		return bbox.min.x, bbox.min.y, bbox.max.x, bbox.max.y
	end)
	if ok and type(x0) == "number" and type(x1) == "number" and x1 > x0 and y1 > y0 then
		local dx, dy = x1 - x0, y1 - y0
		local r = math.sqrt(dx * dx + dy * dy) / 2 + L.RADIUS_MARGIN
		if r < L.RADIUS_MIN then r = L.RADIUS_MIN end
		if r > L.RADIUS_MAX then r = L.RADIUS_MAX end
		return (x0 + x1) / 2, (y0 + y1) / 2, r, "bbox"
	end
	local tx, ty = L.translation(transf)
	if tx ~= nil then return tx, ty, L.RADIUS_DEFAULT, "transf" end
	return nil
end

--- Fallback circle around a list of points {x, y} (added nodes of a build without a construction
-- we know, e.g. if the engine reports the dissolved roundabout only as streets). nil if empty.
function L.circleFromPoints(points)
	local x0, y0, x1, y1 = nil, nil, nil, nil
	for _, p in ipairs(points or {}) do
		if type(p.x) == "number" and type(p.y) == "number" then
			if x0 == nil then
				x0, y0, x1, y1 = p.x, p.y, p.x, p.y
			else
				if p.x < x0 then x0 = p.x end
				if p.y < y0 then y0 = p.y end
				if p.x > x1 then x1 = p.x end
				if p.y > y1 then y1 = p.y end
			end
		end
	end
	if x0 == nil then return nil end
	local x, y, r = L.searchCircle({ min = { x = x0 - 1, y = y0 - 1 }, max = { x = x1 + 1, y = y1 + 1 } }, nil)
	return x, y, r
end

--- Sorted "key:value" list of a construction's params, only the keys starting with "sqrb_"
-- plus the vanilla roundabout's few (anything else would flood the log).
function L.paramsText(params)
	local out = {}
	if type(params) ~= "table" then return "" end
	for k, v in pairs(params) do
		local key = tostring(k)
		if key:sub(1, 5) == "sqrb_" or key == "type" or key == "radius" or key == "streetType" or key == "lanes" then
			if type(v) ~= "table" then out[#out + 1] = key .. ":" .. tostring(v) end
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

--- Generic shape of a build-event param: "1:userdata,2:userdata,3:table,4:boolean".
function L.shapeText(param)
	if type(param) ~= "table" then return type(param) end
	local out = {}
	for k, v in pairs(param) do out[#out + 1] = tostring(k) .. ":" .. type(v) end
	table.sort(out)
	return table.concat(out, ",")
end

--- First n entries of a list of numbers/ids as "a,b,c...(N)".
function L.idsText(list, n)
	n = n or 8
	local out, total = {}, 0
	for _, v in ipairs(list or {}) do
		total = total + 1
		if total <= n then out[#out + 1] = tostring(v) end
	end
	local s = table.concat(out, ",")
	if total > n then s = s .. "...(" .. total .. ")" end
	return s
end

---------------------------------------------------------------------------
-- Write experiment: which connections to remove

--- Picks one ring junction node and the connections that lead from the ring into an arm out of
-- the ring's highest-indexed incoming lane.
--
-- Why the highest index: LaneConnection.lane0 is "zero-based, from left to right when looking
-- from the Node to segment0" (api/tealdef/api/type.d.tl:1197-1213). Standing on the node and
-- looking back up the incoming ring segment, vehicles drive towards you; with right-hand traffic
-- (anticlockwise ring, the default) their left = the ring centre side = your right, so the inner
-- ring lane should be the highest index. That is the guess the probe tests; the log names the
-- lane it removed so the Crossing Tool shows whether it was the inner one.
--
-- nodes: list of { node = id, segs = { {id, tpl}, ... }, conns = { LaneConnection-like } }.
-- Returns { node, lane0, remove = {conn...}, keep = {conn...}, ringIn, arm } or nil, reason.
function L.chooseExperiment(nodes)
	local best = nil
	for _, n in ipairs(nodes or {}) do
		local ring, other = {}, {}
		local nRing, nOther = 0, 0
		for _, s in ipairs(n.segs or {}) do
			if L.isRingTemplate(s.tpl) then
				ring[s.id] = true
				nRing = nRing + 1
			else
				other[s.id] = true
				nOther = nOther + 1
			end
		end
		if nRing == 2 and nOther >= 1 then
			-- connections ring -> arm by road, grouped by incoming lane
			local maxLane, lanes, ringIn, arm = nil, {}, nil, nil
			local distinct = 0
			for _, c in ipairs(n.conns or {}) do
				if ring[c.segment0] and other[c.segment1] and c.withRoad then
					if not lanes[c.lane0] then
						lanes[c.lane0] = true
						distinct = distinct + 1
					end
					if maxLane == nil or c.lane0 > maxLane then
						maxLane, ringIn, arm = c.lane0, c.segment0, c.segment1
					end
				end
			end
			if distinct >= 2 and (best == nil or n.node < best.node) then
				local remove, keep = {}, {}
				for _, c in ipairs(n.conns) do
					if ring[c.segment0] and other[c.segment1] and c.withRoad and c.lane0 == maxLane then
						remove[#remove + 1] = c
					else
						keep[#keep + 1] = c
					end
				end
				best = { node = n.node, lane0 = maxLane, remove = remove, keep = keep, ringIn = ringIn, arm = arm }
			end
		end
	end
	if best == nil then
		return nil, "no node with 2 ring segments, an arm and ring->arm connections from 2+ lanes (1-lane ring?)"
	end
	return best
end

--- userModifiedLaneConnections mode for the k-th write of a session: odd writes set it to true,
-- even writes keep the value read from the node. So one test round answers whether it matters.
function L.userModifiedMode(k)
	if k % 2 == 1 then return "set_true" end
	return "keep"
end

return L
