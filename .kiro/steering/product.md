---
inclusion: always
---

# Product Overview

## What this is

`flutter_ai_whisper` is an MCP (Model Context Protocol) server that lets an AI
coding agent inspect and mutate the runtime state of a **running** Flutter app,
and drive its navigation, without modifying that app.

It is a Dart CLI. It is **not** a Flutter package and has **no Flutter
dependency** — it is an external process that talks to an app over the Dart VM
Service WebSocket.

## Why it exists

Automated Flutter UI testing usually means either instrumenting the app under
test or driving it blind through taps. This takes a third route: it uses the
debug protocol the Dart VM already exposes in debug builds, so it works against
an unmodified app.

State injection is also genuinely useful outside testing — reproducing an edge
case, forcing an error state, or jumping to a screen during development.

## Users

An AI agent operating an app the developer is running locally in debug mode.

## Key features

Five MCP tools:

| Tool | Purpose |
| --- | --- |
| `discover_running_apps` | List running apps and their VM Service URIs. |
| `connect_to_app` | Connect. Takes no arguments — it auto-discovers. |
| `list_active_state_holders` | Report live state, or probe named expressions. |
| `inject_state_variable` | Evaluate Dart to mutate state. |
| `trigger_route_navigation` | Push a named route. |

Works with any state management. Riverpod, Bloc, GetX, plain objects and
hand-rolled libraries differ only in how you obtain a reference and whether they
self-notify — nothing is special-cased.

## Constraints that shape the design

- **No app instrumentation.** The target app is unmodified, so discovery must
  work from outside the process.
- **Flutter Web cannot be enumerated.** `getClassList`, `rootLib.variables` and
  `dart:mirrors` are all unavailable there, so state is addressed by name.
- **The VM Service URI is per-run.** Its path segment is an auth code that
  changes on every relaunch, which is why connection is a tool call backed by
  Dart Tooling Daemon discovery rather than a configured constant.

## Non-goals

- Not a production or release-build tool; no VM Service is exposed then.
- Not a UI automation framework. It changes state; it does not tap pixels.
- Not a debugger replacement.

## Security posture

The server executes arbitrary Dart inside the app process with the app's full
privileges. **Development only.** Never point it at a production build or an app
you do not control, and never expose the VM Service port beyond localhost.

## Deeper reference

`AGENTS.md` is the canonical agent guide: architecture, scope and reachability
rules, rebuild semantics, and state-management recipes. Read it for depth; this
file is the orientation.
