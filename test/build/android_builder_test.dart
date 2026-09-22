import 'dart:async';
import 'dart:io';

import 'package:deploykit/src/build/android_builder.dart';
import 'package:deploykit/src/build/build_artifact.dart';
import 'package:deploykit/src/config/deploy_config.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:deploykit/src/core/logger.dart';
import 'package:deploykit/src/core/process_runner.dart';
import 'package:test/test.dart';

Logger _quiet() =>
    Logger(color: false, sink: IOSink(StreamController<List<int>>().sink));

/// Loyiha ildizini yasaydi va `flutter` chaqirilganda paydo bo'lishi kerak
/// bo'lgan artefakt fayllarini oldindan yaratib qo'yadi.
String _project({bool aab = true, String? apkName}) {
  final root = Directory.systemTemp.createTempSync().path;
  if (aab) {
    File('$root/build/app/outputs/bundle/release/app-release.aab')
      ..createSync(recursive: true)
      ..writeAsStringSync('aab');
  }
  if (apkName != null) {
    File('$root/build/app/outputs/flutter-apk/$apkName')
      ..createSync(recursive: true)
      ..writeAsStringSync('apk');
  }
  return root;
}

EnvironmentConfig _env({
  List<ArtifactType> artifacts = const [ArtifactType.aab],
  Map<String, String> defines = const {},
  List<String> buildArgs = const [],
  bool splitPerAbi = false,
  String? targetPlatform,
}) =>
    EnvironmentConfig(
      name: 'dev',
      branch: null,
      dartDefines: defines,
      buildArgs: buildArgs,
      android: AndroidConfig(
        artifacts: artifacts,
        apk: ApkConfig(splitPerAbi: splitPerAbi, targetPlatform: targetPlatform),
        play: const PlayConfig(track: 'internal', status: 'completed'),
      ),
      ios: null,
      notify: null,
    );

Future<(FakeProcessRunner, List<BuildArtifact>)> _build(
  String root,
  EnvironmentConfig env,
) async {
  final runner = FakeProcessRunner();
  final artifacts = await AndroidBuilder(runner: runner, logger: _quiet())
      .build(projectRoot: root, env: env, buildName: '1.2.3', buildNumber: 46);
  return (runner, artifacts);
}

List<String> _defines(FakeProcessRunner r) =>
    r.calls.expand((c) => c.args).where((a) => a.startsWith('--dart-define')).toList();

