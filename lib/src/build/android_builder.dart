import 'dart:io';

import '../config/deploy_config.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';
import '../core/process_runner.dart';
import 'build_artifact.dart';

/// Android artefaktlarini quradi.
///
/// Bu sinfning butun qiymati `flutter` ga uzatiladigan argumentlarni to'g'ri
/// yig'ishda. Xatolar aynan shu yerda tug'iladi va ular jimgina o'tib
/// ketadi: masalan `--split-per-abi` tushib qolsa build muvaffaqiyatli
/// bo'ladi, lekin natijadagi ~112MB lik APK Telegram'da 413 bilan rad
/// etiladi. Shuning uchun testlar argumentlarni tekshiradi.
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

    // Tartib muhim: AAB birinchi. Dev oqimida AAB Play'ga yuklangach, APK
    // yuborishdagi nosozlik deploy'ni yiqitmaydi.
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

    // --split-per-abi va --target-platform FAQAT apk uchun; appbundle
    // barcha ABI ni o'z ichiga oladi va bu bayroqlarni qabul qilmaydi.
    if (type == ArtifactType.apk) {
      if (android.apk.splitPerAbi) args.add('--split-per-abi');
      final platform = android.apk.targetPlatform;
      if (platform != null) args.add('--target-platform=$platform');
    }

    // Bo'sh dartDefines — hech nima qo'shilmaydi. Bu production build'ning
    // ta'rifi, "sozlanmagan" degani emas.
    for (final e in env.dartDefines.entries) {
      args.add('--dart-define=${e.key}=${e.value}');
    }
    args.addAll(env.buildArgs);

    logger.info('Android ${type.name.toUpperCase()} qurilmoqda ...');
    logger.detail('flutter ${args.join(' ')}');

    final r = await runner.run('flutter', args, workingDirectory: projectRoot);
    if (!r.ok) {
      throw BuildException(
        'flutter build ${type.name} yiqildi (kod ${r.exitCode}):\n'
        '${r.stderr.trim().isEmpty ? r.stdout.trim() : r.stderr.trim()}',
      );
    }

    final path = _artifactPath(projectRoot, type, android);
    if (!File(path).existsSync()) {
      // flutter 0 qaytargan bo'lsa ham fayl bo'lmasligi mumkin — masalan
      // --target-platform boshqa nom bergan bo'lsa.
      throw BuildException('Kutilgan artefakt topilmadi: $path');
    }

    final artifact = BuildArtifact(type, path);
    logger.ok('${type.name.toUpperCase()} tayyor (${artifact.humanSize})');
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

    // --split-per-abi har bir ABI uchun alohida fayl yozadi va nom ABI ni
    // o'z ichiga oladi. --target-platform berilgan bo'lsa faqat bittasi
    // quriladi.
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
