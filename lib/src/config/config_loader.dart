import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../core/exceptions.dart';
import 'deploy_config.dart';
import 'env_resolver.dart';

/// To'liq o'qilgan va tasdiqlangan konfiguratsiya.
class DeployConfig {
  const DeployConfig({
    required this.version,
    required this.app,
    required this.envFile,
    required this.buildNumberFile,
    required this.environments,
    required this.integrations,
  });

  final int version;
  final AppConfig app;
  final String envFile;
  final String buildNumberFile;
  final Map<String, EnvironmentConfig> environments;
  final IntegrationsConfig integrations;

  /// Nomi bo'yicha muhit. Topilmasa — mavjudlarini sanab xato beradi.
  EnvironmentConfig environment(String name) {
    final e = environments[name];
    if (e == null) {
      final known = environments.keys.join(', ');
      throw ConfigException(
        '"$name" muhiti deploy.yaml da topilmadi. Mavjud muhitlar: $known',
      );
    }
    return e;
  }
}

/// `deploy.yaml` / `deploy.json` ni o'qib [DeployConfig] ga aylantiradi.
///
/// `${VAR}` almashtirish **parse'dan oldin** butun daraxt bo'ylab bajariladi,
/// shuning uchun quyidagi kodda har bir maydonda alohida o'ylash shart emas.
class ConfigLoader {
  const ConfigLoader();

  /// Fayldan o'qiydi. Kengaytmaga qarab yaml yoki json deb hisoblaydi.
  DeployConfig load(String path, {Map<String, String>? platformEnv}) {
    final file = File(path);
    if (!file.existsSync()) {
      throw ConfigException(
        '$path topilmadi. `deploykit init` bilan yarating.',
      );
    }
    final source = file.readAsStringSync();
    final isJson = path.toLowerCase().endsWith('.json');

    // envFile yo'lini bilish uchun avval xomaki o'qiymiz — almashtirishsiz.
    final rawRoot = _decode(source, isJson: isJson);
    final envFile = _optString(rawRoot, 'env_file') ?? '.env';

    return parse(
      source,
      isJson: isJson,
      env: EnvResolver.load(envFile: envFile, platformEnv: platformEnv),
    );
  }

  DeployConfig parse(
    String source, {
    required bool isJson,
    required EnvResolver env,
  }) {
    final raw = _decode(source, isJson: isJson);
    final root = env.resolveDeep(raw) as Map<String, Object?>;

    final version = root['version'];
    if (version != 1) {
      throw ConfigException(
        'version: qo\'llab-quvvatlanadigan yagona qiymat — 1 (berilgan: $version)',
      );
    }

    final appMap = _requireMap(root, 'app');
    final app = AppConfig(
      root: _optString(appMap, 'root') ?? '.',
      androidPackage: _requireString(appMap, 'android_package', 'app'),
    );

    final envsMap = _requireMap(root, 'environments');
    if (envsMap.isEmpty) {
      throw ConfigException('environments: kamida bitta muhit bo\'lishi kerak');
    }

    final environments = <String, EnvironmentConfig>{
      for (final entry in envsMap.entries)
        entry.key: _environment(
          entry.key,
          _asMap(entry.value, 'environments.${entry.key}'),
        ),
    };

    return DeployConfig(
      version: 1,
      app: app,
      envFile: _optString(root, 'env_file') ?? '.env',
      buildNumberFile:
          _optString(root, 'build_number_file') ?? '.last_build_number',
      environments: environments,
      integrations: _integrations(_optMap(root, 'integrations')),
    );
  }

  // ---- Muhit --------------------------------------------------------------

  EnvironmentConfig _environment(String name, Map<String, Object?> m) {
    final path = 'environments.$name';

    // branch uch holati: maydon yo'q / null → tekshiruv o'chirilgan;
    // bo'sh matn → xato, chunki bu deyarli har doim tasodif va uni jimgina
    // "o'chirilgan" deb talqin qilish production'ni himoyasiz qoldiradi.
    final branchRaw = m['branch'];
    if (branchRaw is String && branchRaw.trim().isEmpty) {
      throw ConfigException(
        '$path.branch: bo\'sh matn bo\'lishi mumkin emas. '
        'Tekshiruvni o\'chirish uchun maydonni butunlay olib tashlang.',
      );
    }

    return EnvironmentConfig(
      name: name,
      branch: branchRaw as String?,
      dartDefines: _stringMap(_optMap(m, 'dart_defines'), '$path.dart_defines'),
      buildArgs: _stringList(m['build_args'], '$path.build_args'),
      android: _android(_optMap(m, 'android'), '$path.android'),
      ios: _ios(_optMap(m, 'ios')),
      notify: _notify(_optMap(m, 'notify'), '$path.notify'),
    );
  }

  AndroidConfig? _android(Map<String, Object?>? m, String path) {
    if (m == null) return null;

    final artifacts = <ArtifactType>[];
    for (final a in _stringList(m['artifacts'], '$path.artifacts')) {
      final t = ArtifactType.tryParse(a);
      if (t == null) {
        throw ConfigException(
          '$path.artifacts: "$a" noma\'lum. Ruxsat etilgan: aab, apk',
        );
      }
      artifacts.add(t);
    }

    final playMap = _optMap(m, 'play');
    if (playMap == null) {
      throw ConfigException('$path.play: majburiy — track va status kerak');
    }

    final apkMap = _optMap(m, 'apk');
    return AndroidConfig(
      artifacts: artifacts.isEmpty ? [ArtifactType.aab] : artifacts,
      apk: ApkConfig(
        splitPerAbi: (apkMap?['split_per_abi'] as bool?) ?? false,
        targetPlatform: apkMap == null ? null : _optString(apkMap, 'target_platform'),
      ),
      play: PlayConfig(
        track: _requireString(playMap, 'track', '$path.play'),
        status: _optString(playMap, 'status') ?? 'completed',
      ),
    );
  }

