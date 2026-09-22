import 'dart:io';

import 'package:deploykit/src/config/env_resolver.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:test/test.dart';

String _tmpEnv(String contents) {
  final f = File('${Directory.systemTemp.createTempSync().path}/.env')
    ..writeAsStringSync(contents);
  return f.path;
}

void main() {
  group('resolve', () {
    test(r'${VAR} ni almashtiradi', () {
      final r = EnvResolver({'TOKEN': 'abc123'});
      expect(r.resolve(r'${TOKEN}', path: 'x'), 'abc123');
    });

    test(r'matn ichidagi ${VAR} ni ham almashtiradi', () {
      final r = EnvResolver({'H': 'example.com'});
      expect(r.resolve(r'https://${H}/api', path: 'x'), 'https://example.com/api');
    });

    test(r'bir matnda bir nechta ${VAR}', () {
      final r = EnvResolver({'A': '1', 'B': '2'});
      expect(r.resolve(r'${A}-${B}', path: 'x'), '1-2');
    });

    test(r'${VAR} yo`q bo`lsa yo`l bilan xato beradi', () {
      expect(
        () => EnvResolver({}).resolve(
          r'${MISSING}',
          path: 'integrations.telegram.bot_token',
        ),
        throwsA(isA<ConfigException>().having(
          (e) => e.message,
          'message',
          allOf(
            contains('MISSING'),
            contains('integrations.telegram.bot_token'),
          ),
        )),
      );
    });

    test(r'${VAR} bo`lmagan matn o`zgarmaydi', () {
      expect(EnvResolver({}).resolve('oddiy matn', path: 'x'), 'oddiy matn');
    });

    test(r'bo`sh qiymatli ${VAR} ham haqiqiy qiymat', () {
      expect(EnvResolver({'E': ''}).resolve(r'${E}', path: 'x'), '');
    });
  });

  group('resolveDeep', () {
    test('ichma-ich Map va List bo`ylab yuradi', () {
      final out = EnvResolver({'A': '1', 'B': '2'}).resolveDeep({
        'x': r'${A}',
        'y': [r'${B}', 'z'],
        'n': 42,
      });
      expect(out, {
        'x': '1',
        'y': ['2', 'z'],
        'n': 42,
      });
    });

    test('String bo`lmagan qiymatlarga tegmaydi', () {
      final out = EnvResolver({}).resolveDeep({'a': 1, 'b': true, 'c': null});
      expect(out, {'a': 1, 'b': true, 'c': null});
    });

    test('xato yo`lida to`liq kalit zanjiri bo`ladi', () {
      expect(
        () => EnvResolver({}).resolveDeep({
          'integrations': {
            'telegram': {'bot_token': r'${NOPE}'},
          },
        }),
        throwsA(isA<ConfigException>().having(
          (e) => e.message,
          'message',
          contains('integrations.telegram.bot_token'),
        )),
      );
    });

    test('List indeksi yo`lda ko`rsatiladi', () {
      expect(
        () => EnvResolver({}).resolveDeep({
          'a': ['ok', r'${NOPE}'],
        }),
        throwsA(isA<ConfigException>()
            .having((e) => e.message, 'message', contains('a[1]'))),
      );
    });
  });

  group('load', () {
    test('.env faylni o`qiydi, izoh va qo`shtirnoqni tashlaydi', () {
      final r = EnvResolver.load(
        envFile: _tmpEnv('# izoh\nTOKEN="abc"\n\nCHAT=-100123\n'),
        platformEnv: {},
      );
      expect(r.resolve(r'${TOKEN}', path: 'x'), 'abc');
      expect(r.resolve(r'${CHAT}', path: 'x'), '-100123');
    });

    test('bir tirnoq ham olib tashlanadi', () {
      final r = EnvResolver.load(envFile: _tmpEnv("K='v'\n"), platformEnv: {});
      expect(r.resolve(r'${K}', path: 'x'), 'v');
    });

    test('qiymat ichidagi = saqlanadi', () {
      final r = EnvResolver.load(envFile: _tmpEnv('K=a=b=c\n'), platformEnv: {});
      expect(r.resolve(r'${K}', path: 'x'), 'a=b=c');
    });

    test('muhit o`zgaruvchisi .env dan ustun', () {
      final r = EnvResolver.load(
        envFile: _tmpEnv('TOKEN=fayldan\n'),
        platformEnv: {'TOKEN': 'muhitdan'},
      );
      expect(r.resolve(r'${TOKEN}', path: 'x'), 'muhitdan');
    });

    test('.env fayli yo`q bo`lsa xato emas', () {
      final r = EnvResolver.load(
        envFile: '/yo/q/.env',
        platformEnv: {'A': '1'},
      );
      expect(r.resolve(r'${A}', path: 'x'), '1');
    });

    test('export prefiksi qabul qilinadi', () {
      final r = EnvResolver.load(
        envFile: _tmpEnv('export K=v\n'),
        platformEnv: {},
      );
      expect(r.resolve(r'${K}', path: 'x'), 'v');
    });
  });
}
