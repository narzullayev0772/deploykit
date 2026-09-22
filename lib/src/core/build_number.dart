import 'dart:io';

import 'exceptions.dart';

/// Manages the `.last_build_number` file.
///
/// The target project's `pubspec.yaml` is **never modified**: the number is
/// read from here and passed through `flutter build --build-number`. A deploy
/// therefore leaves no changes behind in git.
class BuildNumber {
  const BuildNumber(this.file);

  final File file;

  int read() {
    if (!file.existsSync()) {
      throw ConfigException(
        '${file.path} not found. Create it with `deploykit init`.',
      );
    }
    final raw = file.readAsStringSync().trim();
    final n = int.tryParse(raw);
    if (n == null) {
      throw ConfigException(
        '${file.path}: expected an integer, found "$raw".',
      );
    }
    return n;
  }

  /// Increments the number and returns the new value.
  ///
  /// Called **before** the build. If the build then fails the number is
  /// skipped, which is harmless. Reusing a number is not: Play rejects a
  /// duplicate versionCode outright.
  int increment() {
    final next = read() + 1;
    file.writeAsStringSync('$next\n');
    return next;
  }

  /// Seeds the file from `version: x.y.z+N` in `pubspec.yaml`.
  ///
  /// Falls back to `0` when the pubspec is missing or has no `+N`.
  void initialiseFrom(String pubspecPath) {
    file.writeAsStringSync('${_parseBuildNumber(pubspecPath) ?? 0}\n');
  }

  /// `version: 1.2.3+45` yields `1.2.3`.
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
