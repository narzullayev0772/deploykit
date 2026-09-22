import '../build/build_artifact.dart';

/// The data a notification needs.
class NotifyPayload {
  const NotifyPayload({
    required this.message,
    required this.buildName,
    required this.buildNumber,
    this.attachment,
  });

  final String message;
  final String buildName;
  final int buildNumber;
  final BuildArtifact? attachment;

  String get version => '$buildName+$buildNumber';
}

abstract class Notifier {
  Future<void> send(NotifyPayload payload, {required bool dryRun});
}
