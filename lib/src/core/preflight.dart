import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/config_loader.dart' show DeployConfig;
import '../config/deploy_config.dart';
import 'branch_guard.dart';
import 'exceptions.dart';
import 'logger.dart';
import 'process_runner.dart';

enum CheckStatus { pass, warn, fail }

class CheckResult {
  const CheckResult(this.name, this.status, this.detail);

  const CheckResult.pass(String name, [String detail = ''])
      : this(name, CheckStatus.pass, detail);
  const CheckResult.warn(String name, String detail)
      : this(name, CheckStatus.warn, detail);
  const CheckResult.fail(String name, String detail)
      : this(name, CheckStatus.fail, detail);

  final String name;
  final CheckStatus status;
  final String detail;
}

/// Actually exercises the Play service-account key.
///
/// Injected so tests never touch the network.
typedef PlayProbe = Future<void> Function(String serviceAccountPath);

/// Verifies every precondition before a deploy starts.
///
/// `doctor` calls [runAll] and reports everything; `publish` calls
/// [assertReady] and stops at the first failure. Both run the same code, so a
/// green `doctor` guarantees `publish` gets past its checks.
class Preflight {
  const Preflight({
    required this.runner,
    required this.client,
    required this.config,
    required this.env,
    required this.logger,
    required this.projectRoot,
    required this.playProbe,
  });

  final ProcessRunner runner;
  final http.Client client;
  final DeployConfig config;
  final EnvironmentConfig env;
  final Logger logger;
  final String projectRoot;
  final PlayProbe playProbe;

  Future<List<CheckResult>> runAll({
    bool checkNetwork = true,
    bool android = true,
    bool ios = true,
    bool allowBranchMismatch = false,
  }) async {
    final needAndroid = android && env.android != null;
    final needIos = ios && env.ios != null;

    return [
      // flutter and git are actually executed — a broken install can still
      // be "present".
      await _tool('flutter', args: ['--version'], required: true),
      await _tool('git', args: ['--version'], required: true),
      ...await _gitChecks(allowBranchMismatch: allowBranchMismatch),
      await _tool('xcodebuild', args: ['-version'], required: needIos),
      // vtool has no dry-run mode: even `vtool -help` exits 1. So only its
      // presence is checked.
      await _tool('vtool', required: needIos),
      _buildNumberFile(),
      if (needAndroid) _keyFile(
        'Play service-account',
        config.integrations.play?.serviceAccount,
        'integrations.play.service_account',
      ),
      if (needIos) _keyFile(
        'App Store .p8 key',
        config.integrations.appStore?.privateKey,
        'integrations.app_store.private_key',
      ),
      if (checkNetwork && needAndroid) await _playReachable(),
      if (checkNetwork && env.notify?.telegram != null) await _telegramReachable(),
    ];
  }

  /// Throws at the first failing check.
  Future<void> assertReady({
    bool checkNetwork = true,
    bool android = true,
    bool ios = true,
    bool allowBranchMismatch = false,
  }) async {
    final results = await runAll(
      checkNetwork: checkNetwork,
      android: android,
      ios: ios,
      allowBranchMismatch: allowBranchMismatch,
    );

    for (final r in results) {
      if (r.status == CheckStatus.warn) logger.warn('${r.name}: ${r.detail}');
    }

    final failed = results.where((r) => r.status == CheckStatus.fail).toList();
    if (failed.isEmpty) return;

    throw PreflightException(
      'Preconditions for this deploy are not met:\n'
      '${failed.map((f) => '  ✗ ${f.name}: ${f.detail}').join('\n')}\n'
      'Run `deploykit doctor` for the full report.',
    );
  }

  // ---- Individual checks --------------------------------------------------

  /// With [args] the tool is executed; without them only its presence on
  /// PATH is checked.
  Future<CheckResult> _tool(
    String executable, {
    List<String>? args,
    required bool required,
  }) async {
    final r = args == null
        ? await runner.run('which', [executable])
        : await runner.run(executable, args);

    if (r.ok) return CheckResult.pass(executable, 'available');

    return required
        ? CheckResult.fail(executable, 'not found, or failed to run')
        : CheckResult.warn(
            executable,
            'not found — not needed for this environment',
          );
  }

