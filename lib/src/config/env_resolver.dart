import 'dart:io';

import '../core/exceptions.dart';

/// Substitutes `${VAR}` references with their actual values.
///
/// Secrets never live inside `deploy.yaml` — the file holds only references,
/// and the values come from environment variables or `.env`. That is what
/// makes `deploy.yaml` safe to commit.
class EnvResolver {
  EnvResolver(this._vars);

  /// Merges environment variables with a `.env` file.
  ///
  /// Environment variables take **precedence** over `.env`, so CI can supply
  /// secrets without writing a file.
  factory EnvResolver.load({
    String? envFile,
    Map<String, String>? platformEnv,
  }) {
    final fromFile = envFile == null ? <String, String>{} : _readEnvFile(envFile);
    return EnvResolver({
      ...fromFile,
      ...(platformEnv ?? Platform.environment),
    });
  }

  final Map<String, String> _vars;

  static final _pattern = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');

  /// Substitutes every `${VAR}` in [raw].
  ///
  /// [path] is the config path shown in error messages, for example
  /// `integrations.telegram.bot_token`. Without it the user cannot tell which
  /// field is the problem.
  String resolve(String raw, {required String path}) {
    return raw.replaceAllMapped(_pattern, (m) {
      final name = m.group(1)!;
      final value = _vars[name];
      if (value == null) {
        throw ConfigException(
          '$path: \${$name} is not set. '
          'Export it as an environment variable or add it to your .env file.',
        );
      }
      return value;
    });
  }

  /// Walks a Map/List tree, substituting every string it finds.
  ///
  /// Applied once to the whole config tree, so the parser below never has to
  /// think about substitution again.
  Object? resolveDeep(Object? node, {String path = ''}) {
    if (node is String) return resolve(node, path: path.isEmpty ? '<root>' : path);
    if (node is Map) {
      return <String, Object?>{
        for (final e in node.entries)
          e.key.toString(): resolveDeep(
            e.value,
            path: path.isEmpty ? '${e.key}' : '$path.${e.key}',
          ),
      };
    }
    if (node is List) {
      return [
        for (var i = 0; i < node.length; i++)
          resolveDeep(node[i], path: '$path[$i]'),
      ];
    }
    return node;
  }

  /// Reads a `KEY=value` file.
  ///
  /// A missing file yields an empty map rather than an error: `.env` is
  /// optional.
  static Map<String, String> _readEnvFile(String path) {
    final file = File(path);
    if (!file.existsSync()) return {};

    final out = <String, String>{};
    for (final rawLine in file.readAsLinesSync()) {
      var line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('export ')) line = line.substring(7).trim();

      final eq = line.indexOf('=');
      if (eq <= 0) continue;

      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();

      // Strip a matching pair of surrounding quotes.
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      out[key] = value;
    }
    return out;
  }
}
