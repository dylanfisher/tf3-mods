# /// script
# requires-python = ">=3.11"
# ///
"""Archive and index of the game's logs, so past in-game evidence can be searched without re-running the game.

The game rewrites <userdata>/crash_dump/stdout.txt at every start (one file per game session, appended while
it runs) and leaves error reports next to it: <session-uuid>_N.txt (a copy of that session's log at the
error), <session-uuid>_M.json (errorInfo: type assert / critical / crash / error, message, file, function,
logFile; sessionInfo.started; gameInfo.mods) and a .dmp minidump.

Every command archives: the live stdout.txt and every crash_dump log (<uuid>_N.txt) become
.cache/logs/<start>_<slug>.log.gz (start = first timestamp, UTC; slug from --tag, else the main Stress Test
action + seed, else the top log tags; "-crash" when it crashed). The same content is never stored twice; a
grown copy of a session (same session id) replaces the shorter archive. crash_dump reports (.json) are indexed
in place and attached to their session, so crash_dump can be cleared without losing the logs. A Claude Code
SessionStart hook runs `save --brief`, so sessions are archived without anyone running a command.

  save [--tag NAME] [--file PATH] [--quiet | --brief] [--show N]
                                    --file: archive PATH instead of stdout.txt; --brief: one line per newly
                                    archived session only (the hook)
  list [--tag X] [--crash] [--grep TEXT] [--since DATE] [--last N] [-v]
  grep PATTERN [--tag X] [--since DATE] [--session NAME] [-C N] [--max N] [-i]
                                    regex over every archived log: "session:line: text"
  path NAME...                      a readable file per name: session name or prefix, session-id prefix,
                                    last, last-crash, last-<tag or action> (last-showcase, last-junction_test,
                                    last-sqrl), a Stress Test seed, live, or an existing file (passed
                                    through). Archives decompress to .cache/logs/tmp/.

Index: .cache/logs/index.json (machine) and .cache/logs/INDEX.md (one line per session, newest first).
Tags (--tag): user tags, log tags ([SQST], SQRL ... with or without brackets), Stress Test actions, "crash".

  make logs                   save, then the last few index lines
  make logs-list ARGS='--tag SQRL --last 5'
  make logs-grep PAT='AUDIT node=1234' ARGS='--session last -C 2'
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import re
import sys
from collections import Counter, deque
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

INDEX_VERSION = 1
SLUG_SKIP = {"SQPERF"}  # debug tag of every SQPERF mod: says nothing about the session
INDEX_TAGS = 4  # tags per INDEX.md line (list -v shows all)
TS = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)Z - (\w+)\s*- ")
TAG = re.compile(r"\[([A-Za-z][A-Za-z0-9_-]+)\]")
SESSION_ID = re.compile(r"Startup session with id (\S+)")
BUILD = re.compile(r"Starting up build version: (\d+)")
ACTIVE_MOD = re.compile(r"^\s+[|+]\s+(\S+) \(rev\. (\d+)\)")
LOAD_GAME = re.compile(r"Loading game from file (.+?)\s*$")
SQST_ACTION = re.compile(r"\[SQST\] action=(\S+)")
SEED = re.compile(r"\bseed=(\d+)")
# a Stress Test bench run (plans/square_stress_test/BENCH.md): its sheet and seed name the session ("bench-s1-<seed>")
BENCH_START = re.compile(r"\[SQST\] BENCH_START sheet=(\S+) \S+ seed=(\d+)")
CRASH_FILE = re.compile(r"^([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})_(\d+)\.(txt|json)$")
FATAL_TYPES = {"assert", "critical", "crash"}
# The game's own crash markers, right after the "[ts - LEVEL - thread - category]" header ("]+ Ungraceful exit",
# "]  ShowErrorBox: ..."), so a mod that merely prints these words does not mark its session as crashed.
CRASH_MARK = re.compile(r"^\[\d{4}-[^\]]*\]\s*\+?\s*(Ungraceful exit|ShowErrorBox|Minidump callback called)")


# --------------------------------------------------------------------------------------------- analysis

class Analyzer:
    """Streaming summary of one game log (fed line by line)."""

    def __init__(self) -> None:
        self.first_line = ""
        self.session_id = ""
        self.start = ""
        self.end = ""
        self.lines = 0
        self.build = ""
        self.mods: dict[str, str] = {}
        self.loads: list[str] = []
        self.n_loads = 0
        self.tags: Counter[str] = Counter()
        self.actions: Counter[str] = Counter()
        self.seeds: list[str] = []
        self.bench = ""  # "s1-<seed>" of the last BENCH_START
        self.bench_done = False
        self.audit = self.flow = self.probe = 0
        self.errors: Counter[str] = Counter()
        self.ungraceful = False
        self.errorbox = False
        self.minidump = False
        self.reason = ""
        self._in_mods = False
        self._exc_type = ""
        self._assert_wait = 0

    def feed(self, line: str) -> None:
        line = line.rstrip("\r\n")
        self.lines += 1
        if self.lines == 1:
            self.first_line = line
        m = TS.match(line)
        if m:
            ts = m[1]
            if not self.start:
                self.start = ts
            if ts > self.end:
                self.end = ts
            if m[2] == "ERROR":
                self.errors["error_lines"] += 1
        if self._in_mods:
            if mm := ACTIVE_MOD.match(line):
                self.mods[mm[1]] = mm[2]
                return
            self._in_mods = False
        if "Active mods:" in line:
            self._in_mods = True
            self.n_loads += 1
            return
        if not self.session_id and (sm := SESSION_ID.search(line)):
            self.session_id = sm[1]
        if not self.build and (bm := BUILD.search(line)):
            self.build = bm[1]
        if lm := LOAD_GAME.search(line):
            self.loads.append(lm[1])
        if "[" in line:
            tags = set(TAG.findall(line[1:] if m else line))
            for t in tags:
                self.tags[t] += 1
            if "SQST" in tags:
                if am := SQST_ACTION.search(line):
                    self.actions[am[1]] += 1
                for s in SEED.findall(line):
                    if s not in self.seeds:
                        self.seeds.append(s)
                if bm := BENCH_START.search(line):
                    self.bench = f"{bm[1]}-{bm[2]}"
                    self.bench_done = False
                elif "[SQST] BENCH_DONE " in line:
                    self.bench_done = True
            if "] AUDIT" in line:
                self.audit += 1
            if re.search(r"\] FLOW", line):
                self.flow += 1
            if "PROBE" in line and (re.search(r"\] PROBE", line) or any("PROBE" in t for t in tags)):
                self.probe += 1
        if "Construction Not Possible" in line:
            self.errors["construction_not_possible"] += 1
        if "Exception type:" in line:
            self._exc_type = line.split("Exception type:", 1)[1].strip()
            self.errors["exceptions"] += 1
            if self._exc_type == "Lua error":
                self.errors["lua"] += 1
        elif "Error message:" in line:
            msg = line.split("Error message:", 1)[1].strip()
            self.reason = f"{self._exc_type or 'error'}: {msg}"[:240]
        elif "Assertion Failure" in line:
            self.errors["asserts"] += 1
            msg = line.split("Assertion Failure", 1)[1].lstrip(": ").strip()
            self.reason = f"assert: {msg}"[:240]
            self._assert_wait = 20
        elif self._assert_wait and "In file:" in line:
            self.reason += f" ({line.split('In file:', 1)[1].strip()})"
            self._assert_wait = 0
        elif "Possible hang detected" in line:
            self.errors["hangs"] += 1
            if not self.reason:
                self.reason = "hang: a thread did not respond to ping"
        if self._assert_wait:
            self._assert_wait -= 1
        if m and (cm := CRASH_MARK.match(line)):
            if cm[1] == "Ungraceful exit":
                self.ungraceful = True
            elif cm[1] == "ShowErrorBox":
                self.errorbox = True
            else:
                self.minidump = True

    def result(self) -> dict:
        crashed = self.ungraceful or self.errorbox or self.minidump
        return {
            "first_line": self.first_line[:300], "session_id": self.session_id, "start": self.start,
            "end": self.end, "lines": self.lines, "build": self.build, "mods": self.mods, "loads": self.loads,
            "n_loads": self.n_loads, "tags": dict(self.tags.most_common()), "actions": dict(self.actions),
            "seeds": self.seeds, "audit": self.audit, "bench": self.bench, "bench_done": self.bench_done,
            "flow": self.flow, "probe": self.probe, "errors": dict(self.errors), "crashed": crashed,
            "reason": (self.reason or ("ungraceful exit" if self.ungraceful else "error box" if self.errorbox
                                       else "native crash (minidump)")) if crashed else "",
        }


def iter_lines(data: bytes):
    for raw in data.splitlines():
        yield raw.decode("utf-8", errors="replace")


def analyze_bytes(data: bytes) -> dict:
    a = Analyzer()
    for line in iter_lines(data):
        a.feed(line)
    return a.result()


def analyze_file(path: Path) -> dict:
    a = Analyzer()
    with open_log(path) as f:
        for line in f:
            a.feed(line)
    return a.result()


def open_log(path: Path):
    if path.suffix == ".gz":
        return gzip.open(path, "rt", encoding="utf-8", errors="replace")
    return open(path, encoding="utf-8", errors="replace")


# --------------------------------------------------------------------------------------------- store

def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def main_action(a: dict) -> str:
    """The session's main Stress Test action: the most frequent, the shortest name on a tie (showcase over
    showcase_towns / bus_lines_showcase)."""
    acts = a.get("actions") or {}
    return min(acts, key=lambda k: (-acts[k], len(k), k)) if acts else ""


def action_slug(a: dict) -> str:
    act = main_action(a)
    return "-".join([act] + a["seeds"][-1:]) if act else ""


def auto_slug(a: dict) -> str:
    parts = []
    if a.get("bench"):
        parts.append("bench-" + a["bench"])
    elif act := action_slug(a):
        parts.append(act)
    else:
        top: list[str] = []
        for t, _ in sorted(a["tags"].items(), key=lambda kv: (-kv[1], kv[0])):
            if t.upper() == t and len(t) > 2 and t not in SLUG_SKIP and not any(t.startswith(o) or o.startswith(t) for o in top):
                top.append(t)
        parts += top[:2] or ["session"]
    if a["crashed"]:
        parts.append("crash")
    return slugify("-".join(parts))[:40].strip("-") or "session"


def name_time(ts: str) -> str:
    return ts[:10] + "_" + ts[11:13] + ts[14:16] if ts else "unknown"


def duration_s(a: dict) -> int:
    try:
        s = datetime.strptime(a["start"], "%Y-%m-%d %H:%M:%S")
        e = datetime.strptime(a["end"], "%Y-%m-%d %H:%M:%S")
        return int((e - s).total_seconds())
    except (ValueError, KeyError, TypeError):
        return 0


class Store:
    def __init__(self, logs_dir: Path, crash_dir: Path | None, live: Path | None) -> None:
        self.dir = logs_dir
        self.crash_dir = crash_dir
        self.live = live
        self.index_path = logs_dir / "index.json"
        self.idx = self._load()
        self.new: list[str] = []  # sessions archived (or grown) by this run

    def _load(self) -> dict:
        if self.index_path.is_file():
            try:
                idx = json.loads(self.index_path.read_text())
                if idx.get("version") == INDEX_VERSION:
                    return idx
            except (OSError, json.JSONDecodeError):
                pass
        return {"version": INDEX_VERSION, "sessions": [], "crash_sessions": {}, "file_cache": {}}

    def write(self) -> None:
        write_if_changed(self.index_path, json.dumps(self.idx, indent=1, sort_keys=True).encode())
        write_if_changed(self.dir / "INDEX.md", render_index_md(self.entries()).encode())

    # ---- archive

    def save(self, src: Path, user_tags: list[str]) -> tuple[str, str]:
        """(status, name): status in new / replaced / unchanged / older."""
        data = src.read_bytes()
        if not data.strip():
            return "empty", ""
        h = hashlib.sha256(data).hexdigest()
        sessions = self.idx["sessions"]
        for s in sessions:
            if s["sha256"] == h or h in s.get("old_hashes", []):
                new_tags = [t for t in user_tags if t not in s["user_tags"]]
                if new_tags:
                    s["user_tags"] += new_tags
                return "unchanged", s["name"]
        a = analyze_bytes(data)
        # Same session = same session id and start. Without a session id line nothing is ever merged, and an
        # older archive is only replaced when this copy provably extends it (its first bytes hash to the old one).
        old = next((s for s in sessions if a["session_id"] and s["session_id"] == a["session_id"]
                    and s["start"] == a["start"]), None)
        if old is not None and old["size"] >= len(data):
            old.setdefault("old_hashes", []).append(h)
            return "older", old["name"]
        if old is not None and hashlib.sha256(data[:old["size"]]).hexdigest() != old["sha256"]:
            old = None
        tags = list(dict.fromkeys((old["user_tags"] if old else []) + user_tags))
        if old is not None and tags == old["user_tags"]:
            slug = old["name"].split("_", 2)[-1]  # a grown session keeps its name (logs and notes cite it)
        elif tags:
            extra = a["seeds"][-1:] if main_action(a) and a["seeds"] and a["seeds"][-1] not in tags else []
            slug = slugify("-".join(tags + extra))[:40].strip("-")
        else:
            slug = auto_slug(a)
        base = f"{name_time(a['start'])}_{slug}"
        taken = {s["name"] for s in sessions if s is not old}
        name, n = base, 2
        while name in taken:
            name, n = f"{base}-{n}", n + 1
        self.dir.mkdir(parents=True, exist_ok=True)
        dest = self.dir / f"{name}.log.gz"
        atomic_write(dest, gzip.compress(data, compresslevel=6, mtime=0))
        entry = {**a, "name": name, "file": dest.name, "sha256": h, "size": len(data),
                 "gz_size": dest.stat().st_size, "user_tags": tags, "source": str(src),
                 "saved_at": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S"),
                 "old_hashes": (old.get("old_hashes", []) + [old["sha256"]]) if old else []}
        if old is not None:
            sessions.remove(old)
            if old["file"] != dest.name:
                (self.dir / old["file"]).unlink(missing_ok=True)
            (self.dir / "tmp" / f"{old['name']}.log").unlink(missing_ok=True)
        sessions.append(entry)
        sessions.sort(key=lambda s: (s["start"], s["name"]))
        self.new.append(name)
        return ("replaced" if old else "new"), name

    # ---- crash_dump

    def index_crashes(self, archive: bool = False) -> None:
        """Index the crash_dump reports in place; archive=True also archives each crash log (<uuid>_N.txt) once,
        so the logs survive when crash_dump is cleared (the CLI always does)."""
        if self.crash_dir is None or not self.crash_dir.is_dir():
            return
        groups: dict[str, list[Path]] = {}
        for p in self.crash_dir.iterdir():
            if m := CRASH_FILE.match(p.name):
                groups.setdefault(m[1], []).append(p)
        cache = self.idx["file_cache"]
        seen_paths = set()
        known = self.idx["crash_sessions"]
        for uid, files in groups.items():
            txts, reports, jsons = [], [], []
            for p in sorted(files, key=lambda p: int(CRASH_FILE.match(p.name)[2])):
                try:
                    st = p.stat()
                except OSError:
                    continue
                seen_paths.add(str(p))
                c = cache.get(str(p))
                if not c or c["size"] != st.st_size or c["mtime"] != st.st_mtime_ns:
                    c = {"size": st.st_size, "mtime": st.st_mtime_ns}
                    if p.suffix == ".txt":
                        c["analysis"] = analyze_file(p)
                    else:
                        c["report"] = read_report(p)
                    cache[str(p)] = c
                if p.suffix == ".txt":
                    txts.append((p, c))
                    if archive and "archived" not in c:
                        c["archived"] = self.save(p, [])[1]
                else:
                    jsons.append(p)
                    if c.get("report"):
                        reports.append(c["report"])
            cs = build_crash_session(uid, txts, reports, jsons)
            if names := [c["archived"] for _, c in txts if c.get("archived")]:
                cs["archive"] = names[-1]
            elif (prev := known.get(uid)) and prev.get("archive"):
                cs["archive"] = prev["archive"]
            now = {f["path"] for f in cs["files"]}
            cs["files"] += [{**f, "exists": False} for f in (known.get(uid) or {}).get("files", [])
                            if f["path"] not in now]
            known[uid] = cs
        for p in list(cache):
            if p not in seen_paths and p.startswith(str(self.crash_dir)):
                del cache[p]
        for uid, cs in known.items():
            if uid not in groups:
                cs["missing"] = True
                for f in cs["files"]:
                    f["exists"] = False

    # ---- unified view

    def entries(self) -> list[dict]:
        out = []
        crash = self.idx["crash_sessions"]
        archived = {}
        names = {s["name"] for s in self.idx["sessions"]}
        for s in self.idx["sessions"]:
            e = dict(s)
            e["kind"] = "archive"
            e["missing"] = not (self.dir / s["file"]).is_file()
            e["paths"] = [str(self.dir / s["file"])]
            cs = crash.get(s["session_id"]) if s["session_id"] else None
            e["reports"] = cs["reports"] if cs else []
            e["fatal"] = bool(cs and cs["fatal"]) or s["crashed"]
            e["crashed"] = s["crashed"] or bool(cs and cs["reports"])
            if cs and cs["reason"] and (cs["fatal"] or not e["reason"]):
                e["reason"] = cs["reason"]
            e["crash_logs"] = [f["path"] for f in cs["files"] if f["path"].endswith(".txt")] if cs else []
            if s["session_id"]:
                archived[s["session_id"]] = s["name"]
            out.append(e)
        for uid, cs in crash.items():
            e = dict(cs)
            e["kind"] = "crash_dump"
            e["archived_as"] = archived.get(uid) or (cs.get("archive") if cs.get("archive") in names else "")
            e["paths"] = [f["path"] for f in cs["files"] if f["path"].endswith(".txt") and f["exists"]]
            e["user_tags"] = []
            out.append(e)
        out.sort(key=lambda e: (e["start"] or "", e["name"]))
        return out


def atomic_write(path: Path, data: bytes) -> None:
    """Temp file + rename, so an interrupted or concurrent run never leaves a half-written file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        tmp.write_bytes(data)
        tmp.replace(path)
    finally:
        tmp.unlink(missing_ok=True)


