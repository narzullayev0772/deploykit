import 'package:deploykit/src/core/branch_guard.dart';
import 'package:deploykit/src/core/exceptions.dart';
import 'package:deploykit/src/core/process_runner.dart';
import 'package:test/test.dart';

FakeProcessRunner _git(String branch) => FakeProcessRunner()
  ..responses['git'] = ProcessResult(0, '$branch\n', '');

void main() {
  test('pattern null bo`lsa git umuman chaqirilmaydi', () async {
    final r = _git('main');
    await BranchGuard(r).check('/p', null);
    expect(r.calls, isEmpty);
  });

  test('mos branch o`tadi', () async {
    await BranchGuard(_git('versions/1.2/dev'))
        .check('/p', r'^versions/.+/dev$');
  });

  test('mos kelmagan branch xato beradi, joriy va pattern ko`rsatiladi', () {
    expect(
      () => BranchGuard(_git('main')).check('/p', r'^versions/.+/release$'),
      throwsA(isA<PreflightException>().having(
        (e) => e.message,
        'message',
        allOf(contains('main'), contains('versions')),
      )),
    );
  });

  test('allowMismatch: true xato bermaydi', () async {
    await BranchGuard(_git('main'))
        .check('/p', r'^versions/.+/dev$', allowMismatch: true);
  });

  test('currentBranch to`g`ri git buyrug`ini chaqiradi', () async {
    final r = _git('feat/x');
    expect(await BranchGuard(r).currentBranch('/p'), 'feat/x');
    expect(r.lastCallTo('git')!.args, ['rev-parse', '--abbrev-ref', 'HEAD']);
    expect(r.lastCallTo('git')!.workingDirectory, '/p');
  });

  test('git yiqilsa PreflightException', () {
    final r = FakeProcessRunner()
      ..responses['git'] = const ProcessResult(128, '', 'not a git repository');
    expect(
      () => BranchGuard(r).currentBranch('/p'),
      throwsA(isA<PreflightException>()
          .having((e) => e.message, 'message', contains('git'))),
    );
  });
}
