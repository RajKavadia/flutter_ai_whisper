---
inclusion: always
---

# Technology Stack

## Language and versions

| Item | Value |
| --- | --- |
| Language | Dart `^3.8.0` |
| Package type | Pure Dart CLI — **no Flutter dependency** |
| Executable | `flutter_ai_whisper` → `bin/main.dart` |
| License | MIT |
| Topics | `mcp`, `flutter`, `developer-tools`, `vm-service`, `debugging` |

The `^3.8.0` floor is the higher of two constraints, not an arbitrary choice:
`mcp_server` 2.x requires Dart 3.7 at runtime, while `lints` 6 requires 3.8 as a
dev dependency. Taking 3.8 keeps `dart pub get` satisfiable without pinning the
floor below what the tooling needs.

## Dependencies

| Package | Role |
| --- | --- |
| `mcp_server` ^2.2.4 | MCP protocol server, `stdio` transport, tool schemas |
| `vm_service` ^15.3.0 | VM Service client; `evaluate`, `getVM`, `getIsolate`, `getObject` |
| `dtd` ^4.0.0 | Dart Tooling Daemon client, used to discover running apps |
| `args` ^2.5.0 | CLI flag parsing (`--vm-uri`, `--help`) |
| `meta` ^1.15.0 | `@visibleForTesting` |

Dev: `test` ^1.25.0, `lints` ^5.0.0.

## Dependency policy

- Do **not** add Flutter. This package must stay runnable with plain `dart`.
- Prefer the platform SDK over adding a dependency for small utilities.
- If a dependency is unavoidable, it must be justified in a review.

## Runtime model

```
MCP client  ──stdio/JSON-RPC──>  bin/main.dart  ──WebSocket──>  app isolate
```

A single long-lived process. One `VmBridge` holds the connection; tools share it.
The process stays alive until the client disconnects.

## Platform capabilities — read before designing any change

| Capability | Native (desktop/mobile) | Flutter Web |
| --- | --- | --- |
| `evaluate` | yes | yes |
| `getClassList` + `getInstances` | yes | **no** (`Unknown method`) |
| `rootLib.variables` | yes | **no** (returns empty) |
| `dart:mirrors` | yes | **no** |
| Route navigation | yes | yes |

Any code path that assumes heap enumeration must degrade gracefully when
`VmBridge.supportsClassList` is false. The VM Service itself is unavailable in
profile and release builds, and class names are mangled under
`--obfuscate --split-debug-info`.

## Quality gates

```console
dart analyze          # must report no issues
dart test             # must pass
dart format .
dart pub publish --dry-run   # must report 0 warnings
```

`analysis_options.yaml` enables `strict-casts` and `strict-raw-types`, plus
`public_member_api_docs` as a warning.

## Testing

Unit tests cover argument validation and the disconnected path in
`test/tools_test.dart`. They deliberately avoid requiring a live Flutter app, so
CI stays hermetic.

Behaviour against a real app has been verified manually against a Flutter web
build: discovery, auto-connect, state injection, deferred-rebuild behaviour, and
navigation including the unknown-route failure path.
