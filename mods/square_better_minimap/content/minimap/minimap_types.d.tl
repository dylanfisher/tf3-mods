-- Minimap shared types. Loaded as module "minimap.minimap_types" (every content/**/*.d.tl;
-- tools/tealrt.py def_modules). tealdef/minimap/minimap_types.d.tl is a byte-for-byte editor copy
-- (make check flags drift). Every global name is prefixed SquareMinimap (globals are shared by all
-- loaded mods).

--- World extent of the terrain (api.engine.terrain.getBoundingBox()), in metres.
global record SquareMinimapBox
	minX : number
	minY : number
	maxX : number
	maxY : number
end

--- How world axes map onto the minimap picture: u = (x - minX) / width, v = (y - minY) / height,
--- then swap, then flip. The window always uses DEFAULT_ORIENT (flipY = true: world +Y drawn up,
--- picture rows grow downwards; matched the MapPreviewComp picture in phase 1).
global record SquareMinimapOrient
	flipX : boolean
	flipY : boolean
	swapXY : boolean
end

--- Rectangle in minimap fractions (0..1, origin top-left of the picture).
global record SquareMinimapRect
	x0 : number
	y0 : number
	x1 : number
	y1 : number
end

--- Camera marker layout in whole widget pixels (compared between polls so the overlay only
--- re-renders when something visibly moved).
global record SquareMinimapCamPx
	boxCX : integer   -- footprint box centre
	boxCY : integer
	boxW : integer    -- footprint box size
	boxH : integer
	dotX : integer    -- camera centre
	dotY : integer
	arrowDeg : integer -- view direction, degrees clockwise from picture-up (geom.headingDegrees); nil = unknown
end

--- One industry as read on the GUI thread when the map is built (minimap_hud.script.tl
--- readIndustries): world position (bounding-box centre), icon path, display name.
global record SquareMinimapIndustry
	entity : integer
	x : number
	y : number
	icon : string
	name : string
end

--- An industry marker laid out in a w x h picture: top-left corner in whole pixels (the marker is
--- size x size), plus a localKey that changes with the entity and the position.
global record SquareMinimapMarkerPx
	key : string
	entity : integer
	left : integer
	top : integer
	icon : string
	name : string
end

-- Module: ug_require "square_better_minimap::/minimap/minimap_geom.tl" as SquareMinimapGeom
--- Minimap settings remembered across game loads (stored in the game settings, never the save).
--- Every field may be nil (missing or invalid in the stored table).
global record SquareMinimapPrefs
	posX : number           -- window anchor (top-right) in screen fractions; set together with posY
	posY : number
	pinned : boolean
	sizeIdx : integer
	showIndustries : boolean
	showNet : boolean       -- network layer (roads, tracks, town buildings) on
	hiVis : boolean         -- network layer in the high-visibility palette
	open : boolean          -- a pinned window was open: re-open it after the next load
end

