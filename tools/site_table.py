# /// script
# requires-python = ">=3.11"
# ///
"""CSV result tables -> data files for the mod site's generic "data-explorer" kind (site/, data version 1).

Each input CSV becomes <out>/<csv stem with "_" as "-">.json: column-oriented, categorical columns
dictionary-encoded, so a 20,000-row probe table stays a few hundred KB. Data only: the site's section source
(the mod's manifest) holds every label, sentence and which columns to show.

  {
    "version": 1,
    "source": "probe_p5_all.csv",          # file name only, never a local path
    "modified": "2026-10-08",              # the CSV's modification date (the run's date)
    "rows": 1970,
    "constant": { "tram": "off" },         # columns with one value in every row (dropped from "columns")
    "columns": [
      { "key": "entry", "type": "cat", "values": ["channel", "interchange", "main"], "data": [0, 2, ...] },
      { "key": "ms", "type": "num", "data": [5, 6, null, ...] },
      { "key": "label", "type": "text", "data": ["radius=20", null, ...] }
    ]
  }

Column types: "num" for the --num columns and for numeric columns with more than --max-cat distinct values,
"text" for other columns with more than --max-cat distinct values (searchable, not a filter), else "cat" (values
sorted numerically when they are all numbers). Empty cells and "-" are null (cat: -1).
Columns in --drop, empty columns and constant ones never appear as columns (constant ones go to "constant").

Usage: uv run tools/site_table.py CSV... --out DIR [--drop a,b,c] [--drop-prefix dev] [--num cost,ms] [--max-cat 40]
Builders with inputs of their own import table() (e.g. plans/square_roundabouts/site/build_data.py: the probe tables
and the offline test timings of Roundabouts & Interchanges).
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import sys
from pathlib import Path

MISSING = {"", "-"}


def as_num(v: str) -> float | int | None:
    if v in MISSING:
        return None
    try:
        f = float(v)
    except ValueError:
        return None
    return int(f) if f.is_integer() and "." not in v else f


def is_num(v: str) -> bool:
    return v in MISSING or as_num(v) is not None


def convert(path: Path, drop: set[str], drop_prefix: list[str], num: set[str], max_cat: int) -> dict:
    with path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)
        keys = reader.fieldnames or []
    modified = dt.datetime.fromtimestamp(path.stat().st_mtime).date().isoformat()
    return table(rows, keys, path.name, modified, drop, drop_prefix, num, max_cat)


def table(rows: list[dict], keys: list[str], source: str, modified: str, drop: set[str] = frozenset(), drop_prefix: list[str] = (),
          num: set[str] = frozenset(), max_cat: int = 40) -> dict:
    """Rows (dicts of strings) -> a data file dict; builders with their own inputs call this directly."""
    columns, constant = [], {}
    for k in keys:
        if k in drop or any(k.startswith(p) for p in drop_prefix):
            continue
        vals = [r.get(k) or "" for r in rows]
        present = [v for v in vals if v not in MISSING]
        if not present:
            continue
        distinct = set(present)
        numeric = all(is_num(v) for v in present)
        if len(distinct) == 1 and len(present) == len(vals) and k not in num:
            constant[k] = present[0]
            continue
        if numeric and (k in num or len(distinct) > max_cat):
            columns.append({"key": k, "type": "num", "data": [as_num(v) for v in vals]})
            continue
        if not numeric and len(distinct) > max_cat:
            columns.append({"key": k, "type": "text", "data": [v if v not in MISSING else None for v in vals]})
            continue
        order = sorted(distinct, key=lambda v: (as_num(v), v)) if numeric else sorted(distinct)
        index = {v: i for i, v in enumerate(order)}
        columns.append({"key": k, "type": "cat", "values": order, "data": [index.get(v, -1) for v in vals]})
    return {"version": 1, "source": source, "modified": modified, "rows": len(rows), "constant": constant, "columns": columns}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("csv", nargs="+", type=Path)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--drop", default="", help="comma-separated columns to leave out")
    ap.add_argument("--drop-prefix", default="", help="comma-separated column prefixes to leave out")
    ap.add_argument("--num", default="", help="comma-separated columns that are always numeric")
    ap.add_argument("--max-cat", type=int, default=40, help="numeric columns with more distinct values are numeric")
    a = ap.parse_args()
    split = lambda s: [x for x in s.split(",") if x]
    a.out.mkdir(parents=True, exist_ok=True)
    for p in a.csv:
        data = convert(p, set(split(a.drop)), split(a.drop_prefix), set(split(a.num)), a.max_cat)
        out = a.out / (p.stem.replace("_", "-") + ".json")
        out.write_text(json.dumps(data, separators=(",", ":")) + "\n", encoding="utf-8")
        print(f"{out}: {data['rows']} rows, {len(data['columns'])} columns, {len(data['constant'])} constant, {out.stat().st_size // 1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
