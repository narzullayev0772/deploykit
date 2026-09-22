import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import '../build/build_artifact.dart';
import '../config/deploy_config.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';
import 'notifier.dart';

/// Telegram kanaliga xabar va artefakt yuboradi.
class TelegramNotifier implements Notifier {
  const TelegramNotifier({
    required http.Client client,
    required this.creds,
    required this.config,
    required this.logger,
  }) : _client = client;

  final http.Client _client;
  final TelegramIntegration creds;
  final TelegramConfig config;
  final Logger logger;

  int get _maxBytes => config.maxSizeMb * 1024 * 1024;

  Uri _api(String method) =>
      Uri.parse('https://api.telegram.org/bot${creds.botToken}/$method');

  /// Hajm siyosatini qo'llaydi.
  ///
  /// Qaytaradi: yuboriladigan fayl, yoki `null` (yubormaslik).
  /// Chegaradan oshgan va siyosat ruxsat bermagan holatda xato otadi.
  Future<File?> resolveAttachment(BuildArtifact artifact) async {
    final file = File(artifact.path);
    final size = file.lengthSync();

    if (size <= _maxBytes) return file;

    logger.warn(
      '${artifact.type.name.toUpperCase()} ${_mb(size)} — '
      'chegara ${config.maxSizeMb}MB.',
    );

    switch (config.onOversize) {
      case OversizePolicy.skip:
        logger.warn('Fayl yuborilmaydi (on_oversize: skip).');
        return null;

      case OversizePolicy.fail:
        throw NotifyException(
          'Artefakt ${_mb(size)}, Telegram cheklovi ${config.maxSizeMb}MB. '
          'on_oversize: fail — yuklash to\'xtatildi.',
        );

      case OversizePolicy.zip:
        // APK ichidagi native kutubxonalar (libapp.so, libflutter.so)
        // AGP standart sozlamasida SIQILMAGAN holda saqlanadi, chunki
        // Android ularni to'g'ridan-to'g'ri mmap qiladi. Shuning uchun
        // tashqi zip sezilarli foyda berishi mumkin.
        //
        // Lekin foyda TAXMIN QILINMAYDI — zip yaratiladi va o'lchanadi.
        logger.info('Zip qilinmoqda ...');
        final zipped = _zip(file);
        final zippedSize = zipped.lengthSync();

        logger.info('${_mb(size)} → ${_mb(zippedSize)}');

        if (zippedSize > _maxBytes) {
          throw NotifyException(
            'Zip qilingandan keyin ham katta: ${_mb(size)} → '
            '${_mb(zippedSize)}, Telegram cheklovi ${config.maxSizeMb}MB.\n'
            'Artefaktni kichraytiring (--split-per-abi, --obfuscate) yoki '
            'boshqa kanaldan foydalaning.',
          );
        }
        return zipped;
    }
  }

  @override
  Future<void> send(NotifyPayload payload, {required bool dryRun}) async {
    final artifact = payload.attachment;

    File? file;
    var zipped = false;
    int? zippedBytes;

    if (artifact != null && config.attach != null) {
      file = await resolveAttachment(artifact);
      if (file != null && file.path.endsWith('.zip')) {
        zipped = true;
        zippedBytes = file.lengthSync();
      }
    }

    if (dryRun) {
      logger.info(
        'Telegram: ${file == null ? 'matn' : 'fayl'} yuboriladi (dry-run)',
      );
      return;
    }

    final response = file == null
        ? await _sendMessage(payload)
        : await _sendDocument(
            payload,
            file,
            zipped: zipped,
            zippedBytes: zippedBytes,
          );

    _verify(response);
    logger.ok('Telegram xabari yuborildi');
  }

  /// Izoh matnini yasaydi. Ochiq — alohida test qilinadi.
  String buildCaption(
    NotifyPayload payload, {
    required bool zipped,
    int? zippedBytes,
  }) {
    final buffer = StringBuffer(payload.message)..write('\n📦 v${payload.version}');

    final artifact = payload.attachment;
    if (artifact != null) {
      final original = File(artifact.path).lengthSync();
      if (zipped && zippedBytes != null) {
        buffer.write(' · ${_mb(original)} → ${_mb(zippedBytes)} (zip)');
        buffer.write('\n⚠️ Avval arxivni oching, keyin o\'rnating.');
      } else {
        buffer.write(' · ${_mb(original)}');
      }
    }
    return buffer.toString();
  }

  Future<http.Response> _sendMessage(NotifyPayload payload) => _client.post(
        _api('sendMessage'),
        body: {
          'chat_id': creds.chatId,
          'text': buildCaption(payload, zipped: false),
        },
      );

  Future<http.Response> _sendDocument(
    NotifyPayload payload,
    File file, {
    required bool zipped,
    int? zippedBytes,
  }) async {
    final request = http.MultipartRequest('POST', _api('sendDocument'))
      ..fields['chat_id'] = creds.chatId
      ..fields['caption'] =
          buildCaption(payload, zipped: zipped, zippedBytes: zippedBytes)
      ..files.add(await http.MultipartFile.fromPath('document', file.path));

    logger.info('Telegram`ga yuborilmoqda (${_mb(file.lengthSync())}) ...');
    return http.Response.fromStream(await _client.send(request));
  }

  /// Telegram haqiqiy muvaffaqiyatni faqat JSON dagi `ok` maydonida
  /// bildiradi.
  ///
  /// Bash skriptida bu muammo edi: `curl` HTTP 413 da ham 0 qaytaradi,
  /// shuning uchun rad etilgan yuklash jimgina muvaffaqiyat deb
  /// hisoblanardi.
  void _verify(http.Response response) {
    Map<String, Object?>? body;
    try {
      body = jsonDecode(response.body) as Map<String, Object?>;
    } catch (_) {
      body = null;
    }

    if (response.statusCode == 200 && body?['ok'] == true) return;

    final description = body?['description'] as String? ?? response.body.trim();
    throw NotifyException(
      'Telegram yuborishni rad etdi (HTTP ${response.statusCode}): '
      '${description.isEmpty ? '(tavsif yo\'q)' : description}',
    );
  }

  File _zip(File source) {
    final archive = Archive()
      ..add(
        ArchiveFile(
          source.uri.pathSegments.last,
          source.lengthSync(),
          source.readAsBytesSync(),
        ),
      );

    final out = File('${Directory.systemTemp.createTempSync().path}/'
        '${source.uri.pathSegments.last}.zip');
    out.writeAsBytesSync(
      ZipEncoder().encode(archive, level: DeflateLevel.bestCompression),
    );
    return out;
  }

  String _mb(int bytes) => '${(bytes / 1024 / 1024).round()}MB';
}
