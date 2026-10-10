# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow", "lupa"]
# ///
"""Render the construction-menu icons of square_roundabouts ("Better Roundabouts", "Magic Roundabout",
"Channelized Junction", "Roundabout Interchange", and the three Highway Interchange entries Parclo,
Parclo two quadrants and Diamond).

Outputs (mods/square_roundabouts/content/infrastructure/street_construction/):
  square_roundabouts@2x.tga        `icon = "square_roundabouts.tga"` in square_roundabouts.con.lua
  square_roundabouts_magic@2x.tga  `icon = "square_roundabouts_magic.tga"` in square_roundabouts_magic.con.lua
  square_roundabouts_channel@2x.tga `icon = "square_roundabouts_channel.tga"` in square_roundabouts_channel.con.lua
  square_roundabouts_interchange@2x.tga `icon = "square_roundabouts_interchange.tga"` in square_roundabouts_interchange.con.lua
  square_roundabouts_highway_<id>@2x.tga `icon = "square_roundabouts_highway_<id>.tga"` per Highway
      Interchange entry (<id> = parclo, parclo2, diamond; square_roundabouts_highway_menu.lua; drawn
      from the entry's first Layout: A4, A2, Diamond)
  square_roundabouts_highway_<id>_preview@2x.tga `previewIcon = "..._preview.tga"`: a placeholder
      hover preview per entry (720x405, 24-bit BGR like render_preview_square_roundabouts.py's) drawn
      from the same geometry, until in-game captures exist
(the game picks the @2x file, like the base `roundabout.tga` -> `roundabout@2x.tga` in base
infrastructure/street_construction.zip).

Format (matches the base street construction icons): 240x150 px, uncompressed 32-bit BGRA TGA,
bottom-left origin, transparent background (docs/wiki/modding/constructions/basics.md: "`icon` is
a small `@2x.tga` icon which has a resolution of 240x150 pixels").

Look: the base thumbnails' top-down style (grey-brown asphalt, light kerb lines, transparent
background), but clearly different from the vanilla roundabout icon (a plain ring with four
diagonal arms): an oval ring with a green island and trees, beige sidewalks, and a T layout of
three town roads. Drawn at 4x and downsampled; the asphalt noise is seeded, so the output is
byte-for-byte reproducible.

Magic icon: five small grey rings with paved centres on a two-way ring around a green island with
trees, one arm per small ring running off the canvas, same palette.

Channel icon: a T junction (main road across, side road up) with a curved one-way slip lane
across each upper corner and a green triangle island between slip lane and corner, same palette.

Interchange icon: a highway across (two carriageways), a ring over it on two bridges (a shadow
on the highway under each), the cross road up and down, four curved slip roads from the highway to
the bridge ends, green island halves either side of the highway, same palette.

Highway icons: each Highway Interchange entry's default build (medium highway, road over highway, town
medium cross road, Scale = hx.DEFAULT_SIZE, Small since 2026-10-09) from above, drawn from its real edges (highway_edges(): the entry's
updateFn spec, hx.specFor({type = t}, {}), run live through tools/dump_square_roundabouts_highway.lua,
so a geometry change needs no re-paste): the highway across, the cross road on its bridge, the type's
loops and straight ramps, same palette; the scale fits the ramps to the canvas.

Mod badge (every 240x150 menu icon, not the hover previews): the cover pictogram (the Magic
Roundabout glyph from branding/mods.js, accent #E8833A) on a dark #18202a disc with a family-teal
(#2FA48F) rim, edging off the top-right corner like a seal, so our entries stand out in the menu.

Usage: uv run tools/render_icon_square_roundabouts.py [--png preview.png]
       (--png writes preview.png, preview_magic.png, preview_channel.png, preview_interchange.png,
       preview_highway_<id>.png and preview_highway_<id>_preview.png)
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR  # noqa: E402

OUT_DIR = MODS_DIR / "square_roundabouts/content/infrastructure/street_construction"
OUT = OUT_DIR / "square_roundabouts@2x.tga"
OUT_MAGIC = OUT_DIR / "square_roundabouts_magic@2x.tga"
OUT_CHANNEL = OUT_DIR / "square_roundabouts_channel@2x.tga"
OUT_INTERCHANGE = OUT_DIR / "square_roundabouts_interchange@2x.tga"
# Highway Interchange entries (square_roundabouts_highway_menu.lua ENTRIES) and the type (hx.TYPES
# index) each one's icon shows: its first Layout button
HIGHWAY_ENTRIES = (("parclo", 1), ("parclo2", 3), ("diamond", 6))
HIGHWAY_TYPES = 6
# mod badge (branding/README.md: family teal, the mod's accent)
BADGE_TEAL = (47, 164, 143, 255)
BADGE_ACCENT = (232, 131, 58, 255)
BADGE_FIELD = (24, 32, 42, 255)    # cover pictogram field #18202a (branding/cover.js DARK)
BADGE_INK = (238, 242, 246, 255)   # cover ink #eef2f6
PAVING = (168, 160, 146, 255)

W, H = 240, 150
S = 4  # supersampling factor

# palette sampled from the base roundabout@2x.tga (asphalt ~ (95, 90, 84), light kerb lines)
ASPHALT = (94, 89, 83, 255)
SIDEWALK = (176, 166, 148, 255)
KERB = (210, 201, 182, 255)
MARKING = (226, 220, 206, 255)
GRASS = (104, 132, 64, 255)
GRASS_EDGE = (86, 112, 52, 255)
TREE_SHADOW = (40, 52, 26, 150)
TREE = (58, 92, 40, 255)
TREE_LIGHT = (92, 130, 58, 255)

CX, CY = 120, 72          # ring centre
RA, RB = 52, 40           # ring centreline semi-axes (oval)
ROAD = 14                 # ring carriageway width
WALK = 3.5                # sidewalk width
ARM_ROAD = 15             # arm carriageway width
ARMS = (0.0, 180.0, 270.0)  # degrees, 0 = east, counter-clockwise (screen y points down)


def p(x: float, y: float) -> tuple[float, float]:
    return (x * S, y * S)


def ellipse(draw: ImageDraw.ImageDraw, a: float, b: float, fill) -> None:
    draw.ellipse([p(CX - a, CY - b), p(CX + a, CY + b)], fill=fill)


def arm_poly(phi_deg: float, width: float, start: float, end: float) -> list[tuple[float, float]]:
    phi = math.radians(phi_deg)
    ux, uy = math.cos(phi), -math.sin(phi)
    nx, ny = -uy, ux
    h = width / 2
    pts = []
    for d, s in ((start, -1), (end, -1), (end, 1), (start, 1)):
        pts.append(p(CX + ux * d + nx * h * s, CY + uy * d + ny * h * s))
    return pts


def ring_point(t: float, a: float, b: float) -> tuple[float, float]:
    return (CX + a * math.cos(t), CY - b * math.sin(t))


def dashed_ellipse(draw: ImageDraw.ImageDraw, a: float, b: float, dashes: int, width: float) -> None:
    for k in range(dashes):
        t0 = 2 * math.pi * k / dashes
        t1 = t0 + 2 * math.pi / dashes * 0.5
        pts = [p(*ring_point(t0 + (t1 - t0) * i / 6, a, b)) for i in range(7)]
        draw.line(pts, fill=MARKING, width=round(width * S))


def render() -> Image.Image:
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    far = 200  # arms run off the canvas, as in the base icon

    outer_a, outer_b = RA + ROAD / 2, RB + ROAD / 2
    inner_a, inner_b = RA - ROAD / 2, RB - ROAD / 2

    # sidewalks: arms, then the ring's outer sidewalk
    for phi in ARMS:
        d.polygon(arm_poly(phi, ARM_ROAD + 2 * WALK, 0, far), fill=SIDEWALK)
    ellipse(d, outer_a + WALK, outer_b + WALK, SIDEWALK)
    # carriageways (the arm asphalt cuts the junction openings into the ring sidewalk)
    for phi in ARMS:
        d.polygon(arm_poly(phi, ARM_ROAD, 0, far), fill=ASPHALT)
    ellipse(d, outer_a, outer_b, ASPHALT)
    # light kerb line along the outer ring edge, between the arms (as the base icon's edge lines)
    for k in range(240):
        t = 2 * math.pi * k / 240
        x, y = ring_point(t, outer_a, outer_b)
        ang = math.degrees(math.atan2(-(y - CY) / outer_b, (x - CX) / outer_a)) % 360
        if all(min(abs(ang - a), 360 - abs(ang - a)) > 21 for a in ARMS):
            r = 0.45 * S
            d.ellipse([x * S - r, y * S - r, x * S + r, y * S + r], fill=KERB)
    # inner kerb, island and its edge
    ellipse(d, inner_a, inner_b, KERB)
    ellipse(d, inner_a - 1.2, inner_b - 1.2, GRASS_EDGE)
    ellipse(d, inner_a - 2.4, inner_b - 2.4, GRASS)

    # markings: dashed lane divider on the ring, centre dashes and give-way lines on the arms
    dashed_ellipse(d, RA, RB, 28, 0.9)
    for phi in ARMS:
        rad = math.radians(phi)
        edge = math.hypot(outer_a * math.cos(rad), outer_b * math.sin(rad)) + WALK
        for k in range(8):
            s0 = edge + 4 + k * 9
            d.line([arm_poly(phi, 0, s0, s0)[0], arm_poly(phi, 0, s0 + 4.5, s0 + 4.5)[0]],
                   fill=MARKING, width=round(0.9 * S))
        # give-way line across the entry half (right-hand traffic: entry on the right of the arm)
        ux, uy = math.cos(rad), -math.sin(rad)
        nx, ny = -uy, ux
        g = edge + 1.2
        for k in range(4):
            o0, o1 = 0.6 + k * 1.8, 1.5 + k * 1.8
            a0 = (CX + ux * g - nx * o0, CY + uy * g - ny * o0)
            a1 = (CX + ux * g - nx * o1, CY + uy * g - ny * o1)
            d.line([p(*a0), p(*a1)], fill=MARKING, width=round(0.9 * S))

    # trees on the island: soft shadow, crown, highlight
    trees = [(-24, 2, 8.0), (0, -9, 9.5), (22, 3, 8.0), (-6, 14, 6.0), (13, -19, 5.0), (-17, -17, 5.0)]
    for tx, ty, r in trees:
        x, y = CX + tx, CY + ty
        d.ellipse([p(x - r + 1.6, y - r + 2.0), p(x + r + 1.6, y + r + 2.0)], fill=TREE_SHADOW)
    for tx, ty, r in trees:
        x, y = CX + tx, CY + ty
        d.ellipse([p(x - r, y - r), p(x + r, y + r)], fill=TREE)
        d.ellipse([p(x - r * 0.75, y - r * 0.8), p(x + r * 0.35, y + r * 0.3)], fill=TREE_LIGHT)

    img = img.convert("RGBa").resize((W, H), Image.LANCZOS).convert("RGBA")
    return add_noise(img)


def render_magic() -> Image.Image:
    """Five mini roundabouts on a two-way central ring (Swindon style), top-down."""
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = 120, 75
    ring_r = 46          # link ring / satellite centres
    sat_r = 12.5         # satellite centreline radius
    sat_road = 8
    link_road = 11
    far = 200

    def circle(x, y, r, fill):
        d.ellipse([p(x - r, y - r), p(x + r, y + r)], fill=fill)

    sats = []
    for i in range(5):
        th = math.radians(90 + 72 * i)
        sats.append((cx + ring_r * math.cos(th), cy - ring_r * math.sin(th), th))

    def arm(x, y, th, width, fill):
        ux, uy = math.cos(th), -math.sin(th)
        nx, ny = -uy, ux
        h = width / 2
        pts = [p(x + nx * h, y + ny * h), p(x + ux * far + nx * h, y + uy * far + ny * h),
               p(x + ux * far - nx * h, y + uy * far - ny * h), p(x - nx * h, y - ny * h)]
        d.polygon(pts, fill=fill)

    # sidewalks, then asphalt: link ring, arms, satellites
    circle(cx, cy, ring_r + link_road / 2 + WALK, SIDEWALK)
    for x, y, th in sats:
        arm(x, y, th, ARM_ROAD + 2 * WALK, SIDEWALK)
        circle(x, y, sat_r + sat_road / 2 + WALK, SIDEWALK)
    circle(cx, cy, ring_r + link_road / 2, ASPHALT)
    for x, y, th in sats:
        arm(x, y, th, ARM_ROAD, ASPHALT)
        circle(x, y, sat_r + sat_road / 2, ASPHALT)
    circle(cx, cy, ring_r - link_road / 2, KERB)
    # centre island with trees, cut back around the satellites
    circle(cx, cy, ring_r - link_road / 2 - 1.2, GRASS_EDGE)
    circle(cx, cy, ring_r - link_road / 2 - 2.4, GRASS)
    for x, y, th in sats:
        circle(x, y, sat_r + sat_road / 2, ASPHALT)
    # satellites: paved mini islands
    for x, y, th in sats:
        circle(x, y, sat_r - sat_road / 2, KERB)
        circle(x, y, sat_r - sat_road / 2 - 1.0, PAVING)
    # dashed centre line on the two-way ring (between satellites)
    for k in range(60):
        t0 = 2 * math.pi * k / 60
        t1 = t0 + 2 * math.pi / 60 * 0.5
        mid = (t0 + t1) / 2
        if all(math.hypot(cx + ring_r * math.cos(mid) - x, cy - ring_r * math.sin(mid) - y) > sat_r + sat_road
               for x, y, _ in sats):
            pts = [p(cx + ring_r * math.cos(t0 + (t1 - t0) * i / 4), cy - ring_r * math.sin(t0 + (t1 - t0) * i / 4))
                   for i in range(5)]
            d.line(pts, fill=MARKING, width=round(0.9 * S))
    trees = [(0, 0, 9.0), (-14, 8, 6.5), (13, 9, 6.5), (0, -16, 6.0), (-12, -9, 5.0), (12, -9, 5.0)]
    for tx, ty, r in trees:
        x, y = cx + tx, cy + ty
        d.ellipse([p(x - r + 1.6, y - r + 2.0), p(x + r + 1.6, y + r + 2.0)], fill=TREE_SHADOW)
    for tx, ty, r in trees:
        x, y = cx + tx, cy + ty
        d.ellipse([p(x - r, y - r), p(x + r, y + r)], fill=TREE)
        d.ellipse([p(x - r * 0.75, y - r * 0.8), p(x + r * 0.35, y + r * 0.3)], fill=TREE_LIGHT)

    img = img.convert("RGBa").resize((W, H), Image.LANCZOS).convert("RGBA")
    return add_noise(img)


def render_channel() -> Image.Image:
    """T junction with slip lanes and triangle islands in both upper corners, top-down."""
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, my = 120, 118     # side road axis x, main road axis y (screen y points down)
    main_w, side_w, slip_w = 20, 15, 9
    setback = 92          # slip nodes: this far from the junction centre along each road

    def hermite(p0, t0, p1, t1, n=40):
        pts = []
        for k in range(n + 1):
            u = k / n
            h00, h10 = 2 * u**3 - 3 * u**2 + 1, u**3 - 2 * u**2 + u
            h01, h11 = -2 * u**3 + 3 * u**2, u**3 - u**2
            pts.append((h00 * p0[0] + h10 * t0[0] + h01 * p1[0] + h11 * t1[0],
                        h00 * p0[1] + h10 * t0[1] + h01 * p1[1] + h11 * t1[1]))
        return pts

    def band(pts, width):
        """Polygon of a road band of `width` around a polyline."""
        left, right = [], []
        for i, (x, y) in enumerate(pts):
            a = pts[max(0, i - 1)]
            b = pts[min(len(pts) - 1, i + 1)]
            dx, dy = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dy) or 1
            nx, ny = -dy / ln * width / 2, dx / ln * width / 2
            left.append(p(x + nx, y + ny))
            right.append(p(x - nx, y - ny))
        return left + right[::-1]

    ang = math.radians(30)  # a little more bend than the game's 40 deg, so it reads at icon size
    slips = []
    for sx in (1, -1):  # right corner (east -> north), left corner (north -> west), mirrored
        a = (cx + sx * setback, my)
        b = (cx, my - setback)
        chord = math.hypot(b[0] - a[0], b[1] - a[1])
        t0 = (-sx * math.cos(ang) * chord, -math.sin(ang) * chord)
        t1 = (-sx * math.sin(ang) * chord, -math.cos(ang) * chord)
        slips.append(hermite(a, t0, b, t1))

    main = [(-80, my), (W + 80, my)]
    side = [(cx, my), (cx, -80)]
    for pts, w in ((main, main_w), (side, side_w)):
        d.polygon(band(pts, w + 2 * WALK), fill=SIDEWALK)
    for pts in slips:
        d.polygon(band(pts, slip_w + 2 * WALK), fill=SIDEWALK)
    # triangle islands: between each slip lane and its corner (kerb, grass edge, grass)
    for sx, pts in zip((1, -1), slips):
        corner = (cx + sx * (side_w / 2 + WALK), my - main_w / 2 - WALK)
        tri = [p(*corner)] + [p(x, y) for x, y in pts]
        d.polygon(tri, fill=KERB)
    for sx, pts in zip((1, -1), slips):
        corner = (cx + sx * (side_w / 2 + WALK + 2.0), my - main_w / 2 - WALK - 2.0)
        inner = []
        for i in range(4, len(pts) - 4):
            x, y = pts[i]
            # pull the slip centreline towards the corner by half the slip width + sidewalk + kerb
            vx, vy = corner[0] - x, corner[1] - y
            ln = math.hypot(vx, vy) or 1
            off = slip_w / 2 + WALK + 1.5
            inner.append((x + vx / ln * off, y + vy / ln * off))
        d.polygon([p(*corner)] + [p(*q) for q in inner], fill=GRASS_EDGE)
        cx2, cy2 = corner[0] + sx * 0.0, corner[1]
        shrink = [(q[0] + (cx2 - q[0]) * 0.1, q[1] + (cy2 - q[1]) * 0.1) for q in inner]
        c3 = (corner[0] + sx * 1.2, corner[1] - 1.2)
        d.polygon([p(*c3)] + [p(*q) for q in shrink], fill=GRASS)
    # carriageways on top
    for pts, w in ((main, main_w), (side, side_w)):
        d.polygon(band(pts, w), fill=ASPHALT)
    for pts in slips:
        d.polygon(band(pts, slip_w), fill=ASPHALT)
    # markings: dashed centre lines on main and side road, give-way line on the side road
    for k in range(-2, 16):
        x0 = k * 16
        if abs(x0 + 4 - cx) > side_w / 2 + 6:
            d.line([p(x0, my), p(x0 + 8, my)], fill=MARKING, width=round(0.9 * S))
    for k in range(0, 8):
        y0 = my - main_w / 2 - 8 - k * 14
        d.line([p(cx, y0), p(cx, y0 - 7)], fill=MARKING, width=round(0.9 * S))
    for k in range(4):
        y = my - main_w / 2 - 1.5
        d.line([p(cx - 0.6 - k * 1.8, y), p(cx - 1.5 - k * 1.8, y)], fill=MARKING, width=round(0.9 * S))
    # arrows on the slip lanes (one-way): a small chevron at the middle, pointing along the lane
    for pts in slips:
        i = len(pts) // 2
        (x0, y0), (x1, y1) = pts[i - 2], pts[i + 2]
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy) or 1
        dx, dy = dx / ln, dy / ln
        tip = (pts[i][0] + dx * 3, pts[i][1] + dy * 3)
        for s_ in (1, -1):
            d.line([p(*tip), p(tip[0] - dx * 4 - dy * 3 * s_, tip[1] - dy * 4 + dx * 3 * s_)],
                   fill=MARKING, width=round(1.0 * S))

    img = img.convert("RGBa").resize((W, H), Image.LANCZOS).convert("RGBA")
    return add_noise(img)


def render_interchange() -> Image.Image:
    """Two-bridge roundabout interchange, top-down: highway across, ring over it, four slip roads."""
    img = Image.new("RGBA", (W * S, H * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = 120, 75
    cw_off, cw_w = 7.5, 11.0   # carriageway centre offset from the axis, carriageway width
    r, ring_w = 38.0, 10.0      # ring centreline radius, ring width
    slip_w, cross_w = 7.0, 13.0

    def band(pts, width):
        left, right = [], []
        for i, (x, y) in enumerate(pts):
            a = pts[max(0, i - 1)]
            b = pts[min(len(pts) - 1, i + 1)]
            dx, dy = b[0] - a[0], b[1] - a[1]
            ln = math.hypot(dx, dy) or 1
            nx, ny = -dy / ln * width / 2, dx / ln * width / 2
            left.append(p(x + nx, y + ny))
            right.append(p(x - nx, y - ny))
        return left + right[::-1]

    def hermite(p0, t0, p1, t1, n=40):
        out = []
        for k in range(n + 1):
            u = k / n
            h00, h10 = 2 * u**3 - 3 * u**2 + 1, u**3 - 2 * u**2 + u
            h01, h11 = -2 * u**3 + 3 * u**2, u**3 - u**2
            out.append((h00 * p0[0] + h10 * t0[0] + h01 * p1[0] + h11 * t1[0],
                        h00 * p0[1] + h10 * t0[1] + h01 * p1[1] + h11 * t1[1]))
        return out

    alpha = math.radians(42)   # bridge ends (slip nodes) at +-alpha from the highway axis
    slips = []
    for sx in (1, -1):
        for sy in (1, -1):
            node = (cx + sx * r * math.cos(alpha), cy + sy * r * math.sin(alpha))
            merge = (cx + sx * 104, cy + sy * (cw_off + 4))
            chord = math.hypot(node[0] - merge[0], node[1] - merge[1])
            t = (-sx * chord, 0)
            slips.append(hermite(merge, t, node, t))
    highway = [((-20, cy + s_ * cw_off), (W + 20, cy + s_ * cw_off)) for s_ in (1, -1)]
    cross = [(cx, -20), (cx, cy - r)], [(cx, cy + r), (cx, H + 20)]
    ring = [(cx + r * math.cos(t), cy + r * math.sin(t)) for t in [2 * math.pi * k / 96 for k in range(97)]]

    # lower level: highway with shoulders and lane marks
    for a, b in highway:
        d.polygon(band([a, b], cw_w + 2), fill=SIDEWALK)
    for a, b in highway:
        d.polygon(band([a, b], cw_w), fill=ASPHALT)
        for k in range(-2, 18):
            x0 = k * 14
            d.line([p(x0, a[1]), p(x0 + 7, a[1])], fill=MARKING, width=round(0.8 * S))
    # slip roads (at grade where they meet the highway)
    for pts in slips:
        d.polygon(band(pts, slip_w + 2), fill=SIDEWALK)
    for pts in slips:
        d.polygon(band(pts, slip_w), fill=ASPHALT)
    # island halves either side of the highway (inside the ring, clear of the shoulders)
    inner = r - ring_w / 2 - 2
    for sy in (1, -1):
        y_cut = cw_off + cw_w / 2 + 2
        half = [(cx + inner * math.cos(t), cy + sy * inner * math.sin(t))
                for t in [math.pi * k / 48 for k in range(49)] if inner * math.sin(t) >= y_cut]
        if len(half) >= 3:
            d.polygon([p(*q) for q in half], fill=GRASS_EDGE)
            shrunk = [(cx + (x - cx) * 0.92, cy + sy * y_cut + (y - cy - sy * y_cut) * 0.85) for x, y in half]
            d.polygon([p(*q) for q in shrunk], fill=GRASS)
        tx, ty = cx, cy + sy * (y_cut + 8)
        d.ellipse([p(tx - 3.5, ty - 2.5), p(tx + 4.5, ty + 5.5)], fill=TREE_SHADOW)
        d.ellipse([p(tx - 4, ty - 4), p(tx + 4, ty + 4)], fill=TREE)
        d.ellipse([p(tx - 2.5, ty - 3), p(tx + 1.5, ty + 1)], fill=TREE_LIGHT)
    # upper level: bridge shadows on the highway, then the ring and the cross road
    for sx in (1, -1):
        x = cx + sx * r
        d.rectangle([p(x - ring_w / 2 + 4, cy - cw_off - cw_w / 2 - 1), p(x + ring_w / 2 + 4, cy + cw_off + cw_w / 2 + 1)],
                    fill=(30, 28, 26, 150))
    for pts in cross:
        d.polygon(band(list(pts), cross_w + 2 * WALK), fill=SIDEWALK)
    d.line([p(*q) for q in ring], fill=KERB, width=round((ring_w + 2) * S))
    for pts in cross:
        d.polygon(band(list(pts), cross_w), fill=ASPHALT)
    d.line([p(*q) for q in ring], fill=ASPHALT, width=round(ring_w * S))
    # bridge parapets: light lines along both kerbs of the ring where it spans the highway
    for sx in (1, -1):
        for rr in (r - ring_w / 2 - 0.5, r + ring_w / 2 + 0.5):
            ts = [math.pi * (0 if sx > 0 else 1) + math.radians(a) for a in range(-40, 41, 4)]
            d.line([p(cx + rr * math.cos(t), cy + rr * math.sin(t)) for t in ts], fill=KERB, width=round(1.2 * S))
    for k in range(-1, 3):
        d.line([p(cx, cy - r - 8 - k * 12), p(cx, cy - r - 14 - k * 12)], fill=MARKING, width=round(0.9 * S))
        d.line([p(cx, cy + r + 8 + k * 12), p(cx, cy + r + 14 + k * 12)], fill=MARKING, width=round(0.9 * S))

    img = img.convert("RGBa").resize((W, H), Image.LANCZOS).convert("RGBA")
    return add_noise(img)


def highway_edges() -> dict[int, tuple[list, dict]]:
    """Per type index (1-6): each Highway Interchange entry's default edges in plan (metres; x east,
    y north) and full widths per role.

    Edges: (role, bridge, (p0x, p0y, t0x, t0y), (p1x, p1y, t1x, t1y)), cubic Hermite as the game,
    rounded to 0.1 m. Runs hx.build(hx.specFor({type = t}, {})) through the test harness (Teal +
    ug_require), so the icons and previews follow the geometry with no pasted data.
    """
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tests"))
    import run_tests  # noqa: E402  (tests/run_tests.py: ModRunner)

    dump = Path(__file__).with_name("dump_square_roundabouts_highway.lua")
    out = run_tests.ModRunner(MODS_DIR / "square_roundabouts").run_file(dump, None)
    if out["load_error"] or not out["results"] or not out["results"][0]["ok"]:
        raise SystemExit(f"{dump.name} failed: {out['load_error'] or out['results']}")
    geos: dict[int, tuple[list, dict]] = {}
    edges, widths = [], {}
    for line in out["results"][0]["printed"].splitlines():
        f = line.split()
        if f and f[0] == "T":
            edges, widths = [], {}
            geos[int(f[1])] = (edges, widths)
        elif f and f[0] == "E":
            v = [float(x) for x in f[3:]]
            edges.append((f[1], f[2] == "1", tuple(v[:4]), tuple(v[4:])))
        elif f and f[0] == "HW":
            widths[f[1]] = 2 * float(f[2])
    if sorted(geos) != list(range(1, HIGHWAY_TYPES + 1)):
        raise SystemExit(f"{dump.name}: expected types 1-{HIGHWAY_TYPES}, got {sorted(geos)}")
    return geos


PREVIEW_GROUND = (112, 128, 84, 255)


def highway_scale(geo: tuple[list, dict], w: int, h: int, fill: float) -> float:
    """Pixels per metre that fit the entry's ramps (and its cross road terminals) into fill of the canvas."""
    all_edges, _ = geo
    pts = [q for e in all_edges if e[0] == "ramps" for q in (e[2], e[3])]
    xr = max(abs(q[0]) for q in pts) + 6
    yr = max(abs(q[1]) for q in pts) + 6
    return min(fill * w / (2 * xr), fill * h / (2 * yr))


