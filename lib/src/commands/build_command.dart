import 'package:http/http.dart' as http;

import '../core/preflight.dart';
import '../core/process_runner.dart';
import '../pipeline.dart';
import 'deploy_command.dart';

/// Artefaktlarni quradi va `.deploykit/last_build.json` yozadi.
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
      help: 'Hech nima qurmay, rejani ko\'rsatish.',
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
      'Artefaktlarni quradi (yuklamaydi). upload alohida chaqiriladi.';

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
