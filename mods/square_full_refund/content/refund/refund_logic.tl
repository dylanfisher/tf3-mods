-- Full Refund Window pure ledger logic: no engine calls, so it is unit-tested offline
-- (tests/square_full_refund/test_logic.lua). Types: refund_types.d.tl.

local STATE_VERSION <const> = 1
-- Hard cap on ledger entries (oldest dropped first), so a long road drag can't bloat the save.
local MAX_ENTRIES <const> = 400
-- Seconds for each "Refund window" option (mod.json params, key refundWindow).
local WINDOWS : {number} = { 60.0, 120.0, 300.0, 600.0 }
local DEFAULT_WINDOW <const> = 60.0
-- Segment matching tolerance per coordinate (m). The key is for logs and identity only; matching
-- compares the stored endpoints with this tolerance, so float noise at a rounding boundary can't
-- split one segment into two keys. Distinct parallel roads/tracks are metres apart.
local EDGE_TOL <const> = 0.5

local logic : FullRefundLogic = {}

function logic.windowSeconds(raw : any) : number
	local n = tonumber(raw)
	if n == nil then return DEFAULT_WINDOW end
	-- mod.json "numbers" makes the engine hand us the seconds themselves.
	if n >= 30 and n <= 3600 then return n end
	-- Fallback: an option index. 0-based, as seen in game in preRunFn's allModParams
	-- (plan.md "Phase 1 result"); 4 can only be the 1-based last option.
	local i = math.floor(n)
	if i >= 0 and i <= 3 then return WINDOWS[i + 1] end
	if i == 4 then return WINDOWS[4] end
	return DEFAULT_WINDOW
end

function logic.normalize(s : FullRefundState) : FullRefundState
	if s == nil or type(s) ~= "table" or s.v ~= STATE_VERSION or type(s.ledger) ~= "table" then
		return { v = STATE_VERSION, ledger = {}, pending = nil }
	end
	return s
end

