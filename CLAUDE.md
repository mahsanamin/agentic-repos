# Agentic Repos

**Make any repository agent-ready, so AI assistants follow the team's real way of working.**

## What This Is

This repository contains the SOURCE files for the Agentic Repos framework. It is not a project itself: it is the AI-readiness layer (driver skills, rules, templates, procedures) that gets INSTALLED so other repos run a consistent, safety-checked AI workflow.

Version: v1.0.0

## Depends on agentic-devkit

Agentic Repos does NOT ship its own agents, atomic commit/PR/review skills, or worktree helpers. Those live in the separate `agentic-devkit` repo and are reused: `ar-*` skills invoke devkit agents by name (`a_sag_code_reviewer`, `a_sag_plan_verifier`, `a_sag_commit_writer`, `a_sag_pr_writer`, `a_sag_test_runner`, `a_sag_task_doc_writer`) and delegate atomic actions to devkit skills (`a_sk_commit`, `a_sk_pr`, `a_sk_l_review_pr`, `a_sk_sonarqube_coverage`) and worktree helpers (`a_g_worktree_*`). `./install.sh` bootstraps devkit if it is missing. See `docs/ARCHITECTURE.md`.

## Two layers (the whole model)

- **Global procedure** (installed once per machine by `./install.sh`): the `ar-*` skills are symlinked into `~/.claude/skills/`, the scripts into `~/.claude/scripts/`, and the SessionStart hook + default-branch guard are wired into `~/.claude/settings.json`. Symlinks, not copies, so a `git pull` + re-run updates everything.
- **Per-project config + rules** (written by `/ar-install`): `config_hints.json`, `AGENTS.md`, the stack-adapted coding rules extracted into the repo's `standards_location`, and templates. Skills read this at runtime, so one global copy serves every repo.

## Non-Obvious Layout Notes

- `.claude-plugin/` + `hooks/hooks.json`, the Claude Code plugin manifest and hooks. This repo IS a plugin marketplace: `/plugin marketplace add mahsanamin/agentic-repos` then `/plugin install agentic-repos` ships the `ar-*` skills + hooks, versioned. Plugin hooks use `${CLAUDE_PLUGIN_ROOT}`.
- `install.sh`, the shell installer (symlinks skills, installs scripts, wires hooks into `~/.claude/settings.json`, bootstraps devkit, wires shell helpers). The alternative to the plugin, and the only way to get the shell-function bits a plugin cannot provide. `--no-hooks` skips hook wiring for plugin users.
- `setup.md`, procedures reference consumed by the `ar-install` and `ar-upgrade` commands (not just human docs).
- `scripts/`, `ar-freshness`, `ar-sonarqube`, and `ar-session` (the session hook + default-branch guard); symlinked globally by `install.sh`. Worktree scripts are NOT here (they come from devkit).
- `skills/`, `rules/`, `templates/`, installable artifacts. `skills/` is symlinked global; `rules/`/`templates/` are adapted per-project by the installer. None are active rules for this repo.

## Version Management

**Canonical version source:** `config_hints.json` → `framework_version` (at the framework root).
The `Version:` line in this file's header is kept in sync for human readability.

See `VERSIONING.md` for bump rules and which files to update.

## Writing Rules and Skills

When creating or updating skills/agents/rules for this framework, follow official Claude Code guidelines:

- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices)
- [How Claude Code Works](https://code.claude.com/docs/en/how-claude-code-works)

Key principles:
- Avoid redundancy and rule echoes
- Don't document what's inferable from code
- Keep rules token-efficient
- Use YAML frontmatter for skills
- Follow ar-optimizer optimization patterns
- **Skills/agents carry ZERO language/stack idioms.** They are generic procedure that defers to the project's installed rules plus the `config_hints` command seam. All stack-specific knowledge lives in `rules/`, adapted per stack by the installer. **No supporting prose** (no "why this exists", origin stories, ticket/trace IDs, version-history markers): ar-optimizer check 3n enforces this.

## Development Workflow

1. Make changes to skills/agents/rules
2. Use `ar-add-improvement` command to manage version updates
3. Test changes by installing in a test project
4. Commit to this repo
5. Other projects can update by running the `ar-upgrade` command

## Incorporating Improvements (multi-team, these are non-negotiable)

When picking up recorded improvements via `ar-add-improvement`, the command's **Operating Principles** apply (see `.claude/commands/ar-add-improvement/SKILL.md`). Summary, kept here so every session in this repo has it in context:

- **Run it as a goal**, read the whole pending set, finish it, don't stop after one file.
- **Contradiction check FIRST**, before editing any framework file, confirm the picked improvements are mutually consistent and don't conflict with the framework or an open PR. Multiple teams consume this framework; a contradictory change has outsized blast radius. On conflict: STOP, surface both, ask the user which wins, reconcile, then apply.
- **Apply in dependency order**, consume `improvements/ORDER.md` / `sequence:` frontmatter; out-of-order application breaks dependent fixes.
- **Flag time/step cost**, if an addition adds wall-clock time, a round-trip, or a new mandatory step to a frequently-run path, call it out to the user and in the CHANGELOG, and prefer opt-in/configurable designs.
- **One PR when asked**, if an open PR already covers this work, commit to its branch and roll version/CHANGELOG forward in place; don't open a second PR.

## How Target Projects Use This

The global layer is installed once per machine with `./install.sh`. A repo is then made agent-ready by:
1. Running the `/ar-install` command (or `ar-agent-ready` to re-assess later)
2. Getting its coding rules EXTRACTED from the actual codebase and adapted to its stack via the Content Adaptation Pipeline, written into its `standards_location` (skills/agents are NOT copied per repo; they are global)
3. Creating `config_hints.json` (identity, tracker, commands, standards_location)
4. Creating `AGENTS.md` (their single source of truth)

See `README.md` for installation instructions.