global record SquareMinimapGeom
	DEFAULT_ORIENT : SquareMinimapOrient

	clamp : function(v : number, lo : number, hi : number) : number
	boxFromBounds : function(minX : number, minY : number, maxX : number, maxY : number) : SquareMinimapBox
	--- Picture size in UI pixels: the longer world side gets longSide px, the other keeps the aspect.
	widgetSize : function(box : SquareMinimapBox, longSide : integer, orient : SquareMinimapOrient) : integer, integer
	worldToFrac : function(x : number, y : number, box : SquareMinimapBox, orient : SquareMinimapOrient) : number, number
	fracToWorld : function(fx : number, fy : number, box : SquareMinimapBox, orient : SquareMinimapOrient) : number, number
	--- FloatingLayoutChild h/v gravity that centres a child of childPx on fraction frac of a parentPx parent.
	childGravity : function(frac : number, parentPx : number, childPx : number) : number
	--- Bounding rectangle (clamped to 0..1) of points given as fractions {fx1, fy1, fx2, fy2, ...}.
	rectFromPoints : function(pts : {number}) : SquareMinimapRect
	--- Square of side 2*halfSide metres around (cx, cy), as fractions (camera box fallback).
	rectAround : function(cx : number, cy : number, halfSide : number, box : SquareMinimapBox, orient : SquareMinimapOrient) : SquareMinimapRect
	--- Mouse event position -> fraction of a widget whose corners are p0 (gravity 0,0) and p1 (1,1).
	--- If p0/p1 look normalised (<= 1.5) while the event is in pixels, the event is divided by the
	--- screen size first. Returns fx, fy and whether that normalisation was applied.
	eventToFrac : function(ex : number, ey : number, p0x : number, p0y : number, p1x : number, p1y : number, screenW : number, screenH : number) : number, number, boolean
	--- Camera footprint rect + centre (fractions) -> pixel layout in a w x h widget; boxes are at least minPx.
	clipBox : function(cx : integer, cy : integer, w : integer, h : integer, pw : integer, ph : integer) : integer, integer, integer, integer
	camPx : function(rect : SquareMinimapRect, cx : number, cy : number, w : integer, h : integer, minPx : integer) : SquareMinimapCamPx
	--- Direction (hx, hy) in picture pixels (y down) as whole degrees clockwise from up, 0..359;
	--- nil for a zero or missing vector.
	headingDegrees : function(hx : number, hy : number) : integer
	--- True if both layouts are equal (nil equals only nil).
	sameCamPx : function(a : SquareMinimapCamPx, b : SquareMinimapCamPx) : boolean
	--- Picture size: widgetSize(longSide), widened (keeping the aspect) to at least minW so the
	--- picture fills the window's minimum content width, then the long side capped at maxLong (the
	--- cap wins: extreme strips stay on screen and leave a band beside the picture).
	pictureSize : function(box : SquareMinimapBox, longSide : integer, minW : integer, maxLong : integer, orient : SquareMinimapOrient) : integer, integer
	--- Ground point of a screen-corner ray (near n -> far f) on the plane z = planeZ, at most maxDist
	--- metres from the camera centre (cx, cy); rays at/above the horizon go maxDist along their
	--- ground direction. Returns x, y and whether the ray really hit the plane.
	groundPoint : function(nx : number, ny : number, nz : number, fx : number, fy : number, fz : number, planeZ : number, cx : number, cy : number, maxDist : number) : number, number, boolean
	--- A getPosition() result in screen fractions (pixels are divided by the screen size).
	normalizeScreenPos : function(x : number, y : number, screenW : number, screenH : number) : number, number
	--- Window edges (screen fractions) -> top-right anchor clamped on screen (top >= minTop);
	--- nil, nil for an invalid/hidden/off-screen window.
	windowAnchor : function(left : number, top : number, right : number, bottom : number, minTop : number) : number, number
	--- Round to n decimals (keeps polled view states stable for deepEquals).
	round : function(v : number, decimals : integer) : number
	--- Stored settings table (anything, e.g. edited by hand) -> SquareMinimapPrefs with only valid
	--- fields: a position both inside 0..1 (top kept >= minTop), sizeIdx in 1..nSizes, booleans.
	readPrefs : function(raw : any, nSizes : integer, minTop : number) : SquareMinimapPrefs
	--- Industry icon: the first non-empty path of outputs, else of inputs, else fallback. Also
	--- returns where it came from: "output", "input" or "fallback".
	pickIcon : function(outputs : {string}, inputs : {string}, fallback : string) : string, string
	--- Industries -> markers of size px centred on their position in a w x h picture (clamped to
	--- stay inside it); industries outside the box are dropped. Sorted top to bottom, then left to
	--- right, then by entity (stable drawing order: lower markers drawn over higher ones).
	markerLayout : function(items : {SquareMinimapIndustry}, box : SquareMinimapBox, orient : SquareMinimapOrient, w : integer, h : integer, size : integer) : {SquareMinimapMarkerPx}
end

-- Network layer (phase 6). Module: ug_require "square_better_minimap::/minimap/minimap_net.tl" as SquareMinimapNet

--- World -> image pixel transform (the geom.worldToFrac mapping times the image size):
--- px = ax + bx * u, py = ay + by * v with (u, v) = (x, y), or (y, x) when swap.
global record SquareMinimapNetXform
	swap : boolean
	ax : number
	bx : number
	ay : number
	by : number
	w : integer
	h : integer