function logic.prune(s : FullRefundState, now : integer, windowMs : integer) : integer
	local kept : {FullRefundEntry} = {}
	for _, en in ipairs(s.ledger) do
		if now - en.t <= windowMs then kept[#kept + 1] = en end
	end
	local dropped = #s.ledger - #kept
	if #kept > MAX_ENTRIES then
		local over = #kept - MAX_ENTRIES
		local capped : {FullRefundEntry} = {}
		for i = over + 1, #kept do capped[#capped + 1] = kept[i] end
		kept = capped
		dropped = dropped + over
	end
	s.ledger = kept
	return dropped
end

function logic.add(s : FullRefundState, entities : {integer}, cost : integer, now : integer) : {FullRefundEntry}
	local added : {FullRefundEntry} = {}
	local n = #entities
	if n == 0 or cost == nil or cost <= 0 then return added end
	local share = math.floor(cost / n)
	local rest = cost - share * n
	-- An entity that is rebuilt keeps one entry only.
	logic.take(s, entities)
	for i, e in ipairs(entities) do
		local c = share
		if i == 1 then c = c + rest end
		local en : FullRefundEntry = { e = e, c = c, t = now }
		s.ledger[#s.ledger + 1] = en
		added[#added + 1] = en
	end
	return added
end

function logic.take(s : FullRefundState, entities : {integer}) : {FullRefundEntry}
	local wanted : {integer : boolean} = {}
	for _, e in ipairs(entities) do wanted[e] = true end
	local taken : {FullRefundEntry} = {}
	local kept : {FullRefundEntry} = {}
	for _, en in ipairs(s.ledger) do
		if en.e ~= nil and wanted[en.e] then taken[#taken + 1] = en else kept[#kept + 1] = en end
	end
	s.ledger = kept
	return taken
end

local function round1(v : number) : number
	return math.floor(v * 10 + 0.5) / 10
end

local function before(a : {number}, b : {number}) : boolean
	for i = 1, 3 do
		local x, y = round1(a[i]), round1(b[i])
		if x ~= y then return x < y end
	end
	return false
end

function logic.edgeKey(p0 : {number}, p1 : {number}) : string, {number}
	local a, b = p0, p1
	if before(b, a) then a, b = p1, p0 end
	local key = string.format("e:%.1f,%.1f,%.1f|%.1f,%.1f,%.1f",
		round1(a[1]), round1(a[2]), round1(a[3]), round1(b[1]), round1(b[2]), round1(b[3]))
	return key, { a[1], a[2], a[3], b[1], b[2], b[3] }
end

local function close(a : {number}, ia : integer, b : {number}, ib : integer, tol : number) : boolean
	for i = 0, 2 do
		if math.abs(a[ia + i] - b[ib + i]) > tol then return false end
	end
	return true
end

function logic.sameEdge(a : {number}, b : {number}, tol : number) : boolean
	if a == nil or b == nil or #a < 6 or #b < 6 then return false end
	if close(a, 1, b, 1, tol) and close(a, 4, b, 4, tol) then return true end
	return close(a, 1, b, 4, tol) and close(a, 4, b, 1, tol)
end

function logic.split(weights : {number}, cost : integer) : {integer}
	local out : {integer} = {}
	local n = #weights
	if n == 0 then return out end
	local total = 0.0
	for _, w in ipairs(weights) do
		if w ~= nil and w > 0 then total = total + w end
	end
	local given, big = 0, 1
	for i, w in ipairs(weights) do
		local f : number
		if total > 0 then
			f = ((w ~= nil and w > 0) and w or 0) / total
		else
			f = 1 / n
		end
		out[i] = math.floor(cost * f)
		given = given + out[i]
		if (weights[i] or 0) > (weights[big] or 0) then big = i end
	end
	-- Rounding remainder to the longest segment.
	out[big] = out[big] + (cost - given)
	return out
end

function logic.takeEdges(s : FullRefundState, edges : {FullRefundEdge}) : {FullRefundEntry}
	local taken : {FullRefundEntry} = {}
	local used : {integer : boolean} = {}
	for _, ed in ipairs(edges) do
		local _, g = logic.edgeKey(ed.p0, ed.p1)
		for i, en in ipairs(s.ledger) do
			if not used[i] and en.g ~= nil and logic.sameEdge(en.g, g, EDGE_TOL) then
				used[i] = true
				taken[#taken + 1] = en
				break
			end
		end
	end
	if #taken > 0 then
		local kept : {FullRefundEntry} = {}
		for i, en in ipairs(s.ledger) do
			if not used[i] then kept[#kept + 1] = en end
		end
		s.ledger = kept
	end
	return taken
end

function logic.addEdges(s : FullRefundState, edges : {FullRefundEdge}, cost : integer, now : integer) : {FullRefundEntry}
	local added : {FullRefundEntry} = {}
	if #edges == 0 or cost == nil or cost <= 0 then return added end
	local weights : {number} = {}
	for i, ed in ipairs(edges) do weights[i] = ed.len or 0 end
	local shares = logic.split(weights, cost)
	-- A segment rebuilt in place keeps one entry only.
	logic.takeEdges(s, edges)
	for i, ed in ipairs(edges) do
		local k, g = logic.edgeKey(ed.p0, ed.p1)
		local en : FullRefundEntry = { k = k, g = g, c = shares[i], t = now }
		s.ledger[#s.ledger + 1] = en
		added[#added + 1] = en
	end
	return added
end

function logic.owed(entries : {FullRefundEntry}, now : integer, windowMs : integer) : integer, integer
	local sum, hits = 0, 0
	for _, en in ipairs(entries) do
		if now - en.t <= windowMs then
			sum = sum + en.c
			hits = hits + 1
		end
	end
	return sum, hits
end

function logic.credit(owed : integer, actualRefund : integer) : integer
	if owed == nil or owed <= 0 then return 0 end
	-- A negative delta (the engine charged a fee) never raises the credit above owed.
	local refunded = actualRefund or 0
	if refunded < 0 then refunded = 0 end
	local c = owed - refunded
	if c <= 0 then return 0 end
	return math.floor(c + 0.5)
end

function logic.fingerprint(entities : {integer}) : string
	-- Order-independent and short: count, sum, min, max.
	local n, sum = #entities, 0
	local lo, hi : integer, integer = nil, nil
	for _, e in ipairs(entities) do
		sum = sum + e
		if lo == nil or e < lo then lo = e end
		if hi == nil or e > hi then hi = e end
	end
	return string.format("%d:%d:%d:%d", n, sum, lo or 0, hi or 0)
end

function logic.classify(numAdd : integer, numRemove : integer) : string
	if numAdd > 0 and numRemove > 0 then return "rebuild" end
	if numAdd > 0 then return "add" end
	if numRemove > 0 then return "remove" end
	return "none"
end

return logic
