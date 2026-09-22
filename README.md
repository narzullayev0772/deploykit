# deploykit

Deploy Flutter apps to Google Play and App Store Connect from a single
`deploy.yaml`. No Python, no virtualenv, no fastlane.

`deploykit` separates three things that usually end up tangled together:

| Layer | Lives in | Committed |
|---|---|---|
| Logic | this package, versioned | yes |
| Configuration | `deploy.yaml` | yes |
| Secrets | `${ENV}` / `.env` | **no** |

That separation is the point. Deploy scripts commonly sit in the same
directory as the `.p8` keys and the service-account JSON, so the whole
directory gets gitignored — and the logic quietly stops being version
controlled.

## Install

```bash
dart pub global activate deploykit
```

iOS builds require macOS, Xcode and the command-line tools. Android works
anywhere Flutter does.

## Quick start

```bash
cd your_flutter_app
deploykit init                 # writes deploy.yaml, .env.example, .last_build_number
cp .env.example .env           # then fill in the values
deploykit doctor --dev         # verify everything before you build
deploykit publish --dev --dry-run
```

`doctor` checks the things that otherwise fail ten minutes into a build: is
`flutter` there, is the branch right, is the `.p8` actually readable, does the
Play key still work, does the Telegram token still resolve.

## Commands

| Command | What it does |
|---|---|
| `init` | Write `deploy.yaml`, `.env.example` and `.last_build_number` |
| `doctor` | Check every precondition and report all of them |
| `build` | Build the artifacts; writes `.deploykit/last_build.json` |
| `upload` | Upload the last build. Safe to retry — never bumps the build number |
| `publish` | `build` + `upload` + notify |

All of them except `init` take `--dev`, `--release` or `--env <name>`, plus
`--android` / `--ios` to limit the platforms. `build`, `upload` and `publish`
take `--dry-run`.

A dry run is a real check: it loads the config, resolves every `${VAR}` and
runs pre-flight. It fails if your key is missing. It just does not build or
upload anything.

## Configuration

`deploykit init` generates a fully commented `deploy.yaml`. The shape:

```yaml
version: 1

app:
  root: .
  android_package: com.example.app

env_file: .env
build_number_file: .last_build_number

environments:
  dev:
    branch: '^versions/.+/dev$'      # regex; omit the field to disable
    dart_defines:
      PROD_URL: 'false'
      INSPECTOR: 'true'
    android:
      artifacts: [aab, apk]
      apk:
        split_per_abi: true
        target_platform: android-arm64
      play:
        track: internal
        status: completed
    ios:
      testflight_internal_only: true
    notify:
      telegram:
        message: '⚠️ DEV build, test only'
        attach: apk
        max_size_mb: 50
        on_oversize: zip             # zip | fail | skip

  release:
    branch: '^versions/.+/release$'
    dart_defines: {}                 # empty on purpose — see below
    android:
      artifacts: [aab]
      play:
        track: production
        status: draft
    ios:
      testflight_internal_only: false

integrations:
  play:
    service_account: ${PLAY_SERVICE_ACCOUNT}
  app_store:
    key_id: ${ASC_KEY_ID}
    issuer_id: ${ASC_ISSUER_ID}
    private_key: ${ASC_PRIVATE_KEY}
    team_id: ${ASC_TEAM_ID}
  telegram:
    bot_token: ${TELEGRAM_BOT_TOKEN}
    chat_id: ${TELEGRAM_CHAT_ID}
```

`deploy.json` works too — same schema.

Environment names are not special. Add `staging` and
`deploykit publish --env staging` works immediately.

### Three things worth knowing

**`dart_defines: {}` is a real value.** The `defaultValue` of each
`bool.fromEnvironment` in your Dart code is normally already the production
value, so a production build should pass no `--dart-define` at all. Writing
`PROD_URL: 'true'` would work, but it hides the intent.

**`branch: ''` is an error, not "disabled".** Remove the field to disable the
check. An empty string is almost always an accident, and reading it as
"disabled" would leave production unguarded.

**Use block style for `${VAR}`.** In flow style, `{service_account: ${SA}}`,
YAML reads the `{` of `${SA}` as a nested mapping and fails to parse.

## Secrets

Nothing secret goes in `deploy.yaml` — only `${VAR}` references. Values come
from `.env` or from environment variables, and the environment wins, which is
what you want in CI:

```bash
PLAY_SERVICE_ACCOUNT=/run/secrets/play.json deploykit publish --release
```

`deploykit init` adds `.env` and `.deploykit/` to your `.gitignore`.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Configuration error — bad YAML, missing field, unresolved `${VAR}` |
| 3 | Pre-flight failed — wrong branch, missing tool, unreadable key |
| 4 | Build failed |
| 5 | Upload rejected by Play or App Store Connect |
| 6 | Deployed, but the notification failed |
| 64 | Usage error |

Code 6 is deliberate: by the time a notification is sent the artifact is
already uploaded, so a dead Telegram token is not a failed deploy — but CI
should still notice.

## What it does for you

**Purges stale iOS code-asset frameworks before every build.** Dart code
assets install into one shared, non configuration-specific directory. Run your
app on the simulator, then build a release IPA, and Flutter can skip the
device install as "up to date" — leaving a *simulator* framework for Xcode to
embed. The build succeeds and App Store Connect rejects the upload with error
**91169**, after you have uploaded 40MB.

**Scans the IPA for simulator slices before uploading.** Same failure, caught
in seconds instead of minutes, by reading `LC_BUILD_VERSION` from every Mach-O
in the bundle.

**Checks Telegram's `ok` field, not just the HTTP status.** Telegram reports
real success only in the JSON body; `curl` exits 0 even on a 413, which is how
rejected uploads go unnoticed in shell scripts.

**Zips oversized artifacts — and measures the result.** Native libraries
inside an APK are stored *uncompressed* so Android can mmap them, so an outer
zip often helps a lot. But the saving is never assumed: the zip is created,
measured, and rejected if it is still over the limit.

**Keeps build numbers monotonic.** The number is bumped before the build, so a
failed build skips a number rather than reusing one. `upload` never bumps it,
which is what makes retrying a failed upload safe.

## Using it as a library

Everything is exported, and the external boundaries — `ProcessRunner` and
`http.Client` — are injected, so the pieces are usable and testable on their
own:

```dart
import 'package:deploykit/deploykit.dart';

final config = const ConfigLoader().load('deploy.yaml');
final artifacts = await AndroidBuilder(
  runner: const RealProcessRunner(),
  logger: Logger(),
).build(
  projectRoot: '.',
  env: config.environment('dev'),
  buildName: '1.2.3',
  buildNumber: 46,
);
```

`FakeProcessRunner` ships in `lib/` for exactly this reason.

## Licence

MIT
