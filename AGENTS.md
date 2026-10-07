# flutter_ai_whisper — Agent Guide

MCP server that inspects and mutates the runtime state of a **running** Flutter
app over the Dart VM Service.

This is the canonical agent-facing document. `CLAUDE.md`, `GEMINI.md`,
`.cursorrules` and `.github/copilot-instructions.md` are thin pointers here, so
this file is the single source of truth.

## What this is

A Dart CLI that speaks MCP on `stdio` and exposes five tools. It is **not** a
Flutter app and has no Flutter dependency — it is an external process that talks
to a running app over a WebSocket.

```
MCP client  ──stdio/JSON-RPC──>  bin/main.dart  ──WebSocket──>  app isolate
```

## Setup

```console
dart pub global activate flutter_ai_whisper
```

Register with the client, e.g. in `.mcp.json`:

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

## The connection rule — read this first

The app must run in **debug mode**.

**Call `connect_to_app` with no arguments.** It discovers the running app
through the Dart Tooling Daemon (DTD) — the same mechanism the official
`dart mcp_server` uses — and connects automatically. `discover_running_apps`
lists candidates when several are running, and accepts a `workspaceFilter`.

`flutter run` also prints a URI, but **do not copy it**:

```text
This app is linked to the debug service: ws://127.0.0.1:56660/RsqcVzTFmw0=/ws
```

The path segment is a **per-run auth code** that changes on every relaunch, so a
pasted URI is stale the moment the app restarts. Pass `vmUri` manually only when
discovery finds nothing, which happens when the app was not started by
`flutter run` or an IDE.

Known failure modes:

- The bare app URL (`http://localhost:52362/`) is the **static web server**,
  not the VM Service. Connecting to it yields
  `WebSocketException: HTTP status code: 200`.
- `403` means the URI is stale or missing the auth code.
- Profile/release builds expose no VM Service. Obfuscated builds hide class
  names and break heap discovery.

## Tools

| Tool | Purpose |
| --- | --- |
| `discover_running_apps` | List running apps and their VM Service URIs via DTD. |
| `connect_to_app` | Connect. Safe with no arguments — auto-discovers. |
| `list_active_state_holders` | Report live state; or probe given `expressions`. |
| `inject_state_variable` | Evaluate Dart to mutate state. |
| `trigger_route_navigation` | Push a named route. |

Full parameter tables are in `README.md`.

## Platform differences — the critical constraint

| Capability | Native | Flutter Web |
| --- | --- | --- |
| `evaluate` | yes | yes |
| `getClassList` + `getInstances` | yes | **no** |
| `rootLib.variables` | yes | **no** (empty) |
| `dart:mirrors` | yes | **no** |
| Route navigation | yes | yes |

**On Flutter Web you cannot enumerate state.** Name it via `expressions`.
Practical workflow: read the app's source, find top-level state objects, then
probe them by name. The agent has filesystem access, so this is the intended
flow — not a limitation to work around.

On native, class-name-pattern discovery works, but it is heuristic.

## Expression rules

**Prefer `expression` over `targetExpression`/`newValueExpression`.** The pair
builds `target = value`, which fails on `final` globals with
`Setter not found: x`. Use a method call instead:

```
counterCubit.setValue(42)
```

**`evaluate` returns a single expression, not statements.** No comma
expressions, no multiple statements. Wrap in an IIFE:

```dart
(() { obj.a = 1; obj.b = 2; return 'done'; })()
```

**`evaluate` can target any library, not just the root.** Dart's `_` privacy is
library-scoped, so private members are invisible from the root library. Pass
`libraryUri` to evaluate inside the declaring library:

```
libraryUri: "package:my_app/pages/home_page.dart"
```

Without it, private names fail to even **compile**, surfacing as
`CompilationError: Undefined name '_x'`. That single rule covers private
**fields**, **classes**, **methods** and **getters** alike — there is no
per-kind exception.

The error message lists every app library when a URI does not match.

## Scope and reachability

**One expression is evaluated in exactly one library scope.** Visibility follows
that library's own import and `export` graph, not your intuition. A barrel file
with `export 'state/signal_store.dart';` is why the root library can see a
holder defined elsewhere. Choosing the wrong library gives `Undefined name` even
for a perfectly good object.

**You can only reach what the object exposes.** Injection runs real Dart, so the
public surface is the ceiling. A read-only getter with no setter, plus only an
`increment()`, means you can increment but never assign:

```dart
s.setState(() { for (var i = 0; i < 12; i++) { appState.incrementCounter(); } });
```

Read the class before assuming a value is unsettable. If arbitrary assignment is
genuinely needed, the app must expose a setter — an app change, not a tool
limitation.

