import 'dart:async';
import 'dart:io';

import 'package:deploykit/src/config/config_loader.dart';
import 'package:deploykit/src/config/env_resolver.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:deploykit/src/core/logger.dart';
import 'package:deploykit/src/core/preflight.dart';
import 'package:deploykit/src/core/process_runner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Logger _quiet() =>
    Logger(color: false, sink: IOSink(StreamController<List<int>>().sink));

http.Client _tg({bool ok = true, int status = 200}) =>
    MockClient((_) async => http.Response('{"ok":$ok}', status));

/// Vaqtinchalik loyiha: kalit fayllar, .last_build_number, ixtiyoriy .git
String _project({
  bool git = true,
  bool buildNumber = true,
  String buildNumberValue = '45',
  bool keys = true,
  bool emptyP8 = false,
}) {
  final root = Directory.systemTemp.createTempSync().path;
  if (git) Directory('$root/.git').createSync();
  if (buildNumber) {
    File('$root/.last_build_number').writeAsStringSync(buildNumberValue);
  }
  if (keys) {
    File('$root/sa.json').writeAsStringSync('{"type":"service_account"}');
    File('$root/AuthKey.p8')
        .writeAsStringSync(emptyP8 ? '' : '-----BEGIN PRIVATE KEY-----');
  }
  return root;
}

DeployConfig _config(String root, {String? branch = r'^main$'}) {
  final branchLine = branch == null ? '' : "    branch: '$branch'\n";
  return const ConfigLoader().parse('''
version: 1
app: {root: ., android_package: a.b.c}
environments:
  dev:
$branchLine    android:
      artifacts: [aab]
      play: {track: internal, status: completed}
    ios:
      testflight_internal_only: true
    notify:
      telegram: {message: x}
integrations:
  play: {service_account: $root/sa.json}
  app_store:
    key_id: K
    issuer_id: I
    private_key: $root/AuthKey.p8
    team_id: T
  telegram: {bot_token: tok, chat_id: '-1'}
''', isJson: false, env: EnvResolver({}));
}

Preflight _pre(
  String root, {
  ProcessRunner? runner,
  http.Client? client,
  String? branch = r'^main$',
  PlayProbe? playProbe,
}) {
  final config = _config(root, branch: branch);
  return Preflight(
    runner: runner ??
        (FakeProcessRunner()..responses['git'] = const ProcessResult(0, 'main\n', '')),
    client: client ?? _tg(),
    config: config,
    env: config.environment('dev'),
    logger: _quiet(),
    projectRoot: root,
    playProbe: playProbe ?? (_) async {},
  );
}

CheckResult _find(List<CheckResult> rs, String name) =>
    rs.firstWhere((r) => r.name.contains(name));

