import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:vm_service/vm_service.dart';

/// Dart snippet that walks the element tree to find a `BuildContext` that sits
/// below a `Navigator`, then pushes a named route.
///
/// `WidgetsBinding.instance.rootElement` sits *above* the Navigator, so
/// `Navigator.of(rootElement)` throws. Walking down to the first descendant
/// that resolves a Navigator works and needs no app-side instrumentation.
const _pushViaTreeWalk = r'''(() {
  BuildContext? found;
  void walk(Element e) {
    if (found != null) return;
    try { Navigator.of(e, rootNavigator: true); found = e; return; } catch (_) {}
    e.visitChildren(walk);
  }
  try { walk(WidgetsBinding.instance.rootElement!); } catch (err) {
    return 'walk-failed: ' + err.toString();
  }
  if (found == null) return 'no-navigator-found';
  try {
    Navigator.of(found!, rootNavigator: true).pushNamed(ROUTE);
    return 'ok';
  } catch (err) {
    return 'push-failed: ' + err.toString();
  }
})()''';

/// Fallback for apps that expose a global navigator key.
const _pushViaNavigatorKey = r'''(() {
  final state = navigatorKey.currentState;
  if (state == null) return 'no-navigatorKey-state';
  try { state.pushNamed(ROUTE); return 'ok'; } catch (err) {
    return 'push-failed: ' + err.toString();
  }
})()''';

Future<CallToolResult> triggerRouteNavigation(
  VmBridge bridge,
  Map<String, dynamic> args,
) async {
  try {
    final routePath = args['routePath'] as String?;
    if (routePath == null || routePath.isEmpty) {
      return CallToolResult(
        content: const [TextContent(text: '`routePath` is required.')],
        isError: true,
      );
    }

    final quoted = "'${routePath.replaceAll("'", r"\'")}'";

    var lastFailure = 'unknown';
    for (final template in [_pushViaTreeWalk, _pushViaNavigatorKey]) {
      final response = await bridge.evaluate(
        template.replaceAll('ROUTE', quoted),
      );

      final out =
          response is ErrorRef
              ? 'eval-error: ${response.message ?? "unknown"}'
              : (response as InstanceRef).valueAsString ?? '';

      if (out == 'ok') {
        return CallToolResult(
          content: [TextContent(text: 'Pushed route "$routePath".')],
        );
      }

      // A push failure means we reached a Navigator but it rejected the route.
      // Trying the other strategy would only mask the useful error, so report
      // this one and stop.
      if (out.startsWith('push-failed')) {
        return CallToolResult(
          content: [
            TextContent(
              text:
                  'Could not push route "$routePath". The Navigator '
                  'rejected it — the route is most likely not registered in '
                  'the app\'s routes table.\n\n$out',
            ),
          ],
          isError: true,
        );
      }

      // No navigator reachable this way; try the next strategy.
      lastFailure = out;
    }

    return CallToolResult(
      content: [
        TextContent(text: 'Could not navigate to "$routePath".\n$lastFailure'),
      ],
      isError: true,
    );
  } catch (e) {
    return CallToolResult(
      content: [TextContent(text: 'Error navigating: $e')],
      isError: true,
    );
  }
}
