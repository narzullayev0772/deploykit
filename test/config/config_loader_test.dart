import 'package:deploykit/src/config/config_loader.dart';
import 'package:deploykit/src/config/deploy_config.dart';
import 'package:deploykit/src/config/env_resolver.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:test/test.dart';

const _yaml = r'''
version: 1
app:
  root: .
  android_package: com.example.app
environments:
  dev:
    branch: '^versions/.+/dev$'
    dart_defines:
      PROD_URL: 'false'
      INSPECTOR: 'true'
    build_args: ['--obfuscate']
    android:
      artifacts: [aab, apk]
      apk:
        split_per_abi: true
        target_platform: android-arm64
      play:
        track: internal
        status: completed
    ios:
      testflight_internal_only: true
    notify:
      telegram:
        message: 'DEV build'
        attach: apk
        max_size_mb: 50
        on_oversize: zip
  release:
    branch: '^versions/.+/release$'
    dart_defines: {}
    android:
      artifacts: [aab]
      play:
        track: production
        status: draft
    ios:
      testflight_internal_only: false
integrations:
  play:
    service_account: ${PLAY_SA}
  app_store:
    key_id: ${ASC_KEY}
    issuer_id: ${ASC_ISSUER}
    private_key: ${ASC_P8}
    team_id: ${ASC_TEAM}
  telegram:
    bot_token: ${TG_TOKEN}
    chat_id: ${TG_CHAT}
''';

const _minimal = r'''
version: 1
app: {root: ., android_package: a.b.c}
environments:
  dev: {}
''';

DeployConfig _parse(String src, {bool isJson = false}) =>
    ConfigLoader().parse(
      src,
      isJson: isJson,
      env: EnvResolver({
        'PLAY_SA': '/k/sa.json',
        'ASC_KEY': 'EXAMPLE123',
        'ASC_ISSUER': '11111111-2222',
        'ASC_P8': '/k/AuthKey.p8',
        'ASC_TEAM': 'TEAMID1234',
        'TG_TOKEN': 'tok',
        'TG_CHAT': '-100123',
      }),
    );

