-- showcase.script.lua: exports through data(); Off does nothing; On waits for the delay.

local config = ug_require "/showcase/sc_config.lua"

local function load(params)
	set_global("api", {
		engine = { config = { getModParams = function() return { [config.MOD_ID] = params } end } },
	})
	clear_logs()
	ug_require "/showcase/showcase.script.lua"
	return data()
end

test("data() exports update and guiUpdate", function()
	local d = load(nil)
	eq(type(d.update), "function")
	eq(type(d.guiUpdate), "function")
end)

test("Run Off: one disabled line, nothing else", function()
	reset_modules()
	local d = load({ sqrb_show_run = 1 })
	for _ = 1, 5 do d.guiUpdate({}, {}, {}) end
	local n = 0
	for _, e in ipairs(log_entries()) do
		local text = e.msg
		if tostring(text):find("disabled", 1, true) then n = n + 1 end
	end
	eq(n, 1)
end)
