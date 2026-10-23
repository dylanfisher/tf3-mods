-- Phase 8 (PROBE.md "Phase 8: bridge probe"): the DEV Bridge probe entries (sqrb_probe_bridge*.con.lua),
-- their post-processing (sqrb_probe_bridge.lua) and the p8_bridge sweep.

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_roundabouts_probe/"
local H = loadfile(here .. "helpers.lua", "t", _ENV)()
local rb = H.loadRoundabouts()
local result = H.rbRequire("square_roundabouts::/infrastructure/street_construction/square_roundabouts_result.lua")
local bridge = ug_require "/infrastructure/street_construction/sqrb_probe_bridge.lua"
local grid = ug_require "/probe/probe_grid.lua"
local geomInfo = ug_require "/probe/probe_geom.lua"
local engineMod = ug_require "/probe/probe_engine.lua"

ug_require "/infrastructure/street_construction/sqrb_probe_bridge.con.lua"
local CON_RB = data()
ug_require "/infrastructure/street_construction/sqrb_probe_bridge_ix.con.lua"
local CON_IX = data()
ug_require "/infrastructure/street_construction/sqrb_probe_bridge.script.lua"
local SCRIPT = data()

local function byKey(con)
	local out = {}
	for i, p in ipairs(con.params) do out[p.key] = p; p.pos = i end
	return out
end