def render_highway(geo: tuple[list, dict], w: int, h: int, k: float, ground=None) -> Image.Image:
    """One Highway Interchange entry's default build from above at k px per metre on a w x h canvas
    (transparent, or on ground)."""
    img = Image.new("RGBA", (w * S, h * S), ground or (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = w / 2, h / 2
    all_edges, widths = geo  # one entry of highway_edges()
    # extents read from the edges (highway ends, carriageway y, arm ends, bridge ends, cross road half width)
    hw_x = max(abs(q[0]) for e in all_edges if e[0] == "highway" for q in (e[2], e[3]))
    hw_ys = sorted({q[1] for e in all_edges if e[0] == "highway" for q in (e[2], e[3])})
    arm_y = max(abs(q[1]) for e in all_edges if e[0] == "arms" for q in (e[2], e[3]))
    yb = max(abs(q[1]) for e in all_edges if e[0] == "cross" and e[1] for q in (e[2], e[3]))
    cross_h = widths["cross"] / 2

    def scr(x, y):
        return (cx + x * k, cy - y * k)

    def curve(e, n=24):
        (x0, y0, tx0, ty0), (x1, y1, tx1, ty1) = e[2], e[3]
        out = []
        for i in range(n + 1):
            u = i / n
            h00, h10 = 2 * u**3 - 3 * u**2 + 1, u**3 - 2 * u**2 + u
            h01, h11 = -2 * u**3 + 3 * u**2, u**3 - u**2
            out.append(scr(h00 * x0 + h10 * tx0 + h01 * x1 + h11 * tx1, h00 * y0 + h10 * ty0 + h01 * y1 + h11 * ty1))
        return out

    def stroke(e, width, fill):
        pts = [(x * S, y * S) for x, y in curve(e)]
        wpx = width * k * S
        d.line(pts, fill=fill, width=max(1, round(wpx)), joint="curve")
        r = wpx / 2
        for x, y in (pts[0], pts[-1]):
            d.ellipse([x - r, y - r, x + r, y + r], fill=fill)

    def run_off(e):
        # the highway and arm ends run on off the canvas (no round caps in view)
        (a, b) = e[2], e[3]
        def far(q):
            x, y, tx, ty = q
            if e[0] == "highway" and abs(x) >= hw_x - 1:
                x = math.copysign(400.0, x)
            if e[0] == "arms" and abs(y) >= arm_y - 0.5:
                y = math.copysign(400.0, y)
            return (x, y, tx, ty)
        return (e[0], e[1], far(a), far(b))

    def edges(role, bridge=None):
        return [run_off(e) for e in all_edges if e[0] == role and (bridge is None or e[1] == bridge)]

    roads = edges("highway")
    ramps_ = edges("ramps")
    cross = edges("cross", False) + edges("arms")
    bridge = edges("cross", True)
    edge_px = max(0.8, 1.6 * k)   # kerb / shoulder band
    # ground level: highway, then the ramps (they meet the highway at grade)
    for e in roads:
        stroke(e, widths["highway"] + 2 * edge_px / k, SIDEWALK)
    for e in ramps_:
        stroke(e, widths["ramps"] + 2 * edge_px / k, SIDEWALK)
    for e in roads:
        stroke(e, widths["highway"], ASPHALT)
    for e in ramps_:
        stroke(e, widths["ramps"], ASPHALT)
    # lane marks on both carriageways
    for y in hw_ys:
        x = -(hw_x + 10)
        while x < hw_x + 10:
            d.line([(scr(x, y)[0] * S, scr(x, y)[1] * S), (scr(x + 6, y)[0] * S, scr(x + 6, y)[1] * S)],
                   fill=MARKING, width=max(1, round(0.7 * k * S)))
            x += 14.0
    # the bridge's shadow on the highway
    sx0, sy0 = scr(-cross_h + 5, yb * 0.75)
    sx1, sy1 = scr(cross_h + 5, -yb * 0.75)
    d.rectangle([sx0 * S, sy0 * S, sx1 * S, sy1 * S], fill=(30, 28, 26, 110))
    # upper level: cross road and bridge, with parapets along the bridge
    for e in cross + bridge:
        stroke(e, widths["cross"] + 2 * edge_px / k, SIDEWALK)
    for e in cross + bridge:
        stroke(e, widths["cross"] - 6.0, ASPHALT)
    for side in (-1, 1):
        x = side * (widths["cross"] / 2 + 0.5)
        a, b = scr(x, yb), scr(x, -yb)
        d.line([(a[0] * S, a[1] * S), (b[0] * S, b[1] * S)], fill=KERB, width=max(1, round(1.6 * k * S)))
    # centre line of the cross road
    y = -(arm_y + 4.5)
    while y < arm_y + 4.5:
        a, b = scr(0, y), scr(0, y + 6)
        d.line([(a[0] * S, a[1] * S), (b[0] * S, b[1] * S)], fill=MARKING, width=max(1, round(0.7 * k * S)))
        y += 14.0

    img = img.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")
    rng = random.Random(1)
    px = img.load()
    for yy in range(h):
        for xx in range(w):
            r, g, b, a = px[xx, yy]
            if a == 0:
                continue
            n = rng.randint(-6, 6)
            px[xx, yy] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)), a)
    return img


