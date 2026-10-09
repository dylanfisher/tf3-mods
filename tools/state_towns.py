# /// script
# requires-python = ">=3.11"
# ///
"""Draft data/states/<key>/towns.tsv from US Census files (public domain).

Usage:
  uv run tools/state_towns.py us_washington            write data/states/us_washington/towns.tsv
  uv run tools/state_towns.py us_washington --fetch    download the Census files first (curl)
  uv run tools/state_towns.py us_washington --stdout   print instead of writing
  uv run tools/state_towns.py us_alaska --config /tmp/ak.json   dry run of another config (prints, writes nothing)

Inputs (each downloaded file sits in its own directory under .cache/census/, and is only ever read
as data; nothing from there is imported or executed):
  .cache/census/gaz<Y>_place_<fips>/gaz.txt           Gazetteer places: name + LSAD, internal point
  .cache/census/popest<Y>_<fips>/sub-est<Y>_<fips>.csv population estimates (incorporated places)
  .cache/census/gaz2010_places_extracted/gaz2010_<postal>.txt   2010 Gazetteer rows of the state
                                                      (POP10, the only population source for CDPs)
The 2010 national zip is extracted by --fetch with Python's zipfile (no shell unzip).

All hand decisions live in data/states/<key>/towns_config.json (region rules, tag overrides, CDP
filters), so re-running the tool reproduces towns.tsv exactly. Edit the config, not the TSV.

Optional county data (only when the config has countyTags; fetched by --fetch, read as data only):
  .cache/census/placecou2020_<fips>/place_by_county.txt   2020 place-by-county codes (county names)
  .cache/census/baf2020_<fips>/BlockAssign_ST<fips>_<postal>.zip   2020 block assignment file
A place belongs to the county holding most of its 2020 blocks (the block IDs start with the county
code). The Census 2020 place-to-county relationship file with land areas isn't published (rel2020/place
only has place20-place10), so the block count stands in for the largest land part.

Tags, in this order (the first one is the town's "side", which rules can test):
  side     setSide override, else the crest side ("west"/"east": west or east of the crest polyline by
           latitude), else the first `regions` polygon containing the town, else `defaultTag`
  region   with both `crest` and `regions`: the region polygon tag (or defaultTag) as a second tag
  rules    {tag, side?, lonLt?, lonGe?, latLt?, latGe?}: every condition must hold
  county   countyTags {tag: [county names]} ("Monroe" or "Monroe County")
  lists    tagLists (hand lists), then "big" for the bigCount most populous incorporated places
           (all places with bigIncludesCdp), minus removeTags.
regions is an ordered list of {tag, polygon: [[lat, lon], ...]}; the first match wins. When the config
has regions, regions.geojson (polygons + towns) is written next to towns.tsv for a map check
(geojson.io).
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import subprocess
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import CACHE_DIR, ROOT  # noqa: E402

DATA_DIR = ROOT / "data" / "states"
CENSUS = CACHE_DIR / "census"

# Legal/statistical area suffixes of Gazetteer names, longest first (" city and borough" before " borough").
LSAD_SUFFIXES = tuple(sorted((
    " city and borough", " consolidated government", " unified government", " metropolitan government",
    " metro government", " urban county", " municipality", " borough", " village", " city", " town", " CDP",
), key=len, reverse=True))
BALANCE = " (balance)"
COUNTY_SUFFIXES = (" City and Borough", " Census Area", " Municipality", " Borough", " County", " Parish", " city")


def fetch(cfg: dict) -> None:
    """Download the Census files with curl into their own empty directories."""
    fips, postal = cfg["fips"], cfg["postal"]
    y_gaz, y_pop = cfg["gazetteerYear"], cfg["popestYear"]
    jobs = [
        (CENSUS / f"gaz{y_gaz}_place_{fips}" / "gaz.txt",
         f"https://www2.census.gov/geo/docs/maps-data/data/gazetteer/{y_gaz}_Gazetteer/{y_gaz}_gaz_place_{fips}.txt"),
        (CENSUS / f"popest{y_pop}_{fips}" / f"sub-est{y_pop}_{fips}.csv",
         # The remote name has no leading zero (sub-est2023_2.csv for Alaska, 02).
         f"https://www2.census.gov/programs-surveys/popest/datasets/2020-{y_pop}/cities/totals/sub-est{y_pop}_{int(fips)}.csv"),
        (CENSUS / "gaz2010_places" / "Gaz_places_national.zip",
         "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/Gaz_places_national.zip"),
    ]
    if cfg.get("countyTags"):
        jobs += [
            (CENSUS / f"placecou2020_{fips}" / "place_by_county.txt",
             "https://www2.census.gov/geo/docs/reference/codes2020/place_by_cou/"
             f"st{fips}_{postal.lower()}_place_by_county2020.txt"),
            (CENSUS / f"baf2020_{fips}" / f"BlockAssign_ST{fips}_{postal}.zip",
             f"https://www2.census.gov/geo/docs/maps-data/data/baf2020/BlockAssign_ST{fips}_{postal}.zip"),
        ]
    for dest, url in jobs:
        if dest.exists():
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["curl", "-sSfL", "-m", "120", "-o", str(dest), url], check=True)
    out = CENSUS / "gaz2010_places_extracted" / f"gaz2010_{postal.lower()}.txt"
    if not out.exists():
        with zipfile.ZipFile(CENSUS / "gaz2010_places" / "Gaz_places_national.zip") as z:
            text = z.read(z.namelist()[0]).decode("latin-1")
        lines = text.splitlines()
        keep = [lines[0]] + [ln for ln in lines[1:] if ln.startswith(postal + "\t")]
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("\n".join(keep) + "\n", encoding="utf-8")


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8") as fh:
        return [{k.strip(): (v or "").strip() for k, v in row.items()} for row in csv.DictReader(fh, delimiter="\t")]


def strip_lsad(name: str) -> tuple[str, str]:
    """("Juneau city and borough") -> ("Juneau", "city and borough"). " (balance)" goes first; a balance name
    without a suffix ("Butte-Silver Bow (balance)") is kind "balance"; anything else unknown is kind "?"."""
    balance = name.endswith(BALANCE)
    if balance:
        name = name[: -len(BALANCE)]
    for suf in LSAD_SUFFIXES:
        if name.endswith(suf) and len(name) > len(suf):
            return name[: -len(suf)], suf.strip()
    return name, "balance" if balance else "?"


def point_in_polygon(lat: float, lon: float, poly: list[list[float]]) -> bool:
    """Ray casting on [lat, lon] vertices (open or closed ring)."""
    inside = False
    n = len(poly)
    for i in range(n):
        (la0, lo0), (la1, lo1) = poly[i - 1], poly[i]
        if (la0 > lat) != (la1 > lat):
            cross = lo0 + (lat - la0) / (la1 - la0) * (lo1 - lo0)
            if lon < cross:
                inside = not inside
    return inside


def region_of(lat: float, lon: float, regions: list[dict], default: str | None) -> str | None:
    for r in regions:
        if point_in_polygon(lat, lon, r["polygon"]):
            return r["tag"]
    return default


def rule_matches(rule: dict, side: str, lat: float, lon: float) -> bool:
    if "side" in rule and rule["side"] != side:
        return False
    if "lonLt" in rule and not lon < rule["lonLt"]:
        return False
    if "lonGe" in rule and not lon >= rule["lonGe"]:
        return False
    if "latLt" in rule and not lat < rule["latLt"]:
        return False
    if "latGe" in rule and not lat >= rule["latGe"]:
        return False
    return True


def county_key(name: str) -> str:
    """ "Monroe County" -> "monroe"; "Juneau City and Borough" -> "juneau" (config may name either form)."""
    for suf in COUNTY_SUFFIXES:
        if name.endswith(suf) and len(name) > len(suf):
            return name[: -len(suf)].lower()
    return name.lower()


def place_counties(by_county_rows: list[dict[str, str]], baf_lines: list[str]) -> dict[str, str]:
    """5-digit place code -> county name: the county with most of the place's 2020 blocks; places missing
    from the block file fall back to their first county in the place-by-county list."""
    names = {r["COUNTYFP"]: r["COUNTYNAME"] for r in by_county_rows}
    counts: dict[str, dict[str, int]] = {}
    for ln in baf_lines[1:]:
        block, _, place = ln.strip().partition("|")
        if place:
            c = counts.setdefault(place, {})
            c[block[2:5]] = c.get(block[2:5], 0) + 1
    out = {p: names.get(max(sorted(c), key=lambda k: c[k]), "") for p, c in counts.items()}
    for r in by_county_rows:
        out.setdefault(r["PLACEFP"], r["COUNTYNAME"])
    return out


def load_counties(cfg: dict) -> dict[str, str]:
    fips, postal = cfg["fips"], cfg["postal"]
    with (CENSUS / f"placecou2020_{fips}" / "place_by_county.txt").open(encoding="utf-8") as fh:
        rows = [{k: (v or "").strip() for k, v in r.items()} for r in csv.DictReader(fh, delimiter="|")]
    with zipfile.ZipFile(CENSUS / f"baf2020_{fips}" / f"BlockAssign_ST{fips}_{postal}.zip") as z:
        member = next(m for m in z.namelist() if m.endswith("_INCPLACE_CDP.txt"))
        lines = z.read(member).decode("utf-8").splitlines()
    return place_counties(rows, lines)


def crest_lon(crest: list[list[float]], lat: float) -> float:
    """Longitude of the crest at a latitude (piecewise linear, clamped at the ends)."""
    pts = sorted(crest)
    if lat <= pts[0][0]:
        return pts[0][1]
    if lat >= pts[-1][0]:
        return pts[-1][1]
    for (la0, lo0), (la1, lo1) in zip(pts, pts[1:]):
        if la0 <= lat <= la1:
            t = (lat - la0) / (la1 - la0) if la1 != la0 else 0
            return lo0 + t * (lo1 - lo0)
    return pts[-1][1]


def to_tsv(rows: list[dict]) -> str:
    lines = ["name\ttags\tpopulation\tlat\tlon\tnote"]
    for t in rows:
        lines.append(f"{t['name']}\t{','.join(t['tags'])}\t{t['pop']}\t{t['lat']:.4f}\t{t['lon']:.4f}\t{t['note']}")
    return "\n".join(lines) + "\n"


def inc_floor(cfg: dict, inc_min, name: str, lat: float, lon: float) -> int:
    """The incMinPop (or cdpMinPop) floor that applies to one place (see draft_rows)."""
    if not isinstance(inc_min, dict):
        return int(inc_min)
    tag = cfg.get("setSide", {}).get(name)
    if tag is None:
        tag = region_of(lat, lon, cfg.get("regions") or [], cfg.get("defaultTag"))
    if tag is None and cfg.get("crest"):
        tag = "west" if lon < crest_lon(cfg["crest"], lat) else "east"
    return int(inc_min.get(tag, 0))


def draft_rows(key: str, cfg: dict | None = None) -> tuple[list[dict], list[str]]:
    if cfg is None:
        cfg = json.loads((DATA_DIR / key / "towns_config.json").read_text(encoding="utf-8"))
    fips, postal = cfg["fips"], cfg["postal"]
    gaz = read_tsv(CENSUS / f"gaz{cfg['gazetteerYear']}_place_{fips}" / "gaz.txt")
    pop_rows = list(csv.DictReader(io.StringIO(
        (CENSUS / f"popest{cfg['popestYear']}_{fips}" / f"sub-est{cfg['popestYear']}_{fips}.csv").read_text(encoding="latin-1"))))
    pop_col = f"POPESTIMATE{cfg['popestYear']}"
    # Incorporated places (SUMLEV 162), keyed by the 5-digit place code (some state files drop the zeros).
    popest = {r["PLACE"].zfill(5): int(r[pop_col]) for r in pop_rows if r["SUMLEV"] == "162"}
    g10 = {r["GEOID"]: int(r["POP10"]) for r in read_tsv(CENSUS / "gaz2010_places_extracted" / f"gaz2010_{postal.lower()}.txt")}

    excl = set(cfg.get("excludeCdp", []))
    keep = set(cfg.get("keepCdp", []))
    # incMinPop: a population floor for incorporated places, as one number or as {regionTag: floor} (the tag
    # is setSide, else the first matching region polygon or defaultTag, else the crest side; tags not listed
    # have no floor). keepTown names are exempt. For states with too many small incorporated places (Texas).
    # cdpMinPop takes the same two forms (a number or {regionTag: floor}; unlisted tags have no floor).
    inc_min = cfg.get("incMinPop", 0)
    keep_town = set(cfg.get("keepTown", []))
    drop_words = set(cfg.get("dropCdpWords", []))
    exclude_all = set(cfg.get("exclude", []))
    rename = cfg.get("rename", {})
    # renameGeoid: {"<7-digit GEOID>": "Name"}, applied before rename and the LSAD check. For two places that
    # share one Census name (Hawaii's two "Kailua" CDPs: the Big Island one is known as Kailua-Kona).
    # keepCdp/excludeCdp and the hyphen/drop-word filter see the new name.
    rename_geoid = cfg.get("renameGeoid", {})
    add_tags: dict[str, list[str]] = {}
    for tag, names in cfg.get("tagLists", {}).items():
        for n in names:
            add_tags.setdefault(n, []).append(tag)
    remove_tags = cfg.get("removeTags", {})
    set_side = cfg.get("setSide", {})
    county_tags: dict[str, list[str]] = {}
    for tag, names in cfg.get("countyTags", {}).items():
        for n in names:
            county_tags.setdefault(county_key(n), []).append(tag)
    counties = load_counties(cfg) if county_tags else {}
    warnings: list[str] = []

    towns: dict[str, dict] = {}
    for r in gaz:
        full = r["NAME"]
        name, kind = strip_lsad(full)
        if r["GEOID"] in rename_geoid:
            name = rename_geoid[r["GEOID"]]
        elif kind == "?" and name not in rename:
            warnings.append(f"unknown LSAD suffix (add a rename to accept the name as is): {full}")
        name = rename.get(name, name)
        if name in exclude_all:
            continue
        place = r["GEOID"][-5:]
        lat, lon = float(r["INTPTLAT"]), float(r["INTPTLONG"])
        if kind == "CDP":
            pop = g10.get(r["GEOID"], -1)
            if name not in keep:
                if name in excl or "-" in name or any(w in drop_words for w in name.split()):
                    continue
                if pop < inc_floor(cfg, cfg["cdpMinPop"], name, lat, lon):
                    continue
            note = f"CDP pop2010={pop}" if pop >= 0 else "CDP pop n/a"
            pop = max(pop, 0)
        else:
            pop = popest.get(place)
            if pop is None:
                warnings.append(f"no population estimate for {full}")
                pop = 0
            if inc_min and name not in keep_town and pop < inc_floor(cfg, inc_min, name, lat, lon):
                continue
            note = f"{kind} est{cfg['popestYear']}"
        key_n = name.lower()
        if key_n in {t.lower() for t in towns}:
            prev = towns[next(t for t in towns if t.lower() == key_n)]
            if prev["pop"] >= pop:
                continue  # keep the bigger of two same-named places
            del towns[prev["name"]]
        if len(name.encode("utf-8")) > 40:
            warnings.append(f"name longer than 40 bytes, skipped: {name}")
            continue
        towns[name] = {"name": name, "pop": pop, "lat": lat, "lon": lon, "note": note, "incorporated": kind != "CDP",
                       "county": counties.get(place, "")}

    seen_geoids = {r["GEOID"] for r in gaz}
    for g in rename_geoid:
        if g not in seen_geoids:
            warnings.append(f"renameGeoid names a GEOID that is not in the Gazetteer: {g}")
    for n in list(add_tags) + list(remove_tags) + list(set_side) + list(keep) + list(keep_town):
        if n not in towns:
            warnings.append(f"config names a town that is not in the draft: {n}")
    known_counties = {county_key(c) for c in counties.values() if c}
    for ck in county_tags:
        if ck not in known_counties:
            warnings.append(f"countyTags names a county with no place in it: {ck}")
    if county_tags:
        missing = sorted(t["name"] for t in towns.values() if not t["county"])
        if missing:
            warnings.append(f"{len(missing)} places not in the 2020 county files (no county tag): " + ", ".join(missing[:12])
                            + (" ..." if len(missing) > 12 else ""))

    crest, regions, default_tag = cfg.get("crest"), cfg.get("regions") or [], cfg.get("defaultTag")
    if not crest and not regions and not default_tag:
        raise SystemExit("towns_config.json: needs crest, regions or defaultTag")
    pool = towns.values() if cfg.get("bigIncludesCdp") else (t for t in towns.values() if t["incorporated"])
    big = sorted(pool, key=lambda t: -t["pop"])[: cfg["bigCount"]]
    big_names = {t["name"] for t in big}
    for t in towns.values():
        tags: list[str] = []
        region = region_of(t["lat"], t["lon"], regions, default_tag)
        side = set_side.get(t["name"])
        if side is None:
            if crest:
                side = "west" if t["lon"] < crest_lon(crest, t["lat"]) else "east"
            else:
                side = region
        if side:
            tags.append(side)
        if crest and region:
            tags.append(region)
        for rule in cfg.get("rules", []):
            if rule_matches(rule, side, t["lat"], t["lon"]):
                tags.append(rule["tag"])
        tags += county_tags.get(county_key(t["county"]), []) if t["county"] else []
        tags += add_tags.get(t["name"], [])
        if t["name"] in big_names:
            tags.append("big")
        drop = set(remove_tags.get(t["name"], []))
        out: list[str] = []
        for tag in tags:
            if tag not in out and tag not in drop:
                out.append(tag)
        if not out:
            warnings.append(f"no tags (outside every region and no defaultTag): {t['name']}")
        t["tags"] = out

    return sorted(towns.values(), key=lambda t: (-t["pop"], t["name"])), warnings


def geojson(cfg: dict, rows: list[dict]) -> str:
    """Region polygons + one point per town (simplestyle colours by first tag), for geojson.io."""
    palette = ["#e6194b", "#3cb44b", "#4363d8", "#f58231", "#911eb4", "#46f0f0", "#f032e6", "#bcf60c", "#008080",
               "#9a6324", "#800000", "#000075"]
    tags = [r["tag"] for r in cfg.get("regions") or []]
    if cfg.get("defaultTag"):
        tags.append(cfg["defaultTag"])
    colour = {}
    for t in tags + sorted({x for r in rows for x in r["tags"][:1]}):
        colour.setdefault(t, palette[len(colour) % len(palette)])
    feats = []
    for r in cfg.get("regions") or []:
        ring = [[lon, lat] for lat, lon in r["polygon"]]
        if ring[0] != ring[-1]:
            ring.append(ring[0])
        feats.append({"type": "Feature", "properties": {"tag": r["tag"], "stroke": colour[r["tag"]], "fill": colour[r["tag"]],
                                                        "fill-opacity": 0.15},
                      "geometry": {"type": "Polygon", "coordinates": [ring]}})
    for t in rows:
        first = t["tags"][0] if t["tags"] else ""
        feats.append({"type": "Feature", "properties": {"name": t["name"], "tags": ",".join(t["tags"]), "population": t["pop"],
                                                        "county": t.get("county", ""), "marker-size": "small",
                                                        "marker-color": colour.get(first, "#888888")},
                      "geometry": {"type": "Point", "coordinates": [round(t["lon"], 4), round(t["lat"], 4)]}})
    return json.dumps({"type": "FeatureCollection", "features": feats}, ensure_ascii=False) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("state", help="state key, e.g. us_washington")
    ap.add_argument("--fetch", action="store_true", help="download missing Census files first")
    ap.add_argument("--stdout", action="store_true", help="print the TSV instead of writing it")
    ap.add_argument("--config", type=Path, help="read this towns_config.json instead (dry runs; implies --stdout)")
    args = ap.parse_args()
    cfg_path = args.config or DATA_DIR / args.state / "towns_config.json"
    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    if args.fetch:
        fetch(cfg)
    rows, warnings = draft_rows(args.state, cfg)
    text = to_tsv(rows)
    for w in warnings:
        print(f"warn: {w}", file=sys.stderr)
    counts: dict[str, int] = {}
    for t in rows:
        for tag in t["tags"]:
            counts[tag] = counts.get(tag, 0) + 1
    summary = f"{len(rows)} towns; tags " + ", ".join(f"{k}={v}" for k, v in sorted(counts.items()))
    if args.stdout or args.config:
        sys.stdout.write(text)
        print(summary, file=sys.stderr)
        return
    out = DATA_DIR / args.state / "towns.tsv"
    out.write_text(text, encoding="utf-8")
    msg = f"wrote {out.relative_to(ROOT)}: {summary}"
    if cfg.get("regions"):
        gj = DATA_DIR / args.state / "regions.geojson"
        gj.write_text(geojson(cfg, rows), encoding="utf-8")
        msg += f"\nwrote {gj.relative_to(ROOT)} (paste into geojson.io to check the regions)"
    print(msg)


if __name__ == "__main__":
    main()
