-- DEV ONLY (never upload): deterministic PRNG for the Roundabouts Showcase (pure Lua 5.1, no bit
-- ops): Park-Miller "minimal standard" (16807 * state mod 2^31 - 1). Every product stays below
-- 2^53, so doubles compute it exactly and every Lua version gives the same sequence.

local rng = {}
rng.__index = rng

local M = 2147483647

function rng.new(seed)
	local self = setmetatable({}, rng)
	local s = math.floor(tonumber(seed) or 1)
	s = (s * 7919 + 12345) % (M - 1) + 1
	self.state = s
	-- warm up: nearby seeds give unrelated sequences
	for _ = 1, 4 do self:next() end
	return self
end

--- Uniform in [0, 1).
function rng:next()
	self.state = (self.state * 16807) % M
	return (self.state - 1) / (M - 1)
end

--- Integer in [a, b].
function rng:int(a, b)
	local v = a + math.floor(self:next() * (b - a + 1))
	if v > b then v = b end
	return v
end

--- Shuffles list in place (Fisher-Yates).
function rng:shuffle(list)
	for i = #list, 2, -1 do
		local j = self:int(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

return rng
