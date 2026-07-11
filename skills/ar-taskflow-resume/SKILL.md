---
name: ar-taskflow-resume
description: Resume an ongoing task from where you left off. Use when user says "ar-taskflow-resume" or "resume task". Asks for task folder path and continues from the last phase.
disable-model-invocation: true
---

# Task Flow Resume

Resume an ongoing task by providing the task folder path.

## 🧭 Learning routing

Follow the rule at `<standards_location>/learning-routing.md` (resolve `standards_location` from `.claude/config_hints.json`): route any learning to a project rule (`docs/ai-rules/`), a framework improvement (`ar-record-improvement`), or conversational-only, never personal auto-memory.

## Prerequisites

- `.claude/skill.config` must exist (run `ar-init-skills` if missing)

## Workflow

**Trigger:** User says "ar-taskflow-resume" or "resume task"

**Steps:**

1. Read `skill.config` for paths

2. **Ask for specific task folder path:**
   ```
   Give me the path to your task folder (e.g., {tasks_folder}/{namespace}-195-my-task)
   ```

3. **Read task context:**

   Once user provides the path, read all available files:
   - `raw_prompt.md` (required - if missing, invalid task folder)
   - `prompt-understanding.md` (if exists)
   - `executive_summary.md` (if exists, 2-3 line digest, surface in your resume summary so the user remembers context fast)
   - `execution_plan.md` (if exists)
   - `acceptance_criteria.json` (if exists, primary source of "what's left")
   - `execution-summary.md` (if exists - prioritize this for state)

4a. **Determine current phase:**

   | Files Present | Phase | Next Action |
   |--------------|-------|-------------|
   | Only `raw_prompt.md` | 0 | Ask clarifying questions, create `prompt-understanding.md` |
   | + `prompt-understanding.md` | 1 | Create `execution_plan.md` |
   | + `execution_plan.md` (no code changes) | 2 | Check branch, run smoke test (step 4b), start coding. If `acceptance_criteria.json` missing, generate it from the prose AC before coding (pre-v6.1 task). |
   | + `execution_plan.md` (code changes exist) | 3 | Run smoke test (step 4b), then continue coding |
   | + `ticket.md` + `pr-description.md` | 4 | Run smoke test (step 4b), then ask about commit or archive |

4b. **MANDATORY pre-product smoke test (Phase 2+ only):**

   Before resuming any new code work, prove the previous session left the repo in a working state. Skipping this step is how regressions get buried under new commits.

   a. **Boot the project** using the project's documented dev/start command. Look in this order: `AGENTS.md` → project `README.md` → the build/script manifest. If the boot command isn't documented anywhere, ask the user once and note it in `execution-summary.md` for future resumes.
   b. **Run the touched-path tests**, execute the test files listed in `execution_plan.md` → "Files to change", plus any test referenced in `acceptance_criteria.json` → `verification`. Use the project's test command (`test_command`/`verify.full_command` from `config_hints.json`, else the command documented in the repo), force-rerun if the test runner caches results.
   c. **Re-check the JSON gate** (only if `acceptance_criteria.json` exists): for every criterion currently marked `passes: true`, re-run its `verification` step. If a previously-passing criterion now fails, the prior session left a regression, that becomes the first thing to fix, not new feature work.

   **If boot fails or any previously-green criterion fails:**

   ```
   🚧 Resume blocked, baseline is not green.

   Failures:
     - {what failed}

   Per the resume protocol, regressions must be recovered before new work.
   I'll work on these first. OK?
   ```

   **If everything is green:** state it explicitly ("Baseline green: N/N criteria still pass, smoke tests pass"), then proceed to the next failing criterion.

   **Manual Override:** If user says "skip smoke test", note it in `execution-summary.md` → "Last Action: resumed without smoke test (user override)" so the next resume knows the baseline is unverified.

5. **Check git branch status (worktree-aware):**
   ```bash
   git branch --show-current
   ```
   - If on feature branch matching task → Good, continue
   - If on main → May need to create/checkout branch

   **Cross-check against `execution-summary.md`.** If it records the worktree fields written by ar-taskflow's Pre-Product Worktree Reconciliation, **Worktree**, **Local Branch**, **Remote Branch**, **Reconciliation Result**, reconcile them against the current HEAD before doing anything:

   - If the task was in a worktree (`Worktree: true`) on a branch that **differs from the current HEAD**, do NOT blindly create a new branch. The task's code lives in another worktree. Warn the user and point them to it:
     ```
     ⚠️ This task was last running in a worktree on branch '{Local Branch}',
     but the current checkout is on '{current branch}'.

     Its code likely lives in a different worktree. Locate it with:
       git worktree list
     and relocate there (or use a_g_worktree_* helpers) before resuming -
     creating a fresh branch here would fork the work.
     ```
   - If the recorded **Local Branch** matches the current HEAD → good, you are in the right worktree, continue.
   - If `execution-summary.md` has no worktree fields (task started before this was added) → fall back to the plain branch check above.

6. **Present resumption summary:**
   ```
   Resuming task: {task_name}

   Current state:
   - Phase: {phase}
   - Branch: {branch_status}
   - Last action: {from execution-summary.md if available}

   Next step: {what will happen next}

   Ready to continue? (yes/no)
   ```

7. **📤 Push docs on resume:** After user confirms, push any uncommitted changes in `coding_tasks_root`. Follow the full **Push-Docs Procedure** from the ar-taskflow skill, including pull-rebase and intelligent conflict resolution for `TasksSummary/*.md` and other shared files.
   ```bash
   coding_tasks_root=$(dirname "$(jq -r '.paths.tasks_root' .claude/skill.config)")
   # Use context message: "resume {task_name}"
   # See the ar-taskflow skill, section Docs Auto-Push, for full procedure and conflict resolution
   ```

8. **Continue with task-flow phases:**

   Once user confirms, continue with the appropriate phase from ar-taskflow:
   - Phase 1 → Create prompt-understanding.md
   - Phase 2 → Create execution_plan.md
   - Phase 3 → Code (follow task-flow Phase 3 rules)
   - Phase 4 → Finish (create ticket.md, pr-description.md, commit)

## Quick Commands

| Say | Action |
|-----|--------|
| "ar-taskflow-resume" | Ask for task path and resume |
| "resume task" | Same as above |

## Relationship to ar-taskflow

- **ar-taskflow** = Start a NEW task (ticket-first or ticket-late)
- **ar-taskflow-resume** = Continue an EXISTING task

Both skills share the same phase definitions (0-4) and follow the same rules for coding, commits, and archiving.

## References

See the ar-taskflow skill for:
- Phase definitions and detailed steps
- Safety rules for commits
- Coding conventions
- Documentation requirements
