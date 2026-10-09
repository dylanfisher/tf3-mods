# /// script
# requires-python = ">=3.11"
# ///
"""Fetch pinned state flags from Wikimedia Commons and sanitize them into branding/flags/<key>.svg.

Every flag is pinned in branding/flags/SOURCES.json (Commons file page, upload URL, sha1, licence, author,
retrieval date, aspect). Steps per flag:

1. Download the pinned URL into its own fresh, empty directory .cache/flags/raw/<key>/ (gitignored).
2. Verify the sha1 and the licence (Public domain / CC0 only, unless --allow).
3. Sanitize with a separate, isolated interpreter: `python -I tools/sanitize_svg.py <raw> branding/flags/<key>.svg`.

The downloaded file is untrusted data: it is only read as bytes and parsed as XML by the sanitizer, never
executed or imported.

Usage:
  uv run tools/fetch_flags.py                      fetch + sanitize every pinned flag
  uv run tools/fetch_flags.py us_washington        just this one
  uv run tools/fetch_flags.py --lookup "Flag of Oregon.svg" --key us_oregon
                                                   query the Commons API and print a SOURCES.json entry to pin
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FLAGS = ROOT / "branding" / "flags"
SOURCES = FLAGS / "SOURCES.json"
RAW = ROOT / ".cache" / "flags" / "raw"
SANITIZER = Path(__file__).resolve().parent / "sanitize_svg.py"
UA = "square-tf3-mods/1.0 (flag fetch for mod covers; https://commons.wikimedia.org)"
FREE = {"public domain", "cc0"}


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def strip_html(s: str | None) -> str:
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", s or "")).strip()


def lookup(file_name: str, key: str | None) -> None:
    title = "File:" + file_name.removeprefix("File:").replace(" ", "_")
    q = urllib.parse.urlencode({"action": "query", "titles": title, "prop": "imageinfo", "format": "json",
                                "iiprop": "url|sha1|size|timestamp|extmetadata"})
    data = json.loads(get("https://commons.wikimedia.org/w/api.php?" + q))
    page = next(iter(data["query"]["pages"].values()))
    if "imageinfo" not in page:
        sys.exit(f"{title}: not found on Commons")
    ii = page["imageinfo"][0]
    meta = ii.get("extmetadata") or {}
    entry = {
        "key": key or "<stateKey>",
        "file": ii["descriptionurl"],
        "url": ii["url"].split("?")[0],
        "sha1": ii["sha1"],
        "license": strip_html((meta.get("LicenseShortName") or {}).get("value")),
        "author": strip_html((meta.get("Artist") or {}).get("value")),
        "restrictions": strip_html((meta.get("Restrictions") or {}).get("value")),
        "uploaded": ii.get("timestamp"),
        "retrieved": dt.date.today().isoformat(),
        "aspect": round(ii["width"] / ii["height"], 4) if ii.get("height") else None,
    }
    print(json.dumps(entry, indent=2, ensure_ascii=False))
    print("\nReview the licence, then add this entry to branding/flags/SOURCES.json.", file=sys.stderr)


def fetch(entry: dict, allow: bool) -> bool:
    key = entry["key"]
    if not re.fullmatch(r"[a-z0-9_]+", key):
        print(f"FAIL  {key!r}: bad key")
        return False
    lic = entry.get("license", "").lower()
    if lic not in FREE and not allow:
        print(f"FAIL  {key}: licence {entry.get('license')!r} is not Public domain / CC0 (use --allow after review)")
        return False
    url = entry["url"]
    if not url.startswith("https://upload.wikimedia.org/"):
        print(f"FAIL  {key}: URL must be on upload.wikimedia.org")
        return False
    raw_dir = RAW / key
    shutil.rmtree(raw_dir, ignore_errors=True)
    raw_dir.mkdir(parents=True)
    raw = raw_dir / "download.svg"
    body = get(url)
    raw.write_bytes(body)
    sha1 = hashlib.sha1(body).hexdigest()
    if sha1 != entry["sha1"]:
        print(f"FAIL  {key}: sha1 {sha1} != pinned {entry['sha1']} (file changed on Commons? re-run --lookup)")
        return False
    out = FLAGS / f"{key}.svg"
    # Separate isolated interpreter; the raw file is passed as an argument, cwd is the repo root.
    res = subprocess.run([sys.executable, "-I", str(SANITIZER), str(raw), str(out)], cwd=ROOT)
    if res.returncode != 0:
        print(f"FAIL  {key}: sanitizer refused the file")
        return False
    print(f"ok    {key}: sha1 verified, {entry.get('license')}, by {entry.get('author')}")
    return True


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("keys", nargs="*", help="state keys to fetch (default: every pinned flag)")
    ap.add_argument("--lookup", metavar="FILE", help='Commons file name, e.g. "Flag of Oregon.svg"')
    ap.add_argument("--key", help="state key for --lookup output")
    ap.add_argument("--allow", action="store_true", help="accept a licence other than Public domain / CC0")
    args = ap.parse_args()
    if args.lookup:
        lookup(args.lookup, args.key)
        return
    entries = json.loads(SOURCES.read_text(encoding="utf-8"))["flags"]
    wanted = [e for e in entries if not args.keys or e["key"] in args.keys]
    missing = set(args.keys) - {e["key"] for e in wanted}
    if missing:
        sys.exit(f"not pinned in {SOURCES.relative_to(ROOT)}: {', '.join(sorted(missing))}")
    ok = all([fetch(e, args.allow) for e in wanted])
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
