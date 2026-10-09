-- Type definitions for the globals tests/run_tests.py provides, so tests can be
-- written in Teal (test_*.tl) as well as Lua. Not shipped with any mod.

--- Register a test. Tests in a file run in order, sharing one sandbox.
global test : function(name : string, fn : function())
--- Run before every test in this file (e.g. to reset fakes or modules).
global before_each : function(fn : function())

--- Deep equality; on failure the message shows both values.
global eq : function(actual : any, expected : any, msg?: string)
--- Truthiness check.
global ok : function(value : any, msg?: string)
--- |actual - expected| <= eps (default 1e-9).
global near : function(actual : number, expected : number, eps?: number, msg?: string)
--- fn must raise; the error message must contain `pattern` (plain text) if given.
global raises : function(fn : function(), pattern?: string)

--- Make `ug_require(path)` return `value` (exact path string, e.g. "::/scripts/table_util.tl").
global stub_module : function(path : string, value : any)
--- Forget loaded mod modules so the next ug_require re-runs them (stubs are kept).
global reset_modules : function()
--- Set a global visible to tests and mod modules, e.g. set_global("api", fakeApi).
global set_global : function(name : string, value : any)

global record HarnessLogEntry
	level : string
	msg : string
end
--- Calls to the fake `log` since the last clear_logs(), in order.
global log_entries : function() : {HarnessLogEntry}
global clear_logs : function()
