# Kotlin Runtime MCP

An MCP server that lets an AI agent read, change, and navigate a **running native Kotlin Android app** over JDWP. The app repository is not modified. No Gradle plugin, no library, no manifest entry, and no debug hook in source.

This is a separate product from `flutter_ai_whisper`. That server speaks the Dart VM Service. This one speaks the Android debugger protocol. A Flutter app on Android is still served by `flutter_ai_whisper`.

## Objective

Give a coding agent the same kind of live control over a native Kotlin process that `flutter_ai_whisper` has over a Flutter isolate:

- See the in-memory value that the screen is using.
- Change that value while the process keeps running.
- Open a screen the app already contains.
- Do all of that without editing the app.

The agent never attaches to the phone. It calls tools on a local MCP server. The server attaches to the debug process.

## Solution

A normal debug build is already attachable. Android Studio and `assembleDebug` set `android:debuggable="true"`, which opens a JDWP port. The MCP server, running on the developer machine, uses `adb` to find that port and the Java Debug Interface to suspend one thread, read or write a field, call a method that is already loaded, or open an existing route or Activity. It then resumes the thread.

```
AI agent ──stdio/MCP──> kotlin-runtime-mcp ──adb/JDWP──> debuggable app process
```

Nothing is added to the app. The route, the Activity, the field, and the method must already be in the build that is running. A Play or release build does not appear in `adb jdwp`, and the server stops before any write or navigation.

ART will not compile a new Kotlin snippet into the running process. The server sets fields and calls methods that already exist. That is the same ceiling as Android Studio's debugger, reached from an agent instead of from the IDE.

## What this does not do

- It does not edit, patch, or instrument the app project.
- It does not attach to a release, profile, or Play build.
- It does not bypass `android:debuggable`.
- It does not load new Kotlin, a new screen, or a new method.
- It does not replace a rebuild when the source itself must change.
- It does not ship inside `flutter_ai_whisper` or share `VmBridge`.

## Who uses it, and when

| Who | When |
| --- | --- |
| The developer | Starts the debug app once, from Android Studio or `assembleDebug`. No source edit. |
| The MCP client (Cursor or another agent host) | Starts `kotlin-runtime-mcp` on stdio when the agent session begins. |
| The agent | Calls a tool after the app is in the foreground and `adb devices` shows the emulator or phone. |
| The server | Attaches only for the duration of that tool call, then resumes the thread. |

The developer does not add a dependency. The only machine requirements are a JDK (for JDI), `adb` on `PATH`, and one debuggable process.

## Runtime sequence

Every mutating tool follows the same order.

1. **Discover.** `adb jdwp` lists process ids that are debuggable. The server drops any pid that is not on that list.
2. **Forward.** `adb forward tcp:<local> jdwp:<pid>` exposes that process on localhost.
3. **Attach.** JDI connects to the forwarded port.
4. **Suspend.** The main thread is suspended. Locals exist only in a suspended frame. Fields can be read on an object the server has a reference to.
5. **Act.** One of: read fields and stack, set one field, call one existing method, or navigate.
6. **Resume.** The thread is resumed even when the action fails.
7. **Report.** The tool returns a short text result. `isError: true` means the app was left unchanged or the action was rejected.

The server never leaves the process suspended after the tool returns.

## Design

### Process

One JVM program. Kotlin, using JDI (`com.sun.jdi`). It is not an Android library and it is not installed on the device.

```
kotlin-runtime-mcp
  bin/          MCP stdio entry, tool registration
  adb/          jdwp list, forward, device check
  session/      attach, suspend, resume, always resume on failure
  inspect/      stack, locals, fields, threads
  mutate/       set one field, call one existing method
  navigate/     route on NavController, or start an Activity
```

The session layer owns the invariant: attach only to a pid from `adb jdwp`, and resume in a `finally` block.

### Tools

