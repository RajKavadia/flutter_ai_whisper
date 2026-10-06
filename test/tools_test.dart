import 'package:flutter_ai_whisper/tools/inject_state_variable.dart';
import 'package:flutter_ai_whisper/tools/list_active_state_holders.dart';
import 'package:flutter_ai_whisper/tools/trigger_route_navigation.dart';
import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:test/test.dart';

/// Concatenates the text content of a tool result.
String textOf(CallToolResult result) => result.content
    .map((c) => c is TextContent ? c.text : c.toString())
    .join('\n');

void main() {
  // A disconnected bridge, so we exercise argument validation and the
  // disconnected code paths without needing a live Flutter app.
  final bridge = VmBridge();

  group('tools when not connected', () {
    test('list_active_state_holders reports disconnection', () async {
      final result = await listActiveStateHolders(bridge, const {});
      expect(result.isError, isTrue);
      expect(textOf(result), contains('Not connected'));
    });

    test('inject_state_variable reports disconnection', () async {
      final result = await injectStateVariable(bridge, {'expression': 'x = 1'});
      expect(result.isError, isTrue);
      expect(textOf(result), contains('Not connected'));
    });

    test('trigger_route_navigation reports disconnection', () async {
      final result = await triggerRouteNavigation(bridge, {
        'routePath': '/profile',
      });
      expect(result.isError, isTrue);
      expect(textOf(result), contains('Not connected'));
    });
  });

  group('argument validation', () {
    test('inject_state_variable requires expression or target+value', () async {
      final result = await injectStateVariable(bridge, const {});
      expect(result.isError, isTrue);
      expect(textOf(result), contains('Provide either'));
    });

    test('inject_state_variable accepts expression only', () async {
      // Still disconnected, but it must get past argument validation and fail
      // on connection instead.
      final result = await injectStateVariable(bridge, {'expression': 'a.b()'});
      expect(textOf(result), isNot(contains('Provide either')));
    });

    test('trigger_route_navigation requires routePath', () async {
      final result = await triggerRouteNavigation(bridge, const {});
      expect(result.isError, isTrue);
      expect(textOf(result), contains('routePath'));
    });
  });

  group('VmBridge', () {
    // Each test gets a fresh bridge: the tools above share one, and connect is
    // never called here, but isolation keeps the assertions honest.
    test('starts disconnected', () {
      final fresh = VmBridge();
      expect(fresh.isConnected, isFalse);
    });

    test('throws a helpful error when used while disconnected', () {
      final fresh = VmBridge();
      expect(
        () => fresh.evaluate('1 + 1'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('connect_to_app'), contains('AUTHCODE')),
          ),
        ),
      );
    });
  });
}
