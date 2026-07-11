# Agentic Repos: Operational Guide

The day-to-day operator's guide: install it, make a repo agent-ready, run work through it, and keep a team on it. For the model behind all of this (the two layers, the devkit dependency, the session hook, rule extraction, and the feedback loop), read [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md). This guide does not restate it.

## Contents

1. [What this is](#what-this-is)
2. [Install](#install)
3. [What gets installed, and where](#what-gets-installed-and-where)
4. [The task workflow at a glance](#the-task-workflow-at-a-glance)
5. [Autonomous mode](#autonomous-mode)
6. [Making a repo agent-ready and rule extraction](#making-a-repo-agent-ready-and-rule-extraction)
7. [Customization](#customization)
8. [Team adoption](#team-adoption)
9. [Troubleshooting and FAQ](#troubleshooting-and-faq)

## What this is

Agentic Repos makes any repository agent-ready, so AI coding sessions follow your team's real conventions instead of guessing. It splits into two layers: the generic procedure (the `ar-*` skills, the shared agents, the worktree helpers, the session hook) installed once per machine, and the per-repo config plus rules that declare what each repo actually is. The procedure reads that config at runtime, so one shared copy of "how we work" serves every project.

Who it is for: engineering teams that want AI sessions to produce code that looks like their codebase, on a branch, reviewed, with a PR, every time, without each person carrying a private pile of prompts and scripts that drift.

If you have never seen the model, read the README first, then this guide is the operator's manual.

## Install

Three steps, in order: install the global layer once on your machine, make each repo agent-ready once, then work.

### 1. Global layer (once per machine)

```bash
git clone https://github.com/mahsanamin/agentic-repos ~/agentic-repos
cd ~/agentic-repos
./install.sh
source ~/.zshrc
```

`./install.sh` links the `ar-*` skills into `~/.claude/skills/` as symlinks, links the framework scripts, wires the global session hook and the default-branch guard into `~/.claude/settings.json`, wires your shell rc, and bootstraps [agentic-devkit](https://github.com/mahsanamin/agentic-devkit) (which provides the reusable agents, the atomic commit/PR/review skills, and the worktree helpers) if it is not already present. It touches no project. It is idempotent: re-run it after any `git pull` to pick up new skills and scripts.

Useful flags: `./install.sh -n` (dry run, changes nothing), `./install.sh -f` (force: repoint skill links that point elsewhere), `./install.sh -h` (help).

Requirements: `jq` (`brew install jq`), the `gh` CLI if a repo uses the GitHub tracker, and Claude Code. Restart Claude Code or start a new session afterward so it picks up the new skills and the session hook.

### 2. Make a repo agent-ready (once per repo)

From inside the project, in Claude Code:

```
/ar-install
```

It reads the codebase, extracts the repo's real conventions into rule files, writes the config seam (`config_hints.json`, `AGENTS.md`), and drops in the templates. From then on, every session in that repo is recognized as agent-ready and steered onto the workflow. See [Making a repo agent-ready](#making-a-repo-agent-ready-and-rule-extraction) for what extraction does.

### 3. Do the work

```
ar-taskflow
```

Describe a task and it runs through the flow: raw prompt, then understand, plan, code, document. On a branch. Reviewed. Following the rules extracted from your own repo. See [The task workflow](#the-task-workflow-at-a-glance).

## What gets installed, and where

Two layers, two locations. The important correction over older docs: **skills are global and are never copied into a project.** A repo gets only its config and rules.

### Global, under `~/.claude/` (written by `./install.sh`, as symlinks)

- `~/.claude/skills/ar-*`: symlinks to the `ar-*` driver skills in the framework repo. Editing a skill in the repo is live everywhere immediately.
- `~/.claude/scripts/`: symlinks to the framework scripts (`ar-freshness`, `ar-session`, `ar-sonarqube`).
- `~/.claude/settings.json`: a global `SessionStart` hook (steers every agent-ready session onto the workflow) and a `PreToolUse` default-branch and force-push guard.
- Shell rc (`~/.zshrc` or `~/.bashrc`): exports `AR_FRAMEWORK_DIR` and sources the freshness check.
- `~/.claude/ar-framework-hints.md` and a pointer block in `~/.claude/CLAUDE.md`: discovery hints for the `ar-*` catalog.
- agentic-devkit, installed alongside: the reusable agents (`a_sag_*`), the atomic skills (`a_sk_commit`, `a_sk_pr`, `a_sk_l_review_pr`, `a_sk_sonarqube_coverage`), and the worktree helpers (`a_g_worktree_*`). The `ar-*` skills invoke these by name at runtime; because devkit is global, the names resolve in every repo.

Because the whole global layer is symlinks into the source repos, updating a team is `git pull` plus a re-run of `./install.sh`. Nothing is copied per machine, so nothing drifts.

### Per repo, written by `/ar-install` (config plus rules only)

- `.claude/config_hints.json`: the repo's identity, its tracker, its `standards_location`, and the detected build/test commands. This is the seam every `ar-*` skill reads at runtime.
- `AGENTS.md`: the repo's single source of truth (build commands, structure, and the rule list).
- `CLAUDE.md`: a short pointer to `@AGENTS.md`.
- Coding rules extracted from the codebase, written into the repo's `standards_location` (for example `docs/ai-rules/`). These are the team's editable surface.
- `.claude/settings.json`: a per-repo permissive settings file, from `templates/settings.template.json` (see [Autonomous mode](#autonomous-mode)).
- `.claude/skill.config`: per-repo paths and state.
- PR and commit templates.

`/ar-install` never copies `ar-*` skills or devkit agents into the repo, and never writes the session hook or the default-branch guard (those are global, from `./install.sh`, and already cover every repo).

## The task workflow at a glance

`ar-taskflow` owns the detail; this is only the shape. Each task moves through phases:

**raw prompt -> understand -> plan -> code -> document**, on a branch, reviewed, ending in a PR.

- **Understand**: the task requirements are read (from the tracker ticket or a manual prompt), clarifying questions are asked, and an understanding is captured for approval before any code.
- **Plan**: an execution plan is written (branch name, steps) and, before you see it, cross-checked against the actual codebase by the devkit plan verifier.
- **Code**: the change is implemented on a branch following the extracted rules, tests are run, and the code is reviewed by the devkit code reviewer. Never a commit to the default branch (the global guard enforces this).
- **Document**: docs and the PR description are generated, the tracker ticket is updated if there is one, and the PR is opened.

Companion skills:

- `ar-taskflow-planner`: plan only.
- `ar-taskflow-resume`: continue a task in a new session (reads the task's summary and picks up from the last phase).
- `ar-taskflow-remember`: refresh context in the same session (re-reads the task files and rules).
- `ar-taskflow-review`: review the change before commit.
- `ar-taskflow-fix-comments`: address PR review comments.

Tracker choice is per repo, declared in `config_hints.json` under `tracker.type`: `github` (the default, via the `gh` CLI, no MCP), `jira`, `linear`, or `none`. With `none`, work from a prompt and skip tickets entirely. Skills never hardcode a tracker; they dispatch on this value. A ticket identifier is whatever that tracker uses (for example `#247` for GitHub or `PROJ-247` for Jira).

## Autonomous mode

The per-repo `.claude/settings.json` that `/ar-install` writes (from `templates/settings.template.json`) is deliberately permissive so the flow runs end to end without stopping for prompts:

- `defaultMode` is `acceptEdits`, so file edits are auto-accepted.
- The `allow` list covers the git, build, and PR operations the flow performs (`git status/diff/add/commit/push/checkout/worktree`, `gh pr`, `gh issue`, common read commands, and the `ar-*` skills).
- There is intentionally **no `ask` list**, so the flow never blocks on a routine action.
- The `deny` list blocks only genuinely destructive commands (`rm -rf`, `rm -r`, `git reset --hard`, `git clean`, `git rebase`, `git push --force`, `git push -f`).

Safety still holds: the global default-branch and force-push guard (installed by `./install.sh`) refuses commits and pushes on the default branch and blocks force-push, regardless of the permissive allow list.

**To make a repo non-autonomous:** add the operations you want to confirm to an `"ask"` array in that repo's `.claude/settings.json`. For example, adding `"Bash(git push:*)"` and `"Bash(gh pr:*)"` to `ask` makes the flow pause for your approval before it pushes or opens a PR. You can also tighten `defaultMode` or trim the `allow` list. These are ordinary Claude Code settings; edit them per repo.

## Making a repo agent-ready and rule extraction

Rule extraction is the headline capability. An AI session is only as good as the rules it is handed: a repo with no written conventions gets ad-hoc, inconsistent output. So `/ar-install` (at adoption) and `ar-agent-ready` (on demand) read the actual codebase and extract its real conventions into rules that every session then follows.

What extraction does:

1. **Explore** the codebase (delegating to devkit's codebase explorer) to learn its real structure, stack, and conventions.
2. **Extract** those conventions into rule files under the repo's `standards_location`, citing real files and using the project's own idioms in the Do/Don't examples. It extracts only what is genuinely present (naming and layout always; API, database, testing, and error-handling patterns when there is evidence for them).
3. **Adapt** the framework's universal rules and, when one exists, the matching stack rule set on top, translating every stack-specific element (package names, paths, commands) to the repo's real values.
4. **Wire** the config seam (`config_hints.json`, `AGENTS.md`) so every `ar-*` skill reads it.

The stack is detected by positive evidence, most specific first. When no curated stack matches, extraction falls back to universal rules plus the repo's own extracted conventions; it never borrows another language's rule set.

Run `ar-agent-ready` any time to re-assess a repo's readiness and refresh or expand its rules (for example after a big refactor, or when the rules have gone stale). `ar-optimizer` audits existing rule files for redundancy and staleness.

## Customization

The extracted rules in the repo's `standards_location` are the team's editable surface. Extraction gives you a strong starting point; from there the rules are yours.

- **Edit the rules directly.** Open the files under `standards_location` (for example `docs/ai-rules/project-conventions.md`) and correct anything extraction got wrong, add a convention it missed, or remove one you no longer follow. Every session reads these, so a change takes effect on the next task. Commit them like any other source: they are your team's shared standard, not private config.
- **Re-run extraction when the code moves ahead of the rules.** `ar-agent-ready` refreshes the rules from the current codebase. It is a refresh, so review its diff and keep your hand edits.
- **Adjust per-repo config.** `config_hints.json` holds the tracker choice, `standards_location`, and detected commands; `AGENTS.md` is the human-and-agent-readable source of truth. Edit either if the repo's facts change.
- **Adjust the permission posture.** See [Autonomous mode](#autonomous-mode) to make a repo non-autonomous.

Skills are global and generic on purpose. Do not put stack-specific knowledge in a skill; it belongs in the repo's rules, where extraction and your edits keep it accurate.

## Team adoption

The model is built so a team never drifts:

1. **Everyone installs the global layer once.** Each engineer clones the framework and runs `./install.sh` on their own machine. That is the whole per-person setup.
2. **A repo is made agent-ready once.** One person runs `/ar-install` in the repo and commits the resulting config and rules. Everyone else picks them up on their next `git pull`, because those files live in the repo.
3. **Updates are `git pull` plus `./install.sh`.** When the framework improves, each engineer pulls the framework repo and re-runs `./install.sh` (idempotent). Because the global layer is symlinks, there are no per-machine copies to go stale.
4. **The rules evolve with the code.** As the team refines conventions, they edit the rules in the repo (or re-run `ar-agent-ready`) and commit. The change reaches every session, for everyone, immediately.

**Feedback loop.** When a rule is wrong, a skill misfires, or a better default emerges while working in any repo, run `ar-record-improvement`. It writes a structured improvement file into the shared workspace without touching the framework directly. Later, from the framework repo, `ar-add-improvement` triages the pending set (contradiction check first, apply in dependency order, bump the version, update the CHANGELOG). That is how the framework learns from real use and rolls the improvement back out to everyone via the next `git pull` plus `./install.sh`.

## Troubleshooting and FAQ

**Skills not found (`ar-taskflow` unrecognized).**
Confirm the global layer is installed: `ls -d ~/.claude/skills/ar-taskflow`. If it is missing, run `./install.sh` from the framework root, then restart Claude Code or start a new session so it reloads skills.

**`/ar-install` says the global layer is not installed.**
`/ar-install` writes only config and rules and depends on the global layer being present (the `ar-*` skills and agentic-devkit's agents). Run `./install.sh` from the framework root once, then re-run `/ar-install` in your repo. Do not try to install the global layer from inside a project.

**Devkit agents not resolving (`a_sag_*` not found).**
`./install.sh` bootstraps agentic-devkit. If its agents are absent, re-run `./install.sh` (it will locate or clone devkit and run its installer), then restart Claude Code. You can point at an existing clone with `AGENTIC_DEVKIT_DIR=/path/to/agentic-devkit ./install.sh`.

**The session does not follow the workflow in a repo.**
The steering hook only fires in an agent-ready repo. Confirm the repo has `.claude/config_hints.json` and `AGENTS.md`; if not, run `/ar-install`. Confirm the global hook is wired: `jq '.hooks.SessionStart' ~/.claude/settings.json`. Start a fresh session (hooks run at session start).

**Code does not match the codebase's conventions.**
The rules are probably thin or stale. Re-run `ar-agent-ready` to re-extract, then edit the files under `standards_location` to fill any gap. Run `ar-taskflow-review` before committing so the devkit code reviewer checks the change against the rules.

**A commit or push to the default branch was blocked.**
That is the global default-branch guard working as intended. Work on a task branch; `ar-taskflow` creates one for you.

**The flow stops and asks for permission on routine actions.**
The repo's `.claude/settings.json` may have been tightened, or was not written by `/ar-install`. Compare it against `templates/settings.template.json`. See [Autonomous mode](#autonomous-mode).

**How do I update to a newer framework version?**
`git pull` in the framework repo, then re-run `./install.sh`. Because the global layer is symlinks, the pull alone updates the skills; re-running the installer picks up any new skills, scripts, or hook changes.

**Q: Do I need Claude Code?**
Yes, for the `ar-*` skills and the workflow. The extracted rules in `standards_location` are plain Markdown and are useful to any AI assistant that reads them, but the orchestration needs Claude Code.

**Q: Can I use this with my stack?**
Yes. Extraction reads whatever your repo actually is and writes rules from it. When there is no curated rule set for your stack, it falls back to universal rules plus your extracted conventions rather than forcing a foreign stack's rules on you.

**Q: What if we do not use a ticket tracker?**
Set `tracker.type` to `none` in `config_hints.json` and work from a prompt. GitHub is the default (via the `gh` CLI, no MCP); `jira` and `linear` are the other options.

**Q: Are skills copied into my repo?**
No. Skills are global (`~/.claude/skills/`, as symlinks). A repo gets only config and rules. This is the change from older versions of this framework, which copied skills per project.

**Q: Can I customize the workflow phases?**
The skills are global and generic on purpose, so customize behavior through the repo's rules and config rather than by forking a skill. If a genuine framework improvement emerges, capture it with `ar-record-improvement`.