**The element-tree walk is the general escape hatch.** Any `StatefulWidget`'s
`State` is reachable by matching its widget type, whatever the naming:

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
  return s._localCounter.toString();   // private field AND private method
})()
```

With `libraryUri` set to that declaring library, private members of the `State`
— fields and methods alike — are reachable. Guard on `t == null`: if the widget
is not mounted, nothing matches.

**Navigate via the tree, not `rootElement`.**
`Navigator.of(rootElement!)` throws because `rootElement` sits *above* the
Navigator. `trigger_route_navigation` walks down to the first descendant that
resolves a Navigator.

## Mutating state: always trigger the rebuild

`evaluate` mutates *objects*, which is not the same as updating the *view*. A
plain field write produces no rebuild: the variable reads back as changed while
the screen still shows the old value.

**Mutate inside `setState` for anything without its own notification.** Plain
objects, and private widget state, need it. GetX `Rx`, Riverpod state, Bloc
events and `ValueNotifier`/`ChangeNotifier` notify on their own and need nothing
extra.

```dart
(() {
  Element? t;
  void walk(Element e) {
    if (t != null) return;
    if (e.widget is HomePage) { t = e; return; }
    e.visitChildren(walk);
  }
  walk(WidgetsBinding.instance.rootElement!);
  final s = (t as StatefulElement).state as _HomePageState;
  s.setState(() { counterCubit.setValue(42); });
  return 'ok';
})()
```

Requires `libraryUri` pointing at the declaring library, because `_HomePageState`
is private.

**`setState` rebuilds on the next frame, not inline.** Reading a build counter
immediately after still shows the old value.

**`setState` on an offstage element is deferred.** If the page is covered by
another route, the write lands and the variable reads back changed, but nothing
repaints until that element reactivates. The screen looks unchanged and the build
counter stays frozen — a false negative, not a failed injection. Count matching
elements to check for duplicate copies:

```dart
int homePages = 0;
void walk(Element e) {
  if (e.widget is HomePage) homePages++;
  e.visitChildren(walk);
}
walk(WidgetsBinding.instance.rootElement!);
```

Pop back to the route before injecting, and **poll** for the rebuild rather than
sleeping a fixed amount.

Confirm the view changed by walking the element tree and reading `Text` widgets,
not by re-reading the variable.

Confirm the view changed by walking the element tree and reading `Text` widgets,
not by re-reading the variable. A `static int buildCount = 0;` incremented in
`build()` makes this assertable.

## State-management specifics

None of these are special-cased. Injection is just Dart evaluation, so any state
management works provided you can name a reference to it. The differences are
only about *how you get a reference* and *whether it self-notifies*.

**Riverpod** — `state` is `@protected`; you cannot assign it externally. Call a
method on the notifier via a top-level `ProviderContainer`:

```
container.read(counterProvider.notifier).setValue(77)
```

Assigning `notifier.state = x` fails to compile. Self-notifies, so no `setState`.

**Bloc** — no global instance registry; each lives in its `BlocProvider`. The
agent must be able to name it (keep a handle at creation). Write by dispatching
an event: `activeBloc.add(const CounterSet(55))`. **`BlocProvider(create:)` is
lazy** — navigate to the route first or reads fail with
`Unexpected null value`.

**GetX** — easiest. Global registry, so `Get.find<T>()` works with no app
changes. `.value` is directly writable and self-notifies. Navigation needs no
context: `Get.toNamed('/profile')`.

**Plain objects** (`CounterCubit`, `AppState`) — easiest to name, but they have
**no change notification at all**. Every write needs a `setState`, and they
expose only what you gave them.

**Custom / unknown libraries** — nothing special. A hand-rolled `Sig<T>` or a
`CartRepo` works exactly like the above, because discovery is never involved
when you name the holder yourself.

## Error handling

Tool failures are returned as `isError: true` results, not thrown — the
transport stays alive so the agent can recover and try a different approach.
Read the error text before retrying; most failures name the exact fix.

## Security

This server executes arbitrary Dart in the app process with full app privileges.
Development only. Never point it at a production build or an app you do not
control, and never expose the VM Service port beyond localhost.

## Development

```console
dart pub get
dart analyze          # must be clean
dart test             # must pass
dart format .
dart pub publish --dry-run
```

### Layout

| Path | Role |
| --- | --- |
| `bin/main.dart` | CLI arg parsing, MCP server, tool registration + schemas |
| `lib/vm_bridge.dart` | VM Service connection, isolate/library resolution, `evaluate` |
| `lib/discovery.dart` | Finds running apps via the Dart Tooling Daemon |
| `lib/state_discoverer.dart` | Class-pattern + library-variable discovery, expression probing |
| `lib/tools/*.dart` | One file per tool; each is a `Future<CallToolResult>` |

### Adding a tool

1. Add a handler in `lib/tools/<tool_name>.dart` returning
   `Future<CallToolResult>`. Return `isError: true` for expected failures.
2. Register it in `bin/main.dart` with `server.addTool`, including a full JSON
   schema — the agent only sees that description.
3. Add tests in `test/tools_test.dart` covering argument validation and the
   disconnected path.
4. Document it in `README.md` and the table above.

### Conventions

- Dart 3.7+, strict casts and raw types.
- Prefer `evaluate` with a specific `libraryUri` over guessing.
- Keep the root library as the default target; only widen deliberately.
- Never let a tool throw out of its handler.
- `CallToolResult.isError` is **nullable**; `null` means success. Test it with
  `result.isError != true`, never `!result.isError!`.

## Before publishing

- Repository metadata is set: `repository`/`homepage`/`issue_tracker` point at
  `github.com/RajKavadia/flutter_ai_whisper`, and `LICENSE` names the author.
- Confirm the package name is still available on pub.dev.
- Bump `version` and add a `CHANGELOG.md` entry.