void main() {
  test('aab uchun to`g`ri flutter buyrug`i', () async {
    final (runner, _) = await _build(_project(), _env());
    final call = runner.lastCallTo('flutter')!;

    expect(call.executable, 'flutter');
    expect(call.args.take(3), ['build', 'appbundle', '--release']);
    expect(call.args, containsAll(['--build-name=1.2.3', '--build-number=46']));
  });

  test('dev define`lar qo`shiladi', () async {
    final (runner, _) = await _build(
      _project(),
      _env(defines: {'PROD_URL': 'false', 'INSPECTOR': 'true'}),
    );
    expect(_defines(runner), containsAll([
      '--dart-define=PROD_URL=false',
      '--dart-define=INSPECTOR=true',
    ]));
  });

  test('bo`sh dartDefines — hech qanday --dart-define yo`q', () async {
    // Production build'ning belgisi: Dart'dagi defaultValue lar allaqachon
    // prod qiymatlari, shuning uchun hech nima uzatilmaydi.
    final (runner, _) = await _build(_project(), _env(defines: {}));
    expect(_defines(runner), isEmpty);
  });

  test('splitPerAbi true bo`lsa apk uchun bayroqlar qo`shiladi', () async {
    final (runner, _) = await _build(
      _project(apkName: 'app-arm64-v8a-release.apk'),
      _env(
        artifacts: [ArtifactType.apk],
        splitPerAbi: true,
        targetPlatform: 'android-arm64',
      ),
    );
    final call = runner.lastCallTo('flutter')!;
    expect(call.args, contains('--split-per-abi'));
    expect(call.args, contains('--target-platform=android-arm64'));
  });

  test('splitPerAbi false bo`lsa bayroq yo`q', () async {
    final (runner, _) = await _build(
      _project(apkName: 'app-release.apk'),
      _env(artifacts: [ArtifactType.apk]),
    );
    expect(runner.lastCallTo('flutter')!.args, isNot(contains('--split-per-abi')));
  });

  test('appbundle hech qachon --split-per-abi olmaydi', () async {
    final (runner, _) = await _build(
      _project(),
      _env(splitPerAbi: true, targetPlatform: 'android-arm64'),
    );
    final aabCall = runner.calls.firstWhere((c) => c.args.contains('appbundle'));
    expect(aabCall.args, isNot(contains('--split-per-abi')));
    expect(aabCall.args.any((a) => a.startsWith('--target-platform')), isFalse);
  });

  test('buildArgs qo`shiladi', () async {
    final (runner, _) = await _build(
      _project(),
      _env(buildArgs: ['--obfuscate', '--split-debug-info=sym']),
    );
    expect(runner.lastCallTo('flutter')!.args,
        containsAll(['--obfuscate', '--split-debug-info=sym']));
  });

  test('ikkita artefakt — ikkita chaqiruv, appbundle birinchi', () async {
    final (runner, artifacts) = await _build(
      _project(apkName: 'app-arm64-v8a-release.apk'),
      _env(
        artifacts: [ArtifactType.aab, ArtifactType.apk],
        splitPerAbi: true,
        targetPlatform: 'android-arm64',
      ),
    );
    expect(runner.calls, hasLength(2));
    expect(runner.calls[0].args, contains('appbundle'));
    expect(runner.calls[1].args, contains('apk'));
    expect(artifacts, hasLength(2));
  });

  test('artefakt yo`llari to`g`ri', () async {
    final root = _project(apkName: 'app-arm64-v8a-release.apk');
    final (_, artifacts) = await _build(
      root,
      _env(
        artifacts: [ArtifactType.aab, ArtifactType.apk],
        splitPerAbi: true,
        targetPlatform: 'android-arm64',
      ),
    );
    expect(artifacts[0].path,
        '$root/build/app/outputs/bundle/release/app-release.aab');
    expect(artifacts[1].path,
        '$root/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk');
  });

  test('split emas apk boshqa nom oladi', () async {
    final root = _project(apkName: 'app-release.apk');
    final (_, artifacts) = await _build(root, _env(artifacts: [ArtifactType.apk]));
    expect(artifacts.single.path,
        '$root/build/app/outputs/flutter-apk/app-release.apk');
  });

  test('flutter yiqilsa BuildException, stderr xabarda bo`ladi', () async {
    final runner = FakeProcessRunner()
      ..responses['flutter'] = const ProcessResult(1, '', 'Gradle task failed');

    expect(
      () => AndroidBuilder(runner: runner, logger: _quiet()).build(
        projectRoot: _project(),
        env: _env(),
        buildName: '1.2.3',
        buildNumber: 46,
      ),
      throwsA(isA<BuildException>()
          .having((e) => e.message, 'message', contains('Gradle task failed'))),
    );
  });

  test('kutilgan artefakt paydo bo`lmasa BuildException', () async {
    // flutter 0 qaytarsa ham fayl yo'q bo'lishi mumkin — bu haqiqiy himoya.
    expect(
      () => AndroidBuilder(runner: FakeProcessRunner(), logger: _quiet()).build(
        projectRoot: _project(aab: false),
        env: _env(),
        buildName: '1.2.3',
        buildNumber: 46,
      ),
      throwsA(isA<BuildException>()
          .having((e) => e.message, 'message', contains('app-release.aab'))),
    );
  });

  test('android sozlanmagan bo`lsa bo`sh ro`yxat', () async {
    final runner = FakeProcessRunner();
    final out = await AndroidBuilder(runner: runner, logger: _quiet()).build(
      projectRoot: _project(),
      env: const EnvironmentConfig(
        name: 'dev',
        branch: null,
        dartDefines: {},
        buildArgs: [],
        android: null,
        ios: null,
        notify: null,
      ),
      buildName: '1.2.3',
      buildNumber: 46,
    );
    expect(out, isEmpty);
    expect(runner.calls, isEmpty);
  });
}
