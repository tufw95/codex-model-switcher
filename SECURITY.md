# Security Policy

## Supported Version

Only the latest GitHub release receives security fixes. Update before reporting an issue that may already be resolved.

## Report A Vulnerability

Do not open a public issue for vulnerabilities, leaked credentials, or authentication bypasses.

Use GitHub private vulnerability reporting:

https://github.com/tufw95/codex-model-switcher/security/advisories/new

Include the affected version, macOS version, reproduction steps, impact, and any relevant logs with secrets removed. Do not include API keys, ChatGPT tokens, cookies, or private router URLs.

## Security Boundaries

- The local proxy binds only to the loopback interface.
- Remote router endpoints must use HTTPS.
- HTTP endpoints are accepted only for localhost development.
- Router API keys are stored locally and are never included in release artifacts.
- Incoming ChatGPT/OpenAI authentication headers are removed before requests are sent to the configured router.
- Quota requests use the router API key, return masked account labels, and are kept only in memory by the app.
- The quota endpoint is read-only and does not expose provider access tokens, refresh tokens, dashboard cookies, or administrative actions.
- OTA updates verify the manifest checksum, app identity, version, build, and code signature before installation.

The current public build is ad-hoc signed. Apple Developer ID signing and notarization are still required to provide a warning-free first installation and a stronger publisher identity for updates.
