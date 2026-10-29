/// Polls analysis and refreshes the running app when it is clean.
library;

import 'dart:async';

import 'package:flutter_ai_whisper/refresh/analysis_gate.dart';
import 'package:flutter_ai_whisper/refresh/dart_member.dart';
import 'package:flutter_ai_whisper/refresh/package_sources.dart';
import 'package:flutter_ai_whisper/refresh/parse_members.dart';
import 'package:flutter_ai_whisper/refresh/refresh_client.dart';
import 'package:flutter_ai_whisper/refresh/refresh_plan.dart';

/// One pass of the change-refresh loop.
class RefreshReport {
  /// Creates a report.
  const RefreshReport({
    required this.unchanged,
    required this.analysisClean,
    required this.advanced,
    required this.summary,
    required this.changed,
    required this.results,
  });

  /// True when no library contents changed since the last advanced pass.
  final bool unchanged;

  /// True when the analyzer reported no errors. Meaningless when [unchanged].
  final bool analysisClean;

  /// True when the baseline moved forward.
  final bool advanced;

  /// Text for the tool result and the MCP log.
  final String summary;

  /// Declarations whose source changed.
  final List<DartMember> changed;

  /// Calls made in the app.
  final List<ActionResult> results;
}

/// Compares package libraries to the last clean snapshot and refreshes.
class ChangeRefreshController {
  /// Creates a controller.
  ChangeRefreshController({
    required this.readSources,
    required this.analyze,
    required this.client,
  });

  /// Reads the package libraries.
  final Future<List<LibrarySource>> Function(String packageRoot) readSources;

  /// Analyzer gate. Clean means a refresh is allowed.
  final Future<AnalysisResult> Function(String packageRoot) analyze;

  /// Connected app.
  final RefreshClient client;

  Map<String, String> _fileContents = {};
  Map<String, String> _bodies = {};
  bool _baselined = false;

  /// Records the current libraries without calling into the app.
  Future<String> baseline(String packageRoot) async {
    final libraries = await readSources(packageRoot);
    _fileContents = _contents(libraries);
    _bodies = memberBodies(_members(libraries));
    _baselined = true;
    return 'Baselined ${libraries.length} libraries in $packageRoot. '
        'Later edits refresh only after analysis reports no errors.';
  }

  /// Refreshes when libraries changed and analysis is clean.
  Future<RefreshReport> refresh(String packageRoot) async {
    final libraries = await readSources(packageRoot);
    final contents = _contents(libraries);
    if (_baselined && _sameContents(contents, _fileContents)) {
      return const RefreshReport(
        unchanged: true,
        analysisClean: true,
        advanced: false,
        summary: 'No library changes.',
        changed: [],
        results: [],
      );
    }
    if (!client.isConnected) {
      return const RefreshReport(
        unchanged: false,
        analysisClean: false,
        advanced: false,
        summary:
            'Not connected to a Flutter app. Call connect_to_app with no '
            'arguments, then leave the refresh watch running.',
        changed: [],
        results: [],
      );
    }

    final analysis = await analyze(packageRoot);
    if (!analysis.clean) {
      return RefreshReport(
        unchanged: false,
        analysisClean: false,
        advanced: false,
        summary:
            'Analysis reported errors, so nothing was reloaded.\n'
            '${analysis.detail}',
        changed: const [],
        results: const [],
      );
    }

    final members = _members(libraries);
    if (!_baselined) {
      _fileContents = contents;
      _bodies = memberBodies(members);
      _baselined = true;
      return RefreshReport(
        unchanged: false,
        analysisClean: true,
        advanced: true,
        summary:
            'Baselined ${libraries.length} libraries. '
            'The next clean edit will reload.',
        changed: const [],
        results: const [],
      );
    }

    final changed = changedMembers(_bodies, members);
    if (changed.isEmpty) {
      _fileContents = contents;
      _bodies = memberBodies(members);
      return const RefreshReport(
        unchanged: false,
        analysisClean: true,
        advanced: true,
        summary: 'Analysis is clean and no class or method body changed.',
        changed: [],
        results: [],
      );
    }

    final loaded = await client.loadLibraries();
    if (!loaded.ok) {
      return RefreshReport(
        unchanged: false,
        analysisClean: true,
        advanced: false,
        summary: _summary(changed, [loaded]),
        changed: changed,
        results: [loaded],
      );
    }

    final actions = planRefresh(changed);
    final results = [loaded, ...await runRefreshActions(client, actions)];
    final failed = results.any((result) => !result.ok);
    if (failed) {
      return RefreshReport(
        unchanged: false,
        analysisClean: true,
        advanced: false,
        summary: _summary(changed, results),
        changed: changed,
        results: results,
      );
    }

    _fileContents = contents;
    _bodies = memberBodies(members);
    return RefreshReport(
      unchanged: false,
      analysisClean: true,
      advanced: true,
      summary: _summary(changed, results),
      changed: changed,
      results: results,
    );
  }
}

