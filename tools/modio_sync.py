# /// script
# requires-python = ">=3.11"
# ///
"""Sync a published mod's mod.io profile (everything around the modfile) from the repo.

The Mod Hub still uploads the modfile itself: it validates, cooks and writes the metadata_blob the
game reads (buildVersion, level, ...), so this tool never touches files. It brings these in line:

  text     name + summary (modinfo.json), description (_metadata/description.html, else modinfo's)
  tags     modinfo tags missing on mod.io are added; extra ones are only reported (--prune-tags removes)
  logo     _metadata/0.png
  gallery  _metadata/1.png, 2.png, ... replaces the whole gallery (mod.io `sync`), uploaded as N-<hash>.png
           so a changed slide gets a new URL (a re-used name kept showing the old picture from caches)

Dry run by default; --apply makes the changes. Mods are matched to mod.io by the id the Hub writes to
_metadata/mod.io_fileid.txt. Images can't be compared through the API (only URLs), so the state file
branding/modio_state.json records what was last synced; without a record the remote originals are
downloaded once and compared byte for byte.

Auth: MODIO_TOKEN (personal access token with write scope, https://mod.io/me/access) in .hub.env.

--release (make modio-status) instead downloads each live modfile (cached by modfile id in .cache/modio/modfiles/)
and compares it with the local folder: the live mod.json revision vs the local one, and the changed files. That
tells which mods need a Hub update, and which changed without a revision bump.

Usage: uv run tools/modio_sync.py [--apply] [--only text,tags,logo,gallery] [--force] [mods/<id> ...]
       uv run tools/modio_sync.py --release [--verbose] [--all] [mods/<id> ...]

--release skips the Towns & Streets mods (square_names_us_*) and Blank Slate unless they are named or --all is
given: they rarely change and add a modfile download each.
"""

from __future__ import annotations

import argparse
import datetime
import difflib
import hashlib
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import CACHE_DIR, MODIO_GAME_ID, MODS_DIR, ROOT, modio_api, modio_token  # noqa: E402

STATE_FILE = ROOT / "branding" / "modio_state.json"
MODFILE_CACHE = CACHE_DIR / "modio" / "modfiles"  # live modfile zips, by modfile id
# mod.io's Cloudflare rejects urllib's default "Python-urllib/x.y" agent (error 1010).
USER_AGENT = "square-tf3-mods-modio-sync/1.0"
ID_FILE = "mod.io_fileid.txt"
PARTS = ("text", "tags", "logo", "gallery")
TEXT_FIELDS = ("name", "summary", "description")


def sha(data: bytes | str) -> str:
    return hashlib.sha256(data.encode() if isinstance(data, str) else data).hexdigest()[:16]


# ---------------------------------------------------------------------------- local side


@dataclass
class Local:
    path: Path
    mod_id: str
    modio_id: int
    text: dict[str, str]
    tags: list[str]
    logo: Path | None
    images: list[Path]  # 1-<hash>.png (or 1.png), 2-..., ... in order


SLIDE_RE = re.compile(r"^(\d+)(?:-[0-9a-f]{8})?$")  # N.png, or N-<hash>.png as make shots writes them


def slide_name(path: Path) -> str:
    """The N.png a local slide stands for: 1.png and 1-0a1b2c3d.png both give 1.png."""
    return f"{int(SLIDE_RE.match(path.stem).group(1))}.png"


def gallery_files(meta: Path) -> list[Path]:
    numbered = [p for p in meta.glob("*.png") if SLIDE_RE.match(p.stem) and slide_name(p) != "0.png"]
    return sorted(numbered, key=lambda p: int(slide_name(p)[:-4]))


def load_local(mod_dir: Path) -> Local | None:
    meta = mod_dir / "_metadata"
    id_file = meta / ID_FILE
    if not id_file.is_file():
        return None
    info = json.loads((meta / "modinfo.json").read_text(encoding="utf-8"))
    desc_html = meta / "description.html"
    description = desc_html.read_text(encoding="utf-8") if desc_html.is_file() else info.get("description", "")
    logo = meta / "0.png"
    return Local(
        path=mod_dir,
        mod_id=mod_dir.name,
        modio_id=int(id_file.read_text().strip()),
        text={"name": info.get("name", ""), "summary": info.get("summary", ""), "description": description},
        tags=list(info.get("tags", [])),
        logo=logo if logo.is_file() else None,
        images=gallery_files(meta),
    )