def write_if_changed(path: Path, data: bytes) -> None:
    try:
        if path.read_bytes() == data:
            return
    except OSError:
        pass
    atomic_write(path, data)


def read_report(p: Path) -> dict | None:
    try:
        d = json.loads(p.read_text(errors="replace"))
    except (OSError, json.JSONDecodeError):
        return None
    ei = d.get("errorInfo") or {}
    if ei.get("type") in (None, "", "ping"):
        return None
    gi = d.get("gameInfo") or {}
    return {
        "json": p.name, "type": ei.get("type", ""), "message": ei.get("message", ""),
        "file": ei.get("file", ""), "line": ei.get("line", -1), "function": ei.get("function", ""),
        "logFile": ei.get("logFile", ""), "dumpFile": ei.get("dumpFile", ""), "timestamp": (ei.get("timestamp") or "").rstrip("Z"),
        "build": str((d.get("buildInfo") or {}).get("version", "")),
        "started": ((d.get("sessionInfo") or {}).get("started") or "").rstrip("Z"),
        "mods": [m.get("name", "") for m in gi.get("mods") or [] if isinstance(m, dict)],
        "savegame": gi.get("savegameName", ""),
    }


def report_reason(r: dict) -> str:
    msg = r["message"] or ("native crash, no message (minidump " + r["dumpFile"] + ")" if r.get("dumpFile")
                           else "(no message)")
    where = f" ({Path(r['file']).name}:{r['line']} {r['function']})" if r["file"] else ""
    return f"{r['type']}: {msg}{where}"[:240]


