import 'dart:async';
import 'dart:io';

import 'package:deploykit/src/commands/init_command.dart';
import 'package:deploykit/src/config/config_loader.dart';
import 'package:deploykit/src/config/env_resolver.dart';
import 'package:deploykit/src/core/logger.dart';
import 'package:test/test.dart';

Directory _tmp() => Directory.systemTemp.createTempSync();

/// Test chiqishini toza saqlash uchun logger hech qayerga yozmaydi.
Logger _quiet() =>
    Logger(color: false, sink: IOSink(StreamController<List<int>>().sink));

Future<int> _init(Directory d, {bool force = false}) =>
    InitCommand(workingDir: d, logger: _quiet()).execute(force: force);

void main() {
  test('uchta faylni yaratadi', () async {
    final d = _tmp();
    expect(await _init(d), 0);

    expect(File('${d.path}/deploy.yaml').existsSync(), isTrue);
    expect(File('${d.path}/.env.example').existsSync(), isTrue);
    expect(File('${d.path}/.last_build_number').existsSync(), isTrue);
  });

  test('yaratilgan deploy.yaml ConfigLoader bilan o`qiladi', () async {
    final d = _tmp();
    await _init(d);

    final src = File('${d.path}/deploy.yaml').readAsStringSync();
    // .env.example dagi barcha kalitlarni bo'sh bo'lmagan qiymat bilan beramiz.
    final keys = RegExp(r'^([A-Z_]+)=', multiLine: true)
        .allMatches(File('${d.path}/.env.example').readAsStringSync())
        .map((m) => m.group(1)!);
    final env = EnvResolver({for (final k in keys) k: 'x'});

    final config = const ConfigLoader().parse(src, isJson: false, env: env);
    expect(config.environments.keys, containsAll(['dev', 'release']));
    expect(config.environment('release').dartDefines, isEmpty);
  });

  test(r'.env.example barcha ${VAR} nomlarini qamrab oladi', () async {
    final d = _tmp();
    await _init(d);

    // Izoh qatorlari hisobga olinmaydi — ular ${VAR} ni hujjat sifatida
    // tilga oladi, haqiqiy havola sifatida emas.
    final yamlBody = File('${d.path}/deploy.yaml')
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('#'))
        .join('\n');
    final referenced = RegExp(r'\$\{([A-Z_]+)\}')
        .allMatches(yamlBody)
        .map((m) => m.group(1)!)
        .toSet();
    final declared = RegExp(r'^([A-Z_]+)=', multiLine: true)
        .allMatches(File('${d.path}/.env.example').readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();

    expect(declared, containsAll(referenced));
  });

  test('pubspec dagi build raqamini oladi', () async {
    final d = _tmp();
    File('${d.path}/pubspec.yaml').writeAsStringSync('version: 1.2.3+45\n');
    await _init(d);
    expect(File('${d.path}/.last_build_number').readAsStringSync().trim(), '45');
  });

  test('pubspec yo`q bo`lsa 0', () async {
    final d = _tmp();
    await _init(d);
    expect(File('${d.path}/.last_build_number').readAsStringSync().trim(), '0');
  });

  test('deploy.yaml allaqachon bor bo`lsa qayta yozmaydi', () async {
    final d = _tmp();
    final f = File('${d.path}/deploy.yaml')..writeAsStringSync('mening faylim');
    expect(await _init(d), 2);
    expect(f.readAsStringSync(), 'mening faylim');
  });

  test('--force bilan qayta yoziladi', () async {
    final d = _tmp();
    final f = File('${d.path}/deploy.yaml')..writeAsStringSync('eski');
    expect(await _init(d, force: true), 0);
    expect(f.readAsStringSync(), isNot('eski'));
  });

  test('.gitignore ga .env va .deploykit/ qo`shadi', () async {
    final d = _tmp();
    File('${d.path}/.gitignore').writeAsStringSync('build/\n');
    await _init(d);

    final gi = File('${d.path}/.gitignore').readAsStringSync();
    expect(gi, contains('build/'));
    expect(gi, contains('.env'));
    expect(gi, contains('.deploykit/'));
  });

  test('.gitignore yo`q bo`lsa yaratadi', () async {
    final d = _tmp();
    await _init(d);
    expect(File('${d.path}/.gitignore').readAsStringSync(), contains('.env'));
  });

  test('.gitignore da allaqachon bor qator takrorlanmaydi', () async {
    final d = _tmp();
    File('${d.path}/.gitignore').writeAsStringSync('.env\n.deploykit/\n');
    await _init(d);

    final lines = File('${d.path}/.gitignore').readAsLinesSync();
    expect(lines.where((l) => l.trim() == '.env').length, 1);
    expect(lines.where((l) => l.trim() == '.deploykit/').length, 1);
  });
}
