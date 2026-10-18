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

--- Key of a pick target (to notice changes): "node:<id>", "ring:<key>", "street:<clicked segment>"
-- (a plain click: the junctions at its ends), "street+:<clicked segment>" (Shift+click: followed
-- further), "multi:<id>,<id>,.." (Shift+click selection, PHASE7.md step 5b) or "none".
function P.targetKey(t)
	if t == nil then return "none" end
	if t.kind == "node" then return "node:" .. tostring(t.node) end
	if t.kind == "ring" then return "ring:" .. tostring(t.ringKey) end
	if t.kind == "street" then return (t.follow and "street+:" or "street:") .. tostring(t.seg) end
	if t.kind == "multi" then
		local ids = {}
		for i, n in ipairs(t.junctionNodes or {}) do ids[i] = tostring(n) end
		return "multi:" .. table.concat(ids, ",")
	end
	return tostring(t.kind)
end

-- Display texts go through _() when they are built (this module runs in the tool's GUI Lua state,
-- where _() translates at once; the tests fake it). Singular / plural pairs are whole format strings.
local function plural(n, one, many)
	return string.format(n == 1 and one or many, n)
end

local function lanesText(n) return plural(n, _("%d lane"), _("%d lanes")) end
local function armsText(n) return plural(n, _("%d arm"), _("%d arms")) end

--- Why a junction is not handled, for players: the skip reasons of sl_ring R.nodeView, sl_slip and
-- sl_cross (log ids) as short phrases that fit after "not handled: ". Unknown ids get a generic phrase.
function P.reasonText(id)
	id = tostring(id)
	local n = tonumber(id:match("^roads_(%d+)$"))
	if n ~= nil and n >= 5 then return string.format(_("%d roads meet (at most 4)"), n) end
	if id:match("^one_way_%d+$") then id = "one_way" end
	local labels = {
		bus_lane_ring = _("the ring has a bus lane"),
		bus_road = _("a road has only bus lanes"),
		mixed_sides = _("the roads drive on different sides"),
		no_two_way = _("one-way roads only"),
		one_way = _("one-way roads only"),
		one_way_dir = _("all its roads lead away, or all lead in"),
		no_exit = _("a road has no way on"),
		no_through = _("no road goes straight through"),
		ambiguous = _("two roads leave at almost the same angle"),
		no_lanes = _("a road has no lanes in one direction"),
		no_node = _("the junction is gone"),
		not_on_ring = _("not on the roundabout any more"),
		ring_lanes = _("the ring changes its lane count here"),
		multi_arm = _("two or more roads join here"),
	}
	return labels[id] or _("no rule for this junction shape")
end

--- Why a roundabout got no exit-only outer lane (sl_rules M.ringPlan reason ids), as a phrase.
function P.exitOnlyText(id)
	local labels = {
		one_lane_ring = _("the ring has one lane"),
		skip_node = _("one of its junctions is not handled"),
		no_exit = _("the roundabout has no exits"),
		narrow_exit = _("an exit has only one lane"),
		not_fresh = _("not every junction of it was set"),
	}
	return labels[tostring(id)] or _("the roundabout does not qualify")
end

