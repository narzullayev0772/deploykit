import 'dart:io';

import 'package:http/http.dart' as http;

import 'build/android_builder.dart';
import 'build/build_artifact.dart';
import 'build/ios_builder.dart';
import 'config/config_loader.dart';
import 'config/deploy_config.dart';
import 'core/build_manifest.dart';
import 'core/build_number.dart';
import 'core/exceptions.dart';
import 'core/logger.dart';
import 'core/preflight.dart';
import 'core/process_runner.dart';
import 'notify/notifier.dart';
import 'notify/telegram_notifier.dart';
import 'publish/ios_publisher.dart';
import 'publish/play_publisher.dart';
import 'publish/publisher.dart';

/// Builds an authorised client for Play.
///
/// Injected so tests can exercise the whole flow without a real
/// service-account or a network.
typedef PlayClientFactory = Future<http.Client> Function(
  String serviceAccountPath,
);

/// The shared logic behind `build`, `upload` and `publish`.
///
/// The commands only read flags and hand over to this.
class DeployPipeline {
  DeployPipeline({
    required this.config,
    required this.env,
    required this.projectRoot,
    required this.logger,
    required this.runner,
    required this.client,
    this.playProbe,
    PlayClientFactory? playClientFactory,
  }) : _playClientFactory =
            playClientFactory ?? PlayPublisher.clientFromServiceAccount;

  final DeployConfig config;
  final EnvironmentConfig env;
  final String projectRoot;
  final Logger logger;
  final ProcessRunner runner;
  final http.Client client;
  final PlayProbe? playProbe;
  final PlayClientFactory _playClientFactory;

  File get _manifestFile => File('$projectRoot/.deploykit/last_build.json');
  File get _buildNumberFile => File('$projectRoot/${config.buildNumberFile}');

  /// Builds the artifacts and writes the manifest.
  Future<BuildManifest> build({
    required bool android,
    required bool ios,
    required bool allowBranchMismatch,
    required bool dryRun,
  }) async {
    await _preflight(
      android: android,
      ios: ios,
      allowBranchMismatch: allowBranchMismatch,
      // The network is not needed to build; it is checked again before the
      // upload anyway.
      checkNetwork: false,
    );

    final buildName = BuildNumber.readBuildName('$projectRoot/pubspec.yaml') ??
        '0.0.1';

    if (dryRun) {
      final next = BuildNumber(_buildNumberFile).read() + 1;
      logger.info('Would build: v$buildName+$next');
      _describePlannedArtifacts(android: android, ios: ios);
      return BuildManifest(
        env: env.name,
        buildName: buildName,
        buildNumber: next,
        builtAt: DateTime.now().toUtc(),
        artifacts: const [],
      );
    }

    // The number is bumped BEFORE the build. If the build fails the number
    // is skipped, which is harmless. Reusing one is not: Play rejects a
    // duplicate versionCode.
    final buildNumber = BuildNumber(_buildNumberFile).increment();
    logger.info('Version: $buildName+$buildNumber');

    final artifacts = <BuildArtifact>[];

    if (android && env.android != null) {
      artifacts.addAll(
        await AndroidBuilder(runner: runner, logger: logger).build(
          projectRoot: projectRoot,
          env: env,
          buildName: buildName,
          buildNumber: buildNumber,
        ),
      );
    }

    if (ios && env.ios != null) {
      final asc = config.integrations.appStore;
      if (asc == null) {
        throw const ConfigException(
          'iOS is configured to build, but integrations.app_store is not set.',
        );
      }
      artifacts.add(
        await IosBuilder(runner: runner, logger: logger).build(
          projectRoot: projectRoot,
          env: env,
          asc: asc,
          buildName: buildName,
          buildNumber: buildNumber,
        ),
      );
    }

    final manifest = BuildManifest(
      env: env.name,
      buildName: buildName,
      buildNumber: buildNumber,
      builtAt: DateTime.now().toUtc(),
      artifacts: artifacts,
    )..write(_manifestFile);

    logger.ok('Build complete: v${manifest.version}');
    return manifest;
  }

