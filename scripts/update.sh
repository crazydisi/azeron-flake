#!/usr/bin/env bash
# Bump sources.json to the latest upstream Azeron Software AppImage.
#
# Usage: scripts/update.sh [VERSION]
#
# Without VERSION, the latest version is read from upstream's electron-builder
# feed (live/latest.yml), falling back to scraping the download page.
# When running inside GitHub Actions, writes `updated`, `old_version` and
# `version` to $GITHUB_OUTPUT.
set -euo pipefail

cd "$(dirname "$0")/.."

BASE="https://azeron-software-public.s3.us-east-1.amazonaws.com/live"
PAGE="https://azeron.com/pages/software"
SOURCES="sources.json"
SYSTEM="x86_64-linux"

log() { echo "$*" >&2; }

output() {
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "$1=$2" >>"$GITHUB_OUTPUT"
  fi
}

yaml_field() {
  # Minimal top-level YAML scalar reader: `key: value` -> value
  # (the feed uses CRLF line endings, hence the \r strip).
  tr -d '\r' | awk -v k="$1" '$1 == k":" { $1 = ""; sub(/^ +/, ""); gsub(/["'\'']/, ""); print; exit }'
}

url_exists() {
  curl -fsI --retry 3 -o /dev/null "$1"
}

current=$(jq -r .version "$SOURCES")
latest="${1:-}"
release_date=""
scraped_url=""

if [[ -z "$latest" ]]; then
  # The Windows feed is the reliable version source. (latest-linux.yml is
  # broken upstream: it holds the AppImage binary itself, not YAML.)
  if feed=$(curl -fsSL --retry 3 "$BASE/latest.yml"); then
    latest=$(yaml_field version <<<"$feed")
    release_date=$(yaml_field releaseDate <<<"$feed" | cut -c1-10)
  fi

  if [[ -z "$latest" ]]; then
    log "latest.yml unavailable, scraping $PAGE"
    scraped_url=$(curl -fsSL --retry 3 -A "Mozilla/5.0" "$PAGE" |
      grep -oE 'https://azeron-software-public\.s3[^"'\'' <>]*\.AppImage' | head -n1 || true)
    latest=$(sed -nE 's#.*/live/([^/]+)/.*#\1#p' <<<"$scraped_url")
  fi
fi

if [[ -z "$latest" ]]; then
  log "error: could not determine latest upstream version"
  exit 1
fi

log "current: $current, latest: $latest"

# Only move forward; never downgrade if upstream rolls back the feed.
if [[ "$latest" == "$current" ]] ||
  [[ "$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n1)" != "$latest" ]]; then
  log "up to date"
  output updated false
  output version "$current"
  exit 0
fi

# Upstream has changed its file naming before, so try known schemes in order.
url=""
for candidate in \
  "$BASE/$latest/Azeron-Software-v$latest.AppImage" \
  "$BASE/$latest/Azeron+Software-$latest.AppImage" \
  "$scraped_url"; do
  if [[ -n "$candidate" ]] && url_exists "$candidate"; then
    url="$candidate"
    break
  fi
done

if [[ -z "$url" ]]; then
  log "error: no AppImage found for version $latest"
  exit 1
fi

log "prefetching $url"
hash=$(nix store prefetch-file --json --hash-type sha256 "$url" | jq -r .hash)

if [[ -z "$release_date" ]]; then
  release_date=$(date -u +%Y-%m-%d)
fi

tmp=$(mktemp)
jq --arg v "$latest" --arg d "$release_date" --arg s "$SYSTEM" \
  --arg u "$url" --arg h "$hash" \
  '.version = $v | .releaseDate = $d | .[$s] = { url: $u, hash: $h }' \
  "$SOURCES" >"$tmp"
mv "$tmp" "$SOURCES"

log "updated $current -> $latest ($hash)"
output updated true
output old_version "$current"
output version "$latest"
