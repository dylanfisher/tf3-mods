# /// script
# requires-python = ">=3.11"
# ///
"""Local optimized forks of subscribed third-party mods ("SQ Opt"), with upstream merges.

A fork is a private copy of a mod from .cache/subscribed/ (`make subscribed`) that you change, e.g. for
performance, and keep in sync with the author's updates by three-way merge. Third-party code never
reaches git: the fork and its snapshots are gitignored, and only your notes are committed.

  mods/square_opt_<upstreamId>/        the fork, linked into staging like any mod (gitignored)
  forks/<forkId>/base/                 upstream as of the fork's last merge, normalized (gitignored)
  forks/<forkId>/incoming/             newer upstream during a merge, normalized (gitignored)
  forks/<forkId>/backup/               the fork before the merge started (gitignored)
  forks/<forkId>/REPORT.md             merge report, upstream.diff: what upstream changed (gitignored)
  plans/<forkId>/fork.json             upstream id, base revision, merge history (committed)
  plans/<forkId>/FORK.md               what the fork changes and why: the merge checklist (committed)

"Normalized" means LF line endings and the upstream modId replaced by the fork's, so the merge only sees
real changes. Naming: modId square_opt_<upstreamId>, display name "SQ Opt: <upstream name>" (32 chars max).

Usage:
  uv run tools/fork_mod.py new <upstreamModId>     create the fork from .cache/subscribed/<upstreamModId>
  uv run tools/fork_mod.py status                  every fork: up to date, or upstream has a newer revision
  uv run tools/fork_mod.py merge <forkId> [--from DIR]
                                                   three-way merge newer upstream into the fork; conflicts
                                                   get git-style markers, see forks/<forkId>/REPORT.md
  uv run tools/fork_mod.py finish <forkId>         after resolving: check no markers remain, adopt the new base
  uv run tools/fork_mod.py abort <forkId>          restore the fork from the backup, drop the merge

The tf3-fork-merger agent runs merge → resolve → check/test → finish (.claude/agents/tf3-fork-merger.md).
"""

from __future__ import annotations

import argparse
import datetime
import difflib
import filecmp
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import MODS_DIR, ROOT, SUBSCRIBED_CACHE_DIR  # noqa: E402

FORKS_DIR = ROOT / "forks"
PLANS_DIR = ROOT / "plans"
PREFIX = "square_opt_"
NAME_PREFIX = "SQ Opt: "
NAME_MAX = 32
TEXT_SUFFIXES = {".lua", ".tl", ".json", ".txt", ".md", ".html", ".css", ".mdl", ".mtl", ".con", ".module", ".csv"}
SKIP_NAMES = {".DS_Store", "texture_metadata_cache.lua"}
# Files the fork tool writes itself; never taken from upstream.
OWN_FILES = {"NOT_FOR_UPLOAD.txt", "_metadata/modinfo.json", "_metadata/description.html", "_metadata/0.png"}
MARKER = re.compile(r"^(<<<<<<<|>>>>>>>)( |$)", re.M)


def is_text(path: Path) -> bool:
    return path.suffix.lower() in TEXT_SUFFIXES


def files_of(root: Path) -> dict[str, Path]:
    if not root.is_dir():
        return {}
    return {p.relative_to(root).as_posix(): p for p in sorted(root.rglob("*"))
            if p.is_file() and p.name not in SKIP_NAMES}


def upstream_meta(upstream_id: str) -> dict:
    """Name, author, mod.io id from .cache/subscribed/INDEX.md (written by make subscribed)."""
    index = SUBSCRIBED_CACHE_DIR / "INDEX.md"
    meta = {"name": upstream_id, "author": "", "modioId": None, "url": ""}
    if index.exists():
        for line in index.read_text(encoding="utf-8").splitlines():
            if line.startswith(f"| `{upstream_id}` |"):
                cells = [c.strip() for c in line.strip("|").split("|")]
                m = re.match(r"\[(.*)\]\((.*)\)", cells[1])
                meta["name"], meta["url"] = (m.group(1), m.group(2)) if m else (cells[1], "")
                meta["author"] = cells[2]
                meta["modioId"] = int(cells[3]) if cells[3].isdigit() else None
    return meta


def revision_of(mod_dir: Path) -> int | None:
    try:
        return json.loads((mod_dir / "mod.json").read_text(encoding="utf-8-sig")).get("revision")
    except (OSError, json.JSONDecodeError):
        return None


