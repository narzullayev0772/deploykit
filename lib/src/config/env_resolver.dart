import 'dart:io';

import '../core/exceptions.dart';

/// `${VAR}` havolalarini haqiqiy qiymatlarga almashtiradi.
///
/// Maxfiy qiymatlar hech qachon `deploy.yaml` ichida saqlanmaydi — u faylda
/// faqat havola turadi, qiymat esa muhit o'zgaruvchisidan yoki `.env`
/// faylidan keladi. Shu sabab `deploy.yaml` bemalol git'ga qo'shiladi.
class EnvResolver {
  EnvResolver(this._vars);

  /// Muhit o'zgaruvchilari va `.env` faylini birlashtiradi.
  ///
  /// Muhit o'zgaruvchisi `.env` dan **ustun** — CI'da `.env` yaratmasdan
  /// faqat secret'larni berish uchun.
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

  /// [raw] ichidagi barcha `${VAR}` larni almashtiradi.
  ///
  /// [path] — xato xabarida ko'rsatiladigan config yo'li, masalan
  /// `integrations.telegram.bot_token`. Usiz foydalanuvchi qaysi maydon
  /// muammoli ekanini topolmaydi.
  String resolve(String raw, {required String path}) {
    return raw.replaceAllMapped(_pattern, (m) {
      final name = m.group(1)!;
      final value = _vars[name];
      if (value == null) {
        throw ConfigException(
          '$path: \${$name} topilmadi. '
          'Uni muhit o\'zgaruvchisi sifatida bering yoki .env faylga qo\'shing.',
        );
      }
      return value;
    });
  }

  /// Map/List daraxti bo'ylab rekursiv yurib, barcha matnlarni almashtiradi.
  ///
  /// Butun config daraxtiga bir marta qo'llanadi, shunda har bir maydonda
  /// alohida o'ylash shart emas.
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

  /// `KEY=value` formatidagi faylni o'qiydi.
  ///
  /// Fayl yo'q bo'lsa — bo'sh xarita, xato emas: `.env` ixtiyoriy.
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

      // Qiymat atrofidagi juft tirnoqni olib tashlash.
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
