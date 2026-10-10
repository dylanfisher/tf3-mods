-- Dumps Highway Interchange edges. Run through tests/run_tests.py's ModRunner (ug_require + Teal),
-- not as a test file.
--
-- Default (no SQRB_HX_KEY): the default build of each type (Phase 7c3: three menu entries, the
-- parclos' Layout button picks A4 / B4 or A2 / B2 / AB2) for tools/render_icon_square_roundabouts.py. Per type a "T <type index>" line, then one line per
-- edge: role, bridge (0/1), p0x p0y t0x t0y p1x p1y t1x t1y (0.1 m), then one HW line per role with its
-- half width. Keep this format: the icon tool parses it.
--
-- Diagnosis (`make hx-dump KEY='h:1,3,2,2,1,1,1,1,2'`, several keys space-separated; the probe CSV's
-- `key` column): per key the plan numbers (R, dx, xm, xb, yb, frame), then every edge with its list,
-- bridge flag, tags (cw / ramp / part), plan + 3D length and end points, edges under 15 m marked
-- "<15". Optional SQRB_HX_DEV='key=value,...' adds dev keys (sqrb_dev_*) to the params.
-- SQRB_HX_UNCAP=1 lifts hx.MAX_REACH (Phase 7e2 cap) to dump the geometry a pre-7e2 probe run built.
local DIR = "square_roundabouts::/infrastructure/street_construction/"
local hx = ug_require(DIR .. "square_roundabouts_highway.lua")

local function getenv(n) return os and os.getenv and os.getenv(n) or nil end
if (getenv("SQRB_HX_UNCAP") or "") ~= "" and hx.MAX_REACH then hx.MAX_REACH = { 1e9, 1e9 } end

-- probe_grid.lua HIGHWAY_AXES order (as verdicts.lua V.hxParams); the 9th value is the year
local ORDER = { "type", "highway", "level", "cross", "size", "rampLength", "armLength", "direction" }
local function keyParams(key)
	local p, i = {}, 0
	for v in key:gsub("^h:", ""):gmatch("[^,]+") do
		i = i + 1
		local n = assert(tonumber(v), "bad key " .. key)
		if ORDER[i] then p[hx.PARAM_KEYS[ORDER[i]]] = n elseif i == 9 then p.year = n == 1 and 1969 or 2020 end
	end
	for kv in (getenv("SQRB_HX_DEV") or ""):gmatch("[^,]+") do
		local k, v = kv:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
		if k then p[k] = tonumber(v) or v end
	end
	return p
end

local function f1(v) return type(v) == "number" and string.format("%.1f", v) or tostring(v) end

local function diagnose(key)
	local b = hx.build(hx.readParams(keyParams(key)))
	local f = b.frame
	print(string.format("== %s  type=%s size=%s R=%s Ro=%s dx=%s xm=%s xmMin=%s yTi=%s yTo=%s xb=%s yb=%s forced=%s bridge=%s mirrored=%s",
		key, b.type, f1(b.size), f1(b.R), f1(b.Ro), f1(b.dx), f1(b.xm), f1(b.xmMin), f1(b.yTi), f1(b.yTo),
		f1(b.xb), f1(b.yb), tostring(b.forced), tostring(b.bridge), tostring(b.mirrored)))
	local fr = {}
	for _, k in ipairs({ "run", "xCross", "hwX", "hwH", "hwRamp", "clear", "corr", "yg", "c", "bridgePiece" }) do
		if f[k] ~= nil then fr[#fr + 1] = k .. "=" .. f1(f[k]) end
	end
	print("   frame " .. table.concat(fr, " "))
	print("   list     B tags            plan   3D     p0 (x y z)              p1 (x y z)")
	for _, l in ipairs(b.lists) do
		for _, e in ipairs(l.edges) do
			local dx, dy, dz = e.p1[1] - e.p0[1], e.p1[2] - e.p0[2], (e.p1[3] or 0) - (e.p0[3] or 0)
			local plan = math.sqrt(dx * dx + dy * dy)
			local tags = table.concat({ e.cw or "-", e.ramp or "-", e.part or "-" }, "/")
			print(string.format("   %-8s %s %-15s %6.1f %6.1f  %7.1f %7.1f %5.1f  %7.1f %7.1f %5.1f%s",
				l.role, l.edgeType and "B" or ".", tags, plan, math.sqrt(plan * plan + dz * dz),
				e.p0[1], e.p0[2], e.p0[3] or 0, e.p1[1], e.p1[2], e.p1[3] or 0, plan < 15 and "  <15" or ""))
		end
	end
end

test("dump", function()
	local keys = getenv("SQRB_HX_KEY")
	if keys and keys ~= "" then
		for key in keys:gmatch("%S+") do diagnose(key) end
		return
	end
	for t = 1, #hx.TYPES do
		-- what the entry's updateFn builds with its defaults (captureParams.type = t)
		local b = hx.build(hx.specFor({ type = t }, {}))
		print("T " .. t)
		for _, l in ipairs(b.lists) do
			for _, e in ipairs(l.edges) do
				print(string.format("E %s %d %.1f %.1f %.1f %.1f %.1f %.1f %.1f %.1f", l.role, l.edgeType and 1 or 0,
					e.p0[1], e.p0[2], e.t0[1], e.t0[2], e.p1[1], e.p1[2], e.t1[1], e.t1[2]))
			end
			print(string.format("HW %s %.2f", l.role, l.halfWidth or -1))
		end
	end
end)
