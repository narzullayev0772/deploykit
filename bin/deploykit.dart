import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:deploykit/src/core/logger.dart';
import 'package:deploykit/src/runner.dart';

Future<void> main(List<String> args) async {
  final logger = Logger(color: !args.contains('--no-color'));

  try {
    exitCode = await DeploykitRunner().run(args);
  } on DeployException catch (e) {
    // Kutilgan xato: foydalanuvchiga faqat xabar, stack trace emas.
    logger.err(e.message);
    exitCode = e.exitCode;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64; // EX_USAGE
  } on ArgParserException catch (e) {
    stderr.writeln(e.message);
    exitCode = 64;
  } catch (e, st) {
    logger.err('Kutilmagan xato: $e');
    if (args.contains('--verbose') || args.contains('-v')) {
      stderr.writeln(st);
    }
    exitCode = 1;
  }
}
