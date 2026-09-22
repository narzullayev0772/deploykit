/// Files written by `deploykit init`.
///
/// The comments are deliberately generous: this file is the first thing a
/// user sees, and it doubles as the reference documentation for the schema.
const deployYamlTemplate = r'''
# deploy.yaml — deploykit configuration
#
# Secrets are NOT stored here. Only ${VAR} references appear in this file;
# the values come from .env or from environment variables. That is what makes
# this file safe to commit.
version: 1

app:
  # Flutter project root, relative to this file.
  root: .
  android_package: com.example.app

env_file: .env
build_number_file: .last_build_number

environments:
  dev:
    # Branch guard (regular expression). Remove the line entirely to disable
    # the check. Leaving it empty is an ERROR — that is deliberate, because an
    # empty value is almost always an accident, and silently treating it as
    # "disabled" would leave production unprotected.
    branch: '^versions/.+/dev$'

    dart_defines:
      PROD_URL: 'false'
      INSPECTOR: 'true'

    # Extra arguments appended to `flutter build`.
    build_args: []

    android:
      artifacts: [aab, apk]
      apk:
        # A fat APK is often >100MB, well over Telegram's 50MB bot limit.
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
        # zip | fail | skip — what to do when the artifact is over the limit.
        on_oversize: zip

  release:
    branch: '^versions/.+/release$'

    # Empty ON PURPOSE. The defaultValue of each bool.fromEnvironment in your
    # Dart code is already the production value, so a production build passes
    # no --dart-define at all. Writing PROD_URL: 'true' here would work, but
    # it hides that intent.
    dart_defines: {}

    android:
      artifacts: [aab]
      play:
        track: production
        # draft — you roll the release out by hand in the Play Console.
        status: draft
    ios:
      testflight_internal_only: false
    notify:
      telegram:
        message: '🚀 Production release'

integrations:
  play:
    # Path to the service-account JSON file.
    #
    # Note: use block style here, not flow style. In `{service_account: ${SA}}`
    # YAML reads the `{` of `${SA}` as a nested flow mapping and fails.
    service_account: ${PLAY_SERVICE_ACCOUNT}
  app_store:
    key_id: ${ASC_KEY_ID}
    issuer_id: ${ASC_ISSUER_ID}
    # Path to the .p8 file.
    private_key: ${ASC_PRIVATE_KEY}
    team_id: ${ASC_TEAM_ID}
  telegram:
    bot_token: ${TELEGRAM_BOT_TOKEN}
    chat_id: ${TELEGRAM_CHAT_ID}
''';

/// `.env.example` — every `${VAR}` used in deploy.yaml must appear here.
const envExampleTemplate = '''
# Copy this file to .env and fill in the values. .env is NOT committed.
# Every value can also be supplied as an environment variable, which takes
# precedence over .env — convenient in CI.

# Path to the Google Play service-account JSON file
PLAY_SERVICE_ACCOUNT=

# App Store Connect API key
ASC_KEY_ID=
ASC_ISSUER_ID=
ASC_PRIVATE_KEY=
ASC_TEAM_ID=

# Telegram bot
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
''';
