import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'version.dart';

/// Where the update stands, as Settings → Updates shows it.
enum SourceUpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  building,
  ready,
  failed,
}

/// Updating the custom build from its sources: what `baocode-dev/baocode`
/// has that this checkout does not, and the build that takes it.
///
/// The build is [`tool/in_app_update.sh`]'s: it merges, tests and builds
/// while the app runs, then puts the new build in place once the app quits
/// and opens it again (as the official update does). Nothing is replaced
/// under a running app.
class SourceUpdateController extends ChangeNotifier {
  SourceUpdateController({
    required this.sourceDir,
    required this.logPath,
    this.upstreamUrl = 'https://github.com/baocode-dev/baocode.git',
    this.upstreamBranch = 'main',
    this.autoUpdate,
    this.checkEvery = const Duration(hours: 6),
  });

  /// The checkout this build came from; its scripts do the work.
  final String sourceDir;

  /// Where the build writes what it does.
  final String logPath;

  final String upstreamUrl;
  final String upstreamBranch;

  /// Whether a new upstream commit is taken without being asked
  /// (`update.mode`, which the page's dropdown writes).
  final bool Function()? autoUpdate;

  /// How often the app looks again while it runs.
  final Duration checkEvery;

  SourceUpdateStatus status = SourceUpdateStatus.idle;
  DateTime? lastChecked;

  /// The commits upstream has after the one this checkout is on; none when
  /// it is not behind.
  int upstreamCommits = 0;

  /// The version upstream publishes (`pubspec.yaml`'s at its main), when it
  /// names one.
  AppVersion? upstreamVersion;

  /// The version that is running: what a new one is newer than.
  AppVersion localVersion = currentAppVersion;

  /// Whether upstream publishes a version newer than the one running. The
  /// commits it has are said too, but a commit that keeps the version is
  /// no update: releases are what this build takes.
  bool get hasNewVersion =>
      upstreamVersion != null &&
      upstreamVersion!.compareTo(localVersion) > 0;

  /// This checkout's commit, short.
  String? localCommit;

  /// Why the check or the build failed.
  String? error;

  /// The last lines of [logPath] while a build runs.
  String? logTail;

  bool _checking = false;
  Timer? _every;
  Timer? _watching;

  bool get busy =>
      status == SourceUpdateStatus.checking ||
      status == SourceUpdateStatus.building;

  /// Looks now, and again every [checkEvery] while the app runs. A new
  /// upstream commit is built at once where [autoUpdate] says so.
  void start() {
    unawaited(check());
    _every ??= Timer.periodic(checkEvery, (_) => unawaited(check()));
  }

  @override
  void dispose() {
    _every?.cancel();
    _watching?.cancel();
    super.dispose();
  }

  Future<void> check() async {
    if (_checking || status == SourceUpdateStatus.building) return;
    _checking = true;
    _set(SourceUpdateStatus.checking);
    try {
      await _git(['fetch', '--no-tags', upstreamUrl, upstreamBranch]);
      localCommit = (await _git(['rev-parse', '--short', 'HEAD'])).trim();
      final ahead = int.tryParse(
        (await _git(['rev-list', '--count', 'HEAD..FETCH_HEAD'])).trim(),
      );
      upstreamCommits = ahead ?? 0;
      upstreamVersion = await _versionOfUpstream();
      lastChecked = DateTime.now();
      error = null;
      _set(
        hasNewVersion
            ? SourceUpdateStatus.available
            : SourceUpdateStatus.upToDate,
      );
      if (hasNewVersion && (autoUpdate?.call() ?? false)) {
        await update();
      }
    } on Object catch (problem) {
      error = '$problem';
      _set(SourceUpdateStatus.failed);
    } finally {
      _checking = false;
    }
  }

  /// Starts the build, which installs once the app quits. False when it
  /// could not start at all (the page then shows [error]).
  Future<bool> update() async {
    if (status == SourceUpdateStatus.building) return false;
    final script = p.join(sourceDir, 'tool', 'in_app_update.sh');
    if (!File(script).existsSync()) {
      error = script;
      _set(SourceUpdateStatus.failed);
      return false;
    }
    try {
      Directory(p.dirname(logPath)).createSync(recursive: true);
      // One run's log: the previous one's markers would read as this one's.
      await File(logPath).writeAsString('', flush: true);
      error = null;
      logTail = null;
      // Detached: the build outlives the app, which it waits for.
      await Process.start(
        script,
        ['$pid'],
        mode: ProcessStartMode.detached,
        workingDirectory: sourceDir,
        environment: {...Platform.environment, 'BAOCODE_UPDATE_LOG': logPath},
      );
    } on Object catch (problem) {
      error = '$problem';
      _set(SourceUpdateStatus.failed);
      return false;
    }
    _set(SourceUpdateStatus.building);
    _watching?.cancel();
    _watching = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _readLog(),
    );
    return true;
  }

  /// Opens the log in the app the system opens it with.
  Future<void> openLog() async {
    await Process.run('open', [logPath]);
  }

  /// What the build last wrote: its markers say how it went.
  void _readLog() {
    if (status != SourceUpdateStatus.building) return;
    final String text;
    try {
      final file = File(logPath);
      if (!file.existsSync()) return;
      final length = file.lengthSync();
      final from = length > 8192 ? length - 8192 : 0;
      final handle = file.openSync();
      try {
        handle.setPositionSync(from);
        text = String.fromCharCodes(handle.readSync(length - from));
      } finally {
        handle.closeSync();
      }
    } on FileSystemException {
      return;
    }
    final lines = text
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    logTail = lines.skip(lines.length > 12 ? lines.length - 12 : 0).join('\n');
    if (text.contains('==> Ready')) {
      _stopWatching();
      _set(SourceUpdateStatus.ready);
    } else if (text.contains('==> Failed')) {
      _stopWatching();
      error = lines.lastWhere(
        (line) => line.contains('==> Failed'),
        orElse: () => '',
      );
      _set(SourceUpdateStatus.failed);
    } else if (status == SourceUpdateStatus.building) {
      notifyListeners();
    }
  }

  void _stopWatching() {
    _watching?.cancel();
    _watching = null;
  }

  Future<AppVersion?> _versionOfUpstream() async {
    final pubspec = await _git(['show', 'FETCH_HEAD:pubspec.yaml']);
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    return match == null ? null : AppVersion.tryParse(match.group(1)!);
  }

  Future<String> _git(List<String> arguments) async {
    final git = File('/usr/bin/git').existsSync() ? '/usr/bin/git' : 'git';
    final result = await Process.run(
      git,
      ['-C', sourceDir, ...arguments],
    ).timeout(const Duration(minutes: 2));
    if (result.exitCode != 0) {
      final said = '${result.stderr}'.trim();
      throw StateError(said.isEmpty ? 'git ${arguments.first} failed' : said);
    }
    return '${result.stdout}';
  }

  void _set(SourceUpdateStatus next) {
    status = next;
    notifyListeners();
  }
}
