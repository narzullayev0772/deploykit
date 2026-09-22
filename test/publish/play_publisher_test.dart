import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:deploykit/src/build/build_artifact.dart';
import 'package:deploykit/src/config/deploy_config.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:deploykit/src/core/logger.dart';
import 'package:deploykit/src/publish/play_publisher.dart';
import 'package:googleapis/androidpublisher/v3.dart' show UploadOptions;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Logger _quiet() =>
    Logger(color: false, sink: IOSink(StreamController<List<int>>().sink));

BuildArtifact _aab() {
  final f = File('${Directory.systemTemp.createTempSync().path}/app.aab')
    ..writeAsStringSync('soxta aab mazmuni');
  return BuildArtifact(ArtifactType.aab, f.path);
}

/// So'rovlarni yozib boradigan va tayyor javoblar qaytaradigan client.
class _Recorder {
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];

  http.Client client({int versionCode = 4211, Map<String, int> status = const {}}) {
    return MockClient((req) async {
      requests.add(req);
      bodies.add(req.body);

      final path = req.url.path;
      for (final e in status.entries) {
        if (path.contains(e.key)) {
          return http.Response('{"error":{"message":"rad etildi"}}', e.value);
        }
      }

      if (path.endsWith('/edits')) {
        return http.Response(jsonEncode({'id': 'edit-1'}), 200,
            headers: {'content-type': 'application/json'});
      }
      if (path.contains('/bundles')) {
        return http.Response(jsonEncode({'versionCode': versionCode}), 200,
            headers: {'content-type': 'application/json'});
      }
      if (path.contains('/tracks/')) {
        return http.Response(jsonEncode({'track': 'internal'}), 200,
            headers: {'content-type': 'application/json'});
      }
      if (path.endsWith(':commit')) {
        return http.Response(jsonEncode({'id': 'edit-1'}), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 200,
          headers: {'content-type': 'application/json'});
    });
  }

  List<String> get paths => requests.map((r) => r.url.path).toList();
}

PlayPublisher _publisher(
  http.Client c, {
  String track = 'internal',
  String status = 'completed',
}) =>
    PlayPublisher(
      client: c,
      packageName: 'com.example.app',
      play: PlayConfig(track: track, status: status),
      logger: _quiet(),
      // Oddiy (multipart) yuklash: MockClient bitta so'rovni ko'radi va
      // ketma-ketlikni tekshirish mumkin bo'ladi. Ishlab chiqarishda
      // standart qiymat resumable, chunki AAB odatda 50MB dan katta.
      uploadOptions: UploadOptions.defaultOptions,
    );

void main() {
  test('to`liq oqim to`g`ri tartibda bajariladi', () async {
    final rec = _Recorder();
    await _publisher(rec.client()).publish(_aab(), dryRun: false);

    expect(rec.paths, hasLength(4));
    expect(rec.paths[0], endsWith('/edits'));
    expect(rec.paths[1], contains('/bundles'));
    expect(rec.paths[2], contains('/tracks/internal'));
    expect(rec.paths[3], endsWith(':commit'));
  });

  test('paket nomi har bir so`rovda bo`ladi', () async {
    final rec = _Recorder();
    await _publisher(rec.client()).publish(_aab(), dryRun: false);
    for (final p in rec.paths) {
      expect(p, contains('com.example.app'));
    }
  });

  test('track va status yuboriladi', () async {
    final rec = _Recorder();
    await _publisher(rec.client()).publish(_aab(), dryRun: false);

    final trackBody =
        jsonDecode(rec.bodies[2]) as Map<String, Object?>;
    expect(trackBody['track'], 'internal');

    final release = (trackBody['releases']! as List).single as Map;
    expect(release['status'], 'completed');
  });

  test('production draft uchun to`g`ri qiymatlar', () async {
    final rec = _Recorder();
    await _publisher(rec.client(), track: 'production', status: 'draft')
        .publish(_aab(), dryRun: false);

    expect(rec.paths[2], contains('/tracks/production'));
    final body = jsonDecode(rec.bodies[2]) as Map<String, Object?>;
    final release = (body['releases']! as List).single as Map;
    expect(release['status'], 'draft');
  });

  test('versionCode bundle javobidan olinadi', () async {
    final rec = _Recorder();
    final result =
        await _publisher(rec.client(versionCode: 9876)).publish(_aab(), dryRun: false);

    final body = jsonDecode(rec.bodies[2]) as Map<String, Object?>;
    final release = (body['releases']! as List).single as Map;
    expect(release['versionCodes'], ['9876']);
    expect(release['name'], '9876');
    expect(result.versionCode, 9876);
  });

  test('dryRun: hech qanday HTTP so`rov yo`q', () async {
    final rec = _Recorder();
    final result = await _publisher(rec.client()).publish(_aab(), dryRun: true);

    expect(rec.requests, isEmpty);
    expect(result.description, allOf(contains('internal'), contains('completed')));
  });

  test('AAB fayli yo`q bo`lsa UploadException', () {
    expect(
      () => _publisher(_Recorder().client())
          .publish(const BuildArtifact(ArtifactType.aab, '/yo/q/app.aab'), dryRun: false),
      throwsA(isA<UploadException>()
          .having((e) => e.message, 'message', contains('/yo/q/app.aab'))),
    );
  });

  test('edits.insert rad etsa UploadException', () {
    final rec = _Recorder();
    expect(
      () => _publisher(rec.client(status: {'/edits': 403}))
          .publish(_aab(), dryRun: false),
      throwsA(isA<UploadException>()),
    );
  });

  test('bundle yuklash rad etsa UploadException', () {
    final rec = _Recorder();
    expect(
      () => _publisher(rec.client(status: {'/bundles': 400}))
          .publish(_aab(), dryRun: false),
      throwsA(isA<UploadException>()),
    );
  });

  test('googleapis ichki xato turi tashqariga chiqmaydi', () async {
    final rec = _Recorder();
    try {
      await _publisher(rec.client(status: {'/bundles': 400}))
          .publish(_aab(), dryRun: false);
      fail('xato kutilgan edi');
    } catch (e) {
      expect(e, isA<UploadException>());
      expect(e.toString(), isNot(contains('DetailedApiRequestError')));
    }
  });

  test('service-account JSON yo`q bo`lsa UploadException', () {
    expect(
      () => PlayPublisher.clientFromServiceAccount('/yo/q/sa.json'),
      throwsA(isA<UploadException>()
          .having((e) => e.message, 'message', contains('/yo/q/sa.json'))),
    );
  });
}
