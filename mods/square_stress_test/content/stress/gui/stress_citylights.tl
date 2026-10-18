-- Stress Test bench: the city run's build (plans/square_stress_test/BENCH.md "City lights at scale"; user 2026-10-15:
-- "make every light in the big grid cities be auto timer lights so we can see what happens with many at once").
-- The bench run (gui/stress_bench_run.tl) calls cl.build after its map clear and year; the steps, each a queued job:
--   1. the cities (towns.createGrid with stress_bench.cityPlan's points: Large towns on the wide grid, locked, its outer
--      ring a country road; never linked to each other, so every city is its own network),
--   2. their own streets locked into the grid (towns.lockTowns), 3. one size command each (towns.densify, target pop),
--   4. every inner crossing of every grid lit: a light set to Yes where none stands (the Lights showcase's way), one
--      command at a time; a "[SQST] CITY" line per city,
--   5. one traffic log zone per city (stress_bench.cityZone; slzones.setLocal: not sent to Smart Lanes).
-- Funnel layouts (v2, BENCH.md "Funnel layouts"): the grid construction leaves the gaps' streets out (its layout params,
-- the same in every city); after the lock, any street found in a gap (the town's own, or ours should the game have
-- dropped the params) is removed, one proposal per city, and logged ("[SQST] CITY_GAPS at=build"); cl.gapCheck counts
-- them again at the run's end (at=end). Lit: every inner crossing with 4 streets, and with 3 (the T at the neck / a
-- hole's edge) in a funnel layout.
-- cl.enroll (the run, after its baseline) sends SmartLanes.auto add events for the auto cities' crossings (op=all
-- without control cities) and logs "[SQST] CITY_ENROLL"; cl.unenroll sends op=clear at the end.

local logic = ug_require "square_stress_test::/stress/stress_logic.tl" as SquareStressLogic
local bench = ug_require "square_stress_test::/stress/stress_bench.tl" as SquareStressBench
local rt = ug_require "square_stress_test::/stress/gui/stress_runtime.tl" as SquareStressRuntime
local towns = ug_require "square_stress_test::/stress/gui/stress_towns.tl" as SquareStressTowns
local slzones = ug_require "square_stress_test::/stress/gui/stress_slzones.tl" as SquareStressSlZones
local gridStreets = ug_require "square_stress_test::/stress/stress_grid_streets.lua" as SquareStressGridStreets