def normalize(src: Path, dst: Path, upstream_id: str, fork_id: str) -> None:
    """Copy an upstream mod to dst with LF line endings and the modId replaced."""
    if dst.exists():
        shutil.rmtree(dst)
    for rel, path in files_of(src).items():
        out = dst / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        if is_text(path):
            text = path.read_bytes().decode("utf-8-sig").replace("\r\n", "\n").replace(upstream_id, fork_id)
            out.write_text(text, encoding="utf-8")
        else:
            shutil.copy2(path, out)


def fork_paths(fork_id: str) -> dict[str, Path]:
    f = FORKS_DIR / fork_id
    return {"mod": MODS_DIR / fork_id, "base": f / "base", "incoming": f / "incoming", "backup": f / "backup",
            "report": f / "REPORT.md", "diff": f / "upstream.diff", "plan": PLANS_DIR / fork_id,
            "json": PLANS_DIR / fork_id / "fork.json"}


def load_fork(fork_id: str) -> dict:
    p = fork_paths(fork_id)["json"]
    if not p.exists():
        raise SystemExit(f"{fork_id}: no {p.relative_to(ROOT)} (not a fork; create one with `make fork-new`)")
    return json.loads(p.read_text())


def save_fork(fork_id: str, data: dict) -> None:
    fork_paths(fork_id)["json"].write_text(json.dumps(data, indent=4) + "\n")


def today() -> str:
    return datetime.date.today().isoformat()


def fork_mod_json(text: str, upstream_id: str) -> str:
    """mod.json with revision 1 and an incompatibility with the original, changing as few lines as possible."""
    entry = {"mod": {"modId": upstream_id}}
    text, n = re.subn(r'("revision"\s*:\s*)\d+', r"\g<1>1", text, count=1)
    data = json.loads(text)
    if n == 1 and entry in (data.get("incompatibilities") or []):
        return text
    if n == 1 and re.search(r'"incompatibilities"\s*:\s*null', text):
        return re.sub(r'"incompatibilities"\s*:\s*null',
                      f'"incompatibilities": [\n\t\t{{ "mod": {{ "modId": "{upstream_id}" }} }}\n\t]', text, count=1)
    # unusual layout: rewrite as JSON
    data["revision"] = 1
    data["incompatibilities"] = [*(data.get("incompatibilities") or []), entry]
    return json.dumps(data, indent="\t", ensure_ascii=False) + "\n"


# --- new -------------------------------------------------------------------------------------------------

def add_fork_cover(fork_id: str, display: str) -> None:
    """Register the fork's cover (fork-orange Diagonal Split, branding/README.md "Local forks") in mods.js."""
    mods_js = ROOT / "branding/mods.js"
    text = mods_js.read_text(encoding="utf-8")
    if f"id: '{fork_id}'" in text:
        return
    name = display.replace("\\", "\\\\").replace("'", "\\'")
    mods_js.write_text(text.rstrip("\n") + f"\nSquare.forkCover({{\n  id: '{fork_id}', name: '{name}',\n}});\n",
                       encoding="utf-8")