  IosConfig? _ios(Map<String, Object?>? m) => m == null
      ? null
      : IosConfig(
          testflightInternalOnly:
              (m['testflight_internal_only'] as bool?) ?? false,
        );

  NotifyConfig? _notify(Map<String, Object?>? m, String path) {
    if (m == null) return null;
    final tg = _optMap(m, 'telegram');
    if (tg == null) return const NotifyConfig();

    final tgPath = '$path.telegram';

    ArtifactType? attach;
    final attachRaw = _optString(tg, 'attach');
    if (attachRaw != null) {
      attach = ArtifactType.tryParse(attachRaw);
      if (attach == null) {
        throw ConfigException(
          '$tgPath.attach: "$attachRaw" noma\'lum. Ruxsat etilgan: aab, apk, ipa',
        );
      }
    }

    var policy = OversizePolicy.zip;
    final policyRaw = _optString(tg, 'on_oversize');
    if (policyRaw != null) {
      final parsed = OversizePolicy.tryParse(policyRaw);
      if (parsed == null) {
        throw ConfigException(
          '$tgPath.on_oversize: "$policyRaw" noma\'lum. '
          'Ruxsat etilgan: zip, fail, skip',
        );
      }
      policy = parsed;
    }

    return NotifyConfig(
      telegram: TelegramConfig(
        message: _requireString(tg, 'message', tgPath),
        attach: attach,
        maxSizeMb: (tg['max_size_mb'] as int?) ?? 50,
        onOversize: policy,
      ),
    );
  }

  // ---- Integratsiyalar ----------------------------------------------------

  IntegrationsConfig _integrations(Map<String, Object?>? m) {
    if (m == null) return const IntegrationsConfig();

    final play = _optMap(m, 'play');
    final asc = _optMap(m, 'app_store');
    final tg = _optMap(m, 'telegram');

    return IntegrationsConfig(
      play: play == null
          ? null
          : PlayIntegration(
              serviceAccount: _requireString(
                play,
                'service_account',
                'integrations.play',
              ),
            ),
      appStore: asc == null
          ? null
          : AppStoreIntegration(
              keyId: _requireString(asc, 'key_id', 'integrations.app_store'),
              issuerId: _requireString(asc, 'issuer_id', 'integrations.app_store'),
              privateKey:
                  _requireString(asc, 'private_key', 'integrations.app_store'),
              teamId: _requireString(asc, 'team_id', 'integrations.app_store'),
            ),
      telegram: tg == null
          ? null
          : TelegramIntegration(
              botToken:
                  _requireString(tg, 'bot_token', 'integrations.telegram'),
              chatId: _requireString(tg, 'chat_id', 'integrations.telegram'),
            ),
    );
  }

  // ---- Yordamchilar -------------------------------------------------------

  Map<String, Object?> _decode(String source, {required bool isJson}) {
    try {
      final decoded = isJson ? jsonDecode(source) : loadYaml(source);
      final normalised = _normalise(decoded);
      if (normalised is! Map<String, Object?>) {
        throw const ConfigException('Config ildizi obyekt bo\'lishi kerak');
      }
      return normalised;
    } on ConfigException {
      rethrow;
    } catch (e) {
      throw ConfigException('Config o\'qib bo\'lmadi: $e');
    }
  }

  /// `YamlMap`/`YamlList` ni oddiy Dart to'plamlariga aylantiradi.
  Object? _normalise(Object? node) {
    if (node is Map) {
      return <String, Object?>{
        for (final e in node.entries) e.key.toString(): _normalise(e.value),
      };
    }
    if (node is List) return node.map(_normalise).toList();
    return node;
  }

  Map<String, Object?> _asMap(Object? v, String path) {
    if (v == null) return <String, Object?>{};
    if (v is Map<String, Object?>) return v;
    throw ConfigException('$path: obyekt bo\'lishi kerak');
  }

  Map<String, Object?>? _optMap(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v == null) return null;
    if (v is Map<String, Object?>) return v;
    throw ConfigException('$key: obyekt bo\'lishi kerak');
  }

  Map<String, Object?> _requireMap(Map<String, Object?> m, String key) {
    final v = _optMap(m, key);
    if (v == null) throw ConfigException('$key: majburiy maydon');
    return v;
  }

  String? _optString(Map<String, Object?> m, String key) {
    final v = m[key];
    return v == null ? null : v.toString();
  }

  String _requireString(Map<String, Object?> m, String key, String path) {
    final v = _optString(m, key);
    if (v == null) throw ConfigException('$path.$key: majburiy maydon');
    return v;
  }

  List<String> _stringList(Object? v, String path) {
    if (v == null) return const [];
    if (v is! List) throw ConfigException('$path: ro\'yxat bo\'lishi kerak');
    return v.map((e) => e.toString()).toList();
  }

  Map<String, String> _stringMap(Map<String, Object?>? m, String path) {
    if (m == null) return const {};
    return {for (final e in m.entries) e.key: e.value.toString()};
  }
}