def build_crash_session(uid: str, txts: list, reports: list[dict], jsons: list[Path]) -> dict:
    reports.sort(key=lambda r: (r["timestamp"], r["json"]))
    primary = max(txts, key=lambda t: (t[1]["analysis"]["end"], t[1]["size"]))[1]["analysis"] if txts else None
    a = primary or Analyzer().result()
    started = next((r["started"] for r in reports if r["started"]), "")
    start = started or min((t[1]["analysis"]["start"] for t in txts if t[1]["analysis"]["start"]), default="")
    if not start:
        start = next((r["timestamp"] for r in reports), "")
    end = max([a["end"]] + [r["timestamp"] for r in reports])
    fatal_r = [r for r in reports if r["type"] in FATAL_TYPES]
    fatal = bool(fatal_r) or a["crashed"]
    with_msg = [r for r in fatal_r if r["message"]] or [r for r in reports if r["message"]]
    generic = not a["reason"] or a["reason"].startswith(("hang:", "native crash", "ungraceful", "error box"))
    if with_msg and (generic or with_msg[-1] in fatal_r):
        reason = report_reason(with_msg[-1])
    elif a["reason"]:
        reason = a["reason"]
    elif reports:
        reason = report_reason((fatal_r or reports)[-1])
    else:
        reason = ""
    mods = {m: "" for r in reports for m in r["mods"] if m} or a["mods"]
    files = [{"path": str(p), "exists": True, "size": c["size"]} for p, c in txts]
    files += [{"path": str(p), "exists": True} for p in jsons]
    return {
        **{k: a[k] for k in ("tags", "actions", "seeds", "audit", "flow", "probe", "errors",
                             "loads", "n_loads", "first_line", "lines")},
        "name": f"{name_time(start)}_crash-{uid[:8]}", "session_id": uid, "start": start, "end": end,
        "build": next((r["build"] for r in reports if r["build"]), a["build"]), "mods": mods,
        "size": sum(c["size"] for _, c in txts), "reports": reports, "fatal": fatal,
        "crashed": True, "reason": reason, "files": files, "missing": False,
        "savegame": next((r["savegame"] for r in reports if r["savegame"]), ""),
    }


