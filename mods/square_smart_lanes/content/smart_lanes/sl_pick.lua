-- Smart Lanes tool (Phase 2): pure helpers for picking and the status texts (no api.* calls),
-- unit-tested in tests/square_smart_lanes/test_pick.lua.
--
-- Picking follows move_it (.cache/subscribed/move_it/content/tools/move_it/move_it.script.tl:4513-4560):
-- the Selector mostly reports the street edge next to a junction (node hit boxes are tiny), so an
-- edge hit with the cursor near one of its ends is promoted to that end node. The snap radius is a
-- third of the segment length, capped (move_it: 15 m for streets), so the middle of a segment stays
-- the segment.

local P = {}

P.SNAP_CAP = 15.0 -- m, move_it SNAP_RADIUS_M (move_it.script.tl:146)

local function dist(ax, ay, bx, by)
	local dx, dy = ax - bx, ay - by
	return math.sqrt(dx * dx + dy * dy)
end

--- Promotes an edge hit to an end node.
-- cursor {x, y}; edge {node0, node1, p0 = {x, y}, p1 = {x, y}} (BaseEdge.position0/1).
-- Returns node (or nil), the distance to the nearer end, the snap radius.
function P.promote(cursor, edge, cap)
	cap = cap or P.SNAP_CAP
	local d0 = dist(cursor.x, cursor.y, edge.p0.x, edge.p0.y)
	local d1 = dist(cursor.x, cursor.y, edge.p1.x, edge.p1.y)
	local r = math.min(cap, dist(edge.p0.x, edge.p0.y, edge.p1.x, edge.p1.y) / 3)
	if d0 < r and d0 <= d1 then return edge.node0, d0, r end
	if d1 < r then return edge.node1, d1, r end
	return nil, math.min(d0, d1), r
end

-- Colours for the connection overlay, one per outgoing segment (RGBA 0..1).
P.PALETTE = {
	{ 0.20, 0.80, 0.75, 1 }, -- teal
	{ 1.00, 0.62, 0.15, 1 }, -- orange
	{ 0.55, 0.45, 1.00, 1 }, -- violet
	{ 0.95, 0.30, 0.45, 1 }, -- pink
	{ 0.55, 0.85, 0.25, 1 }, -- green
	{ 0.30, 0.60, 1.00, 1 }, -- blue
}

