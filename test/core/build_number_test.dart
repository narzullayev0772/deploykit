import 'dart:io';

import 'package:deploykit/src/core/build_number.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:test/test.dart';

Directory _tmp() => Directory.systemTemp.createTempSync();

void main() {
  test('increment 45 dan 46 qiladi va faylga yozadi', () {
    final f = File('${_tmp().path}/.last_build_number')..writeAsStringSync('45');
    expect(BuildNumber(f).increment(), 46);
    expect(f.readAsStringSync().trim(), '46');
  });

  test('read faylni o`qiydi', () {
    final f = File('${_tmp().path}/n')..writeAsStringSync('7\n');
    expect(BuildNumber(f).read(), 7);
  });

  test('fayl yo`q bo`lsa init tavsiya qilinadi', () {
    expect(
      () => BuildNumber(File('${_tmp().path}/yoq')).read(),
      throwsA(isA<ConfigException>()
          .having((e) => e.message, 'message', contains('deploykit init'))),
    );
  });

  test('fayl ichida axlat bo`lsa xato', () {
    final f = File('${_tmp().path}/n')..writeAsStringSync('abc');
    expect(() => BuildNumber(f).read(), throwsA(isA<ConfigException>()));
  });

  test('initialiseFrom pubspec dagi + dan keyingi raqamni oladi', () {
    final d = _tmp().path;
    File('$d/pubspec.yaml').writeAsStringSync('name: x\nversion: 1.2.3+45\n');
    final f = File('$d/.last_build_number');
    BuildNumber(f).initialiseFrom('$d/pubspec.yaml');
    expect(f.readAsStringSync().trim(), '45');
  });

  test('pubspec da + bo`lmasa 0', () {
    final d = _tmp().path;
    File('$d/pubspec.yaml').writeAsStringSync('version: 1.2.3\n');
    final f = File('$d/.last_build_number');
    BuildNumber(f).initialiseFrom('$d/pubspec.yaml');
    expect(f.readAsStringSync().trim(), '0');
  });

  test('pubspec yo`q bo`lsa 0', () {
    final f = File('${_tmp().path}/.last_build_number');
    BuildNumber(f).initialiseFrom('/yo/q/pubspec.yaml');
    expect(f.readAsStringSync().trim(), '0');
  });

  test('buildName pubspec dan o`qiladi', () {
    final d = _tmp().path;
    File('$d/pubspec.yaml').writeAsStringSync('version: 1.2.3+45\n');
    expect(BuildNumber.readBuildName('$d/pubspec.yaml'), '1.2.3');
  });
}
