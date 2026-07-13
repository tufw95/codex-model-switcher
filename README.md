# Codex Model Switcher

Native macOS app for switching Codex between the authentic provider and a 9Router-backed provider with minimal user setup.

## What It Does

- Runs as a SwiftUI menu bar-only macOS app.
- Saves `NINEROUTER_API_KEY` once to `~/.codex/.env` and exports it through `launchctl`.
- Generates `~/.codex/9router-model-catalog.json` so custom models appear in the Codex model picker.
- Synchronizes 9Router models on launch, before switching, and every 15 minutes while the app is running.
- Uses the installed Codex catalog for official model names, visibility, ordering, Effort, and Speed metadata.
- Keeps the official `Max` and `Ultra` UI, while normalizing unsupported backend effort values to `xhigh` before forwarding to 9Router.
- Lets the running proxy reload model mappings from `models.json` without restarting Codex or the proxy.
- Starts a local Swift LaunchAgent proxy on `127.0.0.1:9783`.
- Preserves ChatGPT sign-in while routing model requests through 9Router, so account-enabled sidebar items remain available.
- Replaces OpenAI authentication at the local proxy boundary and never forwards ChatGPT tokens or account headers to 9Router.
- Rewrites Codex config safely while preserving unrelated settings.
- Keeps the Chrome/node_repl repair logic from the original AppleScript bundle.
- Checks an update manifest and shows a macOS notification when a newer version is available.
- Keeps each user's 9Router API key local to their Mac.
- Prefers the 9Router `Codex` combo when available, so combo ordering can route to the newest models such as `gpt-5.6-*`.

## Daily Use

1. Open `dist/Codex Model Switcher.app`.
2. Click the menu bar icon.
3. Paste the 9Router API key once if prompted.
4. Choose `9Router` or `Authentic`.

The app converts `gpt 5.6` to:

```json
{
  "codexSlug": "gpt-5.6",
  "upstreamModel": "cx/gpt-5.6"
}
```

Codex then sees `gpt-5.6` in its model picker, while the proxy forwards requests to `cx/gpt-5.6`.
If 9Router exposes a `Codex` combo, the proxy keeps it as an automatic fallback for transient upstream failures.
When the user is signed in with ChatGPT, the generated provider uses `requires_openai_auth = true` for authentic account capabilities. The proxy independently reads the 9Router key from `~/.codex/.env`, strips private OpenAI headers, and applies the router key before forwarding the model request.

Model availability comes from the 9Router `/v1/models` response. Presentation metadata comes from the bundled catalog in the installed Codex app. A model added to both 9Router and the official Codex catalog therefore appears automatically with the official name and priority. A router-only model still appears, but receives conservative controls until verified capability metadata becomes available.

The Codex desktop client currently represents Ultra sessions with `xhigh` reasoning plus delegation metadata. The proxy preserves those delegation fields. If a request contains a literal backend effort of `max` or `ultra`, only that unsupported effort value is normalized to `xhigh` so 9Router does not reject the request.

## Build

```bash
cd CodexModelSwitcher
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
VERSION=1.0.0 BUILD_NUMBER=1 ./scripts/build_app.sh
```

The app is written to:

```text
dist/Codex Model Switcher.app
```

## Package DMG

```bash
UPDATE_MANIFEST_URL="https://example.com/update.json" \
ROUTER_TARGET_URL="https://9router.bigroll.vn" \
VERSION=1.0.0 \
BUILD_NUMBER=1 \
./scripts/package_dmg.sh
```

The DMG is written to:

```text
dist/Codex-Model-Switcher-1.0.0.dmg
```

## Developer ID Signing

For public distribution, set your Developer ID identity:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VERSION=1.0.0 \
BUILD_NUMBER=1 \
./scripts/package_dmg.sh
```

Ad-hoc signing is enough for local testing, but public downloads should use Developer ID signing and notarization.

## Notarize

```bash
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_PASSWORD="app-specific-password" \
VERSION=1.0.0 \
./scripts/notarize.sh
```

## One-click OTA Updates

The app reads a JSON manifest. The default URL can be changed in the Updates section.
For a public release, set the default URL at build time with `UPDATE_MANIFEST_URL`.
When a newer version is available, the app downloads the DMG, verifies its size,
SHA-256 checksum, bundle identifier, version, build, and code signature, then replaces
the installed app and relaunches it. macOS only asks for an administrator password when
the installation directory is not writable by the current user.

Example:

```json
{
  "version": "1.0.1",
  "build": "2",
  "download_url": "https://example.com/Codex-Model-Switcher-1.0.1.dmg",
  "release_notes_url": "https://example.com/codex-model-switcher/releases/1.0.1",
  "minimum_macos": "13.0",
  "message": "Improved model discovery and proxy stability.",
  "sha256": "DMG_SHA256_HERE",
  "size_bytes": 1234567
}
```

Generate a manifest after uploading a DMG:

```bash
VERSION=1.0.1 \
BUILD_NUMBER=2 \
DOWNLOAD_URL="https://example.com/Codex-Model-Switcher-1.0.1.dmg" \
RELEASE_NOTES_URL="https://example.com/codex-model-switcher/releases/1.0.1" \
./scripts/make_update_manifest.sh
```

Upload `dist/update.json` to the manifest URL. Every installed app that has update checks enabled will notify the user when `version` is greater than the installed version and offer one-click installation.

## Files Written On User Machines

- `~/.codex/.env`
- `~/.codex/config.toml`
- `~/.codex/config.toml.before-model-switcher`
- `~/.codex/9router-model-catalog.json`
- `~/Library/Application Support/Codex Model Switcher/models.json`
- `~/Library/Application Support/Codex Model Switcher/Updates/`
- `~/Library/Application Support/Codex Model Switcher/updates.json`
- `~/Library/LaunchAgents/com.bigroll.codex-model-switcher.proxy.plist`

## Notes

- The original AppleScript bundle is not modified.
- The app keeps the local proxy model rewrite behavior from the existing implementation.
- The updater is intentionally manifest-based so it works without a third-party update framework. If you later want one-click in-place replacement, Sparkle can be added on top of the same release pipeline.
