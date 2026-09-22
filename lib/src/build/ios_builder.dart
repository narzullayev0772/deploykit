import 'dart:io';

import '../config/deploy_config.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';
import '../core/process_runner.dart';
import 'build_artifact.dart';

/// Builds the iOS IPA.
///
/// This class encodes two expensive lessons, both learned the hard way.
class IosBuilder {
  const IosBuilder({required this.runner, required this.logger});

  final ProcessRunner runner;
  final Logger logger;

  /// Dart code-asset frameworks are installed into one shared, non
  /// configuration-specific directory: `build/native_assets/ios/`.
  ///
  /// Simulator and device therefore fight over the same path, and the install
  /// step itself is cached. Run the app on the simulator, then build a release
  /// IPA, and Flutter considers the device install "up to date" and skips it —
  /// leaving the SIMULATOR framework for Xcode to embed. The build succeeds;
  /// App Store Connect rejects the upload with error **91169**.
  ///
  /// Deleting the directory makes the target dirty and forces the device copy
  /// to run again.
  Future<void> purgeStaleCodeAssets(String projectRoot) async {
    const stale = [
      'build/native_assets/ios',
      'build/ios/iphonesimulator',
      'build/ios/Debug-iphonesimulator',
    ];

    logger.detail('Purging stale iOS code-asset directories ...');
    for (final rel in stale) {
      final dir = Directory('$projectRoot/$rel');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }

  /// Renders the contents of `ExportOptions.plist`.
  ///
  /// The file is written to a temporary location rather than kept on disk —
  /// one fewer untracked file to lose.
  String renderExportOptions({
    required String teamId,
    required bool internalOnly,
  }) {
    // testFlightInternalTestingOnly keeps the build off external
    // TestFlight.
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

    // 1) The preferred path.
    var ipa = await _flutterBuildIpa(
      projectRoot: projectRoot,
      env: env,
      plistPath: plistPath,
      buildName: buildName,
      buildNumber: buildNumber,
    );

    // 2) The fallback. IMPORTANT: it can only run AFTER flutter has run.
    // `flutter build ipa` writes the defines into
    // ios/Flutter/Generated.xcconfig (DART_DEFINES=, base64) and the archive
    // reads them from there. Running xcodebuild first loses the defines.
    if (ipa == null) {
      logger.warn('flutter export produced no IPA — falling back to '
          'xcodebuild.');
      ipa = await _xcodebuildFallback(
        projectRoot: projectRoot,
        asc: asc,
        plistPath: plistPath,
      );
    }

    if (ipa == null) {
      throw const BuildException(
        'No IPA was produced: neither flutter nor xcodebuild succeeded.',
      );
    }

    final artifact = BuildArtifact(ArtifactType.ipa, ipa);
    logger.ok('IPA ready (${artifact.humanSize})');
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
      'Export mode: ${internalOnly ? 'TestFlight (internal only)' : 'App Store'}',
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

    logger.info('Building iOS IPA ...');
    logger.detail('flutter ${args.join(' ')}');

    final r = await runner.run('flutter', args, workingDirectory: projectRoot);
    if (!r.ok) {
      logger.detail('flutter build ipa exited ${r.exitCode}');
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

    // The ASC key is needed in both steps — provisioning updates can happen
    // during export too.
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
      logger.detail('xcodebuild archive exited ${archive.exitCode}');
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
      logger.detail('xcodebuild export exited ${export.exitCode}');
      return null;
    }
    return _newestIpa(exportDir);
  }

  /// The newest `.ipa` in a directory, or `null`.
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
