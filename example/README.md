# Example: drive a running Flutter app

[Promo video](https://github.com/RajKavadia/flutter_ai_whisper/raw/main/flutter-ai-whisper-promo.mp4)
— MCP connect, state injection, and navigation (also on the
[package README](../README.md#demo)).

This is the walkthrough pub.dev shows on the package's Example tab. The app
below is the smallest one that still exercises every tool: a top-level holder,
a named route, and a private field on a `State` object.

The server does not import Flutter. You run *your* app with `flutter run`, then
the agent talks to it.

## 1. App

`lib/main.dart`:

```dart
import 'package:flutter/material.dart';

final CounterCubit counterCubit = CounterCubit();

void main() => runApp(const MyApp());

class CounterCubit {
  int _count = 0;
  int get count => _count;
  void setValue(int v) => _count = v;
  void increment() => _count++;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      routes: {
        '/': (_) => const HomePage(),
        '/profile': (_) => const Scaffold(body: Center(child: Text('Profile'))),
      },
      initialRoute: '/',
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _localCounter = 0;
  static int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('count: ${counterCubit.count}'),
            Text('local: $_localCounter'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                counterCubit.increment();
                setState(() => _localCounter++);
              },
              child: const Text('increment'),
            ),
          ],
        ),
      ),
    );
  }
}
```

`counterCubit` is `final`. The agent calls `setValue`. It cannot assign a new
cubit. `_localCounter` is private to this library, so the agent must pass
`libraryUri`.

`Text('count: ...')` does not listen to the cubit. A write that is not inside
`setState` changes the field and leaves the old number on screen.

## 2. Run

```console
flutter run
```

Leave that process running. Do not copy the debug-service URI out of the log.
`connect_to_app` discovers it.

## 3. Register the server

User or project MCP config, after `dart pub global activate flutter_ai_whisper`:

```json
{
  "mcpServers": {
    "flutter-ai-whisper": {
      "command": "flutter_ai_whisper"
    }
  }
}
```

## 4. Calls

Connect, with no URI:

```json
{ "name": "connect_to_app", "arguments": {} }
```

On Flutter Web, name the values. Heap search is unavailable there:

```json
{
  "name": "list_active_state_holders",
  "arguments": { "expressions": ["counterCubit.count"] }
}
```

Set the cubit and rebuild the page that displays it. Use the library that
declares `_HomePageState` (here, the root library `package:your_app/main.dart`):

```json
{
  "name": "inject_state_variable",
  "arguments": {
    "libraryUri": "package:your_app/main.dart",
    "expression": "(() { Element? t; void walk(Element e) { if (t != null) return; if (e.widget is HomePage) { t = e; return; } e.visitChildren(walk); } walk(WidgetsBinding.instance.rootElement!); if (t == null) return 'not-found'; final s = (t as StatefulElement).state as _HomePageState; s.setState(() { counterCubit.setValue(42); s._localCounter = 12; }); return 'ok'; })()"
  }
}
```

Push a route that `MaterialApp.routes` already contains:

```json
{
  "name": "trigger_route_navigation",
  "arguments": { "routePath": "/profile" }
}
```

Read the labels after the next frame:

```json
{
  "name": "inject_state_variable",
  "arguments": {
    "expression": "(() { final texts = <String>[]; void walk(Element e) { final w = e.widget; if (w is Text && (w.data ?? '').trim().isNotEmpty) texts.add(w.data!); e.visitChildren(walk); } walk(WidgetsBinding.instance.rootElement!); return texts.join(' | '); })()"
  }
}
```

On the home route that string includes `count: 42` and `local: 12`. On
`/profile` it includes `Profile`, and the home `State` does not repaint until
you pop back.

## 5. What to expect

- A getter with no setter cannot be assigned. Call `setValue` or `increment`.
- GetX `Rx`, Riverpod, Bloc, and `ChangeNotifier` repaint on their own. This
  cubit does not.
- `setState` is deferred while the page sits under another route.
- Several apps running at once: pass `workspaceFilter` to `connect_to_app`.

Riverpod, Bloc, and GetX recipes are in the package [README](../README.md).