# --------------------------------------------------------------------------------------------- views

def fmt_size(n: int) -> str:
    return f"{n / 1e6:.1f} MB" if n >= 1e5 else f"{n / 1e3:.0f} kB"


def fmt_dur(s: int) -> str:
    return f"{s // 3600}h{s % 3600 // 60:02d}m" if s >= 3600 else f"{s // 60}m"


def summary(e: dict, mods: bool = True, top_tags: int = 8, brief: bool = False) -> str:
    """brief: the INDEX.md form (no size, build, mods; short loads, actions and reason)."""
    parts = [f"{e['start'][5:16] or '?'}-{e['end'][11:16] or '?'}Z {fmt_dur(duration_s(e))}"]
    if not brief:
        parts.append(fmt_size(e["size"]))
        if e.get("build"):
            parts.append(f"build {e['build']}")
    if e["kind"] == "crash_dump":
        parts.append("crash_dump" + (f" (archived as {e['archived_as']})" if e.get("archived_as") else ""))
    if e.get("loads"):
        parts.append("loads " + ", ".join(dict.fromkeys(e["loads"]))[:40 if brief else 80])
    if e["tags"]:
        tags = sorted(e["tags"].items(), key=lambda kv: (-kv[1], kv[0]))[:top_tags]
        parts.append("tags " + " ".join(f"{t}:{n}" for t, n in tags))
    if e.get("seeds"):
        parts.append("seed " + ",".join(e["seeds"][-3:] if brief else e["seeds"]))
    if e.get("actions"):
        acts = sorted(e["actions"].items(), key=lambda kv: (-kv[1], kv[0]))
        more = f",+{len(acts) - 4}" if brief and len(acts) > 4 else ""
        parts.append("actions " + ",".join(f"{k}" + (f"x{v}" if v > 1 else "")
                                           for k, v in (acts[:4] if brief else acts)) + more)
    flags = [f"{k} {e[k]}" for k in ("audit", "flow", "probe") if e.get(k)]
    if flags:
        parts.append(" ".join(f.upper() for f in flags))
    err = e.get("errors") or {}
    errs = [f"{lab} {err[k]}" for k, lab in (("lua", "lua"), ("asserts", "assert"),
                                             ("construction_not_possible", "CNP"), ("error_lines", "ERROR"))
            if err.get(k)]
    if errs:
        parts.append("errors " + " ".join(errs))
    if e.get("crashed"):
        reason = e.get("reason") or "?"
        parts.append(("CRASH: " if e.get("fatal") else "ERROR REPORT: ") + (reason[:140] if brief else reason))
    if e.get("missing"):
        parts.append("MISSING")
    if mods and e.get("mods"):
        parts.append("mods " + ", ".join(f"{m.removeprefix('square_')}" + (f" {r}" if r else "")
                                         for m, r in e["mods"].items()))
    return "; ".join(parts)


