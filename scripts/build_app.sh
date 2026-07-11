#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="${APP_NAME:-Codex Model Switcher}"
EXECUTABLE_NAME="CodexModelSwitcher"
BUNDLE_ID="${BUNDLE_ID:-vn.bigroll.codex-model-switcher}"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
UPDATE_MANIFEST_URL="${UPDATE_MANIFEST_URL:-https://raw.githubusercontent.com/bigroll/codex-model-switcher/main/update.json}"
ROUTER_TARGET_URL="${ROUTER_TARGET_URL:-https://9router.bigroll.vn}"
AUTO_REFRESH_MODELS_ON_LAUNCH="${AUTO_REFRESH_MODELS_ON_LAUNCH:-true}"
case "$AUTO_REFRESH_MODELS_ON_LAUNCH" in
  1|true|TRUE|yes|YES) AUTO_REFRESH_MODELS_ON_LAUNCH="true" ;;
  *) AUTO_REFRESH_MODELS_ON_LAUNCH="false" ;;
esac

xml_escape() {
  local value
  value="$(cat)"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

ESCAPED_UPDATE_MANIFEST_URL="$(printf '%s' "$UPDATE_MANIFEST_URL" | xml_escape)"
ESCAPED_ROUTER_TARGET_URL="$(printf '%s' "$ROUTER_TARGET_URL" | xml_escape)"

export DEVELOPER_DIR

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

cd "$ROOT_DIR"
swift build -c release --product "$EXECUTABLE_NAME"

BIN_DIR="$(swift build -c release --show-bin-path)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
STAGE_DIR="${TMPDIR:-/tmp}/codex-model-switcher-build"
STAGE_APP_DIR="$STAGE_DIR/${APP_NAME}.app"

rm -rf "$STAGE_APP_DIR"
mkdir -p "$STAGE_APP_DIR/Contents/MacOS" "$STAGE_APP_DIR/Contents/Resources"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$STAGE_APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$STAGE_APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

if [[ -f "$ROOT_DIR/Assets/AppIcon.icns" ]]; then
  clean_bundle_xattrs "$ROOT_DIR/Assets/AppIcon.icns"
  cp "$ROOT_DIR/Assets/AppIcon.icns" "$STAGE_APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [[ -f "$ROOT_DIR/Assets/MenuBarIcon.png" ]]; then
  clean_bundle_xattrs "$ROOT_DIR/Assets/MenuBarIcon.png"
  cp "$ROOT_DIR/Assets/MenuBarIcon.png" "$STAGE_APP_DIR/Contents/Resources/MenuBarIcon.png"
fi

cat > "$STAGE_APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 Bigroll</string>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
  <key>UpdateManifestURL</key>
  <string>${ESCAPED_UPDATE_MANIFEST_URL}</string>
  <key>DefaultRouterTargetURL</key>
  <string>${ESCAPED_ROUTER_TARGET_URL}</string>
  <key>AutoRefreshModelsOnLaunch</key>
  <${AUTO_REFRESH_MODELS_ON_LAUNCH}/>
</dict>
</plist>
PLIST

clean_bundle_xattrs "$STAGE_APP_DIR"
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$STAGE_APP_DIR"
verify_bundle "$STAGE_APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$DIST_DIR"
ditto --norsrc --noextattr "$STAGE_APP_DIR" "$APP_DIR"
if ! verify_bundle "$APP_DIR"; then
  echo "warning: workspace metadata affected the dist copy; the verified staging bundle remains valid" >&2
fi

echo "$APP_DIR"
