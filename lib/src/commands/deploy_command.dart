import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/config_loader.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';

/// Shared flags for every command that selects an environment.
abstract class DeployCommand extends Command<int> {
  DeployCommand({required this.workingDir, required this.logger}) {
    argParser
      ..addOption(
        'env',
        abbr: 'e',
        help: 'Environment name from deploy.yaml.',
      )
      ..addFlag('dev', negatable: false, help: 'Shorthand for --env dev.')
      ..addFlag(
        'release',
        negatable: false,
        help: 'Shorthand for --env release.',
      )
      ..addFlag('android', negatable: false, help: 'Android only.')
      ..addFlag('ios', negatable: false, help: 'iOS only.')
      ..addOption(
        'config',
        abbr: 'c',
        defaultsTo: 'deploy.yaml',
        help: 'Path to the config file.',
      )
      ..addFlag(
        'allow-branch-mismatch',
        negatable: false,
        help: 'Deliberately bypass the branch guard.',
      );
  }

  final Directory workingDir;
  final Logger logger;

  /// With neither `--android` nor `--ios`, both platforms run.
  bool get doAndroid =>
      argResults!.flag('android') || !argResults!.flag('ios');

  bool get doIos => argResults!.flag('ios') || !argResults!.flag('android');

  bool get allowBranchMismatch => argResults!.flag('allow-branch-mismatch');

  DeployConfig loadConfig() =>
      const ConfigLoader().load('${workingDir.path}/${argResults!.option('config')}');

  /// Resolves the environment name from `--env`, `--dev` or `--release`.
  String resolveEnvName(DeployConfig config) {
    final explicit = argResults!.option('env');
    final dev = argResults!.flag('dev');
    final release = argResults!.flag('release');

    final chosen = <String>[
      ?explicit,
      if (dev) 'dev',
      if (release) 'release',
    ];

    if (chosen.length > 1) {
      throw const ConfigException(
        'Pick exactly one environment (--env, --dev or --release).',
      );
    }
    if (chosen.isEmpty) {
      throw ConfigException(
        'No environment given. Pass --dev, --release or --env <name>.\n'
        'Available environments: ${config.environments.keys.join(', ')}',
      );
    }
    return chosen.single;
  }

  /// Absolute path to the project root.
  String projectRoot(DeployConfig config) {
    final root = config.app.root;
    if (root == '.' || root.isEmpty) return workingDir.path;
    if (root.startsWith('/')) return root;
    return '${workingDir.path}/$root';
  }
}