local SCAN_PAD <const> = 40.0          -- m: nodes are looked for this far beyond the grid's half side
local SETTLE_MS <const> = 3000         -- after the size commands, before the crossings are read
local LIT_READ_MS <const> = 3000       -- after the last light command, before the lit count is read again
local SEND_MAX <const> = 2000          -- light commands in one build at most (6 cities x 81: 486)
local GAP_MAX <const> = 400            -- gap streets removed per city at most (a plain grid's gaps hold 24)
local GAP_READ_MS <const> = 1500       -- after the gap removals, before the size commands

local cl : SquareStressCityLights = {}

-- the build's state (one at a time)
local record Build
	sheet : SquareStressBenchSheet
	plan : SquareStressBenchCityPlan
	run : string
	cx : number
	cy : number
	created : {integer : integer}     -- city index -> town
	crossings : {integer : {{number}}}  -- city index -> its inner crossings {node, x, y, streets}
	layout : SquareStressStreetLayout     -- every city's street grid layout
	gapFound : {integer : integer}      -- city index -> streets found in its gaps after the lock
	gapRemoved : {integer : integer}    -- ... of them removed
	onDone : function(zones : {SquareStressShowcaseZone})
	onAbort : function(why : string)
end

local cur : Build = nil

local function comp(e : integer, ct : Engine.ComponentType) : any
	local ok, c : boolean, any = pcall(api.engine.getComponent, e, ct)
	if not ok then return nil end
	return c
end

--- The street nodes around (x, y) within r: {node, x, y, streets}.
local function streetNodes(x : number, y : number, r : number) : {{number}}
	local out : {{number}} = {}
	local CT = api.type.ComponentType
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), r, CT.BASE_EDGE)
	if not ok or list == nil then return out end
	local seen : {integer : boolean} = {}
	for _, e in ipairs(list as {integer}) do
		if comp(e, CT.BASE_EDGE_STREET) ~= nil then
			local be = comp(e, CT.BASE_EDGE) as Engine.Component.BaseEdge
			if be ~= nil then
				for _, n in ipairs({ be.node0, be.node1 }) do
					if not seen[n] then
						seen[n] = true
						local bn = comp(n, CT.BASE_NODE) as Engine.Component.BaseNode
						local okS, segs = pcall(api.engine.system.streetSystem.getNodeSegments, n)
						if bn ~= nil and okS and segs ~= nil then
							out[#out + 1] = { n, bn.position.x, bn.position.y, #(segs as {integer}) }
						end
					end
				end
			end
		end
	end
	return out
end

--- Whether a node has a light (preference Yes, or a BASE_NODE_TRAFFIC_LIGHT component: as Smart Lanes reads lit=yes).
local function isLit(n : integer) : boolean
	local cfg = comp(n, api.type.ComponentType.BASE_NODE_CONFIG) as Engine.Component.BaseNodeConfig
	if cfg ~= nil and cfg.trafficLightPreference == api.type.enum.TrafficLightPreference.YES then return true end
	return comp(n, api.type.ComponentType.BASE_NODE_TRAFFIC_LIGHT) ~= nil
end

--- Sets a light to Yes at every node of the list, one command after the other (the game's own proposal, as the Lights
--- showcase's setLights); done(refused) once every one answered.
local function lightAll(name : string, nodes : {integer}, done : function(refused : integer))
	local refused = 0
	local i = 0
	local nextOne : function()
	nextOne = function()
		i = i + 1
		if i > #nodes or i > SEND_MAX then done(refused) return end
		local n = nodes[i]
		local ok = pcall(function()
			local cfg = comp(n, api.type.ComponentType.BASE_NODE_CONFIG) as Engine.Component.BaseNodeConfig
			local tlc = cfg.trafficLightConfig
			local okC, c : boolean, any = pcall(function() : any return tlc:clone() end)
			if okC and c ~= nil then tlc = c as Engine.Component.TrafficLightConfig end
			local p = api.engine.util.proposal.createTrafficLightProposal(n, tlc, api.type.enum.TrafficLightPreference.YES)
			rt.send(name .. ":lights", api.cmd.makeWorldBuildProposalCmd(p, nil, false, true), function(sent : boolean, _d : any)
				if not sent then
					refused = refused + 1
					rt.log(string.format("[SQST] %s: light on at node %d refused", name, n))
				end
				-- the next one from the queue, not from inside this callback (no call chain 500 deep)
				rt.later(name, 0, nextOne)
			end)
		end)
		if not ok then
			refused = refused + 1
			rt.later(name, 0, nextOne)
		end
	end
	nextOne()
end

local function inConstruction(e : integer, node : boolean) : boolean
	local sys = api.engine.system.streetConnectorSystem
	local ok, con = pcall(function() : integer
		if node then return sys.getConstructionEntityForNode(e) end
		return sys.getConstructionEntityForEdge(e)
	end)
	return ok and con ~= nil and con >= 0
end

--- The street edges whose middle lies in one of layout L's gaps of the city at (x, y): {edge, node0, node1}, sorted, at
--- most GAP_MAX (construction edges never).
local function gapEdges(L : SquareStressStreetLayout, x : number, y : number, half : number) : {{integer}}
	local out : {{integer}} = {}
	if L == nil or #(L.gaps or {}) == 0 then return out end
	local CT = api.type.ComponentType
	local ok, list = pcall(api.engine.util.octree.findEntitiesInCircle, api.type.Vec2f.new(x, y), half * 1.4143 + SCAN_PAD, CT.BASE_EDGE)
	if not ok or list == nil then return out end
	local seen : {integer : boolean} = {}
	for _, e in ipairs(list as {integer}) do
		if #out >= GAP_MAX then break end
		if not seen[e] and comp(e, CT.BASE_EDGE_STREET) ~= nil and not inConstruction(e, false) then
			seen[e] = true
			local be = comp(e, CT.BASE_EDGE) as Engine.Component.BaseEdge
			local a = be ~= nil and comp(be.node0, CT.BASE_NODE) as Engine.Component.BaseNode or nil
			local b = be ~= nil and comp(be.node1, CT.BASE_NODE) as Engine.Component.BaseNode or nil
			if a ~= nil and b ~= nil then
				local mx, my = (a.position.x + b.position.x) / 2 - x, (a.position.y + b.position.y) / 2 - y
				if gridStreets.inGap(L, mx, my) then out[#out + 1] = { e, be.node0, be.node1 } end
			end
		end
	end
	table.sort(out, function(p : {integer}, q : {integer}) : boolean return p[1] < q[1] end)
	return out
end

--- One proposal removing the gap streets `list` ({edge, node0, node1}): the edges, the nodes they leave without a street
--- (never a construction's), the configs of the nodes that stay without connections through them (as Remove all roads).
local function gapProposal(list : {{integer}}) : SimpleProposal
	local edges : {integer} = {}
	local ends : {{integer}} = {}
	local gone : {integer : boolean} = {}
	for _, g in ipairs(list) do
		edges[#edges + 1] = g[1]
		ends[#ends + 1] = { g[2], g[3] }
		gone[g[1]] = true
	end
	local degree : {integer : integer} = {}
	local frozen : {integer : boolean} = {}
	for _, pr in ipairs(ends) do
		for k = 1, 2 do
			local n = pr[k]
			if frozen[n] == nil then
				local okS, segs = pcall(api.engine.system.streetSystem.getNodeSegments, n)
				if okS and segs ~= nil then degree[n] = #(segs as {integer}) end
				frozen[n] = inConstruction(n, true)
			end
		end
	end
	local nodes = logic.orphanNodes(ends, degree, frozen)
	local orphan : {integer : boolean} = {}
	for _, n in ipairs(nodes) do orphan[n] = true end
	local cfgRemove : {integer} = {}
	local cfgAdd : {Proposal.BaseNodeLaneConnectionAndEntity} = {}
	local done : {integer : boolean} = {}
	for _, pr in ipairs(ends) do
		for k = 1, 2 do
			local n = pr[k]
			if not orphan[n] and not done[n] then
				done[n] = true
				local okE, entry, changed = pcall(rt.nodeConfigEntry, n, nil, gone)
				if okE and entry ~= nil and (changed or 0) > 0 then
					cfgRemove[#cfgRemove + 1] = n
					cfgAdd[#cfgAdd + 1] = entry
				end
			end
		end
	end
	local p = api.type.SimpleProposal.new()
	p.streetProposal.edgesToRemove = edges
	p.streetProposal.nodesToRemove = nodes
	if #cfgAdd > 0 then
		p.streetProposal.nodeConfigsToRemove = cfgRemove
		p.streetProposal.nodeConfigsToAdd = cfgAdd
	end
	return p
end

--- After the lock: every city's gap streets removed (one proposal per city, in turn; a refused one is logged and its
--- streets stay), a CITY_GAPS line per city; then done().
local function clearGaps(b : Build, done : function())
	local name = b.sheet.id .. "_gaps"
	local k = 0
	local nextCity : function()
	nextCity = function()
		k = k + 1
		if cur ~= b then return end
		if k > #b.plan.cities then
			rt.later(name .. ":settle", GAP_READ_MS, done)
			return
		end
		local c = b.plan.cities[k]
		b.gapFound[k], b.gapRemoved[k] = 0, 0
		if b.created[k] == nil then nextCity() return end
		local okG, list = pcall(gapEdges, b.layout, b.cx + c.x, b.cy + c.y, c.half)
		if not okG or list == nil then
			rt.log(string.format("[SQST] %s %s: gap streets unread (%s)", name, c.id, tostring(list)))
			nextCity()
			return
		end
		b.gapFound[k] = #list
		if #list == 0 then
			rt.log(bench.cityGapLine(c, "build", 0, 0))
			nextCity()
			return
		end
		local okP, p = pcall(gapProposal, list)
		if not okP or p == nil then
			rt.log(string.format("[SQST] %s %s: gap removal not built (%s)", name, c.id, tostring(p)))
			rt.log(bench.cityGapLine(c, "build", #list, 0))
			nextCity()
			return
		end
		rt.send(name .. ":remove", api.cmd.makeWorldBuildProposalCmd(p as SimpleProposal, nil, false, true), function(success : boolean, _d : any)
			if success then b.gapRemoved[k] = #list end
			if not success then rt.log(string.format("[SQST] %s %s: removing %d gap streets was refused (they stay)", name, c.id, #list)) end
			rt.log(bench.cityGapLine(c, "build", #list, b.gapRemoved[k]))
			-- the next one from the queue, not from inside this callback
			rt.later(name, 0, nextCity)
		end)
	end
	nextCity()
end

--- A town's people (its residential capacity, as the game's population), nil when unread.
local function townPop(town : integer) : integer
	if town == nil then return nil end
	local ok, m = pcall(function() : any return api.engine.system.townBuildingSystem.getTown2personCapacitiesMap() end)
	if not ok or m == nil then return nil end
	local caps = (m as {integer : {integer}})[town]
	return caps ~= nil and caps[1] or nil
end

local function fail(why : string)
	local b = cur
	cur = nil
	if b ~= nil and b.onAbort ~= nil then pcall(b.onAbort, why) end
end

--- Step 4: every city's inner crossings, the dark ones lit, a CITY line each; then step 5.
local function lightCities(b : Build)
	local name = b.sheet.id .. "_lights"
	local dark : {integer} = {}
	local per : {integer : {integer}} = {}
	local litBefore : {integer : integer} = {}
	local found, found3 = 0, 0
	-- a funnel layout lights its T crossings too (3 streets at an inner grid point)
	local minDeg = (b.layout ~= nil and b.layout.name ~= "plain") and 3 or 4
	for k, c in ipairs(b.plan.cities) do
		local x, y = b.cx + c.x, b.cy + c.y
		-- a city whose town was not created (no land there) has no grid: nothing to light
		local list = b.created[k] ~= nil and bench.cityInterior(streetNodes(x, y, c.half + SCAN_PAD), x, y, c.half, minDeg) or {}
		b.crossings[k] = list
		found = found + #list
		for _, e in ipairs(list) do
			if (e[4] or 4) < 4 then found3 = found3 + 1 end
		end
		per[k], litBefore[k] = {}, 0
		for _, e in ipairs(list) do
			local n = math.floor(e[1])
			if isLit(n) then
				litBefore[k] = litBefore[k] + 1
			else
				per[k][#per[k] + 1] = n
				dark[#dark + 1] = n
			end
		end
	end
	rt.log(string.format("[SQST] %s: %d inner crossings found, %d dark: lights on (layout=%s found4=%d found3=%d)", name, found, #dark,
		b.layout ~= nil and b.layout.name or "plain", found - found3, found3))
	lightAll(name, dark, function(_refused : integer)
		rt.later(name .. ":read", LIT_READ_MS, function()
			if cur ~= b then return end
			local zones : {SquareStressShowcaseZone} = {}
			for k, c in ipairs(b.plan.cities) do
				local refused = 0
				for _, n in ipairs(per[k]) do
					if not isLit(n) then refused = refused + 1 end
				end
				local ex : SquareStressCityLineExtra = { layout = b.layout ~= nil and b.layout.name or "plain", neck = b.layout ~= nil and b.layout.neck or 0,
					holes = b.layout ~= nil and #b.layout.holes or 0, found4 = 0, found3 = 0, lit4 = 0, lit3 = 0, pop = townPop(b.created[k]),
					gapStreets = b.gapFound[k] or 0, gapRemoved = b.gapRemoved[k] or 0 }
				for _, e in ipairs(b.crossings[k]) do
					local t = (e[4] or 4) < 4
					local lit = isLit(math.floor(e[1]))
					if t then ex.found3 = ex.found3 + 1 else ex.found4 = ex.found4 + 1 end
					if lit and t then ex.lit3 = ex.lit3 + 1 elseif lit then ex.lit4 = ex.lit4 + 1 end
				end
				rt.log(bench.cityLine(c, b.cx + c.x, b.cy + c.y, b.created[k], #b.crossings[k], litBefore[k], #per[k] - refused, refused, ex))
				if b.created[k] ~= nil then
					local z = bench.cityZone(c)
					z.x, z.y, z.built = b.cx + c.x, b.cy + c.y, true
					zones[#zones + 1] = z
					rt.log(logic.showcaseZoneLine(z, false))
				end
			end
			slzones.setLocal(zones, b.run)
			-- what the run's enroll needs
			cl.last = { plan = b.plan, crossings = b.crossings, run = b.run, layout = b.layout, cx = b.cx, cy = b.cy, created = b.created }
			cur = nil
			pcall(b.onDone, zones)
		end)
	end)
end

--- Builds the cities of sheet (bench.CITY) on this map; onDone(zones) once their lights are on and the zones set;
--- onAbort(why) when nothing usable came of it. false when it could not start.
function cl.build(sheet : SquareStressBenchSheet, seed : integer, onDone : function(zones : {SquareStressShowcaseZone}),
		onAbort : function(why : string)) : boolean
	if cur ~= nil then return false end
	local w, h, cx, cy = 0.0, 0.0, 0.0, 0.0
	local okB = pcall(function()
		local box = api.engine.terrain.getBoundingBox()
		w, h = box.max.x - box.min.x, box.max.y - box.min.y
		cx, cy = (box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2
	end)
	if not okB then return false end
	local plan, why = bench.cityPlan(w, h, 400.0, sheet)
	if plan == nil then
		rt.log(string.format("[SQST] %s: the cities do not fit (%s)", sheet.id, tostring(why)))
		return false
	end
	local b : Build = { sheet = sheet, plan = plan, run = string.format("city-%d", seed), cx = cx, cy = cy, created = {}, crossings = {},
		layout = bench.cityLayout(sheet, seed), gapFound = {}, gapRemoved = {}, onDone = onDone, onAbort = onAbort }
	local L = b.layout
	local layoutIdx = 1
	for i, n in ipairs(bench.CITY_LAYOUTS) do
		if n == L.name then layoutIdx = i end
	end
	local holesText : {string} = {}
	for _, hc in ipairs(L.holes) do holesText[#holesText + 1] = string.format("%d:%d", hc[1], hc[2]) end
	cur = b
	local size = logic.TOWN_SIZES[sheet.city.size]
	local points : {SquareStressGridPoint} = {}
	for k, c in ipairs(plan.cities) do
		points[k] = { x = c.x, y = c.y, name = c.name, row = 1, col = k, size = sheet.city.size, pop = c.pop }
	end
	-- v2 keys: the options, the layout's neck / holes (grid line indices i:j, 0..n from the south-west corner), crossings per kind
	rt.log(string.format("[SQST] %s cities=%d auto=%d control=%d size=%s pop=%d spacing=%.0f half=%.0f crossings=%d enrolled=%d run=%s %s neck_streets=%d holes=%d holes_pattern=%d holes_at=%s x4=%d t3=%d weights=%s",
		sheet.id, #plan.cities, plan.auto, plan.control, size.label, math.floor(sheet.city.pop), sheet.city.spacing, plan.half, plan.crossings,
		plan.enrolled, b.run, bench.cityOptionKeys(sheet), L.neck, #L.holes, L.pattern, #holesText > 0 and table.concat(holesText, ",") or "-",
		L.x4, L.t3, logic.listText(sheet.city.weights or logic.DENSE_WEIGHTS)))
	towns.createGrid({ name = sheet.id, label = "City lights: cities", cols = #points, rows = 1, spacing = sheet.city.spacing, size = size,
		useCamera = false, cx = 0.0, cy = 0.0, connect = 1, streets = 3, points = points, skipNoLand = true, batch = true,
		gridLayout = layoutIdx > 1 and layoutIdx or nil, gridHoles = L.name == "holes" and L.pattern or nil },
		function(created : {integer : integer}, _pts : {SquareStressGridPoint}, _skipped : {integer : boolean}, _t : {string : number})
			if cur ~= b then return end
			local areas : {SquareStressLockArea} = {}
			for k, c in ipairs(plan.cities) do
				local e = created[k]
				if e ~= nil then
					b.created[k] = e
					areas[#areas + 1] = { town = e, label = c.name, x = cx + c.x, y = cy + c.y, half = c.half, target = c.pop }
				end
			end
			if #areas == 0 then fail("no city was created") return end
			local function grow()
				if cur ~= b then return end
				towns.densify(sheet.id .. "_dense", areas, { factor = logic.growFactorForCap(sheet.city.pop, size.caps) or 1.0,
					target = sheet.city.pop, passes = 1, weights = sheet.city.weights or logic.DENSE_WEIGHTS, onDone = function(_ms2 : number)
						if cur ~= b then return end
						rt.later(sheet.id .. ":settle", SETTLE_MS, function()
							if cur ~= b then return end
							local okL, err : boolean, any = pcall(lightCities, b)
							if not okL then fail("lighting the cities failed: " .. tostring(err)) end
						end)
					end })
			end
			towns.lockTowns(sheet.id .. "_lock", areas, { pass = "towns", stubs = true, onDone = function(_ms : number)
				if cur ~= b then return end
				-- a funnel layout: its gaps cleared of any street before the towns grow (none expected: the grid leaves them out)
				if L.name == "plain" then grow() return end
				local okG, err : boolean, any = pcall(clearGaps, b, grow)
				if not okG then
					rt.log(string.format("[SQST] %s: clearing the gaps failed: %s", sheet.id, tostring(err)))
					grow()
				end
			end })
		end)
	return true
end

--- The run's enroll after its baseline: SmartLanes.auto add events for every auto city's inner crossings (op=all when
--- the sheet has no control cities). Logs "[SQST] CITY_ENROLL"; returns the junctions asked for.
function cl.enroll(sheet : SquareStressBenchSheet, run : string, crossings : {integer : {{number}}}, plan : SquareStressBenchCityPlan) : integer
	local sl = slzones.present()
	if not sheet.city.control then
		slzones.sendAuto("all", "bench_city")
		rt.log(bench.cityEnrollLine(run, "all", plan.auto, plan.enrolled, 1, sheet.baselineS or 0, sl, sheet))
		return plan.enrolled
	end
	local entries : {{number}} = {}
	local cities = 0
	for k, c in ipairs(plan.cities) do
		if c.role == "auto" and crossings[k] ~= nil then
			cities = cities + 1
			for _, e in ipairs(crossings[k]) do entries[#entries + 1] = e end
		end
	end
	local sent = slzones.sendAutoNodes(bench.cityPayloads(entries))
	rt.log(bench.cityEnrollLine(run, "add", cities, #entries, sent, sheet.baselineS or 0, sl, sheet))
	return #entries
end

--- The last build's gaps counted again (no removal): a "[SQST] CITY_GAPS at=<label>" line per city of a funnel layout;
--- the streets found in all (0 for a plain grid: no line).
function cl.gapCheck(label : string) : integer
	local last = cl.last
	if last == nil or last.layout == nil or last.layout.name == "plain" then return 0 end
	local all = 0
	for k, c in ipairs(last.plan.cities) do
		if last.created ~= nil and last.created[k] ~= nil then
			local ok, list = pcall(gapEdges, last.layout, (last.cx or 0) + c.x, (last.cy or 0) + c.y, c.half)
			local n = (ok and list ~= nil) and #list or 0
			all = all + n
			rt.log(bench.cityGapLine(c, label, n, 0))
		end
	end
	return all
end

--- Every junction unenrolled (the run's end): SmartLanes.auto op=clear.
function cl.unenroll()
	slzones.sendAuto("clear", "bench_city")
end

return cl
