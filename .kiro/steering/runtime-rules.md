---
inclusion: always
---

# Runtime Rules

Non-negotiables for driving a running Flutter app through this server. Each of
these has caused a real failed attempt. `AGENTS.md` carries the full rationale.

## Connecting

- **Call `connect_to_app` with no arguments.** It discovers the app through the
  Dart Tooling Daemon. Never paste the URI from `flutter run` — its path segment
  is a per-run auth code that changes on every relaunch, so a pasted URI is stale
  almost immediately.
- The bare app URL (`http://localhost:52362/`) is the **static web server**, not
  the VM Service. Connecting to it fails with
  `WebSocketException: HTTP status code: 200`.
- A `403` means the URI is stale or missing the auth code.
- Pass `vmUri` manually only when discovery finds nothing, which happens when the
  app was not started by `flutter run` or an IDE.

## Scope and reachability

- **One expression is evaluated in exactly one library scope.** Visibility
  follows that library's `import`/`export` graph, not your intuition. Choosing
  the wrong library yields `CompilationError: Undefined name` for a perfectly
  valid object.
- **Private members require `libraryUri`** pointing at their declaring library.
  Dart privacy is library-scoped and uniform — fields, classes, methods and
  getters all fail to compile from the wrong library. There is no per-kind
  exception.
- **You can only reach what the object exposes.** A read-only getter with no
  setter cannot be assigned, however good the injection is. `AppState.counter`
  exposes a getter and `incrementCounter()` but no setter, so setting it to 12
  means looping the increment. Read the class before assuming a value is
  unsettable; if arbitrary assignment is genuinely needed, that is an app change,
  not a tool limitation.
- **The element-tree walk is the general escape hatch.** Match the widget type,
  cast `StatefulElement.state`, then use it — this reaches private `State`
  members and works whatever the widget is named. Guard on a null match, since
  nothing matches when the widget is not mounted.

## Expressions

- **Prefer `expression` over `targetExpression`/`newValueExpression`.** The pair
  builds `target = value`, which fails on `final` globals with
  `Setter not found: x`. Call a method instead.
- **`evaluate` takes one expression, not statements.** No comma expressions and
  no multiple statements. Wrap multi-statement logic in an IIFE.
- **Navigate via the tree, not `rootElement`.** `Navigator.of(rootElement!)`
  throws because `rootElement` sits above the Navigator.

## Updating the view

- **Mutating an object does not update the view.** A plain field write produces
  no rebuild: the variable reads back changed while the screen shows the old
  value. Mutate *inside* `setState` so values are committed before the rebuild
  reads them.
- GetX `Rx`, Riverpod state, Bloc events, `ValueNotifier` and `ChangeNotifier`
  notify on their own and need nothing extra.
- **`setState` rebuilds on the next frame, not inline.** Poll for the rebuild
  rather than sleeping a fixed amount.
- **`setState` on an offstage element is deferred.** If the page is covered by
  another route, the write lands and the variable reads back changed, but nothing
  repaints until that element reactivates — so the screen looks unchanged and the
  build counter stays frozen. This is normal Flutter `markNeedsBuild` behaviour,
  not a failed injection. Pop back to the route before injecting.
- **Verify against the rendered tree**, by walking the element tree for `Text`
  widgets, not by re-reading the variable. A `static int buildCount` incremented
  in `build()` makes this assertable.

## Platform limits

- **Flutter Web cannot enumerate state.** `getClassList`, `rootLib.variables` and
  `dart:mirrors` are unavailable. Name state explicitly via `expressions`,
  derived from the app's source. This is the intended workflow, not a limitation
  to work around — the agent has filesystem access.
- Profile and release builds expose no VM Service at all.

## Errors

- Tool failures come back as `isError: true` results, not exceptions, so the
  transport survives and the agent can try a different approach. Read the error
  text before retrying; most failures name the exact fix.

## Safety

This executes arbitrary Dart in the app process with full app privileges.
Development only. Never connect it to a production build or an app you do not
control.
