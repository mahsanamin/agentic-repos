---
name: ar-agent-ready
description: Assess how agent-ready a repository is and raise it. Reads the actual codebase, extracts its real conventions into rule files, wires the config seam, and reports a readiness scorecard. Say "ar-agent-ready", "make this repo agent-ready", or "extract the rules for this project".
disable-model-invocation: true
---

# Agent Ready

An AI agent is only as good as the rules it is handed. A repo with no written conventions gets ad-hoc, inconsistent output, and every engineer (human or agent) reinvents "how we do things here." This skill reads a codebase, extracts its true conventions into rules, and wires the config seam so every session afterwards follows the same process.

Run it when adopting a repo, when the rules have gone stale, or whenever output feels inconsistent with how the code is actually written.

## What "agent-ready" means (the scorecard)

A repo is agent-ready when all of these exist and are accurate:

| Dimension | Signal | Where it lives |
|---|---|---|
| **Identity + command seam** | name, namespace, tracker, platform, build/test/coverage commands | `config_hints.json` |
| **Single source of truth** | how to build, test, and run; project structure | `AGENTS.md` |
| **Extracted coding rules** | the repo's real conventions, per area, stack-adapted | `standards_location` (e.g. `docs/ai-rules/`) |
| **Workflow governance** | sessions steered onto the agent-ready workflow | the global session hook (from `install.sh`) |
| **Feedback loop** | friction gets captured, not lost | `ar-record-improvement` available |

This skill measures each, fixes what it can, and reports what is missing.

## Flow

### 1. Precheck the global layer
Confirm the global procedure is installed (this skill itself is running from `~/.claude/skills/`, and `agentic-devkit` is present). If the project has no config seam yet and this is a first-time adoption of a whole project, prefer the `ar-install` operator command, which does the full adoption. This skill is the lighter, repeatable "assess and raise readiness" pass and the rule-extraction engine `ar-install` itself leans on.

### 2. Explore the actual codebase
Delegate a structural read to `a_sag_codebase_explorer` (from agentic-devkit) via the Task tool. You need its real map, not assumptions: languages and frameworks in use, directory and module layout, test framework and how tests are structured, data layer, API conventions, error-handling patterns, naming, and the invariants that must not break. If that agent is unavailable, do the read directly with Glob/Grep/Read, but do the read: rules must describe THIS code, not generic best practice.

### 3. Read what already exists
- `config_hints.json`, `AGENTS.md`, and any files under the declared `standards_location`.
- Any pre-existing AI rule files (`CLAUDE.md`, `.cursor/rules/`, `.claude/rules/`, `docs/ai-rules/`).
Resolve `standards_location` from `config_hints.json`; if absent, propose one (`docs/ai-rules/` is a sensible default) and confirm with the user.

### 4. Extract and expand the rules
This is the core. For each convention area the codebase actually demonstrates, write or update a focused rule file under `standards_location`. Extract from evidence, not from generic templates:
- Derive each rule from patterns that recur in the real code (how controllers handle errors, how tests are named and scoped, how modules draw boundaries, how the API shapes requests/responses).
- One concern per file. State the rule and show a short real example from this repo.
- Adapt to the detected stack. If the framework ships a starting template for that stack, use it as a skeleton, then replace its placeholders with what THIS repo does.
- Do NOT invent conventions the code does not follow. If the codebase is inconsistent on something, note the dominant pattern and flag the inconsistency rather than picking arbitrarily.
Keep every rule token-efficient: no redundancy, no rule echoes, no prose about why the rule exists.

### 5. Wire / confirm the config seam
Ensure `config_hints.json` and `AGENTS.md` are present and accurate (build/test/coverage/run commands verified against the repo, tracker declared, `standards_location` set). Create or correct them. These are what the global session hook keys on to recognize the repo as agent-ready and what every `ar-*` skill reads at runtime.

### 6. De-duplicate
Run `ar-optimizer` over the rule set to catch redundancy, `alwaysApply` overuse, and stale references introduced by extraction. Reconcile its findings.

### 7. Report the scorecard
Present the readiness scorecard (each dimension: present / added / still-missing), the rule files created or updated, and any decisions left to the user (an ambiguous convention, a proposed `standards_location`, a command that could not be verified). State plainly what is now agent-ready and what still needs a human call.

## Boundaries
- This skill is stack-agnostic. All stack knowledge lives in the rules it writes, adapted to the detected stack. It hardcodes no language, framework, company, or tracker.
- Tracker-agnostic: it records whatever tracker the repo declares (github / jira / linear / none) and never assumes one.
- It extracts and proposes; the team owns the rules afterward. Rules are the project's editable surface, not framework-managed files.
