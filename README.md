# flutter_ai_whisper

An [MCP](https://modelcontextprotocol.io) server that lets an AI coding agent
inspect and mutate the runtime state of a **running** Flutter app, and drive its
navigation — over the Dart VM Service, with no code changes to the app.

It speaks MCP on `stdio` and exposes four tools. The agent can ask what state
exists, read and write it, and push routes — then see the app react live.

---

## Why

Automated Flutter UI testing usually means either instrumenting the app under
test, or driving it blind through taps. This server takes a third route: it uses
the debug protocol the Dart VM already exposes in debug builds, so it works
against an unmodified app.

## Requirements

- Dart SDK `^3.7.0` (for the server itself).
- A Flutter app running in **debug mode** with the VM Service enabled. Both
  `flutter run` and `flutter run -d chrome` qualify; profile and release builds
  do not expose it.
- Obfuscated builds (`--obfuscate --split-debug-info`) hide class names and
  break heap-based discovery.

## Install

```console
dart pub global activate flutter_ai_whisper
```

Verify:

```console
flutter_ai_whisper --help
```

The server communicates over `stdio`, so it must be launched by an MCP client.
Do not run it interactively and expect output.

## Quick start

1. **Start your app in debug mode.**

   ```console
   flutter run -d chrome
   ```

2. **Register the server with your MCP client** (below).

3. Ask the agent to connect. It needs no URI:

   > Connect to the running app, then read my counter.

   Discovery uses the Dart Tooling Daemon, so nothing has to be copied out of
   the console.

## MCP client configuration

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

### opencode

`~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "flutter-ai-whisper": {
      "type": "local",
      "command": ["dart", "run", "/absolute/path/to/flutter_ai_whisper/bin/main.dart"],
      "enabled": true
    }
  }
}
```

### Cursor / Claude Code project scope

`.mcp.json` in your project root:

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

### VS Code (`.vscode/mcp.json`)

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

### Pre-connecting at startup

If your URI is stable (for example, you always launch the app on a fixed port),
skip `connect_to_app` by passing it at startup:

```console
flutter_ai_whisper --vm-uri "ws://127.0.0.1:56660/RsqcVzTFmw0=/ws"
```

## Tools

### `discover_running_apps`

Lists running apps and their VM Service URIs. Usually you can skip this and call
`connect_to_app` directly.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `workspaceFilter` | string | no | Substring to match the workspace root, e.g. `sample_app`. |

### `connect_to_app`

Connects to a running app. **All parameters are optional** — call it with no
arguments and it discovers the app automatically.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `vmUri` | string | no | Target one specific app by its WebSocket URI. |
| `workspaceFilter` | string | no | Substring to match the workspace root during auto-discovery. |

Reports which VM Service features are available, since they differ by platform.

### Automatic discovery

Rather than copying a URI out of `flutter run`'s console, the server asks the
**Dart Tooling Daemon (DTD)** what is running. `flutter run` and the IDEs start
a DTD instance per workspace and register the app's VM Service with it, so DTD
already holds the auth-coded WebSocket URI.

This matters because that URI's path segment is a **per-run auth code** — it
changes every time the app relaunches, so a pasted URI is stale almost
immediately. It is the same discovery mechanism the official `dart mcp_server`
uses.

Discovery returns nothing if the app was not started by `flutter run` or an IDE.
In that case, pass `vmUri` manually using the line `flutter run` printed:

```text
This app is linked to the debug service: ws://127.0.0.1:56660/RsqcVzTFmw0=/ws
```

The bare app URL (`http://localhost:52362/`) is the static web server, not the
VM Service, and will not connect.

### `list_active_state_holders`

Reports live state holders, optionally filtered by name.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `filter` | string | no | Case-insensitive substring match on name. |
| `expressions` | string[] | no | Dart expressions to evaluate and report. |
| `libraryUri` | string | no | Library to evaluate in, to reach private members. |

### `inject_state_variable`

Mutates runtime state by evaluating Dart inside the app.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `expression` | string | one of | Full Dart statement, e.g. `counterCubit.setValue(42)`. |
| `targetExpression` | string | with `newValueExpression` | Assignable target. |
| `newValueExpression` | string | with `targetExpression` | Value expression. |
| `libraryUri` | string | no | Library to evaluate in. |

Prefer `expression`. The `target`/`value` pair builds `target = value`, which
**fails for `final` globals** with `Setter not found`.

### `trigger_route_navigation`

Pushes a named route.

| Parameter | Type | Required | Description |
| --- | --- | --- | --- |
| `routePath` | string | yes | Named route, e.g. `/profile`. |

Walks the element tree to find a `BuildContext` below a `Navigator`, so no
app-side `navigatorKey` is needed. The route must exist in the app's `routes`
table — this tool cannot synthesise routes that were never registered.

## Platform support

This is the most important thing to know before debugging a failure.

| Capability | Native (desktop/mobile) | Flutter Web |
| --- | --- | --- |
| `evaluate` | yes | yes |
| `getClassList` + `getInstances` | yes | **no** — `Unknown method` |
| `rootLib.variables` | yes | **no** — returns empty |
| `dart:mirrors` | yes | **no** |
| Route navigation | yes | yes |

On **Flutter Web**, heap enumeration is impossible, so
`list_active_state_holders` cannot discover state by itself. Name the state
explicitly via `expressions`. The practical workflow is to have the agent read
the app's source, find the top-level state objects, then probe them:

```json
{
  "name": "list_active_state_holders",
  "arguments": {
    "expressions": ["counterCubit.count", "authNotifier.isLoggedIn"]
  }
}
```

On **native** targets, discovery by class-name pattern works, but note that it is
heuristic: it will miss holders whose names do not match a known pattern and may
include false positives.

## Recipes

### Plain objects

```json
{
  "name": "inject_state_variable",
  "arguments": { "expression": "counterCubit.setValue(42)" }
}
```

### Riverpod

Riverpod's `state` is `@protected`, so you cannot assign it from outside the
notifier subclass. Call a method on the notifier, reached through the container:

```json
{
  "name": "inject_state_variable",
  "arguments": {
    "expression": "container.read(counterProvider.notifier).setValue(77)"
  }
}
```

Requires a top-level `ProviderContainer` the agent can name:

```dart
final container = ProviderContainer();
```

To read state without a method, override it:

```dart
container.overrideWith(counterProvider.overrideWith(() => FakeNotifier(99)));
```

### Bloc

Bloc has **no global registry of instances**. Each lives inside its
`BlocProvider` in the widget tree, so the agent must be able to name it. Keep a
handle when you create it:

```dart
BlocProvider(create: (_) => activeBloc = CounterBloc()),
```

Write by dispatching an event, not by assigning a field:

```json
{
  "name": "inject_state_variable",
  "arguments": { "expression": "activeBloc.add(const CounterSet(55))" }
}
```

Watch out: `BlocProvider(create:)` is **lazy**. The bloc does not exist until
its route is built, so navigate to that screen first or reads will fail with
`Unexpected null value`.

### GetX

GetX is the easiest of the three: it keeps a global registry, so controllers
are reachable by type with no app changes.

```json
{
  "name": "inject_state_variable",
  "arguments": { "expression": "Get.find<CounterController>().count.value = 9" }
}
```

GetX navigation needs no context at all:

```json
{
  "name": "inject_state_variable",
  "arguments": { "expression": "Get.toNamed('/profile')" }
}
```

### Private members

Dart's `_`-prefix privacy is library-scoped. A private field is invisible when
you evaluate against the app's root library, even though the object is alive.
Pass `libraryUri` to evaluate inside the declaring library's scope:

```json
{
  "name": "inject_state_variable",
  "arguments": {
    "libraryUri": "package:my_app/pages/home_page.dart",
    "expression": "(() { final s = targetState as _HomePageState; s.setState(() { s._localCounter = 12; }); })()"
  }
}
```

The agent should discover the exact URI from the error message, which lists
every app library when the URI does not match.

## How it works

```
MCP client  ──stdio/JSON-RPC──>  flutter_ai_whisper  ──WebSocket──>  Dart VM Service  ──>  app isolate
```

1. `vmServiceConnectUri` opens a WebSocket to the DDS endpoint.
2. `getVM` selects the isolate named `main()` and caches its root library.
3. Tools call `evaluate` against that library (or a named one), then cast the
   response to `InstanceRef` or `ErrorRef`.
4. Errors are returned as `isError: true` results rather than thrown, so the
   agent can react instead of the transport dying.

## Troubleshooting

**`Not connected to a Flutter app`** — call `connect_to_app` first, with the
current URI.

**`WebSocketException ... HTTP status code: 200`** — you pointed at the static
web server. Use the `debug service` URI, not the app URL.

**`HTTP status code: 403`** — the URI is missing or has a stale auth code.
Copy it again from the current `flutter run` output.

**`Setter not found`** — you assigned to a `final`. Use an `expression` that
calls a setter method instead.

**`CompilationError: Undefined name 'x'`** — the name is not in scope in the
root library. Either it is private (pass `libraryUri`) or the agent guessed the
name wrong; read the source.

**`list_active_state_holders` returns nothing** — on Flutter Web you must pass
`expressions`.

**Navigation reports no route generator** — the route is not in the app's
`routes` table. This is a correct failure, not a bug.

## Security

This server executes arbitrary Dart inside your app process, with the app's
full privileges. It is a **development-only** tool.

- Only ever point it at an app you control, running locally.
- Do not expose the VM Service port beyond localhost.
- Never run it against a production build or an untrusted app: anyone who can
  reach the VM Service can read and overwrite runtime state.

## License

MIT — see [LICENSE](LICENSE).