# flutter_ai_whisper_devtools

A [Dart DevTools extension](https://docs.flutter.dev/tools/devtools/extensions)
that inspects and mutates **live app state** over the VM Service connection
DevTools already has. It is **not** the MCP server (`flutter_ai_whisper` on
stdio). Agents use MCP; humans use this panel while debugging.

```
DevTools (debug session)
  └── Extensions → flutter_ai_whisper
        └── Screen | Logic | Run
              └── evaluate() in your app isolate
```

## Requirements

- Your app running in **debug** mode (`flutter run`, IDE, or Chrome for web).
- Dart SDK `^3.8.0`, Flutter `>=3.32.0` (same as this package).
- Profile, release, and obfuscated builds do not expose a usable VM Service.

## Install in your app

Add a **dev dependency** (path or git). The package name is
`flutter_ai_whisper_devtools`; the DevTools tab title is **flutter_ai_whisper**
(from `extension/devtools/config.yaml`).

```yaml
# pubspec.yaml
dev_dependencies:
  flutter_ai_whisper_devtools:
    path: ../devtools   # path to this folder in the monorepo
    # git:
    #   url: https://github.com/RajKavadia/flutter_ai_whisper
    #   path: devtools
```

Create **`devtools_options.yaml`** in the same directory as the app's
`pubspec.yaml`:

```yaml
description: This file stores settings for Dart & Flutter DevTools.
documentation: https://docs.flutter.dev/tools/devtools/extensions#configure-extension-enablement-states
extensions:
  - flutter_ai_whisper_devtools: true
```

Then:

```console
flutter pub get
flutter run
```

Open the **DevTools** link from the terminal (or your IDE), go to
**Extensions → flutter_ai_whisper**. If the tab is missing, restart DevTools
after editing `devtools_options.yaml`.

This repo's **`example/`** app is already wired (`path: ../devtools` and
`devtools_options.yaml`).

## Using the panel

### Header

| Control | Action |
| --- | --- |
| **Reload list** | Runs a **Screen** or **Logic** scan again (census / discovery). |
| **Refresh** | Calls `WidgetsBinding.instance.reassemble()` in the app, then reloads the list. Does not assign values. |

Use **Search** to filter the current list (widget type, state type, preview, or
logic name).

### Screen

Lists **`State` objects on the current route** (the top `ModalRoute` with
`isCurrent == true`, including dialogs).

1. **Reload list** on the home route.
2. Select a row (e.g. `_HomePageState` in the example).
3. Pick a **field** in the dropdown.
4. Enter a **primitive literal** only: `42`, `3.14`, `true`, `"text"`, `null`.
5. **Assign** — the write runs in the declaring library inside `setState` when
   needed.
6. Confirm the on-screen **`Text`** changed (not just the variable in memory).

Private fields (e.g. `_localCounter`) are editable when the panel resolves the
correct library. Read-only getters show a reason; use **Run** to call methods
instead.

### Logic

Lists **state-like objects** reachable from the current screen (fields whose
runtime type matches patterns such as `Cubit`, `Bloc`, `Notifier`, `Controller`,
…). On **native** VMs it also adds **heap** rows (`getClassList` /
`getInstances`) and root-library variables.

On **Flutter Web**, heap enumeration is unavailable. You still get
screen-reachable logic; use **Run** to probe a named expression if something
is missing from the list.

Assigning a logic object that **self-notifies** (`ValueNotifier`, `Bloc`,
`Cubit`, `Rx`, …) does not wrap in `setState`. Plain holders still need the
screen `State` to rebuild.

### Run

One **Dart expression** in one optional **library URI** (defaults to the app
root). Same power as MCP `inject_state_variable`. Executes real code in the app
process — debug apps you control only.

After **Run**, the panel polls **`Text.data`** on the current route to detect a
visible change.

## Example app: finding the counter

With `example/lib/main.dart` running:

| UI label | Where in the panel |
| --- | --- |
| `local: N` | **Screen** → `_HomePageState` → field **`_localCounter`** → Assign e.g. `99` |
| `count: N` | **Logic** → field **`counterCubit`** on the home state, or **Run** with `counterCubit.count` / `counterCubit.setValue(42)` plus a rebuild recipe (see [example README](../example/README.md)) |

## Platform notes

| Capability | Native | Flutter Web |
| --- | --- | --- |
| Screen census (element walk) | yes | yes |
| Logic from screen `State` fields | yes | yes |
| Heap / class-list discovery | yes | no |
| Assign + route `Text` poll | yes | yes |

If another route covers the page, the write can succeed while **`Text` on that
route does not update** until you pop back — same as MCP `setState` on an
offstage element.

## Develop this package

```console
cd devtools
flutter pub get
flutter analyze
flutter test
```

### Web smoke test (no DevTools UI)

With `example/` running on Chrome:

```console
cd devtools
dart run tool/web_smoke.dart
# or pass the ws:// URI from flutter run:
dart run tool/web_smoke.dart ws://127.0.0.1:PORT/AUTH=/ws
```

This runs the same **Screen** census, assigns `_localCounter`, and checks route
`Text` over the VM Service.

### Rebuild extension assets

DevTools loads the precompiled web app from `extension/devtools/build/`:

```console
cd devtools
dart run devtools_extensions build_and_copy --source=. --dest=extension/devtools
```

Commit `extension/devtools/build/` when you want path/git consumers to see the
panel without running Flutter locally.

## MCP server

For AI agents (Cursor, Claude, OpenCode, …), use the **`flutter_ai_whisper`**
MCP server and its tools — see the [package README](../README.md). The
extension and MCP share the same VM evaluate ideas but different transports.

## License

Same as [flutter_ai_whisper](../LICENSE) (MIT).
