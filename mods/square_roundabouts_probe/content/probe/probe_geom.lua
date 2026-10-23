-- DEV ONLY (never upload): what the Roundabouts geometry chose for a combo (effective radius,
-- forced layout, splitter fork bump; Magic: effective size; channel: slip set-backs; interchange:
-- radius and bridge type; highway: size, loop radius, ramp length, terminals, bridge type), to
-- correlate with the engine verdict.
-- Pure: takes the square_roundabouts geometry modules as arguments (probe.script.lua passes the
-- real ones via ug_require, the tests pass them too). Never raises: errors go into info.error.

local geomInfo = {}

local function countEdges(lists)
	local n = 0
	for _, l in ipairs(lists or {}) do n = n + #(l.edges or {}) end
	return n
end

local function finite(x) return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge end

local function vecOk(v)
	return type(v) == "table" and finite(v[1]) and finite(v[2]) and finite(v[3] or 0)
end

-- Degenerate geometry is never sent to the engine: a NaN in an edge crashes the game outright
-- (PLAN.md "Phase 3 fixes", transition_util.cpp:128). Dev overrides can force layouts the
-- offline model rejects, so the probe checks every edge first.
geomInfo.MIN_CHORD = 1.0   -- m
geomInfo.MIN_TANGENT = 0.5 -- m

--- nil if every edge of the lists is finite and not degenerate, else the reason.
function geomInfo.insane(lists)
	for li, l in ipairs(lists or {}) do
		for ei, e in ipairs(l.edges or {}) do
			local where = tostring(l.role) .. " list " .. li .. " edge " .. ei
			if not (vecOk(e.p0) and vecOk(e.p1) and vecOk(e.t0) and vecOk(e.t1)) then return where .. ": not finite" end
			local dx, dy = e.p1[1] - e.p0[1], e.p1[2] - e.p0[2]
			if math.sqrt(dx * dx + dy * dy) < geomInfo.MIN_CHORD then return where .. ": shorter than " .. geomInfo.MIN_CHORD .. " m" end
			for _, t in ipairs({ e.t0, e.t1 }) do
				if math.sqrt(t[1] * t[1] + t[2] * t[2]) < geomInfo.MIN_TANGENT then return where .. ": tangent too short" end
			end
		end
	end
	return nil
end

local function round2(v)
	if type(v) ~= "number" then return nil end
	return math.floor(v * 100 + 0.5) / 100
end

--- Main entry: geom = square_roundabouts_geometry.lua's module.
function geomInfo.main(geom, params)
	if not geom then return { error = "geometry module unavailable" } end
	local ok, res = pcall(function()
		local built = geom.build(geom.readParams(params))
		local bad = geomInfo.insane(built.lists)
		return {
			effR = built.radius,
			forced = built.forced == true,
			offline = built.offline, -- nil without the dev radius override
			fork = built.spec and built.spec.forkBump or 0,
			a = round2(built.a),
			b = round2(built.b),
			lists = #built.lists,
			edges = countEdges(built.lists),
			sane = bad == nil,
			insane = bad,
		}
	end)
	if ok then return res end
	return { error = tostring(res) }
end

--- Magic entry: magic = square_roundabouts_magic.lua's module.
function geomInfo.magic(magic, params)
	if not magic then return { error = "magic module unavailable" } end
	local ok, res = pcall(function()
		local built = magic.build(magic.readParams(params))
		local bad = geomInfo.insane(built.lists)
		return {
			effSize = built.size,
			rs = round2(built.rs),
			offline = built.offline, -- nil without dev overrides
			lists = built.lists and #built.lists or nil,
			edges = countEdges(built.lists),
			sane = bad == nil,
			insane = bad,
		}
	end)
	if ok then return res end
	return { error = tostring(res) }
end

--- Whether the square_roundabouts tuning table has a splitter rule for the combo's arm road
-- (search jobs with requireRule = "splitter"). Returns nil (has one) or the skip reason.
function geomInfo.needsRule(rule, modules, params)
	if rule ~= "splitter" then return nil end
	local geom = modules.geom
	if not (geom and geom.splitterRule) then return "geometry module has no splitterRule" end
	if geom.splitterRule(geom.readParams(params)) then return nil end
	return "no splitter rule for this arm road in square_roundabouts_tuning.lua yet"
end

--- Channelized Junction: ch = square_roundabouts_channel.lua's module. setback = "main/side" (m).
function geomInfo.channel(ch, params)
	if not ch then return { error = "channel module unavailable" } end
	local ok, res = pcall(function()
		local built = ch.build(ch.readParams(params))
		local bad = geomInfo.insane(built.lists)
		return {
			setback = string.format("%.1f/%.1f", built.setback.main, built.setback.side),
			lists = #built.lists,
			edges = countEdges(built.lists),
			sane = bad == nil,
			insane = bad,
		}
	end)
	if ok then return res end
	return { error = tostring(res) }