end

--- Image-sized counting grid: cells[y * w + x + 1] = towns + streets * UNIT_STREET + tracks * UNIT_TRACK.
global record SquareMinimapNetGrid
	w : integer
	h : integer
	cells : {number}
	dirty : {boolean}  -- per band of BAND_ROWS grid rows: changed since its last encodeBand
end

--- One cached entity, already in image pixels. kind: KIND_NONE (no geometry: drawn as nothing,
--- cached so it isn't read again), KIND_TOWN (rect), KIND_STREET / KIND_TRACK (polyline).
global record SquareMinimapNetItem
	seen : integer    -- stamp of the last scan that listed it (diff)
	kind : integer
	pts : {integer}   -- polyline x1, y1, x2, y2, ... (edges)
	dashed : boolean  -- tunnel
	x0 : integer      -- covered pixel rect, inclusive (buildings)
	y0 : integer
	x1 : integer
	y1 : integer
end

--- Resumable walk over an engine map {key: {id}} into a cache's seen stamps + added ids (net.flattenStep).
global record SquareMinimapNetFlatten
	map : {any : {integer}}
	kind : integer
	stamp : integer
	added : {integer}
	addKind : {integer}
	addedSet : {integer : boolean}
	key : any
	arr : {integer}
	j : integer
	done : boolean
end

--- Resumable sweep of a cache for ids not seen in a scan (net.sweepStep).
global record SquareMinimapNetSweep
	stamp : integer
	removed : {integer}
	key : integer
	done : boolean
end

global record SquareMinimapNet
	UNIT_TOWN : number
	UNIT_STREET : number
	UNIT_TRACK : number
	LAYER_MAX : integer
	KIND_NONE : integer
	KIND_TOWN : integer
	KIND_STREET : integer
	KIND_TRACK : integer
	FLAT_PX : number
	SEG_PX : number
	MAX_SEGS : integer
	DASH_ON : integer
	DASH_PERIOD : integer
	BAND_ROWS : integer
	STRIP_BANDS : integer  -- bands per image strip (one ImageView each)

	--- Image size: longSide px on the longer world side, the other keeps the aspect.
	imageSize : function(box : SquareMinimapBox, orient : SquareMinimapOrient, longSide : integer) : integer, integer
	makeXform : function(box : SquareMinimapBox, orient : SquareMinimapOrient, w : integer, h : integer) : SquareMinimapNetXform
	--- World position -> continuous image pixel coordinates (0..w, 0..h; pixel = floor).
	toPx : function(xf : SquareMinimapNetXform, x : number, y : number) : number, number
	--- World vector (tangent) -> image pixel vector.
	vecToPx : function(xf : SquareMinimapNetXform, dx : number, dy : number) : number, number
	--- Segments for a Hermite curve given in pixels: 1 when nearly straight, else ~SEG_PX each (2..MAX_SEGS).
	curveSegments : function(p0x : number, p0y : number, t0x : number, t0y : number, p1x : number, p1y : number, t1x : number, t1y : number) : integer
	--- Edge curve (world position/tangent at both ends, the engine's cubic Hermite) -> pixel
	--- polyline {x1, y1, ...} without consecutive duplicates (at least one point).
	hermitePolyline : function(xf : SquareMinimapNetXform, p0x : number, p0y : number, t0x : number, t0y : number, p1x : number, p1y : number, t1x : number, t1y : number) : {integer}
	--- World bounding box -> inclusive pixel rect x0, y0, x1, y1 (not clamped).
	rectFromBounds : function(xf : SquareMinimapNetXform, minX : number, minY : number, maxX : number, maxY : number) : integer, integer, integer, integer
	newGrid : function(w : integer, h : integer) : SquareMinimapNetGrid
	--- Bresenham through the points, delta 1 adds / -1 removes `unit`; dashed draws DASH_ON of
	--- every DASH_PERIOD pixels. Returns the pixels changed.
	drawPolyline : function(g : SquareMinimapNetGrid, pts : {integer}, unit : number, delta : integer, dashed : boolean) : integer
	fillRect : function(g : SquareMinimapNetGrid, x0 : integer, y0 : integer, x1 : integer, y1 : integer, unit : number, delta : integer) : integer
	--- Adds (1) or removes (-1) a cached item.
	drawItem : function(g : SquareMinimapNetGrid, it : SquareMinimapNetItem, delta : integer) : integer
	--- Topmost layer of a cell: 0 none, 1 town, 2 street, 3 track.
	layerOf : function(cell : number) : integer
	newFlatten : function(map : {any : {integer}}, kind : integer, stamp : integer, added : {integer}, addKind : {integer}, addedSet : {integer : boolean}) : SquareMinimapNetFlatten
	--- Up to maxItems ids: listed cached items get seen = stamp, unknown ids go to added (once
	--- each, kind in addKind). True when the map is done.
	flattenStep : function(f : SquareMinimapNetFlatten, cache : {integer : SquareMinimapNetItem}, maxItems : integer) : boolean
	newSweep : function(stamp : integer, removed : {integer}) : SquareMinimapNetSweep
	--- Up to maxItems cache entries: ids whose seen ~= stamp go to removed. True when done.
	sweepStep : function(sw : SquareMinimapNetSweep, cache : {integer : SquareMinimapNetItem}, maxItems : integer) : boolean
	--- RGBA colour -> the 4 bytes in the given order ("RGBA", "BGRA", "ARGB", "ABGR"; unknown = RGBA).
	orderColor : function(rgba : {integer}, order : string) : {integer}
	--- RGBA of {none, town, street, track} -> the same in byte order.
	makePalette : function(layers : {{integer}}, order : string) : {{integer}}
	--- RGBA per layer {none, town, street, track}: the normal and the high-visibility palette.
	COLORS_NORMAL : {{integer}}
	COLORS_HIVIS : {{integer}}
	--- The palette (byte order applied) for the hi-vis toggle.
	paletteFor : function(hiVis : boolean, order : string) : {{integer}}
	--- Scheduler action for a palette switch in `phase`: "none", "encode", "restart" or "dirty".
	recolorAction : function(phase : string, hasImage : boolean) : string
	--- True once a switched-off layer's caches have been kept `seconds` (nil since = not parked).
	parkExpired : function(parkedSinceMs : number, nowMs : number, seconds : number) : boolean
	--- Bytes of a w x h image at 4 per pixel.
	expectedLength : function(w : integer, h : integer) : integer
	--- Encodes image rows row0 .. row1 - 1 (0-based) into out (4 bytes per pixel); flipRows takes
	--- the grid's rows bottom-up.
	encodeRows : function(g : SquareMinimapNetGrid, out : {integer}, row0 : integer, row1 : integer, palette : {{integer}}, flipRows : boolean)
	--- Bands of BAND_ROWS grid rows in the image.
	bandCount : function(g : SquareMinimapNetGrid) : integer
	--- Encodes grid band b when `all` or changed since its last encode (clears the flag); true if encoded.
	encodeBand : function(g : SquareMinimapNetGrid, out : {integer}, b : integer, palette : {{integer}}, flipRows : boolean, all : boolean) : boolean
	--- Grid rows per strip (STRIP_BANDS * BAND_ROWS).
	stripRows : function() : integer
	--- Strips of an image h rows high.
	stripCount : function(h : integer) : integer
	--- Grid rows r0 .. r1 - 1 (top-down) of strip s.
	stripRange : function(h : integer, s : integer) : integer, integer
	--- The strip a band belongs to.
	stripOfBand : function(b : integer) : integer
	--- True when a band of strip s is flagged as changed.
	stripDirty : function(g : SquareMinimapNetGrid, s : integer) : boolean
	--- Grid rows gy0 .. gy1 - 1 into the buffer of the strip spanning rows s0 .. s1 - 1 (flipRows:
	--- the strip's rows bottom-up).
	encodeStripRows : function(g : SquareMinimapNetGrid, out : {integer}, s0 : integer, s1 : integer, gy0 : integer, gy1 : integer, palette : {{integer}}, flipRows : boolean)
	--- encodeBand into the band's strip buffer; true if it encoded.
	encodeStripBand : function(g : SquareMinimapNetGrid, out : {integer}, b : integer, palette : {{integer}}, flipRows : boolean, all : boolean) : boolean
	--- Top and height in UI px of strip rows r0 .. r1 - 1 in a picture h px high (image imageH rows).
	stripPlacement : function(r0 : integer, r1 : integer, imageH : integer, h : integer) : integer, integer
	--- localKey of a strip node for its version, the picture size and the hand-off mode.
	stripKey : function(s : integer, version : integer, w : integer, h : integer, mode : string) : string
	--- Calibration patch (red, green, blue, 50% white squares, top-left); returns the square size, 0 if it doesn't fit.
	--- refSide: size the squares from this side instead of min(w, h).
	paintCalibration : function(out : {integer}, w : integer, h : integer, order : string, flipRows : boolean, refSide? : integer) : integer
	--- Seconds to the next re-list: listMs * factor / 1000 clamped to minSeconds..maxSeconds.
	scanInterval : function(listMs : number, minSeconds : number, maxSeconds : number, factor : number) : number
	--- Back-off: base after a change (or first scan), else prev doubled, clamped to base..cap.
	nextScanSeconds : function(prev : number, base : number, changed : boolean, cap : number) : number
end

-- Network layer scheduler (pure, engine access injected). Module:
-- ug_require "square_better_minimap::/minimap/minimap_netscan.tl" as SquareMinimapNetScan

global record SquareMinimapNetStats
	startMs : number
	frames : integer
	listMs : number
	flattenMs : number
	sweepMs : number
	readMs : number
	rasterMs : number
	encodeMs : number
	handoffMs : number
	bands : integer       -- bands encoded this pass
	stripsHanded : integer -- strips handed to the engine this pass
	streets : integer
	tracks : integer
	tunnels : integer
	noGeom : integer
	noBox : integer
	readFailed : integer
end

--- One strip of a published image (net STRIPS). params: its engine-side ImageView params
--- userdata (one Lua -> C++ copy per strip version); data: the Lua table (fallback hand-off,
--- copied into the ImageView on every new node). r0 .. r1 - 1: its grid rows; version: the image
--- version it was last handed off in (its node's localKey).
global record SquareMinimapNetStrip
	params : any
	data : {integer}
	r0 : integer
	r1 : integer
	version : integer
end

--- A published image: one entry per strip, swapped in all together (netscan "handoff").
global record SquareMinimapNetImage
	strips : {SquareMinimapNetStrip}
	w : integer
	h : integer
	version : integer
	atMs : number
end

global record SquareMinimapNetState
	minX : number            -- map extent the image was made for (a change starts over)
	minY : number
	maxX : number
	maxY : number
	w : integer
	h : integer
	xf : SquareMinimapNetXform
	grid : SquareMinimapNetGrid
	palette : {{integer}}
	hiVis : boolean          -- palette the grid is encoded with
	edges : {integer : SquareMinimapNetItem}
	buildings : {integer : SquareMinimapNetItem}
	edgeCount : integer
	buildingCount : integer
	stamp : integer
	--- idle, list_s, flat_s, list_t, flat_t, sweep_e, list_b, flat_b, sweep_b, remove_e, remove_b,
	--- read_e, read_b, encode, handoff (one strip per frame)
	phase : string
	waitUntilMs : number     -- nothing happens before this (next scan, or a hidden-window pause)
	yield : boolean          -- end this frame's work after the current step
	hiddenSinceMs : number
	flat : SquareMinimapNetFlatten
	sweep : SquareMinimapNetSweep
	addedSet : {integer : boolean}
	addE : {integer}
	addKindE : {integer}
	remE : {integer}
	addB : {integer}
	addKindB : {integer}
	remB : {integer}
	idx : integer
	readBuf : {SquareMinimapNetItem} -- reused per read chunk
	dirty : boolean          -- the grid changed since the shown image
	strips : integer         -- strips of the image (net.stripCount)
	bufs : {integer : {integer}} -- per strip: Lua encode buffer kept for the next pass (nil = none:
	                         -- a strip that changes is then encoded whole into a new one)
	pending : {integer : boolean} -- per strip: re-encoded but not yet published (hand-off due)
	stripFull : {integer : boolean} -- per strip: this encode writes every band (no or stale buffer)
	encBand : integer
	encAll : boolean         -- encode every strip (first image, palette switch, calibration)
	bufHiVis : boolean       -- palette the kept buffers were last encoded with
	handoffList : {integer}  -- strips handed off in this pass, one per frame
	handoffIdx : integer
	staged : {integer : SquareMinimapNetStrip} -- handed-off strips waiting for the publish (io)
	spareParams : {integer : any} -- per strip: the params userdata of its previous version (refilled next)
	recolor : boolean        -- the running encode is a palette switch only (no list, no read)
	parkedSinceMs : number   -- toggled off at this time with the caches kept (nil = on)
	image : SquareMinimapNetImage
	version : integer
	baseSeconds : number     -- scan interval from the list time (scanInterval)
	scanSeconds : number     -- current interval (baseSeconds, doubled per scan without changes)
	passes : integer         -- completed passes that published an image
	emptyScans : integer     -- consecutive scans without any change
	updatesLogged : integer
	stats : SquareMinimapNetStats
end

--- The SQPERF calls the scheduler makes (an SQPERF instance, or a test stub).
global record SquareMinimapNetPerf
	start : function(self : SquareMinimapNetPerf) : number
	stop : function(self : SquareMinimapNetPerf, name : string, t0 : number) : number
	count : function(self : SquareMinimapNetPerf, name : string, n? : integer)
end

--- What the scheduler needs from the game (minimap_hud.script.tl) or a test.
global record SquareMinimapNetIo
	now : function() : number                              -- ms
	listStreets : function() : {any : {integer}}            -- nil = failed (the scan is skipped)
	listTracks : function() : {any : {integer}}
	listBuildings : function() : {any : {integer}}
	readEdge : function(st : SquareMinimapNetState, id : integer, kind : integer) : SquareMinimapNetItem
	readBuilding : function(st : SquareMinimapNetState, id : integer) : SquareMinimapNetItem
	--- st.bufs[s] holds strip s finished: copy it to the engine into st.staged[s] (not shown yet);
	--- false = failed (the pass ends without a publish, the strip stays pending).
	handoff : function(st : SquareMinimapNetState, s : integer) : boolean
	--- Every changed strip is staged: show them all together (a new image version); true = shown.
	publish : function(st : SquareMinimapNetState) : boolean
	--- A pass ended (published: a new image; else something changed but nothing visible).
	passDone : function(st : SquareMinimapNetState, published : boolean)
	perf : SquareMinimapNetPerf
	flipRows : boolean
	calibrate : function(st : SquareMinimapNetState) -- paints over a finished buffer; nil = off
end

global record SquareMinimapNetScan
	SCAN_SECONDS : number       -- minimum re-list interval
	SCAN_MAX_SECONDS : number   -- cap of the list-time based interval
	SCAN_FACTOR : number        -- interval >= factor x the list time
	BACKOFF_MAX_SECONDS : number
	FLATTEN_CHUNK : integer
	SWEEP_CHUNK : integer
	READ_CHUNK : integer
	REMOVE_CHUNK : integer
	newStats : function(now : number) : SquareMinimapNetStats
	newState : function(box : SquareMinimapBox, orient : SquareMinimapOrient, longSide : integer, hiVis : boolean, order : string) : SquareMinimapNetState
	startScan : function(st : SquareMinimapNetState, now : number)
	endScan : function(st : SquareMinimapNetState, now : number)
	--- all: every strip (palette switch / calibration); else only changed strips, and only their
	--- changed bands where the strip's buffer is kept.
	startEncode : function(st : SquareMinimapNetState, all : boolean)
	--- Phases whose one unsliced call runs only as the first work of a frame (engine list calls, hand-off).
	isHeavy : function(phase : string) : boolean
	--- One step of the current phase; true when a new image was published.
	work : function(st : SquareMinimapNetState, io : SquareMinimapNetIo, deadline : number) : boolean
	--- One frame: steps until idle, a yield or budgetMs; true when a new image was published.
	run : function(st : SquareMinimapNetState, io : SquareMinimapNetIo, budgetMs : number) : boolean
end