void main() {
  test('hammasi joyida bo`lsa fail yo`q', () async {
    final rs = await _pre(_project()).runAll();
    expect(rs.where((r) => r.status == CheckStatus.fail), isEmpty);
  });

  test('assertReady toza holatda otmaydi', () async {
    await _pre(_project()).assertReady();
  });

  test('flutter yo`q — fail va assertReady otadi', () async {
    final runner = FakeProcessRunner()
      ..responses['flutter'] = const ProcessResult(127, '', 'not found')
      ..responses['git'] = const ProcessResult(0, 'main\n', '');

    final pre = _pre(_project(), runner: runner);
    expect(_find(await pre.runAll(), 'flutter').status, CheckStatus.fail);
    await expectLater(pre.assertReady(), throwsA(isA<PreflightException>()));
  });

  test('vtool mavjudligi `which` orqali tekshiriladi', () async {
    // vtool sinov rejimiga ega emas: `vtool -help` ham 1 qaytaradi.
    // Uni ishga tushirib tekshirish o'rnatilgan vtool'ni ham "yo'q" deb
    // ko'rsatadi va deploy'ni bekordan bloklaydi.
    final runner = FakeProcessRunner()
      ..responses['git'] = const ProcessResult(0, 'main\n', '')
      ..responses['vtool'] = const ProcessResult(1, '', 'usage: vtool ...');

    final rs = await _pre(_project(), runner: runner).runAll();
    expect(_find(rs, 'vtool').status, CheckStatus.pass);
    expect(
      runner.calls.any((c) => c.executable == 'which' && c.args.contains('vtool')),
      isTrue,
    );
  });

  test('vtool PATH da yo`q bo`lsa iOS uchun fail', () async {
    final runner = FakeProcessRunner()
      ..responses['git'] = const ProcessResult(0, 'main\n', '')
      ..responses['which'] = const ProcessResult(1, '', '');

    final rs = await _pre(_project(), runner: runner).runAll();
    expect(_find(rs, 'vtool').status, CheckStatus.fail);
  });

  test('iOS kerak emas bo`lsa xcodebuild yo`qligi warn', () async {
    final runner = FakeProcessRunner()
      ..responses['xcodebuild'] = const ProcessResult(127, '', '')
      ..responses['git'] = const ProcessResult(0, 'main\n', '');

    final rs = await _pre(_project(), runner: runner).runAll(ios: false);
    expect(_find(rs, 'xcodebuild').status, CheckStatus.warn);
  });

  test('iOS kerak bo`lsa xcodebuild yo`qligi fail', () async {
    final runner = FakeProcessRunner()
      ..responses['xcodebuild'] = const ProcessResult(127, '', '')
      ..responses['git'] = const ProcessResult(0, 'main\n', '');

    final rs = await _pre(_project(), runner: runner).runAll();
    expect(_find(rs, 'xcodebuild').status, CheckStatus.fail);
  });

  group('git', () {
    test('branch regex yo`q bo`lsa git repo talab qilinmaydi', () async {
      final rs = await _pre(_project(git: false), branch: null).runAll();
      expect(rs.where((r) => r.status == CheckStatus.fail), isEmpty);
    });

    test('branch regex bor, git repo yo`q — fail', () async {
      final rs = await _pre(_project(git: false)).runAll();
      expect(_find(rs, 'git repo').status, CheckStatus.fail);
    });

    test('branch mos kelmasa fail, joriy va pattern ko`rsatiladi', () async {
      final runner = FakeProcessRunner()
        ..responses['git'] = const ProcessResult(0, 'feat/x\n', '');

      final r = _find(await _pre(_project(), runner: runner).runAll(), 'branch');
      expect(r.status, CheckStatus.fail);
      expect(r.detail, allOf(contains('feat/x'), contains('main')));
    });

    test('allowBranchMismatch bilan warn', () async {
      final runner = FakeProcessRunner()
        ..responses['git'] = const ProcessResult(0, 'feat/x\n', '');

      final rs = await _pre(_project(), runner: runner)
          .runAll(allowBranchMismatch: true);
      expect(_find(rs, 'branch').status, CheckStatus.warn);
    });
  });

  group('kalit fayllar', () {
    test('.p8 bo`sh bo`lsa fail — mavjudlik yetarli emas', () async {
      final rs = await _pre(_project(emptyP8: true)).runAll();
      final r = _find(rs, '.p8');
      expect(r.status, CheckStatus.fail);
      expect(r.detail, contains('empty'));
    });

    test('kalit fayli yo`q bo`lsa fail, yo`l ko`rsatiladi', () async {
      final root = _project(keys: false);
      final rs = await _pre(root).runAll();
      expect(_find(rs, 'service-account').status, CheckStatus.fail);
      expect(_find(rs, 'service-account').detail, contains(root));
    });
  });

  test('.last_build_number yo`q — fail, init tavsiya qilinadi', () async {
    final rs = await _pre(_project(buildNumber: false)).runAll();
    final r = _find(rs, '.last_build_number');
    expect(r.status, CheckStatus.fail);
    expect(r.detail, contains('deploykit init'));
  });

  test('.last_build_number axlat bo`lsa fail', () async {
    final rs = await _pre(_project(buildNumberValue: 'abc')).runAll();
    expect(_find(rs, '.last_build_number').status, CheckStatus.fail);
  });

  group('tarmoq', () {
    test('checkNetwork: false — tarmoq tekshiruvlari bajarilmaydi', () async {
      var probed = false;
      final rs = await _pre(
        _project(),
        playProbe: (_) async => probed = true,
      ).runAll(checkNetwork: false);

      expect(probed, isFalse);
      expect(rs.where((r) => r.name.contains('Telegram')), isEmpty);
      expect(rs.where((r) => r.name.contains('Play API')), isEmpty);
    });

    test('Play kaliti rad etilsa fail', () async {
      final rs = await _pre(
        _project(),
        playProbe: (_) async => throw const UploadException('kalit eskirgan'),
      ).runAll();
      expect(_find(rs, 'Play API').status, CheckStatus.fail);
      expect(_find(rs, 'Play API').detail, contains('kalit eskirgan'));
    });

    test('Telegram tokeni rad etilsa fail', () async {
      final rs = await _pre(_project(), client: _tg(ok: false, status: 401))
          .runAll();
      expect(_find(rs, 'Telegram').status, CheckStatus.fail);
    });

    test('Telegram ishlasa pass', () async {
      final rs = await _pre(_project()).runAll();
      expect(_find(rs, 'Telegram').status, CheckStatus.pass);
    });
  });

  test('assertReady xabarida barcha fail sanaladi', () async {
    final runner = FakeProcessRunner()
      ..responses['flutter'] = const ProcessResult(127, '', '')
      ..responses['git'] = const ProcessResult(0, 'feat/x\n', '');

    await expectLater(
      _pre(_project(), runner: runner).assertReady(),
      throwsA(isA<PreflightException>().having(
        (e) => e.message,
        'message',
        allOf(contains('flutter'), contains('branch'), contains('doctor')),
      )),
    );
  });
}
