-- Bulk Bulldozer toolbar status (user request 2026-10-07, PLAN "Toolbar"): the selection is shown
-- in the construction options bar as a two-line status chip instead of the cursor tooltip.
-- PURE: no api.* calls (money is formatted by the caller), unit-tested offline
-- (tests/square_bulk_bulldozer/test_status.lua).

local status : BulkBulldozerStatus = {}

-- The bar is 314 UI px wide with 8 px padding (construction.css.lua:723-727) and the button adds
-- 8 px padding per side (builtin.css.lua:140-145), so ~280 px for text: about 36 body-font
-- characters. Longer lines are clipped here (with "...") rather than cut by the engine.
-- Unverified in game: tune after the first look at the chip.
status.MAX_CHARS = 36
status.MAX_KIND_PARTS = 3

-- Display order and short labels (singular, plural).
local KIND_ORDER : {string} = { "road", "track", "station", "asset", "town_building" }
local KIND_LABEL : {string : {string}} = {
	road = { "road", "roads" },
	track = { "track", "tracks" },
	station = { "station", "stations" },
	asset = { "asset", "assets" },
	town_building = { "building", "buildings" },
}

local function counted(n : integer, label : {string}) : string
	return string.format("%d %s", n, n == 1 and label[1] or label[2])
end

function status.clip(s : string, n : integer) : string
	if s == nil then return "" end
	if #s <= n then return s end
	local cut = n - 3
	if cut < 0 then cut = 0 end
	-- Never cut inside a UTF-8 sequence: back off over continuation bytes (0x80-0xBF).
	while cut > 0 do
		local b = string.byte(s, cut + 1)
		if b == nil or b < 0x80 or b >= 0xC0 then break end
		cut = cut - 1
	end
	return string.sub(s, 1, cut) .. "..."
end

function status.kindSummary(kindCounts : {string : integer}, objects : integer) : string
	local parts : {string} = {}
	for _, k in ipairs(KIND_ORDER) do
		local n = kindCounts ~= nil and kindCounts[k] or nil
		if n ~= nil and n > 0 then parts[#parts + 1] = counted(n, KIND_LABEL[k]) end
	end
	if objects ~= nil and objects > 0 then
		parts[#parts + 1] = counted(objects, { "signal/stop", "signals/stops" })
	end
	if #parts > status.MAX_KIND_PARTS then
		local shown : {string} = {}
		for i = 1, status.MAX_KIND_PARTS do shown[i] = parts[i] end
		return table.concat(shown, " · ") .. " ..."
	end
	return table.concat(parts, " · ")
end

local function text(head : string, detail : string) : BulkBulldozerStatusText
	return { head = status.clip(head, status.MAX_CHARS), detail = status.clip(detail, status.MAX_CHARS) }
end

local HINT_PAINT <const> = "Paint with the left mouse button"

function status.lines(v : BulkBulldozerStatusInput) : BulkBulldozerStatusText
	local n = v.count or 0
	local kinds = status.kindSummary(v.kindCounts, v.objects)
	if v.phase == "committing" then
		return text(string.format("Bulldozing %d...", n), kinds)
	end
	if n > 0 and (v.phase == "painting" or v.phase == "selected") then
		local head = string.format("%d selected", n)
		if v.capped then head = head .. " (max)" end
		if v.cost ~= nil then head = head .. " · " .. v.cost end
		return text(head, kinds)
	end
	if v.result ~= nil then
		return text(v.result.head, v.result.detail)
	end
	if v.phase == "idle" and n > 0 then
		return text("Nothing selected", "Brush: " .. kinds)
	end
	return text("Nothing selected", HINT_PAINT)
end

function status.resultLines(r : BulkBulldozerCommitResult) : BulkBulldozerStatusText
	if r.removed == 0 and r.refused ~= nil then
		return text("Nothing bulldozed", r.refused)
	end
	local head = string.format("Bulldozed %d", r.removed)
	if r.skipped <= 0 then return text(head, HINT_PAINT) end
	head = head .. string.format(" · %d skipped", r.skipped)
	local keys : {string} = {}
	for k in pairs(r.reasons or {}) do keys[#keys + 1] = k end
	table.sort(keys, function(a : string, b : string) : boolean
		if r.reasons[a] ~= r.reasons[b] then return r.reasons[a] > r.reasons[b] end
		return a < b
	end)
	local top : {string} = {}
	for i = 1, math.min(2, #keys) do top[#top + 1] = keys[i] end
	return text(head, #top > 0 and table.concat(top, ", ") or "See the game log")
end

function status.oneLine(t : BulkBulldozerStatusText) : string
	if t == nil then return "" end
	return t.head .. " / " .. t.detail
end

return status
