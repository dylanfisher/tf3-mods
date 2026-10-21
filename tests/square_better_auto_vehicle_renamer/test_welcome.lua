-- Better Auto Vehicle Renamer: the welcome window's decision and texts (bavr_welcome.lua): which window shows (first,
-- renumber, stand-down notice, none), when the state is read (a few ticks after load, retries, then never again),
-- the example name, the event payloads, the words sync, and the "\n" line wrapping. PLAN.md "First load of a save",
-- "Phase 3".

local Welcome = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_welcome.lua"
local Settings = ug_require "square_better_auto_vehicle_renamer::/better_auto_vehicle_renamer/bavr_settings.lua"
-- The render tests were written for the first layout (Model + number, automatic separators, no year): pin
-- those three settings unless a test sets them; the defaults test reads Settings.parse directly.
local function P(t, ...)
	local m = { ["bavr.format"] = 1, ["bavr.partSep"] = 1, ["bavr.year"] = 1 }
	for k, v in pairs(t or {}) do m[k] = v end
	return Settings.parse(m, ...)
end


local cfg = P({})
local cfgYes = P({ ["bavr.renumberNext"] = 2 })

test("decide: first (vehicles, no answer), nothing for an empty or answered save, not yet before the count", function()
	eq(Welcome.decide({ ver = 1, count = 12 }, cfg), "first")
	eq(Welcome.decide({ ver = 1, count = 0 }, cfg), nil)
	eq(Welcome.decide({ ver = 1 }, cfg), false, "not counted yet")
	eq(Welcome.decide(nil, cfg), false, "unreadable")
	eq(Welcome.decide({}, cfg), false, "nothing written yet")
	eq(Welcome.decide({ ver = 1, welcome = "apply" }, cfg), nil)
	eq(Welcome.decide({ ver = 1, welcome = "later", count = 5 }, cfg), nil, "Not now, setting No")
end)

test("decide: renumber (Not now + setting Yes) once the untouched vehicles are counted, not with a pass due", function()
	eq(Welcome.decide({ ver = 1, welcome = "later", count = 5 }, cfgYes), "renumber")
	eq(Welcome.decide({ ver = 1, welcome = "later" }, cfgYes), false, "counted at the next cycle end")
	eq(Welcome.decide({ ver = 1, welcome = "later", count = 0 }, cfgYes), nil, "nothing to number")
	eq(Welcome.decide({ ver = 1, welcome = "later", count = 5, pass = {} }, cfgYes), nil)
	eq(Welcome.decide({ ver = 1, welcome = "apply", count = 5 }, cfgYes), nil, "numbered once: never again")
end)

test("decide: stand-down notice once per save, nothing else while Destination Displays is active", function()
	eq(Welcome.decide({ ver = 1, standDown = "destination_displays" }, cfg), "standDown")
	eq(Welcome.decide({ ver = 1, standDown = "destination_displays", sdSeen = 1, count = 4 }, cfg), nil)
end)

test("tick: the state is read at DELAY_TICKS, then every RETRY_TICKS, MAX_TRIES at most; then never again", function()
	local w = Welcome.new()
	local reads = 0
	local value = { ver = 1 } -- not counted yet
	local function read() reads = reads + 1; return value end
	for _ = 1, Welcome.DELAY_TICKS - 1 do eq(Welcome.tick(w, read, cfg), "wait") end
	eq(reads, 0)
	eq(Welcome.tick(w, read, cfg), "wait")
	eq(reads, 1)
	for _ = 1, Welcome.RETRY_TICKS do Welcome.tick(w, read, cfg) end
	eq(reads, 2)
	value = { ver = 1, count = 3 }
	local phase
	for _ = 1, Welcome.RETRY_TICKS do phase = Welcome.tick(w, read, cfg) end
	eq(phase, "show")
	eq(w.kind, "first")
	eq(w.read.count, 3)
	eq(Welcome.tick(w, read, cfg), "shown")
	local n = reads
	for _ = 1, 100 do Welcome.tick(w, read, cfg) end
	eq(reads, n, "no reads after the decision")
end)

