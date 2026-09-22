import 'package:http/http.dart' as http;

import '../core/preflight.dart';
import '../core/process_runner.dart';
import '../pipeline.dart';
import 'deploy_command.dart';

/// Builds the artifacts and writes `.deploykit/last_build.json`.
class BuildCommand extends DeployCommand {
  BuildCommand({
    required super.workingDir,
    required super.logger,
    ProcessRunner? runner,
    http.Client? client,
    PlayProbe? playProbe,
    PlayClientFactory? playClientFactory,
  })  : _runner = runner ?? const RealProcessRunner(),
        _client = client ?? http.Client(),
        _playProbe = playProbe,
        _playClientFactory = playClientFactory {
    argParser.addFlag(
      'dry-run',
      negatable: false,
      help: 'Show the plan without building anything.',
    );
  }

  final ProcessRunner _runner;
  final http.Client _client;
  final PlayProbe? _playProbe;
  final PlayClientFactory? _playClientFactory;

  @override
  String get name => 'build';

  @override
  String get description =>
      'Build the artifacts without uploading. Run `upload` separately.';

  @override
  Future<int> run() async {
    final config = loadConfig();
    final env = config.environment(resolveEnvName(config));

    await DeployPipeline(
      config: config,
      env: env,
      projectRoot: projectRoot(config),
      logger: logger,
      runner: _runner,
      client: _client,
      playProbe: _playProbe,
      playClientFactory: _playClientFactory,
    ).build(
      android: doAndroid,
      ios: doIos,
      allowBranchMismatch: allowBranchMismatch,
      dryRun: argResults!.flag('dry-run'),
    );
    return 0;
  }
}
