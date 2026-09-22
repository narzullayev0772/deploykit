
import 'package:http/http.dart' as http;

import '../core/preflight.dart';
import '../core/process_runner.dart';
import '../publish/play_publisher.dart';
import 'deploy_command.dart';

/// Checks every precondition and reports all of them.
///
/// Unlike `publish`, this does not stop at the first failure: the point is to
/// show the whole picture so everything can be fixed in one pass.
class DoctorCommand extends DeployCommand {
  DoctorCommand({
    required super.workingDir,
    required super.logger,
    ProcessRunner? runner,
    http.Client? client,
    PlayProbe? playProbe,
  })  : _runner = runner ?? const RealProcessRunner(),
        _client = client ?? http.Client(),
        _playProbe = playProbe ?? _realPlayProbe {
    argParser.addFlag(
      'network',
      defaultsTo: true,
      help: 'Also check connectivity to Play and Telegram.',
    );
  }

  final ProcessRunner _runner;
  final http.Client _client;
  final PlayProbe _playProbe;

  static Future<void> _realPlayProbe(String path) async {
    // Actually exchanges the key — file existence is not enough.
    (await PlayPublisher.clientFromServiceAccount(path)).close();
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check every precondition for a deploy and report the results.';

  @override
  Future<int> run() async {
    final config = loadConfig();
    final env = config.environment(resolveEnvName(config));

    logger.info('Environment: ${env.name}');
    logger.blank();

    final results = await Preflight(
      runner: _runner,
      client: _client,
      config: config,
      env: env,
      logger: logger,
      projectRoot: projectRoot(config),
      playProbe: _playProbe,
    ).runAll(
      checkNetwork: argResults!.flag('network'),
      android: doAndroid,
      ios: doIos,
      allowBranchMismatch: allowBranchMismatch,
    );

    for (final r in results) {
      final line = r.detail.isEmpty ? r.name : '${r.name} — ${r.detail}';
      switch (r.status) {
        case CheckStatus.pass:
          logger.ok(line);
        case CheckStatus.warn:
          logger.warn(line);
        case CheckStatus.fail:
          logger.err(line);
      }
    }

    final failed = results.where((r) => r.status == CheckStatus.fail).length;
    final warned = results.where((r) => r.status == CheckStatus.warn).length;

    logger.blank();
    if (failed > 0) {
      logger.err('$failed check(s) failed — this deploy would not work.');
      return 3;
    }
    if (warned > 0) {
      logger.warn('$warned warning(s), but the deploy can proceed.');
    } else {
      logger.ok('Everything is ready.');
    }
    return 0;
  }
}
