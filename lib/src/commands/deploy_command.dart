import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/config_loader.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';

/// Muhit tanlaydigan barcha buyruqlar uchun umumiy flaglar.
abstract class DeployCommand extends Command<int> {
  DeployCommand({required this.workingDir, required this.logger}) {
    argParser
      ..addOption(
        'env',
        abbr: 'e',
        help: 'deploy.yaml dagi muhit nomi.',
      )
      ..addFlag('dev', negatable: false, help: '--env dev ning qisqartmasi.')
      ..addFlag(
        'release',
        negatable: false,
        help: '--env release ning qisqartmasi.',
      )
      ..addFlag('android', negatable: false, help: 'Faqat Android.')
      ..addFlag('ios', negatable: false, help: 'Faqat iOS.')
      ..addOption(
        'config',
        abbr: 'c',
        defaultsTo: 'deploy.yaml',
        help: 'Config fayl yo\'li.',
      )
      ..addFlag(
        'allow-branch-mismatch',
        negatable: false,
        help: 'Branch tekshiruvini ataylab chetlab o\'tish.',
      );
  }

  final Directory workingDir;
  final Logger logger;

  /// `--android`/`--ios` berilmasa ikkalasi ham bajariladi.
  bool get doAndroid =>
      argResults!.flag('android') || !argResults!.flag('ios');

  bool get doIos => argResults!.flag('ios') || !argResults!.flag('android');

  bool get allowBranchMismatch => argResults!.flag('allow-branch-mismatch');

  DeployConfig loadConfig() =>
      const ConfigLoader().load('${workingDir.path}/${argResults!.option('config')}');

  /// `--env`, `--dev`, `--release` dan muhit nomini aniqlaydi.
  String resolveEnvName(DeployConfig config) {
    final explicit = argResults!.option('env');
    final dev = argResults!.flag('dev');
    final release = argResults!.flag('release');

    final chosen = <String>[
      if (explicit != null) explicit,
      if (dev) 'dev',
      if (release) 'release',
    ];

    if (chosen.length > 1) {
      throw const ConfigException(
        'Bir vaqtda faqat bitta muhit tanlanadi (--env, --dev yoki --release).',
      );
    }
    if (chosen.isEmpty) {
      throw ConfigException(
        'Muhit ko\'rsatilmagan. --dev, --release yoki --env <nom> bering.\n'
        'Mavjud muhitlar: ${config.environments.keys.join(', ')}',
      );
    }
    return chosen.single;
  }

  /// Loyiha ildizining absolyut yo'li.
  String projectRoot(DeployConfig config) {
    final root = config.app.root;
    if (root == '.' || root.isEmpty) return workingDir.path;
    if (root.startsWith('/')) return root;
    return '${workingDir.path}/$root';
  }
}