test("tick: answered, map editor, unreadable until MAX_TRIES, a read that throws", function()
	local w = Welcome.new()
	local phase
	for _ = 1, Welcome.DELAY_TICKS do phase = Welcome.tick(w, function() return { ver = 1, welcome = "apply" } end, cfg) end
	eq({ phase, w.reason }, { "done", "nothing" })
	w = Welcome.new()
	for _ = 1, Welcome.DELAY_TICKS do phase = Welcome.tick(w, function() return { editor = true } end, cfg) end
	eq({ phase, w.reason }, { "done", "editor" })
	w = Welcome.new()
	local reads = 0
	for _ = 1, Welcome.DELAY_TICKS + Welcome.RETRY_TICKS * (Welcome.MAX_TRIES + 5) do
		phase = Welcome.tick(w, function() reads = reads + 1; error("no state") end, cfg)
	end
	eq({ phase, w.reason }, { "skip", "unreadable" })
	eq(reads, Welcome.MAX_TRIES)
	w = Welcome.new()
	for _ = 1, Welcome.DELAY_TICKS + Welcome.RETRY_TICKS * (Welcome.MAX_TRIES + 5) do
		phase = Welcome.tick(w, function() return { ver = 1 } end, cfg)
	end
	eq({ phase, w.reason }, { "skip", "uncounted" }, "a paused game that never ran")
end)

test("example name follows the settings; payloads; the words sync only when they differ", function()
	eq(Welcome.example(cfg), "Mercedes-Benz Citaro B-0412")
	eq(Welcome.example(P({ ["bavr.model"] = 2, ["bavr.format"] = 5 })), "Bus 12 · B-0412")
	eq(Welcome.example(P({ ["bavr.year"] = 2 })), "Mercedes-Benz Citaro B-0412 (1925)")
	eq(Welcome.payload("apply", true), { op = "welcome", answer = "apply", number = true })
	eq(Welcome.payload("x", nil), { op = "welcome", answer = "later", number = false })
	eq(Welcome.sdSeenPayload(), { op = "sdseen" })
	local en = { B = "Bus", T = "Truck", R = "Tram", L = "Train", S = "Ship", A = "Aircraft", H = "Helicopter" }
	local de = { B = "Bus", T = "Lkw", R = "Strassenbahn", L = "Zug", S = "Schiff", A = "Flugzeug", H = "Hubschrauber" }
	eq(Welcome.wordsDiffer(nil, en), true, "nothing stored yet")
	eq(Welcome.wordsDiffer(en, en), false)
	eq(Welcome.wordsDiffer(en, de), true)
	eq(Welcome.wordsDiffer(en, { B = "" }), false, "garbage is never sent")
	eq(Welcome.wordsPayload(de).words.T, "Lkw")
end)

local function cols(line)
	local n = 0
	for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + (Welcome.wideGlyph(ch) and 2 or 1) end
	return n
end

test("wrapLine: lines within the columns at spaces; CJK between glyphs, never before closing punctuation", function()
	local s = "Every vehicle gets a fleet number and its model name, like Mercedes-Benz Citaro B-0412."
	local out = Welcome.wrapLine(s, 50)
	for l in (out .. "\n"):gmatch("(.-)\n") do ok(cols(l) <= 50, l) end
	eq((out:gsub("\n", " ")), s, "only spaces became line breaks")
	local ja = "すべての車両に保有番号とモデル名が付きます（例：Mercedes-Benz Citaro B-0412）。新しい車両には購入時に番号が付きます。"
	local outJ = Welcome.wrapLine(ja, 50)
	for l in (outJ .. "\n"):gmatch("(.-)\n") do
		ok(cols(l) <= 50 or not l:find(" "), l)
		ok(not l:find("^、") and not l:find("^。") and not l:find("^）"), "no closing punctuation first: " .. l)
	end
	eq((outJ:gsub("[\n ]", "")), (ja:gsub(" ", "")), "nothing lost but the spaces broken at")
	eq(Welcome.wrapLine("short", 50), "short")
	eq(Welcome.wrapLine("a\nb", 50), "a\nb", "existing breaks kept")
	local huge = string.rep("x", 5000)
	eq(Welcome.wrapLine(huge, 50), huge, "capped: returned as it is")
	eq(Welcome.wrapLine(nil, 50), nil)
end)

test("example: per line counting shows the line position; the old marker word makes the words differ", function()
	local S = Settings
	eq(Welcome.example(S.parse({ ["bavr.counter"] = 4 })), "Bus 12 #03 | Mercedes-Benz Citaro (1925)")
	eq(Welcome.example(S.parse(nil)), "B-0412 | Mercedes-Benz Citaro (1925)", "the default stays")
	local w = { B = "Bus", T = "Truck", R = "Tram", L = "Train", S = "Ship", A = "Aircraft", H = "Helicopter" }
	local wo = { B = "Bus", T = "Truck", R = "Tram", L = "Train", S = "Ship", A = "Aircraft", H = "Helicopter",
		O = "(old)" }
	eq(Welcome.wordsDiffer(w, wo), true, "a stored set without the marker word gets it")
	eq(Welcome.wordsDiffer(wo, wo), false)
end)
