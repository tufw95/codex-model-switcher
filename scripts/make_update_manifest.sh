#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Codex Model Switcher}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DOWNLOAD_URL="${DOWNLOAD_URL:?Set DOWNLOAD_URL to the public DMG URL.}"
RELEASE_NOTES_URL="${RELEASE_NOTES_URL:-}"
MESSAGE="${MESSAGE:-A new Codex Model Switcher build is available.}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/dist/${APP_NAME// /-}-${VERSION}.dmg}"
OUT_PATH="${OUT_PATH:-$ROOT_DIR/dist/update.json}"

if [[ ! -f "$DMG_PATH" ]]; then
  VERSION="$VERSION" "$ROOT_DIR/scripts/package_dmg.sh" >/dev/null
fi

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
SIZE_BYTES="$(stat -f%z "$DMG_PATH")"

cat > "$OUT_PATH" <<JSON
{
  "version": "$VERSION",
  "build": "$BUILD_NUMBER",
  "download_url": "$DOWNLOAD_URL",
  "release_notes_url": "$RELEASE_NOTES_URL",
  "minimum_macos": "13.0",
  "message": "$MESSAGE",
  "sha256": "$SHA256",
  "size_bytes": $SIZE_BYTES
}
JSON

echo "$OUT_PATH"
