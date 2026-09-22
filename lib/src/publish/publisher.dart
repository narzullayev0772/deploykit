import '../build/build_artifact.dart';

/// The outcome of one upload.
class PublishResult {
  const PublishResult({required this.description, this.versionCode});

  /// A one-line description to show the user.
  final String description;

  /// The versionCode assigned by Play. `null` for iOS.
  final int? versionCode;
}

/// Uploads an artifact to a store.
abstract class Publisher {
  /// With [dryRun] nothing external changes, but every check that can still
  /// run does run.
  Future<PublishResult> publish(BuildArtifact artifact, {required bool dryRun});
}
