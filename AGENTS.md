# Agentic Repos

**Make any repository agent-ready, so AI assistants follow the team's real way of working.**

This file is the single source of truth for working in this repository, on any harness. Claude Code
reads it through the thin root `CLAUDE.md`; Codex loads it natively.

## What This Is

This repository contains the SOURCE files for the Agentic Repos framework. It is not a project
itself: it is the AI-readiness layer (driver skills, rules, templates, procedures) that gets
INSTALLED so other repos run a consistent, safety-checked AI workflow.

Version: v1.2.0

## Depends on agentic-devkit

Agentic Repos does NOT ship its own agents, atomic commit/PR/review skills, or worktree helpers.
Those live in the separate `agentic-devkit` repo and are reused: `ar-*` skills invoke devkit agents
by name (`a_sag_code_reviewer`, `a_sag_plan_verifier`, `a_sag_commit_writer`, `a_sag_pr_writer`,
`a_sag_test_runner`, `a_sag_task_doc_writer`) and delegate atomic actions to devkit skills
(`a_sk_commit`, `a_sk_pr`, `a_sk_review_pr`, `a_sk_sonarqube_coverage`) and worktree helpers
(`a_g_worktree_*`). `./install.sh` bootstraps devkit if it is missing. See `docs/ARCHITECTURE.md`.

**Never add an agent to this repository.** A role with no devkit agent is expressed as a bounded
subagent described inline in the skill that needs it, with its rubric in the prompt. Adding an
`agents/` directory here would fork the one thing this framework deliberately does not own.

## Two layers (the whole model)

- **Global procedure** (installed once per machine by `./install.sh`, and `./install-codex.sh` for
  Codex): the `ar-*` skills are symlinked into `~/.claude/skills/` and `~/.agents/skills/`, the
  scripts into `~/.claude/scripts/` and `~/.codex/scripts/`, and the SessionStart hook plus the git
  guard are wired into `~/.claude/settings.json`. Symlinks, not copies, so a `git pull` plus a
  re-run updates everything.
- **Per-project config + rules** (written by `/ar-install`): `config_hints.json`, `AGENTS.md`, the
  stack-adapted coding rules extracted into the repo's `standards_location`, and templates. Skills
  read this at runtime, so one global copy serves every repo.

## Non-Obvious Layout Notes

- `.claude-plugin/` + `hooks/hooks.json`, the Claude Code plugin manifest and hooks. This repo IS a
  plugin marketplace: `/plugin marketplace add mahsanamin/agentic-repos` then
  `/plugin install agentic-repos` ships the `ar-*` skills + hooks, versioned. Plugin hooks use
  `${CLAUDE_PLUGIN_ROOT}`.
- `install.sh`, the shell installer for Claude Code. The alternative to the plugin, and the only way
  to get the shell-function bits a plugin cannot provide. `--no-hooks` skips hook wiring for plugin
  users.
- `install-codex.sh`, the Codex half. Links the SAME `skills/` directory into `~/.agents/skills/`,
  renders devkit agents into `~/.codex/agents/*.toml`, and registers the git guard in a repo's
  `.codex/hooks.json`. See `docs/CODEX.md`.
- `setup.md`, procedures reference consumed by the `ar-install` and `ar-upgrade` commands (not just
  human docs).
- `scripts/`, `ar-freshness`, `ar-sonarqube`, `ar-session` (the session hook + git guard), and
  `ar-lint` (the contract suites); symlinked globally by the installers. Worktree scripts are NOT
  here (they come from devkit).
- `skills/`, `rules/`, `templates/`, installable artifacts. `skills/` is symlinked global;
  `rules/`/`templates/` are adapted per-project by the installer. None are active rules for this repo.

## Safety lives in the guard, not in prompts

`scripts/ar-session/guard-default-branch.sh` is the one predicate both harnesses run, wired as a
`PreToolUse(Bash)` hook by `install.sh` for Claude Code and by `install-codex.sh` for Codex. What it
refuses is listed at the top of the script. Because it exists, the shipped permission settings can
allow `git` and `gh` wholesale.

