import 'dart:convert';
import 'dart:io';

import 'package:googleapis/androidpublisher/v3.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import '../build/build_artifact.dart';
import '../config/deploy_config.dart';
import '../core/exceptions.dart';
import '../core/logger.dart';
import 'publisher.dart';

/// AAB ni Google Play'ga yuklaydi.
///
/// Bu sinf `upload_play.py` ni, u bilan birga `.venv` va
/// `pip install google-api-python-client` ni ham butunlay almashtiradi:
/// `package:googleapis` da androidpublisher API to'liq bor, service-account
/// JWT'ni esa `googleapis_auth` o'zi imzolaydi.
class PlayPublisher implements Publisher {
  PlayPublisher({
    required http.Client client,
    required this.packageName,
    required this.play,
    required this.logger,
    UploadOptions? uploadOptions,
  })  : _api = AndroidPublisherApi(client),
        // Haqiqiy AAB odatda 50MB dan katta, shuning uchun standart holat —
        // resumable. Testlar kichik media bilan oddiy yuklashni ishlatadi,
        // shunda MockClient bitta so'rovni ko'radi va ketma-ketlik
        // tekshiriladi.
        _uploadOptions = uploadOptions ?? ResumableUploadOptions();

  final AndroidPublisherApi _api;
  final String packageName;
  final PlayConfig play;
  final Logger logger;
  final UploadOptions _uploadOptions;

  /// Service-account JSON'dan avtorizatsiyalangan client yasaydi.
  static Future<http.Client> clientFromServiceAccount(String jsonPath) async {
    final file = File(jsonPath);
    if (!file.existsSync()) {
      throw UploadException(
        'Play service-account JSON topilmadi: $jsonPath',
      );
    }

    try {
      final creds = ServiceAccountCredentials.fromJson(
        jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
      );
      return await clientViaServiceAccount(creds, [
        AndroidPublisherApi.androidpublisherScope,
      ]);
    } on UploadException {
      rethrow;
    } catch (e) {
      throw UploadException('Play service-account JSON yaroqsiz ($jsonPath): $e');
    }
  }

  @override
  Future<PublishResult> publish(
    BuildArtifact artifact, {
    required bool dryRun,
  }) async {
    final file = File(artifact.path);
    if (!file.existsSync()) {
      // dryRun bo'lsa ham tekshiriladi — bu haqiqiy tekshiruvning ma'nosi.
      throw UploadException('Yuklash uchun fayl topilmadi: ${artifact.path}');
    }

    if (dryRun) {
      return PublishResult(
        description: 'Play: ${artifact.humanSize} AAB → '
            '"${play.track}" track, status "${play.status}" (dry-run)',
      );
    }

    try {
      final edit = await _api.edits.insert(AppEdit(), packageName);
      final editId = edit.id!;
      logger.detail('Play edit ochildi: $editId');

      logger.info('AAB yuklanmoqda (${artifact.humanSize}) ...');
      final bundle = await _api.edits.bundles.upload(
        packageName,
        editId,
        uploadOptions: _uploadOptions,
        uploadMedia: Media(
          file.openRead(),
          file.lengthSync(),
          contentType: 'application/octet-stream',
        ),
      );

      final versionCode = bundle.versionCode;
      if (versionCode == null) {
        throw const UploadException(
          'Play versionCode qaytarmadi — yuklash tugallanmagan.',
        );
      }
      logger.ok('versionCode $versionCode yuklandi');

      await _api.edits.tracks.update(
        Track(
          track: play.track,
          releases: [
            TrackRelease(
              name: '$versionCode',
              versionCodes: ['$versionCode'],
              status: play.status,
            ),
          ],
        ),
        packageName,
        editId,
        play.track,
      );
      logger.detail('"${play.track}" track yangilandi (${play.status})');

      await _api.edits.commit(packageName, editId);

      return PublishResult(
        description: 'Play: versionCode $versionCode → '
            '"${play.track}" (${play.status})',
        versionCode: versionCode,
      );
    } on UploadException {
      rethrow;
    } on DetailedApiRequestError catch (e) {
      // googleapis ichki turlarini tashqariga chiqarmaymiz — foydalanuvchi
      // uchun bu shovqin.
      throw UploadException(
        'Google Play rad etdi (HTTP ${e.status}): ${e.message ?? e.toString()}',
      );
    } catch (e) {
      throw UploadException('Google Play ga yuklashda xato: $e');
    }
  }
}
