import 'dart:convert';
import 'dart:io';

import '../build/build_artifact.dart';
import '../config/deploy_config.dart';
import 'exceptions.dart';

/// The bridge between `build` and `upload`.
///
/// `build` records what it produced, for which environment, and under which
/// build number; `upload` reads it back. That is what makes retrying a failed
/// upload safe — same artifact, same versionCode.
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

  /// Fails when the manifest's environment is not the expected one.
  ///
  /// This is what stops a dev artifact from being uploaded to production.
  void verifyEnv(String expected) {
    if (env == expected) return;
    throw PreflightException(
      'The last build was made for "$env" but you are uploading to '
      '"$expected". Run `deploykit build --env $expected` first.',
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
        '${file.path} not found. Run `deploykit build` first.',
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
      throw PreflightException('Could not read ${file.path}: $e');
    }
  }
}