def cmd_new(upstream_id: str) -> None:
    src = SUBSCRIBED_CACHE_DIR / upstream_id
    if not (src / "mod.json").exists():
        raise SystemExit(f"{upstream_id} is not in .cache/subscribed/ (subscribe to it, then `make subscribed`)")
    fork_id = PREFIX + upstream_id
    if not re.fullmatch(r"[a-z0-9_]+", fork_id):
        raise SystemExit(f"fork id {fork_id!r} must match [a-z0-9_]+")
    p = fork_paths(fork_id)
    if p["mod"].exists() or p["json"].exists():
        raise SystemExit(f"{fork_id} exists already (mods/ or plans/)")

    meta = upstream_meta(upstream_id)
    rev = revision_of(src)
    normalize(src, p["base"], upstream_id, fork_id)
    shutil.copytree(p["base"], p["mod"])

    # Fork's own identity: revision restarts at 1, incompatible with the original (both would run otherwise).
    # Edited as text, so the rest of mod.json stays byte-identical to upstream (fewer merge conflicts).
    mod_json_path = p["mod"] / "mod.json"
    mod_json_path.write_text(fork_mod_json(mod_json_path.read_text(encoding="utf-8"), upstream_id), encoding="utf-8")

    name = meta["name"]
    display = NAME_PREFIX + name
    if len(display) > NAME_MAX:
        display = display[: NAME_MAX - 1].rstrip() + "…"
    by = f" by {meta['author']}" if meta["author"] else ""
    modinfo = {
        "name": display,
        "summary": f"Local square optimized copy of {name}{by}. Not for upload."[:100],
        "description": (f"LOCAL ONLY - NOT FOR UPLOAD. A square optimized copy of {name}{by}"
                        f"{' (mod.io ' + str(meta['modioId']) + ')' if meta['modioId'] else ''}, upstream revision {rev}. "
                        f"All credit for the mod goes to its author. What changed: plans/{fork_id}/FORK.md."),
        "authors": [{"name": "square", "role": "CREATOR"}],
        "tags": ["Script Mod"],
        "dependencies": [],
        "url": "",
    }
    (p["mod"] / "_metadata").mkdir(exist_ok=True)
    (p["mod"] / "_metadata/modinfo.json").write_text(json.dumps(modinfo, indent=4, ensure_ascii=False) + "\n")
    (p["mod"] / "_metadata/description.html").write_text(
        f"<p><b>LOCAL ONLY - NOT FOR UPLOAD.</b> A square optimized copy of {name}{by}. "
        f"All credit for the mod goes to its author.</p>\n"
        f"<h2>Changelog</h2>\n<h4>Revision 1</h4>\n<ul><li>Forked from upstream revision {rev}.</li></ul>\n")
    (p["mod"] / "NOT_FOR_UPLOAD.txt").write_text(
        f"LOCAL ONLY - NOT FOR UPLOAD\n\n{fork_id} is a private fork of {name}{by} ({upstream_id}).\n"
        f"It is third-party code: never publish it to mod.io (Mod Hub > My Mods would offer it because\n"
        f"`make link` puts it in the staging area). Improvements go to the author instead.\n\n"
        f"Fork notes: plans/{fork_id}/FORK.md. Merging upstream updates: `make fork-status`, then the\n"
        f"tf3-fork-merger agent.\n")

    add_fork_cover(fork_id, display)

    p["plan"].mkdir(parents=True, exist_ok=True)
    save_fork(fork_id, {
        "forkId": fork_id, "upstreamModId": upstream_id, "upstreamName": name, "upstreamAuthor": meta["author"],
        "modioId": meta["modioId"], "url": meta["url"], "baseRevision": rev, "forkedAt": today(),
        "merges": [],
    })
    fork_md = p["plan"] / "FORK.md"
    if not fork_md.exists():
        fork_md.write_text(f"""# {display}

Fork of **{name}**{by} (`{upstream_id}`{', mod.io ' + str(meta['modioId']) if meta['modioId'] else ''}), local only.
Base: upstream revision {rev}, forked {today()}. Mechanics: `tools/fork_mod.py`.

## Changes

One entry per change, so a merge can check each one survived. Name the files and functions it touches and
mark the code with `-- optimized:` comments.

## Open questions

## Merge log

Newest first: upstream revision merged, date, conflicts and how they were resolved.
""")
    print(f"Created {fork_id}\n  mods/{fork_id}/  (fork, gitignored)\n  forks/{fork_id}/base/  (upstream rev {rev})\n"
          f"  plans/{fork_id}/FORK.md, fork.json  (committed notes)\n"
          f"  branding/mods.js forkCover entry: render it with `make covers MOD=mods/{fork_id}`\n"
          f"Disable '{name}' in the game's mod list when you enable '{display}'.")


# --- status ----------------------------------------------------------------------------------------------

def cmd_status() -> None:
    forks = sorted(p.parent.name for p in PLANS_DIR.glob(f"{PREFIX}*/fork.json"))
    if not forks:
        print("No forks yet (`make fork-new UP=<upstreamModId>`).")
    for fork_id in forks:
        data = load_fork(fork_id)
        up = SUBSCRIBED_CACHE_DIR / data["upstreamModId"]
        cur = revision_of(up)
        p = fork_paths(fork_id)
        state = ("MERGE IN PROGRESS (resolve, then `make fork-finish`)" if p["incoming"].exists() else
                 "fork missing in mods/ (gitignored: recreate it)" if not p["mod"].exists() else
                 "base snapshot missing in forks/ (merges impossible until recreated)" if not p["base"].exists() else
                 "upstream not in .cache/subscribed (run `make subscribed`)" if cur is None else
                 f"UPDATE AVAILABLE: upstream rev {cur} (fork based on {data['baseRevision']})"
                 if cur != data["baseRevision"] else f"up to date (upstream rev {cur})")
        print(f"{fork_id:48} {state}")


# --- merge -----------------------------------------------------------------------------------------------

