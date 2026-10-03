# /// script
# requires-python = ">=3.11"
# dependencies = ["beautifulsoup4>=4.12", "markdownify>=0.13"]
# ///
"""Mirror the Transport Fever 3 wiki modding manual into docs/wiki/ as Markdown.

Discovers pages by crawling links and the DokuWiki sitemap starting from
modding:start, fetches each page's clean XHTML export, converts it to Markdown,
downloads attached media, and rewrites links to point at the local copies.
Every run regenerates docs/wiki/ from scratch, so stale pages disappear.

Usage: uv run tools/sync_wiki.py [--no-media] [--namespace modding]
"""

from __future__ import annotations

import argparse
import re
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from collections import deque
from pathlib import Path

from bs4 import BeautifulSoup, Tag
from markdownify import MarkdownConverter

sys.path.insert(0, str(Path(__file__).parent))
from hubconfig import WIKI_DIR, WIKI_EXAMPLES_CACHE_DIR, is_text_resource  # noqa: E402

BASE = "https://wiki.transportfever3.com"
USER_AGENT = "tf3-mods-doc-sync/1.0 (local documentation mirror)"
REQUEST_DELAY = 0.2  # seconds between requests, to be polite to the wiki
MEDIA_DIR_NAME = "_media"
# Wiki-maintenance pages that are not documentation.
SKIP_PAGES = re.compile(r"^modding:(linkcheck|sidebar)(:|$)")


