# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Render the construction-menu icons of square_roundabouts ("Better Roundabouts", "Magic Roundabout",
"Channelized Junction", "Roundabout Interchange").

Outputs (mods/square_roundabouts/content/infrastructure/street_construction/):
  square_roundabouts@2x.tga        `icon = "square_roundabouts.tga"` in square_roundabouts.con.lua
  square_roundabouts_magic@2x.tga  `icon = "square_roundabouts_magic.tga"` in square_roundabouts_magic.con.lua
  square_roundabouts_channel@2x.tga `icon = "square_roundabouts_channel.tga"` in square_roundabouts_channel.con.lua
  square_roundabouts_interchange@2x.tga `icon = "square_roundabouts_interchange.tga"` in square_roundabouts_interchange.con.lua
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

Usage: uv run tools/render_icon_square_roundabouts.py [--png preview.png]
       (--png writes preview.png, preview_magic.png, preview_channel.png and preview_interchange.png)
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
    for img, out, suffix in ((render(), OUT, ""), (render_magic(), OUT_MAGIC, "_magic"),
                             (render_channel(), OUT_CHANNEL, "_channel"),
                             (render_interchange(), OUT_INTERCHANGE, "_interchange")):
        write_tga(img, out)
        print(f"wrote {out.relative_to(MODS_DIR.parent)} ({img.width}x{img.height}, 32-bit TGA)")
        if args.png:
            png = args.png.with_name(args.png.stem + suffix + args.png.suffix)
            bg = Image.new("RGBA", img.size, (40, 40, 40, 255))
            bg.alpha_composite(img)
            bg.save(png)
            print(f"wrote {png}")


if __name__ == "__main__":
    main()
