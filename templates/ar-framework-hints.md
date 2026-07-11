# Agentic Repos, Quick Reference

You are operating on a machine with Agentic Repos installed. This file lives at `~/.claude/ar-framework-hints.md` (installed by `install.sh`) and is referenced from `~/.claude/CLAUDE.md`, so every Claude Code session picks it up. Do not edit it manually; re-run the installer to refresh.

Agentic Repos is the AI-readiness layer. It builds on **agentic-devkit**, which supplies the reusable agents (`a_sag_*`), the atomic skills (`a_sk_commit`, `a_sk_pr`, `a_sk_l_review_pr`, `a_sk_sonarqube_coverage`), and the worktree helpers (`a_g_worktree_*`). Both are installed globally.

## Global skills (available in any project)

These live at `~/.claude/skills/` (symlinks into the framework repo) and are invocable by naming the skill or via slash command.

- **ar-taskflow** (+ `-planner`, `-resume`, `-review`, `-fix-comments`, `-remember`), the task workflow from raw prompt to reviewed PR.
- **ar-agent-ready**, read a repo, extract its conventions into rules, report a readiness scorecard.
- **ar-optimizer**, audit a project's rule files for redundancy, `alwaysApply` overuse, and stale references.
- **ar-ticket-creator**, one PR-sized ticket in whatever tracker the repo declares.
- **ar-record-improvement**, capture a framework-improvement suggestion from inside any project. Writes a structured file to `_AgenticRepos/improvements/` for later triage. It is model-invocable, so capture friction the moment it surfaces.
- **ar-global-pr-reviewer**, review any GitHub PR from anywhere on the machine.

## Every session follows the agent-ready workflow (the session hook)

`install.sh` wires a **SessionStart hook** (`~/.claude/scripts/ar-session/session-start.sh`) into `~/.claude/settings.json`. In any repo that declares itself agent-ready (has `config_hints.json` / `AGENTS.md`), it injects a reminder to: read the project rules first, drive real work through `ar-taskflow`, stay off the default branch, and capture friction with `ar-record-improvement`. It is silent in non-agent-ready repos.

A **default-branch / force-push guard** (`~/.claude/scripts/ar-session/guard-default-branch.sh`) is wired as a `PreToolUse(Bash)` hook: it refuses commits/pushes on the code repo's default branch and blocks force-push.

## Worktree helpers (from agentic-devkit)

**Prefer these over raw `git worktree` commands.** They auto-cd, validate branch names, and handle a large multi-worktree topology. They are sourced into your interactive shell by agentic-devkit.

- **In an interactive terminal**, call by name: `a_g_worktree_init <branch>`, `a_g_worktree_review <pr>`, `a_g_worktree_list`, `a_g_worktree_remove <wt>`, `a_g_worktree_doctor`, `a_g_worktree_prune`, `a_g_worktree_main`, `a_g_worktree_switch <name>`.
- **From Claude Code's non-interactive Bash tool** (shell functions are not sourced), invoke the companion script directly: `bash "${AGENTIC_DEVKIT_DIR:-$HOME/agentic-devkit}"/scripts/a_g_worktree_init <branch>` (the non-interactive form does not auto-cd).

Examples:
- Instead of `git worktree add ...`, use `a_g_worktree_init feature/X`.
- Instead of `git worktree add + checkout` for a PR, use `a_g_worktree_review 123`.

Raw `git worktree` is still correct when the user asks for the canonical command, the helpers are not installed, or an exotic option is needed (`--lock`, `--detach`, etc.).

## Framework freshness

`~/.claude/scripts/ar-freshness/check.sh` is sourced from shell-rc and runs once per 24h. It nudges when the framework is behind `origin`, has been pulled but not re-installed, or has new global skills. Silent when current. Re-check on demand: `ar_check_freshness --force`.

## Project-level rules

When working in a specific project, read its `CLAUDE.md`, `AGENTS.md`, and the rules under its `standards_location` (e.g. `docs/ai-rules/`). Project-level rules override these global hints when they conflict.

## Refreshing

```
(cd "$AR_FRAMEWORK_DIR" && git pull && ./install.sh)
```

`$AR_FRAMEWORK_DIR` is exported by the framework's shell-rc block.
