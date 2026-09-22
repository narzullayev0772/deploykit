import 'exceptions.dart';
import 'process_runner.dart';

/// Deploy faqat ruxsat etilgan branch'dan bajarilishini ta'minlaydi.
///
/// Bash skriptlaridan farqi: bu yerda interaktiv savol yo'q. `read -p`
/// CI'da osilib qolardi, shuning uchun mos kelmagan branch darhol xato
/// beradi va ataylab chetlab o'tish faqat `--allow-branch-mismatch` orqali.
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
        'git branch nomini aniqlab bo\'lmadi: ${r.stderr.trim()}',
      );
    }
    return r.stdout.trim();
  }

  /// [pattern] — regex. `null` bo'lsa tekshiruv umuman bajarilmaydi
  /// (git ham chaqirilmaydi).
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
      'Joriy branch "$branch" talab qilingan shaklga mos emas: $pattern\n'
      'Ataylab davom ettirish uchun --allow-branch-mismatch bering.',
    );
  }
}
