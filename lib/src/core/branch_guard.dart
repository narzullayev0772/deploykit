import 'exceptions.dart';
import 'process_runner.dart';

/// Ensures a deploy only runs from an allowed branch.
///
/// Unlike the shell scripts this replaces, there is no interactive prompt: a
/// `read -p` hangs forever in CI. A mismatched branch fails immediately, and
/// the only way past it is an explicit `--allow-branch-mismatch`.
class BranchGuard {
  const BranchGuard(this.runner);

  final ProcessRunner runner;

  Future<String> currentBranch(String projectRoot) async {
    final r = await runner.run(
      'git',
      ['rev-parse', '--abbrev-ref', 'HEAD'],
      workingDirectory: projectRoot,
    );
    if (!r.ok) {
      throw PreflightException(
        'Could not determine the current git branch: ${r.stderr.trim()}',
      );
    }
    return r.stdout.trim();
  }

  /// [pattern] is a regular expression. When `null` the check is skipped
  /// entirely — git is not even invoked.
  Future<void> check(
    String projectRoot,
    String? pattern, {
    bool allowMismatch = false,
  }) async {
    if (pattern == null) return;

    final branch = await currentBranch(projectRoot);
    if (RegExp(pattern).hasMatch(branch)) return;

    if (allowMismatch) return;

    throw PreflightException(
      'Current branch "$branch" does not match the required pattern: '
      '$pattern\nPass --allow-branch-mismatch to proceed anyway.',
    );
  }
}
