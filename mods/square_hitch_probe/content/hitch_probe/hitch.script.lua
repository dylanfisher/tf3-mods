-- Hitch probe game script: while the GUI's level asks for it, busy-waits gs ms once every PERIOD_TICKS
-- frames inside update, the way a long sweep (Auto Assign Terminals) holds the simulation step.
-- Logs each pause with the tickCount so the report can line it up with the GUI's frame times.
-- State (kept in the save): { burnMs, period = last tickCount // PERIOD_TICKS that paused }. The period
-- lives in the shared state, not a local, because update runs in several simulation Lua states.

local common = require "square_hitch_probe::/hitch_probe/hitch_common.lua"

local subscribed = false
local vm = common.vm()

local script = {}

function script.update(_userParams, state, _dt)
	if not subscribed then
		subscribed = true
		state:subscribeToEvent("level")
	end
	local s = state:get() or {}
	local ms = s.burnMs or 0
	if ms <= 0 then return end
	local tick, upd = common.ticks()
	local period = math.floor(tick / common.PERIOD_TICKS)
	if s.period == period then return end
	s.period = period
	state:set(s)
	local real = common.burn(ms)
	common.log(string.format("side=gs burn want=%d ms=%.2f tick=%d upd=%d vm=%s", ms, real, tick, upd, vm))
end

function script.handleEvent(_userParams, state, _src, id, name, param)
	if id ~= common.EVENT_ID or name ~= "level" or type(param) ~= "table" then return end
	local s = state:get() or {}
	s.burnMs = tonumber(param.gs) or 0
	s.period = nil
	state:set(s)
	local tick, upd = common.ticks()
	common.log(string.format("side=gs level=%s gs=%d tick=%d upd=%d vm=%s", tostring(param.label), s.burnMs, tick, upd, vm))
end

-- .script.lua resources expose their exports through data(), not a return value
function data()
	return script
end
