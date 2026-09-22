import '../build/build_artifact.dart';

/// Bitta yuklash natijasi.
class PublishResult {
  const PublishResult({required this.description, this.versionCode});

  /// Foydalanuvchiga ko'rsatiladigan bir qatorli tavsif.
  final String description;

  /// Play bergan versionCode. iOS uchun `null`.
  final int? versionCode;
}

/// Artefaktni do'konga yuklaydi.
abstract class Publisher {
  /// [dryRun] `true` bo'lsa hech qanday tashqi o'zgarish qilinmaydi, lekin
  /// bajarilishi mumkin bo'lgan tekshiruvlar baribir bajariladi.
  Future<PublishResult> publish(BuildArtifact artifact, {required bool dryRun});
}
