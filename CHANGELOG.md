# Changelog

## 1.3.0

### Added

- `start_change_refresh`, `refresh_changed_members`, and `stop_change_refresh`
  MCP tools — when analysis is clean, hot-reload changed library bodies and
  call changed zero-argument methods (with `State` methods wrapped in
  `setState`).
- DevTools extension package under `devtools/` (`flutter_ai_whisper_devtools`):
  Screen / Logic / Run panel for primitive field writes over the VM Service.
  Documented in README and `devtools/README.md`.
- Runnable `example/lib/main.dart` with web and Windows targets, plus
  `devtools_options.yaml` for the extension.
- `doc/kotlin-runtime-mcp.md` — notes for Kotlin/Android runtime MCP parity.

### Changed

- `VmBridge` gains reload/reassemble helpers used by change-refresh.
- README links to the DevTools extension setup guide.

## 1.2.1

### Changed

- README demo uses a clickable `doc/demo-poster.png` thumbnail so the promo is
  visible on pub.dev (HTML `<video>` is stripped there; the MP4 stays on GitHub).

## 1.2.0

### Added

- README **Demo** section with `flutter-ai-whisper-promo.mp4` (git repository
  only; excluded from the pub tarball via `.pubignore`).

### Changed

- Package and example documentation rewritten for pub.dev: install, MCP client
  setup, auto-discovery, platform matrix, and state-management recipes.
- Public libraries documented for dartdoc.

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