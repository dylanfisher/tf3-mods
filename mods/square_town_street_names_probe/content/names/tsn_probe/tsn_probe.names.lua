-- DEV name set: same shape as base names/usa/usa.names.lua. All three scripts are ours and log
-- ([SQTSN_PROBE] names ...) when the engine asks and what the script can see (climate probe, "names ctx").
function data()
return
	{
		name = _("DEV TSN Probe"),
		personNamesScript = {
			fileName = "square_town_street_names_probe::/names/tsn_probe/tsn_probe_names.script@personsFn",
			params = {}
		},
		townNamesScript = {
			fileName = "square_town_street_names_probe::/names/tsn_probe/tsn_probe_names.script@townsFn",
			params = {}
		},
		streetNamesScript = {
			fileName = "square_town_street_names_probe::/names/tsn_probe/tsn_probe_names.script@streetsFn",
			params = {}
		},
	}
end
