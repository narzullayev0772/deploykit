/// Qurilishi mumkin bo'lgan artefakt turlari.
enum ArtifactType {
  aab,
  apk,
  ipa;

  static ArtifactType? tryParse(String s) =>
      ArtifactType.values.where((v) => v.name == s).firstOrNull;
}

/// Artefakt Telegram chegarasidan oshganda nima qilish.
enum OversizePolicy {
  /// Zip qilib ko'rish; zip ham katta bo'lsa xato.
  zip,

  /// Darhol xato.
  fail,

  /// Faylni yubormaslik, faqat matn.
  skip;

  static OversizePolicy? tryParse(String s) =>
      OversizePolicy.values.where((v) => v.name == s).firstOrNull;
}

class AppConfig {
  const AppConfig({required this.root, required this.androidPackage});

  /// Flutter loyiha ildizi — `deploy.yaml` joylashgan joyga nisbatan.
  final String root;
  final String androidPackage;
}

class ApkConfig {
  const ApkConfig({this.splitPerAbi = false, this.targetPlatform});

  /// Fat APK ~112MB bo'lgani uchun Telegram'ga yuboriladigan build'da
  /// har doim `true` bo'lishi kutiladi.
  final bool splitPerAbi;

  /// Masalan `android-arm64`. `null` — barcha ABI.
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

  /// `true` — build tashqi TestFlight'ga chiqmaydi.
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

  /// Qaysi artefakt biriktiriladi. `null` — faqat matn.
  final ArtifactType? attach;

  /// Telegram bot API cheklovi.
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

  /// Branch tekshiruvi uchun regex. `null` — tekshiruv o'chirilgan.
  final String? branch;

  /// `--dart-define` juftliklari.
  ///
  /// **Bo'sh xarita haqiqiy qiymat**, "sozlanmagan" degani emas: Dart
  /// tomonidagi `defaultValue` lar allaqachon production qiymatlari, shuning
  /// uchun production build'ga hech qanday define uzatilmaydi.
  final Map<String, String> dartDefines;

  /// `flutter build` ga qo'shiladigan qo'shimcha argumentlar.
  final List<String> buildArgs;

  final AndroidConfig? android;
  final IosConfig? ios;
  final NotifyConfig? notify;
}

class PlayIntegration {
  const PlayIntegration({required this.serviceAccount});

  /// Service-account JSON faylining yo'li.
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

  /// `.p8` faylining yo'li.
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