# ---------------------------------------------------------------------------- mod.io API


class ApiError(Exception):
    pass


RATE_LIMIT_REFS = {
    11008: "global limit: every request is blocked until it clears",
    11009: "this endpoint only: other requests still work",
}


def rate_limit_info(method: str, path: str, headers, raw: bytes, attempt: int = 0) -> tuple[int, list[str]]:
    """Seconds to wait and what mod.io said about a 429 (docs.mod.io/restapi/rate-limiting: retry-after in
    seconds, 0 = rolling limit, retry after 60 s; error_ref 11008 global, 11009 per endpoint). A rolling limit
    backs off 60, 120, 240 ... s (max 10 min): retrying every minute can keep it from clearing."""
    retry = (headers.get("retry-after") or "").strip()
    try:
        wait = int(retry or 0)
    except ValueError:
        wait = 0
    endpoint = re.sub(r"/games/\d+/mods/\d+", "", path.split("?")[0]) or "/"
    lines = [f"endpoint: {method} {endpoint}"]
    lines.append(f"retry-after: {retry or '(none)'}" + (" = rolling limit (mod.io advises at least 60 s)" if wait <= 0 else " s"))
    try:
        err = json.loads(raw)["error"]
        ref = err.get("error_ref")
        lines.append(f"error_ref {ref}: {RATE_LIMIT_REFS.get(ref, 'not in the docs')}")
        if err.get("message"):
            lines.append(f"message: {err['message']}")
    except (ValueError, KeyError, TypeError):
        pass
    extra = [f"{k}: {v}" for k, v in headers.items() if "ratelimit" in k.lower() or "rate-limit" in k.lower()]
    return (wait if wait > 0 else min(600, 60 * 2 ** attempt)), lines + extra


def _multipart(fields: list[tuple[str, str]], files: list[tuple[str, str, bytes]]) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    out = bytearray()
    for name, value in fields:
        out += f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        out += value.encode() + b"\r\n"
    for name, filename, data in files:
        out += (
            f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"; filename="{filename}"\r\n'
            f"Content-Type: image/png\r\n\r\n"
        ).encode()
        out += data + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return bytes(out), f"multipart/form-data; boundary={boundary}"


