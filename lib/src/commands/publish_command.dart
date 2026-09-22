import 'package:http/http.dart' as http;

import '../core/preflight.dart';
import '../core/process_runner.dart';
import '../pipeline.dart';
import 'deploy_command.dart';

/// build + upload + notify.
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
      help: 'Hech nima qurmay va yuklamay, to\'liq rejani ko\'rsatish.',
    );
  }

  final ProcessRunner _runner;
  final http.Client _client;
  final PlayProbe? _playProbe;
  final PlayClientFactory? _playClientFactory;

  @override
  String get name => 'publish';

  @override
  String get description => 'Quradi, yuklaydi va xabar beradi.';

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

    if (dryRun) logger.info('DRY RUN — hech narsa o\'zgartirilmaydi');

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
      // build allaqachon preflight qildi — ikki marta tekshirmaymiz.
      runPreflight: false,
    );

    logger.blank();
    logger.ok(
      dryRun
          ? 'Dry run tugadi — v${manifest.version} shu tarzda chiqarilardi.'
          : 'Deploy tugadi — v${manifest.version}',
    );
    return 0;
  }
}
