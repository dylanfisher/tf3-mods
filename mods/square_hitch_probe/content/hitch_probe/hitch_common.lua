-- Hitch probe: constants and helpers shared by the game script and the GUI (plain Lua, pre-5.3).

local M = {}

M.EVENT_ID = "SquareHitchProbe"
M.GAME_SCRIPT = "square_hitch_probe::/hitch_probe/hitch.gs"
M.PREFIX = "[HITCH] "
-- one pause per this many ticks. GAME_TIME.tickCount is documented as "once per frame", but in game (2026-10-10,
-- this probe's first run) it moved by 4 about every 200 ms, once per simulation step: ~20/s, so 40 is ~2 s
M.PERIOD_TICKS = 40

-- gs/gui: milliseconds of busy-wait on that side; the GUI cycles through these with its button
M.LEVELS = {
	{ label = "off", gs = 0, gui = 0 },
	{ label = "gs20", gs = 20, gui = 0 },
	{ label = "gs40", gs = 40, gui = 0 },
	{ label = "gs100", gs = 100, gui = 0 },
	{ label = "gui40", gs = 0, gui = 40 },
}

function M.log(msg)
	if log ~= nil and log.message ~= nil then log.message(M.PREFIX .. msg) else print(M.PREFIX .. msg) end
end

--- tickCount, updateCount of the world's GAME_TIME (0, 0 when unreadable)
function M.ticks()
	local ok, gt = pcall(api.engine.getComponent, api.engine.util.getWorld(), api.type.ComponentType.GAME_TIME)
	if ok and gt then return gt.tickCount or 0, gt.updateCount or 0 end
	return 0, 0
end

--- Busy-waits ms milliseconds on the engine's microsecond clock; returns the real ms.
function M.burn(ms)
	local c = api.type.Clock.new()
	local target = ms * 1000
	while c:getTime() < target do end
	return c:getTime() / 1000
end

--- Short id of the calling Lua state (this module's table address).
function M.vm()
	return (tostring(M):match("0x0*(%x+)") or tostring(M):match("(%x+)$") or "?"):sub(-6)
end

return M