class Api:
    WRITE_GAP = 1.1  # seconds between writes: mod.io allows a user token 60 writes per minute

    def __init__(self, base: str, token: str):
        self.base = base
        self.token = token
        self.last_write = 0.0

    def _request(self, method: str, path: str, body: bytes | None = None, ctype: str | None = None,
                 extra: dict[str, str] | None = None):
        url = path if path.startswith("http") else f"{self.base}{path}"
        headers = {"Authorization": f"Bearer {self.token}", "Accept": "application/json", "User-Agent": USER_AGENT}
        headers.update(extra or {})
        if ctype:
            headers["Content-Type"] = ctype
        if method != "GET":
            time.sleep(max(0.0, self.last_write + self.WRITE_GAP - time.monotonic()))
            self.last_write = time.monotonic()
        tries = 6  # rolling-limit waits 60, 120, 240, 480, 600 s: about 25 min in all
        for attempt in range(tries):
            req = urllib.request.Request(url, data=body, method=method, headers=headers)
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    raw = resp.read()
                    return json.loads(raw) if raw and "json" in resp.headers.get("Content-Type", "") else raw
            except urllib.error.HTTPError as e:
                raw = e.read()
                if e.code == 429 and attempt < tries - 1:
                    # mod.io: retry-after in seconds; 0 means a rolling limit, retry after 60 s
                    # (docs.mod.io/restapi/rate-limiting). User tokens: 120 requests, 60 writes per minute.
                    wait, lines = rate_limit_info(method, path, e.headers, raw, attempt)
                    print(f"    rate limited by mod.io, waiting {wait}s (try {attempt + 2} of {tries})", flush=True)
                    for line in lines:
                        print(f"      {line}", flush=True)
                    time.sleep(wait)
                    continue
                try:
                    err = json.loads(raw)["error"]
                    detail = err.get("message", "")
                    if err.get("errors"):
                        detail += " " + json.dumps(err["errors"])
                    raise ApiError(f"{method} {path}: HTTP {e.code} (ref {err.get('error_ref')}) {detail}") from None
                except (ValueError, KeyError, TypeError):
                    raise ApiError(f"{method} {path}: HTTP {e.code} {raw[:300]!r}") from None
        raise ApiError(f"{method} {path}: still rate limited")

    def get(self, path: str, headers: dict[str, str] | None = None):
        return self._request("GET", path, extra=headers)

    def form(self, method: str, path: str, fields: list[tuple[str, str]]):
        body = urllib.parse.urlencode(fields).encode()
        return self._request(method, path, body, "application/x-www-form-urlencoded")

    def multipart(self, path: str, fields: list[tuple[str, str]], files: list[tuple[str, str, bytes]]):
        body, ctype = _multipart(fields, files)
        return self._request("POST", path, body, ctype)

    def download(self, url: str, auth: bool = False) -> bytes:
        headers = {"User-Agent": USER_AGENT}
        if auth:
            headers["Authorization"] = f"Bearer {self.token}"
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=300) as resp:
            return resp.read()


# ---------------------------------------------------------------------------- planning


@dataclass
class Plan:
    text: dict[str, str] = field(default_factory=dict)  # field -> new value
    tags_add: list[str] = field(default_factory=list)
    tags_extra: list[str] = field(default_factory=list)
    logo: bool = False
    gallery: bool = False
    notes: list[str] = field(default_factory=list)

    def empty(self, prune_tags: bool) -> bool:
        return not (self.text or self.tags_add or self.logo or self.gallery or (prune_tags and self.tags_extra))


def norm(text: str) -> str:
    """mod.io drops the final newline (and may change line ends); only the content counts."""
    return "\n".join(line.rstrip() for line in text.replace("\r\n", "\n").strip().split("\n"))


def text_in_sync(local: str, remote: str, recorded: list[str] | None) -> bool:
    """Equal, or unchanged since the last sync (mod.io may rewrite HTML, so the pair of hashes counts)."""
    return norm(local) == norm(remote) or recorded == [sha(norm(local)), sha(norm(remote))]


def remote_text(remote: dict, f: str) -> str:
    """mod.io returns name and summary HTML-escaped ("&" as "&amp;"); the description is HTML anyway."""
    value = remote.get(f) or ""
    return value if f == "description" else html.unescape(value)


def base_name(remote_filename: str) -> str:
    """The local N.png a remote image stands for. Uploads are named N-<hash>.png (upload_name), and mod.io keeps
    names unique by adding a counter (a second "1.png" is stored as "1.1.png")."""
    m = re.match(r"^(\d+)(?:-[0-9a-f]{8})?(?:\.\d+)?\.png$", remote_filename)
    return f"{int(m.group(1))}.png" if m else remote_filename


def upload_name(path: Path) -> str:
    """N-<content hash>.png: a changed image gets a new name, so a new URL. Re-using "1.png" kept serving the old
    picture from caches (Better Minimap, 2026-10-10)."""
    m = SLIDE_RE.match(path.stem)
    stem = m.group(1) if m else path.stem  # keeps make shots' zero padding (02-...), the name the Hub uploads too
    return f"{stem}-{sha(path.read_bytes())[:8]}{path.suffix}"


def remote_matches(entries: list[tuple[Path, str, str]], recorded: list[dict] | None, fetch) -> bool:
    """entries: (local file, remote filename, remote url). In sync if the record says this exact local file
    went to this remote filename, else if the remote original is byte-identical (fetch(url) -> bytes)."""
    rec = {r["remote"]: r["sha"] for r in recorded or []}
    for path, remote_name, url in entries:
        data = path.read_bytes()
        if rec.get(remote_name) == sha(data):
            continue
        try:
            if fetch(url) != data:
                return False
        except (urllib.error.URLError, OSError):
            return False
    return True