| Tool | When the agent calls it | What it does |
| --- | --- | --- |
| `list_debuggable_apps` | First, and whenever the device set changes | Returns pid, package name if `adb` can resolve it, and whether the process is currently resumed |
| `read_state` | Before a write, and after one, to check the result | Suspends, returns the main-thread stack, locals in the top frame, and named fields |
| `set_field` | When a value already in memory should change | Writes one field the class already has, then reads it back |
| `call_method` | When the app already has a method that performs the change | Invokes that method on a live object |
| `navigate_to_screen` | When the agent needs a particular existing screen | Opens a route or an Activity that is already in the app |
| `watch_field` | When the agent needs to know who wrote a value | Reports the method that next assigns that field, then removes the watch |
| `threads` | When the UI is frozen | Lists threads and the top frame of each |

`set_field` and `call_method` are the memory writes. `navigate_to_screen` is navigation. The others let the agent see the result instead of guessing.

### `set_field`

Arguments:

| Argument | Required | Meaning |
| --- | --- | --- |
| `pid` | yes | Process from `list_debuggable_apps` |
| `className` | yes | Fully qualified class that declares the field |
| `field` | yes | Field name as it exists in the debug build |
| `value` | yes | New value. Strings, numbers, booleans, and `null` in the first version |
| `instance` | no | Which instance, when more than one is live. Default: the single instance, or an error if several exist |

How:

1. Resolve the class in the attached VM.
2. If the field is static, set it on the class.
3. If it is an instance field, take the only live instance, or the instance the agent named.
4. Assign through JDI. Access checks are the debugger's, so a private field in a debug build can be written.
5. Read the field back and return that value.

The write is refused when the field is `final`, when the Kotlin property is a `val` with no setter and no mutable backing field, or when R8 has renamed the field. Compose state updates only when the assigned member is the state value the UI reads (`state.value` via `call_method` on the main thread). Writing a private backing field leaves the screen stale. The tool returns the value it read back and says whether a recompose method was called.

### `call_method`

Arguments:

| Argument | Required | Meaning |
| --- | --- | --- |
| `pid` | yes | Debuggable process |
| `className` | yes | Class of the receiver |
| `method` | yes | Method that already exists |
| `arguments` | no | Values for the existing parameters |
| `instance` | no | Which instance. Same rule as `set_field` |

How: resolve the method, invoke it on the suspended main thread, return the string form of the result or the exception the app threw. The server does not invent a method.

### `navigate_to_screen`

Arguments:

| Argument | Required | Meaning |
| --- | --- | --- |
| `pid` | yes | Debuggable process |
| `screen` | yes | A route (`details/42`, `/checkout`) or an Activity class (`com.example.app.SettingsActivity`) |
| `arguments` | no | Route arguments the existing destination already accepts |

How, in order:

1. If `screen` contains a `/` or does not look like a class name, treat it as a Navigation route.
2. Find loaded classes `androidx.navigation.NavController` and `androidx.navigation.NavHostController`.
3. Take live instances. One instance: call `navigate` with `screen`. Several: use the resumed Activity's controller, or return the instance list and ask the agent to pass `instance`.
4. If `screen` is a class name ending in `Activity`, call `startActivity` on the current foreground `Activity` with that component.
5. Resume, then return `navigated` and the screen id.

The destination must already be in the navigation graph or the manifest. A missing route returns the navigator's error and does not create a destination. No `NavController` and no matching Activity returns `no-navigator` and leaves the back stack as it was.

### `read_state`, `watch_field`, `threads`

`read_state` is the check after a write and the way the agent sees a `ViewModel` without logging. `watch_field` sets a modification watch, resumes, and returns the stack of the next write, then clears the watch. `threads` is read-only.

These three are the second slice. The first slice is list, set, call, and navigate.

### Agent registration

The client starts the server. The app is not involved.

```json
{
  "mcpServers": {
    "kotlin-runtime-mcp": {
      "command": "kotlin-runtime-mcp",
      "args": []
    }
  }
}
```

An agent call:

```json
{
  "name": "navigate_to_screen",
  "arguments": {
    "pid": "24113",
    "screen": "details/42"
  }
}
```

Tool failures return `isError: true` and a reason. They do not throw out of the MCP handler. The transport stays up so the agent can read state and try a different field or screen.

### Safety

- Development only. The server executes debugger operations inside a debug app with the privileges of that app.
- Attach only to pids listed by `adb jdwp`.
- Bind the forward to localhost.
- Resume the thread on every exit path.
- Do not accept a path that patches memory in a non-debuggable process.

