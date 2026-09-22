import 'dart:io';

import '../config/deploy_config.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';
import '../core/process_runner.dart';
import 'build_artifact.dart';

/// Builds the Android artifacts.
///
/// The whole value of this class is assembling the right arguments for
/// `flutter`. That is where the bugs are, and they fail quietly: drop
/// `--split-per-abi` and the build still succeeds, but the resulting fat APK
/// is rejected by Telegram with a 413. Hence the tests assert on arguments.
class AndroidBuilder {
  const AndroidBuilder({required this.runner, required this.logger});

  final ProcessRunner runner;
  final Logger logger;

  Future<List<BuildArtifact>> build({
    required String projectRoot,
    required EnvironmentConfig env,
    required String buildName,
    required int buildNumber,
  }) async {
    final android = env.android;
    if (android == null) return const [];

    final out = <BuildArtifact>[];

    // Order matters: AAB first. In the dev flow the AAB is on Play by the
    // time the APK is sent, so a failed Telegram upload is not a failed
    // deploy.
    for (final type in [ArtifactType.aab, ArtifactType.apk]) {
      if (!android.artifacts.contains(type)) continue;
      out.add(await _buildOne(
        type: type,
        projectRoot: projectRoot,
        env: env,
        android: android,
        buildName: buildName,
        buildNumber: buildNumber,
      ));
    }
    return out;
  }

  Future<BuildArtifact> _buildOne({
    required ArtifactType type,
    required String projectRoot,
    required EnvironmentConfig env,
    required AndroidConfig android,
    required String buildName,
    required int buildNumber,
  }) async {
    final args = <String>[
      'build',
      type == ArtifactType.aab ? 'appbundle' : 'apk',
      '--release',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
    ];

    // --split-per-abi and --target-platform are for apk ONLY; an appbundle
    // contains every ABI and rejects these flags.
    if (type == ArtifactType.apk) {
      if (android.apk.splitPerAbi) args.add('--split-per-abi');
      final platform = android.apk.targetPlatform;
      if (platform != null) args.add('--target-platform=$platform');
    }

    // Empty dartDefines adds nothing. That is the definition of a
    // production build here, not a missing configuration.
    for (final e in env.dartDefines.entries) {
      args.add('--dart-define=${e.key}=${e.value}');
    }
    args.addAll(env.buildArgs);

    logger.info('Building Android ${type.name.toUpperCase()} ...');
    logger.detail('flutter ${args.join(' ')}');

    final r = await runner.run('flutter', args, workingDirectory: projectRoot);
    if (!r.ok) {
      throw BuildException(
        'flutter build ${type.name} failed (exit ${r.exitCode}):\n'
        '${r.stderr.trim().isEmpty ? r.stdout.trim() : r.stderr.trim()}',
      );
    }

    final path = _artifactPath(projectRoot, type, android);
    if (!File(path).existsSync()) {
      // flutter can exit 0 and still not produce the file we expect — for
      // instance when --target-platform changes the output name.
      throw BuildException('Expected artifact not found: $path');
    }

    final artifact = BuildArtifact(type, path);
    logger.ok('${type.name.toUpperCase()} ready (${artifact.humanSize})');
    return artifact;
  }

  String _artifactPath(
    String root,
    ArtifactType type,
    AndroidConfig android,
  ) {
    if (type == ArtifactType.aab) {
      return '$root/build/app/outputs/bundle/release/app-release.aab';
    }

    const dir = 'build/app/outputs/flutter-apk';
    if (!android.apk.splitPerAbi) return '$root/$dir/app-release.apk';

    // --split-per-abi writes one file per ABI, with the ABI in the name.
    // With --target-platform only one of them is built.
    final abi = _abiFor(android.apk.targetPlatform);
    return '$root/$dir/app-$abi-release.apk';
  }

  /// `android-arm64` → `arm64-v8a`
  String _abiFor(String? targetPlatform) => switch (targetPlatform) {
        'android-arm64' => 'arm64-v8a',
        'android-arm' => 'armeabi-v7a',
        'android-x64' => 'x86_64',
        _ => 'arm64-v8a',
      };
}
