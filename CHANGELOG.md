## 0.1.0

First release.

- `init` — generate `deploy.yaml`, `.env.example` and `.last_build_number`
- `doctor` — check every precondition before a deploy starts
- `build` — build AAB, APK and IPA; writes `.deploykit/last_build.json`
- `upload` — upload the last build; safe to retry, never bumps the build number
- `publish` — build, upload and notify in one step
- `--dry-run` on `build`, `upload` and `publish`
- Google Play uploads via `package:googleapis` (no Python, no fastlane)
- App Store Connect uploads via `xcrun altool`, with a pre-flight scan for
  simulator slices that would be rejected with error 91169
- Telegram notifications, with a size policy that zips oversized artifacts
