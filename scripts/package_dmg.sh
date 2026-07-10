#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Codex Model Switcher}"
VERSION="${VERSION:-1.0.0}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/${APP_NAME// /-}-${VERSION}.dmg"
RW_DMG_PATH="${TMPDIR:-/tmp}/codex-model-switcher-${VERSION}-rw.dmg"
MOUNT_DIR=""

clean_bundle_xattrs() {
  local target="$1"
  xattr -cr "$target" 2>/dev/null || true
  while IFS= read -r path; do
    xattr -d com.apple.FinderInfo "$path" 2>/dev/null || true
    xattr -d 'com.apple.fileprovider.fpfs#P' "$path" 2>/dev/null || true
    xattr -d com.apple.quarantine "$path" 2>/dev/null || true
  done < <(find "$target" -print)
}

verify_bundle() {
  local target="$1"
  local attempt
  for attempt in 1 2 3 4 5; do
    clean_bundle_xattrs "$target"
    if codesign --verify --deep --strict --verbose=2 "$target"; then
      clean_bundle_xattrs "$target"
      return 0
    fi
    sleep 0.25
  done
  clean_bundle_xattrs "$target"
  codesign --verify --deep --strict --verbose=2 "$target"
}

cleanup_mount() {
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
    rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
  rm -f "$RW_DMG_PATH" >/dev/null 2>&1 || true
}

trap cleanup_mount EXIT

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  "$ROOT_DIR/scripts/build_app.sh"
fi

verify_bundle "$APP_DIR"

rm -rf "$DMG_ROOT" "$DMG_PATH" "$RW_DMG_PATH"
MOUNT_DIR="$(mktemp -d)"
hdiutil create -size 40m -fs APFS -volname "$APP_NAME" -ov "$RW_DMG_PATH" >/dev/null
hdiutil attach "$RW_DMG_PATH" -mountpoint "$MOUNT_DIR" -nobrowse -quiet
ditto --norsrc --noextattr "$APP_DIR" "$MOUNT_DIR/${APP_NAME}.app"
ln -s /Applications "$MOUNT_DIR/Applications"
clean_bundle_xattrs "$MOUNT_DIR/${APP_NAME}.app"
verify_bundle "$MOUNT_DIR/${APP_NAME}.app"
hdiutil detach "$MOUNT_DIR" -quiet
rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
MOUNT_DIR=""
hdiutil convert "$RW_DMG_PATH" -format UDZO -o "$DMG_PATH" >/dev/null
rm -f "$RW_DMG_PATH"
echo "$DMG_PATH"
