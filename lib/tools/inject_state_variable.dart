import 'package:flutter_ai_whisper/vm_bridge.dart';
import 'package:mcp_server/mcp_server.dart';
import 'package:vm_service/vm_service.dart';

/// Applies a state mutation by evaluating Dart code inside the app isolate.
///
/// Prefer `expression` — a single statement or expression, e.g.
/// `counterCubit.setValue(42)` or `authNotifier.login('tester', 'a@b.c')`.
///
/// `targetExpression` + `newValueExpression` builds `target = value`, which
/// only works for assignable (non-final) targets.
Future<CallToolResult> injectStateVariable(
  VmBridge bridge,
  Map<String, dynamic> args,
) async {
  try {
    final expression = args['expression'] as String?;
    final target = args['targetExpression'] as String?;
    final newValue = args['newValueExpression'] as String?;

    if (expression == null && (target == null || newValue == null)) {
      return CallToolResult(
        content: const [
          TextContent(
            text:
                'Provide either `expression`, or both `targetExpression` '
                'and `newValueExpression`.',
          ),
        ],
        isError: true,
      );
    }

    final code = expression ?? '$target = $newValue';
    final libraryUri = args['libraryUri'] as String?;

    final result = await bridge.evaluate(code, libraryUri: libraryUri);

    if (result is ErrorRef) {
      return CallToolResult(
        content: [
          TextContent(
            text:
                'Injection failed.\n'
                'Expression: $code'
                '${libraryUri == null ? "" : "\nLibrary: $libraryUri"}\n'
                'Error: ${result.message ?? "unknown"}',
          ),
        ],
        isError: true,
      );
    }

    final ref = result as InstanceRef;
    return CallToolResult(
      content: [
        TextContent(
          text: 'Applied `$code`\nReturned: ${ref.valueAsString ?? "<void>"}',
        ),
      ],
    );
  } catch (e) {
    return CallToolResult(
      content: [TextContent(text: 'Error injecting state: $e')],
      isError: true,
    );
  }
}
