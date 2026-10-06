import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_ai_whisper/tools/connect_to_app.dart';
import 'package:flutter_ai_whisper/tools/inject_state_variable.dart';
import 'package:flutter_ai_whisper/tools/list_active_state_holders.dart';
import 'package:flutter_ai_whisper/tools/trigger_route_navigation.dart';
import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:mcp_server/mcp_server.dart';

Future<void> main(List<String> arguments) async {
  final parser =
      ArgParser()
        ..addOption(
          'vm-uri',
          abbr: 'u',
          help:
              'Optional VM Service WebSocket URI. If omitted, use the '
              'connect_to_app tool with the URI printed by `flutter run`.',
        )
        ..addFlag('help', abbr: 'h', negatable: false, help: 'Show usage.');

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exit(2);
  }

  if (args.flag('help')) {
    stdout.writeln(
      'flutter_ai_whisper — MCP server for Flutter runtime state.\n',
    );
    stdout.writeln(parser.usage);
    return;
  }

  final bridge = VmBridge();

  final startupUri = args.option('vm-uri');
  if (startupUri != null) {
    try {
      await bridge.connect(startupUri);
    } on Object catch (e) {
      stderr.writeln('Startup connect failed: $e');
    }
  }

  final serverResult = await McpServer.createAndStart(
    config: McpServer.simpleConfig(name: 'flutter_ai_whisper', version: '1.0.0'),
    transportConfig: TransportConfig.stdio(),
  );

  await serverResult.fold(
    (server) async {
      server.addTool(
        name: 'connect_to_app',
        description:
            'Connects to a running Flutter app via its VM Service '
            'WebSocket URI. Must be called before the other tools when the app '
            'was started with `flutter run`, because the URI contains a '
            'per-run auth code. Copy the URI from the "This app is linked to '
            'the debug service: ws://..." line in the `flutter run` output.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'vmUri': {
              'type': 'string',
              'description':
                  'Full WebSocket URI, including the auth code, '
                  'e.g. "ws://127.0.0.1:56660/RsqcVzTFmw0=/ws".',
            },
          },
          'required': ['vmUri'],
        },
        handler: (a) => connectToApp(bridge, a),
      );

      server.addTool(
        name: 'list_active_state_holders',
        description:
            'Lists active state providers, blocs, notifiers and other '
            'stateful references in the running app. On Flutter Web, automatic '
            'enumeration is impossible, so pass `expressions` (Dart '
            'expressions naming the state, e.g. ["counterCubit.count"]) — read '
            'the app source to derive them.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'filter': {
              'type': 'string',
              'description': 'Case-insensitive substring filter on names.',
            },
            'expressions': {
              'type': 'array',
              'items': {'type': 'string'},
              'description':
                  'Dart expressions to evaluate and report, e.g. '
                  '["counterCubit.count", "authNotifier.isLoggedIn"].',
            },
            'libraryUri': {
              'type': 'string',
              'description':
                  'Optional library to evaluate in, e.g. '
                  '"package:my_app/pages/home_page.dart". Required to reach '
                  'private (_underscore) members, which are only in scope in '
                  'their own library. Defaults to the app root library.',
            },
          },
          'required': [],
        },
        handler: (a) => listActiveStateHolders(bridge, a),
      );

      server.addTool(
        name: 'inject_state_variable',
        description:
            'Modifies runtime state or triggers a state update '
            'function in the running app. Prefer `expression`, a single Dart '
            'statement such as "counterCubit.setValue(42)" or '
            '"authNotifier.login(\'tester\', \'a@b.c\')". '
            'targetExpression + newValueExpression instead builds '
            '"target = value", which fails for final variables.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'expression': {
              'type': 'string',
              'description': 'Full Dart statement to evaluate.',
            },
            'targetExpression': {
              'type': 'string',
              'description':
                  'Assignable target, e.g. "settings.notifications".',
            },
            'newValueExpression': {
              'type': 'string',
              'description': 'Value expression, e.g. "false".',
            },
            'libraryUri': {
              'type': 'string',
              'description':
                  'Optional library to evaluate in, e.g. '
                  '"package:my_app/pages/home_page.dart". Required to reach '
                  'private (_underscore) members. Defaults to the app root '
                  'library.',
            },
          },
          'required': [],
        },
        handler: (a) => injectStateVariable(bridge, a),
      );

      server.addTool(
        name: 'trigger_route_navigation',
        description:
            'Triggers immediate route navigation using the active '
            'Navigator, by locating a BuildContext below it in the element '
            'tree. No app-side instrumentation required.',
        inputSchema: {
          'type': 'object',
          'properties': {
            'routePath': {
              'type': 'string',
              'description': 'Named route, e.g. "/profile" or "/settings".',
            },
          },
          'required': ['routePath'],
        },
        handler: (a) => triggerRouteNavigation(bridge, a),
      );

      server.onDisconnect.listen((_) {
        unawaited(bridge.disconnect());
        exit(0);
      });

      // Keep the isolate alive until the client disconnects.
      await Completer<void>().future;
    },
    (error) {
      stderr.writeln('Server failed: $error');
      exit(1);
    },
  );
}
