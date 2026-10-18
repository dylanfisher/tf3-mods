-- More terrain motifs (ot_motif_relief, phase M4 of plans/square_organic_towns/MOTIFS_BRIEF.md, 2026-10-13): switchbacks
-- on steep slopes, the ridge street along a crest, the headland street along a cliff top and the bridgehead quarter on
-- the far bank of the town's river bridge. Eligibility on synthetic terrain, each motif's pattern metric after simulated
-- increments (join "deadEnd" as in game), the rules (no crossings, no water, grades, map edge, lead limit, configs for
-- every new node) and the M4 slot rule (the bridgehead quarter is an `extra` derived kind: no motif slot).
-- Set OT_SVG=<dir> to dump an SVG per motif run (the plan grey, the motif's pieces orange, built streets black).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local MO = ug_require(F.DIR .. "ot_motif.lua")
local RL = ug_require(F.DIR .. "ot_motif_relief.lua")
local L = ug_require(F.DIR .. "ot_motif_land.lua")
local core = ug_require(F.DIR .. "ot_core.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")
local MT = ug_require(F.DIR .. "ot_metrics.lua")
local SH = ug_require(F.DIR .. "ot_shape.lua")
local SV = ug_require(F.DIR .. "ot_saved.lua")
local SEL = ug_require(F.DIR .. "ot_select.lua")
local OG = ug_require(F.DIR .. "ot_graph.lua")
local G = ug_require(F.DIR .. "ot_geom.lua")
local MAP = ug_require(F.DIR .. "ot_map.lua")
local PR = ug_require(F.DIR .. "ot_proposal.lua")
local D = ug_require(F.DIR .. "ot_driver.lua")
local BR = ug_require(F.DIR .. "ot_bridge.lua")

local EU = "::/names/europe/europe.names"
local NEW_SMALL = "::/infrastructure/street/town/town_new_small.street_template"
local KINDS = { "switchbacks", "ridge_street", "headland_street", "bridgehead_quarter" }

local function has(list, id) for _, m in ipairs(list or {}) do if m.id == id then return m end end end

local function resolve(sampler, o)
	o = o or {}
	local stats = T.stats(sampler, 0, 0, 600, 24)
	local inputs = I.build({ townId = o.id or 5, pos = { 0, 0 }, capacity = o.cap or 1500, year = o.year or 1905,
		nameList = EU, terrain = stats, forceStyle = o.style, autoStyle = o.style == nil, motif = o.motif,
		radius = o.radius or 160, bounds = o.bounds, frame = o.frame })
	local st = ST.resolve(inputs)
	return st, stats, inputs
end

local function ctxOf(st, stats, inputs, o)
	o = o or {}
	return { style = st, terrain = stats, inputs = inputs, tier = o.tier or 2, year = o.year or 1905 }
end

local SVGDIR = os.getenv("OT_SVG")
local function svg(name, g, mp, sampler, extra)
	if not SVGDIR then return end
	local f = io.open(SVGDIR .. "/" .. name .. ".svg", "w")
	if not f then return end
	local S, W = 1000, 2000
	local function X(x) return (x + W / 2) * S / W end
	local function Y(y) return (W / 2 - y) * S / W end
	f:write(string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d"><rect width="100%%" height="100%%" fill="white"/>', S, S))
	for i = 0, 49 do
		for j = 0, 49 do
			local x, y = -W / 2 + (i + 0.5) * W / 50, -W / 2 + (j + 0.5) * W / 50
			local h = T.height(sampler, x, y)
			local c = T.isWater(sampler, x, y) and "#9cf"
				or string.format("#%02x%02x%02x", 255 - math.min(120, math.max(0, math.floor(h))),
					255 - math.min(80, math.max(0, math.floor(h / 2))), 220)
			f:write(string.format('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>', X(x - W / 100),
				Y(y + W / 100), S / 50 + 0.5, S / 50 + 0.5, c))
		end
	end
	for _, pc in ipairs(mp and mp.pieces or {}) do
		local d = {}
		for i, p in ipairs(pc.pts) do d[#d + 1] = (i == 1 and "M" or "L") .. string.format("%.1f %.1f", X(p[1]), Y(p[2])) end
		f:write(string.format('<path d="%s" stroke="%s" stroke-width="%s" fill="none"/>', table.concat(d, " "),
			pc.motif and "#f80" or "#ccc", pc.motif and 2 or 1))
	end
	for _, s in ipairs(extra or {}) do
		f:write(string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="3"/>', X(s[1]), Y(s[2]),
			X(s[3]), Y(s[4]), s.color or "#d33"))
	end
	for _, e in ipairs(g.edges) do
		local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
		f:write(string.format('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#000" stroke-width="2"/>', X(a.x), Y(a.y),
			X(b.x), Y(b.y)))
	end
	f:write("</svg>")
	f:close()
end

--- A forced motif on graph g (a vanilla core at the origin unless given), n increments (join "deadEnd"): measure,
--- record, style, increments, stats, master plan, graph.
local function run(sampler, motif, o)
	o = o or {}
	local st, stats = resolve(sampler, { motif = motif, style = o.style or "EU_ORGANIC", radius = o.radius, cap = o.cap,
		bounds = o.bounds, year = o.year, frame = o.frame })
	if o.prep then o.prep(st) end
	local g = o.g or F.vanillaTown(nil, { n = o.core or 4, spacing = o.spacing or 80 })
	local incs = core.simulate(g, st, { terrain = sampler, stats = stats, join = "deadEnd" }, o.n or 12)
	local m = has(MO.list(st), motif)
	local mp = core.masterPlan(g, st, { terrain = sampler, stats = stats }, 8)
	local r = m and MO.measure(m, { g = g, inc = incs[#incs], style = st, pts = o.pts or {}, sampler = sampler, MT = MT,
		SH = SH, mp = mp })
	if o.svg then svg(o.svg, g, mp, sampler, o.extra) end
	return r, m, st, incs, stats, mp, g
end

--- Rules every motif run keeps: no crossing streets, min angle, nothing on water, no steep or large new street.
local function rules(name, g, st, incs, sampler, prefix)
	local e1, e2 = F.crossingPair(g)
	ok(e1 == nil, name .. ": crossing edges " .. tostring(e1 and e1.id) .. "/" .. tostring(e2 and e2.id))
	ok(F.minAngle(g) >= 15, name .. ": min angle " .. F.minAngle(g))
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			local pts = { { e.p0[1], e.p0[2] }, { e.p1[1], e.p1[2] } }
			ok(not T.wetAlong(sampler, pts, 0), name .. ": edge on water " .. tostring(e.key))
			ok(T.grade(sampler, e.p0[1], e.p0[2], e.p1[1], e.p1[2]) <= st.maxSlope + 0.01, name .. ": steep edge " .. tostring(e.key))
			if prefix and type(e.key) == "string" and e.key:sub(1, #prefix) == prefix then
				ok(not tostring(e.template):find("large", 1, true), name .. ": wide motif street " .. e.key)
			end
		end
	end
end

local function motifEdges(incs, prefix)
	local n, list = 0, {}
	for _, inc in ipairs(incs) do
		for _, e in ipairs(inc.edges) do
			if type(e.key) == "string" and e.key:sub(1, #prefix) == prefix then n = n + 1; list[#list + 1] = e end
		end
	end
	return n, list
end

---------------------------------------------------------------------------

--- A river town with its bridge built: the vanilla core north of a river at y = -260 (F.river), the ot_bridge increment
--- across it from the core's southern dead end applied. Returns graph, sampler, the bridge plan.
local function bridgedTown()
	local sampler = F.river(-260)
	local g = F.vanillaTown(nil, { n = 4, spacing = 80 })
	local des = {}
	for _, id in ipairs(OG.deadEnds(g)) do
		local n = g.nodeById[id]
		des[#des + 1] = { n.x, n.y, id, n.z, NEW_SMALL }
	end
	table.sort(des, function(a, b) return a[3] < b[3] end)
	local bp = BR.plan({ sampler = sampler, deadEnds = des, axis = 0, g = g, seed = 3 })
	assert(bp, "a bridge plan")
	OG.apply(g, bp.inc, 1)
	return g, sampler, bp
end

test("registry: the four M4 kinds with append-only save indices (14-17); the bridgehead quarter derived and extra", function()
	for i, id in ipairs(KINDS) do eq(MO.IDS[13 + i], id) end
	for _, id in ipairs({ "switchbacks", "ridge_street", "headland_street" }) do
		local k = MO.BY_ID[id]
		ok(k and not k.derived and not k.extra and k.eligible and k.plan and k.measure, id)
	end
	eq(MO.BY_ID.switchbacks.group, "land"); eq(MO.BY_ID.ridge_street.group, "land")
	eq(MO.BY_ID.headland_street.group, "shore")
	ok(MO.BY_ID.switchbacks.dose and MO.BY_ID.headland_street.dose, "houses at the bends / facing the water")
	local bh = MO.BY_ID.bridgehead_quarter
	ok(bh.derived and bh.extra and bh.lock, "bridgehead: derived, extra, locked")
	eq(MO.LOCK_PREFIX.bridgehead_quarter, "mbh")
	-- (the station quarter is extra too since M4: the player's actions take no motif slot)
	ok(MO.BY_ID.station_quarter.extra)
	local v = MO.encode({ { id = "switchbacks" }, { id = "headland_street" } })
	eq(v, 14 + 64 * 16)
	local d = MO.decode(v)
	eq(d[1], "switchbacks"); eq(d[2], "headland_street")
	eq(MO.encode({ { id = "bridgehead_quarter", derived = true } }), nil, "derived never saved")
end)

test("eligibility: each kind only where the land calls for it; none while the module is off", function()
	local fx = { flat = F.flat, gentle = F.plane(0.04, 0), plane = F.plane(0.085, 0), steep = F.steep(0.10, 0.04),
		cliffy = F.plane(0.2, 0), valley = F.valley(0), ridge = F.valley(0, true), ridgeVar = F.ridgeVar(),
		cliff = F.cliff(), headland = F.cliff(0.0015), beach = F.coast(), bay = F.bay(), river = F.river() }
	local want = {
		flat = {}, gentle = {}, cliffy = {}, valley = {}, beach = {}, bay = {}, river = {},
		plane = { switchbacks = true }, steep = { switchbacks = true },
		ridge = { ridge_street = true }, ridgeVar = { ridge_street = true },
		cliff = { headland_street = true }, headland = { headland_street = true },
	}
	local st0, stats0, in0 = resolve(F.plane(0.085, 0), { style = "EU_ORGANIC" })
	eq(MO.BY_ID.switchbacks.eligible(ctxOf(st0, stats0, in0)), 0, "off (fixtures): 0")
	F.withReliefMotifs(function()
		local lines = {}
		for name, sampler in pairs(fx) do
			local st, stats, inputs = resolve(sampler, { style = "EU_ORGANIC" })
			local parts = {}
			for _, id in ipairs(KINDS) do
				local s, why = MO.BY_ID[id].eligible(ctxOf(st, stats, inputs))
				s = s or 0
				if s < MO.MIN_SCORE then s = 0 end   -- (the registry's floor, ot_motif MIN_SCORE)
				parts[#parts + 1] = string.format("%s=%.2f", id, s)
				if want[name][id] then ok(s > 0.3, name .. " " .. id .. " should be eligible: " .. s); ok(type(why) == "string")
				else eq(s, 0, name .. " " .. id .. " should not be eligible") end
			end
			lines[#lines + 1] = name .. " " .. table.concat(parts, " ")
		end
		table.sort(lines)
		for _, l in ipairs(lines) do print(l) end
		-- grids weigh less; metropolises none; the bridgehead only with a bridge record
		local og, os_, oi = resolve(F.plane(0.085, 0), { style = "EU_ORGANIC" })
		local gg, gs, gi = resolve(F.plane(0.085, 0), { style = "NA_GRID" })
		ok(MO.BY_ID.switchbacks.eligible(ctxOf(gg, gs, gi)) < MO.BY_ID.switchbacks.eligible(ctxOf(og, os_, oi)), "grid less")
		og.metro = { id = "grid" }
		eq(MO.BY_ID.switchbacks.eligible(ctxOf(og, os_, oi)), 0, "metropolis")
		local st, stats, inputs = resolve(F.river(-260), { style = "EU_ORGANIC" })
		eq(MO.BY_ID.bridgehead_quarter.eligible(ctxOf(st, stats, inputs)), 0, "no bridge yet")
		st.bridge = { built = true, src = "frame" }
		eq(MO.BY_ID.bridgehead_quarter.eligible(ctxOf(st, stats, inputs)), 1, "the bridge built")
		-- the frame's `br` flag gives the record (ot_style)
		local fr = SV.frame(SV.applyFrame(nil, { town = 5, a = 0.1, x = 0, y = 0 }), 5)
		fr.bridge = true
		local framed = resolve(F.river(-260), { style = "EU_ORGANIC", frame = fr })
		ok(framed.bridge and framed.bridge.src == "frame", "frame br -> style.bridge")
		ok(has(MO.list(framed), "bridgehead_quarter"), "the quarter listed on a bridged town")
	end)
end)

test("picks: deterministic, one land / shore motif, M4 kinds drawn on their sites; the bridgehead takes no slot", function()
	F.withReliefMotifs(function()
		local function count(sampler, o)
			local seen, n = {}, 0
			for id = 1, 120 do
				local a = resolve(sampler, { id = id, cap = 3000 })
				local b = resolve(sampler, { id = id, cap = 3000 })
				eq(MO.text(a.motifs), MO.text(b.motifs), "same town, same motifs")
				local groups = {}
				for _, m in ipairs(a.motifs) do
					seen[m.id] = (seen[m.id] or 0) + 1
					local gr = MO.BY_ID[m.id].group
					if gr then ok(not groups[gr], "one per group: " .. MO.text(a.motifs)); groups[gr] = true end
				end
				if o and o.bridge then
					local before = MO.text(a.motifs)
					a.bridge = { built = true }
					eq(MO.slotsTaken(a), MO.slotsTaken({ motifs = {}, shape = a.shape, crescents = a.crescents, greens = a.greens }),
						"the bridgehead takes no slot")
					ok(has(MO.list(a), "bridgehead_quarter"), "listed")
					eq(MO.text(a.motifs), before)
				end
				n = n + 1
			end
			return seen
		end
		local steep, ridge, cliff = count(F.steep(0.10, 0.04)), count(F.valley(0, true)), count(F.cliff())
		local function t(x) local p = {} for k, v in pairs(x) do p[#p + 1] = k .. " " .. v end table.sort(p) return table.concat(p, ", ") end
		print("120 steep towns: " .. t(steep))
		print("120 ridge towns: " .. t(ridge))
		print("120 cliff towns: " .. t(cliff))
		ok((steep.switchbacks or 0) >= 8, "switchbacks drawn on steep slopes")
		ok((ridge.ridge_street or 0) >= 30, "ridge streets on crests")
		ok((cliff.headland_street or 0) >= 30, "headland streets on cliffs")
		count(F.river(-260), { bridge = true })
		-- saved on the frame, reloaded as saved
		local town, st
		for id = 1, 60 do
			local s = resolve(F.valley(0, true), { id = id })
			if has(s.motifs, "ridge_street") then town, st = id, s; break end
		end
		ok(town, "a ridge town")
		local fp = SV.frameParam(town, st, nil, 900)
		local fr = SV.frame(SV.normalize(SV.applyFrame(SV.applyInit(nil, { known = {} }), fp)), town)
		local again = resolve(F.valley(0, true), { id = town, frame = fr })
		ok(has(again.motifs, "ridge_street") and has(again.motifs, "ridge_street").saved, "saved ridge street")
	end)
end)

test("switchbacks: legs along the slope joined by legal hairpin bends, built bend by bend, green between", function()
	F.withReliefMotifs(function()
		for _, c in ipairs({ { "plane", F.plane(0.085, 0) }, { "shelves", F.steep(0.10, 0.04) } }) do
			local sampler = c[2]
			local r, m, st, incs, stats, mp, g = run(sampler, "switchbacks", { n = 16, svg = "switchbacks_" .. c[1] })
			print(c[1] .. ": " .. r.text)
			local geo = m.geo
			ok(geo ~= nil, tostring(m.planWhy))
			ok(#geo.bends >= 2, c[1] .. ": bends planned " .. #geo.bends)
			ok(r.bends >= 2, c[1] .. ": bends built " .. r.bends)
			ok(r.len >= 600, c[1] .. ": built " .. r.len)
			ok(r.climb >= 40, c[1] .. ": climbs " .. r.climb)
			-- every bend a legal curve (radius >= ot_plan.MIN_RADIUS) on ground within maxSlope; a hairpin (>= 100 deg)
			for i, bd in ipairs(geo.bends) do
				local pts = L.sub(geo.ix, bd.s0, bd.s1)
				ok(G.minDiscreteRadius(pts) >= 70, c[1] .. " bend " .. i .. " radius " .. G.minDiscreteRadius(pts))
				ok(T.pathMaxGrade(sampler, pts, 10) <= st.maxSlope, c[1] .. " bend " .. i .. " too steep")
				ok(bd.delta >= math.rad(100), c[1] .. " bend " .. i .. " turns " .. math.deg(bd.delta))
			end
			-- the legs climb gently (the planned line's steepest 10 m within maxSlope)
			ok(geo.grade <= st.maxSlope + 1e-9, "grade " .. geo.grade)
			-- the slopes between the legs stay green: no plan street of the town in the zigzag's zone beyond the core
			local intruders = 0
			for _, pc in ipairs(mp.pieces) do
				if pc.motif == nil then
					local mx, my = G.polyAt(pc.pts, 0.5)
					if G.dist(0, 0, mx, my) > geo.r0 + 10 and L.nearest(geo.ix, mx, my, geo.zone - 5) then intruders = intruders + 1 end
				end
			end
			eq(intruders, 0, c[1] .. ": plan streets between the legs")
			rules("switchbacks " .. c[1], g, st, incs, sampler, "msb")
			-- houses at the bends: the dose beside the bend edges
			local inc
			for _, x in ipairs(incs) do
				for _, e in ipairs(x.edges) do
					local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
					for _, bd in ipairs(geo.bends) do
						if math.abs(G.dist(mx, my, bd.centre[1], bd.centre[2]) - bd.R) < 15 then inc = inc or x end
					end
				end
			end
			ok(inc, "an increment with a bend")
			local pts = MO.dose(st, inc.edges, 30, 6)
			ok(#pts >= 1, "dose points at the bends")
			for _, p in ipairs(pts) do
				local near = false
				for _, bd in ipairs(geo.bends) do
					if math.abs(G.dist(p[1], p[2], bd.centre[1], bd.centre[2]) - bd.R) <= 30 + 15 then near = true end
				end
				local dd = {}
				for _, bd in ipairs(geo.bends) do dd[#dd + 1] = string.format("%.0f", G.dist(p[1], p[2], bd.centre[1], bd.centre[2])) end
				ok(near, "dose at a bend " .. table.concat(dd, "/"))
			end
		end
		-- deterministic; flat: nothing (and says why)
		local st = resolve(F.plane(0.085, 0), { motif = "switchbacks", style = "EU_ORGANIC" })
		local a, b = RL.switchGeo(st, F.plane(0.085, 0), 1500), RL.switchGeo(st, F.plane(0.085, 0), 1500)
		eq(#a.line, #b.line); near(a.ix.len, b.ix.len, 1e-9); eq(#a.bends, #b.bends)
		local _, mf = run(F.flat, "switchbacks", { n = 2 })
		eq(mf.geo, nil); eq(mf.planWhy, "flat")
		-- too steep for any legal bend: none
		local stS = resolve(F.plane(0.16, 0), { motif = "switchbacks", style = "EU_ORGANIC" })
		local gS, whyS = RL.switchGeo(stS, F.plane(0.16, 0), 1500)
		eq(gS, nil, "no legal bend on a uniform 16 % slope")
		print("16 % slope: " .. tostring(whyS))
	end)
end)

test("ridge street: a street on the crest, houses both sides, spurs only down gentle flanks, green flanks", function()
	F.withReliefMotifs(function()
		local r, m, st, incs, stats, mp, g = run(F.valley(0, true), "ridge_street", { n = 16, svg = "ridge_street" })
		print("crest: " .. r.text)
		local geo = m.geo
		ok(geo ~= nil, tostring(m.planWhy))
		ok(r.len >= 600, "spine built " .. r.len)
		ok(r.crest >= 0.9, "on the crest " .. r.crest)
		ok(r.spurs >= 6, "spurs built " .. r.spurs)
		-- on the crest line (y = 0) and spurs both sides, short, square
		for _, p in ipairs(geo.line) do ok(math.abs(p[2]) < 25, "spine off the crest at " .. p[1] .. "," .. p[2]) end
		local sides = { [1] = 0, [-1] = 0 }
		for _, sp in ipairs(geo.spurs) do
			sides[sp.side] = sides[sp.side] + 1
			ok(sp.len <= geo.spurMax + 1e-6, "spur too long")
		end
		ok(sides[1] >= 3 and sides[-1] >= 3, "spurs both sides " .. sides[1] .. "+" .. sides[-1])
		-- no plan street on the flanks beyond the core but the motif's own
		local intruders = 0
		for _, pc in ipairs(mp.pieces) do
			if pc.motif == nil then
				local mx, my = G.polyAt(pc.pts, 0.5)
				local d, s = L.nearest(geo.ix, mx, my, geo.zone - 5)
				if d and G.dist(0, 0, mx, my) > geo.r0 + 10 and math.abs(s - geo.sc) >= geo.r0 then intruders = intruders + 1 end
			end
		end
		eq(intruders, 0, "plan streets on the flanks")
		rules("ridge_street", g, st, incs, F.valley(0, true), "mrs")
		-- houses both sides of the spine (house points: both sides counted)
		local pts = {}
		for _, e in ipairs(g.edges) do
			local a, b = g.nodeById[e.n0], g.nodeById[e.n1]
			local mx, my = (a.x + b.x) / 2, (a.y + b.y) / 2
			if math.abs(mx) > 250 and math.abs(my) < 10 then pts[#pts + 1] = { mx, my + 20 }; pts[#pts + 1] = { mx, my - 20 } end
		end
		local rr = MO.measure(m, { g = g, inc = incs[#incs], style = st, pts = pts, sampler = F.valley(0, true), mp = mp })
		ok(rr.left > 0 and rr.right > 0, "houses both sides " .. rr.left .. "+" .. rr.right)
		-- steep east flanks: spurs only on the gentle (west) half
		local r2, m2, st2, incs2 = run(F.ridgeVar(), "ridge_street", { n = 16, svg = "ridge_street_var" })
		print("uneven flanks: " .. r2.text)
		ok(#m2.geo.spurs >= 3, "spurs on the gentle half " .. #m2.geo.spurs)
		for _, sp in ipairs(m2.geo.spurs) do ok(sp.x0 < 0, "a spur down the steep east flank at x " .. sp.x0) end
		ok(r2.len >= 600, "spine " .. r2.len)
		-- no crest: nothing
		local _, mf = run(F.plane(0.06, 0), "ridge_street", { n = 2 })
		eq(mf.geo, nil); eq(mf.planWhy, "noRidge")
	end)
end)

test("headland street: along the cliff top a setback from the brink, lanes and houses inland, nothing seaward", function()
	F.withReliefMotifs(function()
		for _, c in ipairs({ { "straight", F.cliff() }, { "headland", F.cliff(0.0015) } }) do
			local sampler = c[2]
			local r, m, st, incs, stats, mp, g = run(sampler, "headland_street", { n = 16, svg = "headland_" .. c[1] })
			print(c[1] .. ": " .. r.text)
			local geo = m.geo
			ok(geo ~= nil, tostring(m.planWhy))
			ok(r.len >= 500, c[1] .. ": built " .. r.len)
			ok(r.setbackMin >= geo.off - 10 and r.setbackMean <= geo.off + 15, c[1] .. ": setback " .. r.setbackMin .. ".." .. r.setbackMean)
			eq(r.seaward, 0, c[1] .. ": streets between the street and the cliff")
			ok(r.lanes >= 6, c[1] .. ": lanes " .. r.lanes)
			eq(st.shoreFront, nil, "no promenade below the cliff")
			-- the street follows the brink: every planned point within off +- 15 of it
			for _, p in ipairs(G.resample(geo.line, 40)) do
				local d = L.nearest(geo.brinkIx, p[1], p[2], 200) or 999
				ok(math.abs(d - geo.off) <= 15, c[1] .. ": off the brink by " .. d)
			end
			-- lanes go inland: their ends farther from the brink
			for _, ln in ipairs(geo.lanes) do
				local d0 = L.nearest(geo.brinkIx, ln.x0, ln.y0, 400) or 0
				local d1 = L.nearest(geo.brinkIx, ln.x1, ln.y1, 400) or 0
				ok(d1 > d0 + 20, "lane inland")
			end
			-- no plan street between the street and the cliff
			for _, pc in ipairs(mp.pieces) do
				if pc.motif == nil then
					local mx, my = G.polyAt(pc.pts, 0.5)
					local d, _, side = L.nearest(geo.ix, mx, my, geo.off)
					ok(not (d and side * geo.sea > 0 and d > 5), c[1] .. ": plan street seaward " .. pc.key)
				end
			end
			rules("headland " .. c[1], g, st, incs, sampler, "mhl")
			-- the row facing the water: dose points on the inland side
			local inc
			for _, x in ipairs(incs) do if motifEdges({ x }, "mhl#") > 0 then inc = x; break end end
			ok(inc, "an increment with clifftop streets")
			local pts = MO.dose(st, inc.edges, 30, 6)
			ok(#pts >= 1, "dose points")
			for _, p in ipairs(pts) do
				local d, _, side = L.nearest(geo.ix, p[1], p[2], 40)
				ok(d and side * geo.sea < 0, "dose inland")
			end
		end
		-- a beach (no cliff): nothing
		local _, mf = run(F.coast(), "headland_street", { n = 2 })
		eq(mf.geo, nil); eq(mf.planWhy, "noCliff")
	end)
end)

test("bridgehead quarter: a small grid on the far bank, squared to the bridge, its first row the cross street", function()
	F.withReliefMotifs(function()
		local g, sampler, bp = bridgedTown()
		local C = bp.inc.nodes[3]
		print(string.format("bridge: span %.0f, far end C %.0f,%.0f, heading %.0f", bp.span, C.x, C.y, math.deg(bp.heading)))
		-- before the record: no quarter
		local st0 = resolve(sampler, { style = "EU_ORGANIC" })
		eq(has(MO.list(st0), "bridgehead_quarter"), nil)
		-- the frame's record: the bridge found in the graph (an edge over water)
		local found = RL.findBridge({ centre = { 0, 0 }, bridge = { built = true } }, g, sampler)
		ok(found, "the bridge found in the graph")
		near(found.C.x, C.x, 1); near(found.C.y, C.y, 1)
		near(G.angleDiff(found.heading, bp.heading), 0, 1e-3)
		for _, src in ipairs({ "frame", "session" }) do
			local g2 = bridgedTown()
			local rec = src == "frame" and { built = true, src = "frame" } or { built = true, src = "session", C = { C.x, C.y },
				heading = bp.heading }
			local r, m, st, incs, stats, mp = run(sampler, "bridgehead_quarter", { g = g2, n = 14, svg = "bridgehead_" .. src,
				prep = function(s) s.bridge, s.bridgeKey = rec, RL.bridgeKey(rec) end })
			print(src .. ": " .. r.text)
			local geo = mp.bridgeGeo
			ok(geo ~= nil, tostring(mp.bridgeWhy))
			ok(r.built >= 8, src .. ": sides built " .. r.built .. "/" .. r.planned)
			ok(r.linked >= 1, src .. ": linked to the cross street's dead ends")
			-- on the far bank, squared to the bridge
			local n, list = motifEdges(incs, "mbh")
			ok(n >= 8, "quarter edges " .. n)
			local fx, fy = geo.f[1], geo.f[2]
			for _, e in ipairs(list) do
				local mx, my = (e.p0[1] + e.p1[1]) / 2, (e.p0[2] + e.p1[2]) / 2
				ok((mx - C.x) * fx + (my - C.y) * fy >= -5, "quarter street back across the river")
				local h = G.heading(e.p0[1], e.p0[2], e.p1[1], e.p1[2])
				local dev = math.min(G.lineAngleDiff(h, geo.heading), G.lineAngleDiff(h, geo.heading + math.pi / 2))
				ok(dev < math.rad(3), "squared " .. math.deg(dev))
				ok(not T.wetAlong(sampler, { e.p0, e.p1 }, 0), "on water")
			end
			rules("bridgehead " .. src, g2, st, incs, sampler, "mbh")
		end
		-- the plan is rebuilt when the record appears (ot_core: bridgeKey)
		local g3 = bridgedTown()
		local st3, stats3 = resolve(sampler, { style = "EU_ORGANIC" })
		local mp1 = core.masterPlan(g3, st3, { terrain = sampler, stats = stats3 }, 8)
		eq(mp1.bridgeGeo, nil)
		st3.bridge = { built = true, src = "frame" }
		st3.bridgeKey = RL.bridgeKey(st3.bridge)
		local mp2 = core.masterPlan(g3, st3, { terrain = sampler, stats = stats3 }, 8)
		ok(mp2 ~= mp1 and mp2.bridgeGeo ~= nil, "replanned with the quarter")
		-- locked like the station quarter
		local pre = MO.lockPrefixes(st3)
		local hasP = false
		for _, p in ipairs(pre) do if p == "mbh" then hasP = true end end
		ok(hasP, "locked prefix")
		-- a town without a bridge edge: none (and says why)
		local st4 = resolve(sampler, { style = "EU_ORGANIC" })
		st4.bridge = { built = true }
		local g4 = F.vanillaTown(nil, { n = 4, spacing = 80 })
		local geo4, why4 = RL.bridgeGeo(st4, g4, sampler, 1500)
		eq(geo4, nil); eq(why4, "noBridgeEdge")
	end)
end)

test("rules: map edge margin, lead limit from the houses, configs for every new node", function()
	F.withReliefMotifs(function()
		-- the map's east edge 750 m out: the switchbacks (climbing east) stop 400 m before it
		local bounds = { -4000, -4000, 750, 4000 }
		local r, m, st, incs = run(F.plane(0.085, 0), "switchbacks", { bounds = bounds, n = 12 })
		for _, inc in ipairs(incs) do
			for _, e in ipairs(inc.edges) do
				ok(MAP.edgeDist(bounds, e.p1[1], e.p1[2]) >= MAP.MARGIN - 1, "street near the map edge " .. tostring(e.key))
			end
		end
		if m.geo then for _, p in ipairs(m.geo.line) do ok(MAP.edgeDist(bounds, p[1], p[2]) >= MAP.MARGIN - 45, "line near the edge") end end
		local cases = { { F.plane(0.085, 0), "switchbacks", "msb" }, { F.valley(0, true), "ridge_street", "mrs" },
			{ F.cliff(), "headland_street", "mhl" } }
		-- house data: no new piece farther than the lead limit from a housed street; each motif builds
		for _, c in ipairs(cases) do
			local st2, stats2 = resolve(c[1], { motif = c[2], style = "EU_ORGANIC" })
			local g2 = F.vanillaTown(nil, { n = 4, spacing = 80 })
			local motif = 0
			for k = 1, 8 do
				F.markBuilt(g2, 40 + 30 * k)
				local idx = SEL.housedIndexM(g2, SEL.MAX_LEAD_M)
				local inc = core.planIncrement(g2, st2, { terrain = c[1], stats = stats2, join = "deadEnd" })
				if #inc.edges == 0 then break end
				for _, e in ipairs(inc.edges) do
					for _, p in ipairs({ e.p0, e.p1 }) do
						ok(SEL.housedDist(idx, p[1], p[2]) <= SEL.MAX_LEAD_M + 1, c[2] .. ": beyond the lead limit")
					end
					if type(e.key) == "string" and e.key:sub(1, #c[3]) == c[3] then motif = motif + 1 end
				end
				OG.apply(g2, inc, k)
			end
			print(c[2] .. " with house data: " .. motif .. " motif edges")
			ok(motif > 0, c[2] .. ": the motif builds with house data too")
		end
		-- crash rule: every new node of a motif increment gets a config, every lane index valid; never a noJoin node
		local specs = 0
		local g0, sampler0, bp0 = bridgedTown()
		cases[#cases + 1] = { sampler0, "bridgehead_quarter", "mbh", g0, { built = true, src = "session",
			C = { bp0.inc.nodes[3].x, bp0.inc.nodes[3].y }, heading = bp0.heading } }
		for _, c in ipairs(cases) do
			local st3, stats3 = resolve(c[1], { motif = c[2], style = "EU_ORGANIC" })
			if c[5] then st3.bridge, st3.bridgeKey = c[5], RL.bridgeKey(c[5]) end
			local g3 = c[4] or F.vanillaTown(nil, { n = 3, spacing = 70 })
			for k = 1, 6 do
				local inc = core.planIncrement(g3, st3, { terrain = c[1], stats = stats3, join = "deadEnd" })
				if #inc.edges == 0 then break end
				local inf = { nodes = {}, sources = {}, fallback = 902 }
				for _, j in ipairs(inc.joins) do
					local edges = {}
					for _, eid in ipairs(g3.adj[j.node] or {}) do edges[#edges + 1] = eid end
					inf.nodes[j.node] = { hasConfig = true, edges = edges, lanes = 4, src = edges[1] or 902, template = NEW_SMALL }
					ok(not g3.nodeById[j.node].noJoin, c[2] .. ": joined a noJoin node")
				end
				local spec, err = PR.build(inc, inf)
				ok(spec ~= nil, c[2] .. " " .. tostring(err))
				if spec then
					specs = specs + 1
					local cfg = {}
					for _, cc in ipairs(spec.cfgAdd) do cfg[cc.node] = true end
					for _, nd in ipairs(spec.nodes) do ok(cfg[nd.entity], c[2] .. " node without a config") end
					ok(PR.checkLanes(spec, function(seg) return spec.lanes[seg] or 4 end))
				end
				OG.apply(g3, inc, k)
			end
		end
		ok(specs >= 16, specs .. " specs")
	end)
end)

test("driver: the bridge record reaches the style (this session's build with its geometry, else the frame's flag)", function()
	F.withReliefMotifs(function()
		local lines = {}
		local E = { nowUs = function() return 0 end, log = function(l) lines[#lines + 1] = l end,
			name = function() return "Brigg" end, sendEvent = function() end }
		local d = D.new(E)
		d.opts = { debug = true }
		local st = resolve(F.river(-260), { style = "EU_ORGANIC" })
		local base = resolve(F.river(-260), { style = "EU_ORGANIC" })
		local job = { town = 5, baseStyle = base }
		-- nothing built: no record
		d:bridgeRefresh(job, st, nil)
		eq(st.bridge, nil); eq(st.bridgeKey or "", "")
		-- a saved frame with `br`: the record, the quarter listed, a MOTIF pick line once
		local function frameWith()
			-- (a saved frame whose `br` is set: SV.frame gives bridge = true)
			local real = SV.frame
			SV.frame = function() return { bridge = true } end
			local okR, err = pcall(d.bridgeRefresh, d, job, st, {})
			SV.frame = real
			assert(okR, err)
		end
		frameWith()
		ok(st.bridge and st.bridge.src == "frame", "frame record")
		eq(base.bridge and base.bridge.src, "frame", "the base style too")
		ok(has(MO.list(st), "bridgehead_quarter"), "the quarter now")
		local picks = 0
		for _, l in ipairs(lines) do if l:find("kind=bridgehead_quarter", 1, true) and l:find("event=pick", 1, true) then picks = picks + 1 end end
		eq(picks, 1, "MOTIF pick line")
		frameWith()
		local again = 0
		for _, l in ipairs(lines) do if l:find("kind=bridgehead_quarter", 1, true) then again = again + 1 end end
		eq(again, 1, "no second pick line while the record stays")
		-- this session's build: the far junction and heading from the bridge plan (Driver:bridgeBuilt)
		local _, _, bp = bridgedTown()
		local djob = { town = 5, bridgePlan = bp, spec = { edges = {} } }
		d:bridgeBuilt(djob, 0)
		d:bridgeRefresh(job, st, nil)
		eq(st.bridge.src, "session")
		near(st.bridge.C[1], bp.inc.nodes[3].x, 1e-6)
		near(st.bridge.heading, bp.heading, 1e-9)
		eq(st.bridgeKey, RL.bridgeKey(st.bridge))
	end)
end)