void main() {
  group('to`liq yaml', () {
    test('ildiz maydonlari', () {
      final c = _parse(_yaml);
      expect(c.version, 1);
      expect(c.app.root, '.');
      expect(c.app.androidPackage, 'com.example.app');
      expect(c.environments.keys, containsAll(['dev', 'release']));
      expect(c.buildNumberFile, '.last_build_number');
      expect(c.envFile, '.env');
    });

    test('dev muhiti', () {
      final dev = _parse(_yaml).environment('dev');
      expect(dev.name, 'dev');
      expect(dev.branch, r'^versions/.+/dev$');
      expect(dev.dartDefines, {'PROD_URL': 'false', 'INSPECTOR': 'true'});
      expect(dev.buildArgs, ['--obfuscate']);
      expect(dev.android!.artifacts, [ArtifactType.aab, ArtifactType.apk]);
      expect(dev.android!.apk.splitPerAbi, isTrue);
      expect(dev.android!.apk.targetPlatform, 'android-arm64');
      expect(dev.android!.play.track, 'internal');
      expect(dev.android!.play.status, 'completed');
      expect(dev.ios!.testflightInternalOnly, isTrue);
      expect(dev.notify!.telegram!.message, 'DEV build');
      expect(dev.notify!.telegram!.attach, ArtifactType.apk);
      expect(dev.notify!.telegram!.maxSizeMb, 50);
      expect(dev.notify!.telegram!.onOversize, OversizePolicy.zip);
    });

    test('bo`sh dart_defines haqiqiy qiymat — define uzatilmaydi', () {
      expect(_parse(_yaml).environment('release').dartDefines, isEmpty);
    });

    test(r'${VAR} integratsiyalarda almashtiriladi', () {
      final i = _parse(_yaml).integrations;
      expect(i.play!.serviceAccount, '/k/sa.json');
      expect(i.appStore!.keyId, 'EXAMPLE123');
      expect(i.appStore!.teamId, 'TEAMID1234');
      expect(i.telegram!.botToken, 'tok');
      expect(i.telegram!.chatId, '-100123');
    });
  });

  group('branch uch holati', () {
    test('maydon yo`q bo`lsa null', () {
      expect(_parse(_minimal).environment('dev').branch, isNull);
    });

    test('branch: null bo`lsa null', () {
      expect(
        _parse('''
version: 1
app: {root: ., android_package: a.b.c}
environments:
  dev: {branch: null}
''').environment('dev').branch,
        isNull,
      );
    });

    test("branch: '' xato beradi", () {
      expect(
        () => _parse('''
version: 1
app: {root: ., android_package: a.b.c}
environments:
  dev: {branch: ''}
'''),
        throwsA(isA<ConfigException>().having(
          (e) => e.message,
          'message',
          allOf(contains('branch'), contains('dev')),
        )),
      );
    });
  });

  group('validatsiya', () {
    test('noma`lum muhit xato beradi va mavjudlarini sanaydi', () {
      expect(
        () => _parse(_yaml).environment('staging'),
        throwsA(isA<ConfigException>().having(
          (e) => e.message,
          'message',
          allOf(contains('staging'), contains('dev'), contains('release')),
        )),
      );
    });

    test('version != 1 xato beradi', () {
      expect(
        () => _parse('''
version: 2
app: {root: ., android_package: a.b.c}
environments: {dev: {}}
'''),
        throwsA(isA<ConfigException>()
            .having((e) => e.message, 'message', contains('version'))),
      );
    });

    test('environments bo`sh bo`lsa xato', () {
      expect(
        () => _parse('''
version: 1
app: {root: ., android_package: a.b.c}
environments: {}
'''),
        throwsA(isA<ConfigException>()
            .having((e) => e.message, 'message', contains('environments'))),
      );
    });

    test('app yo`q bo`lsa xato', () {
      expect(
        () => _parse('version: 1\nenvironments: {dev: {}}\n'),
        throwsA(isA<ConfigException>()
            .having((e) => e.message, 'message', contains('app'))),
      );
    });

    test('noma`lum on_oversize xato beradi', () {
      expect(
        () => _parse('''
version: 1
app: {root: ., android_package: a.b.c}
environments:
  dev:
    notify:
      telegram: {message: x, on_oversize: teleport}
'''),
        throwsA(isA<ConfigException>().having(
          (e) => e.message,
          'message',
          allOf(contains('on_oversize'), contains('teleport')),
        )),
      );
    });

    test('noma`lum artifact turi xato beradi', () {
      expect(
        () => _parse('''
version: 1
app: {root: ., android_package: a.b.c}
environments:
  dev:
    android:
      artifacts: [aab, exe]
      play: {track: internal, status: completed}
'''),
        throwsA(isA<ConfigException>()
            .having((e) => e.message, 'message', contains('exe'))),
      );
    });

    test('android bor, lekin play yo`q — xato', () {
      expect(
        () => _parse('''
version: 1
app: {root: ., android_package: a.b.c}
environments:
  dev:
    android:
      artifacts: [aab]
'''),
        throwsA(isA<ConfigException>()
            .having((e) => e.message, 'message', contains('play'))),
      );
    });

    test('yaroqsiz yaml xato beradi', () {
      expect(
        () => _parse('version: 1\n  bad indent: ['),
        throwsA(isA<ConfigException>()),
      );
    });
  });

  test('json va yaml bir xil natija beradi', () {
    const json = r'''
{"version":1,"app":{"root":".","android_package":"a.b.c"},
 "environments":{"dev":{"branch":"^main$","dart_defines":{"K":"v"}}}}
''';
    final c = _parse(json, isJson: true);
    expect(c.environment('dev').branch, r'^main$');
    expect(c.environment('dev').dartDefines, {'K': 'v'});
  });
}