def fetch(url: str, retries: int = 3) -> bytes:
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = resp.read()
            time.sleep(REQUEST_DELAY)
            return data
        except (urllib.error.URLError, TimeoutError) as exc:
            if attempt == retries - 1:
                raise
            print(f"  retry {url}: {exc}", file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    raise AssertionError("unreachable")


def page_path(page_id: str) -> Path:
    """modding:general:moddefinition -> modding/general/moddefinition.md"""
    return Path(*page_id.split(":")).with_suffix(".md")


def media_path(media_id: str) -> Path:
    return Path(MEDIA_DIR_NAME, *media_id.split(":"))


def rel(target: Path, from_page: Path) -> str:
    return Path(*([".."] * (len(from_page.parts) - 1)), target).as_posix()


def query_param(href: str, key: str) -> str | None:
    values = urllib.parse.parse_qs(urllib.parse.urlparse(href).query).get(key)
    return values[0] if values else None


def is_wiki_url(href: str) -> bool:
    parsed = urllib.parse.urlparse(href)
    return parsed.netloc in ("", urllib.parse.urlparse(BASE).netloc)


def page_id_of(href: str) -> str | None:
    if not is_wiki_url(href) or "doku.php" not in href:
        return None
    page_id = query_param(href, "id")
    if not page_id or query_param(href, "do") not in (None, "show"):
        return None
    return page_id.lower().lstrip(":")


def media_id_of(href: str) -> str | None:
    if not is_wiki_url(href):
        return None
    if "fetch.php" in href or "detail.php" in href:
        media = query_param(href, "media")
        return media.lstrip(":") if media else None
    match = re.match(r"^/_media/(.+)$", urllib.parse.urlparse(href).path)
    return match.group(1).replace("/", ":") if match else None


def in_namespace(page_id: str, namespace: str) -> bool:
    return page_id == namespace or page_id.startswith(namespace + ":")


class WikiConverter(MarkdownConverter):
    def convert_pre(self, el, text, parent_tags=None, **kwargs):
        classes = el.get("class") or []
        lang = next((c for c in classes if c != "code"), "") if "code" in classes else ""
        code = el.get_text().rstrip("\n")
        return f"\n\n```{lang}\n{code}\n```\n\n"


def clean_body(soup: BeautifulSoup) -> Tag:
    body = soup.body or soup
    for selector in ["script", "style", "#dw__toc", ".secedit", ".editbutton_section"]:
        for el in body.select(selector):
            el.decompose()
    for box in body.select("div.admonition"):
        kind = next((c for c in box.get("class", []) if c not in ("admonition", "plugin_wrap")), "note")
        quote = soup.new_tag("blockquote")
        label = soup.new_tag("p")
        strong = soup.new_tag("strong")
        strong.string = f"{kind.capitalize()}:"
        label.append(strong)
        quote.append(label)
        for child in list(box.children):
            quote.append(child.extract())
        box.replace_with(quote)
    return body


def convert_page(page_id: str, html: bytes, media_ids: set[str]) -> tuple[str, str, set[str]]:
    soup = BeautifulSoup(html, "html.parser")
    body = clean_body(soup)
    here = page_path(page_id)
    links: set[str] = set()

    for img in body.find_all("img"):
        media = media_id_of(img.get("src", ""))
        if media:
            media_ids.add(media)
            img["src"] = rel(media_path(media), here)
        parent = img.parent
        if parent and parent.name == "a" and media_id_of(parent.get("href", "")):
            parent.replace_with(img)

    for a in body.find_all("a", href=True):
        del a["title"]
        href = a["href"]
        target_page = a.get("data-wiki-id") or page_id_of(href)
        media = media_id_of(href)
        if target_page:
            target_page = target_page.lower()
            links.add(target_page)
            anchor = urllib.parse.urlparse(href).fragment
            a["href"] = f"wiki:{target_page}" + (f"#{anchor}" if anchor else "")
        elif media:
            media_ids.add(media)
            a["href"] = rel(media_path(media), here)
        elif href.startswith("/"):
            a["href"] = BASE + href

    title_el = body.find(["h1", "h2"])
    title = title_el.get_text(strip=True) if title_el else page_id
    markdown = WikiConverter(heading_style="ATX", bullets="-", escape_underscores=False).convert_soup(body)
    markdown = re.sub(r"\n{3,}", "\n\n", markdown).strip() + "\n"
    return title, markdown, links


def is_placeholder(title: str, markdown: str) -> bool:
    return (
        title == "Permission Denied"
        or "This topic does not exist yet" in markdown
        or "This page has been moved, the new location is" in markdown and len(markdown) < 400
    )


def sitemap_pages(namespace: str) -> set[str]:
    """Walk the DokuWiki sitemap tree for a namespace."""
    found: set[str] = set()
    todo, seen = deque([namespace]), set()
    while todo:
        ns = todo.popleft()
        if ns in seen:
            continue
        seen.add(ns)
        html = fetch(f"{BASE}/doku.php?id={namespace}:start&do=index&idx={urllib.parse.quote(ns)}")
        soup = BeautifulSoup(html, "html.parser")
        index = soup.select_one("#index__tree") or soup
        for a in index.find_all("a", href=True):
            sub = query_param(a["href"], "idx")
            if sub and in_namespace(sub, namespace):
                todo.append(sub)
            page = page_id_of(a["href"])
            if page and in_namespace(page, namespace):
                found.add(page)
    return found


def resolve_links(markdown: str, here: Path, existing: set[str]) -> str:
    def repl(match: re.Match) -> str:
        page, anchor = match.group(1), match.group(2) or ""
        if page in existing:
            return f"]({rel(page_path(page), here)}{anchor})"
        return f"]({BASE}/doku.php?id={page}{anchor})"

    return re.sub(r"\]\(wiki:([^)#\s]+)(#[^)\s]*)?\)", repl, markdown)


def build_index(pages: dict[str, dict], namespace: str) -> str:
    lines = [
        f"# TF3 Wiki Mirror: `{namespace}` namespace",
        "",
        "Generated by `tools/sync_wiki.py`. Do not edit by hand; run `make docs-wiki`.",
        f"Source: {BASE}/doku.php?id={namespace}:start",
        "",
        "| Page | Title | Sections |",
        "|---|---|---|",
    ]
    for page_id in sorted(pages):
        info = pages[page_id]
        headings = re.findall(r"^#{2,3} (.+)$", info["markdown"], flags=re.M)
        sections = ", ".join(h.strip() for h in headings[:12])
        if len(headings) > 12:
            sections += ", …"
        lines.append(f"| [{page_id}]({page_path(page_id).as_posix()}) | {info['title']} | {sections} |")
    return "\n".join(lines) + "\n"


def extract_examples(media_root: Path, dest_root: Path) -> None:
    """Unpack text files from attached example/template mod zips for grepping."""
    shutil.rmtree(dest_root, ignore_errors=True)
    for archive in sorted(media_root.rglob("*.zip")):
        dest = dest_root / archive.stem
        try:
            with zipfile.ZipFile(archive) as zf:
                names = [n for n in zf.namelist() if not n.endswith("/") and is_text_resource(n)]
                for name in names:
                    target = (dest / name).resolve()
                    if dest.resolve() not in target.parents:
                        continue  # guard against path traversal
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(zf.read(name))
            print(f"  examples: {archive.stem} ({len(names)} text files)")
        except zipfile.BadZipFile:
            print(f"  examples: {archive.name} is not a valid zip", file=sys.stderr)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--namespace", default="modding")
    parser.add_argument("--no-media", action="store_true", help="skip downloading images/attachments")
    parser.add_argument("--out", type=Path, default=WIKI_DIR)
    args = parser.parse_args()

    ns = args.namespace
    print(f"Discovering pages in '{ns}' …")
    queue = deque(sorted(sitemap_pages(ns) | {f"{ns}:start"}))
    print(f"  sitemap: {len(queue)} pages")

    pages: dict[str, dict] = {}
    media_ids: set[str] = set()
    queued = set(queue)
    failed: list[str] = []
    while queue:
        page_id = queue.popleft()
        print(f"  page {page_id}")
        try:
            html = fetch(f"{BASE}/doku.php?do=export_xhtml&id={urllib.parse.quote(page_id)}")
        except Exception as exc:  # noqa: BLE001
            print(f"    FAILED: {exc}", file=sys.stderr)
            failed.append(page_id)
            continue
        title, markdown, links = convert_page(page_id, html, media_ids)
        for link in sorted(links):
            if in_namespace(link, ns) and link not in queued:
                queued.add(link)
                queue.append(link)
        if is_placeholder(title, markdown) or SKIP_PAGES.match(page_id):
            print("    skipped (redirect/empty/maintenance)")
            continue
        pages[page_id] = {"title": title, "markdown": markdown}

    if not pages:
        raise SystemExit("No pages fetched; leaving existing docs untouched.")

    out: Path = args.out
    staging = out.with_name(out.name + ".tmp")
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)

    existing = set(pages)
    for page_id, info in pages.items():
        here = page_path(page_id)
        body = resolve_links(info["markdown"], here, existing)
        header = f"---\ntitle: {info['title']}\npage_id: {page_id}\nsource: {BASE}/doku.php?id={page_id}\n---\n\n"
        dest = staging / here
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(header + body)

    old_media = out / MEDIA_DIR_NAME
    if not args.no_media:
        print(f"Downloading {len(media_ids)} media files …")
        for media in sorted(media_ids):
            dest = staging / media_path(media)
            dest.parent.mkdir(parents=True, exist_ok=True)
            cached = old_media / media_path(media).relative_to(MEDIA_DIR_NAME)
            try:
                dest.write_bytes(fetch(f"{BASE}/lib/exe/fetch.php?media={urllib.parse.quote(media)}"))
            except Exception as exc:  # noqa: BLE001
                print(f"  media FAILED {media}: {exc}", file=sys.stderr)
                if cached.exists():
                    shutil.copy2(cached, dest)
    elif old_media.exists():
        shutil.copytree(old_media, staging / MEDIA_DIR_NAME)

    (staging / "INDEX.md").write_text(build_index(pages, ns))

    shutil.rmtree(out, ignore_errors=True)
    staging.rename(out)
    print(f"Wrote {len(pages)} pages to {out}")
    if (out / MEDIA_DIR_NAME).exists():
        print(f"Extracting example mods to {WIKI_EXAMPLES_CACHE_DIR} …")
        extract_examples(out / MEDIA_DIR_NAME, WIKI_EXAMPLES_CACHE_DIR)
    if failed:
        print(f"WARNING: {len(failed)} pages failed: {', '.join(failed)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
