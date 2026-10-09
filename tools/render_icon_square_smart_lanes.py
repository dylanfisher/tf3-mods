# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Render the construction-menu icons of square_smart_lanes ("Smart Lanes").

A two-lane roundabout seen from the game's tilted 3/4 camera (like the base road-tool icons, e.g.
the Crossing Tool's `lane_control`), with two matched lane-connection curves painted over it: the
outer entry lane takes the first exit on the outer ring lane (amber), the inner entry lane goes
three quarters round on the inner ring lane (cyan, the Smart Lanes accent #3FD6EE), plus a small sparkle
for "set automatically".

Outputs (mods/square_smart_lanes/content/smart_lanes/):
  sl_tool@2x.tga          240x150, `icon = { icon = resolve("sl_tool.tga") }`
  sl_tool_preview@2x.tga  720x405, `previewIcon = { icon = resolve("sl_tool_preview.tga") }`
(the game picks the @2x file, as base gui/construction/tools/lane_control.tga -> lane_control@2x.tga).

Format (matches base gui.zip gui/construction/tools/lane_control@2x.tga and
lane_control_preview@2x.tga): uncompressed 32-bit BGRA TGA (type 2, descriptor 0x08), bottom-left
origin, TGA 2.0 footer. The icon has a transparent background with the scene cut to the road
shape inside ~(30,18)-(214,133); the preview is opaque. Drawn supersampled and downsampled; all
noise is seeded, so the output is byte-for-byte reproducible.

Usage: uv run tools/render_icon_square_smart_lanes.py [--png DIR]
"""

from __future__ import annotations

import argparse
import math
import random
import struct
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR  # noqa: E402

OUT_DIR = MODS_DIR / "square_smart_lanes/content/smart_lanes"

# palette (warm asphalt and paving sampled from base lane_control@2x / lane_control_preview@2x)
ASPHALT = (104, 96, 88)
SIDEWALK = (160, 150, 136)
CURB = (194, 186, 172)
GRASS = (98, 122, 58)
GROUND = (112, 126, 70)
MARK = (226, 226, 220)
CYAN = (63, 214, 238)    # Smart Lanes accent (branding/mods.js)
AMBER = (255, 172, 54)
OUTLINE = (20, 26, 32)
TREE = (54, 86, 38)
TREE_HI = (78, 112, 50)

# geometry in metres; image y points down, so traffic (right-hand) runs counter-clockwise on screen
ISLAND_R = 8.0
DIVIDER_R = 12.0
RING_R = 16.0            # outer asphalt edge of the ring
WALK = 3.0               # sidewalk width
ARM_HW = 7.0             # arm half width: 2 lanes in + 2 lanes out, 3.5 m each
FILLET = 7.0             # asphalt corner radius where an arm meets the ring
ARMS = (0.0, 90.0, 180.0, 270.0)  # image angles: east, south, west, north


# ---------------------------------------------------------------------------------------- helpers

def noise(size: tuple[int, int], cell: int, seed: int) -> Image.Image:
    """Smooth value noise (L, mean 128) from a seeded random grid, upscaled bicubically."""
    rnd = random.Random(seed)
    gw, gh = max(2, size[0] // cell + 2), max(2, size[1] // cell + 2)
    small = Image.new("L", (gw, gh))
    small.putdata([max(0, min(255, int(rnd.gauss(128, 40)))) for _ in range(gw * gh)])
    return small.resize((gw * cell, gh * cell), Image.BICUBIC).crop((0, 0, *size))


def textured(size: tuple[int, int], base: tuple[int, int, int], amount: float, seed: int,
             scale: float) -> Image.Image:
    """A flat colour with two octaves of seeded noise (amount = +-brightness at full swing)."""
    n1 = noise(size, max(2, int(18 * scale)), seed)
    n2 = noise(size, max(1, int(3 * scale)), seed + 1)
    n = Image.blend(n1, n2, 0.45)
    lut = []
    for c in base:
        lut += [max(0, min(255, int(c + (v - 128) / 128 * amount * 2))) for v in range(256)]
    return Image.merge("RGB", (n, n, n)).point(lut)


def rot(x: float, y: float, deg: float) -> tuple[float, float]:
    a = math.radians(deg)
    return (x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a))


class Plan:
    """A top-down canvas in metres, centred on the roundabout."""

    def __init__(self, half_m: float, ppm: float):
        self.half, self.ppm = half_m, ppm
        self.n = int(2 * half_m * ppm)

    def P(self, x: float, y: float) -> tuple[float, float]:
        return ((x + self.half) * self.ppm, (y + self.half) * self.ppm)

    def mask(self) -> Image.Image:
        return Image.new("L", (self.n, self.n), 0)

    def disc(self, m: Image.Image, r: float, fill: int = 255, cx: float = 0, cy: float = 0) -> None:
        ImageDraw.Draw(m).ellipse([self.P(cx - r, cy - r), self.P(cx + r, cy + r)], fill=fill)

    def junction(self, ring_r: float, hw: float, fillet: float, arm_len: float) -> Image.Image:
        """Ring disc + straight arms, with concave fillets where the arms meet the ring."""
        m = self.mask()
        d = ImageDraw.Draw(m)
        self.disc(m, ring_r)
        for ang in ARMS:
            d.polygon([self.P(*rot(x, y, ang)) for x, y in ((0, -hw), (arm_len, -hw), (arm_len, hw), (0, hw))], fill=255)
            for side in (-1, 1):
                # fillet circle tangent to the arm edge (y = side*hw) and to the ring from outside
                fy = side * (hw + fillet)
                fx = math.sqrt((ring_r + fillet) ** 2 - fy ** 2)
                t_line = (fx, side * hw)
                k = ring_r / (ring_r + fillet)
                t_circ = (fx * k, fy * k)
                corner = Image.new("L", m.size, 0)
                cd = ImageDraw.Draw(corner)
                cd.polygon([self.P(*rot(*p, ang)) for p in ((fx, fy), t_line, (0, 0), t_circ)], fill=255)
                hole = self.mask()
                self.disc(hole, fillet, cx=rot(fx, fy, ang)[0], cy=rot(fx, fy, ang)[1])
                m = ImageChops.lighter(m, ImageChops.subtract(corner, hole))
                d = ImageDraw.Draw(m)
        return m


def lane_path(entry_x: float, ring_r: float, exit_arm: float, exit_off: float, arm_len: float,
              step: float = 0.4) -> list[tuple[float, float]]:
    """Entry on the south arm at x = entry_x, onto the ring at radius ring_r (counter-clockwise on
    screen), off at arm angle exit_arm on its right-hand side (offset exit_off)."""
    pts: list[tuple[float, float]] = []
    y0 = math.sqrt(max(RING_R ** 2 - entry_x ** 2, 0)) + 2.0  # just outside the give-way line
    y = arm_len
    while y > y0:
        pts.append((entry_x, y))
        y -= step
    a_in = 90.0 - 34.0      # where the curve settles on the ring lane
    a_out = exit_arm + 34.0
    # entry blend: cubic from (entry_x, y0) heading north to the ring lane at a_in heading CCW
    def bez(p0, p1, p2, p3, n=40):
        out = []
        for i in range(n + 1):
            t = i / n
            out.append(tuple((1 - t) ** 3 * a + 3 * (1 - t) ** 2 * t * b + 3 * (1 - t) * t * t * c + t ** 3 * e
                             for a, b, c, e in zip(p0, p1, p2, p3)))
        return out
    ai = math.radians(a_in)
    q = (ring_r * math.cos(ai), ring_r * math.sin(ai))
    tq = (math.sin(ai), -math.cos(ai))  # CCW on screen tangent
    h = 0.45 * math.dist((entry_x, y0), q)
    pts += bez((entry_x, y0), (entry_x, y0 - h), (q[0] - tq[0] * h, q[1] - tq[1] * h), q)
    a = a_in
    while a > a_out:
        r = math.radians(a)
        pts.append((ring_r * math.cos(r), ring_r * math.sin(r)))
        a -= 2.0
    ao = math.radians(a_out)
    q2 = (ring_r * math.cos(ao), ring_r * math.sin(ao))
    t2 = (math.sin(ao), -math.cos(ao))
    # exit lane: arm direction u, right-hand side (driving away from the centre) is u rotated +90
    u = (math.cos(math.radians(exit_arm)), math.sin(math.radians(exit_arm)))
    rgt = (-u[1], u[0])
    e_dist = RING_R + 2.0
    e0 = (u[0] * e_dist + rgt[0] * exit_off, u[1] * e_dist + rgt[1] * exit_off)
    h = 0.45 * math.dist(q2, e0)
    pts += bez(q2, (q2[0] + t2[0] * h, q2[1] + t2[1] * h), (e0[0] - u[0] * h, e0[1] - u[1] * h), e0)
    dist = e_dist
    while dist < arm_len:
        dist += step
        pts.append((u[0] * dist + rgt[0] * exit_off, u[1] * dist + rgt[1] * exit_off))
    return pts


# ------------------------------------------------------------------------------------------ scene

def plan_scene(plan: Plan, arm_len: float, preview: bool, line_w: float, path_len: float) -> tuple[Image.Image, Image.Image]:
    """Top-down RGB scene and the road-shape mask (asphalt + sidewalks)."""
    size = (plan.n, plan.n)
    sc = plan.ppm / 4
    img = textured(size, GROUND, 10, 11, sc) if preview else Image.new("RGB", size, SIDEWALK)
    walk = plan.junction(RING_R + WALK, ARM_HW + WALK, FILLET - WALK, arm_len)
    curb = plan.junction(RING_R + 0.45, ARM_HW + 0.45, FILLET - 0.45, arm_len)
    road = plan.junction(RING_R, ARM_HW, FILLET, arm_len)
    img.paste(textured(size, SIDEWALK, 7, 21, sc), mask=walk)
    if preview:  # a darker edge where the sidewalk meets the grass
        edge = ImageChops.subtract(walk, plan.junction(RING_R + WALK - 0.35, ARM_HW + WALK - 0.35, FILLET - WALK + 0.35, arm_len))
        img.paste((110, 106, 98), mask=edge)
    img.paste(CURB, mask=curb)
    img.paste(textured(size, ASPHALT, 9, 31, sc), mask=road)

    # central island: curb ring, grass, a couple of shrubs
    isl = plan.mask()
    plan.disc(isl, ISLAND_R + 0.5)
    img.paste(CURB, mask=isl)
    isl = plan.mask()
    plan.disc(isl, ISLAND_R)
    img.paste(textured(size, GRASS, 12, 41, sc), mask=isl)

    d = ImageDraw.Draw(img)
    mw = max(1, int(0.32 * plan.ppm))
    # ring lane divider (dashed)
    n = 44
    for i in range(n):
        a0 = 360 / n * i
        d.arc([plan.P(-DIVIDER_R, -DIVIDER_R), plan.P(DIVIDER_R, DIVIDER_R)], a0, a0 + 360 / n * 0.5, fill=MARK, width=mw)
    for ang in ARMS:
        def L(x0, y0, x1, y1, w=mw):
            d.line([plan.P(*rot(x0, y0, ang)), plan.P(*rot(x1, y1, ang))], fill=MARK, width=w)
        x_start = math.sqrt(RING_R ** 2 - ARM_HW ** 2) + 0.6
        # centre line: double solid
        L(x_start + 3, -0.3, arm_len, -0.3)
        L(x_start + 3, 0.3, arm_len, 0.3)
        # lane dividers (dashed) both directions
        for side in (-1, 1):
            x = x_start + 3
            while x < arm_len:
                L(x, side * 3.5, min(x + 2.5, arm_len), side * 3.5)
                x += 6
        # give-way line across the entry half (right-hand traffic: entries on the y<0 side of
        # each arm's local frame, i.e. the left of the outbound direction)
        gx = x_start + 0.8
        y = -ARM_HW + 0.3
        while y < -0.6:
            L(gx, y, gx, min(y + 0.9, -0.6), w=int(mw * 1.6))
            y += 1.6

    if preview:  # shrubs on the island
        for (x, y, r) in ((-2.2, -1.5, 3.0), (2.6, 1.2, 2.5), (0.4, 3.6, 1.8), (-3.0, 3.2, 1.6), (3.2, -3.6, 1.7)):
            sh = plan.mask()
            plan.disc(sh, r, cx=x + 0.8, cy=y + 0.9)
            img.paste((62, 82, 40), mask=sh.filter(ImageFilter.GaussianBlur(plan.ppm * 0.4)))
            m = plan.mask()
            plan.disc(m, r, cx=x, cy=y)
            img.paste(textured(size, TREE, 14, 51 + int(r * 10), sc), mask=m)
            m = plan.mask()
            plan.disc(m, r * 0.5, cx=x - r * 0.25, cy=y - r * 0.25)
            img.paste(TREE_HI, mask=m.filter(ImageFilter.GaussianBlur(plan.ppm * 0.5)))

    # lane connections: south arm entry (outbound east is +x; south arm entries are at x > 0)
    # exit_arm is the image angle of the exit arm, counted down (counter-clockwise on screen) from
    # the south entry at 90: east 0, north -90, west -180
    for entry_x, ring_r, exit_arm, colour in ((5.25, 14.0, 0.0, AMBER), (1.75, 10.0, -180.0, CYAN)):
        exit_off = 5.25 if ring_r > 12 else 1.75
        pts = lane_path(entry_x, ring_r, exit_arm, exit_off, path_len)
        flat = [plan.P(*p) for p in pts]
        ow, cw = int(line_w * 1.9 * plan.ppm), int(line_w * plan.ppm)
        d.line(flat, fill=OUTLINE, width=ow, joint="curve")
        for p in (flat[0],):
            d.ellipse([p[0] - ow / 2, p[1] - ow / 2, p[0] + ow / 2, p[1] + ow / 2], fill=OUTLINE)
        # arrow head at the end
        (x1, y1), (x0, y0) = pts[-1], pts[-6]
        ux, uy = x1 - x0, y1 - y0
        ln = math.hypot(ux, uy)
        ux, uy = ux / ln, uy / ln
        hl, hw = line_w * 3.0, line_w * 2.1
        tip = (x1 + ux * hl * 0.9, y1 + uy * hl * 0.9)
        head = [tip, (x1 - uy * hw, y1 + ux * hw), (x1 + uy * hw, y1 - ux * hw)]
        grow = line_w * 0.45
        head_o = [(tip[0] + ux * grow * 1.6, tip[1] + uy * grow * 1.6),
                  (x1 - uy * (hw + grow * 1.5) - ux * grow, y1 + ux * (hw + grow * 1.5) - uy * grow),
                  (x1 + uy * (hw + grow * 1.5) - ux * grow, y1 - ux * (hw + grow * 1.5) - uy * grow)]
        d.polygon([plan.P(*p) for p in head_o], fill=OUTLINE)
        d.line(flat, fill=colour, width=cw, joint="curve")
        p = flat[0]
        d.ellipse([p[0] - cw / 2, p[1] - cw / 2, p[0] + cw / 2, p[1] + cw / 2], fill=colour)
        d.polygon([plan.P(*q) for q in head], fill=colour)

    return img, walk


def tilt(plan_img: Image.Image, plan: Plan, out: tuple[int, int], zoom: float, yaw: float, squash: float,
         centre: tuple[float, float], resample=Image.BICUBIC) -> Image.Image:
    """Rotate by yaw and foreshorten by squash (the tilted camera), as an affine warp.
    screen = centre + zoom * [[c, -s], [squash*s, squash*c]] . world."""
    c, s = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
    a, b, cc, dd = zoom * c, -zoom * s, zoom * squash * s, zoom * squash * c
    det = a * dd - b * cc
    ia, ib, ic, idd = dd / det, -b / det, -cc / det, a / det
    # world = inv . (screen - centre); plan_px = (world + half) * ppm
    p = plan.ppm
    coeffs = (ia * p, ib * p, (-(ia * centre[0] + ib * centre[1]) + plan.half) * p,
              ic * p, idd * p, (-(ic * centre[0] + idd * centre[1]) + plan.half) * p)
    return plan_img.transform(out, Image.AFFINE, coeffs, resample=resample)


def sparkle(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, fill, outline=None, ow: float = 0) -> None:
    """A four-pointed star with concave sides."""
    pts = []
    for i in range(16):
        a = math.radians(i * 22.5 - 90)
        rr = r if i % 4 == 0 else (r * 0.22 if i % 2 == 1 else r * 0.16)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    if outline is not None:
        big = []
        for i in range(16):
            a = math.radians(i * 22.5 - 90)
            rr = (r + ow * 1.6) if i % 4 == 0 else ((r * 0.22 + ow) if i % 2 == 1 else (r * 0.16 + ow))
            big.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
        d.polygon(big, fill=outline)
    d.polygon(pts, fill=fill)


# ---------------------------------------------------------------------------------------- outputs

YAW = 40.0       # turns the south (entry) arm toward the lower left, like the base 3/4 camera
SQUASH = 0.62


def render_icon() -> Image.Image:
    S = 4
    w, h = 240 * S, 150 * S
    plan = Plan(34.0, 24.0)
    scene, walk = plan_scene(plan, 34.0, preview=False, line_w=1.25, path_len=23.0)
    zoom = 4.1 * S
    centre = (121 * S, 72 * S)
    rgb = tilt(scene, plan, (w, h), zoom, YAW, SQUASH, centre)
    alpha = tilt(walk, plan, (w, h), zoom, YAW, SQUASH, centre)
    clip = Image.new("L", (w, h), 0)
    ImageDraw.Draw(clip).rectangle([30 * S, 18 * S, 214 * S, 133 * S], fill=255)
    alpha = ImageChops.multiply(alpha, clip)
    img = rgb.convert("RGBA")
    img.putalpha(alpha)
    sparkle(ImageDraw.Draw(img), 194 * S, 37 * S, 19 * S, (255, 255, 255, 255), OUTLINE + (255,), 2.4 * S)
    sparkle(ImageDraw.Draw(img), 172 * S, 24 * S, 9 * S, CYAN + (255,), OUTLINE + (255,), 2.0 * S)
    return img.resize((240, 150), Image.LANCZOS)


def render_preview() -> Image.Image:
    S = 2
    w, h = 720 * S, 405 * S
    plan = Plan(56.0, 24.0)
    scene, _ = plan_scene(plan, 56.0, preview=True, line_w=0.85, path_len=27.0)
    zoom = 10.5 * S
    rgb = tilt(scene, plan, (w, h), zoom, YAW, SQUASH, (360 * S, 196 * S))
    img = rgb.convert("RGBA")
    d = ImageDraw.Draw(img)
    sparkle(d, 640 * S, 70 * S, 34 * S, (255, 255, 255, 255), OUTLINE + (255,), 3 * S)
    sparkle(d, 598 * S, 42 * S, 16 * S, CYAN + (255,), OUTLINE + (255,), 2.5 * S)
    return img.resize((720, 405), Image.LANCZOS)


def write_tga(img: Image.Image, path: Path) -> None:
    """Uncompressed 32-bit BGRA, bottom-left origin, TGA 2.0 footer (as the base icons)."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, img.width, img.height, 32, 8)
    r, g, b, a = img.convert("RGBA").transpose(Image.FLIP_TOP_BOTTOM).split()
    body = Image.merge("RGBA", (b, g, r, a)).tobytes()
    footer = struct.pack("<II", 0, 0) + b"TRUEVISION-XFILE.\0"
    path.write_bytes(header + body + footer)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--png", type=Path, metavar="DIR",
                    help="also write PNG previews to DIR (icon on the menu tile grey, at 1x and 2x, and the preview)")
    args = ap.parse_args()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for img, name in ((render_icon(), "sl_tool@2x.tga"), (render_preview(), "sl_tool_preview@2x.tga")):
        out = OUT_DIR / name
        write_tga(img, out)
        print(f"wrote {out.relative_to(MODS_DIR.parent)} ({img.width}x{img.height}, 32-bit TGA)")
        if args.png:
            args.png.mkdir(parents=True, exist_ok=True)
            stem = name.replace("@2x.tga", "")
            bg = Image.new("RGBA", img.size, (178, 182, 186, 255))  # menu tile grey
            bg.alpha_composite(img)
            bg.save(args.png / f"{stem}.png")
            if img.width == 240:
                bg.resize((120, 75), Image.LANCZOS).save(args.png / f"{stem}_1x.png")
            print(f"wrote {args.png / (stem + '.png')}")


if __name__ == "__main__":
    main()
