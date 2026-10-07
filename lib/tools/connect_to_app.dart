import 'package:flutter_ai_whisper/discovery.dart';
import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:mcp_server/mcp_server.dart';

/// Concatenates the text content of a tool result.
String textOf(CallToolResult result) => result.content
    .map((c) => c is TextContent ? c.text : c.toString())
    .join('\n');

/// Connects the server to a running Flutter app's VM Service.
///
/// [args] may contain `vmUri`. When omitted — or when the supplied URI fails to
/// connect — the tool falls back to discovering running apps through the Dart
/// Tooling Daemon, so the agent does not have to read `flutter run` output.
Future<CallToolResult> connectToApp(
  VmBridge bridge,
  Map<String, dynamic> args,
) async {
  final uri = args['vmUri'] as String?;
  final failures = <String>[];

  if (uri != null && uri.isNotEmpty) {
    final result = await _tryConnect(bridge, uri);
    // `isError` is nullable: null means success.
    if (result.isError != true) return result;
    failures.add(textOf(result).split('\n').first);
  }

  try {
    final apps = await VmServiceDiscovery.discoverApps(
      workspaceFilter: args['workspaceFilter'] as String?,
    );

    if (apps.isEmpty) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Could not connect.\n\n'
                '${failures.isEmpty ? '' : '${failures.join("\n")}\n\n'}'
                'No running apps were found via the Dart Tooling Daemon.\n\n'
                'Make sure the app is running in debug mode with `flutter run`, '
                'then retry, or pass the ws:// URI printed by `flutter run`.',
          ),
        ],
        isError: true,
      );
    }

    for (final app in apps) {
      final result = await _tryConnect(bridge, app.vmServiceUri);
      if (result.isError != true) {
        final origin = [
          'discovered automatically via DTD',
          if (app.name != null) app.name!,
          if (app.workspaceRoot != null) app.workspaceRoot!,
        ].join(' — ');
        return CallToolResult(
          content: [TextContent(text: '${textOf(result)}\n($origin)')],
        );
      }
      failures.add('${app.name ?? app.vmServiceUri}: connection failed');
    }
  } on Object catch (e) {
    failures.add('DTD discovery error: $e');
  }

  return CallToolResult(
    content: [
      TextContent(
        text: 'Could not connect to any app.\n\n${failures.join("\n")}',
      ),
    ],
    isError: true,
  );
}

Future<CallToolResult> _tryConnect(VmBridge bridge, String uri) async {
  try {
    await bridge.connect(uri);

    final root = await bridge.getRootLibrary();
    final features = <String>[
      'evaluate: yes',
      'getClassList: ${bridge.supportsClassList ? "yes" : "no (Flutter Web)"}',
      'root library: ${root.uri ?? "unknown"}',
    ];

    return CallToolResult(
      content: [TextContent(text: 'Connected to $uri\n${features.join("\n")}')],
    );
  } on Object catch (e) {
    await bridge.disconnect();
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Could not connect to $uri\n'
              '$e\n\nCheck that the app is running and the URI is current '
              '(it contains a per-run auth code).',
        ),
      ],
      isError: true,
    );
  }
}
