import 'dart:async';
import 'dart:io';

import 'package:deploykit/src/build/ios_builder.dart';
import 'package:deploykit/src/config/deploy_config.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:deploykit/src/core/logger.dart';
import 'package:deploykit/src/core/process_runner.dart';
import 'package:test/test.dart';

Logger _quiet() =>
    Logger(color: false, sink: IOSink(StreamController<List<int>>().sink));

IosBuilder _builder(ProcessRunner r) =>
    IosBuilder(runner: r, logger: _quiet());

const _asc = AppStoreIntegration(
  keyId: 'EXAMPLE123',
  issuerId: '11111111-2222-3333-4444-555555555555',
  privateKey: '/keys/AuthKey_EXAMPLE123.p8',
  teamId: 'TEAMID1234',
);

EnvironmentConfig _env({
  Map<String, String> defines = const {},
  bool internalOnly = true,
}) =>
    EnvironmentConfig(
      name: 'dev',
      branch: null,
      dartDefines: defines,
      buildArgs: const [],
      android: null,
      ios: IosConfig(testflightInternalOnly: internalOnly),
      notify: null,
    );

/// Loyiha ildizi. [flutterIpa]/[xcodeIpa] — qaysi yo'l IPA hosil qilishi.
String _project({bool flutterIpa = true, bool xcodeIpa = false}) {
  final root = Directory.systemTemp.createTempSync().path;
  if (flutterIpa) {
    File('$root/build/ios/ipa/Runner.ipa')
      ..createSync(recursive: true)
      ..writeAsStringSync('ipa');
  }
  if (xcodeIpa) {
    File('$root/build/ios_deploy/ipa/Runner.ipa')
      ..createSync(recursive: true)
      ..writeAsStringSync('ipa');
  }
  return root;
}

