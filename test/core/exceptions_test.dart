import 'package:deploykit/src/core/exceptions.dart';
import 'package:test/test.dart';

void main() {
  test('har bir xato turi o\'z exit kodini beradi', () {
    expect(const ConfigException('x').exitCode, 2);
    expect(const PreflightException('x').exitCode, 3);
    expect(const BuildException('x').exitCode, 4);
    expect(const UploadException('x').exitCode, 5);
    expect(const NotifyException('x').exitCode, 6);
  });

  test('toString xabarni o\'z ichiga oladi', () {
    expect(
      const ConfigException('branch bo\'sh').toString(),
      contains('branch bo\'sh'),
    );
  });

  test('hammasi DeployException ostida', () {
    expect(const ConfigException('x'), isA<DeployException>());
    expect(const NotifyException('x'), isA<DeployException>());
  });
}
