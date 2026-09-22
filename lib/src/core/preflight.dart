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

/// Play service-account kalitini haqiqatdan tekshiradigan funksiya.
///
/// Inject qilinadi, shuning uchun testlar tarmoqqa chiqmaydi.
typedef PlayProbe = Future<void> Function(String serviceAccountPath);

/// Deploy'dan oldin barcha shartlarni tekshiradi.
///
/// `doctor` [runAll] ni chaqirib hammasini ko'rsatadi; `publish`
/// [assertReady] ni chaqirib birinchi `fail` da to'xtaydi. Ikkalasi bir xil
/// kodni ishlatadi, shuning uchun `doctor` yashil bo'lsa `publish` ham
/// o'tishi kafolatlanadi.
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
      // flutter va git haqiqatdan ishga tushiriladi — buzilgan o'rnatish
      // "mavjud" bo'lishi mumkin.
      await _tool('flutter', args: ['--version'], required: true),
      await _tool('git', args: ['--version'], required: true),
      ...await _gitChecks(allowBranchMismatch: allowBranchMismatch),
      await _tool('xcodebuild', args: ['-version'], required: needIos),
      // vtool sinov rejimiga ega emas: `vtool -help` ham 1 qaytaradi.
      // Shuning uchun faqat mavjudligi tekshiriladi.
      await _tool('vtool', required: needIos),
      _buildNumberFile(),
      if (needAndroid) _keyFile(
        'Play service-account',
        config.integrations.play?.serviceAccount,
        'integrations.play.service_account',
      ),
      if (needIos) _keyFile(
        'App Store .p8 kaliti',
        config.integrations.appStore?.privateKey,
        'integrations.app_store.private_key',
      ),
      if (checkNetwork && needAndroid) await _playReachable(),
      if (checkNetwork && env.notify?.telegram != null) await _telegramReachable(),
    ];
  }

  /// Birinchi `fail` da to'xtaydi.
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
      'Deploy uchun shartlar bajarilmagan:\n'
      '${failed.map((f) => '  ✗ ${f.name}: ${f.detail}').join('\n')}\n'
      'Batafsil: deploykit doctor',
    );
  }

  // ---- Alohida tekshiruvlar ----------------------------------------------

  /// [args] berilsa vosita o'sha argumentlar bilan ishga tushiriladi;
  /// berilmasa faqat PATH da borligi tekshiriladi.
  Future<CheckResult> _tool(
    String executable, {
    List<String>? args,
    required bool required,
  }) async {
    final r = args == null
        ? await runner.run('which', [executable])
        : await runner.run(executable, args);

    if (r.ok) return CheckResult.pass(executable, 'mavjud');

    return required
        ? CheckResult.fail(executable, 'topilmadi yoki ishlamadi')
        : CheckResult.warn(
            executable,
            'topilmadi — bu muhit uchun kerak emas',
          );
  }

  /// Git repo va branch tekshiruvi.
  ///
  /// Repo bo'lmasligi `branch` regex'i sozlangan holdagina `fail`: regex bor
  /// bo'lsa, uni tekshira olmaslik himoyaning ishlamayotganini bildiradi.
  /// Regex yo'q bo'lsa git umuman kerak emas.
  Future<List<CheckResult>> _gitChecks({
    required bool allowBranchMismatch,
  }) async {
    final pattern = env.branch;
    if (pattern == null) {
      return const [CheckResult.pass('branch tekshiruvi', 'o\'chirilgan')];
    }

    if (!Directory('$projectRoot/.git').existsSync()) {
      return const [
        CheckResult.fail(
          'git repo',
          'topilmadi, lekin deploy.yaml da branch regex sozlangan — '
              'himoya ishlamaydi',
        ),
      ];
    }

    try {
      final branch = await BranchGuard(runner).currentBranch(projectRoot);
      if (RegExp(pattern).hasMatch(branch)) {
        return [CheckResult.pass('branch', '$branch — mos')];
      }
      return [
        allowBranchMismatch
            ? CheckResult.warn(
                'branch',
                '$branch "$pattern" ga mos emas (--allow-branch-mismatch)',
              )
            : CheckResult.fail('branch', '$branch "$pattern" ga mos emas'),
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
        'topilmadi — `deploykit init` bilan yarating',
      );
    }
    final raw = file.readAsStringSync().trim();
    if (int.tryParse(raw) == null) {
      return CheckResult.fail(
        config.buildNumberFile,
        'butun son emas: "$raw"',
      );
    }
    return CheckResult.pass(config.buildNumberFile, 'joriy raqam $raw');
  }

  /// Kalit faylni mavjudligi emas, **o'qilishi** bo'yicha tekshiradi.
  ///
  /// Bo'sh (0 bayt) `.p8` haqiqiy holat: `the legacy scripts` da skriptlar o'chirilgach
  /// aynan shunday fayllar qolgan edi. Mavjudlik tekshiruvi bunday faylni
  /// o'tkazib yuborardi va xato faqat yuklash paytida bilinardi.
  CheckResult _keyFile(String name, String? path, String configPath) {
    if (path == null) {
      return CheckResult.fail(name, '$configPath sozlanmagan');
    }

    final file = File(path);
    if (!file.existsSync()) return CheckResult.fail(name, 'topilmadi: $path');

    try {
      final length = file.lengthSync();
      if (length == 0) return CheckResult.fail(name, 'fayl bo\'sh: $path');
      file.openSync().closeSync();
      return CheckResult.pass(name, '$length bayt');
    } on FileSystemException catch (e) {
      return CheckResult.fail(name, 'o\'qib bo\'lmadi: ${e.message}');
    }
  }

  Future<CheckResult> _playReachable() async {
    final path = config.integrations.play?.serviceAccount;
    if (path == null) {
      return const CheckResult.fail(
        'Play API',
        'integrations.play.service_account sozlanmagan',
      );
    }
    try {
      await playProbe(path);
      return const CheckResult.pass('Play API', 'kalit qabul qilindi');
    } catch (e) {
      return CheckResult.fail('Play API', '$e');
    }
  }

  Future<CheckResult> _telegramReachable() async {
    final creds = config.integrations.telegram;
    if (creds == null) {
      return const CheckResult.fail(
        'Telegram',
        'notify.telegram sozlangan, lekin integrations.telegram yo\'q',
      );
    }
    try {
      final r = await client.get(
        Uri.parse('https://api.telegram.org/bot${creds.botToken}/getMe'),
      );
      if (r.statusCode == 200 && r.body.contains('"ok":true')) {
        return const CheckResult.pass('Telegram', 'bot tokeni ishlayapti');
      }
      return CheckResult.fail('Telegram', 'token rad etildi (HTTP ${r.statusCode})');
    } catch (e) {
      return CheckResult.fail('Telegram', '$e');
    }
  }
}
