-- Organic Towns: deterministic hash RNG (no saved state). A town's street plan is a pure function of its
-- seed, so the same town always gets the same master plan across loads; per-increment choices mix in a bucket
-- (e.g. edge count / 16) so retries differ without drifting the plan.
--
-- Park-Miller "minimal standard" generator (multiplier 48271, modulus 2^31 - 1): every product stays below
-- 2^47, exact in doubles, so pre-5.3 Lua (doubles only) and 5.4 (integers) give identical sequences.

local M = {}

local MOD = 2147483647
local MUL = 48271
local floor = math.floor

local function norm(v)
	v = floor(v) % MOD
	if v == 0 then v = 1 end
	return v
end

local function mixNumber(h, v)
	-- floor to an integer, keep the sign apart so -3 and 3 differ
	local n = floor(v)
	if n < 0 then n = -n * 2 + 1 else n = n * 2 end
	-- split into 3 chunks so large values don't lose low bits through the modulus
	local lo = n % 65536
	local mid = floor(n / 65536) % 65536
	local hi = floor(n / 4294967296) % 65536
	h = (h * 31 + lo + 1) % MOD
	h = (h * 31 + mid + 7) % MOD
	h = (h * 31 + hi + 13) % MOD
	return (h * MUL) % MOD
end

local function mixString(h, s)
	for i = 1, #s do h = (h * 31 + s:byte(i)) % MOD end
	return (h * MUL) % MOD
end

--- Hash of any mix of numbers (floored), strings and booleans -> integer in [1, 2^31 - 2].
function M.hash(...)
	local h = 2166136
	local n = select("#", ...)
	for i = 1, n do
		local v = select(i, ...)
		local t = type(v)
		if t == "number" then
			h = mixNumber(h, v)
		elseif t == "string" then
			h = mixString(h, v)
		elseif t == "boolean" then
			h = mixNumber(h, v and 3 or 5)
		else
			h = mixNumber(h, 11)
		end
	end
	-- avalanche: a few generator steps
	h = norm(h)
	for _ = 1, 3 do h = (h * MUL) % MOD end
	return norm(h)
end

--- Town seed: stable per town (entity id + position rounded to metres). `bucket` is optional (nil for the
--- master-plan seed, a number for a per-increment seed).
function M.seed(townId, posX, posY, bucket)
	if bucket == nil then return M.hash("town", townId or 0, posX or 0, posY or 0) end
	return M.hash("town", townId or 0, posX or 0, posY or 0, "inc", bucket)
end

--- Value in [0, 1) from a hash of the arguments (stateless lookups, e.g. per lattice line).
function M.unit(...)
	return (M.hash(...) - 1) / (MOD - 1)
end

-- A non-linear draw (2026-10-15, NEXT_PHASE_BRIEF 64). M.hash is affine mod 2^31 - 1 in its inputs, so
-- M.unit(seed, a) and M.unit(seed, b) for two labels of the same length are the SAME draw shifted by a constant mod 1
-- ("district" and "leadLane": u_district = u_leadLane + 0.649, so every lane-ahead town (u_leadLane < 0.3) was
-- district-rare; "works" = "shape" + 0.430 = "metro" + 0.708), and nearby numbers give near-linear values (seed and
-- seed + 2 correlate -0.31). M.draw puts M.hash through three rounds of x -> (x + c)^5 mod p (a bijection: 5 does not
-- divide p - 1), which breaks both. M.unit is unchanged (every other seeded outcome stays as it was); M.draw is used
-- for the offshoot decisions (ot_works / ot_district eligible, ot_satpace key / need).
local DRAW_C = { 1013904223, 1664525, 22695477 }

--- (a x b) mod MOD for a, b in [0, MOD): exact in doubles (each product below 2^48).
local function mulmod(a, b)
	local bh, bl = floor(b / 65536), b % 65536
	return ((a * bh) % MOD * 65536 + a * bl) % MOD
end

local function pow5(x)
	local x2 = mulmod(x, x)
	return mulmod(mulmod(x2, x2), x)
end

--- Value in [0, 1) from the arguments, like M.unit but well mixed: two labels or nearby numbers give independent draws.
function M.draw(...)
	local h = M.hash(...)
	for r = 1, #DRAW_C do h = pow5((h + DRAW_C[r]) % MOD) end
	h = norm(h)
	return (h - 1) / (MOD - 1)
end

-- Decision draws (2026-10-15, NEXT_PHASE_BRIEF 68). §64 left every other seeded decision on M.unit, so the yes / no
-- gates and kind picks whose labels have the same length were shifted copies of one draw (20000 seeds: resultant 1.000
-- for every same-length pair, below 0.02 for different lengths): forestMode = forestDeep + 0.861, entryTrees =
-- forestMode + 0.806 (10 letters: hug / deep / tree-lined entries hung together), arms3 = shape + 0.028 (5: a cross
-- town's 3-arm chance hung on where cross sat in the shape weights), metro = shape + 0.722, leadLane / mrbLanes,
-- shoreForm = satellite + 0.732, satellite = siteStyle + 0.718 (9), densify / leadEnd / fingers (7), characterForm /
-- satpace:ready / every / phase (13); motif slot 2's gate = slot 1's + a constant (same label, the slot number added
-- linearly). M.decide (M.draw) is what those decisions use now. Each group keeps at most one member on M.unit (an
-- anchor: shape, siteStyle, characterForm, form, characterIsland): a draw is independent of every unit, so no pair is
-- coupled any more and the anchors' picks (and every test town's shape, form and style) stay. v = 1 keeps M.unit for a
-- town whose plan frame was saved before §68 (style.drawV from the frame's `dv`): its re-derived picks (forest mode,
-- entry trees, metro, the cross's arms, the finger count, lead lane, bridge, densify, offshoot readiness, ...) stay
-- what they were. Geometry jitter stays on M.unit.

--- A decision draw in [0, 1): M.draw, or M.unit for v == 1 (a town framed before §68).
function M.decide(v, ...)
	if v == 1 then return M.unit(...) end
	return M.draw(...)
end

local Rng = {}
Rng.__index = Rng

--- New generator. `seed` is any number (normalised into the valid range).
function M.new(seed)
	return setmetatable({ s = norm(seed or 1) }, Rng)
end

--- Float in [0, 1).
function Rng:next()
	self.s = (self.s * MUL) % MOD
	return (self.s - 1) / (MOD - 1)
end

--- Float in [a, b).
function Rng:range(a, b) return a + (b - a) * self:next() end

--- Integer in [a, b].
function Rng:int(a, b)
	local v = a + floor(self:next() * (b - a + 1))
	if v > b then v = b end
	return v
end

--- True with probability p.
function Rng:chance(p) return self:next() < p end

--- Approximately normal (mean 0, sd 1), clamped to [-3, 3]: sum of 4 uniforms (Irwin-Hall), no log/cos.
function Rng:normal()
	local s = self:next() + self:next() + self:next() + self:next()
	local v = (s - 2) * 1.7320508075688772   -- sd of the sum is sqrt(1/3)
	if v > 3 then v = 3 elseif v < -3 then v = -3 end
	return v
end

--- Random element of an array (nil for an empty one).
function Rng:pick(list)
	if #list == 0 then return nil end
	return list[self:int(1, #list)]
end

--- Derived generator: a new stream from this one's seed and a label (does not advance this one).
function Rng:fork(label)
	return M.new(M.hash(self.s, label))
end

return M
