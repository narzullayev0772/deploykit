import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/build_command.dart';
import 'commands/doctor_command.dart';
import 'commands/init_command.dart';
import 'commands/publish_command.dart';
import 'commands/upload_command.dart';
import 'core/logger.dart';

/// Assembles the commands and declares the global flags.
class DeploykitRunner extends CommandRunner<int> {
  DeploykitRunner({Directory? workingDir})
      : _workingDir = workingDir ?? Directory.current,
        super(
          'deploykit',
          'Flutter ilovalarini deploy.yaml orqali Play va App Store\'ga chiqaradi.',
        ) {
    argParser
      ..addFlag(
        'verbose',
        abbr: 'v',
        negatable: false,
        help: 'Bajarilayotgan buyruqlarni ham ko\'rsatish.',
      )
      ..addFlag(
        'color',
        defaultsTo: true,
        help: 'Rangli chiqish. --no-color bilan o\'chiriladi.',
      );

    addCommand(InitCommand(workingDir: _workingDir, logger: _logger));
    addCommand(DoctorCommand(workingDir: _workingDir, logger: _logger));
    addCommand(BuildCommand(workingDir: _workingDir, logger: _logger));
    addCommand(UploadCommand(workingDir: _workingDir, logger: _logger));
    addCommand(PublishCommand(workingDir: _workingDir, logger: _logger));
  }

  final Directory _workingDir;

  // A logger is needed before the global flags are parsed, so it is
  // configured late.
  final Logger _logger = Logger();

  @override
  Future<int> run(Iterable<String> args) async => await super.run(args) ?? 0;
}
