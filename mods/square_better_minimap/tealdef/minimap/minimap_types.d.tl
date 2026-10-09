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
