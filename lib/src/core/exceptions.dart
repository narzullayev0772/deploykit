/// Deploy jarayonidagi barcha kutilgan xatolarning asosi.
///
/// Har bir tur o'z exit kodiga ega — CI shu kod orqali nima yiqilganini
/// ajratadi. Kodlar dizayn hujjatining 7-bo'limida belgilangan va
/// o'zgartirilmaydi, chunki ular ommaviy interfeysning bir qismi.
abstract class DeployException implements Exception {
  const DeployException(this.message);

  final String message;

  /// Jarayon shu kod bilan tugaydi.
  int get exitCode;

  @override
  String toString() => '$runtimeType: $message';
}

/// yaml xato, majburiy maydon yo'q, `${ENV}` to'ldirilmagan.
class ConfigException extends DeployException {
  const ConfigException(super.message);

  @override
  int get exitCode => 2;
}

/// branch mos emas, vosita yo'q, kalit fayl topilmadi.
class PreflightException extends DeployException {
  const PreflightException(super.message);

  @override
  int get exitCode => 3;
}

/// flutter yoki xcodebuild yiqildi.
class BuildException extends DeployException {
  const BuildException(super.message);

  @override
  int get exitCode => 4;
}

/// Play yoki App Store Connect rad etdi.
class UploadException extends DeployException {
  const UploadException(super.message);

  @override
  int get exitCode => 5;
}

/// Deploy o'tdi, xabarnoma o'tmadi.
///
/// Bu alohida kod, chunki bu holatda artefakt allaqachon yuklangan —
/// deploy muvaffaqiyatli, faqat xabar yetib bormadi.
class NotifyException extends DeployException {
  const NotifyException(super.message);

  @override
  int get exitCode => 6;
}