  /// Uploads the artifacts in the manifest and sends the notification.
  ///
  /// Does **not** bump the build number, which is what makes retrying a
  /// failed upload safe.
  Future<void> upload({
    required BuildManifest manifest,
    required bool android,
    required bool ios,
    required bool allowBranchMismatch,
    required bool dryRun,
    bool runPreflight = true,
  }) async {
    manifest.verifyEnv(env.name);

    if (runPreflight) {
      await _preflight(
        android: android,
        ios: ios,
        allowBranchMismatch: allowBranchMismatch,
        checkNetwork: !dryRun,
      );
    }

    final results = <PublishResult>[];

    if (android) {
      final aab = manifest.artifactOf(ArtifactType.aab);
      if (aab != null) results.add(await _publishAab(aab, dryRun: dryRun));
    }

    if (ios) {
      final ipa = manifest.artifactOf(ArtifactType.ipa);
      if (ipa != null) results.add(await _publishIpa(ipa, dryRun: dryRun));
    }

    for (final r in results) {
      logger.ok(r.description);
    }

    await _notify(manifest, android: android, dryRun: dryRun);
  }

  Future<PublishResult> _publishAab(
    BuildArtifact aab, {
    required bool dryRun,
  }) async {
    final play = env.android?.play;
    final creds = config.integrations.play;
    if (play == null || creds == null) {
      throw const ConfigException(
        'An AAB is being uploaded, but the play settings or the '
        'service-account are missing.',
      );
    }

    // No authorisation for a dry run — we stay off the network.
    final httpClient =
        dryRun ? client : await _playClientFactory(creds.serviceAccount);

    try {
      return await PlayPublisher(
        client: httpClient,
        packageName: config.app.androidPackage,
        play: play,
        logger: logger,
      ).publish(aab, dryRun: dryRun);
    } finally {
      if (!dryRun && !identical(httpClient, client)) httpClient.close();
    }
  }

  Future<PublishResult> _publishIpa(
    BuildArtifact ipa, {
    required bool dryRun,
  }) async {
    final asc = config.integrations.appStore;
    if (asc == null) {
      throw const ConfigException(
        'An IPA is being uploaded, but integrations.app_store is not set.',
      );
    }
    return IosPublisher(runner: runner, asc: asc, logger: logger)
        .publish(ipa, dryRun: dryRun);
  }

  /// A failed notification is not a failed deploy — the artifact is already
  /// uploaded by then. The error is still surfaced to the caller, not
  /// swallowed.
  Future<void> _notify(
    BuildManifest manifest, {
    required bool android,
    required bool dryRun,
  }) async {
    final telegramConfig = env.notify?.telegram;
    final creds = config.integrations.telegram;
    if (telegramConfig == null || creds == null) return;

    final attach = telegramConfig.attach;
    final attachment = attach == null ? null : manifest.artifactOf(attach);

    await TelegramNotifier(
      client: client,
      creds: creds,
      config: telegramConfig,
      logger: logger,
    ).send(
      NotifyPayload(
        message: telegramConfig.message,
        buildName: manifest.buildName,
        buildNumber: manifest.buildNumber,
        attachment: attachment,
      ),
      dryRun: dryRun,
    );
  }

  Future<void> _preflight({
    required bool android,
    required bool ios,
    required bool allowBranchMismatch,
    required bool checkNetwork,
  }) =>
      Preflight(
        runner: runner,
        client: client,
        config: config,
        env: env,
        logger: logger,
        projectRoot: projectRoot,
        playProbe: playProbe ?? _realPlayProbe,
      ).assertReady(
        checkNetwork: checkNetwork,
        android: android,
        ios: ios,
        allowBranchMismatch: allowBranchMismatch,
      );

  static Future<void> _realPlayProbe(String path) async {
    (await PlayPublisher.clientFromServiceAccount(path)).close();
  }

  BuildManifest readManifest() => BuildManifest.read(_manifestFile);

  void _describePlannedArtifacts({required bool android, required bool ios}) {
    if (android && env.android != null) {
      final a = env.android!;
      logger.info(
        '  Android: ${a.artifacts.map((t) => t.name).join(', ')} → '
        'Play track "${a.play.track}" (${a.play.status})',
      );
    }
    if (ios && env.ios != null) {
      logger.info(
        '  iOS: ipa → App Store Connect'
        '${env.ios!.testflightInternalOnly ? ' (TestFlight, internal only)' : ''}',
      );
    }
    final tg = env.notify?.telegram;
    if (tg != null) {
      logger.info(
        '  Telegram: "${tg.message}"'
        '${tg.attach == null ? '' : ' + ${tg.attach!.name}'}',
      );
    }
  }
}