def write_tga24(img: Image.Image, path: Path) -> None:
    """Uncompressed 24-bit BGR, bottom-left origin, TGA 2.0 footer (as render_preview_square_roundabouts.py)."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, img.width, img.height, 24, 0)
    rgb = img.convert("RGB")
    px = rgb.load()
    rows = []
    for y in range(rgb.height - 1, -1, -1):
        row = bytearray()
        for x in range(rgb.width):
            r, g, b = px[x, y]
            row += bytes((b, g, r))
        rows.append(bytes(row))
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    path.write_bytes(header + b"".join(rows) + footer)


def add_noise(img: Image.Image) -> Image.Image:
    """Seeded per-pixel brightness noise, like the base icons' asphalt texture."""
    rng = random.Random(1)
    px = img.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            n = rng.randint(-6, 6)
            px[x, y] = (max(0, min(255, r + n)), max(0, min(255, g + n)), max(0, min(255, b + n)), a)
    return img


def with_badge(img: Image.Image) -> Image.Image:
    """The mod badge: the cover pictogram (branding/mods.js square_roundabouts glyph: five ink mini rings
    with knocked-out islands on an ink ring, five arms, accent centre island) on a dark cover-field disc
    with a family-teal rim, set like a corner seal that edges off the top-right corner. Drawn at S x in
    the glyph's 800-unit box and downsampled onto the icon (deterministic)."""
    r_disc, off = 27, 5                      # disc radius; px it pokes past the top and right edges
    rim = 2.0                                # teal rim width (px)
    k = 0.068                                # px per glyph unit (arms reach the rim, minis ~5.7 px)
    n = 2 * r_disc * S
    lay = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    c = n / 2
    u = k * S                                # supersampled px per glyph unit
    rr = (r_disc - rim) * S

    def at(deg: float, r: float) -> tuple[float, float]:
        return c + r * u * math.cos(math.radians(deg)), c - r * u * math.sin(math.radians(deg))

    def disc(xy, r, fill):
        d.ellipse([xy[0] - r * u, xy[1] - r * u, xy[0] + r * u, xy[1] + r * u], fill=fill)

    angles, ring = [90, 162, 234, 306, 18], 215
    for deg in angles:                       # arms: 84 wide, from ring-42 out to 390 (past the rim)
        a, b = at(deg, ring - 42 + 30), at(deg, 390)
        d.line([a, b], fill=BADGE_INK, width=round(84 * u))
        disc(a, 42, BADGE_INK)
    d.ellipse([c - (ring + 30) * u, c - (ring + 30) * u, c + (ring + 30) * u, c + (ring + 30) * u],
              outline=BADGE_INK, width=round(60 * u))
    for deg in angles:                       # minis: ink r84 with a 10-unit dark separation, cut r36
        m = at(deg, ring)
        disc(m, 94, BADGE_FIELD)
        disc(m, 84, BADGE_INK)
        disc(m, 36, BADGE_FIELD)
    disc((c, c), 114, BADGE_FIELD)
    disc((c, c), 104, BADGE_ACCENT)
    # keep the glyph inside the dark field (arms run out to the rim, not over it)
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).ellipse([c - rr, c - rr, c + rr, c + rr], fill=255)
    rimmed = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(rimmed).ellipse([0, 0, n - 1, n - 1], fill=BADGE_TEAL)
    ImageDraw.Draw(rimmed).ellipse([c - rr, c - rr, c + rr, c + rr], fill=BADGE_FIELD)
    rimmed.paste(lay, (0, 0), mask)
    badge = rimmed.resize((2 * r_disc, 2 * r_disc), Image.LANCZOS)
    out = img.copy()
    out.alpha_composite(badge, (img.width - 2 * r_disc + off, -off))
    return out


