-- DEV name scripts for the "DEV TSN Probe" name set. Contract: docs/wiki/modding/misc/names.md
-- (params.lang, params.num; num == -1 means "all names"). Reference: base names/names.script.lua.
--
-- Towns: Washington cities first, so a new game gets towns called Seattle, Tacoma, ... to test with.
-- Streets: "Probe Street 01".."Probe Street 80" in a fixed order (no shuffle), so a stop's default
-- name tells which pool entry the engine used and in which order it consumes the pool.
-- Every call logs "[SQTSN_PROBE] names <kind> call=<n> lang=<l> num=<n> clock=<s> -> <count> first=<..>".

local TAG = "[SQTSN_PROBE] "
local log_message_fn = nil
pcall(function() if type(log) == "table" and type(log.message) == "function" then log_message_fn = log.message end end)

local WA_TOWNS = {
	"Seattle", "Tacoma", "Spokane", "Bellevue", "Everett", "Olympia", "Yakima", "Bellingham",
	"Vancouver", "Kent", "Renton", "Redmond", "Kirkland", "Wenatchee", "Walla Walla", "Pasco",
}

local calls = { towns = 0, streets = 0, persons = 0 }

-- print() lines carry no thread column; log.message does (shows which Lua state runs the name scripts).
local function log(msg)
	print(TAG .. msg)
	if type(log_message_fn) == "function" then pcall(log_message_fn, TAG .. msg) end
end

local function describe(kind, params, res)
	calls[kind] = calls[kind] + 1
	local lang = params and params.lang or "?"
	local num = params and params.num or "?"
	local first = {}
	for i = 1, math.min(#res, 4) do first[#first + 1] = tostring(res[i]) end
	log(string.format("names %s call=%d lang=%s num=%s clock=%.2f -> %d first=%s",
		kind, calls[kind], tostring(lang), tostring(num), os.clock(), #res, table.concat(first, " | ")))
end

--- Climate probe (plans/square_state_names/PLAN.md "Probe 3"): what can a name script see?
--- Logs once per kind per Lua state: Lua version, api/api.engine presence, getConfigDict().climate,
--- getModParams()[""].isMapEditor, the global our runFn sets (content/mod.script.lua), and `game`.
local ctxLogged = {}
local function context(kind)
	if ctxLogged[kind] then return end
	ctxLogged[kind] = true
	local _, a = pcall(function() return api end)
	local parts = { "ctx " .. kind, "_VERSION=" .. tostring(_VERSION), "api=" .. type(a) }
	local hasEngine = type(a) == "table" and a.engine ~= nil
	parts[#parts + 1] = "api.engine=" .. tostring(hasEngine)
	local ok, cfg = pcall(function() return api.engine.config.getConfigDict() end)
	if ok and cfg ~= nil then
		local ok2, cl = pcall(function() return cfg.climate end)
		local ok3, nl = pcall(function() return cfg.nameList end)
		parts[#parts + 1] = "getConfigDict climate=" .. tostring(ok2 and cl) .. " nameList=" .. tostring(ok3 and nl)
	else
		parts[#parts + 1] = "getConfigDict FAILED " .. tostring(cfg)
	end
	local okp, mp = pcall(function() return api.engine.config.getModParams()[""] end)
	parts[#parts + 1] = "getModParams[\"\"]=" .. (okp and type(mp) or ("FAILED " .. tostring(mp)))
	if okp and type(mp) == "table" then parts[#parts + 1] = "isMapEditor=" .. tostring(mp.isMapEditor) end
	-- Globals read inside pcall: a strict-globals sandbox would throw on an undeclared name.
	local _, g = pcall(function() return SQTSN_PROBE_RUNFN end)
	if type(g) == "table" then
		parts[#parts + 1] = string.format("runFnGlobal climate=%s nameList=%s states=%s", tostring(g.climate),
			tostring(g.nameList), tostring(g.n))
	else
		parts[#parts + 1] = "runFnGlobal=" .. type(g)
	end
	local _, gm = pcall(function() return game end)
	parts[#parts + 1] = "game=" .. type(gm)
	parts[#parts + 1] = "logmsg=" .. tostring(log_message_fn ~= nil)
	log("names " .. table.concat(parts, " | "))
end

local function baseUsaTowns()
	local ok, t = pcall(require, "::/names/usa/en/towns.lua")
	if ok and type(t) == "table" then return t end
	log("names towns: could not load base usa towns: " .. tostring(t))
	return {}
end

local function allTowns()
	local out = {}
	for _, n in ipairs(WA_TOWNS) do out[#out + 1] = n end
	for _, n in ipairs(baseUsaTowns()) do out[#out + 1] = n end
	return out
end

local function allStreets()
	local out = {}
	for i = 1, 80 do out[#out + 1] = string.format("Probe Street %02d", i) end
	return out
end

local function townsFn(_captureParams, params)
	pcall(context, "towns")
	local all = allTowns()
	local res = {}
	local num = params and params.num or -1
	if num < 0 then
		res = all
	else
		for i = 1, num do res[#res + 1] = all[((i - 1) % #all) + 1] end
	end
	local ok, err = pcall(describe, "towns", params, res)
	if not ok then print(TAG .. "names towns log failed: " .. tostring(err)) end
	return res
end

local function streetsFn(_captureParams, params)
	pcall(context, "streets")
	local all = allStreets()
	local res = {}
	local num = params and params.num or -1
	if num < 0 then
		res = all
	else
		-- Positive num: hand out pool entries in order, continuing across calls, so repeats show up.
		local start = calls.streets * 7
		for i = 1, num do res[#res + 1] = all[((start + i - 1) % #all) + 1] end
	end
	local ok, err = pcall(describe, "streets", params, res)
	if not ok then print(TAG .. "names streets log failed: " .. tostring(err)) end
	return res
end

-- Person names: base usa parts if the base util loads, else a fixed name. Logs the first 3 calls and
-- every 200th, so we learn when the engine asks (per new sim person?) and from which state.
local personParts = nil
local function personsFn(_captureParams, params)
	pcall(context, "persons")
	calls.persons = calls.persons + 1
	if personParts == nil then
		local ok, util = pcall(require, "::/names/personnameutil.lua")
		personParts = (ok and type(util) == "table" and util.usa and util.usa.en) or false
		if not personParts then log("names persons: base personnameutil not loadable: " .. tostring(util)) end
	end
	local name = "Probe Person"
	if personParts then
		local first = (params and params.isMale) and personParts.firstNamesMale or personParts.firstNamesFemale
		name = first[math.random(#first)] .. " " .. personParts.lastNames[math.random(#personParts.lastNames)]
	end
	if calls.persons <= 3 or calls.persons % 200 == 0 then
		log(string.format("names persons call=%d lang=%s isMale=%s clock=%.2f -> %s", calls.persons,
			tostring(params and params.lang), tostring(params and params.isMale), os.clock(), name))
	end
	return name
end

function data()
	return {
		personsFn = personsFn,
		townsFn = townsFn,
		streetsFn = streetsFn,
	}
end