A permission entry is a prefix match: it cannot stop `bash -c` or a rephrased command, so it is
defense in depth and never the boundary. The authoritative control is server-side branch protection.

The shipped `settings.json` and `templates/settings.template.json` follow one rule for where an entry
goes: **`deny`** when it must never run, **`ask`** when a human's answer in the moment changes the
outcome (merging a PR, deleting a branch or a volume), and **`allow`** otherwise. The allow list is
stack-neutral on purpose and is never pruned per project, so a repo that gains a second language does
not start prompting.

Changing the guard or either settings file means re-running `scripts/ar-lint/git-guard-cases.sh`,
`install-cases.sh` and `codex-install-cases.sh`.

## Version Management

**Canonical version source:** `config_hints.json` -> `framework_version` (at the framework root).
The `Version:` line in this file and in `CLAUDE.md` is kept in sync for human readability.

See `VERSIONING.md` for bump rules and which files to update.

## Writing Rules and Skills

Follow the official guidance for every supported harness:

- [Claude Code best practices](https://code.claude.com/docs/en/best-practices)
- [How Claude Code works](https://code.claude.com/docs/en/how-claude-code-works)
- [Codex custom instructions](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Codex subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)

Key principles:

- Avoid redundancy and rule echoes; keep always-loaded guidance short.
- Don't document what's inferable from code.
- Use YAML frontmatter for skills.
- Follow `ar-optimizer` optimization patterns.
- **Skills carry ZERO language/stack idioms.** They are generic procedure that defers to the
  project's installed rules plus the `config_hints` command seam. All stack-specific knowledge lives
  in `rules/`, adapted per stack by the installer. **The recurring form of this defect is a per-stack
  mapping table**, a line that maps several ecosystems to an outcome. It looks like helpful
  derivation and it is the worst case, because a skill body is installed verbatim: one such line
  ships every listed stack's vocabulary into a project that has none of them. A skill resolves from
  what the installer recorded, or asks; it never translates a stack itself.
  `scripts/ar-lint/generic-skill-lint.sh` fails on two or more ecosystems named on one line.
- **No supporting prose** (no "why this exists", origin stories, ticket/trace IDs, version-history
  markers): `ar-optimizer` check 3n enforces this.
- Prefer read-heavy, bounded subagents for exploration, verification, tests, and review. Parallel
  write agents must own disjoint files. The parent agent owns integration and the final verdict.
- In-source documentation follows `rules/universal/lean-doc-comments.md` (blocks attached to
  declarations) and `rules/universal/lean-inline-comments.md` (comments inside a body). A doc comment
  is a claim about its signature and is mechanically checkable; an inline comment has no signature to
  check against, so it is never deleted unattended. Audit with `ar-optimize-doc-comments` and
  `ar-optimize-inline-comments`.
- Documentation follows `rules/universal/lean-docs.md`: a doc earns its place only by carrying what
  the code cannot. One fact one owner, name the source rather than transcribing it, present tense
  with no change logs, delete rather than tombstone, cut rather than append. Audit with
  `ar-optimize-docs`.
- Tests follow four universal rules: `test-change-policy.md` (when an existing test may change),
  `test-scope-policy.md` (what a test asserts), `test-layer-policy.md` (which layer a new test runs
  at, the cheapest rung that can still fail for the reason the test exists), and
  `delegation-and-cost.md` (which model tier does bulk reading). Audit a suite with
  `ar-optimize-tests`.
- **An automated reviewer and an automated fixer share a round budget**, `review.max_agent_rounds`
  (default 3), defined in `rules/universal/code-review.md`. Rounds are counted from the
  `<!-- ar-review round=N -->` and `<!-- ar-fix round=N commit=SHA -->` markers each side posts, so a
  fresh session computes the same number and neither prose nor the posting account is parsed. Past
  the budget `ar-taskflow-fix-comments` stops with `ROUND CAP` and `ar-global-pr-reviewer` posts one
  summary, and a human decides whether the PR continues, splits, or changes approach. Green CI does
  not extend the budget and neither does the two sides agreeing.

## Commit attribution

Commits in this repository and in projects it installs into carry **no tool or assistant attribution
trailer**. No `Co-Authored-By` for an agent, no "generated with" footer. The commit is authored by the
developer. This is deliberate and differs from some upstream frameworks; do not reintroduce it.

## Codex Compatibility Contract

The `ar-*` skills are written once for both harnesses, so some carry Claude's vocabulary. On Codex,
translate it:

- "Task subagent" or `subagent_type` means spawn the matching custom agent from `~/.codex/agents/`.
  Where none matches, spawn a bounded default subagent carrying that agent's instructions.
- A request to launch independent agents in parallel means spawn them concurrently, wait for every
  result, and synthesize in the parent thread.
- A foreground agent is awaited before the next dependent step.
- A background test or shell task uses Codex's non-blocking process support and a bounded timeout.
- Paths under `.claude/` are compatibility data, not an instruction to invoke Claude Code. Do not run
  `claude`, `claude init`, or `claude mcp`; use Codex `/init` or `codex mcp`.

There is no generated mirror of the skills: both harnesses read the same files through symlinks, so
there is no sync step and nothing to drift. Agents are the one rendered artifact, regenerated from
agentic-devkit on every `install-codex.sh` run. Never hand-edit a file under `~/.codex/agents/`.

## Verification

- **Fast** (default for a focused change): run the contract suites your change touches, and say what
  you did not exercise.
- **Full** (installer, hook, settings, or cross-harness changes): `./install-codex.sh --check-only`,
  which syntax-checks the shipped scripts and runs every `scripts/ar-lint/*-cases.sh`.

Never describe fast mode as end to end, and never report a skipped, cached or unavailable suite as
passing.

## Development Workflow

1. Make changes to skills/rules/templates/installers.
2. Use `ar-add-improvement` to manage version updates.
3. Run the contract suites; run the full check before shipping an installer or hook change.
4. Test installation in a disposable target.
5. Commit to this repo.
6. Other projects update by running the `ar-upgrade` command.

## Incorporating Improvements (multi-team, these are non-negotiable)

When picking up recorded improvements via `ar-add-improvement`, the command's **Operating Principles**
apply (see `.claude/commands/ar-add-improvement/SKILL.md`). Summary, kept here so every session in
this repo has it in context:

- **Run it as a goal**, read the whole pending set, finish it, don't stop after one file.
- **Contradiction check FIRST**, before editing any framework file, confirm the picked improvements
  are mutually consistent and don't conflict with the framework or an open PR. Multiple teams consume
  this framework; a contradictory change has outsized blast radius. On conflict: STOP, surface both,
  ask the user which wins, reconcile, then apply.
- **Apply in dependency order**, consume `improvements/ORDER.md` / `sequence:` frontmatter;
  out-of-order application breaks dependent fixes.
- **Flag time/step cost**, if an addition adds wall-clock time, a round-trip, or a new mandatory step
  to a frequently-run path, call it out to the user and in the CHANGELOG, and prefer
  opt-in/configurable designs.
- **One PR when asked**, if an open PR already covers this work, commit to its branch and roll
  version/CHANGELOG forward in place; don't open a second PR.

## How Target Projects Use This

The global layer is installed once per machine with `./install.sh` (plus `./install-codex.sh` for
Codex). A repo is then made agent-ready by:

1. Running the `/ar-install` command (or `ar-agent-ready` to re-assess later)
2. Getting its coding rules EXTRACTED from the actual codebase and adapted to its stack via the
   Content Adaptation Pipeline, written into its `standards_location` (skills are NOT copied per
   repo; they are global)
3. Creating `config_hints.json` (identity, tracker, commands, standards_location)
4. Creating `AGENTS.md` (their single source of truth)

See `README.md` for installation instructions.
