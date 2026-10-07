import 'dart:convert';
import 'dart:io';

import 'package:dtd/dtd.dart';
import 'package:meta/meta.dart';

/// A Dart Tooling Daemon instance discovered on this machine.
class DtdInstance {
  const DtdInstance({required this.uri, this.workspaceRoot, this.dartVersion});

  /// WebSocket URI of the DTD instance.
  final Uri uri;

  /// Workspace the DTD was started for, if reported.
  final String? workspaceRoot;

  /// Dart version reported by the DTD, if reported.
  final String? dartVersion;

  @override
  String toString() => '$uri (root: ${workspaceRoot ?? '?'})';
}

/// A running app discovered through DTD, with its connectable VM Service URI.
class DiscoveredApp {
  const DiscoveredApp({
    required this.vmServiceUri,
    this.name,
    this.workspaceRoot,
    this.dartVersion,
  });

  /// VM Service WebSocket URI, including the per-run auth code.
  final String vmServiceUri;

  /// Human-readable app name, e.g. `Flutter - Chrome`.
  final String? name;

  /// Workspace root of the DTD instance that reported this app.
  final String? workspaceRoot;

  final String? dartVersion;

  Map<String, Object?> toJson() => {
    'vmServiceUri': vmServiceUri,
    'name': name,
    'workspaceRoot': workspaceRoot,
    'dartVersion': dartVersion,
  };
}

/// Finds running Flutter/Dart apps without being handed a URI.
///
/// Uses the Dart Tooling Daemon (DTD). `flutter run` and the IDEs start a DTD
/// instance per workspace and register their app's VM Service with it, so
/// DTD already knows the auth-coded WebSocket URI that is otherwise only ever
/// printed to `flutter run`'s stdout.
///
/// This is the same mechanism the official `dart mcp_server` uses.
class VmServiceDiscovery {
  /// Runs `dart tooling-daemon --list` and parses the result.
  ///
  /// Returns an empty list when no DTD instance is running, which simply means
  /// no app was started by `flutter run` or an IDE.
  static Future<List<DtdInstance>> listDtdInstances({
    String? dartExecutable,
  }) async {
    final exe = dartExecutable ?? Platform.resolvedExecutable;

    final ProcessResult result;
    try {
      result = await Process.run(exe, [
        'tooling-daemon',
        '--list',
      ], runInShell: Platform.isWindows);
    } on ProcessException {
      return const [];
    }

    if (result.exitCode != 0) return const [];

    final stdout = (result.stdout as String?) ?? '';
    return _parseDtdList(stdout);
  }

  static List<DtdInstance> _parseDtdList(String text) {
    // Output looks like:
    //   Found 1 Dart Tooling Daemon instance(s):
    //     WS URI:         ws://127.0.0.1:50167/d9drxIoGnWc=
    //     Workspace Root: C:\path\to\project
    //     Dart Version:   3.13.2 (stable) ...
    //     PID:            19236
    final uriRe = RegExp(r'WS URI:\s+(ws://\S+)');
    final rootRe = RegExp(r'Workspace Root:\s+(.+)');
    final verRe = RegExp(r'Dart Version:\s+(.+)');

    final instances = <DtdInstance>[];
    final uriMatches = uriRe.allMatches(text).toList();
    for (var i = 0; i < uriMatches.length; i++) {
      final uri = Uri.parse(uriMatches[i].group(1)!);
      // Attribute each block's root/version by slicing between matches.
      final start = uriMatches[i].start;
      final end = i + 1 < uriMatches.length
          ? uriMatches[i + 1].start
          : text.length;
      final block = text.substring(start, end);
      instances.add(
        DtdInstance(
          uri: uri,
          workspaceRoot: _firstMatch(rootRe, block)?.trim(),
          dartVersion: _firstMatch(verRe, block)?.trim(),
        ),
      );
    }
    return instances;
  }

  static String? _firstMatch(RegExp re, String text) =>
      re.firstMatch(text)?.group(1);

  /// A null workspace root is treated as a match so discovery is not silently
  /// narrowed by missing metadata.
  static bool _matches(String? workspaceRoot, String filter) =>
      workspaceRoot == null ||
      workspaceRoot.toLowerCase().contains(filter.toLowerCase());

  /// Connects to every local DTD instance and collects the VM Service URIs of
  /// the apps they manage.
  ///
  /// [workspaceFilter] optionally narrows results by workspace root, which is
  /// useful when several apps are running.
  static Future<List<DiscoveredApp>> discoverApps({
    String? workspaceFilter,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final instances = await listDtdInstances();
    final apps = <DiscoveredApp>[];

    for (final instance in instances) {
      if (workspaceFilter != null &&
          !_matches(instance.workspaceRoot, workspaceFilter)) {
        continue;
      }

      DartToolingDaemon? dtd;
      try {
        dtd = await DartToolingDaemon.connect(instance.uri).timeout(timeout);
        final response = await dtd.getVmServices().timeout(timeout);
        for (final info in response.vmServicesInfos) {
          apps.add(
            DiscoveredApp(
              // `exposedUri` is the one to dial from this machine.
              vmServiceUri: info.exposedUri ?? info.uri,
              name: info.name,
              workspaceRoot: instance.workspaceRoot,
              dartVersion: instance.dartVersion,
            ),
          );
        }
      } on Object {
        // A DTD we cannot reach (stale entry, or shutting down) is skipped
        // rather than failing the whole discovery.
      } finally {
        try {
          await dtd?.close();
        } on Object {
          // Best effort.
        }
      }
    }
    return apps;
  }

  /// Renders discovered apps for an MCP tool response.
  static String describe(List<DiscoveredApp> apps) {
    if (apps.isEmpty) {
      return 'No running Flutter/Dart apps found.\n\n'
          'Discovery uses the Dart Tooling Daemon, which is started by '
          '`flutter run` and the IDEs. Make sure the app is running in debug '
          'mode, then retry. If the app was started some other way, pass its '
          '`ws://127.0.0.1:PORT/AUTHCODE=/ws` URI to connect_to_app directly.';
    }
    final buffer = StringBuffer('Found ${apps.length} running app(s):\n');
    for (final app in apps) {
      buffer.writeln('\n- ${app.name ?? 'unnamed app'}');
      buffer.writeln('  vmServiceUri : ${app.vmServiceUri}');
      if (app.workspaceRoot != null) {
        buffer.writeln('  workspace    : ${app.workspaceRoot}');
      }
      if (app.dartVersion != null) {
        buffer.writeln('  dart         : ${app.dartVersion}');
      }
    }
    buffer.write('\nPass one of the vmServiceUri values to connect_to_app.');
    return buffer.toString();
  }

  /// Exposed for tests: parse without touching the filesystem.
  @visibleForTesting
  static List<DtdInstance> parseForTest(String text) => _parseDtdList(text);

  /// Convenience for JSON consumers.
  static String toJsonText(List<DiscoveredApp> apps) =>
      const JsonEncoder.withIndent(
        '  ',
      ).convert(apps.map((a) => a.toJson()).toList());
}