--- Lane counts of a slip-lane junction (sl_slip S.streamCounts) as text, e.g.
-- "2 lanes: 1 straight on, 1 into the slip lane". "" without counts.
function P.slipText(counts)
	local parts = {}
	for _i, c in ipairs(counts or {}) do
		if c.shape == "diverge" then
			parts[#parts + 1] = string.format(_("%d lanes in: %d straight on, %d into the slip lane"), c.main, c.through, c.branch)
		elseif c.shape == "merge" then
			parts[#parts + 1] = string.format(_("%d straight on and %d from the slip lane into %d lanes"), c.through, c.branch, c.out)
		end
	end
	return table.concat(parts, "; ")
end

--- The Shift+click hint (street detail line, the hover tooltip with a selection).
function P.shiftHint()
	return _("Shift+click: add a junction or road")
end

--- One-line description of a pick target (the cursor tooltip and the status head).
-- t: { kind = "node" | "ring" | "street" | "multi", node, ringKey, ringLanes, junctions, roads, conns,
--      nodeKind = "arm" | "plain" | "skip" (on a ring) | "slip", exits, entries,
--      busKept (bus lanes kept as they are), slipShape ("diverge" | "merge" | "diverge+merge" | "crossroads" |
--      "t_junction" | "lane_drop" | "lane_gain" | "lane_drop+gain"), slipLanes, slipSummary, slipReason }
function P.describe(t)
	if t == nil then return _("Nothing selected") end
	if t.kind == "street" then return plural(t.junctions or 0, _("Street: %d junction"), _("Street: %d junctions")) end
	if t.kind == "multi" then return plural(t.junctions or 0, _("%d junction selected"), _("%d junctions selected")) end
	if t.kind == "ring" then
		return string.format(_("Roundabout: %s, %s"), lanesText(t.ringLanes or 0), armsText(t.junctions or 0))
	end
	if t.ringKey == nil and t.slipShape == "crossroads" then
		return string.format(_("Crossroads, %s"), lanesText(t.slipLanes or 0))
	end
	if t.ringKey == nil and t.slipShape == "t_junction" then
		return string.format(_("T-junction, %s"), lanesText(t.slipLanes or 0))
	end
	-- plain lane drops / gains (sl_slip case "D"); slipLanes: the wider side
	local drops = { lane_drop = _("Lane drop, %s"), lane_gain = _("Lane gain, %s"), ["lane_drop+gain"] = _("Lane drop and gain, %s") }
	if t.ringKey == nil and drops[t.slipShape] ~= nil then
		return string.format(drops[t.slipShape], lanesText(t.slipLanes or 0))
	end
	local slips = { diverge = _("Slip lane leaving the road, %s"), merge = _("Slip lane joining the road, %s"),
		["diverge+merge"] = _("Slip lanes leaving and joining, %s") }
	if t.ringKey == nil and t.slipShape ~= nil then
		return string.format(slips[t.slipShape] or _("Slip-lane junction, %s"), lanesText(t.slipLanes or 0))
	end
	if t.ringKey ~= nil then
		return string.format(_("Roundabout junction (%s, %s)"), lanesText(t.ringLanes or 0), armsText(t.junctions or 0))
	end
	-- the node id stays in the log (PICK node=..): players see the shape only
	return string.format(_("Junction, %s"), plural(t.roads or 0, _("%d road"), _("%d roads")))
end

--- Second line: connections at the junction, exits / entries when on a ring.
function P.detail(t)
	if t == nil then return _("Click a junction, or a roundabout between its junctions") end
	if t.kind == "ring" then
		-- a ring whose plain nodes between the arms change lanes (the mid-node spiral, sl_toolcore fillRing midNodes):
		-- Smart lanes and Reset set those too, and the Crossing Tool can't pick them
		if (t.midNodes or 0) > 0 then
			return _("Acts on the roundabout and its lane changes between the arms")
		end
		return _("Acts on the whole roundabout; click near a junction to pick one")
	end
	if t.kind == "street" then
		-- a plain click selects the two ends: tell how to get more (Shift+click: the street followed
		-- further, or more junctions and roads added, sl_toolcore C.select)
		if not t.follow then return P.shiftHint() end
		return _("Acts on every junction of the street")
	end
	if t.kind == "multi" then return _("Acts on every selected junction") end
	-- not handled: the reason alone (user 2026-10-17: "simple and friendly and obvious why"; no lane count, and no
	-- Smart lights line, which would only repeat it)
	local notHandled = nil
	if t.ringKey ~= nil and t.nodeKind == "skip" then
		notHandled = t.reason
	elseif t.ringKey == nil and t.slipShape == nil and t.slipReason ~= nil then
		notHandled = t.slipReason
	elseif t.ringKey == nil and t.slipShape == nil and (t.roads or 0) > 2 then
		notHandled = false -- the generic phrase
	end
	if notHandled ~= nil then return string.format(_("not handled: %s"), P.reasonText(notHandled or nil)) end
	local parts = { plural(t.conns or 0, _("%d lane connection"), _("%d lane connections")) }
	if t.ringKey ~= nil and t.nodeKind == "arm" then
		parts[#parts + 1] = string.format(_("%d exit, %d entry lanes"), t.exits or 0, t.entries or 0)
	elseif t.ringKey == nil and (t.slipShape == "crossroads" or t.slipShape == "t_junction"
		or t.slipShape == "lane_drop" or t.slipShape == "lane_gain" or t.slipShape == "lane_drop+gain") then
		-- the head names it; the lane summary is log material
	elseif t.ringKey == nil and t.slipShape ~= nil then
		local lanes = P.slipText(t.slipCounts)
		if lanes ~= "" then table.insert(parts, 1, lanes) end
	elseif t.ringKey == nil and (t.roads or 0) <= 2 then
		-- a bend or joint of one road (sl_slip kind "none"): nothing to set
		parts[#parts + 1] = _("no junction here")
	end
	-- a handled junction with a bus-only lane (sl_toolcore nodeTarget: t.busKept): its car lanes are set,
	-- its bus-lane connections stay as they are (Rules.mergeTram)
	if t.busKept and (t.nodeKind == "arm" or t.nodeKind == "slip") then parts[#parts + 1] = _("bus lanes kept as they are") end
	-- why Smart lights (the toolbar button, "Lights only" before 2026-10-16) has nothing to do at a lit crossroads / T-junction
	-- (sl_toolcore C.lightsStatus), in either mode: with the box on it is why Apply is gone
	local lights = P.lightsText(t.lights)
	if lights ~= nil then parts[#parts + 1] = string.format(_("Smart lights: %s"), lights) end
	return table.concat(parts, ", ")
end

--- Why Smart lights has nothing to do, as a phrase after "Smart lights: " (sl_toolcore C.lightsStatus result, or
-- { why = "shape" } that C.canInfo sets at a lit junction that is no crossroads / T-junction): nil when it would
-- change the phases (except "timing changed by hand": the plan's phases timed by the player) or without a traffic
-- light. Where no axis plan can be made the button is hidden and this says
-- why (PLAN.md "No classic fallback"): the junction's shape ("shape", plan_fail:no_axis_shape), else its lanes.
function P.lightsText(ls)
	if type(ls) ~= "table" then return nil end
	if ls.ok == true then
		-- the plan's phases: the badge says so ("| √ Smart lights", P.badgeChecks; user 2026-10-16), nothing here
		if ls.same then return nil end
		-- their greens re-timed by Re-time or Keep timing adjusted: the badge says Smart lights, this the timing
		if ls.timed then return _("timing adjusted") end
		-- the plan's phases, their greens changed in the Crossing window (not by us): Smart lights puts the plan's
		-- timing back, Reset the game's phases (both offered; user 2026-10-16)
		if ls.hand then return _("timing changed by hand") end
		return nil
	end
	-- no light (or no read): nothing (the light row is hidden)
	local why = tostring(ls.why)
	if why == "not_x" or why == "no_light" or why == "error" then return nil end
	if why == "shape" or why == "plan_fail:no_axis_shape" then return _("not for this junction shape") end
	-- plan_fail:<reason> (axis_extra, invalid_..), and a light whose phases or lanes can't be read for a plan
	-- (no_phases, no_config, stale_conns, crosswalks)
	return _("no phase plan for these lanes")
end

--- Toolbar status chip: { head, detail }.
-- sel: the selected target (nil = none); _layoutName: unused since the tool has one layout;
-- result: last result text or nil; acts: sl_toolcore C.actions() (nil: as with buttons shown).
-- A lane button (Smart lanes, Reset) that would change nothing is hidden (sl_toolcore C.buttons, user 2026-10-16);
-- with a selection where no button can act (acts.none) the detail line says so: the lane status badge under it tells
-- which state (Smart lanes, Game default, Not handled) and the detail line why a junction is not handled.
function P.status(sel, _layoutName, result, acts)
	local head = P.describe(sel)
	local detail
	if result ~= nil and result ~= "" then
		detail = result
	elseif sel ~= nil then
		detail = P.detail(sel)
		if type(acts) == "table" and acts.none then
			local lightsPhrase = P.lightsText(sel.lights) ~= nil
			local na = type(sel.badge) == "table" and sel.badge.key == "na"
			if sel.kind == "ring" or sel.kind == "multi" or (sel.kind == "street" and sel.follow) then
				-- "Acts on ..." would promise buttons that are not there
				detail = _("Nothing to change here")
			elseif sel.kind == "node" and not lightsPhrase and not na then
				-- a node: its lanes line stays (a not handled one already says why)
				detail = detail .. ", " .. _("nothing to change here")
			end
		end
	else
		detail = _("Click a junction or a roundabout")
	end
	return { head = head, detail = detail }
end

--- Lane status badge (the toolbar's second chip, the hover tooltip, PICK badge=..).
-- info: { kind = "ring" | "node" (ring junction) | "slip" | "street" | "multi" | "na", total = junctions the tool
-- handles (skipped ones not counted), smart = how many equal what Apply would write,
-- default = how many equal the engine-default model (nil: no model, slip nodes; a street or multi
-- selection with any junction without a model), kept = how many are kept by a Reset (sl_kept.lua; nil: 0),
-- oneLane = every handled junction's roads have one car lane each way (smart = default for that reason),
-- bus = a handled junction has a bus-only lane (its bus connections stay as they are) }.
-- Returns { key = "smart" | "default" | "kept" | "custom" | "partial" | "na", label, class } where class is
-- the game's global TextView colour class (default.css.lua "!positive" / "!warning") or nil.
-- Smart wins over default (a 1-lane ring junction with one entry lane is both).
function P.badge(info)
	local total = info and info.total or 0
	if info == nil or info.kind == "na" or total <= 0 then
		return { key = "na", label = _("Not handled"), class = nil }
	end
	local smart, default = info.smart or 0, info.default
	if smart >= total then
		if default ~= nil and default >= total then
			-- name the reason (a player found "= game default" puzzling at a 1-lane crossroads, 2026-10-14):
			-- one car lane per road leaves nothing to improve; bus lanes stay as they are
			if info.oneLane == true then
				if info.bus == true then
					return { key = "smart", label = _("Smart lanes = game default (one car lane per road; bus lanes kept)"), class = "positive" }
				end
				return { key = "smart", label = _("Smart lanes = game default (one car lane per road)"), class = "positive" }
			end
			return { key = "smart", label = _("Smart lanes (= game default)"), class = "positive" }
		end
		return { key = "smart", label = _("Smart lanes"), class = "positive" }
	end
	if default ~= nil and default >= total then
		-- every handled junction kept by a Reset (sl_kept.lua): the automatic pass leaves them alone
		if (info.kept or 0) >= total then return { key = "kept", label = _("Game default (locked)"), class = nil } end
		return { key = "default", label = _("Game default"), class = nil }
	end
	if smart > 0 and total > 1 then
		return { key = "partial", label = string.format(_("Smart lanes on %d of %d junctions"), smart, total), class = "warning" }
	end
	if info.kind == "slip" or ((info.kind == "street" or info.kind == "multi") and default == nil) then
		-- never claim "changed by hand" off a ring: slip-lane nodes and lane drops have no engine-default
		-- model, and crossroads / T-junctions (kind "slip" too) have one that does not match every shape
		-- the game builds (a town T on a bent main road, 2026-10-13 node 48723: game lanes, read as not
		-- default; TESTING.md K "T-junctions ... extrapolated"). Neutral label, no warning colour.
		-- kept by a Reset (a slip node's Reset writes back its lanes from before the Apply): as kept above
		if (info.kept or 0) >= total and smart == 0 then return { key = "kept", label = _("Game default (locked)"), class = nil } end
		return { key = "custom", label = _("Game or custom lanes"), class = nil }
	end
	return { key = "custom", label = _("Custom lanes"), class = "warning" }
end

--- The check mark of the badge (user 2026-10-16: "✓ Smart lanes | ✓ Smart lights"). "√" (U+221A), not "✓" (U+2713):
-- the GUI font Lato has √ but no ✓ / ✔ (fontTools on base/content/locale.zip, 2026-10-17; only Noto CJK has them,
-- and whether window text falls back to Noto is not known: docs/findings/gui.md).
P.CHECK = "\226\136\154" -- √

--- The badge with what is applied checked (user 2026-10-16): "√ Smart lanes" when the lanes are smart, and
-- " | √ Smart lights" after any label when the light phases are the Smart Lanes plan (lightsOn: exact, or re-timed by
-- Smart Lanes: sl_toolcore C.lightsStatus same / timed). Key and class (one colour for the whole line) stay; a fresh
-- table, b itself when nothing changes.
function P.badgeChecks(b, lightsOn)
	if type(b) ~= "table" or b.key == "none" or b.key == "na" then return b end
	local smart = b.key == "smart"
	if not smart and not lightsOn then return b end
	local label = b.label
	if smart then label = string.format("%s %s", P.CHECK, label) end
	if lightsOn then label = string.format("%s | %s %s", label, P.CHECK, _("Smart lights")) end
	return { key = b.key, label = label, class = b.class, lights = lightsOn or nil }
end

-- Badge chip with nothing selected (translated when called).
function P.badgeNone()
	return { key = "none", label = _("Lane status"), class = nil }
end

P.ERROR_MAX = 20       -- tool ERROR lines per session (the game script's cap)
P.ERROR_PER_WHERE = 3  -- of them per where= (a failure repeating every refresh logs 3 times)

--- Gate for the tool's ERROR lines: "log" (write it), "last" (write it and say the rest of this
-- where= / the session is suppressed) or "drop". state: table kept per session; where: the
-- line's where= field (any value).
function P.errorGate(state, where)
	local key = tostring(where)
	state.total = state.total or 0
	state.by = state.by or {}
	local k = state.by[key] or 0
	if state.total >= P.ERROR_MAX or k >= P.ERROR_PER_WHERE then return "drop" end
	state.total = state.total + 1
	state.by[key] = k + 1
	if state.total >= P.ERROR_MAX or k + 1 >= P.ERROR_PER_WHERE then return "last" end
	return "log"
end

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
