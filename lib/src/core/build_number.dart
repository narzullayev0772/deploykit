import 'dart:io';

import 'exceptions.dart';

/// `.last_build_number` faylini boshqaradi.
///
/// Maqsadli loyihaning `pubspec.yaml` fayli **hech qachon o'zgartirilmaydi** —
/// raqam bu yerdan olinadi va `flutter build --build-number` orqali uzatiladi.
/// Shuning uchun deploy git'da hech qanday o'zgarish qoldirmaydi.
class BuildNumber {
  const BuildNumber(this.file);

  final File file;

  int read() {
    if (!file.existsSync()) {
      throw ConfigException(
        '${file.path} topilmadi. `deploykit init` bilan yarating.',
      );
    }
    final raw = file.readAsStringSync().trim();
    final n = int.tryParse(raw);
    if (n == null) {
      throw ConfigException(
        '${file.path}: butun son kutilgan edi, "$raw" topildi.',
      );
    }
    return n;
  }

  /// Raqamni oshiradi va yangi qiymatni qaytaradi.
  ///
  /// Build'dan **oldin** chaqiriladi. Build yiqilsa raqam o'tkazib
  /// yuboriladi — bu zararsiz. Raqamni qayta ishlatish esa halokatli:
  /// Play takrorlangan versionCode ni rad etadi.
  int increment() {
    final next = read() + 1;
    file.writeAsStringSync('$next\n');
    return next;
  }

  /// Faylni `pubspec.yaml` dagi `version: x.y.z+N` dan boshlab yaratadi.
  ///
  /// pubspec topilmasa yoki `+N` bo'lmasa — `0`.
  void initialiseFrom(String pubspecPath) {
    file.writeAsStringSync('${_parseBuildNumber(pubspecPath) ?? 0}\n');
  }

  /// `version: 1.2.3+45` dan `1.2.3`.
  static String? readBuildName(String pubspecPath) {
    final v = _versionLine(pubspecPath);
    if (v == null) return null;
    return v.split('+').first;
  }

  static int? _parseBuildNumber(String pubspecPath) {
    final v = _versionLine(pubspecPath);
    if (v == null || !v.contains('+')) return null;
    return int.tryParse(v.split('+').last);
  }

  static String? _versionLine(String pubspecPath) {
    final f = File(pubspecPath);
    if (!f.existsSync()) return null;
    for (final line in f.readAsLinesSync()) {
      if (line.startsWith('version:')) {
        return line.substring('version:'.length).trim();
      }
    }
    return null;
  }
}