def make_plan(local: Local, remote: dict, state: dict, parts: set[str], force: bool, fetch) -> Plan:
    plan = Plan()
    if "text" in parts:
        for f in TEXT_FIELDS:
            if not text_in_sync(local.text[f], remote_text(remote, f), state.get("text", {}).get(f)):
                plan.text[f] = local.text[f]
    if "tags" in parts:
        have = [t["name"] for t in remote.get("tags", [])]
        plan.tags_add = [t for t in local.tags if t not in have]
        plan.tags_extra = [t for t in have if t not in local.tags]
    if "logo" in parts and local.logo:
        logo = remote.get("logo") or {}
        recorded = [state["logo"]] if state.get("logo") else None
        plan.logo = force or not logo.get("filename") or not remote_matches(
            [(local.logo, logo["filename"], logo.get("original", ""))], recorded, fetch)
    if "gallery" in parts:
        images = (remote.get("media") or {}).get("images", [])
        names = [base_name(i["filename"]) for i in images]
        wanted = [slide_name(p) for p in local.images]
        if force:
            plan.gallery = True
        elif not wanted and names and set(names) == {"0.png"}:
            pass  # no slides: the Hub puts the cover in the gallery on every upload; leave it
        elif names != wanted:
            plan.gallery = True
            shown = ", ".join(i["filename"] for i in images) or "(empty)"
            plan.notes.append(f"gallery on mod.io: {shown}; local: {', '.join(wanted) or '(none)'}")
        else:
            entries = [(p, i["filename"], i["original"]) for p, i in zip(local.images, images)]
            plan.gallery = not remote_matches(entries, state.get("images"), fetch)
            if plan.gallery:
                plan.notes.append("gallery images differ from the local slides")
    return plan


# ---------------------------------------------------------------------------- applying


def apply_plan(api: Api, local: Local, plan: Plan, prune_tags: bool) -> None:
    mod = f"/games/{MODIO_GAME_ID}/mods/{local.modio_id}"
    if plan.text:
        api.multipart(mod, list(plan.text.items()), [])
    if plan.tags_add:
        api.form("POST", f"{mod}/tags", [("tags[]", t) for t in plan.tags_add])
    if prune_tags and plan.tags_extra:
        api.form("DELETE", f"{mod}/tags", [("tags[]", t) for t in plan.tags_extra])
    if plan.logo and local.logo:
        api.multipart(f"{mod}/media", [], [("logo", upload_name(local.logo), local.logo.read_bytes())])
    if plan.gallery:
        if local.images:
            files = [(f"image{i}", upload_name(p), p.read_bytes()) for i, p in enumerate(local.images, 1)]
            api.multipart(f"{mod}/media", [("sync", "true")], files)
        else:
            current = (api.get(mod).get("media") or {}).get("images", [])
            if current:
                api.form("DELETE", f"{mod}/media", [("images[]", i["filename"]) for i in current])
        # Uploads may land out of order; put them back in 1, 2, 3 order.
        names = [i["filename"] for i in (api.get(mod).get("media") or {}).get("images", [])]
        wanted = [slide_name(p) for p in local.images]
        by_base = {base_name(n): n for n in names}
        if [base_name(n) for n in names] != wanted and sorted(by_base) == sorted(wanted) and len(by_base) == len(names):
            api.form("PUT", f"{mod}/media/reorder", [("images[]", by_base[w]) for w in wanted])


