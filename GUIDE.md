# Agentic Repos: Operational Guide

The day-to-day operator's guide: install it, make a repo agent-ready, run work through it, and keep a team on it. For the model behind all of this (the two layers, the devkit dependency, the session hook, rule extraction, and the feedback loop), read [`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md). This guide does not restate it.

## Contents

1. [What this is](#what-this-is)
2. [Install](#install)
3. [What gets installed, and where](#what-gets-installed-and-where)
4. [The task workflow at a glance](#the-task-workflow-at-a-glance)
5. [Permissions, and where safety actually lives](#permissions-and-where-safety-actually-lives)
6. [Autonomous mode](#autonomous-mode)
7. [Making a repo agent-ready and rule extraction](#making-a-repo-agent-ready-and-rule-extraction)
8. [Customization](#customization)
9. [Team adoption](#team-adoption)
10. [Troubleshooting and FAQ](#troubleshooting-and-faq)

## What this is

Agentic Repos makes any repository agent-ready, so AI coding sessions follow your team's real conventions instead of guessing. It splits into two layers: the generic procedure (the `ar-*` skills, the shared agents, the worktree helpers, the session hook) installed once per machine, and the per-repo config plus rules that declare what each repo actually is. The procedure reads that config at runtime, so one shared copy of "how we work" serves every project.

It runs on Claude Code and on Codex. Both harnesses read the same skill files through symlinks, so there is no mirror to regenerate and nothing that can drift between them.

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

`./install.sh` links the `ar-*` skills into `~/.claude/skills/` as symlinks, links the framework scripts, wires the global session hook and the git safety guard into `~/.claude/settings.json`, wires your shell rc, and bootstraps [agentic-devkit](https://github.com/mahsanamin/agentic-devkit) (which provides the reusable agents, the atomic commit/PR/review skills, and the worktree helpers) if it is not already present. It touches no project. It is idempotent: re-run it after any `git pull` to pick up new skills and scripts.

Useful flags: `./install.sh -n` (dry run, changes nothing), `./install.sh -f` (force: repoint skill links that point elsewhere), `./install.sh -h` (help).

Requirements: `jq` (`brew install jq`), the `gh` CLI if a repo uses the GitHub tracker, and Claude Code or Codex. Restart the harness or start a new session afterward so it picks up the new skills and the session hook.

### 2. Codex layer (optional, once per machine)

```bash
./install-codex.sh                                  # the global Codex layer
./install-codex.sh --target /path/to/repo           # that repo's .codex layer and the git guard hook
./install-codex.sh --target-only /path/to/repo      # the repo layer only, leaves ~/.codex and ~/.agents alone
```

Run `./install.sh` first. It is what installs agentic-devkit, and `install-codex.sh` renders that devkit's agents into `~/.codex/agents/*.toml`. Both installers are idempotent, so re-run both after a `git pull`.

`install-codex.sh` symlinks the **same** `skills/` directory into `~/.agents/skills/` that `install.sh` links into `~/.claude/skills/`. One copy, two harnesses, no sync step. Agents are the only rendered artifact; never hand-edit a file under `~/.codex/agents/`.

**A fresh Codex install is unprotected until you trust the hook.** Codex requires you to review a project hook once: open `/hooks`, find the Agentic Repos protected-branch hook, and trust it. Until you do, the guard does not run and does not announce itself, and only `AGENTS.md` carries the policy, as prose. Treat a Codex install as unprotected until you have confirmed the trust step. Full detail is in [`docs/CODEX.md`](./docs/CODEX.md).

### 3. Make a repo agent-ready (once per repo)

From inside the project:

```
/ar-install
```

It reads the codebase, extracts the repo's real conventions into rule files, writes the config seam (`config_hints.json`, `AGENTS.md`), and drops in the templates. From then on, every session in that repo is recognized as agent-ready and steered onto the workflow. See [Making a repo agent-ready](#making-a-repo-agent-ready-and-rule-extraction) for what extraction does.

### 4. Do the work

```
ar-taskflow
```

Describe a task and it runs through the flow: raw prompt, then understand, plan, code, document. On a branch. Reviewed. Following the rules extracted from your own repo. See [The task workflow](#the-task-workflow-at-a-glance).

## What gets installed, and where

Two layers, two locations. The important correction over older docs: **skills are global and are never copied into a project.** A repo gets only its config and rules.

### Global, written by the installers (as symlinks)

- `~/.claude/skills/ar-*` and `~/.agents/skills/ar-*`: both are symlinks to the same `ar-*` driver skills in the framework repo. Claude Code reads the first, Codex reads the second. Editing a skill in the repo is live on both immediately.
- `~/.claude/scripts/` and `~/.codex/scripts/`: symlinks to the framework scripts (`ar-freshness`, `ar-session`, `ar-sonarqube`, `ar-lint`).
- `~/.claude/settings.json`: a global `SessionStart` hook (steers every agent-ready session onto the workflow) and the `PreToolUse` git safety guard.
- `~/.codex/agents/*.toml`: the agentic-devkit agents, rendered from their Markdown sources on every `install-codex.sh` run.
- `~/.codex/AGENTS.md`: a marker-guarded block pointing Codex at the framework.
- Shell rc (`~/.zshrc` or `~/.bashrc`): exports `AR_FRAMEWORK_DIR` and sources the freshness check.
- `~/.claude/ar-framework-hints.md`, `~/.codex/ar-framework-hints.md`, and a pointer block in `~/.claude/CLAUDE.md`: discovery hints for the `ar-*` catalog.
- agentic-devkit, installed alongside: the reusable agents (`a_sag_*`), the atomic skills (`a_sk_commit`, `a_sk_pr`, `a_sk_review_pr`, `a_sk_sonarqube_coverage`), and the worktree helpers (`a_g_worktree_*`). The `ar-*` skills invoke these by name at runtime; because devkit is global, the names resolve in every repo.

Because the whole global layer is symlinks into the source repos, updating a team is `git pull` plus a re-run of the installers. Nothing is copied per machine, so nothing drifts.

### Per repo, written by `/ar-install` (config plus rules only)

- `.claude/config_hints.json`: the repo's identity, its tracker, its `standards_location`, and the detected build/test commands. This is the seam every `ar-*` skill reads at runtime.
- `AGENTS.md`: the repo's single source of truth (build commands, structure, and the rule list).
- `CLAUDE.md`: a short pointer to `@AGENTS.md`. Repo-level guidance goes in `AGENTS.md`, never in `CLAUDE.md`, so both harnesses read the same file.
- Coding rules extracted from the codebase, written into the repo's `standards_location` (for example `docs/ai-rules/`). These are the team's editable surface.
- `.claude/settings.json`: the per-repo permission posture, from `templates/settings.template.json` (see [Permissions](#permissions-and-where-safety-actually-lives)).
- `.claude/skill.config`: per-repo paths and state.
- PR and commit templates.

`/ar-install` never copies `ar-*` skills or devkit agents into the repo, and never writes the session hook or the git safety guard (those are global, from `./install.sh`, and already cover every repo). A repo's Codex layer, which is `.codex/config.toml` plus the guard hook in `.codex/hooks.json`, comes from `./install-codex.sh --target`.

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

Other global skills, usable from any repo:

- `ar-agent-ready`, `ar-optimizer`, `ar-ticket-creator`, `ar-record-improvement`, `ar-global-pr-reviewer`.
- `ar-optimize-docs`, `ar-optimize-doc-comments`, `ar-optimize-inline-comments`, `ar-optimize-tests`. These four partition the same codebase: standalone documents, the block attached to a declaration, the comments inside a body, and what a test costs. A finding outside a skill's own half is recorded and deferred, not fixed. Nothing that only a human can judge is deleted unattended.
- `ar-sonar-sweep`, work a static-analysis backlog down to zero in bounded, reviewable batches.

Tracker choice is per repo, declared in `config_hints.json` under `tracker.type`: `github` (the default, via the `gh` CLI, no MCP), `jira`, `linear`, or `none`. With `none`, work from a prompt and skip tickets entirely. Skills never hardcode a tracker; they dispatch on this value. A ticket identifier is whatever that tracker uses (for example `#247` for GitHub or `PROJ-247` for Jira).

### When the reviewer and the fixer are both agents

`ar-global-pr-reviewer` posts review comments and `ar-taskflow-fix-comments` answers them. Left alone, two agents can trade rounds indefinitely. They share a round budget, `review.max_agent_rounds` in `config_hints.json`, default 3.

Rounds are counted from the markers each side puts in what it posts (`<!-- ar-review round=N -->` and `<!-- ar-fix round=N commit=SHA -->`), so a fresh session computes the same number and neither prose nor the posting account is parsed. Past the budget, `ar-taskflow-fix-comments` stops with `ROUND CAP` and `ar-global-pr-reviewer` posts one summary instead of a new review. A human then decides whether the PR continues, splits, or changes approach. Green CI does not extend the budget, and neither does the two agents agreeing with each other.

Within a round, a class is a shape across files, not a file. Several instances of one shape get one structural fix or one reply, never one fix each.

## Permissions, and where safety actually lives

The per-repo `.claude/settings.json` that `/ar-install` writes (from `templates/settings.template.json`) follows one rule for where an entry goes:

- **`deny`** holds only what must never run, such as `rm -rf` and `gh repo delete`.
- **`ask`** holds the operator decisions where a human's answer in the moment changes the outcome: merging or closing a PR, cutting a release, deleting a branch, a stash, a container or a volume. None of these sits on the normal task flow, so the flow still runs end to end without stopping.
- **`allow`** holds everything else. It is stack-neutral on purpose and is never pruned per project, so a repo that gains a second language does not start prompting.
- `defaultMode` is `acceptEdits`, so file edits are auto-accepted.

Codex gets the same posture from `.codex/config.toml`: `approval_policy = "on-request"` and `sandbox_mode = "workspace-write"`, which lets it edit inside the repo without asking and prompt only to leave the sandbox. The installer writes those two keys only when the file sets neither, so a project that chose its own posture keeps it.

### The git safety guard

**Safety is not in the settings file.** A permission entry is a prefix match, so it cannot stop `bash -c` or a rephrased command. The real control is `scripts/ar-session/guard-default-branch.sh`, wired as a `PreToolUse` hook by `install.sh` for Claude Code and by `install-codex.sh` for Codex. It is one script, so the two harnesses cannot enforce different policies. It refuses:

- a force-push anywhere, and `git push --all` or `--mirror`;
- `--force-with-lease` or a rebase onto a shared branch (`main`, `master`, `develop`, `staging`, `release/*`, `story/*`) or from a detached HEAD;
- a whole-tree `git checkout .` or `git restore .`;
- `git reset --hard`, `--merge` or `--keep`;
- `git clean` without a dry run;
- any commit or push that would land on the repo's default branch.

The in-progress rebase verbs (`--continue`, `--abort`, `--skip`) always pass, so a rebase can always be finished or backed out. The exact list, in the order it is checked, is at the top of the script itself.

If the hook payload cannot be read, the guard degrades by scope: it refuses git commands and allows everything else with a warning. A blanket refusal would block `ls`, and a blanket allow would drop protection on exactly the commands that need it.

The guard is a seatbelt, not a boundary. It inspects a shell string statically, so a determined command can evade it. Turn on server-side branch protection for the default branch of any repo that matters.

**To make a repo stop for more things:** add those operations to the `ask` array in that repo's `.claude/settings.json`. For example, adding `"Bash(git push:*)"` and `"Bash(gh pr:*)"` makes the flow pause for your approval before it pushes or opens a PR. You can also tighten `defaultMode`. These are ordinary harness settings; edit them per repo.

## Autonomous mode

Two separate mechanisms, and they are not the same thing.

### `/goal` and `flow.continuous`

When you explicitly ask for an unattended run ("run this with /goal", "drive it unattended"), `ar-taskflow` prints `/goal` and `/loop` blocks at the phase boundaries for you to copy and run. A skill can only produce text, so it never runs a slash command itself. What a goal buys you is completeness: the write, verify, fix loop keeps going until it is clean, without you re-nudging it. It buys you no speed and it clears no checkpoint. The plan approval between GOAL A and GOAL B is still yours.

`flow.continuous` in `config_hints.json` governs whether the final phase runs straight through instead of prompting at each step.

Both of these are unchanged. By default the skill prints no goals at all.

### `flow.autonomous` (opt-in, defaults to false)

Set `flow.autonomous: true` in a repo's `config_hints.json` and each human judgement checkpoint is instead cleared by an **independent verifier subagent** applying an explicit rubric. Three checkpoints are affected: the Phase 1 understanding review, the Phase 2 plan approval, and the pre-commit code review. The verifier runs in a fresh context, is given only the artifact and its sources, and must not be the context that wrote the artifact.

Each gate returns one of three verdicts:

- **pass**: the flow moves to the next phase, and the verdict is recorded in `execution-summary.md`.
- **repair**: the listed fixes are applied and the same gate re-runs, up to `repair_attempts` (default 2). Still not passing after that is treated as an escalation.
- **escalate**: the run stops, the blocker is written into `execution-summary.md` under an `## Escalation` heading, and a human decides. That ledger is read on resume, so a re-entered run does not raise the same escalation forever.

What turning it on means for you:

- It costs three extra fresh-context agent round-trips per task, plus any repair re-runs. On a small or well-understood change that trade is usually not worth paying.
- It implies a continuous final phase, so `flow.continuous` is forced true while it is on.
- Questions become cited assumptions. Anything derivable from the ticket or the code is written into the artifact under an `## Assumptions` heading with its source, instead of stopping to ask. Only a non-derivable, outcome-changing decision escalates.
- It does not decide mechanics. Staging, committing, pushing and opening the PR are still governed by the ordinary prompt-suppression rules, not by this flag.
- It does not widen what the git safety guard blocks, and it never skips verification. It replaces verification by a human with verification by an independent agent.
- Asking to "skip the agent" is treated as an escalation, not as permission. In autonomous mode the agent is the checkpoint, so clearing it on request would leave nothing verifying the work.

With the key absent or `false`, none of this fires and the flow behaves exactly as [The task workflow](#the-task-workflow-at-a-glance) describes.

## Making a repo agent-ready and rule extraction

Rule extraction is the headline capability. An AI session is only as good as the rules it is handed: a repo with no written conventions gets ad-hoc, inconsistent output. So `/ar-install` (at adoption) and `ar-agent-ready` (on demand) read the actual codebase and extract its real conventions into rules that every session then follows.

What extraction does:

1. **Explore** the codebase (delegating to devkit's codebase explorer) to learn its real structure, stack, and conventions.
2. **Extract** those conventions into rule files under the repo's `standards_location`, citing real files and using the project's own idioms in the Do/Don't examples. It extracts only what is genuinely present (naming and layout always; API, database, testing, and error-handling patterns when there is evidence for them).
3. **Adapt** the framework's universal rules and, when one exists, the matching stack rule set on top, translating every stack-specific element (package names, paths, commands) to the repo's real values.
4. **Wire** the config seam (`config_hints.json`, `AGENTS.md`) so every `ar-*` skill reads it.

The universal rules cover code review (including the round budget above), the three test policies (when an existing test may change, what a test asserts, and which layer a new test runs at), lean documentation, lean doc comments, lean inline comments, which model tier does bulk reading, what medium a diagram is drawn in, seed jobs versus migration jobs, and how a task flow starts up.

The stack is detected by positive evidence, most specific first. When no curated stack matches, extraction falls back to universal rules plus the repo's own extracted conventions; it never borrows another language's rule set.

Run `ar-agent-ready` any time to re-assess a repo's readiness and refresh or expand its rules (for example after a big refactor, or when the rules have gone stale). `ar-optimizer` audits existing rule files for redundancy and staleness.

## Customization

The extracted rules in the repo's `standards_location` are the team's editable surface. Extraction gives you a strong starting point; from there the rules are yours.

- **Edit the rules directly.** Open the files under `standards_location` (for example `docs/ai-rules/project-conventions.md`) and correct anything extraction got wrong, add a convention it missed, or remove one you no longer follow. Every session reads these, so a change takes effect on the next task. Commit them like any other source: they are your team's shared standard, not private config.
- **Re-run extraction when the code moves ahead of the rules.** `ar-agent-ready` refreshes the rules from the current codebase. It is a refresh, so review its diff and keep your hand edits.
- **Adjust per-repo config.** `config_hints.json` holds the tracker choice, `standards_location`, the detected commands, `review.max_agent_rounds`, and `flow.autonomous`. `AGENTS.md` is the human-and-agent-readable source of truth. Edit either if the repo's facts change.
- **Adjust the permission posture.** See [Permissions](#permissions-and-where-safety-actually-lives) to make a repo stop for more operations.

Skills are global and generic on purpose. Do not put stack-specific knowledge in a skill; it belongs in the repo's rules, where extraction and your edits keep it accurate.

## Team adoption

The model is built so a team never drifts:

1. **Everyone installs the global layer once.** Each engineer clones the framework and runs `./install.sh` on their own machine, plus `./install-codex.sh` if they use Codex. That is the whole per-person setup.
2. **A repo is made agent-ready once.** One person runs `/ar-install` in the repo and commits the resulting config and rules. Everyone else picks them up on their next `git pull`, because those files live in the repo.
3. **Updates are `git pull` plus the installers.** When the framework improves, each engineer pulls the framework repo and re-runs the installers (both are idempotent). Because the global layer is symlinks, there are no per-machine copies to go stale.
4. **The rules evolve with the code.** As the team refines conventions, they edit the rules in the repo (or re-run `ar-agent-ready`) and commit. The change reaches every session, for everyone, immediately.

One thing does not travel with a `git pull`: a Codex user has to trust the project hook in their own `/hooks` before the guard runs for them. Say so when you onboard someone.

**Feedback loop.** When a rule is wrong, a skill misfires, or a better default emerges while working in any repo, run `ar-record-improvement`. It writes a structured improvement file into the shared workspace without touching the framework directly. Later, from the framework repo, `ar-add-improvement` triages the pending set (contradiction check first, apply in dependency order, bump the version, update the CHANGELOG). That is how the framework learns from real use and rolls the improvement back out to everyone via the next `git pull` plus `./install.sh`.

## Troubleshooting and FAQ

**Skills not found (`ar-taskflow` unrecognized).**
Confirm the global layer is installed: `ls -d ~/.claude/skills/ar-taskflow` for Claude Code, `ls -d ~/.agents/skills/ar-taskflow` for Codex. If it is missing, run `./install.sh` (and `./install-codex.sh`) from the framework root, then restart the harness or open a new thread so it reloads skills.

**Codex is not enforcing anything.**
The hook is registered but untrusted. Open `/hooks` in Codex, find the Agentic Repos protected-branch hook, and trust it. Until then it does not run and does not warn you. Also confirm the repo has a `.codex/` layer: `./install-codex.sh --target /path/to/repo`.

**`/ar-install` says the global layer is not installed.**
`/ar-install` writes only config and rules and depends on the global layer being present (the `ar-*` skills and agentic-devkit's agents). Run `./install.sh` from the framework root once, then re-run `/ar-install` in your repo. Do not try to install the global layer from inside a project.

**Devkit agents not resolving (`a_sag_*` not found).**
`./install.sh` bootstraps agentic-devkit. If its agents are absent, re-run `./install.sh` (it will locate or clone devkit and run its installer), then restart the harness. You can point at an existing clone with `AGENTIC_DEVKIT_DIR=/path/to/agentic-devkit ./install.sh`. On Codex, re-run `./install-codex.sh` afterward so the agents are re-rendered into `~/.codex/agents/`.

**The session does not follow the workflow in a repo.**
The steering hook only fires in an agent-ready repo. Confirm the repo has `.claude/config_hints.json` and `AGENTS.md`; if not, run `/ar-install`. Confirm the global hook is wired: `jq '.hooks.SessionStart' ~/.claude/settings.json`. Start a fresh session (hooks run at session start).

**Code does not match the codebase's conventions.**
The rules are probably thin or stale. Re-run `ar-agent-ready` to re-extract, then edit the files under `standards_location` to fill any gap. Run `ar-taskflow-review` before committing so the devkit code reviewer checks the change against the rules.

**A git command was refused.**
That is the git safety guard. See [The git safety guard](#the-git-safety-guard) for the full list of what it refuses and why. The common cases are a commit or push that would land on the default branch (work on a task branch; `ar-taskflow` creates one) and a force-push (rewrite your own feature branch with `--force-with-lease` instead, which the guard allows).

**The flow stops and asks for permission on routine actions.**
The repo's `.claude/settings.json` may have been tightened, or was not written by `/ar-install`. Compare it against `templates/settings.template.json`. See [Permissions](#permissions-and-where-safety-actually-lives).

**The PR review and the fix loop keep going.**
They stop at `review.max_agent_rounds` (default 3). If the fixer printed `ROUND CAP`, that is the budget, not a failure: read the reviewer's summary and decide whether the PR continues, splits, or changes approach. Raising the number in `config_hints.json` is a deliberate choice, not a workaround.

**I changed a script, an installer or the guard. How do I check it?**
`./install-codex.sh --check-only` syntax-checks the shipped scripts and runs every contract suite in `scripts/ar-lint/`: `git-guard-cases.sh` (47 cases covering every refusal and every command the guard must not block), `install-cases.sh` (23 cases for `install.sh` against a disposable HOME) and `codex-install-cases.sh` (33 cases for `install-codex.sh`). It installs nothing. Run a single suite directly with `bash scripts/ar-lint/git-guard-cases.sh`.

**How do I update to a newer framework version?**
`git pull` in the framework repo, then re-run `./install.sh` (and `./install-codex.sh` if you use Codex). Because the global layer is symlinks, the pull alone updates the skills; re-running the installers picks up any new skills, scripts, or hook changes.

**Q: Do I need Claude Code?**
Claude Code or Codex. Both read the same `ar-*` skills. The extracted rules in `standards_location` are plain Markdown and are useful to any AI assistant that reads them, but the orchestration needs one of the two harnesses.

**Q: Can I use this with my stack?**
Yes. Extraction reads whatever your repo actually is and writes rules from it. When there is no curated rule set for your stack, it falls back to universal rules plus your extracted conventions rather than forcing a foreign stack's rules on you.

**Q: What if we do not use a ticket tracker?**
Set `tracker.type` to `none` in `config_hints.json` and work from a prompt. GitHub is the default (via the `gh` CLI, no MCP); `jira` and `linear` are the other options.

**Q: Are skills copied into my repo?**
No. Skills are global (`~/.claude/skills/` and `~/.agents/skills/`, both symlinks to the same directory). A repo gets only config and rules. This is the change from older versions of this framework, which copied skills per project.

**Q: Can I customize the workflow phases?**
The skills are global and generic on purpose, so customize behavior through the repo's rules and config rather than by forking a skill. If a genuine framework improvement emerges, capture it with `ar-record-improvement`.
