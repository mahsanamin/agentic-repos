# Changelog

## v1.1.1, 2026-08-05

**Summary:** Two bug fixes, a devkit skill name that does not exist, and a project-name normalisation that leaked whitespace into a directory name.

**Cost note:** None. Both are corrections to existing behaviour; no new steps, round-trips, or wall-clock time on any path.

**Fixed:**
- **`a_sk_l_review_pr` is not a real skill.** The installed devkit skill is `a_sk_review_pr`. The bad name appeared 18 times across 9 files and did not resolve to anything. It also contradicted devkit's own naming scheme, where the `l_` modifier means "local-only" and applies to routines only (`a_r_l_*`); devkit's `CLAUDE.md` states "Never write `a_sk_l_*`". Because `rules/universal/code-review.md` is part of the installable rules layer and `templates/ar-framework-hints.md` is installed to `~/.claude/`, the wrong name was being written into every adopted repo and read by every session on the machine.
- **Project names containing a space produced a malformed improvements directory.** `ar-record-improvement` Step 7 pascal-cased only snake/kebab/lower-case names; a name already starting with a capital passed through unchanged, whitespace included, so a `project.name` of "My Service" produced a directory literally named `My Service_AgenticRepos`. Whitespace is now a word separator alongside `_` and `-`, giving `My_Service_AgenticRepos`. Names already pascal or snake-cased are unaffected (`Example_Project` stays `Example_Project`). The same derivation in `ar-add-improvement` is fixed identically, the two skills resolve this directory independently and must agree on it.

**Files changed:**
- `rules/universal/code-review.md`, `templates/ar-framework-hints.md`, `CLAUDE.md`, `GUIDE.md`, `docs/ARCHITECTURE.md`, `skills/ar-taskflow-review/SKILL.md`, `skills/ar-global-pr-reviewer/SKILL.md`, `.claude/commands/ar-self-reviewer/SKILL.md`, `.claude/commands/ar-add-improvement/SKILL.md`, corrected the skill name; no logic changes.
- `skills/ar-record-improvement/SKILL.md`, replaced the case-guarded pascal-case block with a single normalisation that treats whitespace as a separator.
- `.claude/commands/ar-add-improvement/SKILL.md`, matching normalisation so both skills derive the same directory.
- `config_hints.json`, `CLAUDE.md`, version bumped to 1.1.1.

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