def record_state(local: Local, remote: dict, parts: set[str], state: dict) -> dict:
    """What is in sync now (call with the mod as re-read after applying)."""
    entry = dict(state)
    entry["modioId"] = local.modio_id
    if "text" in parts:
        entry["text"] = {f: [sha(norm(local.text[f])), sha(norm(remote_text(remote, f)))] for f in TEXT_FIELDS}
    if "logo" in parts and local.logo and (remote.get("logo") or {}).get("filename"):
        entry["logo"] = {"file": local.logo.name, "sha": sha(local.logo.read_bytes()), "remote": remote["logo"]["filename"]}
    if "gallery" in parts:
        images = (remote.get("media") or {}).get("images", [])
        if [base_name(i["filename"]) for i in images] == [slide_name(p) for p in local.images]:
            entry["images"] = [
                {"file": slide_name(p), "sha": sha(p.read_bytes()), "remote": i["filename"]} for p, i in zip(local.images, images)
            ]
    if {k: v for k, v in entry.items() if k != "synced"} != {k: v for k, v in state.items() if k != "synced"}:
        entry["synced"] = datetime.date.today().isoformat()
    return entry


# ---------------------------------------------------------------------------- main


def text_diff(local: Local, remote: dict, f: str, limit: int = 60) -> list[str]:
    old = remote_text(remote, f).splitlines()
    new = local.text[f].splitlines()
    lines = list(difflib.unified_diff(old, new, "mod.io", "local", n=1, lineterm=""))
    if len(lines) > limit:
        lines = lines[:limit] + [f"... {len(lines) - limit} more diff lines"]
    return lines


def describe(plan: Plan, prune_tags: bool) -> list[str]:
    lines = []
    for f, value in plan.text.items():
        lines.append(f"text: update {f} -> {value[:90]!r}" if f != "description" else f"text: update description ({len(value)} chars)")
    if plan.tags_add:
        lines.append(f"tags: add {plan.tags_add}")
    if plan.tags_extra:
        lines.append(f"tags: {'remove' if prune_tags else 'extra on mod.io (kept; --prune-tags removes)'} {plan.tags_extra}")
    if plan.logo:
        lines.append("logo: upload 0.png")
    if plan.gallery:
        lines.append("gallery: replace with the local slides")
    return lines + [f"  ({n})" for n in plan.notes]


# ---------------------------------------------------------------------------- release check (--release)

# Not part of a release: written by the Hub after upload, or synced through the API by this tool.
PROFILE_ONLY = ("_metadata/mod.io_fileid.txt",)
SKIP_NAMES = {".DS_Store", "Thumbs.db"}


def is_profile_file(rel: str) -> bool:
    """Files make modio pushes (cover, slides, texts) that need no Hub update on their own."""
    return rel.startswith("_metadata/") and (rel.endswith(".png") or rel.endswith((".html", "modinfo.json")))


def file_key(rel: str, data: bytes) -> str:
    """mod.json is compared parsed, in case the Hub rewrites its formatting."""
    if rel == "mod.json":
        try:
            return sha(json.dumps(json.loads(data), sort_keys=True))
        except ValueError:
            pass
    return sha(data)


def local_files(mod_dir: Path) -> dict[str, str]:
    out = {}
    for p in sorted(mod_dir.rglob("*")):
        rel = p.relative_to(mod_dir).as_posix()
        if p.is_file() and p.name not in SKIP_NAMES and rel not in PROFILE_ONLY:
            out[rel] = file_key(rel, p.read_bytes())
    return out


def zip_files(zpath: Path) -> tuple[dict[str, str], dict]:
    """Files of a modfile zip relative to its mod.json, and that mod.json parsed."""
    with zipfile.ZipFile(zpath) as z:
        names = [n for n in z.namelist() if not n.endswith("/")]
        roots = sorted((n for n in names if n == "mod.json" or n.endswith("/mod.json")), key=len)
        if not roots:
            raise ApiError(f"{zpath.name}: no mod.json in the modfile")
        prefix = roots[0][: -len("mod.json")]
        out = {}
        for n in names:
            rel = n[len(prefix):]
            if n.startswith(prefix) and Path(rel).name not in SKIP_NAMES and rel not in PROFILE_ONLY:
                out[rel] = file_key(rel, z.read(n))
        return out, json.loads(z.read(roots[0]))


