import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:mcp_server/mcp_server.dart';

/// Connects the server to a running Flutter app's VM Service.
///
/// Required before any other tool when the app was started with `flutter run`,
/// because the printed WebSocket URI contains a per-run auth code
/// (e.g. `ws://127.0.0.1:56660/RsqcVzTFmw0=/ws`).
Future<CallToolResult> connectToApp(
  VmBridge bridge,
  Map<String, dynamic> args,
) async {
  final uri = args['vmUri'] as String?;
  if (uri == null || uri.isEmpty) {
    return CallToolResult(
      content: const [
        TextContent(
          text:
              '`vmUri` is required, e.g. '
              '"ws://127.0.0.1:56660/RsqcVzTFmw0=/ws". Copy it from the line '
              '"This app is linked to the debug service: ..." printed by '
              '`flutter run`.',
        ),
      ],
      isError: true,
    );
  }

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
