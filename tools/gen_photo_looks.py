# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Write Photo Mode's look environments: one .env.lua per base climate and sky / haze / water combination.

Reads the base climate environments (.cache/game/base/content/climates/<c>/<c>.env.lua, from
`make docs`), applies one SKY look (sun, moon, Rayleigh and ozone fields of `atmosphere`, and the
`light` block: exposure, contrast, ambient), one HAZE look (every mie field and the aerial
perspective fogScaleLow / High) and one WATER look (the `water` block, plus two overcast-only light
fields owned by Wild water) and writes

  mods/square_photo_mode/content/environments/sqpm_<climate>_<sky>_<haze>_<water>.env.lua

with "orig" for a layer left as the climate's own (orig x3 is the climate itself: no file).
Layers: an environment file is switched as a whole (only the six atmosphere fields of
api type.d.tl Environment.AthmostphereParams are live-settable), so mixing looks needs a file per
combination. The three layers change disjoint fields (checked here), so each file is the sky look's
changes plus the haze look's plus the water look's. Clouds, the day and the sun stay live (Photo
Mode carries them over every switch). 4 climates x (9 x 6 x 5 - 1) = 1076 files of ~4.2 KB, 4.5 MB (round 15; 396 in
round 12).

ResName in game: `square_photo_mode::/environments/sqpm_<climate>_<sky>_<haze>_<water>.env` (the form
the probe's T7 found for its own env file). Photo Mode switches to them for rendering only
(`api.gui.rendering.setEnvironment`, never `api.gui.game.setEnvironment`), see
plans/square_photo_mode/LOOKS.md. The keys and their order must match
`content/photo_mode/pm_looks.lua` SKY_ORDER / HAZE_ORDER / WATER_ORDER (the offline test test_looks.lua checks
every file).

Every file: `isToolEnvironment = true` (hidden from the calendar editor's Environment list, as the
base *_old and model-editor envs; climates for a new game come from .clima.lua files, which never
name these), a plain English name "Photo Mode look: <Sky> + <Haze> + <Water> (<Climate>)", texture paths
made absolute (a relative "sun.dds" resolves next to the env file, so it becomes
"::/climates/<c>/sun.dds"; "/climates/shared/x" becomes "::/climates/shared/x").

Values stay inside the wiki's documented ranges (modding/environment/environments.md) and our own
sanity bounds where the wiki gives none; RANGES below fails the run otherwise.

Usage:
  uv run tools/gen_photo_looks.py           write the files (and remove stale sqpm_* files)
  uv run tools/gen_photo_looks.py --check   exit 1 when a file is missing or differs (after a
                                            game update changed a base climate: rerun to refresh)
"""

from __future__ import annotations

import argparse
import copy
import importlib
import itertools
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import GAME_CACHE_DIR, ROOT  # noqa: E402

try:
    LuaRuntime = importlib.import_module("lupa.lua54").LuaRuntime
except ImportError:  # pragma: no cover
    raise SystemExit("lupa is required; run this script through `uv run`")

CLIMATES = ["dry", "temperate", "subarctic", "tropical"]
CLIMATE_NAMES = {"dry": "Dry", "temperate": "Temperate", "subarctic": "Subarctic", "tropical": "Tropical"}
OUT_DIR = ROOT / "mods" / "square_photo_mode" / "content" / "environments"
PREFIX = "sqpm_"
ORIG = "orig"

# Documented ranges (wiki environments.md); hdr*, miePhaseG(Overcast), the *Overcast mie scales, normalScale, sunsetBoostScale, extinctionCoeff:
# sanity bounds of our own (the wiki gives none). Only fields a look changes are checked. normalScale goes past
# the base files' 0.3..0.6 on purpose: the water shader (rendering/programs/shaders/mat/fs/water_normals.fs)
# multiplies it by 0.5 * log2((depth + 5) / 4), about 0.16 at 0 m, 0.5 at 3 m and 1.3 at 20 m, so shallow
# rivers need a far larger value than the sea for the same choppiness.
RANGES = {
    ("atmosphere", "sunBloom"): (0, 1000),
    ("atmosphere", "sunBloomScale"): (0, 10),
    ("atmosphere", "sunIlluminance"): (0, 100),
    ("atmosphere", "sunIntensity"): (0, 100000),
    ("atmosphere", "sunSizeAngle"): (0, 5),
    ("atmosphere", "moonIlluminance"): (0, 100),
    ("atmosphere", "moonIntensity"): (0, 1000),
    ("atmosphere", "mieScatteringScale"): (0, 1),
    ("atmosphere", "mieAbsorptionScale"): (0, 1),
    ("atmosphere", "mieScatteringScaleOvercast"): (0, 1),
    ("atmosphere", "mieAbsorptionScaleOvercast"): (0, 1),
    ("atmosphere", "mieScaleHeight"): (0, 100),
    ("atmosphere", "miePhaseG"): (0, 0.99),
    ("atmosphere", "miePhaseGOvercast"): (0, 0.99),
    ("atmosphere", "rayScatteringScale"): (0, 1),
    ("atmosphere", "absorptionScale"): (0, 1),
    ("atmosphere", "fogScaleLow"): (0.1, 25),
    ("atmosphere", "fogScaleHigh"): (0.1, 25),
    ("atmosphere", "sunsetBoostScale"): (0, 10),
    ("atmosphere", "sunsetBoostParam"): (0.05, 2),
    ("light", "hdrExposureDay"): (0.1, 4),
    ("light", "hdrExposureNight"): (0.1, 6),
    ("light", "hdrExposureOvercast"): (0.1, 4),
    ("light", "hdrContrastDay"): (0.5, 3),
    ("light", "hdrContrastNight"): (0.5, 3),
    ("light", "hdrContrastOvercast"): (0.5, 3),
    ("light", "globalEmissiveScale"): (0, 6),
    ("water", "normalScale"): (0, 8),
    ("water", "roughness"): (0, 1),
    ("water", "extinctionCoeff"): (0, 1),
}


# A change: ("set", value) | ("mul", factor) | ("contrast", value added to hdrContrastDay[1]).
def mul(f):
    return ("mul", f)


def setv(v):
    return ("set", v)


FOAM = "::/climates/shared/water_wave_foam.dds"

# Round 12 (user: "Is it possible to mix Dramatic sky and a new selector for haze?"): the atmosphere is split in two
# layers. SKY: the sun (disc, bloom, brightness, sunset glow), Rayleigh / ozone (the sky's colour) and the `light`
# grade. HAZE: the aerosol (all mie fields) and the aerial perspective (fogScaleLow / High). The old sky looks were
# split along that line: Hazy morning, Crisp & clear, Misty valley and Soft background became haze looks (their
# light grade went to the new Soft light sky, Crisp's deep blue to Dramatic), Dramatic and Storybook lost their mie
# changes. plans/square_photo_mode/LOOKS.md "Round 12".
#
# The sky looks, in the window's order (`atmosphere` sun / Rayleigh / ozone fields and the `light` block). Each:
# key, English name, intent, changes per section. Relative (mul) where the climates differ on purpose, absolute
# (set) where the look needs one value everywhere.
SKY = [
    {
        "key": "soft_light",
        "name": "Soft light",
        "intent": "Soft, bright light (the grade of round 11's Misty valley and Soft background): a lifted neutral "
        "fill (soft shadows), brighter exposure and low contrast, a veiled sun disc (x0.8) with a wide soft "
        "glow (sunBloom 150, scale x1.5). Pairs with the Misty valley and Soft background haze.",
        "atmosphere": {
            "sunBloom": setv(150),
            "sunBloomScale": mul(1.5),
            "sunIntensity": mul(0.8),
        },
        "light": {
            "ambientDayColor": setv([0.08, 0.08, 0.082]),
            "hdrExposureDay": mul(1.15),
            "hdrContrastDay": ("contrast", -0.35),
        },
    },
    {
        "key": "dramatic",
        "name": "Dramatic",
        "intent": "Hard light and a huge sun under a deep blue sky: much more contrast by day and night, a bigger "
        "sun disc (x1.8) with a wide bloom (sunBloom 80: smaller = larger haze, scale x2.5), twice the sunset "
        "glow, a quarter more direct sun, almost black shadows, stronger Rayleigh scattering and ozone (round "
        "11's Crisp & clear sky).",
        "atmosphere": {
            "sunBloom": setv(80),
            "sunBloomScale": mul(2.5),
            "sunSizeAngle": mul(1.8),
            "sunsetBoostScale": mul(2.0),
            "sunIntensity": mul(1.25),
            "rayScatteringScale": mul(1.3),
            "absorptionScale": mul(1.6),
        },
        "light": {
            "ambientDayColor": setv([0.025, 0.025, 0.03]),
            "hdrContrastDay": ("contrast", 0.6),
            "hdrContrastNight": setv(1.4),
        },
    },
    {
        "key": "storybook",
        "name": "Storybook",
        "intent": "A pastel picture-book sky: the Rayleigh colour moved from deep blue to a pale lavender blue, "
        "a little weaker, rich sunsets, a bright warm ambient fill (soft shadows), brighter exposure and gentle "
        "contrast. Good for a model-railway look.",
        "atmosphere": {
            "rayScatteringCoeff": setv([0.26, 0.42, 0.70]),
            "rayScatteringScale": mul(0.85),
            "sunsetBoostScale": mul(1.8),
        },
        "light": {
            "ambientDayColor": setv([0.12, 0.10, 0.09]),
            "hdrExposureDay": mul(1.3),
            "hdrContrastDay": ("contrast", -0.35),
        },
    },
    {
        "key": "moonlit_night",
        "name": "Moonlit night",
        "intent": "A full moon: eight times the moon's illuminance (indirect light), three times its intensity, "
        "a blue night ambient, more night exposure and contrast, and (round 16) twice the glow of lit windows and "
        "lamps (light.globalEmissiveScale: mat/fs/normal/physical.fs multiplies the window light by it, "
        "emissive.fs every emissive material). Only shows at night.",
        "atmosphere": {
            "moonIlluminance": mul(8.0),
            "moonIntensity": mul(3.0),
        },
        "light": {
            "ambientNightColor": setv([0.02, 0.03, 0.06]),
            "hdrExposureNight": mul(1.6),
            "hdrContrastNight": setv(1.2),
            "globalEmissiveScale": mul(2.0),
        },
    },
    # Round 15 (user: "Is it possible to add more looks?"). No env field grades the picture's colour (hdr/compose.fs:
    # exposure, bloom, the AMD tone mapper; util/tonemappers.glsl), so colour comes from the light itself: the ozone
    # layer (absorptionCoeff / absorptionScale: atmosphere/common.glsl sampleMediumRGB, in every ray's transmittance
    # to the sun, so it tints the sunlight on the land and the light the sky scatters), the Rayleigh colour, the
    # ambient fill and the sunset boost. The tone mapper's saturation follows its contrast (amdTonemapperOpt:
    # saturation = mix(contrast, 1, 0.25), the colour ratio raised to it), so hdrContrastDay[1] is also the
    # picture's saturation: a full black-and-white "noir" is out of reach (contrast 0.5, the lowest in RANGES,
    # still leaves ~60 % of the colour), "Faded film" goes part of the way. LOOKS.md "Round 15".
    {
        "key": "golden_glow",
        "name": "Golden glow",
        "intent": "Warm golden light all day: an ozone layer that absorbs blue (the sunlight on the land turns "
        "golden, more so the lower the sun), a warm ambient fill, a sunset glow that is stronger and lasts "
        "higher into the day (sunsetBoostScale 5, sunsetBoostParam 0.5) and a wide, soft glow round the sun.",
        "atmosphere": {
            "absorptionCoeff": setv([0.04, 0.30, 0.95]),
            "absorptionScale": setv(0.012),
            "sunsetBoostScale": setv(5.0),
            "sunsetBoostParam": setv(0.5),
            "sunBloom": setv(200),
            "sunBloomScale": mul(1.8),
        },
        "light": {
            "ambientDayColor": setv([0.10, 0.075, 0.045]),
            "hdrExposureDay": mul(1.05),
        },
    },
    {
        "key": "cold_blue",
        "name": "Cold blue",
        "intent": "A cold, clear winter light: an ozone layer that absorbs red and green (a pale, bluish sun), a "
        "little more Rayleigh blue, half the sunset glow, a cool blue ambient fill by day and night, a touch more "
        "contrast and a little less exposure.",
        "atmosphere": {
            "absorptionCoeff": setv([0.62, 0.78, 0.06]),
            "absorptionScale": setv(0.008),
            "rayScatteringScale": mul(1.15),
            "sunsetBoostScale": mul(0.5),
        },
        "light": {
            "ambientDayColor": setv([0.03, 0.042, 0.07]),
            "ambientNightColor": setv([0.005, 0.01, 0.025]),
            "hdrExposureDay": mul(0.95),
            "hdrContrastDay": ("contrast", 0.15),
        },
    },
    {
        "key": "vintage",
        "name": "Faded film",
        "intent": "An old photograph: much lower contrast (the tone mapper's saturation follows it, so the colours "
        "fade too), lifted warm shadows, warm light through an ozone layer that absorbs blue, a paler sky "
        "(Rayleigh x0.8) and a little more exposure.",
        "atmosphere": {
            "absorptionCoeff": setv([0.04, 0.30, 0.95]),
            "absorptionScale": setv(0.008),
            "rayScatteringScale": mul(0.8),
        },
        "light": {
            "ambientDayColor": setv([0.12, 0.10, 0.07]),
            "hdrExposureDay": mul(1.1),
            "hdrContrastDay": ("contrast", -0.5),
            "hdrContrastNight": setv(0.8),
        },
    },
    {
        "key": "neon_dusk",
        "name": "Neon dusk",
        "intent": "Vivid magenta and violet twilight: a strong ozone layer that absorbs green (ozone is what turns "
        "the real sky purple after sunset; here it tints the day a little too), a deeper blue Rayleigh colour, a "
        "strong sunset glow (sunsetBoostScale 7), a violet ambient fill, a bright, contrasty night, more "
        "colour by day (contrast +0.3) and (round 16) windows and lamps glowing 2.5 times as bright "
        "(globalEmissiveScale).",
        "atmosphere": {
            "absorptionCoeff": setv([0.20, 0.97, 0.10]),
            "absorptionScale": setv(0.012),
            "rayScatteringCoeff": setv([0.12, 0.33, 0.94]),
            "sunsetBoostScale": setv(7.0),
        },
        "light": {
            "ambientDayColor": setv([0.06, 0.035, 0.07]),
            "ambientNightColor": setv([0.04, 0.012, 0.06]),
            "hdrExposureNight": mul(1.4),
            "hdrContrastNight": setv(1.4),
            "hdrContrastDay": ("contrast", 0.3),
            "globalEmissiveScale": mul(2.5),
        },
    },
]

# The haze looks, in the window's order (every mie field and fogScaleLow / High). How the shaders turn them into a
# veil (atmosphere/common.glsl sampleMediumRGB, integrateScatteredLuminance; LOOKS.md "Round 12"): mie density
# exp(-(altitude above sea level + heightOffset 0.5 km) / mieScaleHeight) per km, times mieScatteringCoeff x
# mieScatteringScale; geometry rays get their length multiplied by the fog factor (fogScaleLow for a camera up to
# 100 m above sea level), the sky does not. So a small scale height with a large scale puts the aerosol near the
# ground (a veil over the land) and keeps it out of the sky's column; a large scale height fills the sky too.
HAZE = [
    {
        "key": "crisp_clear",
        "name": "Crisp & clear",
        "intent": "Long views after rain: a sixth of the aerosol, a fifth of its absorption and a quarter of the "
        "aerial perspective (fog).",
        "atmosphere": {
            "mieScatteringScale": mul(0.15),
            "mieAbsorptionScale": mul(0.2),
            "fogScaleLow": mul(0.25),
            "fogScaleHigh": mul(0.25),
        },
    },
    {
        "key": "hazy_morning",
        "name": "Hazy morning",
        "intent": "A golden haze: six times the aerosol (mie) scattering, tinted warm, spread twice as high, a "
        "tight bright halo round the sun (miePhaseG 0.9) and much more aerial perspective. Best with the sun low "
        "in the morning or evening.",
        "atmosphere": {
            "mieScatteringScale": mul(6.0),
            "mieScatteringCoeff": setv([0.68, 0.57, 0.46]),
            "miePhaseG": setv(0.9),
            "mieScaleHeight": mul(2.0),
            "fogScaleLow": mul(2.5),
            "fogScaleHigh": mul(1.8),
        },
    },
    {
        # Round 12 scale height fix (round 11 had mie x10 with mieScaleHeight x0.35: the 0.5 km heightOffset left
        # only ~27 % of it at sea level, ~0.6 per km). Absolute now: a dense layer 0.3 km high, white, no absorption,
        # the same under clouds. Model, camera 100 m above sea level, level view: 9 % veil at 50 m, 18 % at 100 m,
        # 32 % at 200 m, 62 % at 500 m, 86 % at 1 km (round 11: 2 / 5 / 9 / 22 / 38 %).
        "key": "misty_valley",
        "name": "Misty valley",
        "intent": "Thick mist lying low: a dense aerosol layer near the ground (mie 0.9 with a 0.3 km scale "
        "height, the same under clouds, no absorption: white, not grey), aerial perspective near the ground "
        "almost at its maximum (fogScaleLow 24), little from above (1.5) and a broad, bright scatter (miePhaseG "
        "0.35). Best at eye level in the morning.",
        "atmosphere": {
            "fogScaleLow": setv(24.0),
            "fogScaleHigh": setv(1.5),
            "mieScatteringScale": setv(0.9),
            "mieScatteringScaleOvercast": setv(0.9),
            "mieAbsorptionScale": setv(0.0),
            "mieAbsorptionScaleOvercast": setv(0.0),
            "mieScatteringCoeff": setv([0.56, 0.58, 0.60]),
            "mieScaleHeight": setv(0.3),
            "miePhaseG": setv(0.35),
            "miePhaseGOvercast": setv(0.35),
        },
    },
    {
        # Round 12 retune (user, Dry map: "the whole scene beyond ~50 m is a heavy grey-brown murk, the sky a dull
        # grey-mauve overcast"). Round 11 had mie 0.25 spread 2 km high: zenith optical depth ~0.23 and ~16 at the
        # horizon (the sky itself became haze), the sun at 10 degrees kept ~20 % of its light through it (a dim,
        # brown veil), extinction ~3 per km at the ground (13 % veil at 50 m, 76 % at 500 m) and phase g 0.45 (dull
        # away from the sun). Now: the aerosol packed low (scale height 0.4 km: zenith depth ~0.02, the sun keeps
        # ~74 % at 10 degrees), ~1.4 per km at the ground with fogScaleLow 25, a near-isotropic phase (g 0.1:
        # bright on every side) and the climate's own fogScaleHigh and mie colour (with the climate's Rayleigh
        # x25 the far veil turns the sky's tint). Model, camera 100 m above sea level: 6 % at 50 m, 11 % at 100 m,
        # 21 % at 200 m, 44 % at 500 m, 68 % at 1 km; 300 m above sea level: 3 / 7 / 13 / 29 / 49 %.
        "key": "soft_background",
        "name": "Soft background",
        "intent": "For close-ups, a stand-in for a blurred background: a bright aerosol veil packed near the "
        "ground (mie 0.27 with a 0.4 km scale height, the same under clouds, no absorption) and the aerial "
        "perspective at its maximum for a low camera (fogScaleLow 25), scattered almost evenly (miePhaseG 0.1) "
        "so it glows on every side, not only towards the sun. A subject 20-80 m away stays clear, about half "
        "the scene is veiled at 500 m, and the sky keeps its colour.",
        "atmosphere": {
            "mieScatteringScale": setv(0.27),
            "mieScatteringScaleOvercast": setv(0.27),
            "mieAbsorptionScale": setv(0.0),
            "mieAbsorptionScaleOvercast": setv(0.0),
            "mieScaleHeight": setv(0.4),
            "miePhaseG": setv(0.1),
            "miePhaseGOvercast": setv(0.1),
            "fogScaleLow": setv(25.0),
        },
    },
    {
        # Round 15. What round 11's Soft background did by accident ("a heavy grey-brown murk", LOOKS.md "Round 12"),
        # on purpose and warmer: an aerosol spread high (scale height 1.2 km fills the sky's column too), dust that
        # absorbs blue (mieAbsorptionCoeff) so the veil and the sun turn orange-brown, the same under clouds.
        "key": "dust_storm",
        "name": "Dust storm",
        "intent": "A desert dust storm: a thick, warm aerosol spread high (mie 0.2, scale height 1.2 km, the same "
        "under clouds), dust that absorbs blue (an orange-brown veil, a dim orange sun), a forward-scattering "
        "phase (0.75) and twice the aerial perspective near the ground. The sky itself turns hazy brown.",
        "atmosphere": {
            "mieScatteringScale": setv(0.2),
            "mieScatteringScaleOvercast": setv(0.2),
            "mieScatteringCoeff": setv([0.66, 0.58, 0.48]),
            "mieAbsorptionScale": setv(0.06),
            "mieAbsorptionScaleOvercast": setv(0.06),
            "mieAbsorptionCoeff": setv([0.25, 0.45, 0.86]),
            "mieScaleHeight": setv(1.2),
            "miePhaseG": setv(0.75),
            "miePhaseGOvercast": setv(0.6),
            "fogScaleLow": setv(6.0),
            "fogScaleHigh": setv(3.0),
        },
    },
]

# The water looks, in the window's order (the `water` block; Wild water also owns the two overcast-only light fields).
# Round 12: Stormy sea merged into Wild water (its overcast light came along) to keep the file count under 400
# (round 15: 1076 with Tropical turquoise, LOOKS.md "Round 15").
# The engine has no flow speed or direction for water: the normal map scrolls with the clock in six fixed
# directions (water_normals.fs), sea and rivers alike, so only how strong, rough, foamy and murky it is changes.
WATER = [
    {
        "key": "mirror",
        "name": "Mirror water",
        "intent": "Still water that mirrors the scene: no wave normals (the wiki: 0 = still water), the subtle "
        "low-frequency motion, no roughness, no shoreline foam.",
        "water": {
            "normalScale": setv(0.0),
            "preferLowFreq": setv(True),
            "roughness": setv(0.0),
            "waveFoamTex": setv(""),
        },
    },
    {
        "key": "clear",
        "name": "Crystal clear",
        "intent": "Clear water you see the bottom through: a sixth to a twelfth of the extinction (0.008), half the "
        "waves, the low-frequency motion and little roughness. Best over shallow coasts and rivers.",
        "water": {
            "extinctionCoeff": setv(0.008),
            "normalScale": mul(0.5),
            "preferLowFreq": setv(True),
            "roughness": setv(0.1),
        },
    },
    {
        "key": "wild",
        "name": "Wild water",
        "intent": "Churning white water for rivers and rapids, a boiling sea: wave normals at 6 (the shader scales "
        "them down in shallow water, so a river gets what a stormy sea has), high-frequency motion, half roughness "
        "so the broken surface still glitters, shoreline foam, near-opaque, stirred-up water (eight times the "
        "extinction) and, under overcast, a harder, darker picture (round 11's Stormy sea).",
        "water": {
            "normalScale": setv(6.0),
            "preferLowFreq": setv(False),
            "roughness": setv(0.6),
            "waveFoamTex": setv(FOAM),
            "extinctionCoeff": mul(8.0),
        },
        "light": {
            "hdrContrastOvercast": setv(1.4),
            "hdrExposureOvercast": setv(0.75),
        },
    },
    {
        # Round 15. The water's colour is a texture: depthColorTex, a 64 x 16 gradient from shallow (white) to deep
        # (climates.zip: dry and temperate (subarctic uses temperate's) run through teal-green, #6ad6b4 -> #183029;
        # tropical through cyan-blue, #7beef6 -> #081c29). Tropical's gradient with clearer water gives every climate
        # the turquoise of a tropical coast; on the Tropical map it is its own colour, only clearer.
        "key": "turquoise",
        "name": "Tropical turquoise",
        "intent": "Turquoise water: the tropical climate's depth colours (cyan to deep blue instead of teal-green), "
        "clearer than the climates' own (extinction 0.02) with a little less roughness.",
        "water": {
            "depthColorTex": setv("::/climates/tropical/depthColor.dds"),
            "extinctionCoeff": setv(0.02),
            "roughness": setv(0.3),
        },
    },
]

SECTIONS = ("atmosphere", "light", "water")
LAYERS = (("sky", SKY), ("haze", HAZE), ("water", WATER))
ORIG_LOOK = {"key": ORIG, "name": "Original", "intent": ""}

TEXTURE_KEYS = {"fileName", "depthColorTex", "normalTex", "waveFoamTex"}


def fields(look: dict) -> set[tuple[str, str]]:
    return {(s, k) for s in SECTIONS for k in look.get(s, {})}


def check_layers() -> None:
    """The layers change disjoint fields, so a combination is each layer's changes in turn."""
    owner: dict[tuple[str, str], str] = {}
    for layer, looks in LAYERS:
        for look in looks:
            for f in fields(look):
                if owner.setdefault(f, layer) != layer:
                    raise SystemExit(f"layers {owner[f]} and {layer} change the same field {f} ({look['key']})")
    keys = [ORIG] + [x["key"] for __, looks in LAYERS for x in looks]
    if len(set(keys)) != len(keys):
        raise SystemExit("duplicate look keys")


def load_env(lua, path: Path):
    code = path.read_text(encoding="utf-8")
    fn = lua.execute("local _ = function(s) return s end\n" + code + "\nreturn data")
    return to_py(fn())


def to_py(v):
    if hasattr(v, "keys") and hasattr(v, "values"):  # a Lua table
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [to_py(v[i]) for i in range(1, len(keys) + 1)]
        if not keys:
            return {}
        return {str(k): to_py(v[k]) for k in keys}
    return v


def abs_texture(name: str, climate: str) -> str:
    if name == "" or name.startswith("::") or ":" in name:
        return name
    if name.startswith("/"):
        return "::" + name
    return f"::/climates/{climate}/{name}"


def fix_textures(t, climate: str):
    if isinstance(t, dict):
        for k, v in t.items():
            if k in TEXTURE_KEYS and isinstance(v, str):
                t[k] = abs_texture(v, climate)
            else:
                fix_textures(v, climate)
    elif isinstance(t, list):
        for v in t:
            fix_textures(v, climate)


def apply_changes(out: dict, look: dict, climate: str, label: str) -> None:
    for section in SECTIONS:
        for key, (op, val) in look.get(section, {}).items():
            sec = out[section]
            if op == "set":
                sec[key] = copy.deepcopy(val)
            elif op == "mul":
                sec[key] = round(sec[key] * val, 6)
            elif op == "contrast":
                c = list(sec[key])
                c[0] = round(c[0] + val, 6)
                sec[key] = c
            else:
                raise ValueError(op)
            v = sec[key][0] if op == "contrast" else sec[key]
            check_range(section, key, v, label, climate)


def apply_looks(env: dict, combo: tuple[dict, ...], climate: str) -> dict:
    out = copy.deepcopy(env)
    fix_textures(out, climate)
    for look in combo:
        apply_changes(out, look, climate, look["key"])
    names = " + ".join(look["name"] for look in combo)
    out["name"] = f"Photo Mode look: {names} ({CLIMATE_NAMES[climate]})"
    out["isToolEnvironment"] = True
    return out


def check_range(section, key, value, look, climate):
    r = RANGES.get((section, key))
    if r is None or not isinstance(value, (int, float)) or isinstance(value, bool):
        return
    lo, hi = r
    if not lo <= value <= hi:
        raise SystemExit(f"{look} ({climate}): {section}.{key} = {value} outside {lo}..{hi}")


def lua_value(v, indent: str) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        if v == int(v) and abs(v) < 1e15:
            return f"{v:.1f}"
        return repr(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        return "{ " + ", ".join(lua_value(x, indent) for x in v) + " }"
    if isinstance(v, dict):
        inner = indent + "\t"
        lines = [f"{inner}{k} = {lua_value(v[k], inner)}," for k in sorted(v)]
        return "{\n" + "\n".join(lines) + f"\n{indent}}}"
    raise TypeError(type(v))


def change_lines(look: dict) -> list[str]:
    out = []
    for section in SECTIONS:
        for key, (op, val) in look.get(section, {}).items():
            if op == "contrast":
                what = f"[1] {val:+}"
            elif op == "mul":
                what = f"x {val}"
            else:
                what = "= " + lua_value(val, "")
            out.append(f"--   {section}.{key} {what}")
    return out


def render(env: dict, combo: tuple[dict, ...], climate: str) -> str:
    what = " + ".join(f"\"{look['name']}\" {layer}" for (layer, __), look in zip(LAYERS, combo))
    head = [
        f"-- Photo Mode look {what} for the {CLIMATE_NAMES[climate]} climate.",
        f"-- GENERATED by tools/gen_photo_looks.py from base climates/{climate}/{climate}.env.lua: do not edit, "
        "rerun the tool.",
    ]
    for (layer, __), look in zip(LAYERS, combo):
        kind = layer.capitalize()
        if look["key"] == ORIG:
            head.append(f"-- {kind}: the climate's own.")
            continue
        # round 15: the intent stays in this generator (and LOOKS.md), not in each of the 1076 files (-0.9 MB)
        head.append(f"-- {kind} \"{look['name']}\", changes from the base climate (intent: tools/gen_photo_looks.py):")
        head += change_lines(look)
    head.append("-- Switched to for rendering only (api.gui.rendering.setEnvironment); plans/square_photo_mode/LOOKS.md.")
    order = ["atmosphere", "light", "name", "isToolEnvironment", "shadows", "skyBox", "useSkyBoxOverwrite", "water"]
    keys = order + sorted(k for k in env if k not in order)
    body = [f"\t\t{k} = {lua_value(env[k], chr(9) * 2)}," for k in keys if k in env]
    # the name is an id (a tool environment never shows it; our window names the looks itself)
    body = [b + " -- i18n: ignore" if b.startswith("\t\tname = ") else b for b in body]
    return "\n".join(head) + "\nfunction data()\n\treturn {\n" + "\n".join(body) + "\n\t}\nend\n"


def combos():
    """Every sky x haze x water combination but all three originals (the climate itself)."""
    for combo in itertools.product(*([ORIG_LOOK] + looks for __, looks in LAYERS)):
        if any(look["key"] != ORIG for look in combo):
            yield combo


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="only compare; exit 1 on a difference")
    args = ap.parse_args()
    check_layers()
    base = GAME_CACHE_DIR / "base" / "content" / "climates"
    if not base.is_dir():
        raise SystemExit(f"{base} missing: run `make docs` first")
    lua = LuaRuntime(unpack_returned_tuples=True)
    want: dict[Path, str] = {}
    for climate in CLIMATES:
        env = load_env(lua, base / climate / f"{climate}.env.lua")
        for combo in combos():
            stem = "_".join(look["key"] for look in combo)
            path = OUT_DIR / f"{PREFIX}{climate}_{stem}.env.lua"
            want[path] = render(apply_looks(env, combo, climate), combo, climate)
    stale = [p for p in OUT_DIR.glob(f"{PREFIX}*.env.lua") if p not in want] if OUT_DIR.is_dir() else []
    if args.check:
        bad = [p for p, text in want.items() if not p.is_file() or p.read_text(encoding="utf-8") != text]
        for p in bad + stale:
            print(f"differs: {p.relative_to(ROOT)}")
        print(f"{len(want)} look files, {len(bad) + len(stale)} differ")
        return 1 if bad or stale else 0
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    n = 0
    for p, text in want.items():
        if not p.is_file() or p.read_text(encoding="utf-8") != text:
            p.write_text(text, encoding="utf-8")
            n += 1
    for p in stale:
        p.unlink()
    size = sum(len(t.encode()) for t in want.values())
    print(
        f"{len(want)} look files ({len(CLIMATES)} climates x ({len(SKY) + 1} skies x {len(HAZE) + 1} hazes x "
        f"{len(WATER) + 1} waters - 1)), "
        f"{size // 1024} KB, {n} written, {len(stale)} removed"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