@dataclass
class Release:
    live_rev: object
    local_rev: object
    changed: list[str]       # differ between the upload and the local folder
    added: list[str]         # only local
    removed: list[str]       # only in the upload (deleted locally, or made by the Hub's cooking)
    profile: list[str]       # changed _metadata files make modio covers



def compare_release(local: dict[str, str], live: dict[str, str], live_rev, local_rev) -> Release:
    changed, profile = [], []
    for rel in sorted(set(local) | set(live)):
        if local.get(rel) == live.get(rel) or rel not in local:
            continue
        (profile if is_profile_file(rel) else changed).append(rel)
    added = [r for r in changed if r not in live]
    changed = [r for r in changed if r in live]
    removed = sorted(r for r in live if r not in local)
    return Release(live_rev, local_rev, changed, added, removed, profile)


PLATFORM_PREFERENCE = ("mac", "windows", "linux")


def live_modfile_id(remote: dict) -> tuple[int | None, str | None]:
    """TF3 has cross-platform moderation: the mod's `modfile` is empty unless a platform is named, and the
    live file per platform is in `platforms[].modfile_live`. Prefer the desktop builds."""
    live = {p.get("platform"): p.get("modfile_live") for p in remote.get("platforms") or [] if p.get("modfile_live")}
    for platform in PLATFORM_PREFERENCE + tuple(sorted(live)):
        if live.get(platform):
            return live[platform], platform
    mf = remote.get("modfile") or {}
    return mf.get("id"), None


def newest_modfile_id(api: Api, remote: dict) -> int | None:
    files = api.get(f"/games/{MODIO_GAME_ID}/mods/{remote['id']}/files?_sort=-date_added&_limit=1").get("data") or []
    return files[0]["id"] if files else None


def live_modfile(api: Api, remote: dict, mf_id: int | None = None) -> tuple[Path, dict]:
    """The live modfile (or the one with id mf_id) as a cached zip, plus its modfile object."""
    platform = None
    if mf_id is None:
        mf_id, platform = live_modfile_id(remote)
    if not mf_id:
        # Fallback: the newest upload (may not be approved/live yet). Quiet, to keep the table readable.
        mf_id = newest_modfile_id(api, remote)
        if not mf_id:
            raise ApiError("no modfile on mod.io")
    headers = {"X-Modio-Platform": platform} if platform else None
    mf = api.get(f"/games/{MODIO_GAME_ID}/mods/{remote['id']}/files/{mf_id}", headers)
    zpath = MODFILE_CACHE / f"{mf['id']}.zip"
    if not zpath.is_file():
        zpath.parent.mkdir(parents=True, exist_ok=True)
        url = (mf.get("download") or {}).get("binary_url", "")
        try:
            data = api.download(url)
        except urllib.error.HTTPError:
            data = api.download(url, auth=True)
        tmp = zpath.with_suffix(".part")
        tmp.write_bytes(data)
        tmp.rename(zpath)
    return zpath, mf


@dataclass
class ReleaseRow:
    mod_id: str
    uploaded: str = ""
    rel: Release | None = None
    error: str = ""
    pending: bool = False  # a newer upload matches the local folder but mod.io hasn't made it live yet

    @property
    def status(self) -> str:
        if self.error:
            return "error"
        if not (self.rel.changed or self.rel.added):
            return "ok"
        if self.pending:
            return "pending"
        return "update" if self.rel.local_rev != self.rel.live_rev else "bump"


def release_check(api: Api, loc: Local) -> ReleaseRow:
    """Compare the local folder with the live upload."""
    remote = api.get(f"/games/{MODIO_GAME_ID}/mods/{loc.modio_id}")
    zpath, mf = live_modfile(api, remote)
    live, live_mod_json = zip_files(zpath)
    local_rev = json.loads((loc.path / "mod.json").read_text(encoding="utf-8")).get("revision")
    files = local_files(loc.path)
    rel = compare_release(files, live, live_mod_json.get("revision"), local_rev)
    uploaded = datetime.date.fromtimestamp(mf.get("date_added", 0)).isoformat()
    row = ReleaseRow(loc.mod_id, uploaded, rel)
    if rel.changed or rel.added:
        # mod.io scans (and per platform approves) a new upload before it goes live: check the newest one too.
        newest = newest_modfile_id(api, remote)
        if newest and newest != mf.get("id"):
            npath, nmf = live_modfile(api, remote, newest)
            nfiles, n_mod_json = zip_files(npath)
            nrel = compare_release(files, nfiles, n_mod_json.get("revision"), local_rev)
            if not (nrel.changed or nrel.added):
                row.pending = True
                row.uploaded = datetime.date.fromtimestamp(nmf.get("date_added", 0)).isoformat()
    return row


