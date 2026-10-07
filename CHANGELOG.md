# Changelog

## 1.1.0

### Added

- `discover_running_apps` — lists running Flutter/Dart apps with their VM Service
  URIs using the Dart Tooling Daemon (DTD). Optional `workspaceFilter` narrows
  the result when several apps are running.
- Automatic app discovery in `connect_to_app`. **The `vmUri` argument is now
  optional**: with no arguments the tool discovers the running app via DTD. Pass
  `vmUri` only to target one specific app, or when discovery finds nothing.
- Agent documentation for Kiro under `.kiro/steering/` (`product`, `tech`,
  `structure`, `runtime-rules`).

### Changed

- Minimum Dart SDK is now `^3.8.0` (was `^3.7.0`). `mcp_server` 2.x needs 3.7 at
  runtime and `lints` 6 needs 3.8 as a dev dependency; the floor is the higher
  of the two.
- `lints` upgraded to `^6.0.0`, which adds `no_wildcard_variable_uses`,
  `unnecessary_underscores` and `use_null_aware_elements` to the recommended set.
- Connection guidance corrected everywhere it appeared. The `--vm-uri` help text,
  the "not connected" error and the discovery-failure message previously told
  callers to copy the URI printed by `flutter run`. That is the one thing the
  docs tell you not to do, because its path segment is a per-run auth code.

### Fixed

- Repository line endings are now normalised by a `.gitattributes` rule
  (`* text=auto eol=lf`). Previously `AGENTS.md` and `llms.txt` carried mixed
  CRLF/LF within a single file, and every `git add` on Windows emitted
  "LF will be replaced by CRLF".

## 1.0.0

Initial release.

### Tools

- `connect_to_app` — connect to a running Flutter app over its VM Service
  WebSocket. Required first when the app was started with `flutter run`,
  because the printed URI embeds a per-run auth code.
- `list_active_state_holders` — report live state providers, blocs, notifiers
  and stateful references. On Flutter Web, automatic enumeration is
  impossible, so caller-supplied `expressions` are probed instead.
- `inject_state_variable` — evaluate a Dart statement to mutate runtime state.
  Accepts a full `expression`, or `targetExpression` + `newValueExpression`.
- `trigger_route_navigation` — push a named route by locating a
  `BuildContext` below a `Navigator` in the element tree, so no app-side
  `navigatorKey` is required.

### Platform support

- Native (Android, iOS, Linux, macOS, Windows): heap enumeration via
  `getClassList` + `getInstances` is available.
- Flutter Web: `getClassList` and `getRootLibrary().variables` are not
  implemented and `dart:mirrors` is unavailable, so state must be addressed by
  name. `libraryUri` may be supplied to evaluate inside a specific library's
  scope, which is required to reach private (`_`-prefixed) members.