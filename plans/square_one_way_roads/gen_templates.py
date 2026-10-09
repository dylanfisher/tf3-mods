"""Generate the one-way street templates for square_one_way_roads.

Each template is the vanilla two-way template with every car lane set to
forward = true, the same changes the base game makes for its own one-way
roads: cheaper (2/3 cost and maintenance), lower junction priority, not
simBuildable (towns never build them) and a separate menu order.

Run: uv run plans/square_one_way_roads/gen_templates.py
"""

import gettext
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / ".cache/game/base/content/infrastructure/street"
MOD = ROOT / "mods/square_one_way_roads"
OUT = MOD / "content/infrastructure/street/square_one_way"

# source template -> English name, in the base game's style ("Small One-Way Street"). Old and
# new versions share a name like the base roads do: they are never in the menu at the same time.
ROADS = {
    "town/town_old_xsmall": "Narrow One-Way Street",
    "town/town_old_small": "Small One-Way Street",
    "town/town_old_medium": "Medium One-Way Street",
    "town/town_old_large": "Large One-Way Street",
    "town/town_new_large": "Large One-Way Street",
    "country/country_old_small": "Small One-Way Country Road",
    "country/country_old_medium": "Medium One-Way Country Road",
    "country/country_old_large": "Large One-Way Country Road",
    "country/country_new_small": "Small One-Way Country Road",
    "country/country_new_medium": "Medium One-Way Country Road",
    "country/country_new_large": "Large One-Way Country Road",
}

# English descriptions of the two-way roads (base/strings/en/LC_MESSAGES/base.mo). The one-way
# text inserts ", one-way" after the lane count, as the base one-way descriptions do.
def base_descriptions() -> dict[str, str]:
    with open(Path.home() / "Library/Application Support/Steam/steamapps/common/Transport Fever 3/base/strings/en/LC_MESSAGES/base.mo", "rb") as f:
        return gettext.GNUTranslations(f)._catalog


def one_way_desc(two_way: str) -> str:
    out, n = re.subn(r"^((?:Narrow )?\w+-lane)( |,)", lambda m: f"{m.group(1)}, one-way{m.group(2)}", two_way, count=1)
    assert n == 1, two_way
    return out.replace("one-way,", "one-way")


LANE = re.compile(r"\{\s*\n\s*forward = (?:true|false),(.*?)\n\t\t\t\},", re.S)


def flip_lanes(text: str) -> str:
    def sub(m: re.Match) -> str:
        block = m.group(0)
        if '"CAR"' in block:
            block = block.replace("forward = false,", "forward = true,", 1)
        return block

    out, n = LANE.subn(sub, text)
    assert n >= 4, f"expected lane blocks, found {n}"
    return out


def replace_int(text: str, key: str, fn) -> str:
    pat = re.compile(rf"(\n\t+{key} = )(\d+)(,)")
    out, n = pat.subn(lambda m: f"{m.group(1)}{fn(int(m.group(2)))}{m.group(3)}", text)
    assert n == 1, f"{key}: {n} matches"
    return out


def build(src: str, slug: str) -> str:
    text = (BASE / f"{src}.street_template.lua").read_text()
    country = "country = true" in text
    key = f"SQUARE_OWR_{slug.upper()}"
    text = flip_lanes(text)
    text = replace_int(text, "cost", lambda v: round(v * 2 / 3))
    text = replace_int(text, "maintenanceCost", lambda v: round(v * 2 / 3))
    # Vanilla one-way town roads sit 200 below their twin; country priorities
    # are only 100-260, so stay just below the twin there.
    text = replace_int(text, "priority", lambda v: v - (5 if country else 200))
    text = replace_int(text, "order", lambda v: v + 5)
    text = re.sub(r"\n\t+simBuildable = true,", "", text)
    text = re.sub(r"(\n\t+)(notificationSortKey|NotificationSortKey) = \d+,", "", text)
    text = re.sub(r"_\(\"STREET_[A-Z_]+_NAME\"\)", f'_("{key}_NAME")', text)
    text = re.sub(r"_\(\"STREET_[A-Z_]+_DESC\"\)", f'_("{key}_DESC")', text)
    # Icon with the one-way arrow: tools/render_icon_square_one_way_roads.py (the game picks @2x).
    text, n = re.subn(r'(\n\t+icon = )"[^"]+"', rf'\1"{slug}.tga"', text)
    assert n == 1, src
    # The availability years stay the twin's. Every twin that unlocks later
    # than year 0 already has notifyWhenAvailable = false.
    assert "yearFrom = 0," in text or "notifyWhenAvailable = false" in text, src
    lanes = [m.group(0) for m in LANE.finditer(text)]
    assert all("forward = true," in b for b in lanes if '"CAR"' in b), src
    return text


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    strings = {}
    catalog = base_descriptions()
    for src, name in ROADS.items():
        slug = "one_way_" + src.split("/")[1]
        (OUT / f"{slug}.street_template.lua").write_text(build(src, slug))
        key = f"SQUARE_OWR_{slug.upper()}"
        strings[f"{key}_NAME"] = name
        two_way_key = "STREET_" + src.split("/")[1].upper() + "_DESC"
        strings[f"{key}_DESC"] = one_way_desc(catalog[two_way_key])
        print(f"{slug}.street_template.lua")
    (MOD / "strings.json").write_text(json.dumps({"en": strings}, indent=4) + "\n")


if __name__ == "__main__":
    main()