end

--- Roundabout Interchange: ix = square_roundabouts_interchange.lua's module. effR = the built
-- radius (slider or grown), bridge = "steel" / "concrete" (from params.year).
function geomInfo.interchange(ix, params)
	if not ix then return { error = "interchange module unavailable" } end
	local ok, res = pcall(function()
		local built = ix.build(ix.readParams(params))
		local bad = geomInfo.insane(built.lists)
		return {
			effR = built.radius,
			forced = built.forced == true,
			bridge = tostring(built.bridge):match("([%w_]+)%.bridge$") or tostring(built.bridge),
			lists = #built.lists,
			edges = countEdges(built.lists),
			sane = bad == nil,
			insane = bad,
		}
	end)
	if ok then return res end
	return { error = tostring(res) }
end

--- Highway Interchange (Phase 7d): hx = square_roundabouts_highway.lua's module. effSize = the
-- built Size value (parclo loop radius or diamond terminal distance, m; a dev hxLoopRadius or
-- growth shows here), effR = the loop radius (parclos only), xm = the diagonal ramps' carriageway
-- node |x| (ramp length along the highway, m), term = "yTi/yTo" terminal distances from the highway
-- axis (m; the diamond has no inner terminal: "-/yTo"), bridge = "steel" / "concrete".
-- Phase 7c2: built as the per-type entry builds it (its captureParams.type = the combo's sqrb_hx_type).
function geomInfo.hxSpec(hx, params)
	if hx.specFor then return hx.specFor({ type = params[hx.PARAM_KEYS.type] }, params) end
	return hx.readParams(params)
end

function geomInfo.highway(hx, params)
	if not hx then return { error = "highway module unavailable" } end
	local ok, res = pcall(function()
		local built = hx.build(geomInfo.hxSpec(hx, params))
		local bad = geomInfo.insane(built.lists)
		local function m(v) return v and string.format("%.1f", v) or "-" end
		return {
			effSize = built.size,
			effR = built.R,
			forced = built.forced == true,
			xm = round2(built.xm),
			term = m(built.yTi) .. "/" .. m(built.yTo),
			bridge = tostring(built.bridge):match("([%w_]+)%.bridge$") or tostring(built.bridge),
			lists = #built.lists,
			edges = countEdges(built.lists),
			sane = bad == nil,
			insane = bad,
		}
	end)
	if ok then return res end
	return { error = tostring(res) }
end

-- Phase 8: the DEV Bridge probe entries (probe_grid.lua bridge_main / bridge_ix) build the main mod's
-- geometry unchanged (sqrb_probe_bridge.script.lua).
geomInfo.GEOMETRY_OF = { bridge_main = "main", bridge_ix = "interchange" }

--- p7_spot (Phase 7e fix-up): the unique edge end points {x, y, z} (construction frame) of a
-- highway / interchange build (Phase 8: also the main roundabout's), or nil + error text. Pure.
function geomInfo.nodes(entry, modules, params)
	entry = geomInfo.GEOMETRY_OF[entry] or entry
	local mod = entry == "highway" and modules.highway or entry == "interchange" and modules.interchange
		or entry == "main" and modules.geom or nil
	if not mod then return nil, "no nodes for entry " .. tostring(entry) end
	local ok, res = pcall(function()
		local built = mod.build(entry == "highway" and geomInfo.hxSpec(mod, params) or mod.readParams(params))
		local out, seen = {}, {}
		for _, l in ipairs(built.lists) do
			for _, e in ipairs(l.edges) do
				for _, p in ipairs({ e.p0, e.p1 }) do
					local k = string.format("%.3f,%.3f,%.3f", p[1], p[2], p[3])
					if not seen[k] then
						seen[k] = true
						out[#out + 1] = { p[1], p[2], p[3] }
					end
				end
			end
		end
		return out
	end)
	if ok then return res end
	return nil, tostring(res)
end

--- A construction-frame point p {x, y, z} in world coordinates for an origin {x, y, z} and a
-- rotation of deg degrees about z (counter-clockwise; the transf rows of engine:transfFor). Pure.
function geomInfo.toWorld(origin, deg, p)
	local a = math.rad(deg or 0)
	local c, s = math.cos(a), math.sin(a)
	return origin[1] + c * p[1] - s * p[2], origin[2] + s * p[1] + c * p[2], origin[3] + (p[3] or 0)
end

function geomInfo.forEntry(entry, modules, params)
	entry = geomInfo.GEOMETRY_OF[entry] or entry
	if entry == "magic" then return geomInfo.magic(modules.magic, params) end
	if entry == "channel" then return geomInfo.channel(modules.channel, params) end
	if entry == "interchange" then return geomInfo.interchange(modules.interchange, params) end
	if entry == "highway" then return geomInfo.highway(modules.highway, params) end
	return geomInfo.main(modules.geom, params)
end

return geomInfo
