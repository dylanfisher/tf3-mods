-- Shared table of "{{MOD_ID}}" for one Lua state: mod.script.lua runFn stores the config dict's climate here
-- (runFn = { climate, nameList }) as the fallback to its rawset global; names.script.lua reads it. Never saved.
return {}
