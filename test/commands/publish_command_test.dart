import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:deploykit/src/commands/build_command.dart';
import 'package:deploykit/src/commands/publish_command.dart';
import 'package:deploykit/src/commands/upload_command.dart';
import 'package:deploykit/src/core/logger.dart';
import 'package:deploykit/src/core/process_runner.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Logger _quiet() =>
    Logger(color: false, sink: IOSink(StreamController<List<int>>().sink));

http.Client _http() =>
    MockClient((_) async => http.Response('{"ok":true}', 200));

/// Play API javoblarini taqlid qiladi.
///
/// AAB yuklash ishlab chiqarishda resumable protokol bilan ketadi (fayl
/// odatda 50MB dan katta), shuning uchun mock ham shu protokolni bajaradi:
/// POST session ochadi va `location` sarlavhasini qaytaradi, keyin PUT
/// mazmunni yuboradi.
http.Client _play() => MockClient((req) async {
      const json = {'content-type': 'application/json'};
      final path = req.url.path;

      if (path.contains('/bundles')) {
        if (req.method == 'POST') {
          return http.Response('', 200, headers: {
            'location': 'https://upload.example/session/1',
            ...json,
          });
        }
        return http.Response('{"versionCode": 4211}', 200, headers: json);
      }
      if (req.url.host == 'upload.example') {
        return http.Response('{"versionCode": 4211}', 200, headers: json);
      }
      return http.Response('{"id": "edit-1"}', 200, headers: json);
    });

const _yaml = r'''
version: 1
app: {root: ., android_package: a.b.c}
environments:
  dev:
    branch: '^main$'
    dart_defines: {PROD_URL: 'false'}
    android:
      artifacts: [aab]
      play: {track: internal, status: completed}
    notify:
      telegram: {message: 'DEV build'}
  release:
    branch: '^main$'
    dart_defines: {}
    android:
      artifacts: [aab]
      play: {track: production, status: draft}
integrations:
  play:
    # Block uslubi: flow uslubida ({...}) ${VAR} ning { belgisi YAML
    # tomonidan ichma-ich mapping deb o'qiladi.
    service_account: ${SA}
  telegram: {bot_token: tok, chat_id: '-1'}
''';

/// To'liq tayyor loyiha: config, kalitlar, git, artefakt fayli.
String _project() {
  final root = Directory.systemTemp.createTempSync().path;
  File('$root/sa.json').writeAsStringSync('{"type":"service_account"}');
  File('$root/deploy.yaml').writeAsStringSync(_yaml);
  File('$root/.env').writeAsStringSync('SA=$root/sa.json\n');
  File('$root/.last_build_number').writeAsStringSync('45');
  File('$root/pubspec.yaml').writeAsStringSync('version: 1.2.3+45\n');
  Directory('$root/.git').createSync();
  File('$root/build/app/outputs/bundle/release/app-release.aab')
    ..createSync(recursive: true)
    ..writeAsStringSync('soxta aab');
  return root;
}

FakeProcessRunner _runner() => FakeProcessRunner()
  ..responses['git'] = const ProcessResult(0, 'main\n', '');

Future<int> _run(
  String root,
  List<String> args, {
  FakeProcessRunner? runner,
}) async {
  final r = runner ?? _runner();
  final dir = Directory(root);
  final logger = _quiet();
  final cr = CommandRunner<int>('deploykit', 'test')
    ..addCommand(BuildCommand(
        workingDir: dir, logger: logger, runner: r, client: _http(),
        playProbe: (_) async {}, playClientFactory: (_) async => _play()))
    ..addCommand(UploadCommand(
        workingDir: dir, logger: logger, runner: r, client: _http(),
        playProbe: (_) async {}, playClientFactory: (_) async => _play()))
    ..addCommand(PublishCommand(
        workingDir: dir, logger: logger, runner: r, client: _http(),
        playProbe: (_) async {}, playClientFactory: (_) async => _play()));
  return await cr.run(args) ?? 0;
}

int _buildNumber(String root) =>
    int.parse(File('$root/.last_build_number').readAsStringSync().trim());

Map<String, Object?> _manifest(String root) => jsonDecode(
      File('$root/.deploykit/last_build.json').readAsStringSync(),
    ) as Map<String, Object?>;

