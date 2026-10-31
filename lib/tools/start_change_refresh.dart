/// The `start_change_refresh` and `refresh_changed_members` MCP tools.
library;

import 'package:flutter_ai_whisper/refresh/change_refresh.dart';
import 'package:mcp_server/mcp_server.dart';

/// Starts a 10-second watch that refreshes the app after clean analysis.
Future<CallToolResult> startChangeRefresh(
  ChangeRefreshWatch watch,
  Map<String, dynamic> args,
) async {
  final packageRoot = args['packageRoot'];
  if (packageRoot is! String || packageRoot.isEmpty) {
    return _error('Provide `packageRoot`, the Flutter package to analyze.');
  }
  final rawInterval = args['intervalSeconds'];
  final seconds = rawInterval == null
      ? 10
      : rawInterval is num
      ? rawInterval.toInt()
      : null;
  if (seconds == null || seconds < 1) {
    return _error('`intervalSeconds` must be a number of seconds, at least 1.');
  }
  if (!watch.controller.client.isConnected) {
    return _error(
      'Not connected to a Flutter app. Call connect_to_app with no arguments '
      'before start_change_refresh.',
    );
  }

  try {
    final message = await watch.start(
      packageRoot: packageRoot,
      interval: Duration(seconds: seconds),
    );
    return CallToolResult(
      content: [
        TextContent(
          text:
              '$message\n'
              'Watching every $seconds seconds. When analysis reports no '
              'errors, the server loads the changed library and then evaluates '
              'only that class method. State methods run inside setState.',
        ),
      ],
    );
  } on Object catch (error) {
    return _error('Could not start change refresh: $error');
  }
}

/// Runs one refresh pass. Pass [args] `packageRoot` when the watch is stopped.
Future<CallToolResult> refreshChangedMembers(
  ChangeRefreshWatch watch,
  Map<String, dynamic> args,
) async {
  final packageRoot = args['packageRoot'];
  if (!watch.isRunning && packageRoot is String && packageRoot.isNotEmpty) {
    watch.bind(packageRoot);
  }
  if (!watch.controller.client.isConnected) {
    return _error(
      'Not connected to a Flutter app. Call connect_to_app with no arguments.',
    );
  }

  try {
    final report = await watch.refreshNow();
    final failed =
        !report.analysisClean || report.results.any((result) => !result.ok);
    return CallToolResult(
      content: [TextContent(text: report.summary)],
      isError: failed ? true : null,
    );
  } on StateError catch (error) {
    return _error('$error');
  } on Object catch (error) {
    return _error('Change refresh failed: $error');
  }
}

/// Stops the change-refresh interval.
Future<CallToolResult> stopChangeRefresh(ChangeRefreshWatch watch) async {
  await watch.stop();
  return const CallToolResult(
    content: [TextContent(text: 'Change refresh stopped.')],
  );
}

CallToolResult _error(String text) =>
    CallToolResult(content: [TextContent(text: text)], isError: true);
