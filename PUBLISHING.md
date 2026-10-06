# Files that are intentionally published

| File | Why |
| --- | --- |
| `bin/`, `lib/` | The server itself. |
| `README.md` | Rendered on the pub.dev package page. |
| `CHANGELOG.md` | Required by pub.dev; shown on the version page. |
| `LICENSE` | Required by pub.dev. |
| `llms.txt` | Canonical guide for LLM/agent tooling. |
| `AGENTS.md` | Instructions for Codex, Zed, Aider and other agents. |
| `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, `.github/copilot-instructions.md` | Thin per-agent pointers. |
| `AGENT_DOCS.md` | Maintainer map of the agent docs. |
| `analysis_options.yaml` | Lints and strict-casts. |
| `example/` | Usage walkthrough. |

## Before publishing

1. Confirm `pubspec.yaml` still points at the right repository — it is set to
   `github.com/RajKavadia/flutter_ai_whisper` for `repository`,
   `issue_tracker` and `homepage`. `LICENSE` names the author.
2. Re-check that the package name is still free:
   `curl -s -o /dev/null -w '%{http_code}' https://pub.dev/api/packages/flutter_ai_whisper`
   Expect `404` for available.
3. Bump `version` and add a `CHANGELOG.md` entry.
4. Verify:

   ```console
   dart analyze
   dart test
   dart pub publish --dry-run
   ```

5. Publish:

   ```console
   dart pub publish
   ```

`pubspec.lock` is not published (pub ignores it), and `.dart_tool/`,
`build/` and `.git/` are excluded automatically.