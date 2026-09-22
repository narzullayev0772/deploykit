import 'package:deploykit/src/core/process_runner.dart';
import 'package:test/test.dart';

void main() {
  test('FakeProcessRunner chaqiruvlarni yozib boradi', () async {
    final runner = FakeProcessRunner();
    await runner.run('flutter', ['build', 'apk'], workingDirectory: '/tmp');

    expect(runner.calls, hasLength(1));
    expect(runner.calls.single.executable, 'flutter');
    expect(runner.calls.single.args, ['build', 'apk']);
    expect(runner.calls.single.workingDirectory, '/tmp');
  });

  test('FakeProcessRunner sozlangan javobni qaytaradi', () async {
    final runner = FakeProcessRunner()
      ..responses['flutter'] = const ProcessResult(1, '', 'yiqildi');

    final r = await runner.run('flutter', ['build']);
    expect(r.exitCode, 1);
    expect(r.stderr, 'yiqildi');
    expect(r.ok, isFalse);
  });

  test('sozlanmagan fayl uchun defaultResponse qaytadi', () async {
    final runner = FakeProcessRunner();
    expect((await runner.run('git', ['status'])).ok, isTrue);
  });

  test('lastCallTo faqat o\'sha faylga qilingan oxirgi chaqiruvni beradi', () async {
    final runner = FakeProcessRunner();
    await runner.run('flutter', ['build', 'appbundle']);
    await runner.run('git', ['status']);
    await runner.run('flutter', ['build', 'apk']);

    expect(runner.lastCallTo('flutter')!.args, ['build', 'apk']);
    expect(runner.lastCallTo('xcodebuild'), isNull);
  });

  test('RealProcessRunner haqiqiy jarayonni ishga tushiradi', () async {
    final r = await const RealProcessRunner().run('echo', ['salom']);
    expect(r.exitCode, 0);
    expect(r.stdout.trim(), 'salom');
  });
}