def render_index_md(entries: list[dict]) -> str:
    out = ["# Game log archive", "",
           "Generated by `tools/game_logs.py`. One line per game session, newest first, times UTC. Search with",
           "`make logs-grep PAT='regex' ARGS='--session NAME'`; `make logs-list -v` adds mods, build and every tag.",
           "errors: lua = Lua exceptions, assert, CNP = Construction Not Possible, ERROR = ERROR-level lines.",
           "`_crash-<id>`: a crash_dump report whose log is not archived.", ""]
    shown = [e for e in entries if not (e["kind"] == "crash_dump" and e.get("archived_as"))]
    lines, build = [], ""
    for e in shown:
        line = f"- **{e['name']}** {summary(e, mods=False, top_tags=INDEX_TAGS, brief=True)}"
        if e.get("build") and build and e["build"] != build:
            line += f"; NEW BUILD {e['build']}"
        build = e.get("build") or build
        lines.append(line)
    return "\n".join(out + lines[::-1]) + "\n"


def tag_match(e: dict, tag: str) -> bool:
    t = tag.strip("[]").lower()
    if t == "crash":
        return bool(e.get("crashed"))
    if any(t == a.lower() for a in e.get("actions") or {}):
        return True
    if e.get("bench") and t in ("bench", "bench-" + e["bench"].split("-")[0], "bench_" + e["bench"].split("-")[0]):
        return True
    if any(t == u.lower() for u in e.get("user_tags", [])):
        return True
    if t in e["name"].lower().split("_", 2)[-1].split("-"):
        return True
    return any(t == k.lower() for k in e["tags"])


