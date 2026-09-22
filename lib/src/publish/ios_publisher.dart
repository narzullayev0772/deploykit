import 'dart:io';

import 'package:archive/archive.dart';

import '../build/build_artifact.dart';
import '../config/deploy_config.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';
import '../core/process_runner.dart';
import 'publisher.dart';

/// IPA ni App Store Connect'ga yuklaydi.
class IosPublisher implements Publisher {
  const IosPublisher({
    required this.runner,
    required this.asc,
    required this.logger,
  });

  final ProcessRunner runner;
  final AppStoreIntegration asc;
  final Logger logger;

  /// Mach-O sarlavhasining sehrli baytlari (32/64 bit, ikkala tartibda, fat).
  static const _machOMagics = <int>[
    0xFEEDFACE, 0xFEEDFACF, // big-endian
    0xCEFAEDFE, 0xCFFAEDFE, // little-endian
    0xCAFEBABE, 0xBEBAFECA, // universal (fat)
  ];

  /// IPA ichidagi har bir Mach-O ikkilik faylining maqsad platformasini
  /// tekshiradi.
  ///
  /// Simulyator uchun qurilgan slice App Store Connect tomonidan **91169**
  /// ("references an unsupported platform in the arm64 slice") bilan rad
  /// etiladi. Buni yuklashdan oldin bir necha soniyada topish, 40MB
  /// yuklangandan keyin bilishdan ancha arzon.
  ///
  /// Qaytaradi: `"<nisbiy yo'l>: <platforma>"` ro'yxati. Bo'sh — toza.
  Future<List<String>> findSimulatorSlices(String ipaPath) async {
    final tmp = Directory.systemTemp.createTempSync('deploykit_ipa_');
    final offenders = <String>[];

    try {
      final archive = ZipDecoder().decodeBytes(File(ipaPath).readAsBytesSync());

      for (final entry in archive.files) {
        if (!entry.isFile) continue;

        final bytes = entry.readBytes();
        if (bytes == null || !_isMachO(bytes)) continue;

        // vtool faylni diskdan o'qiydi, shuning uchun chiqarib olamiz.
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
      throw UploadException('Yuklash uchun IPA topilmadi: ${artifact.path}');
    }

    // Tekshiruv dryRun'da ham bajariladi — bu uning butun ma'nosi.
    logger.info('IPA simulyator slice`lari uchun tekshirilmoqda ...');
    final offenders = await findSimulatorSlices(artifact.path);

    if (offenders.isNotEmpty) {
      throw UploadException(
        'IPA ichida simulyator uchun qurilgan ikkilik fayllar bor. '
        'App Store Connect buni 91169 xatosi bilan rad etadi.\n'
        '${offenders.map((o) => '  • $o').join('\n')}\n'
        'Sabab odatda build/native_assets/ios keshi — `deploykit build` uni '
        'avtomatik tozalaydi.',
      );
    }
    logger.ok('Barcha ikkilik fayllar iOS qurilmasiga mo\'ljallangan');

    if (dryRun) {
      return PublishResult(
        description: 'App Store Connect: ${artifact.humanSize} IPA → '
            'altool yuklash (dry-run)',
      );
    }

    logger.info('altool orqali yuklanmoqda ...');
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
        'altool yuklashni rad etdi (kod ${r.exitCode}):\n'
        '${r.stderr.trim().isEmpty ? r.stdout.trim() : r.stderr.trim()}',
      );
    }

    return const PublishResult(
      description: 'App Store Connect: IPA yuklandi',
    );
  }

  bool _isMachO(List<int> bytes) {
    if (bytes.length < 4) return false;
    final magic =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return _machOMagics.contains(magic);
  }

  /// `vtool -show-build-version` chiqishidan platformani ajratadi.
  ///
  /// vtool yiqilsa `null` — bu fayl Mach-O ko'rinsa ham LC_BUILD_VERSION
  /// bo'lmasligi mumkin. Bunday holatni buzg'unchi deb hisoblamaymiz,
  /// chunki noto'g'ri to'xtatish haqiqiy deploy'ni bloklaydi.
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
