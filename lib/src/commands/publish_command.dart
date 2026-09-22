import 'package:http/http.dart' as http;

import '../core/preflight.dart';
import '../core/process_runner.dart';
import '../pipeline.dart';
import 'deploy_command.dart';

/// build + upload + notify, in one step.
class PublishCommand extends DeployCommand {
  PublishCommand({
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
      help: 'Show the full plan without building or uploading.',
    );
  }

  final ProcessRunner _runner;
  final http.Client _client;
  final PlayProbe? _playProbe;
  final PlayClientFactory? _playClientFactory;

  @override
  String get name => 'publish';

  @override
  String get description => 'Build, upload and notify.';

  @override
  Future<int> run() async {
    final dryRun = argResults!.flag('dry-run');
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

    if (dryRun) logger.info('DRY RUN — nothing will be changed');

    final manifest = await pipeline.build(
      android: doAndroid,
      ios: doIos,
      allowBranchMismatch: allowBranchMismatch,
      dryRun: dryRun,
    );

    await pipeline.upload(
      manifest: manifest,
      android: doAndroid,
      ios: doIos,
      allowBranchMismatch: allowBranchMismatch,
      dryRun: dryRun,
      // build already ran pre-flight; no need to do it twice.
      runPreflight: false,
    );

    logger.blank();
    logger.ok(
      dryRun
          ? 'Dry run complete — v${manifest.version} would ship like this.'
          : 'Deploy complete — v${manifest.version}',
    );
    return 0;
  }
}
