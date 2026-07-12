# Changelog

## v1.1.0, 2026-07-12

**Summary:** Optional, opt-in per-repo "global-layer precheck" hook so a teammate who clones an adopted repo without the machine-global layer gets an in-session install nudge instead of silent degradation.

**Cost note:** Opt-in only, the default install writes nothing and adds a single yes/no question to the `ar-install` flow. When enabled, the advisory mode (choice 2) only prints a SessionStart banner; the enforce mode (choice 3) hard-blocks edits until the layer is installed.

**Added:**
- `templates/agentic-repos-precheck.sh`, self-silencing detector for the global layer. Detects both install paths (the `install.sh` skills symlink or a plugin install) plus the devkit agents; advisory by default (exit 0), `--block` mode exits 2 for a PreToolUse wall. Points a plugin-only install at `./install.sh` for the complete layer (the plugin does not ship agentic-devkit).

**Files changed:**
- `setup.md`, added **Step: Write Global-Layer Precheck Hook (Optional, opt-in)**; carved out the narrow precheck exception in the "no per-project hooks" rule (it fires only when the global layer is absent and self-silences when present, so it never duplicates the global hooks); added a **Prerequisites** subsection to the generated `AGENTS.md`.
- `.claude/commands/ar-install/SKILL.md`, Phase 4 now offers the optional precheck step; intro reflects the opt-in exception.
- `.claude/commands/ar-upgrade/SKILL.md`, can add the opt-in precheck to an already-adopted repo on request.
- `config_hints.json`, `CLAUDE.md`, `.claude-plugin/plugin.json`, version bumped to 1.1.0.

## v1.0.0

First release of Agentic Repos, the AI-readiness layer that builds on agentic-devkit.

- **Global procedure, local config.** Driver `ar-*` skills, scripts, and hooks install once per machine. Each repo gets only its config + extracted rules via `/ar-install`. No per-repo skill/agent copies.
- **Two install paths.** A Claude Code plugin (`/plugin marketplace add mahsanamin/agentic-repos` then `/plugin install agentic-repos`, hooks fire globally at user scope), or `./install.sh` (symlinks + shell helpers a plugin cannot provide; `--no-hooks` for plugin users).
- **Depends on agentic-devkit** for reusable agents (`a_sag_*`), atomic skills (`a_sk_*`), and worktree helpers (`a_g_worktree_*`). `install.sh` bootstraps it if missing.
- **Rule extraction is first-class.** `ar-agent-ready` and `/ar-install` read the actual codebase and extract its conventions into rules, so every session follows the team's real way of working.
- **Session governance.** `install.sh` wires a global SessionStart hook that steers every session in an agent-ready repo onto the workflow, plus a default-branch / force-push guard.
- **Feedback loop.** `ar-record-improvement` (from any repo) feeds `ar-add-improvement` (in this repo) to improve the framework from real use.
- **Tracker-agnostic.** GitHub Issues by default; Jira, Linear, or none by config.
