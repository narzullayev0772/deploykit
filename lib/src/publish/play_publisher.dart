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

/// Uploads an AAB to Google Play.
///
/// This replaces the usual Python helper together with its virtualenv and
/// `pip install google-api-python-client`: `package:googleapis` ships the
/// full androidpublisher API, and `googleapis_auth` signs the service-account
/// JWT itself.
class PlayPublisher implements Publisher {
  PlayPublisher({
    required http.Client client,
    required this.packageName,
    required this.play,
    required this.logger,
    UploadOptions? uploadOptions,
  })  : _api = AndroidPublisherApi(client),
        // A real AAB is usually well over 50MB, so resumable is the
        // default. Tests pass small media with the simple options so a
        // MockClient sees one request and the sequence can be asserted.
        _uploadOptions = uploadOptions ?? ResumableUploadOptions();

  final AndroidPublisherApi _api;
  final String packageName;
  final PlayConfig play;
  final Logger logger;
  final UploadOptions _uploadOptions;

  /// Builds an authorised client from a service-account JSON file.
  static Future<http.Client> clientFromServiceAccount(String jsonPath) async {
    final file = File(jsonPath);
    if (!file.existsSync()) {
      throw UploadException(
        'Play service-account JSON not found: $jsonPath',
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
      throw UploadException(
        'Play service-account JSON is invalid ($jsonPath): $e',
      );
    }
  }

  @override
  Future<PublishResult> publish(
    BuildArtifact artifact, {
    required bool dryRun,
  }) async {
    final file = File(artifact.path);
    if (!file.existsSync()) {
      // Checked even for a dry run — that is what makes a dry run useful.
      throw UploadException('File to upload not found: ${artifact.path}');
    }

    if (dryRun) {
      return PublishResult(
        description: 'Play: ${artifact.humanSize} AAB → '
            'track "${play.track}", status "${play.status}" (dry run)',
      );
    }

    try {
      final edit = await _api.edits.insert(AppEdit(), packageName);
      final editId = edit.id!;
      logger.detail('Opened Play edit $editId');

      logger.info('Uploading AAB (${artifact.humanSize}) ...');
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
          'Play returned no versionCode — the upload did not complete.',
        );
      }
      logger.ok('Uploaded versionCode $versionCode');

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
      logger.detail('Updated track "${play.track}" (${play.status})');

      await _api.edits.commit(packageName, editId);

      return PublishResult(
        description: 'Play: versionCode $versionCode → '
            '"${play.track}" (${play.status})',
        versionCode: versionCode,
      );
    } on UploadException {
      rethrow;
    } on DetailedApiRequestError catch (e) {
      // googleapis internals never reach the user — that is just noise.
      throw UploadException(
        'Google Play rejected the upload (HTTP ${e.status}): '
        '${e.message ?? e}',
      );
    } catch (e) {
      throw UploadException('Failed to upload to Google Play: $e');
    }
  }
}
