# GEMINI.md

Guidance for Gemini CLI when working on **flutter_ai_whisper**.

**Read `AGENTS.md` first — it is the canonical guide** covering architecture,
the five tools, platform differences, scope and reachability, expression rules,
rebuild semantics, state-management recipes, and the development workflow. This
file adds Gemini-specific notes only.

## What this project is

A Dart CLI that speaks MCP on `stdio` and inspects/mutates the state of a
**running** Flutter app over the Dart VM Service. It has **no Flutter
dependency** — do not add one.

## Non-negotiables

- **Call `connect_to_app` with no arguments.** It auto-discovers the app via the
  Dart Tooling Daemon. Never paste the URI from `flutter run` — its path is a
  per-run auth code that goes stale on every relaunch.
- **The app URL is not the VM Service.** `http://localhost:52362/` is the static
  web server; the real URI is the `ws://127.0.0.1:PORT/AUTHCODE=/ws` line.
- **An expression lives in exactly one library scope.** Visibility follows that
  library's import/export graph, so the wrong library yields
  `CompilationError: Undefined name`.
- **Private members need `libraryUri`.** Dart privacy is library-scoped and
  uniform — fields, classes, methods and getters all fail to compile from the
  wrong library, so private methods need it too.
- **Mutating an object does not update the view.** Plain fields need an explicit
  `setState` (mutate inside it); GetX `Rx`, Riverpod, Bloc and
  `ValueNotifier`/`ChangeNotifier` notify themselves. `setState` rebuilds on the
  next frame, not inline — wait a frame before verifying, and check the rendered
  `Text` widgets rather than re-reading the variable.
- **You can only reach what the object exposes.** A read-only getter with no
  setter cannot be assigned, however good the injection is.
- **The element-tree walk reaches any widget state.** Match on the widget type,
  cast `StatefulElement.state`, then use it — the escape hatch when naming fails.
- **Prefer `expression` over `target`/`value`.** The pair builds `target = value`
  and fails on `final` globals with `Setter not found`.
- **`evaluate` takes one expression, not statements.** No comma expressions; wrap
  multi-statement logic in an IIFE.
- **Tool failures come back as `isError: true`, not exceptions.** Read the error
  text before retrying.
- **Flutter Web cannot enumerate state.** `getClassList`, `rootLib.variables`
  and `dart:mirrors` are unavailable. Name state explicitly via `expressions`.

## Verify before claiming done

```console
dart analyze   # must report no issues
dart test      # must pass
```

## Safety

This server runs arbitrary Dart inside the app process with full privileges. It
is development-only. Never connect it to a production build or an untrusted app.

## Before publishing

Repository metadata is already set to `RajKavadia/flutter_ai_whisper`. Before
releasing, bump the version, add a `CHANGELOG.md` entry, and run
`dart pub publish --dry-run`.