import 'package:flutter_ai_whisper/state_discoverer.dart';
import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:mcp_server/mcp_server.dart';

Future<CallToolResult> listActiveStateHolders(
  VmBridge bridge,
  Map<String, dynamic> args,
) async {
  try {
    final discoverer = StateDiscoverer(bridge);

    // `expressions` lets the agent name holders it found in the app's source.
    // This is required on Flutter Web, where enumeration is not possible.
    final expressions = (args['expressions'] as List?)?.cast<String>();

    final results = <Map<String, dynamic>>[];

    if (expressions != null && expressions.isNotEmpty) {
      results.addAll(
        await discoverer.probeExpressions(
          expressions,
          libraryUri: args['libraryUri'] as String?,
        ),
      );
    }

    results.addAll(await discoverer.discoverStateHolders());

    final filter = args['filter'] as String?;
    final filtered =
        filter == null || filter.isEmpty
            ? results
            : results
                .where(
                  (h) => '${h['name'] ?? h['expression'] ?? ''}'
                      .toLowerCase()
                      .contains(filter.toLowerCase()),
                )
                .toList();

    if (filtered.isEmpty) {
      final hint =
          bridge.supportsClassList
              ? 'No state holders matched. Try a `filter`, or pass `expressions` '
                  'such as ["counterCubit.count"].'
              : 'Automatic enumeration is unavailable on Flutter Web, so nothing '
                  'was found. Read the app source for top-level state objects '
                  'and pass `expressions`, e.g. '
                  '["counterCubit.count", "authNotifier.isLoggedIn"].';
      return CallToolResult(content: [TextContent(text: hint)]);
    }

    final json = StringBuffer();
    for (final h in filtered) {
      if (h.containsKey('expression')) {
        json.writeln('${h['expression']}  =>  ${h['value'] ?? h['error']}');
      } else {
        json.writeln(
          '${h['name']}  [${h['source']}]  '
          '${h['value'] == null ? '' : '=> ${h['value']}'}',
        );
      }
    }

    final footer =
        bridge.supportsClassList
            ? ''
            : '\n\n(note: Flutter Web — supply `expressions` to inspect named state)';

    return CallToolResult(content: [TextContent(text: '$json$footer')]);
  } catch (e) {
    return CallToolResult(
      content: [TextContent(text: 'Error listing state holders: $e')],
      isError: true,
    );
  }
}
