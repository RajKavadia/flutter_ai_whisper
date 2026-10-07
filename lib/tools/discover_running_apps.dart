import 'package:flutter_ai_whisper/discovery.dart';
import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:mcp_server/mcp_server.dart';

/// Lists running Flutter/Dart apps and their VM Service URIs.
///
/// Uses the Dart Tooling Daemon, so the agent never has to read or copy the
/// URI that `flutter run` prints to its console.
Future<CallToolResult> discoverRunningApps(
  VmBridge bridge,
  Map<String, dynamic> args,
) async {
  try {
    final workspace = args['workspaceFilter'] as String?;

    final apps = await VmServiceDiscovery.discoverApps(
      workspaceFilter: workspace,
    );

    return CallToolResult(
      content: [TextContent(text: VmServiceDiscovery.describe(apps))],
    );
  } on Object catch (e) {
    return CallToolResult(
      content: [
        TextContent(
          text:
              'Discovery failed: $e\n\n'
              'Falling back: pass the URI from the `flutter run` console '
              '(the "This app is linked to the debug service: ws://..." line) '
              'to connect_to_app.',
        ),
      ],
      isError: true,
    );
  }
}
