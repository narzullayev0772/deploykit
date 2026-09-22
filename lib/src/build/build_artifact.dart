import 'dart:io';

import '../config/deploy_config.dart';

/// A single produced file.
class BuildArtifact {
  const BuildArtifact(this.type, this.path);

  final ArtifactType type;
  final String path;

  File get file => File(path);

  int get sizeBytes => file.lengthSync();

  /// Human-readable size, e.g. `46MB`.
  String get humanSize => '${(sizeBytes / 1024 / 1024).round()}MB';

  Map<String, Object?> toJson() => {'type': type.name, 'path': path};

  static BuildArtifact fromJson(Map<String, Object?> j) => BuildArtifact(
        ArtifactType.values.byName(j['type']! as String),
        j['path']! as String,
      );

  @override
  String toString() => '${type.name}: $path';
}
