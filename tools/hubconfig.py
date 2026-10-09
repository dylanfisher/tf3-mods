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
CACHE_DIR = ROOT / ".cache"
GAME_CACHE_DIR = CACHE_DIR / "game"

STEAM_APP_ID = "3493540"
_STEAM = Path.home() / "Library/Application Support/Steam"


def _hub_env() -> dict[str, str]:
    env_file = ROOT / ".hub.env"
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

# File types worth extracting for grep: scripts, configs, model/material
# definitions and Teal type definitions. Binary meshes/textures/audio are skipped.
TEXT_SUFFIXES = {
    ".lua", ".tl", ".json", ".mdl", ".mtl", ".con", ".module", ".txt", ".html",
    ".md", ".fs", ".vs", ".gs", ".glsl", ".tesc", ".tese", ".csv",
}


def is_text_resource(name: str) -> bool:
    return Path(name).suffix.lower() in TEXT_SUFFIXES
