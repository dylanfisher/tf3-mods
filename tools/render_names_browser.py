# /// script
# requires-python = ">=3.11"
# dependencies = ["lupa"]
# ///
"""Render a browsable HTML page of every US State Names data set (towns, city streets, stations, generic streets).

Usage:
  uv run tools/render_names_browser.py            write plans/square_state_names/names_browser.html
  (make names-browser)

Reads data/states/*/ the same way tools/gen_state_mod.py does and shows names in their shipped form (ASCII when the
state sets asciiFallback). The page template is templates/names_browser.html; the data goes in as one JSON blob.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from gen_state_mod import KINDS, load_lua, read_towns, to_ascii  # noqa: E402
from hubconfig import ROOT  # noqa: E402

DATA_DIR = ROOT / "data" / "states"
TEMPLATE = ROOT / "templates" / "names_browser.html"
OUT = ROOT / "plans" / "square_state_names" / "names_browser.html"


def state_entry(key: str) -> dict:
    src = DATA_DIR / key
    state = load_lua(src / "state.lua")
    fix = to_ascii if state.get("asciiFallback") else (lambda s: s)
    towns = read_towns(src / "towns.tsv")
    cities = load_lua(src / "cities.lua") or {}
    streets = load_lua(src / "streets.lua") or []
    pop = {t["n"]: t["p"] for t in towns}
    city_rows = []
    for name, entry in cities.items():
        row = {"n": fix(name), "p": pop.get(name, 0)}
        for kind in KINDS + ("aliases",):
            vals = entry.get(kind) or []
            if vals:
                row[kind] = [fix(v) for v in vals]
        city_rows.append(row)
    city_rows.sort(key=lambda c: -c["p"])
    return {
        "key": key,
        "name": state["name"],
        "postal": state.get("postal", ""),
        "mod": state.get("modName", ""),
        "modId": "square_names_us_" + key.removeprefix("us_"),
        "accent": state.get("accent", "#1f6b4a"),
        "labels": state.get("regionLabels") or {},
        "towns": [{"n": fix(t["n"]), "t": t["t"], "p": t["p"]} for t in towns],
        "cities": city_rows,
        "streets": [fix(s) for s in streets],
    }


def main() -> None:
    keys = sorted(p.name for p in DATA_DIR.iterdir() if (p / "state.lua").exists())
    states = sorted((state_entry(k) for k in keys), key=lambda s: s["name"])
    blob = json.dumps(states, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    html = TEMPLATE.read_text(encoding="utf-8").replace("/*DATA*/[]", blob)
    OUT.write_text(html, encoding="utf-8")
    towns = sum(len(s["towns"]) for s in states)
    streets = sum(len(c.get("streets", [])) for s in states for c in s["cities"])
    print(f"wrote {OUT.relative_to(ROOT)}: {len(states)} states, {towns} towns, {streets} city streets, "
          f"{len(html) // 1024} KB")


if __name__ == "__main__":
    main()
