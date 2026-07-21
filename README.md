# Codex Model Switcher

[![Latest release](https://img.shields.io/github/v/release/tufw95/codex-model-switcher)](https://github.com/tufw95/codex-model-switcher/releases/latest)
[![Release](https://github.com/tufw95/codex-model-switcher/actions/workflows/release.yml/badge.svg)](https://github.com/tufw95/codex-model-switcher/actions/workflows/release.yml)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)
![Swift](https://img.shields.io/badge/Swift-native-F05138)

A native macOS menu bar app that switches Codex between the authentic OpenAI provider and a shared 9Router provider.

## Download

Download the latest DMG from:

**[Download the latest Codex Model Switcher](https://github.com/tufw95/codex-model-switcher/releases/latest)**

## Quick Start

1. Download and open the latest `Codex-Model-Switcher-<version>.dmg`.
2. Drag `Codex Model Switcher` into `Applications`.
3. Open the app and enter your 9Router API key once.
4. Use the menu bar icon to choose `9Router` or `Authentic`.

When the configured router supports the read-only quota endpoint, Codex quota appears automatically in the same menu bar window.

The API key stays on that Mac. It is not embedded in the app or committed to this repository.

> The current public build is ad-hoc signed. On first installation, macOS may require **System Settings > Privacy & Security > Open Anyway**. Removing this first-install warning requires an Apple Developer ID certificate and notarization. Updates installed from inside an existing app use the one-click OTA updater.

## Automatic Model Sync

Codex Model Switcher is designed to require no manual model configuration:

- Reads available models and Combos from the 9Router `/v1/models` endpoint.
- Syncs on app launch, before switching to 9Router, and every 15 minutes.
- Uses the installed Codex catalog for official display names, visibility, ordering, Effort, and Speed metadata.
- Adds new models automatically after they become available in both 9Router and the installed Codex catalog.
- Keeps router-only models available with conservative controls until official metadata exists.
- Reloads routing from `models.json` without restarting the proxy.
- Removes unsupported `Ultra` from the generated 9Router catalog.
- Uses strict model routing: an exact model alias is required and failed requests never switch to a Combo or another model.

For compatibility with existing sessions, old backend payloads containing `max` or `ultra` are normalized to `xhigh`. Delegation and summary fields are preserved.

## Quota Tracker

- Reads active Codex account limits from the configured router's `/v1/quota` endpoint.
- Shows remaining quota, reset time, and account availability directly in the menu bar.
- Sorts the lowest remaining quota first and refreshes automatically every two minutes.
- Uses a 60-second server cache so a whole team does not repeatedly query every Codex account.
- Shows full account email addresses for team identification and never stores quota responses on disk.
- Uses the same locally stored 9Router API key; dashboard passwords and cookies are never required.

Quota tracking is an optional 9Router server extension, not part of the OpenAI API standard. If a custom router does not implement `/v1/quota`, the app hides the quota section and switching continues to work normally.

## Use A Different Router

The app is not limited to `9router.bigroll.vn`:

1. Open the menu bar app and choose **Settings**.
2. Enter the server in **Router URL**, for example `https://router.example.com`.
3. Click the checkmark to save it.
4. Enter the API key for that router and switch to `9Router`.

The URL is stored locally and restored on the next launch. A custom server must provide an OpenAI-compatible `/v1/models` endpoint and accept Codex requests such as `/v1/responses`. To display quota, it may additionally provide the sanitized `/v1/quota` endpoint described above. Base paths are supported, for example `https://gateway.example.com/team`. URLs ending in `/v1` or `/v1/models` are accepted and normalized automatically.

Remote servers must use HTTPS because the app sends the configured API key to that server. Plain HTTP is accepted only for `localhost`, `127.0.0.1`, or `::1` development endpoints.

## Switching Behavior

### 9Router

- Starts a native Swift proxy bound only to `127.0.0.1:9783`.
- Generates `~/.codex/9router-model-catalog.json` for the Codex model picker.
- Preserves ChatGPT sign-in and account-enabled sidebar features.
- Removes private OpenAI authentication headers before forwarding requests.
- Applies the locally stored 9Router key only at the proxy boundary.
- Preserves the exact requested model. For example, `5.6 Sol` can only route to `cx/gpt-5.6-sol`.
- Retries transient gateway errors once with the same model, then returns the error without fallback.
- Restarts Codex after a provider switch so the new configuration takes effect.

### Authentic

- Removes the custom 9Router provider from the active Codex configuration.
- Restores the authentic OpenAI provider without deleting unrelated Codex settings.
- Stops the local router proxy and restarts Codex.

## One-Click Updates

The app checks this manifest:

```text
https://github.com/tufw95/codex-model-switcher/releases/latest/download/update.json
```

When a newer release is available, the app can download and install it directly. Before replacing the installed app, it verifies:

- DMG size and SHA-256 checksum.
- Bundle identifier.
- Version and build number.
- Code signature.
- Minimum supported macOS version.

Users can also run **Check for Updates** from the menu bar app at any time.

The app checks for new versions on launch and every hour. Notifications include **Update Now** and **Remind Me Later** actions; reminders are scheduled by macOS for four hours later and work even when the menu bar popup is closed.

## Build From Source

Requirements:

- macOS 13 or newer.
- Xcode with the macOS SDK.
- Swift Package Manager.

```bash
git clone https://github.com/tufw95/codex-model-switcher.git
cd codex-model-switcher
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
VERSION=1.3.1 BUILD_NUMBER=20 ./scripts/package_dmg.sh
```

Build outputs are written to `dist/`.

## Release A New Version

The GitHub Actions release workflow runs whenever a `v*` tag is pushed:

```bash
git tag -a v1.3.2 -m "Codex Model Switcher 1.3.2"
git push origin v1.3.2
```

The workflow tests the project, builds the DMG, generates `update.json`, and uploads both files to GitHub Releases.

### Developer ID And Notarization

For warning-free public installation, build with an Apple Developer ID identity and notarize the DMG:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
VERSION=1.3.2 \
BUILD_NUMBER=21 \
./scripts/package_dmg.sh

APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_PASSWORD="app-specific-password" \
VERSION=1.3.2 \
./scripts/notarize.sh
```

Do not commit certificates, passwords, API keys, or notarization credentials.

## Local Files

The app may create or update:

- `~/.codex/.env`
- `~/.codex/config.toml`
- `~/.codex/config.toml.before-model-switcher`
- `~/.codex/9router-model-catalog.json`
- `~/Library/Application Support/Codex Model Switcher/models.json`
- `~/Library/Application Support/Codex Model Switcher/Updates/`
- `~/Library/Application Support/Codex Model Switcher/updates.json`
- `~/Library/LaunchAgents/com.bigroll.codex-model-switcher.proxy.plist`

## Privacy

- Each user enters their own 9Router API key.
- The key is stored locally in `~/.codex/.env` with restricted permissions.
- The app does not upload the key to GitHub or include it in release artifacts.
- ChatGPT cookies and OpenAI account tokens are not forwarded to 9Router.
- Quota data remains in memory and is not persisted locally. Full account emails are visible to users who hold a valid router API key.

Security issues should be reported privately as described in [SECURITY.md](SECURITY.md).

## License

See [LICENSE](LICENSE).
