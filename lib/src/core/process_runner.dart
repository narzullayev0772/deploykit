import 'dart:convert';
import 'dart:io' as io;

import 'package:collection/collection.dart';

/// The result of running an external process.
class ProcessResult {
  const ProcessResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
}

/// Runs external processes.
///
/// Always injected through the constructor, so builders and publishers can be
/// tested without a real `flutter` or `xcodebuild`. The tests assert on the
/// arguments that were passed — which is where the bugs actually live.
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

/// A single recorded invocation.
class RecordedCall {
  const RecordedCall(this.executable, this.args, this.workingDirectory);

  final String executable;
  final List<String> args;
  final String? workingDirectory;

  @override
  String toString() => '$executable ${args.join(' ')}';
}

/// A [ProcessRunner] for tests.
///
/// It lives in `lib/` rather than `test/` because consumers of this package
/// can use it in their own tests too.
class FakeProcessRunner implements ProcessRunner {
  /// Every call that was made, in order.
  final List<RecordedCall> calls = [];

  /// Keyed by executable name.
  final Map<String, ProcessResult> responses = {};

  /// For responses that depend on the arguments.
  ///
  /// `flutter --version` (pre-flight) and `flutter build` share an executable
  /// but a test often needs to tell them apart — letting pre-flight pass while
  /// the build fails, say. Returning `null` falls through to [responses] and
  /// then [defaultResponse].
  ProcessResult? Function(String executable, List<String> args)? responder;

  /// Used for calls matched by neither [responder] nor [responses].
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

  /// The last call made to [executable], or `null`.
  RecordedCall? lastCallTo(String executable) =>
      calls.lastWhereOrNull((c) => c.executable == executable);
}