--- Palette index (1-based) per connection: connections into the same segment share a colour;
-- segments get colours in ascending id order, so the colours stay stable while the player clicks.
-- conns: list of {segment0, lane0, segment1, lane1, ...}. Returns { [i] = paletteIndex }.
function P.colorIndices(conns)
	local segs, seen = {}, {}
	for _, c in ipairs(conns or {}) do
		if not seen[c.segment1] then
			seen[c.segment1] = true
			segs[#segs + 1] = c.segment1
		end
	end
	table.sort(segs)
	local idx = {}
	for i, s in ipairs(segs) do idx[s] = ((i - 1) % #P.PALETTE) + 1 end
	local out = {}
	for i, c in ipairs(conns or {}) do out[i] = idx[c.segment1] end
	return out
end

--- Key of a pick target (to notice changes): "node:<id>", "ring:<key>" or "none".
function P.targetKey(t)
	if t == nil then return "none" end
	if t.kind == "node" then return "node:" .. tostring(t.node) end
	if t.kind == "ring" then return "ring:" .. tostring(t.ringKey) end
	return tostring(t.kind)
end

local function plural(n, one, many)
	return tostring(n) .. " " .. (n == 1 and one or many)
end

--- One-line description of a pick target (the cursor tooltip and the status head).
-- t: { kind = "node" | "ring", node, ringKey, ringLanes, junctions, roads, conns,
--      nodeKind = "arm" | "plain" | "skip" (on a ring) | "slip", exits, entries,
--      slipShape ("diverge" | "merge" | "diverge+merge"), slipLanes, slipSummary, slipReason }
function P.describe(t)
	if t == nil then return "Nothing selected" end
	if t.kind == "ring" then
		return string.format("Roundabout %s: %s, %s", tostring(t.ringKey), plural(t.ringLanes or 0, "lane", "lanes"),
			plural(t.junctions or 0, "arm", "arms"))
	end
	if t.ringKey == nil and t.slipShape ~= nil then
		return string.format("Slip-lane junction: %s, %s", t.slipShape, plural(t.slipLanes or 0, "lane", "lanes"))
	end
	local s = "Junction " .. tostring(t.node)
	if t.ringKey ~= nil then
		s = s .. string.format(" on roundabout %s (%s, %s)", tostring(t.ringKey),
			plural(t.ringLanes or 0, "lane", "lanes"), plural(t.junctions or 0, "arm", "arms"))
	else
		s = s .. " (" .. plural(t.roads or 0, "road", "roads") .. ", not a roundabout)"
	end
	return s
end

--- Second line: connections at the junction, exits / entries when on a ring.
function P.detail(t)
	if t == nil then return "Click a junction, or a roundabout between its junctions" end
	if t.kind == "ring" then return "Apply to roundabout or Reset; click near a junction to pick one" end
	local parts = { plural(t.conns or 0, "lane connection", "lane connections") }
	if t.ringKey ~= nil and t.nodeKind == "arm" then
		parts[#parts + 1] = string.format("%d exit, %d entry lanes", t.exits or 0, t.entries or 0)
	elseif t.ringKey ~= nil and t.nodeKind == "skip" then
		parts[#parts + 1] = "left alone (" .. tostring(t.reason) .. ")"
	elseif t.ringKey == nil and t.slipShape ~= nil then
		table.insert(parts, 1, t.slipSummary or t.slipShape)
	elseif t.ringKey == nil and t.slipReason ~= nil then
		parts[#parts + 1] = "not handled (" .. tostring(t.slipReason) .. ")"
	elseif t.ringKey == nil then
		parts[#parts + 1] = "not handled yet"
	end
	return table.concat(parts, ", ")
end

--- Toolbar status chip: { head, detail }.
-- sel: the selected target (nil = none); _layoutName: unused since the tool has one layout;
-- result: last result text or nil.
function P.status(sel, _layoutName, result)
	local head = P.describe(sel)
	local detail
	if result ~= nil and result ~= "" then
		detail = result
	elseif sel ~= nil then
		detail = P.detail(sel)
	else
		detail = "Click a junction or a roundabout"
	end
	return { head = head, detail = detail }
end

--- Lane status badge (the toolbar's second chip, the hover tooltip, PICK badge=..).
-- info: { kind = "ring" | "node" (ring junction) | "slip" | "na", total = junctions the tool
-- handles (skipped ones not counted), smart = how many equal what Apply would write,
-- default = how many equal the engine-default model (nil: no model, slip nodes) }.
-- Returns { key = "smart" | "default" | "custom" | "partial" | "na", label, class } where class is
-- the game's global TextView colour class (default.css.lua "!positive" / "!warning") or nil.
-- Smart wins over default (a 1-lane ring junction with one entry lane is both).
function P.badge(info)
	local total = info and info.total or 0
	if info == nil or info.kind == "na" or total <= 0 then
		return { key = "na", label = "Not handled", class = nil }
	end
	local smart, default = info.smart or 0, info.default
	if smart >= total then
		if default ~= nil and default >= total then
			return { key = "smart", label = "Smart lanes (= game default)", class = "positive" }
		end
		return { key = "smart", label = "Smart lanes", class = "positive" }
	end
	if default ~= nil and default >= total then
		return { key = "default", label = "Game default", class = nil }
	end
	if smart > 0 and total > 1 then
		return { key = "partial", label = string.format("Smart lanes on %d of %d junctions", smart, total), class = "warning" }
	end
	if info.kind == "slip" then
		-- no engine-default model at slip nodes: never claim "changed by hand" there
		return { key = "custom", label = "Custom", class = nil }
	end
	return { key = "custom", label = "Custom lanes", class = "warning" }
end

-- Badge chip text with nothing selected.
P.BADGE_NONE = { key = "none", label = "Lane status", class = nil }

--- Rate limiter for log lines: true when `key` differs from the last logged key and at least
-- `gap` seconds passed since the last true. A refused change is not remembered, so the caller's
-- next try (next hover frame) logs it once the gap is over. lim: table {key, at}; now: seconds.
function P.allow(lim, key, now, gap)
	if lim.key == key then return false end
	if lim.at ~= nil and now - lim.at < gap then return false end
	lim.key, lim.at = key, now
	return true
end

return P
