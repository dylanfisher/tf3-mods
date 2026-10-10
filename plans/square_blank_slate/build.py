"""Build Blank Slate's terrain generator files.

Writes, under mods/square_blank_slate/content/blank_slate/:
  island_hmap.png                 16-bit grayscale heightmap: flat plateau, sloped coast, sea rim
  blank_slate_<climate>.gen.lua   one generator per base climate (shows in that climate's dropdown)
  blank_slate_<climate>_gen.tree.lua

The tree samples the PNG with a texture_map node (as urbangames_campaign_mission_07 does) between
HEIGHT_MIN and HEIGHT_MAX, so white = HEIGHT_MAX exactly. Sea level is fixed at 0 m by the engine.
Asset and forest maps are constant 0, which no mapping entry uses, so no trees or rocks are placed.

Run: uv run plans/square_blank_slate/build.py
"""

import math
import struct
import zlib
from pathlib import Path

MOD_ID = "square_blank_slate"
OUT = Path(__file__).resolve().parents[2] / "mods" / MOD_ID / "content" / "blank_slate"

HEIGHT_MIN = -30.0  # sea floor (m)
HEIGHT_MAX = 5.0  # plateau (m), same as the Map Editor's blank map
SIZE = 1024  # PNG side (px); stretched over the whole map

# Island shape in map fractions (0..1 per side, stretched on non-square maps).
HALF = 0.40  # half-size of the plateau's rounded square, from the centre
CORNER = 0.06  # corner radius
COAST = 0.035  # width of the slope from plateau edge down to the sea floor

# Per climate: a real tag from that climate's own gen tree, so the (unused) mapping tables stay valid.
CLIMATES = {
    "temperate": {"name": "Temperate", "asset": "granite", "forest": "temperate_single"},
    "dry": {"name": "Dry", "asset": "sandstone", "forest": "desert_rock"},
    "tropical": {"name": "Tropical", "asset": "tropical_cliff_shrub", "forest": "tropical_hill_tree"},
    "subarctic": {"name": "Subarctic", "asset": "coast_stone", "forest": "norway_spruce"},
}


def height_at(u: float, v: float) -> float:
    """0..1 height fraction at map position (u, v) in 0..1."""
    # Signed distance to a rounded square centred on the map (negative inside).
    qx = abs(u - 0.5) - (HALF - CORNER)
    qy = abs(v - 0.5) - (HALF - CORNER)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    sd = outside + min(max(qx, qy), 0.0) - CORNER
    if sd <= 0.0:
        return 1.0
    t = min(sd / COAST, 1.0)
    return 1.0 - t * t * (3.0 - 2.0 * t)  # smoothstep down to the sea floor


def write_png16(path: Path) -> None:
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # filter: none
        v = (y + 0.5) / SIZE
        for x in range(SIZE):
            rows += struct.pack(">H", round(height_at((x + 0.5) / SIZE, v) * 65535))

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 16, 0, 0, 0, 0)  # 16-bit grayscale
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(rows), 9))
        + chunk(b"IEND", b"")
    )


def node(name: str, layer: str, pos: tuple[float, float], inputs: dict[str, str] | None = None, params: str = "") -> str:
    ins = "".join(
        f'\t\t\t\t\t{k} = {{ key = "out", nodeName = "{n}", }},\n' for k, n in (inputs or {}).items()
    )
    return (
        "\t\t\t{\n"
        "\t\t\t\tcolor = { 0.01, 0.1, 0.2, 0.6, },\n"
        f"\t\t\t\tinputs = {{\n{ins}\t\t\t\t}},\n"
        f'\t\t\t\tlayerType = "{layer}",\n'
        f'\t\t\t\tname = "{name}",\n'
        f"\t\t\t\tparams = {{ {params}}},\n"
        f"\t\t\t\tposition = {{ {pos[0]}, {pos[1]}, }},\n"
        "\t\t\t},\n"
    )


