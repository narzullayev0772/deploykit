import 'dart:io';

import '../config/deploy_config.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';
import '../core/process_runner.dart';
import 'build_artifact.dart';

/// iOS IPA quradi.
///
/// Bu sinf ikkita qimmat darsni o'z ichiga oladi — ikkalasi ham
/// `deploy_ios.sh` da tajriba orqali topilgan.
class IosBuilder {
  const IosBuilder({required this.runner, required this.logger});

  final ProcessRunner runner;
  final Logger logger;

  /// Dart code-asset framework'lari bitta umumiy, konfiguratsiyaga bog'liq
  /// bo'lmagan katalogga o'rnatiladi: `build/native_assets/ios/`.
  ///
  /// Simulyator va qurilma o'sha yo'l uchun kurashadi, va o'rnatish
  /// bosqichining o'zi keshlanadi. Ilovani simulyatorda ishga tushirib,
  /// keyin release IPA qursangiz, Flutter qurilma uchun o'rnatishni
  /// "allaqachon bajarilgan" deb hisoblaydi va o'tkazib yuboradi — Xcode esa
  /// SIMULYATOR framework'ini IPA ichiga joylaydi. Build muvaffaqiyatli
  /// bo'ladi, App Store Connect esa **91169** bilan rad etadi.
  ///
  /// Katalogni o'chirish target'ni "iflos" qiladi va nusxalashni qayta
  /// bajartiradi.
  Future<void> purgeStaleCodeAssets(String projectRoot) async {
    const stale = [
      'build/native_assets/ios',
      'build/ios/iphonesimulator',
      'build/ios/Debug-iphonesimulator',
    ];

    logger.detail('Eskirgan iOS code-asset kataloglari tozalanmoqda ...');
    for (final rel in stale) {
      final dir = Directory('$projectRoot/$rel');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }

  /// `ExportOptions.plist` mazmunini yasaydi.
  ///
  /// Fayl diskda saqlanmaydi — vaqtinchalik yoziladi. Shu bilan git'da
  /// kuzatilmaydigan yana bitta fayl kamayadi.
  String renderExportOptions({
    required String teamId,
    required bool internalOnly,
  }) {
    // testFlightInternalTestingOnly build'ni tashqi TestFlight'dan
    // chetda ushlab turadi.
    final internalKey = internalOnly
        ? '    <key>testFlightInternalTestingOnly</key>\n    <true/>\n'
        : '';

    return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>$teamId</string>
$internalKey    <key>uploadSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
''';
  }

  Future<BuildArtifact> build({
    required String projectRoot,
    required EnvironmentConfig env,
    required AppStoreIntegration asc,
    required String buildName,
    required int buildNumber,
  }) async {
    await purgeStaleCodeAssets(projectRoot);

    final plistPath = _writeExportOptions(
      projectRoot: projectRoot,
      teamId: asc.teamId,
      internalOnly: env.ios?.testflightInternalOnly ?? false,
    );

    // 1) Asosiy yo'l.
    var ipa = await _flutterBuildIpa(
      projectRoot: projectRoot,
      env: env,
      plistPath: plistPath,
      buildName: buildName,
      buildNumber: buildNumber,
    );

    // 2) Zaxira yo'l. MUHIM: bu faqat flutter chaqirilgandan keyin
    // ishlashi mumkin — `flutter build ipa` define'larni
    // ios/Flutter/Generated.xcconfig ga (DART_DEFINES=, base64) yozadi va
    // archive o'sha yerdan o'qiydi. xcodebuild'ni birinchi ishlatish
    // define'larni yo'qotadi.
    if (ipa == null) {
      logger.warn('flutter export IPA bermadi — xcodebuild ga o\'tilmoqda.');
      ipa = await _xcodebuildFallback(
        projectRoot: projectRoot,
        asc: asc,
        plistPath: plistPath,
      );
    }

    if (ipa == null) {
      throw const BuildException(
        'IPA hosil bo\'lmadi: flutter ham, xcodebuild ham natija bermadi.',
      );
    }

    final artifact = BuildArtifact(ArtifactType.ipa, ipa);
    logger.ok('IPA tayyor (${artifact.humanSize})');
    return artifact;
  }

  String _writeExportOptions({
    required String projectRoot,
    required String teamId,
    required bool internalOnly,
  }) {
    final dir = Directory('$projectRoot/build/deploykit')
      ..createSync(recursive: true);
    final file = File('${dir.path}/ExportOptions.plist')
      ..writeAsStringSync(
        renderExportOptions(teamId: teamId, internalOnly: internalOnly),
      );

    logger.detail(
      'Export rejimi: ${internalOnly ? 'TestFlight (faqat ichki)' : 'App Store'}',
    );
    return file.path;
  }

  Future<String?> _flutterBuildIpa({
    required String projectRoot,
    required EnvironmentConfig env,
    required String plistPath,
    required String buildName,
    required int buildNumber,
  }) async {
    final args = <String>[
      'build',
      'ipa',
      '--build-name=$buildName',
      '--build-number=$buildNumber',
      for (final e in env.dartDefines.entries)
        '--dart-define=${e.key}=${e.value}',
      ...env.buildArgs,
      '--export-options-plist=$plistPath',
    ];

    logger.info('iOS IPA qurilmoqda ...');
    logger.detail('flutter ${args.join(' ')}');

    final r = await runner.run('flutter', args, workingDirectory: projectRoot);
    if (!r.ok) {
      logger.detail('flutter build ipa kod ${r.exitCode} qaytardi');
      return null;
    }
    return _newestIpa('$projectRoot/build/ios/ipa');
  }

  Future<String?> _xcodebuildFallback({
    required String projectRoot,
    required AppStoreIntegration asc,
    required String plistPath,
  }) async {
    final outDir = '$projectRoot/build/ios_deploy';
    final archivePath = '$outDir/Runner.xcarchive';
    final exportDir = '$outDir/ipa';

    // ASC kaliti ikkala bosqichda ham kerak — provisioning yangilanishi
    // export vaqtida ham sodir bo'ladi.
    final auth = <String>[
      '-allowProvisioningUpdates',
      '-authenticationKeyPath', asc.privateKey,
      '-authenticationKeyID', asc.keyId,
      '-authenticationKeyIssuerID', asc.issuerId,
    ];

    logger.info('xcodebuild archive ...');
    final archive = await runner.run('xcodebuild', [
      '-workspace', '$projectRoot/ios/Runner.xcworkspace',
      '-scheme', 'Runner',
      '-configuration', 'Release',
      '-archivePath', archivePath,
      ...auth,
      'archive',
    ], workingDirectory: projectRoot);

    if (!archive.ok) {
      logger.detail('xcodebuild archive kod ${archive.exitCode} qaytardi');
      return null;
    }

    logger.info('xcodebuild -exportArchive ...');
    final export = await runner.run('xcodebuild', [
      '-exportArchive',
      '-archivePath', archivePath,
      '-exportPath', exportDir,
      '-exportOptionsPlist', plistPath,
      ...auth,
    ], workingDirectory: projectRoot);

    if (!export.ok) {
      logger.detail('xcodebuild export kod ${export.exitCode} qaytardi');
      return null;
    }
    return _newestIpa(exportDir);
  }

  /// Katalogdagi eng so'nggi `.ipa`, yoki `null`.
  String? _newestIpa(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;

    final ipas = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ipa'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    return ipas.isEmpty ? null : ipas.first.path;
  }
}
