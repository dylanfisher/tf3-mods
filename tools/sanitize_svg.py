"""Sanitize an untrusted SVG (e.g. a flag from Wikimedia Commons) into a static, self-contained drawing.

Run it isolated, with the input as an argument (never from inside the download directory):

    python -I tools/sanitize_svg.py <in.svg> <out.svg>

Allow-list based: only shape, group, gradient, clip/mask and `use` elements survive, with plain presentation
attributes. Rejected outright: DOCTYPE / ENTITY declarations. Dropped: <script>, <foreignObject>, <image>,
<a>, animation elements, editor metadata (sodipodi/inkscape/rdf), every on* attribute, every href that is not a
local "#id" reference, and style text that loads anything (@import, url() to anything but "#id").
Prints the output size and element counts for review. Standard library only, so `-I` is enough.
"""

from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from collections import Counter
from pathlib import Path

SVG = "http://www.w3.org/2000/svg"
XLINK = "http://www.w3.org/1999/xlink"

KEEP = {
    "svg", "g", "defs", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
    "linearGradient", "radialGradient", "stop", "clipPath", "mask", "use", "symbol", "title", "style",
}
# Presentation and geometry attributes worth keeping (anything else is dropped).
ATTRS = {
    "id", "class", "style", "transform", "d", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry",
    "fx", "fy", "width", "height", "points", "viewBox", "preserveAspectRatio", "version",
    "fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-opacity", "stroke-linecap",
    "stroke-linejoin", "stroke-miterlimit", "stroke-dasharray", "stroke-dashoffset", "opacity", "color",
    "clip-path", "clip-rule", "clipPathUnits", "mask", "maskUnits", "maskContentUnits", "display", "visibility",
    "offset", "stop-color", "stop-opacity", "gradientUnits", "gradientTransform", "spreadMethod", "href",
    "overflow", "paint-order", "vector-effect", "shape-rendering", "color-interpolation",
}
BAD_URL = re.compile(r"url\(\s*(?!['\"]?#)", re.I)       # url(...) that isn't a local #id
BAD_CSS = re.compile(r"@import|expression\s*\(|javascript:|behavior\s*:", re.I)


def local(tag: str) -> tuple[str, str]:
    if tag.startswith("{"):
        ns, _, name = tag[1:].partition("}")
        return ns, name
    return "", tag


def clean(el: ET.Element, counts: Counter, dropped: Counter) -> None:
    for child in list(el):
        if not isinstance(child.tag, str):  # comments / processing instructions
            el.remove(child)
            continue
        ns, name = local(child.tag)
        if ns != SVG or name not in KEEP:
            dropped[name] += 1
            el.remove(child)
            continue
        if name == "style" and (BAD_CSS.search(child.text or "") or BAD_URL.search(child.text or "")):
            dropped["style(unsafe)"] += 1
            el.remove(child)
            continue
        scrub_attrs(child, dropped)
        counts[name] += 1
        clean(child, counts, dropped)


def scrub_attrs(el: ET.Element, dropped: Counter) -> None:
    for key in list(el.attrib):
        ns, name = local(key)
        value = el.attrib[key]
        ok = (ns == "" or (ns == XLINK and name == "href")) and name in ATTRS and not name.lower().startswith("on")
        if ok and name == "href" and not value.startswith("#"):
            ok = False
        if ok and (BAD_URL.search(value) or BAD_CSS.search(value)):
            ok = False
        if not ok:
            dropped["@" + name] += 1
            del el.attrib[key]
        elif ns == XLINK:  # normalise xlink:href to plain href (SVG 2)
            del el.attrib[key]
            el.set("href", value)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    raw = src.read_bytes()
    if re.search(rb"<!DOCTYPE|<!ENTITY", raw, re.I):
        sys.exit(f"{src}: DOCTYPE/ENTITY declarations are not allowed; refusing")
    root = ET.fromstring(raw)
    if local(root.tag) != (SVG, "svg"):
        sys.exit(f"{src}: root element is {root.tag}, not an SVG <svg>")
    counts: Counter = Counter({"svg": 1})
    dropped: Counter = Counter()
    scrub_attrs(root, dropped)
    clean(root, counts, dropped)
    if "viewBox" not in root.attrib and {"width", "height"} <= set(root.attrib):
        w, h = (re.sub(r"[^0-9.]", "", root.attrib[k]) for k in ("width", "height"))
        root.set("viewBox", f"0 0 {w} {h}")
    ET.register_namespace("", SVG)
    text = ET.tostring(root, encoding="unicode")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + text + "\n", encoding="utf-8")
    print(f"wrote {out} ({out.stat().st_size // 1024} KB, from {len(raw) // 1024} KB) viewBox={root.get('viewBox')}")
    print("  kept:    " + ", ".join(f"{k} {v}" for k, v in counts.most_common()))
    print("  dropped: " + (", ".join(f"{k} {v}" for k, v in dropped.most_common()) or "nothing"))


if __name__ == "__main__":
    main()
