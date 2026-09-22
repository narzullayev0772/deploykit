import 'dart:io';

import 'package:args/command_runner.dart';

import '../core/build_number.dart';
import '../core/logger.dart';
import 'templates.dart';

/// Writes a `deploy.yaml` skeleton and its companion files.
class InitCommand extends Command<int> {
  InitCommand({required this.workingDir, required this.logger}) {
    argParser.addFlag(
      'force',
      abbr: 'f',
      negatable: false,
      help: 'Overwrite an existing deploy.yaml.',
    );
  }

  final Directory workingDir;
  final Logger logger;

  @override
  String get name => 'init';

  @override
  String get description =>
      'Create deploy.yaml, .env.example and .last_build_number.';

  @override
  Future<int> run() => execute(force: argResults!.flag('force'));

  /// Called directly from tests.
  Future<int> execute({bool force = false}) async {
    final configFile = File('${workingDir.path}/deploy.yaml');

    if (configFile.existsSync() && !force) {
      logger.err('${configFile.path} already exists.');
      logger.info('Use `deploykit init --force` to overwrite it.');
      return 2;
    }

    configFile.writeAsStringSync(deployYamlTemplate);
    logger.ok('Created deploy.yaml');

    File('${workingDir.path}/.env.example')
        .writeAsStringSync(envExampleTemplate);
    logger.ok('Created .env.example');

    _initBuildNumber();
    _updateGitignore();

    logger.blank();
    logger.info('Next steps:');
    logger.info('  1. cp .env.example .env   — then fill in the values');
    logger.info('  2. set app.android_package in deploy.yaml');
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
        'No pubspec.yaml found — .last_build_number starts at 0.',
      );
    } else {
      logger.ok('.last_build_number = $value (from pubspec.yaml)');
    }
  }

  /// Keeps `.env` and `.deploykit/` out of git.
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
    buffer.writeln('# deploykit — secrets and local state');
    for (final m in missing) {
      buffer.writeln(m);
    }
    file.writeAsStringSync(buffer.toString());
    logger.ok('Updated .gitignore: ${missing.join(', ')}');
  }
}
