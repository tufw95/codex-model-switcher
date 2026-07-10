#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Codex Model Switcher}"
VERSION="${VERSION:-1.0.0}"
DMG_PATH="${DMG_PATH:-$ROOT_DIR/dist/${APP_NAME// /-}-${VERSION}.dmg}"

: "${APPLE_ID:?Set APPLE_ID to your Apple Developer account email.}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer team ID.}"
: "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD to an app-specific password.}"

if [[ ! -f "$DMG_PATH" ]]; then
  VERSION="$VERSION" "$ROOT_DIR/scripts/package_dmg.sh"
fi

xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

xcrun stapler staple "$DMG_PATH"
spctl -a -t open --context context:primary-signature -v "$DMG_PATH"

echo "$DMG_PATH notarized"
