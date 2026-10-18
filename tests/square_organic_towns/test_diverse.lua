-- Neighbour diversity (ot_diverse, 2026-10-13). User: "Can we make sure we try not to have the same town style near
-- another town?", refined: character variation (form / shape) over regional style ids, the terrain first. A town's
-- style / shape / form draw down-weights what the towns within ot_diverse.RADIUS use (saved frames, or a lower town id
-- picked earlier this session).

local here = debug.getinfo(1, "S").source:match("^@(.*/)") or "tests/square_organic_towns/"
local F = loadfile(here .. "fixtures.lua", "t", _ENV)()
local DV = ug_require(F.DIR .. "ot_diverse.lua")
local T = ug_require(F.DIR .. "ot_terrain.lua")
local I = ug_require(F.DIR .. "ot_inputs.lua")
local ST = ug_require(F.DIR .. "ot_style.lua")

local EU = "::/names/europe/europe.names"
local FLAT = T.stats(F.flat, 0, 0, 600, 24)

--- A cluster of n x n towns `spacing` m apart on similar flat sites (ids base + k, picked in id order as the head start
--- does). Returns the list { {id, x, y, style, form, shape} }.
local function cluster(base, n, spacing, on)
	local saved = DV.ON
	DV.ON = on
	local towns, picked = {}, {}
	F.withForms(function()
		local k = 0
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				k = k + 1
				-- (a little jitter so the distances differ)
				local id = base + k
				local x, y = i * spacing + (id * 37) % 300, j * spacing + (id * 53) % 300
				towns[#towns + 1] = { id = id, x = x, y = y }
			end
		end
		local cands = {}
		for _, t in ipairs(towns) do cands[#cands + 1] = { t.id, t.x, t.y } end
		for _, t in ipairs(towns) do
			local nb = DV.gather(t.id, { t.x, t.y }, cands, nil, function(id) return picked[id] end)
			local inputs = I.build({ townId = t.id, pos = { t.x, t.y }, capacity = 1500, year = 1900, nameList = EU,
				terrain = FLAT, autoStyle = true, nbrPicks = nb })
			local st = ST.resolve(inputs)
			t.style, t.form, t.shape = st.id, st.form and st.form.id or "-", st.shape and st.shape.id or "-"
			t.nbr, t.pen = DV.nbrText(nb), DV.penText(inputs)
			picked[t.id] = { style = t.style, form = st.form and st.form.id or nil, shape = st.shape and st.shape.id or nil }
		end
	end)
	DV.ON = saved
	return towns
end

--- Pairs of towns within `r` m sharing the form / the shape / the style, and the mean distinct forms among each town and
--- its neighbours within r.
local function sameness(towns, r)
	local out = { pairs = 0, form = 0, shape = 0, style = 0, distinct = 0 }
	for a = 1, #towns do
		local seen, nseen = { [towns[a].form] = true }, 1
		for b = 1, #towns do
			local A, B = towns[a], towns[b]
			local d = math.sqrt((A.x - B.x) ^ 2 + (A.y - B.y) ^ 2)
			if b ~= a and d <= r then
				if not seen[B.form] then seen[B.form], nseen = true, nseen + 1 end
				if b > a then
					out.pairs = out.pairs + 1
					if A.form == B.form then out.form = out.form + 1 end
					if A.shape == B.shape then out.shape = out.shape + 1 end
					if A.style == B.style then out.style = out.style + 1 end
				end
			end
		end
		out.distinct = out.distinct + nseen / #towns
	end
	return out
end

local function pooled(on)
	local acc = { pairs = 0, form = 0, shape = 0, style = 0, distinct = 0 }
	local bases = { 100, 300, 700, 1100, 1900 }
	for _, base in ipairs(bases) do
		local s = sameness(cluster(base, 4, 2500, on), 3000)
		for k, v in pairs(s) do acc[k] = acc[k] + (k == "distinct" and v / #bases or v) end
	end
	return acc
end

test("a cluster of towns on similar sites: neighbours share forms and shapes less often with diversity", function()
	local off, on = pooled(false), pooled(true)
	local function txt(s)
		return string.format("same form %d/%d (%.2f), same shape %d (%.2f), same style %d (%.2f), distinct forms near %.2f",
			s.form, s.pairs, s.form / s.pairs, s.shape, s.shape / s.pairs, s.style, s.style / s.pairs, s.distinct)
	end
	print("        without diversity: " .. txt(off))
	print("        with diversity:    " .. txt(on))
	eq(on.pairs, off.pairs)
	ok(on.form < off.form * 0.7, "fewer neighbour pairs with the same form: " .. on.form .. " vs " .. off.form)
	ok(on.distinct > off.distinct, string.format("more distinct forms near each town: %.2f vs %.2f", on.distinct, off.distinct))
	ok(on.shape < off.shape, "fewer same shapes: " .. on.shape .. " vs " .. off.shape)
	-- styles: weak only (the region's home style stays home: no foreign styles pushed in)
	ok(on.style >= off.style * 0.6, "styles change only a little: " .. on.style .. " vs " .. off.style)
end)

test("deterministic: the same cluster gives the same picks; STYLE fields nbr= / divPen=", function()
	local a, b = cluster(500, 3, 2500, true), cluster(500, 3, 2500, true)
	for i = 1, #a do
		eq(a[i].style .. "/" .. a[i].form .. "/" .. a[i].shape, b[i].style .. "/" .. b[i].form .. "/" .. b[i].shape, "town " .. a[i].id)
	end
	eq(a[1].nbr, "0/-", "the first town has no earlier neighbour")
	ok(a[#a].nbr:match("^%d+/") and tonumber(a[#a].nbr:match("^(%d+)/")) >= 2, a[#a].nbr)
	ok(a[#a].pen:find("form:", 1, true) or a[#a].pen:find("shape:", 1, true), a[#a].pen)
end)

test("factors: closer = stronger, floors, styles weak; no neighbours = no change", function()
	local f = DV.factors({ { dist = 0, form = "clustered" } }, "form")
	ok(math.abs(f.clustered - DV.FORM_MIN) < 1e-9, tostring(f.clustered))
	f = DV.factors({ { dist = DV.RADIUS / 2, form = "clustered" } }, "form")
	ok(f.clustered > DV.FORM_MIN and f.clustered < 1, tostring(f.clustered))
	f = DV.factors({ { dist = DV.RADIUS + 1, form = "clustered" } }, "form")
	eq(f.clustered, nil)
	f = DV.factors({ { dist = 0, form = "linear" }, { dist = 0, form = "linear" }, { dist = 0, form = "linear" } }, "form")
	eq(f.linear, DV.FLOOR)
	f = DV.factors({ { dist = 0, style = "EU_ORGANIC" } }, "style")
	ok(f.EU_ORGANIC >= DV.STYLE_MIN - 1e-9, tostring(f.EU_ORGANIC))
	-- a neighbour's form implies its shape when the shape is unknown
	f = DV.factors({ { dist = 1000, form = "radiating" } }, "shape")
	ok(f.cross and f.cross < 1, "radiating -> cross")
	-- gather: a saved frame counts always, a session pick only for a lower town id
	local cands = { { 5, 1000, 0 }, { 20, 2000, 0 }, { 30, 9000, 0 } }
	local nb = DV.gather(10, { 0, 0 }, cands, function(id) return id == 20 and { form = "wide" } or nil end,
		function(id) return { form = "linear", id = id } end)
	eq(#nb, 2)
	eq(nb[1].town, 5)
	eq(nb[2].form, "wide")
end)

test("saved towns never change; terrain still decides (valley town stays linear)", function()
	F.withForms(function()
		local nb = { { town = 1, dist = 500, style = "EU_ORGANIC", form = "clustered", shape = "compact" },
			{ town = 2, dist = 800, style = "EU_ORGANIC", form = "clustered", shape = "compact" } }
		local frame = { axis = 0.3, origin = { 0, 0 }, style = "EU_ORGANIC", form = "clustered", shape = "compact" }
		local base = { townId = 9, pos = { 0, 0 }, capacity = 1500, year = 1900, nameList = EU, terrain = FLAT,
			autoStyle = true, frame = frame }
		local a = ST.resolve(I.build(base))
		base.nbrPicks = nb
		local b = ST.resolve(I.build(base))
		eq(a.id .. "/" .. a.form.id .. "/" .. a.shape.id, b.id .. "/" .. b.form.id .. "/" .. b.shape.id)
		eq(b.form.id, "clustered")
		-- a valley town: the site's linear evidence is never down-weighted
		local VS = T.stats(F.valley(0.4), 0, 0, 600, 24)
		local lin, n = 0, 0
		for id = 1, 12 do
			local r = { townId = id, pos = { 0, 0 }, capacity = 1500, year = 1900, nameList = EU, terrain = VS, autoStyle = true,
				nbrPicks = { { town = 0, dist = 300, form = "linear", shape = "linear", style = "EU_ORGANIC" } } }
			local st = ST.resolve(I.build(r))
			n = n + 1
			if st.shape.id == "linear" then lin = lin + 1 end
		end
		print(string.format("        valley towns beside a linear neighbour: %d/%d linear", lin, n))
		ok(lin >= n * 0.6, "valley towns stay linear: " .. lin .. "/" .. n)
	end)
end)