def since_ok(e: dict, since: str | None) -> bool:
    return not since or (e["start"] or "") >= since.replace("T", " ").replace("_", " ")


def resolve(store: Store, name: str) -> dict | Path:
    p = Path(name).expanduser()
    if p.is_file():
        if any(c.isspace() for c in str(p)):  # make splits the printed path on whitespace
            return link(store, "file-" + hashlib.sha256(str(p.resolve()).encode()).hexdigest()[:12], p.resolve())
        return p
    every = [e for e in store.entries() if not e.get("missing")]
    # Aliases prefer the full archive over a crash_dump entry of the same session (its logs are ~800-line tails).
    ents = [e for e in every if not (e["kind"] == "crash_dump" and e.get("archived_as"))]
    if name == "live":
        if store.live and store.live.is_file():
            return link(store, "live", store.live)
        raise SystemExit("No live stdout.txt")
    if name == "last":
        if ents:
            return ents[-1]
    elif name.startswith("last-"):
        hits = [e for e in ents if tag_match(e, name[5:])]
        if hits:
            return hits[-1]
    else:
        for e in every:
            if e["name"] == name:
                return e
        if name.isdigit():
            hits = [e for e in ents if name in e.get("seeds", [])]
            if hits:
                return hits[-1]
        hits = [e for e in ents if e["name"].startswith(name)] or \
               [e for e in ents if e["session_id"] and e["session_id"].startswith(name)]
        if len(hits) == 1:
            return hits[0]
        if len(hits) > 1:
            raise SystemExit(f"'{name}' matches {len(hits)} sessions: " + ", ".join(e["name"] for e in hits[:8]))
    raise SystemExit(f"No archived session matches '{name}' (make logs-list)")


