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
   b. **Run the touched-path tests**, execute the test files listed in `execution_plan.md` → "Files to change", plus any test referenced in `acceptance_criteria.json` → `verification`. Use `verify.targeted_command` from `config_hints.json` over those paths, else the project's `test_command`, else the command documented in the repo. Force-rerun if the test runner caches results.

      **Not `verify.full_command`.** This step exists to prove the *previous session* left the touched paths working, and it runs before any new code is written, so a full suite here reports mostly on code this task never went near, at full price, on the one step whose whole purpose is to be a fast smoke check. The task's one mandatory full gate is the final verification gate in `ar-taskflow` Phase 4, and resuming does not move it. Classify the diff per the **Change Scope** section of `ar-taskflow` if the previous session's changes are wider than the plan's file list.
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

   **Manual Override:** If user says "skip smoke test", **hold the note in memory, do not write it yet.** Step 6 promises that a declined resume leaves no trace in `execution-summary.md`, and the user can skip the smoke test and then answer "no" at Step 6, by which point a note written here already claims a resume that never happened, which the next resume reads as a real unverified baseline. Write it in Step 7, once the resume is confirmed: `Last Action: resumed without smoke test (user override)` so the next resume knows the baseline is unverified.

5. **Check git branch status (worktree-aware):**
   ```bash
   # Resolve the default branch, never assume "main", same idiom as ar-taskflow and
   # ar-taskflow-planner. A master-based repo would otherwise pass this check and resume
   # commit-producing work in the default worktree.
   default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
   [ -z "$default_branch" ] && default_branch=$(git remote show origin 2>/dev/null | sed -n 's/^[[:space:]]*HEAD branch: //p')
   if [ -z "$default_branch" ]; then
     candidate=$(jq -r '.default_branch // empty' .claude/config_hints.json)
     [ -n "$candidate" ] && git show-ref --verify --quiet "refs/remotes/origin/$candidate" && default_branch="$candidate"
   fi
   if [ -z "$default_branch" ]; then
     # Last local resort, before stopping the run. `git remote show origin` is a NETWORK call and
     # origin/HEAD is absent in any clone whose remote was added by hand or that CI fetched, so an
     # offline run with neither would reach the stop below through no fault of the project.
     # Removing the wrong-base bug should not turn that into a hard stop.
     # A local remote-tracking ref is not a guess: it exists because the remote has that branch.
     # Ambiguity still stops, choosing between main and master IS the wrong-base bug.
     # GUARDED, like every step above it: an unguarded run would overwrite an already-correct
     # answer, so a `develop`-based repo that merely still carries a stale `origin/main` ref would
     # be silently retargeted at `main`, the exact bug this chain exists to remove.
     has_main=$(git show-ref --verify --quiet refs/remotes/origin/main && echo 1)
     has_master=$(git show-ref --verify --quiet refs/remotes/origin/master && echo 1)
     if [ "$has_main" = 1 ] && [ -z "$has_master" ]; then
       default_branch=main
       echo "Default branch resolved to 'main' from local refs/remotes/origin/main: origin/HEAD is unset and the remote was unreachable, and no origin/master exists here, so this is unambiguous." >&2
     elif [ "$has_master" = 1 ] && [ -z "$has_main" ]; then
       default_branch=master
       echo "Default branch resolved to 'master' from local refs/remotes/origin/master: origin/HEAD is unset and the remote was unreachable, and no origin/main exists here, so this is unambiguous." >&2
     fi
   fi
   if [ -z "$default_branch" ]; then
     echo "Cannot determine the remote default branch (origin/main and origin/master are both present or both absent locally). Set it with: git remote set-head origin -a, or set .default_branch in .claude/config_hints.json when offline." >&2
     exit 1
   fi
   git branch --show-current
   ```
   - If on feature branch matching task → Good, continue
   - If on `$default_branch` → do NOT create a branch in the main checkout (commit-producing work always uses a dedicated worktree, see `task-flow-startup.md`). Locate the task's existing worktree (`git worktree list`, or the **Worktree** fields in `execution-summary.md` below), or create one with the `a_g_worktree_*` helpers and resume there.

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

   Wait for the answer before writing anything to task history. **If "no":** stop here, do **not** write the held smoke-test override note and do **not** push docs. A declined resume must leave no trace in `execution-summary.md`, or the history records a session that never continued.

7. **On "yes", record the resume, then push docs:**

   **Write the held smoke-test override note from Step 4b now, if there was one** (only here, after the user confirmed): set `execution-summary.md` → `Last Action: resumed without smoke test (user override)`.

   **📤 Push docs on resume:** push any uncommitted changes in `coding_tasks_root` (this includes the note just written). Follow the full **Push-Docs Procedure** from the ar-taskflow skill, including pull-rebase and intelligent conflict resolution for `TasksSummary/*.md` and other shared files.
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