def render_release(rows: list[ReleaseRow], verbose: bool, color: bool) -> list[str]:
    """Rows grouped by status as a table: what to upload through the Hub, what to bump first, what's current."""
    def c(code: str, text: str) -> str:
        return f"\033[{code}m{text}\033[0m" if color else text

    groups = [
        ("update", "Needs a Hub update", "33", "upload these in Mod Hub > My Mods"),
        ("bump", "Changed, revision not bumped", "31", "bump revision + changelog entry, then Hub update"),
        ("pending", "Uploaded, waiting for mod.io", "36", "the new upload matches; mod.io makes it live after its scan"),
        ("error", "Could not check", "31", ""),
        ("ok", "Up to date", "32", ""),
    ]
    width = max([len(r.mod_id) for r in rows] + [3])
    out: list[str] = []
    for key, title, code, hint in groups:
        members = [r for r in rows if r.status == key]
        if not members:
            continue
        if out:
            out.append("")
        out.append(c("1;" + code, f"{title} ({len(members)})") + (c("2", f"  {hint}") if hint else ""))
        if key == "ok" and not verbose:
            out.append("  " + ", ".join(r.mod_id for r in members))
            continue
        if key == "error":
            out += [f"  {r.mod_id.ljust(width)}  {r.error}" for r in members]
            continue
        out.append(c("2", f"  {'MOD'.ljust(width)}  {'REVISION':<10} {'UPLOADED':<11} CHANGES"))
        for r in members:
            rel = r.rel
            revision = f"{rel.live_rev} -> {rel.local_rev}" if rel.live_rev != rel.local_rev else str(rel.local_rev)
            changes = ", ".join(x for x in (
                f"{len(rel.changed)} changed" if rel.changed else "",
                f"{len(rel.added)} new" if rel.added else "") if x) or "-"
            out.append(f"  {r.mod_id.ljust(width)}  {revision:<10} {r.uploaded:<11} {changes}")
            if verbose:
                for label, items in (("changed", rel.changed), ("new", rel.added), ("profile", rel.profile),
                                     ("only in upload", rel.removed)):
                    if items:
                        out.append(c("2", f"  {'':{width}}    {label}: {', '.join(items)}"))
    due = sum(r.status in ("update", "bump") for r in rows)
    out += ["", c("1", f"{due} of {len(rows)} mod(s) need a Hub update.")]
    return out


# Mods --release leaves out unless named or --all: they rarely change.
RELEASE_QUIET_PREFIXES = ("square_names_us_",)
RELEASE_QUIET_IDS = {"square_blank_slate"}


