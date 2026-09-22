import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:deploykit/src/build/build_artifact.dart';
import 'package:deploykit/src/config/deploy_config.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:deploykit/src/core/logger.dart';
import 'package:deploykit/src/notify/notifier.dart';
import 'package:deploykit/src/notify/telegram_notifier.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

Logger _quiet() =>
    Logger(color: false, sink: IOSink(StreamController<List<int>>().sink));

const _creds = TelegramIntegration(botToken: 'tok', chatId: '-100123');

/// Takrorlanuvchi baytlar — zip juda yaxshi siqadi.
BuildArtifact _compressible(int bytes) {
  final f = File('${Directory.systemTemp.createTempSync().path}/app.apk')
    ..writeAsBytesSync(List.filled(bytes, 0x41));
  return BuildArtifact(ArtifactType.apk, f.path);
}

/// Tasodifiy baytlar — zip deyarli yordam bermaydi.
BuildArtifact _incompressible(int bytes) {
  final rnd = Random(42);
  final f = File('${Directory.systemTemp.createTempSync().path}/app.apk')
    ..writeAsBytesSync(
        List.generate(bytes, (_) => rnd.nextInt(256)));
  return BuildArtifact(ArtifactType.apk, f.path);
}

class _Recorder {
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];

  http.Client client({bool ok = true, int status = 200, String? description}) =>
      MockClient((req) async {
        requests.add(req);
        bodies.add(req.body);
        return http.Response(
          jsonEncode({'ok': ok, 'description': ?description}),
          status,
        );
      });

  List<String> get methods =>
      requests.map((r) => r.url.pathSegments.last).toList();
}

TelegramNotifier _notifier(
  http.Client c, {
  int maxSizeMb = 50,
  OversizePolicy policy = OversizePolicy.zip,
  ArtifactType? attach = ArtifactType.apk,
}) =>
    TelegramNotifier(
      client: c,
      creds: _creds,
      config: TelegramConfig(
        message: 'DEV build, test only',
        attach: attach,
        maxSizeMb: maxSizeMb,
        onOversize: policy,
      ),
      logger: _quiet(),
    );

NotifyPayload _payload(BuildArtifact? a) => NotifyPayload(
      message: 'DEV build, test only',
      buildName: '1.2.3',
      buildNumber: 45,
      attachment: a,
    );

const _mb = 1024 * 1024;

void main() {
  group('resolveAttachment — hajm siyosati', () {
    test('chegaradan kichik fayl o`zgarmaydi', () async {
      final a = _compressible(_mb ~/ 2);
      final out = await _notifier(_Recorder().client(), maxSizeMb: 1)
          .resolveAttachment(a);
      expect(out!.path, a.path);
      expect(out.path, isNot(endsWith('.zip')));
    });

    test('katta va siqiladigan fayl zip qilinadi', () async {
      final a = _compressible(3 * _mb);
      final out = await _notifier(_Recorder().client(), maxSizeMb: 1)
          .resolveAttachment(a);

      expect(out!.path, endsWith('.zip'));
      expect(out.lengthSync(), lessThan(_mb));
      // Asl fayl o'zgarmaydi.
      expect(File(a.path).lengthSync(), 3 * _mb);
    });

    test('zip ham yordam bermasa NotifyException, ikkala hajm xabarda',
        () async {
      final a = _incompressible(3 * _mb);
      await expectLater(
        _notifier(_Recorder().client(), maxSizeMb: 1).resolveAttachment(a),
        throwsA(isA<NotifyException>().having(
          (e) => e.message,
          'message',
          allOf(contains('3MB'), contains('1MB')),
        )),
      );
    });

    test('policy fail — zip umuman yaratilmaydi', () async {
      final a = _compressible(3 * _mb);
      await expectLater(
        _notifier(
          _Recorder().client(),
          maxSizeMb: 1,
          policy: OversizePolicy.fail,
        ).resolveAttachment(a),
        throwsA(isA<NotifyException>()),
      );
      expect(File('${a.path}.zip').existsSync(), isFalse);
    });

    test('policy skip — null qaytadi, xato yo`q', () async {
      final out = await _notifier(
        _Recorder().client(),
        maxSizeMb: 1,
        policy: OversizePolicy.skip,
      ).resolveAttachment(_compressible(3 * _mb));
      expect(out, isNull);
    });
  });

  group('send', () {
    test('biriktirma yo`q bo`lsa sendMessage', () async {
      final rec = _Recorder();
      await _notifier(rec.client(), attach: null)
          .send(_payload(null), dryRun: false);

      expect(rec.methods, ['sendMessage']);
      expect(rec.requests.single.url.path, contains('bottok'));
    });

    test('biriktirma bor bo`lsa sendDocument', () async {
      final rec = _Recorder();
      await _notifier(rec.client())
          .send(_payload(_compressible(1024)), dryRun: false);

      expect(rec.methods, ['sendDocument']);
      // MockClient MultipartRequest'ni oddiy Request'ga aylantiradi,
      // shuning uchun multipart ekanini content-type orqali tekshiramiz.
      expect(
        rec.requests.single.headers['content-type'],
        contains('multipart/form-data'),
      );
    });

    test('HTTP 200 lekin ok:false — NotifyException', () async {
      // curl HTTP 413 da ham 0 qaytaradi; haqiqiy muvaffaqiyat faqat
      // JSON dagi "ok" maydonida bildiriladi.
      final rec = _Recorder();
      await expectLater(
        _notifier(rec.client(ok: false, description: 'chat not found'))
            .send(_payload(null), dryRun: false),
        throwsA(isA<NotifyException>()
            .having((e) => e.message, 'message', contains('chat not found'))),
      );
    });

    test('HTTP 413 — NotifyException, hajm tilga olinadi', () async {
      final rec = _Recorder();
      await expectLater(
        _notifier(rec.client(ok: false, status: 413))
            .send(_payload(_compressible(1024)), dryRun: false),
        throwsA(isA<NotifyException>()
            .having((e) => e.message, 'message', contains('413'))),
      );
    });

    test('dryRun — hech qanday HTTP so`rov yo`q', () async {
      final rec = _Recorder();
      await _notifier(rec.client())
          .send(_payload(_compressible(1024)), dryRun: true);
      expect(rec.requests, isEmpty);
    });

    test('izohda versiya va hajm bo`ladi', () async {
      final rec = _Recorder();
      final n = _notifier(rec.client());
      expect(
        n.buildCaption(_payload(_compressible(2 * _mb)), zipped: false),
        allOf(contains('1.2.3+45'), contains('2MB'), contains('DEV build')),
      );
    });

    test('zip bo`lsa izohda ikkala hajm va ochish haqida yoziladi', () async {
      final rec = _Recorder();
      final n = _notifier(rec.client(), maxSizeMb: 1);
      final a = _compressible(3 * _mb);
      final zip = await n.resolveAttachment(a);

      final caption = n.buildCaption(
        _payload(a),
        zipped: true,
        zippedBytes: zip!.lengthSync(),
      );
      expect(caption, contains('3MB'));
      expect(caption, contains('zip'));
      expect(caption.toLowerCase(), contains('extract'));
    });
  });
}