## Plan

Work is ordered so each phase is usable on its own. Dates are sequence, not a calendar.

### Phase 1 — Attach and read

**When:** first. Nothing else is trustworthy until a live field can be read back.

**What:** `list_debuggable_apps`, session attach/resume, `read_state` for one named field and the main-thread top frame.

**How:**

1. Create a Kotlin JVM project, separate from this Flutter repository.
2. Shell out to `adb jdwp` and `adb forward`.
3. Attach with JDI. Suspend the main thread. Read one field. Resume in `finally`.
4. Register the two tools on stdio MCP.
5. Prove it on a sample debug app that already has a `ViewModel` field `count`: launch the app, call `read_state`, confirm the number matches the screen. Install the release variant of the same app and confirm the pid is absent and the tool returns an error.

**Done when:** a debug process can be listed and a field read with no file in the sample app changed. The release process cannot be attached.

### Phase 2 — Write memory

**When:** after Phase 1's read-back matches the screen.

**What:** `set_field` and `call_method`.

**How:**

1. Set the field through JDI and return the value read back.
2. Refuse `final` and a `val` that has no mutable field.
3. Invoke one existing method on the main thread and return its result or the app exception.
4. Prove `count` changes from the tool, the following `read_state` shows the new value, and a method the app already has (a setter or `load()`) runs.

**Done when:** the agent can change one in-memory field and call one existing method, and both are visible to a later read. Release still refuses.

### Phase 3 — Open a screen

**When:** after write and call work on a known object.

**What:** `navigate_to_screen`.

**How:**

1. Instance-scan `NavController` / `NavHostController` and call `navigate`.
2. If the screen is an Activity class, `startActivity` from the foreground Activity.
3. Prove a route that is already in the sample graph opens, a missing route returns `no-navigator` or the graph error without crashing the app, and an Activity class that is already exported to the app opens.

**Done when:** the agent opens one existing route and one existing Activity. The sample source is still unchanged.

### Phase 4 — Explain a freeze or a surprise write

**When:** after the agent can read, write, and navigate.

**What:** `threads` and `watch_field`.

**How:** list thread frames; set a modification watch and return the writer stack once.

**Done when:** a blocked main thread shows its top frame, and the next assignment to a watched field names the method that wrote it.

### Later, only if a real session needs it

A host-side expression box that compiles new Kotlin and loads it into ART. That is a different product. Phase 1–4 do not include it. Hot-swapping method bodies is also out of scope: a source change still goes through a rebuild.

## How a session runs

1. The developer launches the debug build and leaves the app in the foreground.
2. The agent calls `list_debuggable_apps` and keeps the pid.
3. The agent calls `read_state` for the `ViewModel` field it cares about.
4. The agent calls `navigate_to_screen` when that screen is not showing.
5. The agent calls `set_field` or `call_method`.
6. The agent calls `read_state` again. The returned value is the proof. The screen is the proof only when the write went through a setter or a `State` value the UI observes.

## Acceptance

- No file under the target app is created or edited.
- `adb jdwp` is the only attach allowlist.
- A tool that fails still resumes the thread.
- `set_field` returns the value read after the write.
- `navigate_to_screen` opens only a route or Activity that was already in the running build.
- `dart` / Flutter tooling in this repository is unchanged. The Kotlin server is its own project.

## Risks

| Risk | What happens | Response |
| --- | --- | --- |
| Several `NavController` instances | The wrong graph is used | Return the list and require `instance` |
| Compose backing field written directly | The variable changes and the screen does not | Tell the agent to call the state setter |
| Obfuscated debug build | Field names do not match source | Return the names JDI actually sees |
| App not debuggable | pid missing from `adb jdwp` | Error, no forward, no attach |
| `adb` missing or no device | Discovery fails before JDWP | Error naming `adb devices` |

## First build

Phase 1 and Phase 2, in a new Kotlin JVM repository. The first proof is a debug app the developer already has: read `count`, set `count`, read `count` again, with no commit in that app. Navigation is Phase 3 and uses the same session.
