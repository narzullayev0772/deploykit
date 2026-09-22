import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../core/exceptions.dart';
import 'deploy_config.dart';
import 'env_resolver.dart';

/// A fully parsed and validated configuration.
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

  /// Looks up an environment by name, listing the known ones when it fails.
  EnvironmentConfig environment(String name) {
    final e = environments[name];
    if (e == null) {
      final known = environments.keys.join(', ');
      throw ConfigException(
        'Environment "$name" is not defined in deploy.yaml. '
        'Available environments: $known',
      );
    }
    return e;
  }
}

/// Reads `deploy.yaml` / `deploy.json` into a [DeployConfig].
///
/// `${VAR}` substitution runs over the whole tree **before** parsing, so the
/// code below never has to think about it field by field.
class ConfigLoader {
  const ConfigLoader();

  /// Loads from a file, picking YAML or JSON by extension.
  DeployConfig load(String path, {Map<String, String>? platformEnv}) {
    final file = File(path);
    if (!file.existsSync()) {
      throw ConfigException(
        '$path not found. Create it with `deploykit init`.',
      );
    }
    final source = file.readAsStringSync();
    final isJson = path.toLowerCase().endsWith('.json');

    // Decode once without substitution, just to learn where .env lives.
    final rawRoot = _decode(source, isJson: isJson);
    final envFile = _optString(rawRoot, 'env_file') ?? '.env';

    // A relative path resolves against the CONFIG FILE's directory, not the
    // process working directory. Otherwise
    // `deploykit --config some/dir/deploy.yaml` cannot find `some/dir/.env`.
    final configDir = file.parent.path;
    final resolvedEnvFile =
        envFile.startsWith('/') ? envFile : '$configDir/$envFile';

    return parse(
      source,
      isJson: isJson,
      env: EnvResolver.load(
        envFile: resolvedEnvFile,
        platformEnv: platformEnv,
      ),
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
        'version: the only supported value is 1 (got: $version)',
      );
    }

    final appMap = _requireMap(root, 'app');
    final app = AppConfig(
      root: _optString(appMap, 'root') ?? '.',
      androidPackage: _requireString(appMap, 'android_package', 'app'),
    );

    final envsMap = _requireMap(root, 'environments');
    if (envsMap.isEmpty) {
      throw const ConfigException(
        'environments: at least one environment is required',
      );
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

  // ---- Environments -------------------------------------------------------

  EnvironmentConfig _environment(String name, Map<String, Object?> m) {
    final path = 'environments.$name';

    // Three cases for `branch`: absent or null disables the check; an empty
    // string is an error, because that is almost always an accident and
    // silently reading it as "disabled" would leave production unprotected.
    final branchRaw = m['branch'];
    if (branchRaw is String && branchRaw.trim().isEmpty) {
      throw ConfigException(
        '$path.branch: must not be an empty string. '
        'Remove the field entirely to disable the check.',
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
          '$path.artifacts: unknown value "$a". Allowed: aab, apk',
        );
      }
      artifacts.add(t);
    }

    final playMap = _optMap(m, 'play');
    if (playMap == null) {
      throw ConfigException(
        '$path.play: required — both track and status must be set',
      );
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
          '$tgPath.attach: unknown value "$attachRaw". '
          'Allowed: aab, apk, ipa',
        );
      }
    }

    var policy = OversizePolicy.zip;
    final policyRaw = _optString(tg, 'on_oversize');
    if (policyRaw != null) {
      final parsed = OversizePolicy.tryParse(policyRaw);
      if (parsed == null) {
        throw ConfigException(
          '$tgPath.on_oversize: unknown value "$policyRaw". '
          'Allowed: zip, fail, skip',
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

  // ---- Integrations -------------------------------------------------------

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

  // ---- Helpers ------------------------------------------------------------

  Map<String, Object?> _decode(String source, {required bool isJson}) {
    try {
      final decoded = isJson ? jsonDecode(source) : loadYaml(source);
      final normalised = _normalise(decoded);
      if (normalised is! Map<String, Object?>) {
        throw const ConfigException('The config root must be a mapping');
      }
      return normalised;
    } on ConfigException {
      rethrow;
    } catch (e) {
      throw ConfigException('Could not parse the config: $e');
    }
  }

  /// Converts `YamlMap`/`YamlList` into plain Dart collections.
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
    throw ConfigException('$path: must be a mapping');
  }

  Map<String, Object?>? _optMap(Map<String, Object?> m, String key) {
    final v = m[key];
    if (v == null) return null;
    if (v is Map<String, Object?>) return v;
    throw ConfigException('$key: must be a mapping');
  }

  Map<String, Object?> _requireMap(Map<String, Object?> m, String key) {
    final v = _optMap(m, key);
    if (v == null) throw ConfigException('$key: required field');
    return v;
  }

  String? _optString(Map<String, Object?> m, String key) {
    return m[key]?.toString();
  }

  String _requireString(Map<String, Object?> m, String key, String path) {
    final v = _optString(m, key);
    if (v == null) throw ConfigException('$path.$key: required field');
    return v;
  }

  List<String> _stringList(Object? v, String path) {
    if (v == null) return const [];
    if (v is! List) throw ConfigException('$path: must be a list');
    return v.map((e) => e.toString()).toList();
  }

  Map<String, String> _stringMap(Map<String, Object?>? m, String path) {
    if (m == null) return const {};
    return {for (final e in m.entries) e.key: e.value.toString()};
  }
}
