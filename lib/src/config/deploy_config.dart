/// The artifact types that can be produced.
enum ArtifactType {
  aab,
  apk,
  ipa;

  static ArtifactType? tryParse(String s) =>
      ArtifactType.values.where((v) => v.name == s).firstOrNull;
}

/// What to do when an artifact exceeds the Telegram size limit.
enum OversizePolicy {
  /// Try zipping it; fail if the zip is still too large.
  zip,

  /// Fail immediately.
  fail,

  /// Send the message without the file.
  skip;

  static OversizePolicy? tryParse(String s) =>
      OversizePolicy.values.where((v) => v.name == s).firstOrNull;
}

class AppConfig {
  const AppConfig({required this.root, required this.androidPackage});

  /// Flutter project root, relative to `deploy.yaml`.
  final String root;
  final String androidPackage;
}

class ApkConfig {
  const ApkConfig({this.splitPerAbi = false, this.targetPlatform});

  /// A fat APK is usually well over 100MB, so any build destined for
  /// Telegram is expected to set this.
  final bool splitPerAbi;

  /// For example `android-arm64`. `null` means every ABI.
  final String? targetPlatform;
}

class PlayConfig {
  const PlayConfig({required this.track, required this.status});

  /// `internal` | `alpha` | `beta` | `production`
  final String track;

  /// `completed` | `draft` | `inProgress` | `halted`
  final String status;
}

class AndroidConfig {
  const AndroidConfig({
    required this.artifacts,
    required this.apk,
    required this.play,
  });

  final List<ArtifactType> artifacts;
  final ApkConfig apk;
  final PlayConfig play;
}

class IosConfig {
  const IosConfig({required this.testflightInternalOnly});

  /// When `true` the build never reaches external TestFlight.
  final bool testflightInternalOnly;
}

class TelegramConfig {
  const TelegramConfig({
    required this.message,
    this.attach,
    this.maxSizeMb = 50,
    this.onOversize = OversizePolicy.zip,
  });

  final String message;

  /// Which artifact to attach. `null` sends text only.
  final ArtifactType? attach;

  /// The Telegram bot API limit.
  final int maxSizeMb;

  final OversizePolicy onOversize;
}

class NotifyConfig {
  const NotifyConfig({this.telegram});

  final TelegramConfig? telegram;
}

class EnvironmentConfig {
  const EnvironmentConfig({
    required this.name,
    required this.branch,
    required this.dartDefines,
    required this.buildArgs,
    required this.android,
    required this.ios,
    required this.notify,
  });

  final String name;

  /// Regular expression for the branch guard. `null` disables the check.
  final String? branch;

  /// `--dart-define` pairs.
  ///
  /// **An empty map is a real value**, not "unconfigured": the `defaultValue`
  /// of each `fromEnvironment` in the Dart code is already the production
  /// value, so a production build passes no defines at all.
  final Map<String, String> dartDefines;

  /// Extra arguments appended to `flutter build`.
  final List<String> buildArgs;

  final AndroidConfig? android;
  final IosConfig? ios;
  final NotifyConfig? notify;
}

class PlayIntegration {
  const PlayIntegration({required this.serviceAccount});

  /// Path to the service-account JSON file.
  final String serviceAccount;
}

class AppStoreIntegration {
  const AppStoreIntegration({
    required this.keyId,
    required this.issuerId,
    required this.privateKey,
    required this.teamId,
  });

  final String keyId;
  final String issuerId;

  /// Path to the `.p8` file.
  final String privateKey;

  final String teamId;
}

class TelegramIntegration {
  const TelegramIntegration({required this.botToken, required this.chatId});

  final String botToken;
  final String chatId;
}

class IntegrationsConfig {
  const IntegrationsConfig({this.play, this.appStore, this.telegram});

  final PlayIntegration? play;
  final AppStoreIntegration? appStore;
  final TelegramIntegration? telegram;
}