def link(store: Store, name: str, target: Path) -> Path:
    """A space-free symlink under .cache/logs/tmp/ (the userdata path has spaces; make splits on them)."""
    out = store.dir / "tmp" / f"{name}.log"
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.is_symlink() or out.exists():
        out.unlink()
    out.symlink_to(target)
    return out


def readable_path(store: Store, e: dict) -> Path:
    if e["kind"] == "crash_dump":
        if not e["paths"]:
            raise SystemExit(f"{e['name']}: its crash_dump logs are gone")
        return link(store, e["name"], Path(max(e["paths"], key=lambda p: Path(p).stat().st_size)))
    gz = Path(e["paths"][0])
    out = store.dir / "tmp" / f"{e['name']}.log"
    if out.is_symlink() or not out.is_file() or out.stat().st_mtime < gz.stat().st_mtime:
        if out.is_symlink():  # never write through a link (it may point into crash_dump)
            out.unlink()
        with gzip.open(gz, "rb") as f:
            atomic_write(out, f.read())
    return out


def grep(store: Store, pattern: str, tag: str | None = None, since: str | None = None,
         session: str | None = None, context: int = 0, max_hits: int = 200, ignore_case: bool = False,
         out=sys.stdout) -> int:
    rx = re.compile(pattern, re.IGNORECASE if ignore_case else 0)
    if session:
        r = resolve(store, session)
        targets = [({"name": r.name, "kind": "file", "paths": [str(r)]}) if isinstance(r, Path) else r]
    else:
        targets = [e for e in store.entries() if not e.get("missing") and since_ok(e, since)
                   and (not tag or tag_match(e, tag)) and not (e["kind"] == "crash_dump" and e.get("archived_as"))]
    hits = 0
    for e in targets:
        seen: set[str] = set()  # lines of this crash session's earlier files (overlapping tail copies)
        for path in e["paths"]:
            p = Path(path)
            if not p.is_file():
                continue
            cur: set[str] = set()
            before: deque[tuple[int, str]] = deque(maxlen=context)
            after, last_printed = 0, 0
            with open_log(p) as f:
                for i, line in enumerate(f, 1):
                    line = line.rstrip("\r\n")
                    if e["kind"] == "crash_dump":
                        if line in seen:
                            continue
                        cur.add(line)
                    if rx.search(line):
                        if context and last_printed and i - context > last_printed + 1:
                            print("--", file=out)
                        for j, b in before:
                            if j > last_printed:
                                print(f"{e['name']}-{j}- {b}", file=out)
                        print(f"{e['name']}:{i}: {line}", file=out)
                        last_printed, after = i, context
                        before.clear()
                        hits += 1
                        if hits >= max_hits:
                            out.flush()
                            print(f"... stopped after {max_hits} matches (--max)", file=sys.stderr)
                            return hits
                    elif after:
                        print(f"{e['name']}-{i}- {line}", file=out)
                        last_printed, after = i, after - 1
                    else:
                        before.append((i, line))
            seen |= cur
    return hits


# --------------------------------------------------------------------------------------------- CLI

