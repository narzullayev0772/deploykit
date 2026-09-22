import 'dart:io';

import 'package:args/command_runner.dart';

import 'commands/init_command.dart';
import 'core/logger.dart';

/// Barcha buyruqlarni yig'adi va global flaglarni e'lon qiladi.
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
  }

  final Directory _workingDir;

  // Global flaglar parse qilinmasdan oldin ham logger kerak bo'ladi, shuning
  // uchun u kech sozlanadi.
  final Logger _logger = Logger();

  @override
  Future<int> run(Iterable<String> args) async => await super.run(args) ?? 0;
}
