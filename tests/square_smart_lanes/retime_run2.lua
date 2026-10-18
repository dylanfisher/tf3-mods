-- Light plans A/B run 2 (session 2026-10-15_0509_light-plans-auto-863105): every AUTORETIME op=plan line of the
-- six sl_auto junctions, in order (extracted from the log; test_retime.lua "replay run 2"). load: the critical
-- demand per entry lane of phases 1 and 3 over the window; y, cycle_reason, cycle_wanted, cycle, new: as logged.
-- g1v, g5v: 2x2 balanced; g4v: 3x3 balanced; g3v: 2x2 unbalanced; g2v, g6v: 3x3 unbalanced.
return {
	g1v = {
		{ node = 270585, samples = 56, total = 360, queued = 81.4, load = { 58.5, 68.0 }, y = 1.28, reason = "saturated", wanted = 120, cycle = "52>72", old = "24/2/24/2", new = "32/2/36/2", result = "write" },
		{ node = 270585, samples = 55, total = 381, queued = 92.9, load = { 53.1, 71.9 }, y = 1.25, reason = "saturated", wanted = 120, cycle = "72>92", old = "32/2/36/2", new = "38/2/50/2", result = "write" },
		{ node = 270585, samples = 55, total = 380, queued = 103.8, load = { 56.5, 64.9 }, y = 1.21, reason = "saturated", wanted = 120, cycle = "92>112", old = "38/2/50/2", new = "49/2/59/2", result = "write" },
		{ node = 270585, samples = 55, total = 368, queued = 106.8, load = { 54.5, 61.9 }, y = 1.19, reason = "saturated", wanted = 120, cycle = "112>120", old = "49/2/59/2", new = "56/2/60/2", result = "fits" },
		{ node = 270585, samples = 46, total = 364, queued = 106.4, load = { 53.7, 61.0 }, y = 1.20, reason = "saturated", wanted = 120, cycle = "112>120", old = "49/2/59/2", new = "56/2/60/2", result = "fits" },
	},
	g2v = {
		{ node = 32151, samples = 56, total = 364, queued = 12.8, load = { 54.9, 5.8 }, y = 0.67, reason = "webster", wanted = 61, cycle = "62>62", old = "28/3/28/3", new = "45/3/11/3", result = "write" },
		{ node = 32151, samples = 55, total = 384, queued = 21.0, load = { 55.9, 14.7 }, y = 1.17, reason = "saturated", wanted = 120, cycle = "62>82", old = "45/3/11/3", new = "60/3/16/3", result = "write" },
		{ node = 32151, samples = 55, total = 344, queued = 10.6, load = { 41.8, 11.7 }, y = 0.59, reason = "webster", wanted = 49, cycle = "82>62", old = "60/3/16/3", new = "44/3/12/3", result = "write" },
		{ node = 32151, samples = 55, total = 352, queued = 16.0, load = { 47.3, 15.3 }, y = 1.04, reason = "saturated", wanted = 120, cycle = "62>82", old = "44/3/12/3", new = "58/3/18/3", result = "write" },
		{ node = 32151, samples = 57, total = 388, queued = 9.4, load = { 46.7, 10.4 }, y = 0.63, reason = "webster", wanted = 55, cycle = "82>62", old = "58/3/18/3", new = "45/3/11/3", result = "write" },
		{ node = 32151, samples = 60, total = 330, queued = 12.9, load = { 39.4, 15.1 }, y = 0.61, reason = "webster", wanted = 51, cycle = "62>50", old = "45/3/11/3", new = "33/3/11/3", result = "write" },
		{ node = 32151, samples = 60, total = 327, queued = 10.2, load = { 45.8, 15.7 }, y = 0.68, reason = "webster", wanted = 63, cycle = "50>63", old = "33/3/11/3", new = "43/3/14/3", result = "write" },
	},
	g3v = {
		{ node = 306919, samples = 56, total = 275, queued = 32.7, load = { 65.5, 35.3 }, y = 0.90, reason = "queues", wanted = 120, cycle = "52>72", old = "24/2/24/2", new = "42/2/26/2", result = "write" },
		{ node = 306919, samples = 55, total = 350, queued = 30.1, load = { 79.0, 32.8 }, y = 0.91, reason = "saturated", wanted = 120, cycle = "72>92", old = "42/2/26/2", new = "60/2/28/2", result = "write" },
		{ node = 306919, samples = 55, total = 299, queued = 28.4, load = { 66.6, 26.7 }, y = 1.00, reason = "saturated", wanted = 120, cycle = "92>112", old = "60/2/28/2", new = "60/2/48/2", result = "write" },
		{ node = 306919, samples = 55, total = 317, queued = 31.9, load = { 71.6, 27.9 }, y = 0.80, reason = "queues", wanted = 120, cycle = "112>120", old = "60/2/48/2", new = "60/2/56/2", result = "write" },
		{ node = 306919, samples = 57, total = 316, queued = 28.1, load = { 74.6, 23.4 }, y = 0.69, reason = "queues", wanted = 120, cycle = "120>120", old = "60/2/56/2", new = "60/2/56/2", result = "fits" },
		{ node = 306919, samples = 60, total = 316, queued = 28.9, load = { 71.2, 26.3 }, y = 0.74, reason = "queues", wanted = 120, cycle = "120>120", old = "60/2/56/2", new = "60/2/56/2", result = "fits" },
	},
	g4v = {
		{ node = 301887, samples = 56, total = 489, queued = 55.3, load = { 31.8, 36.2 }, y = 1.12, reason = "saturated", wanted = 120, cycle = "62>82", old = "28/3/28/3", new = "36/3/40/3", result = "write" },
		{ node = 301887, samples = 55, total = 437, queued = 73.3, load = { 34.4, 33.3 }, y = 1.12, reason = "saturated", wanted = 120, cycle = "82>102", old = "36/3/40/3", new = "48/3/48/3", result = "write" },
		{ node = 301887, samples = 55, total = 460, queued = 85.3, load = { 36.1, 32.5 }, y = 1.11, reason = "saturated", wanted = 120, cycle = "102>120", old = "48/3/48/3", new = "59/3/55/3", result = "write" },
		{ node = 301887, samples = 55, total = 466, queued = 81.7, load = { 30.4, 41.3 }, y = 1.07, reason = "saturated", wanted = 120, cycle = "120>120", old = "59/3/55/3", new = "54/3/60/3", result = "fits" },
		{ node = 301887, samples = 46, total = 443, queued = 80.7, load = { 39.6, 24.6 }, y = 1.06, reason = "saturated", wanted = 120, cycle = "120>120", old = "59/3/55/3", new = "60/3/54/3", result = "fits" },
	},
	g5v = {
		{ node = 299872, samples = 57, total = 311, queued = 42.0, load = { 54.7, 48.4 }, y = 1.18, reason = "saturated", wanted = 120, cycle = "52>72", old = "24/2/24/2", new = "36/2/32/2", result = "write" },
		{ node = 299872, samples = 57, total = 385, queued = 92.5, load = { 61.9, 65.7 }, y = 1.21, reason = "saturated", wanted = 120, cycle = "72>92", old = "36/2/32/2", new = "44/2/44/2", result = "write" },
		{ node = 299872, samples = 57, total = 374, queued = 100.5, load = { 59.2, 60.0 }, y = 1.21, reason = "saturated", wanted = 120, cycle = "92>112", old = "44/2/44/2", new = "54/2/54/2", result = "write" },
		{ node = 299872, samples = 57, total = 386, queued = 103.4, load = { 57.1, 65.5 }, y = 1.16, reason = "saturated", wanted = 120, cycle = "112>120", old = "54/2/54/2", new = "56/2/60/2", result = "fits" },
		{ node = 299872, samples = 57, total = 371, queued = 107.0, load = { 58.4, 58.4 }, y = 1.18, reason = "saturated", wanted = 120, cycle = "112>120", old = "54/2/54/2", new = "58/2/58/2", result = "fits" },
	},
	g6v = {
		{ node = 294758, samples = 57, total = 293, queued = 5.2, load = { 33.1, 11.6 }, y = 0.50, reason = "min", wanted = 40, cycle = "62>42", old = "28/3/28/3", new = "24/3/12/3", result = "write" },
		{ node = 294758, samples = 57, total = 376, queued = 5.1, load = { 48.9, 7.4 }, y = 0.62, reason = "webster", wanted = 53, cycle = "42>53", old = "24/3/12/3", new = "38/3/9/3", result = "write" },
		{ node = 294758, samples = 57, total = 332, queued = 16.8, load = { 45.9, 17.5 }, y = 1.06, reason = "saturated", wanted = 120, cycle = "53>73", old = "38/3/9/3", new = "50/3/17/3", result = "write" },
		{ node = 294758, samples = 57, total = 330, queued = 9.2, load = { 36.8, 14.8 }, y = 0.57, reason = "webster", wanted = 47, cycle = "73>53", old = "50/3/17/3", new = "34/3/13/3", result = "write" },
		{ node = 294758, samples = 57, total = 357, queued = 5.3, load = { 42.9, 10.6 }, y = 0.59, reason = "webster", wanted = 49, cycle = "53>49", old = "34/3/13/3", new = "34/3/9/3", result = "write" },
		{ node = 294758, samples = 46, total = 332, queued = 4.7, load = { 42.0, 12.7 }, y = 0.60, reason = "webster", wanted = 51, cycle = "49>50", old = "34/3/9/3", new = "34/3/10/3", result = "fits" },
	},
}
