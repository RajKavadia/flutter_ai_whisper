# AI agent documentation map

This package ships agent-facing docs for the tools that read repository-root
instruction files. One is canonical; the rest are thin pointers, so there is a
single source of truth to maintain.

| File | Audience | Relationship |
| --- | --- | --- |
| **`llms.txt`** | Any agent / LLM tooling | **Canonical.** Full guide: architecture, tools, platform matrix, scope and reachability, expression rules, rebuild semantics, state-management recipes, development workflow. |
| `AGENTS.md` | Codex, Zed, Aider, generic agents | Full guide plus agent-specific conventions and the publish checklist. |
| `CLAUDE.md` | Claude Code | Non-negotiables and verification steps. Points to `AGENTS.md`. |
| `GEMINI.md` | Gemini CLI | Non-negotiables and verification steps. Points to `AGENTS.md`. |
| `.cursorrules` | Cursor | Rules that cause real bugs. Points to `AGENTS.md`. |
| `.github/copilot-instructions.md` | GitHub Copilot | Non-negotiables and verification steps. Points to `AGENTS.md`. |
| `.kiro/steering/product.md` | Kiro | Orientation: purpose, users, constraints, non-goals, security. |
| `.kiro/steering/tech.md` | Kiro | Stack, dependency policy, runtime model, platform capability matrix, quality gates. |
| `.kiro/steering/structure.md` | Kiro | Layout, responsibilities, where new code goes, how to add a tool. |
| `.kiro/steering/runtime-rules.md` | Kiro | The non-negotiables, split by concern. Points to `AGENTS.md`. |

Kiro steering follows its own taxonomy (`product` / `tech` / `structure`), so it
is partitioned by concern rather than mirroring `AGENTS.md` wholesale. All four
carry `inclusion: always`, and the front matter must remain the first content in
each file or Kiro silently ignores the file.

## Maintaining these

`llms.txt` is the canonical document. `AGENTS.md` tracks it closely and adds
development conventions. The Kiro steering set is partitioned by Kiro's own
taxonomy. The remaining pointer files are deliberately short — they state the
rules that cause real bugs and defer the rest.

When behaviour changes, update in this order:

1. `llms.txt` and `AGENTS.md` (keep them consistent).
2. The Kiro steering set (`product`, `tech`, `structure`, `runtime-rules`).
3. `README.md`, which is the human-facing surface.
4. `CHANGELOG.md` for anything user-visible.
5. The four short pointer files, only if the changed rule is one they list.

Avoid pasting the full guide into the pointer files. They exist so an agent
loads one small file first and reads `AGENTS.md` for depth.

## The rules worth repeating everywhere

If a change touches any of these, every file above must be updated:

- `connect_to_app` needs no URI: it auto-discovers via the Dart Tooling Daemon.
  Never copy the `flutter run` URI — its path is a per-run auth code.
- The app URL is the static web server, not the VM Service.
- An expression is evaluated in exactly one library scope; visibility follows
  that library's import/export graph.
- Flutter Web cannot enumerate state (`getClassList`, `rootLib.variables` and
  `dart:mirrors` are unavailable).
- Prefer `expression` over `target`/`value`; `final` globals reject assignment.
- `evaluate` takes one expression, not statements.
- Private members require `libraryUri` — fields, classes and methods alike.
- Mutating an object does not update the view; plain fields need `setState`,
  and it rebuilds on the next frame rather than inline — and is deferred
  entirely when the page is offstage under another route.
- You can only reach what the object exposes; a getter with no setter cannot
  be assigned.