def default_store() -> Store:
    from hubconfig import CACHE_DIR  # noqa: PLC0415
    crash_dir = live = None
    try:
        from hubconfig import userdata  # noqa: PLC0415
        crash_dir = userdata() / "crash_dump"
        live = crash_dir / "stdout.txt"
    except SystemExit as exc:
        print(f"game_logs: userdata not found ({exc}); crash_dump not indexed", file=sys.stderr)
    return Store(CACHE_DIR / "logs", crash_dir, live)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sp = sub.add_parser("save", help="archive the live stdout.txt (and re-index crash_dump)")
    sp.add_argument("--tag", action="append", default=[], help="tag(s) for the session (slug of the name)")
    sp.add_argument("--file", type=Path, help="archive this log copy instead of the live stdout.txt")
    sp.add_argument("--quiet", action="store_true")
    sp.add_argument("--brief", action="store_true", help="print only newly archived sessions (SessionStart hook)")
    sp.add_argument("--show", type=int, default=0, help="then print the newest N index lines")
    lp = sub.add_parser("list", help="print matching sessions")
    lp.add_argument("--tag")
    lp.add_argument("--crash", action="store_true")
    lp.add_argument("--grep")
    lp.add_argument("--since")
    lp.add_argument("--last", type=int)
    lp.add_argument("-v", "--verbose", action="store_true", help="also the mods and every tag")
    gp = sub.add_parser("grep", help="regex search across archived and crash logs")
    gp.add_argument("pattern")
    gp.add_argument("--tag")
    gp.add_argument("--since")
    gp.add_argument("--session")
    gp.add_argument("-C", type=int, default=0, dest="context")
    gp.add_argument("--max", type=int, default=200)
    gp.add_argument("-i", action="store_true", dest="ignore_case")
    pp = sub.add_parser("path", help="readable file for a session name / alias")
    pp.add_argument("names", nargs="+")
    args = ap.parse_args(argv)
    store = default_store()

    if args.cmd == "save":
        src = args.file or store.live
        status, name = "missing", ""
        if src is None or not src.is_file():
            print(f"game_logs: no log at {src}", file=sys.stderr)
        else:
            status, name = store.save(src, [t for t in args.tag if t])
        store.index_crashes(archive=True)
        store.write()
        if args.brief:
            new = [e for e in store.entries() if e["kind"] == "archive" and e["name"] in store.new]
            if new:
                print(f"Game logs newly archived ({store.dir / 'INDEX.md'}; make logs-grep / logs-list):")
            for e in new[-8:]:
                print(f"  {e['name']}  {summary(e, mods=False, top_tags=3, brief=True)}")
            if len(new) > 8:
                print(f"  ... and {len(new) - 8} older")
        elif not args.quiet:
            msg = {"new": "archived", "replaced": "archived (replaces the shorter copy)",
                   "unchanged": "already archived", "older": "archive already holds a longer copy:",
                   "empty": "empty log, nothing archived", "missing": "nothing archived"}[status]
            print(f"{msg} {name}".rstrip() + f"  ({store.dir / 'INDEX.md'})")
            for e in store.entries()[-args.show:] if args.show else []:
                print(f"{e['name']}  {summary(e, mods=False, top_tags=5)}")
        return 0 if status != "missing" or args.quiet or args.brief else 1

    store.index_crashes(archive=True)
    store.write()
    if args.cmd == "list":
        ents = [e for e in store.entries() if since_ok(e, args.since)
                and (args.verbose or not (e["kind"] == "crash_dump" and e.get("archived_as")))
                and (not args.tag or tag_match(e, args.tag)) and (not args.crash or e.get("crashed"))]
        if args.grep:
            g = args.grep.lower()
            ents = [e for e in ents if g in (e["name"] + " " + summary(e, top_tags=99) + " "
                                             + e.get("session_id", "")).lower()]
        if args.last:
            ents = ents[-args.last:]
        for e in ents:
            print(f"{e['name']}  {summary(e, mods=args.verbose, top_tags=99 if args.verbose else 6)}")
        if not ents:
            print("No matching sessions.", file=sys.stderr)
        return 0
    if args.cmd == "grep":
        n = grep(store, args.pattern, args.tag, args.since, args.session, args.context, args.max,
                 args.ignore_case)
        return 0 if n else 1
    if args.cmd == "path":
        joined = " ".join(args.names)  # make passes LOG unquoted: a file path with spaces arrives split
        names = [joined] if len(args.names) > 1 and Path(joined).expanduser().is_file() else args.names
        for nm in names:
            r = resolve(store, nm)
            print(r if isinstance(r, Path) else readable_path(store, r))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main())
