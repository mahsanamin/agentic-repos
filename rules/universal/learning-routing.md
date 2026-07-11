# Learning Routing, where learnings go when they surface during task-flow

This is a universal rule referenced by every skill in the `ar-taskflow` family. It governs **where new knowledge goes** when the user teaches the model something during a task-flow run.

## The non-destination: personal auto-memory

During any task-flow skill's execution, **do not read, cite, or write entries from** `~/.claude/projects/<project>/memory/`. The user has explicitly excluded it for these skills. Reasons recorded by the team:

- Personal memories accumulate over sessions and drift from current truth.
- They override deliberate framework instructions in unpredictable ways.
- They are invisible to teammates and to Claude sessions on other machines, so behaviour stops being reproducible across the team.
- They blur the line between "a project convention" (which belongs in code review) and "a personal preference" (which doesn't).

The model cannot disable the user's global auto-memory feature, but inside task-flow it must not act on personal-memory content, must not cite it as a reason for decisions, and must not write to it.

## The three valid destinations

When a learning surfaces during a task-flow skill, route it explicitly. There is no fourth option.

### 1. Project rule update

**Use when:** the learning describes "how we write code in this project", naming, module placement, testing patterns, validation rules, project-specific conventions.

**Action:**

1. Identify the project's coding-rules directory from `standards_location` in `.claude/config_hints.json` (typically `docs/ai-rules/`).
2. Propose an edit to the relevant file in that directory.
3. On user approval, edit the file and commit it on the feature branch alongside the code change.
4. Mention the rule edit in the PR description so reviewers see the convention change in context.

**Why this destination:** the rule persists in the codebase, is visible in PR review, applies to every teammate, and survives session boundaries.

### 2. Framework improvement

**Use when:** the learning describes "how the Agentic Repos itself should behave differently", a skill defect, a missing rule, a wrong default, a confusing example.

**Three-prong test** (all three must hold for the issue to be framework-level):

1. The bad behaviour came from an Agentic Repos instruction the model followed literally, not a project-specific quirk.
2. The fix is to change a framework artifact (`*/SKILL.md`, an agent prompt, a template, a default), not the target project's code.
3. Another project on the same framework version would hit the same problem.

**Action:** invoke `ar-record-improvement` (see also `ar-taskflow`'s "🔄 Framework-Defect Capture" section, which auto-detects when this destination is appropriate). The skill writes a structured improvement file to the workspace's `_AgenticRepos/improvements/` directory and auto-commits/pushes the workspace docs repo.

**Why this destination:** the improvement is visible to the whole team, captured in the workspace docs repo, and feeds into the framework maintainer's review queue.

### 3. Conversational only

**Use when:** the learning is a one-off preference for this single task that does not generalise. Examples: "use 4-space indent in this one file because it matches the surrounding code", "name this private method `validatePackageVersion` instead of `verifyPackage`".

**Action:** apply the preference in-session. Do not persist anywhere.

**Why no destination:** persisting a one-off as a project rule pollutes the rules with noise; persisting it as a framework improvement is even worse (frames a single-task choice as a system-wide change). Conversational application keeps the signal-to-noise high.

## Redirect language

If the user says "remember this" or "save this", or asks to save a personal memory during the skill, do NOT write to `~/.claude/projects/...`. Instead, redirect with explicit choices:

> "Should this become a project rule (under `docs/ai-rules/`) or a framework improvement (via `ar-record-improvement`)? Personal auto-memory isn't used inside task-flow skills."

If the user picks neither, treat it as conversational-only.

## Banner (optional, when supported)

A skill MAY surface a one-line banner at startup to make the rule visible:

> "Personal auto-memory is ignored during this skill. Learnings route to `docs/ai-rules/` (project) or `ar-record-improvement` (framework)."

This is opt-in per skill; absence of a banner doesn't relax the rule.

## Verification examples

- **User:** "Remember that we always use Lombok `@RequiredArgsConstructor` on services."
  **Model:** must NOT write to `~/.claude/projects/.../memory/`. Must offer to add the rule under `docs/ai-rules/` (e.g. `coding-conventions.md`). On yes, edit and commit on the feature branch. On no, apply for this task only.

- **User:** "The SKILL.md example for `gh pr create` is missing `--base`."
  **Model:** offers to record a framework improvement via `ar-record-improvement` (the `ar-taskflow` "🔄 Framework-Defect Capture" auto-trigger fires here). Must not write to personal memory.

- **User:** "Stop using emojis in commit messages." (User adds "save it.")
  **Model:** asks whether that's a project rule or a one-off. If project rule → edit `docs/ai-rules/`. If one-off → apply this session only.

## Regression test

With the user's `~/.claude/projects/<project>/memory/MEMORY.md` containing entries that contradict the framework (e.g. a memory saying "always commit to main"), the model must follow the framework, not the memory. The decision log should reference the framework instruction, not the memory entry.