void main() {
  group('purgeStaleCodeAssets', () {
    test('uchta katalogni ham o`chiradi', () async {
      // Bu qilinmasa simulyator framework'i IPA ichiga tushadi va App Store
      // Connect uni 91169 bilan rad etadi — 40MB yuklangandan keyin.
      final root = Directory.systemTemp.createTempSync().path;
      const dirs = [
        'build/native_assets/ios',
        'build/ios/iphonesimulator',
        'build/ios/Debug-iphonesimulator',
      ];
      for (final d in dirs) {
        Directory('$root/$d').createSync(recursive: true);
      }

      await _builder(FakeProcessRunner()).purgeStaleCodeAssets(root);

      for (final d in dirs) {
        expect(Directory('$root/$d').existsSync(), isFalse, reason: d);
      }
    });

    test('kataloglar yo`q bo`lsa ham yiqilmaydi', () async {
      final root = Directory.systemTemp.createTempSync().path;
      await _builder(FakeProcessRunner()).purgeStaleCodeAssets(root);
    });

    test('boshqa build kataloglariga tegmaydi', () async {
      final root = Directory.systemTemp.createTempSync().path;
      Directory('$root/build/ios/Release-iphoneos').createSync(recursive: true);
      await _builder(FakeProcessRunner()).purgeStaleCodeAssets(root);
      expect(Directory('$root/build/ios/Release-iphoneos').existsSync(), isTrue);
    });
  });

  group('renderExportOptions', () {
    test('internalOnly true bo`lsa TestFlight kaliti qo`yiladi', () {
      final x = _builder(FakeProcessRunner())
          .renderExportOptions(teamId: 'TEAMID1234', internalOnly: true);
      expect(x, contains('<key>testFlightInternalTestingOnly</key>'));
      expect(x, contains('<string>TEAMID1234</string>'));
      expect(x, contains('<string>app-store</string>'));
    });

    test('internalOnly false bo`lsa TestFlight kaliti yo`q', () {
      final x = _builder(FakeProcessRunner())
          .renderExportOptions(teamId: 'T', internalOnly: false);
      expect(x, isNot(contains('testFlightInternalTestingOnly')));
      expect(x, contains('<string>app-store</string>'));
    });

    test('haqiqiy plist sifatida o`qiladi', () {
      final x = _builder(FakeProcessRunner())
          .renderExportOptions(teamId: 'T', internalOnly: true);
      expect(x.trimLeft(), startsWith('<?xml'));
      expect(x, contains('<!DOCTYPE plist'));
      expect(x.trimRight(), endsWith('</plist>'));
    });
  });

  group('build', () {
    test('flutter muvaffaqiyatli bo`lsa xcodebuild chaqirilmaydi', () async {
      final r = FakeProcessRunner();
      final a = await _builder(r).build(
        projectRoot: _project(),
        env: _env(),
        asc: _asc,
        buildName: '1.2.3',
        buildNumber: 46,
      );
      expect(r.calls.map((c) => c.executable), isNot(contains('xcodebuild')));
      expect(a.type, ArtifactType.ipa);
    });

    test('flutter ga versiya va export-options uzatiladi', () async {
      final r = FakeProcessRunner();
      await _builder(r).build(
        projectRoot: _project(),
        env: _env(),
        asc: _asc,
        buildName: '1.2.3',
        buildNumber: 46,
      );
      final call = r.lastCallTo('flutter')!;
      expect(call.args.take(2), ['build', 'ipa']);
      expect(call.args, containsAll(['--build-name=1.2.3', '--build-number=46']));
      expect(call.args.any((a) => a.startsWith('--export-options-plist=')), isTrue);
    });

    test('dev define`lar flutter build ipa ga uzatiladi', () async {
      final r = FakeProcessRunner();
      await _builder(r).build(
        projectRoot: _project(),
        env: _env(defines: {'PROD_URL': 'false', 'INSPECTOR': 'true'}),
        asc: _asc,
        buildName: '1.2.3',
        buildNumber: 46,
      );
      expect(r.lastCallTo('flutter')!.args, containsAll([
        '--dart-define=PROD_URL=false',
        '--dart-define=INSPECTOR=true',
      ]));
    });

    test('bo`sh define`lar — hech nima uzatilmaydi', () async {
      final r = FakeProcessRunner();
      await _builder(r).build(
        projectRoot: _project(),
        env: _env(defines: {}),
        asc: _asc,
        buildName: '1.2.3',
        buildNumber: 46,
      );
      expect(
        r.lastCallTo('flutter')!.args.where((a) => a.startsWith('--dart-define')),
        isEmpty,
      );
    });

    test('flutter yiqilsa xcodebuild archive+export ga tushadi', () async {
      final r = FakeProcessRunner()
        ..responses['flutter'] = const ProcessResult(1, '', 'export failed');

      await _builder(r).build(
        projectRoot: _project(flutterIpa: false, xcodeIpa: true),
        env: _env(),
        asc: _asc,
        buildName: '1.2.3',
        buildNumber: 46,
      );

      final xc = r.calls.where((c) => c.executable == 'xcodebuild').toList();
      expect(xc, hasLength(2));
      expect(xc[0].args, contains('archive'));
      expect(xc[1].args, contains('-exportArchive'));

      for (final c in xc) {
        expect(c.args, containsAll([
          '-allowProvisioningUpdates',
          '-authenticationKeyPath',
          '/keys/AuthKey_EXAMPLE123.p8',
          '-authenticationKeyID',
          'EXAMPLE123',
          '-authenticationKeyIssuerID',
          '11111111-2222-3333-4444-555555555555',
        ]));
      }
    });

    test('fallback FAQAT flutter chaqirilgandan keyin ishlaydi', () async {
      // Define'lar ios/Flutter/Generated.xcconfig ga flutter tomonidan
      // yoziladi. xcodebuild birinchi ishlasa, define'lar yo'qoladi.
      final r = FakeProcessRunner()
        ..responses['flutter'] = const ProcessResult(1, '', 'x');

      await _builder(r).build(
        projectRoot: _project(flutterIpa: false, xcodeIpa: true),
        env: _env(),
        asc: _asc,
        buildName: '1.2.3',
        buildNumber: 46,
      );
      expect(r.calls.first.executable, 'flutter');
    });

    test('flutter 0 qaytarsa ham IPA yo`q bo`lsa fallback ishlaydi', () async {
      final r = FakeProcessRunner();
      await _builder(r).build(
        projectRoot: _project(flutterIpa: false, xcodeIpa: true),
        env: _env(),
        asc: _asc,
        buildName: '1.2.3',
        buildNumber: 46,
      );
      expect(r.calls.map((c) => c.executable), contains('xcodebuild'));
    });

    test('ikkala yo`l ham IPA bermasa BuildException', () {
      final r = FakeProcessRunner()
        ..responses['flutter'] = const ProcessResult(1, '', 'a')
        ..responses['xcodebuild'] = const ProcessResult(1, '', 'b');

      expect(
        () => _builder(r).build(
          projectRoot: _project(flutterIpa: false),
          env: _env(),
          asc: _asc,
          buildName: '1.2.3',
          buildNumber: 46,
        ),
        throwsA(isA<BuildException>()
            .having((e) => e.message, 'message', contains('IPA'))),
      );
    });

    test('purge build`dan oldin bajariladi', () async {
      final root = _project();
      Directory('$root/build/native_assets/ios').createSync(recursive: true);

      final r = FakeProcessRunner();
      await _builder(r).build(
        projectRoot: root,
        env: _env(),
        asc: _asc,
        buildName: '1.2.3',
        buildNumber: 46,
      );
      expect(Directory('$root/build/native_assets/ios').existsSync(), isFalse);
    });
  });
}
