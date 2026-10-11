# flutter_ai_whisper

An [MCP](https://modelcontextprotocol.io) server that lets an AI coding agent
**read, change, and navigate a running Flutter app** over the Dart VM Service.
No Flutter dependency, no test instrumentation, and no edits to the app.

Start the app with `flutter run`. Ask the agent to connect. The counter, the
route, and the widgets update live.

[![pub package](https://img.shields.io/pub/v/flutter_ai_whisper.svg)](https://pub.dev/packages/flutter_ai_whisper)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Demo

Developer promo: connect, read state, inject (GetX, Bloc, Riverpod), and navigate
over MCP — no sample app walkthrough.

<video src="flutter-ai-whisper-promo.mp4" controls width="100%">
  <a href="https://github.com/RajKavadia/flutter_ai_whisper/raw/main/flutter-ai-whisper-promo.mp4">Watch the demo (MP4)</a>
</video>

On [pub.dev](https://pub.dev/packages/flutter_ai_whisper) the player may not
embed; [open the video on GitHub](https://github.com/RajKavadia/flutter_ai_whisper/raw/main/flutter-ai-whisper-promo.mp4)
instead (~5 MB).

```
MCP client ──stdio──> flutter_ai_whisper ──WebSocket──> Dart VM Service ──> app
```

## What it is for

Widget tests and integration tests drive the app through taps, or they require
you to add keys and test hooks first. This server uses the debug protocol the
Dart VM already exposes, so an agent can:

- list the apps that are running and connect without copying a URI
- read live state (cubits, notifiers, blocs, GetX controllers, plain objects)
- change that state by evaluating real Dart inside the app
- push a named route, with no `navigatorKey` added to the app

It is a **developer tool**, not a Flutter plugin. You do not add it to the
app's `pubspec.yaml`. You register it with the agent that is editing the app.

## Requirements

- Dart SDK `^3.8.0` for the server.
- A Flutter app running in **debug mode**. `flutter run` and
  `flutter run -d chrome` both qualify.
- Profile builds, release builds, and obfuscated builds
  (`--obfuscate --split-debug-info`) do not work. They hide the VM Service or
  the class names discovery needs.

## Install

```console
dart pub global activate flutter_ai_whisper
```

Confirm the executable is on your PATH:

```console
flutter_ai_whisper --help
```

The server speaks MCP on `stdio`. An agent launches it. Running it in a
terminal by itself produces no interactive session.

From a clone, skip activation and point the client at the entrypoint:

```console
dart run /absolute/path/to/flutter_ai_whisper/bin/main.dart
```

## Register it

### Cursor

`.cursor/mcp.json` in the app you are working on (or your user MCP config):

```json
{
  "mcpServers": {
    "flutter-ai-whisper": {
      "command": "flutter_ai_whisper"
    }
  }
}
```

### Claude Desktop

`claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "flutter-ai-whisper": {
      "command": "flutter_ai_whisper"
    }
  }
}
```

### VS Code

`.vscode/mcp.json`:

```json
{
  "servers": {
    "flutter-ai-whisper": {
      "type": "stdio",
      "command": "flutter_ai_whisper"
    }
  }
}
```

### Claude Code, or a project-local checkout

`.mcp.json`:

```json
{
  "mcpServers": {
    "flutter-ai-whisper": {
      "command": "dart",
      "args": ["run", "/absolute/path/to/flutter_ai_whisper/bin/main.dart"]
    }
  }
}
```

### opencode

`~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "flutter-ai-whisper": {
      "type": "local",
      "command": ["flutter_ai_whisper"],
      "enabled": true
    }
  }
}
```

## Quick start

1. Run the app in debug mode.

   ```console
   flutter run
   ```

2. In the agent chat, paste:

   > Connect to the running Flutter app. Read the counter, set it to 42, and
   > tell me what the screen shows.

3. The agent calls `connect_to_app` with **no arguments**. Discovery goes
   through the Dart Tooling Daemon, the same way the official Dart MCP server
   finds a debug session.

Do not paste the `ws://127.0.0.1:PORT/AUTH=/ws` line from the `flutter run`
console. That path is a per-run auth code. It is stale the moment the app
restarts. Pass `vmUri` only when discovery finds nothing, which happens when
the app was not started by `flutter run` or an IDE.

The address printed as the app URL (`http://localhost:52362/`) is the static
web server. Connecting to it fails with `WebSocketException: HTTP status code:
200`.

## Tools

| Tool | What the agent uses it for |
| --- | --- |
| `discover_running_apps` | List debug sessions and their VM Service URIs. |
| `connect_to_app` | Connect. Safe with no arguments. |
| `list_active_state_holders` | Report live state, or probe expressions you name. |
| `inject_state_variable` | Evaluate Dart in the app to change state. |
| `trigger_route_navigation` | Push a named route that the app already registered. |

### `discover_running_apps`

| Parameter | Required | Description |
| --- | --- | --- |
| `workspaceFilter` | no | Substring of the workspace root, for example `sample_app`, when several apps are running. |

### `connect_to_app`

| Parameter | Required | Description |
| --- | --- | --- |
| `vmUri` | no | WebSocket URI of one specific app. Omit it to auto-discover. |
| `workspaceFilter` | no | Substring of the workspace root used during auto-discovery. |

The result also reports which VM features this target implements. Flutter Web
cannot enumerate the heap. Native debug builds can.

### `list_active_state_holders`

| Parameter | Required | Description |
| --- | --- | --- |
| `filter` | no | Case-insensitive substring match on the holder name. |
| `expressions` | no | Dart expressions to evaluate, such as `counterCubit.count`. Required on Flutter Web. |
| `libraryUri` | no | Library to evaluate in. Required for private names. |

### `inject_state_variable`

| Parameter | Required | Description |
| --- | --- | --- |
| `expression` | one of | One Dart expression, such as `counterCubit.setValue(42)`. |
| `targetExpression` | with `newValueExpression` | Left-hand side of an assignment. |
| `newValueExpression` | with `targetExpression` | Right-hand side of an assignment. |
| `libraryUri` | no | Library to evaluate in. |

Prefer `expression`. The pair `targetExpression` / `newValueExpression` builds
`target = value`, and that fails on `final` globals with `Setter not found`.

`evaluate` accepts one expression, not a list of statements. Wrap several
statements in an immediately invoked function:

```dart
(() { obj.a = 1; obj.b = 2; return 'done'; })()
```

### `trigger_route_navigation`

| Parameter | Required | Description |
| --- | --- | --- |
| `routePath` | yes | Named route, for example `/profile`. |

The tool walks the element tree until it finds a context under a `Navigator`.
`Navigator.of` on `rootElement` throws, because that element sits above the
navigator. The route must already exist in the app's `routes` table (or an
equivalent `onGenerateRoute`). The tool cannot invent a page that was never
registered.

## Platform support

| Capability | Android, iOS, desktop | Flutter Web |
| --- | --- | --- |
| `evaluate` | yes | yes |
| `getClassList` and `getInstances` | yes | no |
| Root-library variables | yes | empty |
| `dart:mirrors` | yes | no |
| Named-route navigation | yes | yes |

On Flutter Web, `list_active_state_holders` cannot search the heap. Read the
app source, then probe the names:

```json
{
  "name": "list_active_state_holders",
  "arguments": {
    "expressions": ["counterCubit.count", "authNotifier.isLoggedIn"]
  }
}
```

On native targets, class-name discovery is a heuristic. It looks for names
containing `Bloc`, `Cubit`, `Notifier`, `Provider`, `Controller`, `Store`,
`State`, `Manager`, `Model`, or `ViewModel`. Holders outside that list need
`expressions`.

## Rules that save a failed call

**One expression, one library.** Visibility follows that library's imports and
exports. The wrong library yields `CompilationError: Undefined name` even when
the object exists. A barrel file that exports the holder is often why the root
library can see it.

**Private names need `libraryUri`.** `_field`, `_HomePageState`, and
`_increment` all fail to compile unless evaluation happens in the library that
declares them:

```json
{
  "libraryUri": "package:my_app/pages/home_page.dart",
  "expression": "_localCounter.toString()"
}
```

When the URI does not match, the error lists the app's libraries.

**You can only call what the object exposes.** A getter without a setter cannot
be assigned. Call the method the class already has:

```dart
s.setState(() { for (var i = 0; i < 12; i++) { appState.incrementCounter(); } });
```

**Changing a field does not repaint the screen.** GetX `Rx`, Riverpod, Bloc,
`ValueNotifier`, and `ChangeNotifier` notify themselves. Plain objects and
private `State` fields need `setState` around the write. `setState` runs on the
next frame. If another route is covering that page, the rebuild waits until the
page is visible again. Pop back first, then read the `Text` widgets in the tree
to confirm the screen changed. Re-reading the variable only proves the object
changed.

## Recipes

### Plain object

```json
{
  "name": "inject_state_variable",
  "arguments": { "expression": "counterCubit.setValue(42)" }
}
```

If the widget does not listen to that object, wrap the call in `setState` on
the `State` that builds the text. See the example below.

### Riverpod

`State` on a notifier is `@protected`, so assign through a method the notifier
exposes, reached from a `ProviderContainer` the agent can name:

```json
{
  "name": "inject_state_variable",
  "arguments": {
    "expression": "container.read(counterProvider.notifier).setValue(77)"
  }
}
```

Riverpod notifies listeners itself.

### Bloc

There is no global registry. Keep a handle when the provider is created, and
dispatch an event:

```dart
late final CounterBloc activeBloc;
// ...
BlocProvider(create: (_) => activeBloc = CounterBloc()),
```

```json
{
  "name": "inject_state_variable",
  "arguments": { "expression": "activeBloc.add(const CounterSet(55))" }
}
```

`BlocProvider(create:)` is lazy. Open that route before the first read, or the
handle is still null.

### GetX

```json
{
  "name": "inject_state_variable",
  "arguments": { "expression": "Get.find<CounterController>().count.value = 9" }
}
```

GetX navigation does not need a `BuildContext`:

```json
{
  "name": "inject_state_variable",
  "arguments": { "expression": "Get.toNamed('/profile')" }
}
```

### Private widget state

Match the widget in the element tree, cast its `State`, and write inside
`setState`. Pass `libraryUri` of the file that declares `_HomePageState`.

```dart
(() {
  Element? t;
  void walk(Element e) {
    if (t != null) return;
    if (e.widget is HomePage) { t = e; return; }
    e.visitChildren(walk);
  }
  walk(WidgetsBinding.instance.rootElement!);
  if (t == null) return 'not-found';
  final s = (t as StatefulElement).state as _HomePageState;
  s.setState(() { s._localCounter = 12; });
  return 'ok';
})()
```

### Confirm the screen, not the variable

```dart
(() {
  final texts = <String>[];
  void walk(Element e) {
    final w = e.widget;
    if (w is Text && (w.data ?? '').trim().isNotEmpty) texts.add(w.data!);
    e.visitChildren(walk);
  }
  walk(WidgetsBinding.instance.rootElement!);
  return texts.join(' | ');
})()
```

## Prompts that work

After the server is registered and the app is running:

> Connect to the running app and list the state you can see. On web, read the
> source and probe the top-level holders by name.

> Set the cart total to 19.99 by calling the method the store already exposes.
> If the page does not rebuild by itself, do it inside setState, then read the
> Text widgets to confirm.

> Open the `/profile` route, then come back and tell me whether the home page
> rebuilt.

A worked counter app, including the private-state case, is in
[`example/README.md`](example/README.md).

## Troubleshooting

| What you see | What to do |
| --- | --- |
| `Not connected to a Flutter app` | Call `connect_to_app` with no arguments. |
| `WebSocketException` and HTTP 200 | You used the app URL. Use discovery, or the `debug service` WebSocket. |
| HTTP 403 | The auth code is missing or from a previous run. Reconnect with no URI. |
| `Setter not found` | The target is `final`. Call a method via `expression`. |
| `Undefined name '_x'` | Pass `libraryUri` of the declaring library. |
| Empty state list on web | Pass `expressions`. Heap enumeration does not exist on web. |
| Navigation says the route was rejected | Register that name in the app's route table. |
| Variable changed, screen did not | Wrap the write in `setState`, or pop back to that route first. |

Tool failures come back as `isError: true`. They do not drop the MCP session.
`isError` is nullable: `null` means success.

## Security

The server evaluates arbitrary Dart inside the app process, with that app's
privileges. Use it on a debug build you control, on localhost.

Do not point it at a production build, a release build, or an app you do not
trust. Do not expose the VM Service port beyond your machine. Anyone who can
open that socket can read and overwrite runtime state.

## Development

```console
dart pub get
dart analyze
dart test
```

Agent-facing rules (connection, privacy, rebuilds, state-management recipes)
live in [`AGENTS.md`](AGENTS.md). [`llms.txt`](llms.txt) is the same guide for
other LLM tooling.

## License

MIT. See [LICENSE](LICENSE).