  /// Git repository and branch checks.
  ///
  /// A missing repository only fails when a `branch` pattern is configured:
  /// being unable to check it means the guard is not working. Without a
  /// pattern, git is not needed at all.
  Future<List<CheckResult>> _gitChecks({
    required bool allowBranchMismatch,
  }) async {
    final pattern = env.branch;
    if (pattern == null) {
      return const [CheckResult.pass('branch check', 'disabled')];
    }

    if (!Directory('$projectRoot/.git').existsSync()) {
      return const [
        CheckResult.fail(
          'git repo',
          'not found, but deploy.yaml configures a branch pattern — '
              'the guard cannot work',
        ),
      ];
    }

    try {
      final branch = await BranchGuard(runner).currentBranch(projectRoot);
      if (RegExp(pattern).hasMatch(branch)) {
        return [CheckResult.pass('branch', '$branch — matches')];
      }
      return [
        allowBranchMismatch
            ? CheckResult.warn(
                'branch',
                '$branch does not match "$pattern" '
                    '(--allow-branch-mismatch)',
              )
            : CheckResult.fail(
                'branch',
                '$branch does not match "$pattern"',
              ),
      ];
    } on PreflightException catch (e) {
      return [CheckResult.fail('branch', e.message)];
    }
  }

  CheckResult _buildNumberFile() {
    final file = File('$projectRoot/${config.buildNumberFile}');
    if (!file.existsSync()) {
      return CheckResult.fail(
        config.buildNumberFile,
        'not found — create it with `deploykit init`',
      );
    }
    final raw = file.readAsStringSync().trim();
    if (int.tryParse(raw) == null) {
      return CheckResult.fail(
        config.buildNumberFile,
        'not an integer: "$raw"',
      );
    }
    return CheckResult.pass(config.buildNumberFile, 'currently $raw');
  }

  /// Checks that a key file is **readable**, not merely present.
  ///
  /// An empty (0-byte) `.p8` is a real situation — it is what a botched
  /// restore leaves behind. An existence check waves such a file through and
  /// the failure only surfaces during the upload.
  CheckResult _keyFile(String name, String? path, String configPath) {
    if (path == null) {
      return CheckResult.fail(name, '$configPath is not configured');
    }

    final file = File(path);
    if (!file.existsSync()) return CheckResult.fail(name, 'not found: $path');

    try {
      final length = file.lengthSync();
      if (length == 0) return CheckResult.fail(name, 'file is empty: $path');
      file.openSync().closeSync();
      return CheckResult.pass(name, '$length bytes');
    } on FileSystemException catch (e) {
      return CheckResult.fail(name, 'could not read it: ${e.message}');
    }
  }

  Future<CheckResult> _playReachable() async {
    final path = config.integrations.play?.serviceAccount;
    if (path == null) {
      return const CheckResult.fail(
        'Play API',
        'integrations.play.service_account is not configured',
      );
    }
    try {
      await playProbe(path);
      return const CheckResult.pass('Play API', 'key accepted');
    } catch (e) {
      return CheckResult.fail('Play API', '$e');
    }
  }

  Future<CheckResult> _telegramReachable() async {
    final creds = config.integrations.telegram;
    if (creds == null) {
      return const CheckResult.fail(
        'Telegram',
        'notify.telegram is set but integrations.telegram is missing',
      );
    }
    try {
      final r = await client.get(
        Uri.parse('https://api.telegram.org/bot${creds.botToken}/getMe'),
      );
      if (r.statusCode == 200 && r.body.contains('"ok":true')) {
        return const CheckResult.pass('Telegram', 'bot token works');
      }
      return CheckResult.fail(
        'Telegram',
        'token rejected (HTTP ${r.statusCode})',
      );
    } catch (e) {
      return CheckResult.fail('Telegram', '$e');
    }
  }
}