def merge_file(ours: Path, base: Path, theirs: Path) -> tuple[str, int]:
    """git merge-file -p: merged text and the number of conflicts."""
    r = subprocess.run(["git", "merge-file", "-p", "-L", "fork", "-L", "base", "-L", "upstream",
                        str(ours), str(base), str(theirs)], capture_output=True)
    if r.returncode < 0 or r.returncode > 127:
        raise SystemExit(f"git merge-file failed on {ours}: {r.stderr.decode(errors='replace')}")
    return r.stdout.decode("utf-8"), r.returncode


_MISSING = object()


def merge_mod_json(ours: Path, base: Path, theirs: Path) -> dict | None:
    """Key-level three-way merge of mod.json, or None when both sides changed the same key differently.
    The fork keeps its own revision; incompatibilities are the union (the fork adds one with the original)."""
    o, b, t = (json.loads(x.read_text(encoding="utf-8-sig")) for x in (ours, base, theirs))
    out = {}
    for k in [*t, *(k for k in o if k not in t)]:
        if k == "revision":
            out[k] = o.get(k, t.get(k))
            continue
        ov, bv, tv = o.get(k, _MISSING), b.get(k, _MISSING), t.get(k, _MISSING)
        if k == "incompatibilities":
            merged = list(tv if isinstance(tv, list) else [])
            merged += [i for i in (ov if isinstance(ov, list) else []) if i not in merged]
            out[k] = merged or None
            continue
        if ov == bv:
            v = tv
        elif tv == bv or ov == tv:
            v = ov
        else:
            return None
        if v is not _MISSING:
            out[k] = v
    return out


def same(a: Path | None, b: Path | None) -> bool:
    if a is None or b is None:
        return a is b
    return filecmp.cmp(a, b, shallow=False)


