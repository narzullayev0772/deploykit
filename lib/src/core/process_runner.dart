import 'dart:convert';
import 'dart:io' as io;

import 'package:collection/collection.dart';

/// Tashqi jarayon natijasi.
class ProcessResult {
  const ProcessResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
}

/// Tashqi jarayonlarni ishga tushirish.
///
/// Har doim konstruktor orqali inject qilinadi, shuning uchun builder va
/// publisher'lar haqiqiy `flutter` yoki `xcodebuild`siz test qilinadi —
/// testlar uzatilgan argumentlarni tekshiradi, bu esa xatolar aslida
/// tug'iladigan joy.
abstract class ProcessRunner {
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
}

class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final r = await io.Process.run(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: environment,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    return ProcessResult(
      r.exitCode,
      (r.stdout as String?) ?? '',
      (r.stderr as String?) ?? '',
    );
  }
}

/// Bitta yozib olingan chaqiruv.
class RecordedCall {
  const RecordedCall(this.executable, this.args, this.workingDirectory);

  final String executable;
  final List<String> args;
  final String? workingDirectory;

  @override
  String toString() => '$executable ${args.join(' ')}';
}

/// Testlar uchun [ProcessRunner].
///
/// `lib/` ichida turadi, `test/` da emas — paket foydalanuvchilari ham o'z
/// testlarida ishlatishi mumkin.
class FakeProcessRunner implements ProcessRunner {
  /// Qilingan barcha chaqiruvlar, tartibi bilan.
  final List<RecordedCall> calls = [];

  /// Kalit — bajariladigan fayl nomi.
  final Map<String, ProcessResult> responses = {};

  /// Argumentlarga qarab javob berish kerak bo'lganda.
  ///
  /// `flutter --version` (preflight) va `flutter build` (haqiqiy build)
  /// bir xil faylga tegishli, lekin testda ularni ajratish kerak bo'ladi:
  /// masalan preflight o'tsin, build esa yiqilsin. `null` qaytarsa
  /// [responses] va [defaultResponse] ga o'tiladi.
  ProcessResult? Function(String executable, List<String> args)? responder;

  /// [responder] va [responses] da mos kelmagan chaqiruvlar uchun javob.
  ProcessResult defaultResponse = const ProcessResult(0, '', '');

  @override
  Future<ProcessResult> run(
    String executable,
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(RecordedCall(executable, args, workingDirectory));
    return responder?.call(executable, args) ??
        responses[executable] ??
        defaultResponse;
  }

  /// Berilgan faylga qilingan oxirgi chaqiruv, yoki `null`.
  RecordedCall? lastCallTo(String executable) =>
      calls.lastWhereOrNull((c) => c.executable == executable);
}
