-- DEV probe runScript (plans/square_state_names/PLAN.md "Probe 3"). runFn runs in ~50 Lua states per load
-- (docs/findings.md). It only stores the config dict's climate and name list in a global, so the name
-- set script (content/names/tsn_probe/tsn_probe_names.script.lua) can report whether it shares a Lua state
-- with runFn ("runFnGlobal climate=..." in its "names ctx" line). Signature per docs/findings.md:
-- runFn(captureParams, configDict, allModParams). Plain Lua, pre-5.3.

function data()
	return {
		runFn = function(_captureParams, configDict, _allModParams)
			pcall(function()
				-- rawset: a plain assignment hits base init.lua's _G.__newindex, which logs
				-- "Global variable in mod" in every Lua state (docs/findings.md).
				local prev = rawget(_G, "SQTSN_PROBE_RUNFN")
				rawset(_G, "SQTSN_PROBE_RUNFN", {
					climate = configDict and configDict.climate,
					nameList = configDict and configDict.nameList,
					n = ((type(prev) == "table" and prev.n) or 0) + 1,
				})
			end)
		end,
	}
end