/// Watches a package and refreshes on an interval.
class ChangeRefreshWatch {
  /// Creates a watch that reports through [onReport].
  ChangeRefreshWatch({required this.controller, required this.onReport});

  /// Shared controller, so a manual refresh sees the same baseline.
  final ChangeRefreshController controller;

  /// Called for a pass that is not a no-change tick.
  final void Function(String message, {required bool isError}) onReport;

  Timer? _timer;
  String? _packageRoot;
  var _busy = false;
  String? _lastSummary;

  /// Whether the interval is armed.
  bool get isRunning => _timer != null;

  /// Package passed to the last [start] or [bind].
  String? get packageRoot => _packageRoot;

  /// Selects [packageRoot] for [refreshNow] without starting the interval.
  void bind(String packageRoot) {
    _packageRoot = packageRoot;
  }

  /// Baselines [packageRoot] and repeats [refresh] every [interval].
  Future<String> start({
    required String packageRoot,
    required Duration interval,
  }) async {
    await stop();
    _packageRoot = packageRoot;
    _lastSummary = null;
    final message = await controller.baseline(packageRoot);
    _timer = Timer.periodic(interval, (_) {
      unawaited(_tick());
    });
    return message;
  }

  /// Runs one pass against the bound package.
  Future<RefreshReport> refreshNow() async {
    final root = _packageRoot;
    if (root == null) {
      throw StateError(
        'Change refresh has no package. Pass packageRoot or call '
        'start_change_refresh first.',
      );
    }
    return controller.refresh(root);
  }

  /// Stops the interval. The baseline is kept.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    final root = _packageRoot;
    if (root == null || _busy) return;
    _busy = true;
    try {
      final report = await controller.refresh(root);
      if (report.unchanged || report.summary == _lastSummary) return;
      _lastSummary = report.summary;
      final failed =
          !report.analysisClean || report.results.any((result) => !result.ok);
      onReport(report.summary, isError: failed);
    } on Object catch (error) {
      final message = 'Change refresh failed: $error';
      if (message == _lastSummary) return;
      _lastSummary = message;
      onReport(message, isError: true);
    } finally {
      _busy = false;
    }
  }
}

Map<String, String> _contents(List<LibrarySource> libraries) => {
  for (final library in libraries) library.path: library.contents,
};

bool _sameContents(Map<String, String> next, Map<String, String> previous) {
  if (next.length != previous.length) return false;
  for (final entry in next.entries) {
    if (previous[entry.key] != entry.value) return false;
  }
  return true;
}

List<DartMember> _members(List<LibrarySource> libraries) => [
  for (final library in libraries)
    ...parseDartMembers(library.contents, libraryUri: library.libraryUri),
];

String _summary(List<DartMember> changed, List<ActionResult> results) {
  final names = changed.map((member) => member.displayName).join(', ');
  final calls = results.map((result) => result.toString()).join('\n');
  return 'Analysis is clean.\nChanged: $names\n$calls';
}
