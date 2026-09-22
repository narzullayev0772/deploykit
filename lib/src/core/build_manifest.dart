import 'dart:convert';
import 'dart:io';

import '../build/build_artifact.dart';
import '../config/deploy_config.dart';
import 'exceptions.dart';

/// `build` va `upload` orasidagi ko'prik.
///
/// `build` nimani, qaysi muhit uchun va qaysi raqam bilan qurganini yozadi;
/// `upload` shu yerdan o'qiydi. Shuning uchun yiqilgan yuklashni qayta
/// urinish xavfsiz — bir xil artefakt, bir xil versionCode.
class BuildManifest {
  const BuildManifest({
    required this.env,
    required this.buildName,
    required this.buildNumber,
    required this.builtAt,
    required this.artifacts,
  });

  final String env;
  final String buildName;
  final int buildNumber;
  final DateTime builtAt;
  final List<BuildArtifact> artifacts;

  String get version => '$buildName+$buildNumber';

  BuildArtifact? artifactOf(ArtifactType type) =>
      artifacts.where((a) => a.type == type).firstOrNull;

  /// Manifestdagi muhit kutilganidan farq qilsa xato.
  ///
  /// Bu dev artefaktini tasodifan production'ga yuklashdan himoya qiladi.
  void verifyEnv(String expected) {
    if (env == expected) return;
    throw PreflightException(
      'Oxirgi build "$env" muhiti uchun qurilgan, siz esa "$expected" ga '
      'yuklamoqchisiz. Avval `deploykit build --env $expected` bajaring.',
    );
  }

  void write(File file) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'env': env,
        'build_name': buildName,
        'build_number': buildNumber,
        'built_at': builtAt.toUtc().toIso8601String(),
        'artifacts': artifacts.map((a) => a.toJson()).toList(),
      }),
    );
  }

  static BuildManifest read(File file) {
    if (!file.existsSync()) {
      throw PreflightException(
        '${file.path} topilmadi. Avval `deploykit build` bajaring.',
      );
    }
    try {
      final j = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      return BuildManifest(
        env: j['env']! as String,
        buildName: j['build_name']! as String,
        buildNumber: j['build_number']! as int,
        builtAt: DateTime.parse(j['built_at']! as String),
        artifacts: (j['artifacts']! as List)
            .map((e) => BuildArtifact.fromJson(e as Map<String, Object?>))
            .toList(),
      );
    } on PreflightException {
      rethrow;
    } catch (e) {
      throw PreflightException('${file.path} o\'qib bo\'lmadi: $e');
    }
  }
}
