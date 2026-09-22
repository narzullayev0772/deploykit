
import 'package:http/http.dart' as http;

import '../core/preflight.dart';
import '../core/process_runner.dart';
import '../publish/play_publisher.dart';
import 'deploy_command.dart';

/// Deploy'dan oldin barcha shartlarni tekshiradi va hammasini ko'rsatadi.
///
/// `publish` dan farqi: bu yerda birinchi xatoda to'xtash yo'q — maqsad
/// to'liq manzarani berish, shunda foydalanuvchi hammasini bir yo'la
/// tuzatadi.
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
      help: 'Play va Telegram bilan aloqani ham tekshirish.',
    );
  }

  final ProcessRunner _runner;
  final http.Client _client;
  final PlayProbe _playProbe;

  static Future<void> _realPlayProbe(String path) async {
    // Kalitni haqiqatdan almashtirib ko'radi — fayl mavjudligi yetarli emas.
    (await PlayPublisher.clientFromServiceAccount(path)).close();
  }

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Deploy uchun barcha shartlarni tekshiradi va hisobot beradi.';

  @override
  Future<int> run() async {
    final config = loadConfig();
    final env = config.environment(resolveEnvName(config));

    logger.info('Muhit: ${env.name}');
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
      logger.err('$failed ta shart bajarilmagan — deploy ishlamaydi.');
      return 3;
    }
    if (warned > 0) {
      logger.warn('$warned ta ogohlantirish, lekin deploy mumkin.');
    } else {
      logger.ok('Hammasi tayyor.');
    }
    return 0;
  }
}
