# flutter_ai_whisper

MCP server that inspects and injects state in a running Flutter app over the Dart
VM Service.

**Read `AGENTS.md` first — it is the canonical guide** covering architecture,
the four MCP tools, platform differences, expression rules, state-management
specifics, and the development workflow. This file adds Copilot-specific notes
only.

## What this project is

A Dart CLI that speaks MCP on `stdio` and inspects/mutates the state of a
**running** Flutter app over the Dart VM Service. It has **no Flutter
dependency** — do not add one.

## Non-negotiables

- **Call `connect_to_app` before any other tool.** The URI printed by
  `flutter run` embeds a per-run auth code and changes every relaunch.
- **The app URL is not the VM Service.** `http://localhost:52362/` is the static
  web server; the real URI is the `ws://127.0.0.1:PORT/AUTHCODE=/ws` line.
- **Flutter Web cannot enumerate state.** `getClassList`, `rootLib.variables`
  and `dart:mirrors` are all unavailable. Name state explicitly and read the
  app's source to find the names.
- **Prefer `expression` over `target`/`value`.** The pair builds `target = value`
  and fails on `final` globals with `Setter not found`.
- **`evaluate` takes one expression, not statements.** No comma expressions; wrap
  multi-statement logic in an IIFE.
- **Private members need `libraryUri`.** Dart privacy is library-scoped, so
  `_field` is invisible from the root library.
- **Tool failures come back as `isError: true`, not exceptions.** Read the error
  text before retrying.

## Verify before claiming done

```console
dart analyze   # must report no issues
dart test      # must pass
```

## Safety

This server runs arbitrary Dart inside the app process with full privileges. It
is development-only. Never connect it to a production build or an untrusted app.

## Before publishing

Replace the `YOUR_GITHUB_USERNAME` / `YOUR_NAME` placeholders in `pubspec.yaml`
and `LICENSE`, bump the version, add a `CHANGELOG.md` entry, and run
`dart pub publish --dry-run`.