def is_release_quiet(mod_id: str) -> bool:
    return mod_id in RELEASE_QUIET_IDS or mod_id.startswith(RELEASE_QUIET_PREFIXES)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mods", nargs="*", type=Path, help="mods/<id> folders (default: every mod with a mod.io id)")
    ap.add_argument("--apply", action="store_true", help="make the changes (default: dry run)")
    ap.add_argument("--only", default=",".join(PARTS), help=f"comma list of {','.join(PARTS)}")
    ap.add_argument("--force", action="store_true", help="re-upload logo and gallery even if they look in sync")
    ap.add_argument("--verify", action="store_true",
                    help="compare logo and gallery bytes with mod.io's originals instead of trusting the sync record")
    ap.add_argument("--diff", action="store_true", help="show a line diff (mod.io -> local) for changed text fields")
    ap.add_argument("--release", action="store_true",
                    help="instead: compare each mod with its live upload and list the ones needing a Hub update")
    ap.add_argument("--verbose", action="store_true", help="--release: list every file, incl. ones only in the upload")
    ap.add_argument("--all", action="store_true",
                    help="--release: also check the Towns & Streets mods and Blank Slate (skipped by default)")
    ap.add_argument("--prune-tags", action="store_true", help="remove mod.io tags that modinfo.json doesn't list")
    args = ap.parse_args()

    parts = {p.strip() for p in args.only.split(",") if p.strip()}
    if bad := parts - set(PARTS):
        raise SystemExit(f"unknown --only part(s): {', '.join(sorted(bad))}")

    dirs = [ROOT / m for m in args.mods] if args.mods else sorted(p for p in MODS_DIR.iterdir() if p.is_dir())
    locals_ = []
    quiet_skipped = 0
    for d in dirs:
        if args.release and not args.mods and not args.all and is_release_quiet(d.name):
            quiet_skipped += 1
            continue
        if d.name.startswith("square_opt_"):
            if args.mods:
                print(f"{d.name}: local fork of another author's mod, never published; skipped")
            continue
        loc = load_local(d)
        if loc is None:
            if args.mods:
                print(f"{d.name}: no _metadata/{ID_FILE} (not published through the Mod Hub yet); skipped")
            continue
        locals_.append(loc)
    if not locals_:
        return

    api = Api(modio_api(), modio_token())
    if args.release:
        rows = []
        tty = sys.stdout.isatty()
        for i, loc in enumerate(locals_, 1):
            if tty:
                print(f"\rchecking {i}/{len(locals_)} {loc.mod_id:<50}", end="", flush=True)
            try:
                rows.append(release_check(api, loc))
            except (ApiError, urllib.error.URLError, zipfile.BadZipFile) as e:
                rows.append(ReleaseRow(loc.mod_id, error=str(e)))
        if tty:
            print("\r\033[K", end="")
        print("\n".join(render_release(rows, args.verbose, tty)))
        if quiet_skipped:
            print(f"\n{quiet_skipped} Towns & Streets / Blank Slate mods not checked (--all or MOD=mods/<id> to include)")
        return
    state = json.loads(STATE_FILE.read_text()) if STATE_FILE.is_file() else {}
    before = json.dumps(state, sort_keys=True)
    changed = failed = 0
    for loc in locals_:
        try:
            remote = api.get(f"/games/{MODIO_GAME_ID}/mods/{loc.modio_id}")
            entry = state.get(loc.mod_id, {})
            if entry.get("modioId") not in (None, loc.modio_id):
                entry = {}
            plan = make_plan(loc, remote, {k: v for k, v in entry.items() if k not in ("logo", "images")} if args.verify else entry,
                             parts, args.force, api.download)
            if plan.empty(args.prune_tags):
                print(f"{loc.mod_id} ({loc.modio_id}): in sync")
                state[loc.mod_id] = record_state(loc, remote, parts, entry)
                continue
            changed += 1
            print(f"{loc.mod_id} ({loc.modio_id}):")
            for line in describe(plan, args.prune_tags):
                print(f"  {line}")
            if args.diff:
                for f in plan.text:
                    print(f"  --- {f} diff:")
                    for line in text_diff(loc, remote, f):
                        print(f"    {line}")
            if args.apply:
                apply_plan(api, loc, plan, args.prune_tags)
                remote = api.get(f"/games/{MODIO_GAME_ID}/mods/{loc.modio_id}")
                state[loc.mod_id] = record_state(loc, remote, parts, entry)
                print("  done")
        except ApiError as e:
            failed += 1
            print(f"{loc.mod_id} ({loc.modio_id}): ERROR {e}")

    if json.dumps(state, sort_keys=True) != before:
        STATE_FILE.write_text(json.dumps(dict(sorted(state.items())), indent=2) + "\n")
    if changed and not args.apply:
        print(f"\n{changed} mod(s) out of sync. Rerun with ARGS=--apply to update mod.io.")
    if failed:
        raise SystemExit(f"{failed} mod(s) failed")


if __name__ == "__main__":
    main()
