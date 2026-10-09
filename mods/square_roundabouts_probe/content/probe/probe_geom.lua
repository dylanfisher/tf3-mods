-- DEV ONLY (never upload): what the Roundabouts geometry chose for a combo (effective radius,
-- forced layout, splitter fork bump; Magic: effective size; channel: slip set-backs; interchange:
-- radius and bridge type), to correlate with the engine verdict.
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

function geomInfo.forEntry(entry, modules, params)
	if entry == "magic" then return geomInfo.magic(modules.magic, params) end
	if entry == "channel" then return geomInfo.channel(modules.channel, params) end
	if entry == "interchange" then return geomInfo.interchange(modules.interchange, params) end
	return geomInfo.main(modules.geom, params)
end

return geomInfo