def cmd_merge(fork_id: str, from_dir: Path | None) -> None:
    data = load_fork(fork_id)
    p = fork_paths(fork_id)
    if p["incoming"].exists():
        raise SystemExit(f"A merge is already in progress: resolve it and `make fork-finish FORK={fork_id}`, "
                         f"or `make fork-abort FORK={fork_id}`")
    if not p["base"].exists():
        raise SystemExit(f"No base snapshot at {p['base']}: a three-way merge needs it")
    src = from_dir or SUBSCRIBED_CACHE_DIR / data["upstreamModId"]
    if not (src / "mod.json").exists():
        raise SystemExit(f"No upstream at {src} (run `make subscribed`)")
    new_rev = revision_of(src)
    if from_dir is None and new_rev == data["baseRevision"]:
        raise SystemExit(f"{fork_id}: upstream is still at rev {new_rev}, nothing to merge")

    normalize(src, p["incoming"], data["upstreamModId"], fork_id)
    if p["backup"].exists():
        shutil.rmtree(p["backup"])
    shutil.copytree(p["mod"], p["backup"], symlinks=True)

    base, theirs, ours = files_of(p["base"]), files_of(p["incoming"]), files_of(p["mod"])
    clean, conflicts, taken, added, deleted, kept, attention = [], [], [], [], [], [], []
    for rel in sorted(set(base) | set(theirs) | set(ours)):
        if rel in OWN_FILES:
            continue
        b, t, o = base.get(rel), theirs.get(rel), ours.get(rel)
        target = p["mod"] / rel
        if same(b, t):
            continue  # upstream did not touch it: the fork's version stands
        if same(b, o):
            # only upstream changed it: take theirs (or its deletion)
            if t is None:
                target.unlink()
                deleted.append(rel)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(t, target)
                (added if b is None else taken).append(rel)
            continue
        if same(o, t):
            continue  # both made the same change
        # both changed it
        if rel == "mod.json" and b and t and o:
            merged = merge_mod_json(o, b, t)
            if merged is not None:
                target.write_text(json.dumps(merged, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
                clean.append((rel + " (key by key; the fork's revision kept, bump it)", 0))
                continue
        if b and t and o and is_text(o):
            text, n = merge_file(o, b, t)
            target.write_text(text, encoding="utf-8")
            (conflicts if n else clean).append((rel, n))
        elif t is None:
            kept.append(rel)
            attention.append(f"`{rel}`: upstream deleted it, the fork changed it. Kept the fork's version.")
        elif o is None:
            attention.append(f"`{rel}`: the fork deleted it, upstream changed it. Still deleted; upstream's is in incoming/.")
        else:
            attention.append(f"`{rel}`: binary or new on both sides and different. Kept the fork's; upstream's is in incoming/.")

    # what upstream changed, for the resolver to understand the intent
    diff_lines: list[str] = []
    for rel in sorted(set(base) | set(theirs)):
        b, t = base.get(rel), theirs.get(rel)
        if same(b, t):
            continue
        if (b and not is_text(b)) or (t and not is_text(t)):
            diff_lines.append(f"Binary {rel} {'added' if b is None else 'deleted' if t is None else 'changed'}\n")
            continue
        a_lines = b.read_text(encoding="utf-8").splitlines(keepends=True) if b else []
        t_lines = t.read_text(encoding="utf-8").splitlines(keepends=True) if t else []
        diff_lines += difflib.unified_diff(a_lines, t_lines, f"base/{rel}", f"upstream/{rel}")
    p["diff"].write_text("".join(diff_lines), encoding="utf-8")

    def section(title: str, items: list[str]) -> list[str]:
        return [f"## {title}", "", *(items or ["(none)"]), ""]

    report = [
        f"# Merge report: {fork_id}",
        "",
        f"Upstream rev {data['baseRevision']} → {new_rev} ({today()}). Fork before the merge: `forks/{fork_id}/backup/`.",
        f"What upstream changed: `forks/{fork_id}/upstream.diff`. The fork's own changes: `plans/{fork_id}/FORK.md`.",
        "",
        *section("Conflicts (markers <<<<<<< fork / ======= / >>>>>>> upstream left in the file)",
                 [f"- `{r}`: {n} conflict(s)" for r, n in conflicts]),
        *section("Needs attention", [f"- {a}" for a in attention]),
        *section("Merged cleanly (both sides changed, no overlap)", [f"- `{r}`" for r, _ in clean]),
        *section("Taken from upstream (the fork had not changed them)", [f"- `{r}`" for r in taken]),
        *section("Added by upstream", [f"- `{r}`" for r in added]),
        *section("Deleted by upstream", [f"- `{r}`" for r in deleted]),
        "## Next",
        "",
        "Resolve every conflict and attention item, re-check each FORK.md change still holds (also in cleanly",
        "merged files), bump the fork's revision, add the changelog and merge-log entries, run make check/test,",
        f"then `make fork-finish FORK={fork_id}`.",
        "",
    ]
    p["report"].write_text("\n".join(report), encoding="utf-8")
    print("\n".join(report))


def cmd_finish(fork_id: str) -> None:
    data = load_fork(fork_id)
    p = fork_paths(fork_id)
    if not p["incoming"].exists():
        raise SystemExit(f"No merge in progress for {fork_id}")
    left = [rel for rel, path in files_of(p["mod"]).items() if is_text(path) and MARKER.search(path.read_text(encoding="utf-8"))]
    if left:
        raise SystemExit("Conflict markers remain in:\n  " + "\n  ".join(left))
    new_rev = revision_of(p["incoming"])
    shutil.rmtree(p["base"])
    p["incoming"].rename(p["base"])
    data["merges"].insert(0, {"from": data["baseRevision"], "to": new_rev, "date": today(),
                              "forkRevision": revision_of(p["mod"])})
    data["baseRevision"] = new_rev
    save_fork(fork_id, data)
    print(f"{fork_id}: now based on upstream rev {new_rev}. Backup of the pre-merge fork stays in forks/{fork_id}/backup/.")


def cmd_abort(fork_id: str) -> None:
    p = fork_paths(fork_id)
    if not p["incoming"].exists() or not p["backup"].exists():
        raise SystemExit(f"No merge in progress for {fork_id}")
    shutil.rmtree(p["mod"])
    shutil.copytree(p["backup"], p["mod"], symlinks=True)
    shutil.rmtree(p["incoming"])
    for k in ("report", "diff"):
        p[k].unlink(missing_ok=True)
    print(f"{fork_id}: merge aborted, fork restored from forks/{fork_id}/backup/.")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("new").add_argument("upstream_id")
    sub.add_parser("status")
    m = sub.add_parser("merge")
    m.add_argument("fork_id")
    m.add_argument("--from", dest="from_dir", type=Path, help="upstream folder to merge (default: .cache/subscribed)")
    sub.add_parser("finish").add_argument("fork_id")
    sub.add_parser("abort").add_argument("fork_id")
    args = ap.parse_args()
    if args.cmd == "new":
        cmd_new(args.upstream_id)
    elif args.cmd == "status":
        cmd_status()
    elif args.cmd == "merge":
        cmd_merge(args.fork_id, args.from_dir)
    elif args.cmd == "finish":
        cmd_finish(args.fork_id)
    else:
        cmd_abort(args.fork_id)


if __name__ == "__main__":
    main()
