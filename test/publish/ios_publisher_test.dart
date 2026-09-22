import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:deploykit/src/build/build_artifact.dart';
import 'package:deploykit/src/config/deploy_config.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:deploykit/src/core/logger.dart';
import 'package:deploykit/src/core/process_runner.dart';
import 'package:deploykit/src/publish/ios_publisher.dart';
import 'package:test/test.dart';

Logger _quiet() =>
    Logger(color: false, sink: IOSink(StreamController<List<int>>().sink));

const _asc = AppStoreIntegration(
  keyId: 'EXAMPLE123',
  issuerId: '11111111-2222',
  privateKey: '/keys/AuthKey.p8',
  teamId: 'TEAMID1234',
);

/// 64-bitli Mach-O sarlavhasi (0xFEEDFACF, little-endian).
final _machO = <int>[0xCF, 0xFA, 0xED, 0xFE, ...List.filled(60, 0)];

/// Mach-O bo'lmagan fayl.
final _plain = 'bu oddiy matn fayli'.codeUnits;

/// Soxta IPA yasaydi: Payload/Runner.app ichida berilgan fayllar.
BuildArtifact _ipa(Map<String, List<int>> entries) {
  final archive = Archive();
  for (final e in entries.entries) {
    archive.add(ArchiveFile(e.key, e.value.length, e.value));
  }
  final path = '${Directory.systemTemp.createTempSync().path}/Runner.ipa';
  File(path).writeAsBytesSync(ZipEncoder().encode(archive));
  return BuildArtifact(ArtifactType.ipa, path);
}

/// `vtool -show-build-version` chiqishi.
String _vtool(String platform) => '''
/path/to/binary:
Load command 1
      cmd LC_BUILD_VERSION
  cmdsize 32
 platform $platform
    minos 13.0
      sdk 17.0
''';

IosPublisher _publisher(ProcessRunner r) =>
    IosPublisher(runner: r, asc: _asc, logger: _quiet());

void main() {
  group('findSimulatorSlices', () {
    test('qurilma platformasi — ro`yxat bo`sh', () async {
      final r = FakeProcessRunner()
        ..responses['vtool'] = ProcessResult(0, _vtool('IOS'), '');

      final out = await _publisher(r).findSimulatorSlices(
        _ipa({'Payload/Runner.app/Runner': _machO}).path,
      );
      expect(out, isEmpty);
    });

    test('IOSSIMULATOR topilsa ro`yxatga tushadi', () async {
      final r = FakeProcessRunner()
        ..responses['vtool'] = ProcessResult(0, _vtool('IOSSIMULATOR'), '');

      final out = await _publisher(r).findSimulatorSlices(
        _ipa({'Payload/Runner.app/Runner': _machO}).path,
      );
      expect(out, hasLength(1));
      expect(out.single, allOf(contains('Runner'), contains('IOSSIMULATOR')));
    });

    test('Mach-O bo`lmagan fayllar tekshirilmaydi', () async {
      final r = FakeProcessRunner()
        ..responses['vtool'] = ProcessResult(0, _vtool('IOSSIMULATOR'), '');

      final out = await _publisher(r).findSimulatorSlices(
        _ipa({
          'Payload/Runner.app/Info.plist': _plain,
          'Payload/Runner.app/assets.car': _plain,
        }).path,
      );
      expect(out, isEmpty);
      expect(r.calls, isEmpty);
    });

    test('ichma-ich framework`lar ham tekshiriladi', () async {
      final r = FakeProcessRunner()
        ..responses['vtool'] = ProcessResult(0, _vtool('IOSSIMULATOR'), '');

      final out = await _publisher(r).findSimulatorSlices(
        _ipa({
          'Payload/Runner.app/Runner': _machO,
          'Payload/Runner.app/Frameworks/objective_c.framework/objective_c':
              _machO,
        }).path,
      );
      expect(out, hasLength(2));
    });

    test('vtool yiqilsa fayl toza deb hisoblanmaydi ham, yiqitmaydi ham',
        () async {
      final r = FakeProcessRunner()
        ..responses['vtool'] = const ProcessResult(1, '', 'not a Mach-O');

      final out = await _publisher(r).findSimulatorSlices(
        _ipa({'Payload/Runner.app/Runner': _machO}).path,
      );
      expect(out, isEmpty);
    });
  });

  group('publish', () {
    test('toza IPA altool bilan yuklanadi', () async {
      final r = FakeProcessRunner()
        ..responses['vtool'] = ProcessResult(0, _vtool('IOS'), '');

      final artifact = _ipa({'Payload/Runner.app/Runner': _machO});
      await _publisher(r).publish(artifact, dryRun: false);

      final call = r.lastCallTo('xcrun')!;
      expect(call.args, containsAll([
        'altool',
        '--upload-app',
        '-f',
        artifact.path,
        '-t',
        'ios',
        '--apiKey',
        'EXAMPLE123',
        '--apiIssuer',
        '11111111-2222',
      ]));
    });

    test('simulyator slice topilsa altool CHAQIRILMAYDI', () async {
      // App Store Connect buni baribir rad etadi, shuning uchun to'xtatish
      // shartsiz — yuklashga urinishning ma'nosi yo'q.
      final r = FakeProcessRunner()
        ..responses['vtool'] = ProcessResult(0, _vtool('IOSSIMULATOR'), '');

      await expectLater(
        _publisher(r).publish(
          _ipa({'Payload/Runner.app/Runner': _machO}),
          dryRun: false,
        ),
        throwsA(isA<UploadException>()
            .having((e) => e.message, 'message', contains('91169'))),
      );
      expect(r.lastCallTo('xcrun'), isNull);
    });

    test('altool yiqilsa UploadException, stderr xabarda', () async {
      final r = FakeProcessRunner()
        ..responses['vtool'] = ProcessResult(0, _vtool('IOS'), '')
        ..responses['xcrun'] = const ProcessResult(1, '', 'Invalid signature');

      await expectLater(
        _publisher(r).publish(
          _ipa({'Payload/Runner.app/Runner': _machO}),
          dryRun: false,
        ),
        throwsA(isA<UploadException>()
            .having((e) => e.message, 'message', contains('Invalid signature'))),
      );
    });

    test('dryRun: altool chaqirilmaydi, lekin slice tekshiruvi bajariladi',
        () async {
      final r = FakeProcessRunner()
        ..responses['vtool'] = ProcessResult(0, _vtool('IOS'), '');

      await _publisher(r).publish(
        _ipa({'Payload/Runner.app/Runner': _machO}),
        dryRun: true,
      );

      expect(r.lastCallTo('vtool'), isNotNull);
      expect(r.lastCallTo('xcrun'), isNull);
    });

    test('dryRun bo`lsa ham slice topilsa xato beradi', () async {
      final r = FakeProcessRunner()
        ..responses['vtool'] = ProcessResult(0, _vtool('IOSSIMULATOR'), '');

      await expectLater(
        _publisher(r).publish(
          _ipa({'Payload/Runner.app/Runner': _machO}),
          dryRun: true,
        ),
        throwsA(isA<UploadException>()),
      );
    });

    test('IPA fayli yo`q bo`lsa UploadException', () {
      expect(
        () => _publisher(FakeProcessRunner()).publish(
          const BuildArtifact(ArtifactType.ipa, '/yo/q/Runner.ipa'),
          dryRun: false,
        ),
        throwsA(isA<UploadException>()
            .having((e) => e.message, 'message', contains('/yo/q/Runner.ipa'))),
      );
    });
  });
}
