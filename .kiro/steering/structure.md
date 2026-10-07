---
inclusion: always
---

# Project Structure

## Layout

```
flutter_ai_whisper/
├── bin/
│   └── main.dart               Entry point: CLI args, MCP server, tool schemas
├── lib/
│   ├── discovery.dart          Finds running apps via the Dart Tooling Daemon
│   ├── state_discoverer.dart   Class-pattern + library-variable discovery
│   ├── vm_bridge.dart          VM Service connection and `evaluate`
│   └── tools/
│       ├── connect_to_app.dart
│       ├── discover_running_apps.dart
│       ├── inject_state_variable.dart
│       ├── list_active_state_holders.dart
│       └── trigger_route_navigation.dart
├── test/
│   └── tools_test.dart
├── example/
│   └── README.md               Usage walkthrough
├── pubspec.yaml
└── analysis_options.yaml
```

## Responsibilities

| Path | Owns |
| --- | --- |
| `bin/main.dart` | Argument parsing, server startup, registering tools with full JSON schemas |
| `lib/vm_bridge.dart` | Connecting, isolate and library resolution, `evaluate`, capability detection |
| `lib/discovery.dart` | `dart tooling-daemon --list`, DTD connections, app enumeration |
| `lib/state_discoverer.dart` | Name-pattern discovery and expression probing |
| `lib/tools/*.dart` | One tool each, returning `Future<CallToolResult>` |

Keep these separate. `vm_bridge.dart` is transport; it must not contain tool
logic. `state_discoverer.dart` is discovery; it must not connect to anything.

## Where new code goes

- A new capability → new `lib/tools/<tool_name>.dart`.
- A new way to find apps → `lib/discovery.dart`.
- A new way to find state → `lib/state_discoverer.dart`.
- Anything touching the VM Service connection → `lib/vm_bridge.dart`.

## Adding a tool

1. Create `lib/tools/<tool_name>.dart` exporting
   `Future<CallToolResult> handler(VmBridge bridge, Map<String, dynamic> args)`.
2. Return `isError: true` for **expected** failures. Never let a tool throw out
   of its handler — the transport must survive so the agent can recover.
3. Register it in `bin/main.dart` with `server.addTool`, including a complete
   JSON schema. The agent sees only that description, so it must state what the
   tool is for, when to use it, and what its parameters mean.
4. Add tests to `test/tools_test.dart` for argument validation and the
   disconnected path.
5. Document it in `README.md`, `AGENTS.md` and `llms.txt`.

## Conventions

- Dart 3.8+, strict casts and raw types.
- One `VmBridge` instance shared by all tools; never open a second connection.
- Prefer `evaluate` with an explicit `libraryUri` over guessing at scope.
- Keep the app's root library as the default target; widen only deliberately.
- `CallToolResult.isError` is **nullable** — `null` means success. Always test
  with `result.isError != true`, never `!result.isError!`. Getting this wrong
  throws a null-check error on every successful call.

## Agent documentation

This package ships instructions for several tools, because the agent-facing
knowledge is substantial and easy to get wrong:

| File | Audience |
| --- | --- |
| `llms.txt`, `AGENTS.md` | Canonical guides |
| `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, `.github/copilot-instructions.md` | Pointers |
| `.kiro/steering/*.md` | This Kiro workspace |
| `AGENT_DOCS.md` | Maintainer map of all of the above |

When a behavioural rule changes, update the canonical guides first, then the
pointers. `AGENT_DOCS.md` lists the rules that must stay in sync across every
file.

Not published: `pubspec.lock`, `.dart_tool/`, `build/`, `.git/`.
