import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import '../build/build_artifact.dart';
import '../config/deploy_config.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';
import 'notifier.dart';

/// Sends a message, and optionally an artifact, to a Telegram chat.
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

  /// Applies the size policy.
  ///
  /// Returns the file to send, or `null` to send nothing. Throws when the
  /// artifact is over the limit and the policy does not allow it through.
  Future<File?> resolveAttachment(BuildArtifact artifact) async {
    final file = File(artifact.path);
    final size = file.lengthSync();

    if (size <= _maxBytes) return file;

    logger.warn(
      '${artifact.type.name.toUpperCase()} is ${_mb(size)} — '
      'the limit is ${config.maxSizeMb}MB.',
    );

    switch (config.onOversize) {
      case OversizePolicy.skip:
        logger.warn('Skipping the attachment (on_oversize: skip).');
        return null;

      case OversizePolicy.fail:
        throw NotifyException(
          'The artifact is ${_mb(size)} and the Telegram limit is '
          '${config.maxSizeMb}MB. on_oversize is set to fail.',
        );

      case OversizePolicy.zip:
        // Native libraries inside an APK (libapp.so, libflutter.so) are
        // STORED uncompressed under AGP's defaults, because Android mmaps
        // them straight out of the archive. An outer zip can therefore help
        // a great deal.
        //
        // But the saving is never ASSUMED — the zip is made and measured.
        logger.info('Zipping ...');
        final zipped = _zip(file);
        final zippedSize = zipped.lengthSync();

        logger.info('${_mb(size)} → ${_mb(zippedSize)}');

        if (zippedSize > _maxBytes) {
          throw NotifyException(
            'Still too large after zipping: ${_mb(size)} → '
            '${_mb(zippedSize)}, and the Telegram limit is '
            '${config.maxSizeMb}MB.\n'
            'Shrink the artifact (--split-per-abi, --obfuscate) or use a '
            'different channel.',
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
        'Telegram: would send ${file == null ? 'a message' : 'a file'} '
        '(dry run)',
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
    logger.ok('Telegram notification sent');
  }

  /// Builds the caption. Public so it can be tested on its own.
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
        buffer.write('\n⚠️ Extract the archive before installing.');
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

    logger.info('Sending to Telegram (${_mb(file.lengthSync())}) ...');
    return http.Response.fromStream(await _client.send(request));
  }

  /// Telegram signals real success only through the `ok` field of its JSON
  /// body.
  ///
  /// This bites in shell scripts: `curl` exits 0 even on HTTP 413, so a
  /// rejected upload looks like a success.
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
      'Telegram rejected the request (HTTP ${response.statusCode}): '
      '${description.isEmpty ? '(no description)' : description}',
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
