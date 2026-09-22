import 'dart:io';

import 'package:args/command_runner.dart';

import '../core/build_number.dart';
import '../core/logger.dart';
import 'templates.dart';

/// `deploy.yaml` skeletini va yordamchi fayllarni yaratadi.
class InitCommand extends Command<int> {
  InitCommand({required this.workingDir, required this.logger}) {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Mavjud deploy.yaml ni qayta yozish.',
    );
  }

  final Directory workingDir;
  final Logger logger;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Bo\'sh deploy.yaml, .env.example va .last_build_number yaratadi.';

  @override
  Future<int> run() => execute(force: argResults!.flag('force'));

  /// Test'lardan to'g'ridan-to'g'ri chaqiriladi.
  Future<int> execute({bool force = false}) async {
    final configFile = File('${workingDir.path}/deploy.yaml');

    if (configFile.existsSync() && !force) {
      logger.err('${configFile.path} allaqachon mavjud.');
      logger.info('Qayta yozish uchun: deploykit init --force');
      return 2;
    }

    configFile.writeAsStringSync(deployYamlTemplate);
    logger.ok('deploy.yaml yaratildi');

    File('${workingDir.path}/.env.example')
        .writeAsStringSync(envExampleTemplate);
    logger.ok('.env.example yaratildi');

    _initBuildNumber();
    _updateGitignore();

    logger.blank();
    logger.info('Keyingi qadamlar:');
    logger.info('  1. cp .env.example .env  — va qiymatlarni to\'ldiring');
    logger.info('  2. deploy.yaml dagi app.android_package ni to\'g\'rilang');
    logger.info('  3. deploykit doctor --dev');
    logger.info('  4. deploykit publish --dev --dry-run');
    return 0;
  }

  void _initBuildNumber() {
    final pubspec = '${workingDir.path}/pubspec.yaml';
    final target = File('${workingDir.path}/.last_build_number');

    BuildNumber(target).initialiseFrom(pubspec);
    final value = target.readAsStringSync().trim();

    if (!File(pubspec).existsSync()) {
      logger.warn(
        'pubspec.yaml topilmadi — .last_build_number 0 dan boshlandi.',
      );
    } else {
      logger.ok('.last_build_number = $value (pubspec.yaml dan)');
    }
  }

  /// `.env` va `.deploykit/` ni git'dan chetda ushlab turadi.
  void _updateGitignore() {
    const needed = ['.env', '.deploykit/'];
    final file = File('${workingDir.path}/.gitignore');

    final existing = file.existsSync() ? file.readAsLinesSync() : <String>[];
    final present = existing.map((l) => l.trim()).toSet();
    final missing = needed.where((n) => !present.contains(n)).toList();

    if (missing.isEmpty) return;

    final buffer = StringBuffer();
    if (existing.isNotEmpty) {
      buffer.writeln(existing.join('\n'));
      if (existing.last.trim().isNotEmpty) buffer.writeln();
    }
    buffer.writeln('# deploykit — maxfiy qiymatlar va ishlash holati');
    for (final m in missing) {
      buffer.writeln(m);
    }
    file.writeAsStringSync(buffer.toString());
    logger.ok('.gitignore yangilandi: ${missing.join(', ')}');
  }
}
