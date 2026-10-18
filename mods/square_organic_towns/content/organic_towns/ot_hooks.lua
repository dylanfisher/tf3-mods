-- Organic Towns: run-time hooks for developer tools (pure, never saved). One table per Lua state (require
-- cache). The DEV mod square_organic_towns_dev, whose game script runs in the same Lua state as ours (game
-- script guiUpdate, Main Thread), writes these fields; without it they keep their defaults and the mod behaves
-- exactly as before. Nothing else writes them.
--   paused    true: the driver starts no new town check (a running job still finishes)
--   devBusy   true while a dev action runs: same effect as paused, so dev builds never race the driver
--   debug     nil: the "Debug log" param decides; true / false override it for this session
--   main      the game script's driver instance (set by ot_gs.script.lua; read-only for dev tools)
--   player    nil / false: builds run without ctx.player (free, the town's streets; since 2026-10-17); true: with the
--             player (charged, then refunded; dev toggle "Build as player")
--   diagnose  true: a pre-check refused with Construction_Not_Possible (and every dry run) is followed by one
--             pre-check per new edge, the failing ones logged as DIAG lines (dev tools turn it on)
--   simNoFills true while the dev Simulate's build round runs (2026-10-14): no dose / upward fill after a build (the
--             Simulate's Fast fill covers them); a lane's far end, a satellite core and a bridge's far bank still dose
--   simRound  the dev Simulate's build round number while it runs, else nil (2026-10-14, ot_satpace: at most one
--             founding per round; the map's growth lands during the rounds)
--   simYears  the dev Simulate's simulated years so far (SATPACE `simYear=`, the summary's decades; the calendar
--             doesn't move), nil without it
--   lockDefault nil: ot_driver.LOCK_DEFAULT ("steer", §69); "steer" / "mod" / "legacy": the lock of the towns framed
--             from now on this session (§65, §69; a town keeps the lock its first build saved, ot_driver.townLockMode)
--   glockDefault nil: ot_driver.GLOCK_DEFAULT; true / false: whether the towns framed from now on this session also
--             get the game's own streets locked and the valves (§67, ot_glock; a town keeps what its frame saved)

return {
	paused = false,
	devBusy = false,
	debug = nil,
	main = nil,
	player = nil,
	diagnose = false,
	simNoFills = false,
	simRound = nil,
	simYears = nil,
	lockDefault = nil,
	glockDefault = nil,
}