void main() {
  group('muhit tanlash', () {
    test('--dev va --release birga berilsa xato', () async {
      await expectLater(
        _run(_project(), ['publish', '--dev', '--release', '--dry-run']),
        throwsA(predicate((e) => '$e'.contains('bitta muhit'))),
      );
    });

    test('muhit ko`rsatilmasa mavjudlari sanaladi', () async {
      await expectLater(
        _run(_project(), ['publish', '--dry-run']),
        throwsA(predicate(
            (e) => '$e'.contains('dev') && '$e'.contains('release'))),
      );
    });

    test('--env staging yo`q muhit — xato', () async {
      await expectLater(
        _run(_project(), ['publish', '--env', 'staging', '--dry-run']),
        throwsA(predicate((e) => '$e'.contains('staging'))),
      );
    });
  });

  group('--dry-run', () {
    test('hech qanday `flutter build` chaqiruvi yo`q', () async {
      // Preflight baribir `flutter --version` ni chaqiradi — bu to'g'ri,
      // dry-run haqiqiy tekshiruv bo'lishi kerak. Taqiqlangani — build.
      final r = _runner();
      await _run(_project(), ['publish', '--dev', '--dry-run'], runner: r);
      expect(
        r.calls.where((c) => c.args.contains('build')),
        isEmpty,
      );
    });

    test('build raqamini oshirmaydi', () async {
      final root = _project();
      await _run(root, ['publish', '--dev', '--dry-run']);
      expect(_buildNumber(root), 45);
    });

    test('config xato bo`lsa baribir yiqiladi', () async {
      final root = _project();
      File('$root/deploy.yaml').writeAsStringSync('version: 99\n');
      await expectLater(
        _run(root, ['publish', '--dev', '--dry-run']),
        throwsA(predicate((e) => '$e'.contains('version'))),
      );
    });

    test('kalit yo`q bo`lsa yiqiladi', () async {
      final root = _project();
      File('$root/sa.json').deleteSync();
      await expectLater(
        _run(root, ['publish', '--dev', '--dry-run']),
        throwsA(predicate((e) => '$e'.contains('service-account'))),
      );
    });
  });

  group('build', () {
    test('build raqamini bir marta oshiradi', () async {
      final root = _project();
      expect(await _run(root, ['build', '--dev']), 0);
      expect(_buildNumber(root), 46);
    });

    test('manifest yoziladi va env to`g`ri', () async {
      final root = _project();
      await _run(root, ['build', '--dev']);

      final m = _manifest(root);
      expect(m['env'], 'dev');
      expect(m['build_number'], 46);
      expect(m['build_name'], '1.2.3');
      expect((m['artifacts']! as List), hasLength(1));
    });

    test('flutter ga oshirilgan raqam uzatiladi', () async {
      final r = _runner();
      await _run(_project(), ['build', '--dev'], runner: r);
      expect(r.lastCallTo('flutter')!.args, contains('--build-number=46'));
    });

    test('build yiqilsa raqam qaytarilmaydi', () async {
      final root = _project();
      // Preflight `flutter --version` ni chaqiradi va u o'tishi kerak —
      // aks holda raqam umuman oshmaydi va test nimani tekshirayotgani
      // noaniq bo'lib qoladi.
      final r = _runner()
        ..responder = (exe, args) => exe == 'flutter' && args.contains('build')
            ? const ProcessResult(1, '', 'Gradle failed')
            : null;

      await expectLater(
        _run(root, ['build', '--dev'], runner: r),
        throwsA(anything),
      );
      // Raqamni qayta ishlatish Play tomonidan rad etiladi, o'tkazib
      // yuborish esa zararsiz.
      expect(_buildNumber(root), 46);
    });

    test('--android bilan iOS qurilmaydi', () async {
      final r = _runner();
      await _run(_project(), ['build', '--dev', '--android'], runner: r);
      expect(
        r.calls.where((c) => c.args.contains('ipa')),
        isEmpty,
      );
    });
  });

  group('upload', () {
    test('manifestsiz — build tavsiya qilinadi', () async {
      await expectLater(
        _run(_project(), ['upload', '--dev']),
        throwsA(predicate((e) => '$e'.contains('deploykit build'))),
      );
    });

    test('boshqa muhit manifesti bilan xato', () async {
      final root = _project();
      await _run(root, ['build', '--dev']);

      await expectLater(
        _run(root, ['upload', '--release']),
        throwsA(predicate(
            (e) => '$e'.contains('dev') && '$e'.contains('release'))),
      );
    });

    test('build raqamini oshirmaydi — qayta urinish xavfsiz', () async {
      final root = _project();
      await _run(root, ['build', '--dev']);
      expect(_buildNumber(root), 46);

      await _run(root, ['upload', '--dev', '--dry-run']);
      await _run(root, ['upload', '--dev', '--dry-run']);
      expect(_buildNumber(root), 46);
    });
  });

  group('publish', () {
    test('build va upload birga bajariladi', () async {
      final root = _project();
      expect(await _run(root, ['publish', '--dev']), 0);
      expect(_buildNumber(root), 46);
      expect(_manifest(root)['env'], 'dev');
    });

    test('release muhitida hech qanday --dart-define yo`q', () async {
      final r = _runner();
      await _run(_project(), ['build', '--release'], runner: r);
      expect(
        r.lastCallTo('flutter')!.args.where((a) => a.startsWith('--dart-define')),
        isEmpty,
      );
    });

    test('dev muhitida define uzatiladi', () async {
      final r = _runner();
      await _run(_project(), ['build', '--dev'], runner: r);
      expect(r.lastCallTo('flutter')!.args,
          contains('--dart-define=PROD_URL=false'));
    });

    test('branch mos kelmasa yiqiladi', () async {
      final r = FakeProcessRunner()
        ..responses['git'] = const ProcessResult(0, 'feat/x\n', '');
      await expectLater(
        _run(_project(), ['publish', '--dev'], runner: r),
        throwsA(predicate((e) => '$e'.contains('branch'))),
      );
    });

    test('--allow-branch-mismatch bilan o`tadi', () async {
      final r = FakeProcessRunner()
        ..responses['git'] = const ProcessResult(0, 'feat/x\n', '');
      expect(
        await _run(
          _project(),
          ['publish', '--dev', '--allow-branch-mismatch'],
          runner: r,
        ),
        0,
      );
    });
  });
}