def mask(key: str, source: str, y: float) -> str:
    return node(
        f"{key} out", "output_map_data", (-0.38, y), {"output": source},
        f'key = "{key}", resolutionx = 32, resolutiony = 32, ',
    )


def tree(climate: str, c: dict[str, str]) -> str:
    nodes = [
        node("height min", "constant_number", (-0.44, -0.16), params=f"value = {HEIGHT_MIN:g}, "),
        node("height max", "constant_number", (-0.44, -0.15), params=f"value = {HEIGHT_MAX:g}, "),
        node(
            "island heightmap", "texture_map", (-0.42, -0.155),
            {"minHeight": "height min", "maxHeight": "height max"},
            f'tex = "{MOD_ID}::/blank_slate/island_hmap.png", ',
        ),
        node("hm_out", "height_map_output", (-0.40, -0.155), {"in1": "island heightmap"}),
        node("zero", "constant_map", (-0.42, -0.13), params="value = 0, "),
        node("one", "constant_map", (-0.42, -0.12), params="value = 1, "),
        # Nothing maps value 0, so no rocks or trees are placed.
        node(
            "assets_out", "assets_output", (-0.38, -0.17), {"assets": "zero", "forest": "zero"},
            f'assets = {{ {{ 1, "{c["asset"]}", }}, }}, forest = {{ {{ 1, "{c["forest"]}", }}, }}, ',
        ),
        # One biome everywhere, no forest mask (no reforestation).
        mask("biome0", "one", -0.14),
        mask("biome1", "zero", -0.13),
        mask("biome2", "zero", -0.12),
        mask("biome3", "zero", -0.11),
        mask("biome4", "zero", -0.10),
        mask("forest_mask", "zero", -0.09),
        node("Biomes Output", "output_biomes", (-0.38, -0.08), {"output": "zero"}, 'layerKey = "", type = "Biomes", '),
    ]
    return (
        "-- Generated by plans/square_blank_slate/build.py; edit that and rerun.\n"
        "function data()\n"
        "return {\n"
        f'\t\tclimate = "::/climates/{climate}/{climate}.clima",\n'
        "\t\tcomments = { },\n"
        "\t\tnodes = {\n" + "".join(nodes) + "\t\t},\n"
        '\t\tpreviewSeed = "blank",\n'
        "\t\tsnapPoints = { },\n"
        "\t}\n"
        "end\n"
    )


def gen(climate: str) -> str:
    return (
        "-- Generated by plans/square_blank_slate/build.py; edit that and rerun.\n"
        "function data()\n"
        "return {\n"
        f'\t\tnodeTree = "blank_slate_{climate}_gen.tree",\n'
        f'\t\tclimate = "::/climates/{climate}/{climate}.clima",\n'
        "\t\tdesc = {\n"
        "\t\t\tcargoTypeSet = {\n"
        "\t\t\t\tcargoClassesExcluded = { },\n"
        "\t\t\t\tcargoClassesIncluded = { },\n"
        "\t\t\t\tcargoTypesExcluded = { },\n"
        "\t\t\t\tcargoTypesIncluded = { },\n"
        "\t\t\t},\n"
        '\t\t\tname = _("Blank Slate (flat island)"),\n'
        "\t\t},\n"
        "\t\teditorOnly = false,\n"
        "\t\torder = 10,\n"
        "\t\tparams = { },\n"
        '\t\tpreviewSeed = "blank",\n'
        '\t\tupdateScript = {\n\t\t\tfileName = "",\n\t\t\tparams = { },\n\t\t},\n'
        "\t}\n"
        "end\n"
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    write_png16(OUT / "island_hmap.png")
    for climate, c in CLIMATES.items():
        (OUT / f"blank_slate_{climate}.gen.lua").write_text(gen(climate))
        (OUT / f"blank_slate_{climate}_gen.tree.lua").write_text(tree(climate, c))
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
