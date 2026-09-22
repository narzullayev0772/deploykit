/// Base class for every expected failure during a deploy.
///
/// Each subtype carries its own exit code so CI can tell the failures apart.
/// The codes are part of the public interface and do not change.
abstract class DeployException implements Exception {
  const DeployException(this.message);

  final String message;

  /// The process exits with this code.
  int get exitCode;

  @override
  String toString() => '$runtimeType: $message';
}

/// Malformed YAML, a missing required field, or an unresolved `${VAR}`.
class ConfigException extends DeployException {
  const ConfigException(super.message);

  @override
  int get exitCode => 2;
}

/// Wrong branch, a missing tool, or an unreadable key file.
class PreflightException extends DeployException {
  const PreflightException(super.message);

  @override
  int get exitCode => 3;
}

/// `flutter` or `xcodebuild` failed.
class BuildException extends DeployException {
  const BuildException(super.message);

  @override
  int get exitCode => 4;
}

/// Google Play or App Store Connect rejected the upload.
class UploadException extends DeployException {
  const UploadException(super.message);

  @override
  int get exitCode => 5;
}

/// The deploy succeeded but the notification did not go out.
///
/// This gets its own code because the artifact is already uploaded at that
/// point — the deploy itself was fine, only the message failed.
class NotifyException extends DeployException {
  const NotifyException(super.message);

  @override
  int get exitCode => 6;
}
