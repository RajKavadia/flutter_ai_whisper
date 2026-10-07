# Example: driving a Flutter app from an MCP client

A minimal Flutter app with three top-level state objects, then the MCP calls
that read and mutate them.

The app is intentionally simple — the point is to show what the tools can reach
without any instrumentation.

## 1. The app

```dart
// lib/main.dart
import 'package:flutter/material.dart';

final CounterCubit counterCubit = CounterCubit();

void main() => runApp(const MyApp());

class CounterCubit {
  int _count = 0;
  int get count => _count;
  void setValue(int v) => _count = v; // setter for the agent to call
  void increment() => _count++;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      initialRoute: '/',
      routes: {
        '/': (_) => const HomePage(),
        '/profile': (_) => const Scaffold(body: Text('Profile')),
      },
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('count: ${counterCubit.count}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: counterCubit.increment,
              child: const Text('increment'),
            ),
          ],
        ),
      ),
    );
  }
}
```

Note the explicit `setValue`. Top-level objects are `final`, so the agent cannot
assign `counterCubit` itself — it calls a method instead.

## 2. Run it

```console
flutter run -d chrome
```

Copy the line the agent needs:

```text
This app is linked to the debug service: ws://127.0.0.1:56660/RsqcVzTFmw0=/ws
```

## 3. Register the MCP server

`.mcp.json`:

```json
{
  "mcpServers": {
    "flutter-ai-whisper": {
      "command": "dart",
      "args": ["run", "/abs/path/to/flutter_ai_whisper/bin/main.dart"]
    }
  }
}
```

## 4. Drive it

Connect:

```json
{ "name": "connect_to_app",
  "arguments": { "vmUri": "ws://127.0.0.1:56660/RsqcVzTFmw0=/ws" } }
```

Read state (named explicitly — required on Flutter Web):

```json
{ "name": "list_active_state_holders",
  "arguments": { "expressions": ["counterCubit.count"] } }
```

Mutate:

```json
{ "name": "inject_state_variable",
  "arguments": { "expression": "counterCubit.setValue(42)" } }
```

Navigate:

```json
{ "name": "trigger_route_navigation",
  "arguments": { "routePath": "/profile" } }
```

The app UI updates live between calls.

## 5. Private widget state

`evaluate` targets the app's root library by default, where `_`-prefixed names
are invisible. Pass `libraryUri` to evaluate inside the declaring library:

```json
{ "name": "inject_state_variable",
  "arguments": {
    "libraryUri": "package:my_app/pages/home_page.dart",
    "expression": "(() { Element? t; void walk(Element e) { if (t != null) return; if (e.widget is HomePage) { t = e; return; } e.visitChildren(walk); } walk(WidgetsBinding.instance.rootElement!); final s = (t as StatefulElement).state as _HomePageState; s.setState(() { s._localCounter = 12; }); return 'ok'; })()"
  }
}
```

Note the `walk` helper: it locates the `State` object by matching the widget
type, which works whatever the widget is named.

Two rules that save a wasted attempt:

- **You can only assign what has a setter.** If the class only exposes
  `increment()`, call it in a loop instead of assigning.
- **Plain writes do not update the screen.** Wrap them in `setState`. GetX `Rx`,
  Riverpod, Bloc and `ChangeNotifier` notify themselves and need nothing extra.

`setState` rebuilds on the next frame, so poll briefly before checking that the
view changed. It is also deferred entirely while the page is offstage under
another route — pop back to it first, or the write will land without repainting.

## Next steps

See `README.md` for Riverpod, Bloc and GetX recipes, the platform support
matrix, and troubleshooting.