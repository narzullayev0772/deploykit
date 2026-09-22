import 'dart:io';

import 'package:deploykit/src/build/build_artifact.dart';
import 'package:deploykit/src/config/deploy_config.dart';
import 'package:deploykit/src/core/build_manifest.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:test/test.dart';

BuildManifest _sample(String env) => BuildManifest(
      env: env,
      buildName: '1.2.3',
      buildNumber: 46,
      builtAt: DateTime.utc(2026, 9, 22, 14, 30),
      artifacts: [
        const BuildArtifact(ArtifactType.aab, '/b/app.aab'),
        const BuildArtifact(ArtifactType.apk, '/b/app.apk'),
      ],
    );

void main() {
  test('yozib-o`qilganda barcha maydonlar saqlanadi', () {
    final f = File('${Directory.systemTemp.createTempSync().path}/m.json');
    _sample('dev').write(f);

    final back = BuildManifest.read(f);
    expect(back.env, 'dev');
    expect(back.buildName, '1.2.3');
    expect(back.buildNumber, 46);
    expect(back.builtAt, DateTime.utc(2026, 9, 22, 14, 30));
    expect(back.artifacts.map((a) => a.type),
        [ArtifactType.aab, ArtifactType.apk]);
    expect(back.artifacts.first.path, '/b/app.aab');
  });

  test('write kerak bo`lsa katalog yaratadi', () {
    final f = File(
        '${Directory.systemTemp.createTempSync().path}/.deploykit/last_build.json');
    _sample('dev').write(f);
    expect(f.existsSync(), isTrue);
  });

  test('fayl yo`q bo`lsa build tavsiya qilinadi', () {
    expect(
      () => BuildManifest.read(File('/yo/q/m.json')),
      throwsA(isA<PreflightException>()
          .having((e) => e.message, 'message', contains('deploykit build'))),
    );
  });

  test('verifyEnv mos kelsa o`tadi', () {
    _sample('dev').verifyEnv('dev');
  });

  test('verifyEnv mos kelmasa ikkala nom bilan xato beradi', () {
    expect(
      () => _sample('dev').verifyEnv('release'),
      throwsA(isA<PreflightException>().having(
        (e) => e.message,
        'message',
        allOf(contains('dev'), contains('release')),
      )),
    );
  });

  test('artifactOf turi bo`yicha topadi', () {
    expect(_sample('dev').artifactOf(ArtifactType.apk)!.path, '/b/app.apk');
    expect(_sample('dev').artifactOf(ArtifactType.ipa), isNull);
  });
}
