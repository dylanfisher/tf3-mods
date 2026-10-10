-- aat_params.lua helpers of the optimized implementation: stopSlots and fingerprint.

local params = ug_require "square_aat_perftest::/aat_params.lua"

local function stops(groups)
	local out = {}
	for i, g in ipairs(groups) do out[i] = { stationGroup = g } end
	return out
end

local LISTS = {
	{},
	{ 26160 },
	{ 1, 2 },
	{ 1, 2, 1, 2, 1 },
	{ 5, 5, 5, 5 },
	{ 26160, 300, 26160, 7, 300, 26160, 7 },
	{ 9, 8, 7, 6, 5, 4, 3, 2, 1, 9, 8, 7 },
}

test("stopSlots: the same strings as stopSlot for every stop", function()
	for __, groups in ipairs(LISTS) do
		local list = stops(groups)
		local all = params.stopSlots(list)
		eq(#all, #list, "one slot per stop")
		for i = 1, #list do eq(all[i], params.stopSlot(list, i), "stop " .. i) end
	end
end)

test("stopSlots: counts per group", function()
	eq(params.stopSlots(stops({ 26160, 300, 26160 })), { "26160#1", "300#1", "26160#2" })
end)

test("fingerprint: same input, same result", function()
	local s = "1201.3,1201.4,1201.5,1388.0,1388.1"
	eq(params.fingerprint(s), params.fingerprint(s))
	eq(params.fingerprint(""), params.fingerprint(""))
end)

test("fingerprint: different inputs differ, also with equal length or swapped parts", function()
	local inputs = {
		"", "1201.3", "1201.4", "1201.3,1201.4", "1201.4,1201.3", "1201.3,1201.5", "1202.3,1201.4",
		"10.1,2.11", "10.12,.11", "a", "b", "ab", "ba",
	}
	local long = {}
	for k = 1, 40 do long[k] = (100000 + k) .. "." .. k end
	inputs[#inputs + 1] = table.concat(long, ",")
	long[20] = (100000 + 20) .. "." .. 21
	inputs[#inputs + 1] = table.concat(long, ",")
	local seen = {}
	for __, s in ipairs(inputs) do
		local f = params.fingerprint(s)
		ok(not seen[f], "collision: " .. s .. " and " .. tostring(seen[f]))
		seen[f] = s
	end
end)

test("fingerprint: short and without signature separators", function()
	local long = {}
	for k = 1, 200 do long[k] = (100000 + k) .. "." .. k end
	local f = params.fingerprint(table.concat(long, ","))
	ok(#f <= 24, "short: " .. f)
	ok(not f:find("[#|{}]"), "no separators: " .. f)
end)