test("the two con.lua: DEV names, probe params (bridge type, structure, islands) last, main params with the main keys and values", function()
	for _, con in ipairs({ CON_RB, CON_IX }) do
		ok(con.description.name:sub(1, 4) == "DEV " and con.description.name:find("NOT FOR UPLOAD", 1, true), con.description.name)
		local n = #con.params
		eq(con.params[n - 2].key, bridge.KEYS.bridgeType)
		eq(#con.params[n - 2].values, #bridge.BRIDGE_TYPE_NAMES)
		eq(con.params[n - 1].key, bridge.KEYS.structure)
		eq(con.params[n].key, bridge.KEYS.islands)
		eq(#con.params[n - 1].values, 4); eq(#con.params[n].values, 2)
		eq(bridge.readParams({ [bridge.KEYS.structure] = con.params[n - 1].defaultIndex, [bridge.KEYS.islands] = con.params[n].defaultIndex }),
			bridge.readParams({}))
		for _, p in ipairs(con.params) do eq(p.location, "Toolbar", p.key) end
	end
	eq(CON_RB.updateScript.fileName, "sqrb_probe_bridge.script@updateFn")
	eq(CON_IX.updateScript.fileName, "sqrb_probe_bridge.script@updateFnIx")
	-- every other param is a param of the real entry, same key, same number of values
	local pairsOf = {
		{ CON_RB, H.loadCon("square_roundabouts.con.lua") },
		{ CON_IX, H.loadCon("square_roundabouts_interchange.con.lua") },
	}
	for _, pr in ipairs(pairsOf) do
		local real = byKey(pr[2])
		for i = 1, #pr[1].params - 3 do
			local p = pr[1].params[i]
			ok(real[p.key], p.key)
			eq(#p.values, #real[p.key].values, p.key)
		end
	end
	-- the interchange probe has every interchange param but Structure (sqrb_structure: its own Probe
	-- structure replaces it; the probe's updateFns build Embankment, then apply the probe params)
	local ixParams = H.loadCon("square_roundabouts_interchange.con.lua").params
	eq(ixParams[#ixParams].key, "sqrb_structure")
	eq(#CON_IX.params - 3, #ixParams - 1)
end)

local function readIx(p) return rb.interchange.readParams(p) end

test("Embankment + keep = the main mod's result exactly (roundabout and interchange)", function()
	local p = { [rb.geom.PARAM_KEYS.island] = 2 }
	eq(SCRIPT.updateFn({}, p), result.build(rb.geom.build(rb.geom.readParams(p))))
	eq(SCRIPT.updateFnIx({}, p), result.build(rb.interchange.build(readIx(p))))
end)

test("Probe bridge picks the bridge type of the Bridge structures", function()
	for t = 1, #bridge.BRIDGE_TYPE_LABELS do
		for _, entry in ipairs({ "rb", "ix" }) do
			local p = { [rb.geom.PARAM_KEYS.island] = 2, [bridge.KEYS.structure] = 2, [bridge.KEYS.bridgeType] = t, year = 1960 }
			local base = entry == "rb" and result.build(rb.geom.build(rb.geom.readParams(p))) or result.build(rb.interchange.build(readIx(p)))
			local res = entry == "rb" and SCRIPT.updateFn({}, p) or SCRIPT.updateFnIx({}, p)
			local want = bridge.BRIDGE_TYPE_NAMES[t] or rb.ramps.BRIDGE_STEEL
			for i, el in ipairs(res.edgeLists) do
				eq(el.edgeType, "BRIDGE", entry .. " " .. t)
				eq(el.edgeTypeName, base.edgeLists[i].edgeTypeName or want, entry .. " " .. t)
			end
		end
	end
end)

test("every structure x islands: edge types, alignTerrain, islands", function()
	for _, entry in ipairs({ "rb", "ix" }) do
		for structure = 1, 4 do
			for islands = 1, 2 do
				for _, year in ipairs({ 1969, 2020 }) do
					local p = { [rb.geom.PARAM_KEYS.island] = 2, [bridge.KEYS.structure] = structure, [bridge.KEYS.islands] = islands, year = year }
					local base = entry == "rb" and result.build(rb.geom.build(rb.geom.readParams(p))) or result.build(rb.interchange.build(readIx(p)))
					local res = entry == "rb" and SCRIPT.updateFn({}, p) or SCRIPT.updateFnIx({}, p)
					local tag = entry .. " structure " .. structure .. " islands " .. islands .. " " .. year
					eq(#res.edgeLists, #base.edgeLists, tag)
					local wantName = year < 1970 and rb.ramps.BRIDGE_STEEL or rb.ramps.BRIDGE_CONCRETE
					for i, el in ipairs(res.edgeLists) do
						local b = base.edgeLists[i]
						eq(el.edges, b.edges, tag)
						eq(el.freeNodes, b.freeNodes, tag)
						if structure == 2 or structure == 4 then
							eq(el.edgeType, "BRIDGE", tag)
							-- the interchange's own bridges keep their type
							eq(el.edgeTypeName, b.edgeTypeName or wantName, tag)
						else
							eq(el.edgeType, b.edgeType, tag)
							eq(el.edgeTypeName, b.edgeTypeName, tag)
						end
						if structure == 3 or structure == 4 then eq(el.alignTerrain, false, tag) else eq(el.alignTerrain, nil, tag) end
					end
					ok(base.subconstructions ~= nil, tag .. ": Grass makes islands")
					if islands == 2 then
						eq(res.subconstructions, nil, tag); eq(res.models, {}, tag); eq(res.groundFaces, {}, tag)
						eq(res.terrainAlignmentLists, nil, tag)
					else
						eq(res.subconstructions, base.subconstructions, tag)
					end
				end
			end
		end
	end
	-- some interchange list is a bridge already, some is not (Bridge mode changes the rest)
	local base = result.build(rb.interchange.build(readIx({})))
	local nb, nn = 0, 0
	for _, el in ipairs(base.edgeLists) do if el.edgeType == "BRIDGE" then nb = nb + 1 else nn = nn + 1 end end
	ok(nb > 0 and nn > 0, nb .. " / " .. nn)
end)

test("p8_bridge: 800 placed combos, dz / context on the place, probe params sent, sane geometry", function()
	local combos = grid.expand("p8_bridge")
	eq(#combos, (8 + 2) * 4 * 2 * 5 * 2); eq(grid.size("p8_bridge"), #combos)
	local keys, per, dzs, ctxs = {}, {}, {}, {}
	for _, c in ipairs(combos) do
		ok(not keys[c.key], "duplicate " .. c.key); keys[c.key] = true
		ok(c.entry == "bridge_main" or c.entry == "bridge_ix", c.entry)
		per[c.entry] = (per[c.entry] or 0) + 1
		ok(c.place and c.search == nil, c.key)
		eq(c.place.rot, 0); eq(c.place.dx, 0); eq(c.place.dy, 0)
		dzs[c.place.dz] = true; ctxs[c.place.ctx] = true
		eq(c.params.dz, nil); eq(c.params.ctx, nil)
		ok(c.params.sqrb_probe_structure >= 1 and c.params.sqrb_probe_structure <= 4, c.key)
		ok(c.params.sqrb_probe_islands == 1 or c.params.sqrb_probe_islands == 2, c.key)
		eq(c.params.sqrb_island, 2, c.key)
		local l = grid.labelsByKey(c.entry, c)
		eq(tostring(c.place.dz), l.dz); eq(c.place.ctx, l.context)
		local g = geomInfo.forEntry(c.entry, rb, c.params)
		ok(g.error == nil and g.sane, c.key .. ": " .. tostring(g.error or g.insane))
		local nodes, err = geomInfo.nodes(c.entry, rb, c.params)
		ok(nodes and #nodes > 4, c.key .. ": " .. tostring(err))
	end
	eq(per.bridge_main, 640); eq(per.bridge_ix, 160)
	for _, z in ipairs({ 0, 2, 4, 8, 12 }) do ok(dzs[z], "dz " .. z) end
	ok(ctxs.none and ctxs.full)
	-- the R line carries the probe axes and the place; the D line the dz
	local _, f = H.parseLine(grid.resultLine(1, 1, combos[1], { ok = true }))
	eq(f.entry, combos[1].entry); ok(f.structure and f.islands and f.dz and f.context and f.rot, "fields")
	eq(grid.placeLabel(combos[1].place), "r0_none_0_0_z0")
	eq(grid.placeLabel({ rot = 0, ctx = "none", dx = 0, dy = 0 }), "r0_none_0_0", "older labels unchanged")
end)

test("engine: the probe entries resolve in this mod; dz raises the transf like the builder's Height", function()
	local logs = {}
	local e = engineMod.new({ context = "none", pos = "setting", x = 0, y = 0 }, function(l) logs[#logs + 1] = l end)
	e.modules = rb
	e.player = 7
	local tried, made = {}, {}
	local function vec(...) return { ... } end
	local saved = api
	api = {
		type = {
			Vec2f = { new = function(x, y) return { x = x, y = y } end },
			Vec4f = { new = vec },
			Mat4f = { new = vec },
			Context = { new = function() return {} end },
			SimpleProposal = { new = function() return {} end, ConstructionEntity = { new = function() return {} end } },
			ComponentType = {},
		},
		res = { constructionRep = { find = function(name)
			tried[#tried + 1] = name
			return name:sub(1, 26) == "square_roundabouts_probe::" and 9 or -1
		end } },
		engine = {
			terrain = {
				getHeightAt = function() return 50 end,
				isOnWater = function() return false end,
				isValidCoordinate = function() return true end,
			},
			entityExists = function() return false end,
			getComponent = function() return nil end,
			util = { construction = { getConstructionResult = function() return {} end }, proposal = { makeProposalData = function(sp)
				made[#made + 1] = { transf = sp.constructionsToAdd[1].transf, params = sp.constructionsToAdd[1].params,
					file = sp.constructionsToAdd[1].fileName }
				return { errorState = { critical = false, messages = {} }, collisionInfo = {}, costs = 1,
					terrainPreviewHeightModCutFill = {} }
			end } },
		},
	}
	local okCall, err = pcall(function()
		e:placement()
		eq(e:resolveFile("bridge_ix"), "square_roundabouts_probe::/infrastructure/street_construction/sqrb_probe_bridge_ix.con")
		eq(e:resolveFile("bridge_main"), "square_roundabouts_probe::/infrastructure/street_construction/sqrb_probe_bridge.con")
		local c
		for _, k in ipairs(grid.expand("p8_bridge")) do
			if k.entry == "bridge_main" and k.place.dz == 8 and k.place.ctx == "full" then c = k break end
		end
		return e:evaluate(c)
	end)
	api = saved
	ok(okCall, tostring(err))
	eq(err.ok, true)
	local m = made[#made]
	eq(m.file, "square_roundabouts_probe::/infrastructure/street_construction/sqrb_probe_bridge.con")
	eq(m.transf[4][3], 58, "z = getHeightAt + dz")
	eq(m.params.dz, nil); ok(m.params.sqrb_probe_structure ~= nil)
	local kind, f = H.parseLine(logs[#logs])
	eq(kind, "D"); eq(f.dz, "8"); eq(f.ctx, "full"); eq(f.oz, "58.00")
	-- the node at the ring's height is 8 m above the flat terrain
	eq(f.fillMax, "8.00")
end)
