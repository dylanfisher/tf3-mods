"""Shared paths for the TF3 mod hub.

Resolution order for each path: environment variable, then `.hub.env` at the
repo root (KEY=VALUE lines, gitignored), then macOS Steam auto-detection.
"""

from __future__ import annotations

import glob
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODS_DIR = ROOT / "mods"
DOCS_DIR = ROOT / "docs"
WIKI_DIR = DOCS_DIR / "wiki"
GAME_DOCS_DIR = DOCS_DIR / "game"


def _main_worktree() -> Path | None:
    """In a linked `git worktree`, the main checkout (its gitignored .cache / .hub.env are reused)."""
    git = ROOT / ".git"
    if git.is_file():
        text = git.read_text().strip()
        if text.startswith("gitdir:"):
            gitdir = Path(text.split(":", 1)[1].strip())  # <main>/.git/worktrees/<name>
            if gitdir.parent.name == "worktrees":
                return gitdir.parent.parent.parent
    return None


_MAIN = _main_worktree()
CACHE_DIR = ROOT / ".cache"
if not CACHE_DIR.is_dir() and _MAIN and (_MAIN / ".cache").is_dir():
    CACHE_DIR = _MAIN / ".cache"
GAME_CACHE_DIR = CACHE_DIR / "game"

STEAM_APP_ID = "3493540"
_STEAM = Path.home() / "Library/Application Support/Steam"


def _hub_env() -> dict[str, str]:
    env_file = ROOT / ".hub.env"
    if not env_file.exists() and _MAIN:
        env_file = _MAIN / ".hub.env"
    values: dict[str, str] = {}
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip().strip('"')
    return values


def _lookup(key: str) -> str | None:
    return os.environ.get(key) or _hub_env().get(key)


def game_install() -> Path:
    value = _lookup("TF3_INSTALL")
    path = Path(value).expanduser() if value else _STEAM / "steamapps/common/Transport Fever 3"
    if not path.is_dir():
        raise SystemExit(f"TF3 install not found at {path}; set TF3_INSTALL in .hub.env")
    return path


def userdata() -> Path:
    value = _lookup("TF3_USERDATA")
    if value:
        path = Path(value).expanduser()
    else:
        matches = sorted(glob.glob(str(_STEAM / "userdata" / "*" / STEAM_APP_ID / "local")))
        if len(matches) != 1:
            raise SystemExit(
                f"Found {len(matches)} TF3 userdata folders; set TF3_USERDATA in .hub.env "
                "(game: Settings > Advanced > Open User Data Folder)"
            )
        path = Path(matches[0])
    if not path.is_dir():
        raise SystemExit(f"TF3 userdata not found at {path}; set TF3_USERDATA in .hub.env")
    return path


def staging_area() -> Path:
    return userdata() / "staging_area"


WIKI_EXAMPLES_CACHE_DIR = CACHE_DIR / "wiki-examples"
SUBSCRIBED_CACHE_DIR = CACHE_DIR / "subscribed"

MODIO_GAME_ID = "10640"


def modio_dir() -> Path:
    """mod.io client data for TF3: subscriptions, downloaded mods, metadata."""
    value = _lookup("TF3_MODIO")
    path = Path(value).expanduser() if value else Path.home() / "Library/Application Support/mod.io"
    if not (path / "common" / MODIO_GAME_ID).is_dir():
        raise SystemExit(f"mod.io data for TF3 not found under {path}; set TF3_MODIO in .hub.env")
    return path


def modio_token() -> str:
    """mod.io personal access token with write scope (https://mod.io/me/access > Personal access tokens).

    MODIO_TOKEN may be the token itself or a 1Password reference (op://vault/item/field), read with `op read`.
    """
    value = _lookup("MODIO_TOKEN")
    if not value:
        raise SystemExit(
            "MODIO_TOKEN not set: create a read+write personal access token at https://mod.io/me/access "
            "and add MODIO_TOKEN=... (or an op://vault/item/field reference) to .hub.env"
        )
    if value.startswith("op://"):
        import subprocess

        try:
            value = subprocess.run(["op", "read", value], capture_output=True, text=True, check=True).stdout.strip()
        except FileNotFoundError:
            raise SystemExit("MODIO_TOKEN is an op:// reference but the 1Password CLI `op` is not installed") from None
        except subprocess.CalledProcessError as e:
            raise SystemExit(f"op read failed for MODIO_TOKEN: {e.stderr.strip()}") from None
    if len(value) == 32 and all(c in "0123456789abcdef" for c in value.lower()):
        raise SystemExit(
            "MODIO_TOKEN looks like a mod.io API key (32 hex chars). API keys are read-only; editing mods needs an "
            "access token (https://mod.io/me/access > Personal access tokens > new token with write scope)"
        )
    return value


def modio_api() -> str:
    """mod.io API base URL; the game-specific host the TF3 client uses for downloads."""
    return (_lookup("MODIO_API") or f"https://g-{MODIO_GAME_ID}.modapi.io/v1").rstrip("/")

# File types worth extracting for grep: scripts, configs, model/material
# definitions and Teal type definitions. Binary meshes/textures/audio are skipped.
TEXT_SUFFIXES = {
    ".lua", ".tl", ".json", ".mdl", ".mtl", ".con", ".module", ".txt", ".html",
    ".md", ".fs", ".vs", ".gs", ".glsl", ".tesc", ".tese", ".csv",
}


def is_text_resource(name: str) -> bool:
    return Path(name).suffix.lower() in TEXT_SUFFIXES
