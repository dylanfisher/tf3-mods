#!/usr/bin/env bash
# Build the site and push site/dist/ to the public Pages repo (default git@github.com:dylanfisher/tf3-mods-site.git,
# branch main). The sources (plans/**, screenshots) are local, so the build runs here and only the output is
# published. Works in a temp clone outside the repo; the Pages repo's history keeps one commit per deploy.
# The custom domain (CNAME) comes from astro.config.mjs SITE_URL, its only source. A built URL with "_" fails it.
#
#   SITE_REMOTE=...  SITE_BRANCH=main  SKIP_BUILD=1  DRY_RUN=1  scripts/deploy.sh
#
# DRY_RUN=1: build, stage and commit in the temp clone, print the commit's stat and keep the clone; no push. When the
# remote cannot be reached (not created yet, no access), a dry run stages into a fresh local repo instead.
set -euo pipefail

SITE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REMOTE="${SITE_REMOTE:-git@github.com:dylanfisher/tf3-mods-site.git}"
BRANCH="${SITE_BRANCH:-main}"
DRY="${DRY_RUN:-}"

if [[ -z "${SKIP_BUILD:-}" ]]; then
  (cd "$SITE_DIR" && pnpm run build)
fi
[[ -f "$SITE_DIR/dist/index.html" ]] || { echo "deploy: no build in $SITE_DIR/dist" >&2; exit 1; }

DOMAIN="$(cd "$SITE_DIR" && node --input-type=module -e 'const { SITE_URL } = await import("./astro.config.mjs"); console.log(new URL(SITE_URL).host)')"
[[ -n "$DOMAIN" ]] || { echo "deploy: no SITE_URL in astro.config.mjs" >&2; exit 1; }

# Every URL the site makes is dashed (src/lib/slug.ts); an internal href/src with "_" is a bug, not a deploy.
BAD="$(grep -rhoE '(href|src|srcset)="[^"]*"' "$SITE_DIR/dist" --include='*.html' | grep -vE '="(https?:|mailto:|data:)' | grep '_' | sort -u || true)"
if [[ -n "$BAD" ]]; then
  echo "deploy: internal URLs with an underscore in dist/ (use slugify/urlPath):" >&2
  echo "$BAD" | head -20 >&2
  exit 1
fi

# The site is public: no local paths (home folders, the repo checkout) in any built file.
LEAK="$(grep -rlE "/Users/|/home/[a-z]|$HOME" "$SITE_DIR/dist" --include='*.html' --include='*.js' --include='*.json' --include='*.svg' || true)"
if [[ -n "$LEAK" ]]; then
  echo "deploy: local paths in dist/ (strip them in the builder):" >&2
  echo "$LEAK" | head -20 >&2
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tf3-site-deploy.XXXXXX")"
if [[ -z "$DRY" ]]; then trap 'rm -rf "$TMP"' EXIT; fi

echo "deploy: checking $REMOTE ($BRANCH)"
if HEADS="$(git ls-remote --heads "$REMOTE" "$BRANCH")"; then
  if [[ -n "$HEADS" ]]; then
    git clone --quiet --depth 1 --branch "$BRANCH" "$REMOTE" "$TMP/repo"
  else
    # Empty repo or no such branch yet: start the branch fresh.
    git clone --quiet "$REMOTE" "$TMP/repo"
    git -C "$TMP/repo" checkout --quiet --orphan "$BRANCH"
  fi
elif [[ -n "$DRY" ]]; then
  echo "deploy: $REMOTE not reachable (see the error above); DRY_RUN stages into a fresh local repo"
  git init --quiet -b "$BRANCH" "$TMP/repo"
else
  echo "deploy: cannot reach $REMOTE (see the error above)" >&2
  exit 1
fi

# Replace the tree with dist/ (keep .git), then the Pages files.
find "$TMP/repo" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
cp -R "$SITE_DIR/dist/." "$TMP/repo/"
printf '%s\n' "$DOMAIN" > "$TMP/repo/CNAME"
touch "$TMP/repo/.nojekyll"

cd "$TMP/repo"
git add -A
if git diff --cached --quiet; then
  echo "deploy: no changes"
  exit 0
fi
SRC_REV="$(git -C "$SITE_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
git commit --quiet -m "Deploy $(date -u +%Y-%m-%dT%H:%MZ) from tf3-mods $SRC_REV"
git --no-pager show --stat --format='deploy: commit %h %s' HEAD | tail -1
if [[ -n "$DRY" ]]; then
  echo "deploy: DRY_RUN set, not pushing; staged commit kept in $TMP/repo (git -C $TMP/repo show --stat)"
  exit 0
fi
git push --quiet origin "HEAD:$BRANCH"
echo "deploy: pushed to $REMOTE $BRANCH -> https://$DOMAIN/"
