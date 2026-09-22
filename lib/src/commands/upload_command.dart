import 'package:http/http.dart' as http;

import '../core/preflight.dart';
import '../core/process_runner.dart';
import '../pipeline.dart';
import 'deploy_command.dart';

/// Oxirgi build'ni yuklaydi. Build raqamini oshirmaydi.
class UploadCommand extends DeployCommand {
  UploadCommand({
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
      help: 'Hech nima yuklamay, rejani ko\'rsatish.',
    );
  }

  final ProcessRunner _runner;
  final http.Client _client;
  final PlayProbe? _playProbe;
  final PlayClientFactory? _playClientFactory;

  @override
  String get name => 'upload';

  @override
  String get description =>
      'Oxirgi build artefaktlarini yuklaydi. Yiqilsa xavfsiz qayta urinish mumkin.';

  @override
  Future<int> run() async {
    final config = loadConfig();
    final env = config.environment(resolveEnvName(config));

    final pipeline = DeployPipeline(
      config: config,
      env: env,
      projectRoot: projectRoot(config),
      logger: logger,
      runner: _runner,
      client: _client,
      playProbe: _playProbe,
      playClientFactory: _playClientFactory,
    );

    await pipeline.upload(
      manifest: pipeline.readManifest(),
      android: doAndroid,
      ios: doIos,
      allowBranchMismatch: allowBranchMismatch,
      dryRun: argResults!.flag('dry-run'),
    );
    return 0;
  }
}
