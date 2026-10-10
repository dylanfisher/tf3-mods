-- Hitch probe GUI: a button in the mod ridge cycles common.LEVELS and tells the game script by event;
-- react.onStep (Main Thread, once per frame: docs/findings.md "Clock in GUI contexts") times every
-- frame and logs the frame times in chunks of CHUNK frames, each with the tickCount of its frames:
--   [HITCH] side=gui frames level=gs40 tick0=1234 n=240 dt=167,166,412/2,...
-- dt in tenths of a ms; "/k" marks a frame whose tickCount moved by k instead of 1 since the one before.
-- At a gui level the busy-wait runs here, in onStep, as the control that must show up as a slow frame.

local react = ug_require "::/gui/main/react.lua"
local builtin = ug_require "::/gui/main/builtin.lua"
local main_mod_button_area = ug_require "::/gui/main/main_mod_button_area.tl"
local common = require "square_hitch_probe::/hitch_probe/hitch_common.lua"

local CHUNK = 240

local vm = common.vm()
local clock -- api.type.Clock, made on the first onStep (Main Thread)
local lastUs
local level = 1 -- index into common.LEVELS, shared by the callbacks below
local chunk = { tick0 = nil, lastTick = nil, items = {} }
local guiPeriod

local function flush()
	if #chunk.items > 0 then
		common.log(string.format("side=gui frames level=%s tick0=%d n=%d vm=%s dt=%s", common.LEVELS[level].label,
			chunk.tick0, #chunk.items, vm, table.concat(chunk.items, ",")))
	end
	chunk.tick0, chunk.lastTick, chunk.items = nil, nil, {}
end

local function send(idx)
	local lv = common.LEVELS[idx]
	api.cmd.sendCommand(api.cmd.makeScriptingSendEventCmd("", common.EVENT_ID, "level",
		{ label = lv.label, gs = lv.gs, gui = lv.gui }))
end

local function setLevel(idx)
	flush() -- a chunk never spans two levels
	level = idx
	local tick, upd = common.ticks()
	local lv = common.LEVELS[idx]
	common.log(string.format("side=gui level=%s gs=%d gui=%d tick=%d upd=%d vm=%s", lv.label, lv.gs, lv.gui, tick, upd, vm))
	send(idx)
end

local function onFrame()
	if clock == nil then
		clock = api.type.Clock.new()
		lastUs = clock:getTime()
		return
	end
	local now = clock:getTime()
	local dt = now - lastUs
	lastUs = now
	local tick, upd = common.ticks()
	local item = tostring(math.floor(dt / 100 + 0.5))
	if chunk.tick0 == nil then
		chunk.tick0 = tick
	elseif tick - chunk.lastTick ~= 1 then
		item = item .. "/" .. tostring(tick - chunk.lastTick)
	end
	chunk.lastTick = tick
	chunk.items[#chunk.items + 1] = item
	if #chunk.items >= CHUNK then flush() end

	local ms = common.LEVELS[level].gui
	if ms > 0 then
		local period = math.floor(tick / common.PERIOD_TICKS)
		if period ~= guiPeriod then
			guiPeriod = period
			local real = common.burn(ms)
			common.log(string.format("side=gui burn want=%d ms=%.2f tick=%d upd=%d vm=%s", ms, real, tick, upd, vm))
		end
	end
end

local HitchProbePlugin = react.RegisterPluginRecipe(main_mod_button_area.MainModButtonAreaExtension, "HitchProbePlugin", function()
	local shown = react.useState(level)
	local synced = react.useRef(false)
	react.onStep(function()
		if not synced:get() then
			-- a level saved with the game would keep pausing: start every load at "off"
			synced:set(true)
			setLevel(1)
			shown:set(1)
		end
		onFrame()
	end)
	local lv = common.LEVELS[shown:old()] or common.LEVELS[1]
	return builtin.BoxLayout{
		orientation = builtin.type.Orientation.Horizontal,
		children = {
			builtin.Button{
				meta = { tooltip = "DEV Hitch Probe: click for the next fake pause (off, game script 20/40/100 ms, GUI 40 ms)" },
				content = builtin.TextView{ meta = { class = "font-scale-annotation" }, text = "Hitch: " .. lv.label },
				onClick = function()
					local idx = level % #common.LEVELS + 1
					setLevel(idx)
					shown:set(idx)
				end,
			},
		},
	}
end)

-- .script.lua resources expose their exports through data(), not a return value
function data()
	return {
		HitchProbePlugin = HitchProbePlugin,
	}
end
