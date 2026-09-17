---
alwaysApply: true
---
# Route Commit-Producing Work Through Task-Flow

**Purpose**: Coding tasks should run through the structured flow (Understand → Plan → Code → Document → Review → PR) in an isolated worktree, not as silent ad-hoc edits in the main checkout. This rule makes starting that flow a directive, not a suggestion.

## Core Rule

**When a session hands you any change that will produce a commit, a feature, a fix, or a refactor, route it through `ar-taskflow`.** Do not start editing files in the main checkout.

- `ar-taskflow` is model-invocable, but it deliberately auto-fires only on a **prepared task** (a task-folder path, `raw_prompt.md`, or a tracker ticket). For an ad-hoc change typed straight into chat it will **not** auto-start.
- So for an ad-hoc request: **state that the work should run through task-flow and start it**, or prompt the user to invoke `ar-taskflow` (or `ar-taskflow-resume` / `ar-taskflow-planner`), rather than silently making the edits.
- The work happens in a **dedicated worktree**, never a branch in the main checkout.

## Narrow Exceptions (no task-flow needed)

- Pure reads / investigation and Q&A.
- Orchestration-only work (ticket / PR triage, raw-prompt authoring).
- Explicit trivial one-liners the user said to just do.

## Routing Is Yours

`ar-taskflow` does not auto-fire on an ad-hoc chat prompt. Route the work through it yourself rather than starting ad-hoc edits in the main checkout, which skips the worktree discipline and the Understand/Plan/Review gates.
