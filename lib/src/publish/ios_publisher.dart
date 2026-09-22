import 'dart:io';

import 'package:archive/archive.dart';

import '../build/build_artifact.dart';
import '../config/deploy_config.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';
import '../core/process_runner.dart';
import 'publisher.dart';

/// Uploads an IPA to App Store Connect.
class IosPublisher implements Publisher {
  const IosPublisher({
    required this.runner,
    required this.asc,
    required this.logger,
  });

  final ProcessRunner runner;
  final AppStoreIntegration asc;
  final Logger logger;

  /// Mach-O magic numbers (32/64-bit, both byte orders, and universal).
  static const _machOMagics = <int>[
    0xFEEDFACE, 0xFEEDFACF, // big-endian
    0xCEFAEDFE, 0xCFFAEDFE, // little-endian
    0xCAFEBABE, 0xBEBAFECA, // universal (fat)
  ];

  /// Checks the target platform of every Mach-O binary inside the IPA.
  ///
  /// A slice built for the simulator is rejected by App Store Connect with
  /// error **91169** ("references an unsupported platform in the arm64
  /// slice"). Catching that here takes seconds; finding out after a 40MB
  /// upload takes minutes.
  ///
  /// Returns a list of `"<relative path>: <platform>"`. Empty means clean.
  Future<List<String>> findSimulatorSlices(String ipaPath) async {
    final tmp = Directory.systemTemp.createTempSync('deploykit_ipa_');
    final offenders = <String>[];

    try {
      final archive = ZipDecoder().decodeBytes(File(ipaPath).readAsBytesSync());

      for (final entry in archive.files) {
        if (!entry.isFile) continue;

        final bytes = entry.readBytes();
        if (bytes == null || !_isMachO(bytes)) continue;

        // vtool reads from disk, so the entry has to be extracted.
        final extracted = File('${tmp.path}/${entry.name}')
          ..createSync(recursive: true)
          ..writeAsBytesSync(bytes);

        final platform = await _platformOf(extracted.path);
        if (platform != null && platform.contains('SIMULATOR')) {
          offenders.add('${_relativeToApp(entry.name)}: $platform');
        }
      }
    } finally {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    }

    return offenders;
  }

  @override
  Future<PublishResult> publish(
    BuildArtifact artifact, {
    required bool dryRun,
  }) async {
    if (!File(artifact.path).existsSync()) {
      throw UploadException('IPA to upload not found: ${artifact.path}');
    }

    // Runs even for a dry run — that is the entire point of the check.
    logger.info('Scanning the IPA for simulator slices ...');
    final offenders = await findSimulatorSlices(artifact.path);

    if (offenders.isNotEmpty) {
      throw UploadException(
        'The IPA contains binaries built for the simulator. App Store '
        'Connect rejects these with error 91169.\n'
        '${offenders.map((o) => '  • $o').join('\n')}\n'
        'The usual cause is a stale build/native_assets/ios cache, which '
        '`deploykit build` purges for you.',
      );
    }
    logger.ok('All embedded binaries target an iOS device');

    if (dryRun) {
      return PublishResult(
        description: 'App Store Connect: ${artifact.humanSize} IPA → '
            'altool upload (dry run)',
      );
    }

    logger.info('Uploading via altool ...');
    final r = await runner.run('xcrun', [
      'altool',
      '--upload-app',
      '-f', artifact.path,
      '-t', 'ios',
      '--apiKey', asc.keyId,
      '--apiIssuer', asc.issuerId,
    ]);

    if (!r.ok) {
      throw UploadException(
        'altool rejected the upload (exit ${r.exitCode}):\n'
        '${r.stderr.trim().isEmpty ? r.stdout.trim() : r.stderr.trim()}',
      );
    }

    return const PublishResult(
      description: 'App Store Connect: IPA uploaded',
    );
  }

  bool _isMachO(List<int> bytes) {
    if (bytes.length < 4) return false;
    final magic =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return _machOMagics.contains(magic);
  }

  /// Extracts the platform from `vtool -show-build-version` output.
  ///
  /// Returns `null` when vtool fails — a file can look like a Mach-O and
  /// still carry no LC_BUILD_VERSION. Such a file is not treated as an
  /// offender, because a false positive blocks a legitimate deploy.
  Future<String?> _platformOf(String binaryPath) async {
    final r = await runner.run('vtool', ['-show-build-version', binaryPath]);
    if (!r.ok) return null;

    for (final line in r.stdout.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[0] == 'platform') return parts[1];
    }
    return null;
  }

  /// `Payload/Runner.app/Frameworks/x` → `Frameworks/x`
  String _relativeToApp(String entryName) {
    final match = RegExp(r'^Payload/[^/]+\.app/(.*)$').firstMatch(entryName);
    return match?.group(1) ?? entryName;
  }
}