def write_tga(img: Image.Image, path: Path) -> None:
    """Uncompressed 32-bit BGRA, bottom-left origin, TGA 2.0 footer (as the base icons)."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, img.width, img.height, 32, 8)
    rows = []
    px = img.load()
    for y in range(img.height - 1, -1, -1):
        row = bytearray()
        for x in range(img.width):
            r, g, b, a = px[x, y]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    path.write_bytes(header + b"".join(rows) + footer)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--png", type=Path, help="also write PNG previews (on a dark background)")
    args = ap.parse_args()
    geos = highway_edges()
    icons = [(render(), OUT, ""), (render_magic(), OUT_MAGIC, "_magic"),
             (render_channel(), OUT_CHANNEL, "_channel"),
             (render_interchange(), OUT_INTERCHANGE, "_interchange")]
    for hid, t in HIGHWAY_ENTRIES:
        geo = geos[t]
        icons.append((render_highway(geo, W, H, highway_scale(geo, W, H, 0.9)),
                      OUT_DIR / f"square_roundabouts_highway_{hid}@2x.tga", f"_highway_{hid}"))
    row = []
    for img, out, suffix in icons:
        img = with_badge(img)
        row.append(img)
        write_tga(img, out)
        print(f"wrote {out.relative_to(MODS_DIR.parent)} ({img.width}x{img.height}, 32-bit TGA)")
        if args.png:
            png = args.png.with_name(args.png.stem + suffix + args.png.suffix)
            bg = Image.new("RGBA", img.size, (40, 40, 40, 255))
            bg.alpha_composite(img)
            bg.save(png)
            print(f"wrote {png}")
    if args.png:
        # the menu row as the game shows it: every entry's icon side by side on the menu's dark grey
        pad = 8
        strip = Image.new("RGBA", (pad + len(row) * (W + pad), H + 2 * pad), (40, 40, 40, 255))
        for i, img in enumerate(row):
            strip.alpha_composite(img, (pad + i * (W + pad), pad))
        png = args.png.with_name(args.png.stem + "_menu_row" + args.png.suffix)
        strip.save(png)
        print(f"wrote {png}")
    for hid, t in HIGHWAY_ENTRIES:
        geo = geos[t]
        preview = render_highway(geo, 720, 405, highway_scale(geo, 720, 405, 0.85), PREVIEW_GROUND)
        out = OUT_DIR / f"square_roundabouts_highway_{hid}_preview@2x.tga"
        write_tga24(preview, out)
        print(f"wrote {out.relative_to(MODS_DIR.parent)} ({preview.width}x{preview.height}, 24-bit TGA)")
        if args.png:
            png = args.png.with_name(args.png.stem + f"_highway_{hid}_preview" + args.png.suffix)
            preview.convert("RGB").save(png)
            print(f"wrote {png}")


if __name__ == "__main__":
    main()
