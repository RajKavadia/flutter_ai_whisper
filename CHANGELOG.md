# Changelog

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