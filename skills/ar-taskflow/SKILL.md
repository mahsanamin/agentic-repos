---
name: ar-taskflow
description: Structured development workflow from raw prompt to PR. Use when user says "ar-taskflow" or provides a task folder path. Follows Raw Prompt - Understand - Plan - Code - Document flow.
disable-model-invocation: true
---

# Task Flow

Structured workflow: Raw Prompt → Understand → Plan → Code → Document

## 🔧 Configuration

**IMPORTANT:** This skill uses project-specific configuration from `.claude/config_hints.json`.

At the start of this workflow, read the configuration:

```bash
# Read project configuration
project_namespace=$(jq -r '.project.namespace' .claude/config_hints.json)
project_name=$(jq -r '.project.name' .claude/config_hints.json)
tracker_type=$(jq -r '.project.tracker.type // "github"' .claude/config_hints.json)
tracker_url=$(jq -r '.project.tracker.url // ""' .claude/config_hints.json)  # jira/linear only
platform=$(jq -r '.platform' .claude/config_hints.json)
standards_location=$(jq -r '.standards_location' .claude/config_hints.json)

# Continuous-finish settings (all optional, defaults shown)
flow_continuous=$(jq -r '.flow.continuous // false' .claude/config_hints.json)          # true = don't ask at 4i/4j/4k; run 4l monitor after PR
verify_pr_timeout=$(jq -r '.verify_pr.timeout_minutes // 30' .claude/config_hints.json) # max wait for CI/quality checks
coverage_min=$(jq -r '.verify_pr.coverage_min // ""' .claude/config_hints.json)         # e.g. 80, if set, 4l flags coverage below this
```

**Use these variables throughout the workflow:**
- Ticket format: `{project_namespace}-XXX` (e.g., "{namespace}-195", "SVC-42")
- Branch format: `feature/{lowercase(project_namespace)}-XXX-description`
- Tracker: `{tracker_type}` (`{tracker_url}` set for jira/linear), resolve ticket ops via the Tracker Dispatch Table in `<standards_location>/mcp-integration.md`
- Task folders: `{project_name}_Coding_Tasks/{platform}/`
- Coding standards: `<standards_location>` (the value of `standards_location` in `.claude/config_hints.json`, read at runtime; e.g., "docs/ai-rules", "docs/coding-standards", ".aiRules")

**Example for User Service project:**
- Tickets: SVC-XXX
- Branches: feature/svc-42-add-auth
- Tracker: `github` by default (`gh` CLI); `jira`/`linear` if the repo declares it

## 📤 Docs Auto-Push

The docs/tasks directory (`coding_tasks_root`) is a **separate git repo** from the project repo. Task files created there (raw_prompt.md, prompt-understanding.md, execution_plan.md, ticket.md, etc.) and improvement files under `{Project}_AgenticRepos/improvements/` must be pushed to avoid losing work.

**Cadence: per-edit, not per-phase.** Push immediately after each meaningful `Write` or `Edit` to any file under `coding_tasks_root` or any workspace docs directory (task folder, TasksSummary, WeeklySummaries, `{Project}_AgenticRepos/improvements/`). Phase checkpoints (📤 in the phases below) are a **backstop** that catches any push missed mid-phase, they are not the primary cadence.

**Grouping rule:** related files written in the same model step (e.g. `ticket.md` + `pr-description.md` from one `a_sag_task_doc_writer` invocation) can share one commit. Unrelated files written at different times each get their own commit.

**Same rule applies to `ar-record-improvement`**, its Step 8 commits and pushes the improvement file immediately after writing it. Don't batch.

### Push-Docs Procedure

Run this immediately after each workspace file write, and at each phase checkpoint as a backstop:

```bash
# Step 1: Commit local changes (if any)
cd "$coding_tasks_root"

if git status --porcelain | grep -q .; then
  git add -A
  git commit -m "ar-taskflow: {context_message}"
fi

# Step 2: Pull with rebase to sync remote changes
if ! git pull --rebase 2>/dev/null; then
  # Conflicts detected, resolve intelligently (see below)
  resolve_docs_conflicts
fi

# Step 3: Push
if git push; then
  echo "✓ Docs saved: {context_message}"
else
  echo "⚠️ Docs push failed, push $coding_tasks_root manually"
fi

cd -  # return to project repo
```

If `git status --porcelain` is empty (nothing changed since the last push), the procedure exits silently, no `git pull` round-trip, no push, no status line. The per-edit cadence is cheap precisely because the no-op case is fast.

### Merge Conflict Resolution

When `git pull --rebase` produces conflicts, resolve each conflicted file based on its type:

**Step 1: List conflicted files**
```bash
git diff --name-only --diff-filter=U
```

**Step 2: Resolve each file using the strategy for its type:**

---

**`TasksSummary/*.md`, Shared table file (most common conflict)**

Multiple developers add rows to the same weekly section. Both sides have valid rows that must be preserved.

Resolution approach:
1. Read the conflicted file, it will contain `<<<<<<< HEAD`, `=======`, `>>>>>>> ...` markers
2. For each conflict block:
   - Extract table rows (lines starting with `|`) from **our** side (above `=======`)
   - Extract table rows from **their** side (below `=======`)
   - Keep all unique rows from both sides, dedup by comparing the Task column value
   - Preserve section headers (`## Week Ending: ...`) from either side (they're identical)
3. Write the merged result back (no conflict markers)
4. `git add {file}`

**Example:**

Conflicted file:
```
## Week Ending: January 31, 2026

<<<<<<< HEAD
| {namespace}-195 My Task | dev@example.com | Jan 29 | - | | [Link](...) |
=======
| {namespace}-196 Their Task | teammate@example.com | Jan 29 | - | | [Link](...) |
>>>>>>> origin/main
```

Resolved:
```
## Week Ending: January 31, 2026

| {namespace}-195 My Task | dev@example.com | Jan 29 | - | | [Link](...) |
| {namespace}-196 Their Task | teammate@example.com | Jan 29 | - | | [Link](...) |
```

---

**`WeeklySummaries/**/*.md`, Per-task summary files**

Different developers create files with different names (e.g., `{namespace}-195-...md` vs `{namespace}-196-...md`). These rarely conflict. If they do (same filename edited by two people):

Resolution approach:
1. Read both sides of the conflict
2. Check if the content difference is meaningful (not just whitespace)
3. If our version has more content → keep ours: `git checkout --ours {file}`
4. If their version has more content → keep theirs: `git checkout --theirs {file}`
5. If both have unique content → manually merge: combine both into one coherent file
6. `git add {file}`

---

**Task folder files (`raw_prompt.md`, `execution_plan.md`, `prompt-understanding.md`, `ticket.md`, etc.)**

These live in unique task folders (`{namespace}-195-my-task/`) per developer. Conflicts here are extremely rare. If they occur, keep ours (the active working version):

```bash
git checkout --ours {file}
git add {file}
```

---

**Step 3: Complete the rebase after resolving all conflicts**
```bash
git rebase --continue
```

If more conflict rounds occur, repeat resolution until rebase completes.

**Step 4: Push**
```bash
git push
echo "✓ Docs saved (with merge): {context_message}"
```

### Context Messages

Per-edit pushes carry a context message that describes the specific file or pair just written. Examples:

- `"raw_prompt.md created"`, after Phase 0 sets up the task folder
- `"prompt-understanding.md updated"`, after Phase 1 captures clarifications
- `"execution_plan.md drafted"`, after Phase 2's first plan write
- `"execution_plan.md + acceptance_criteria.json"`, when the plan and JSON are written together
- `"ticket.md + pr-description.md"`, when a_sag_task_doc_writer writes both
- `"execution-summary.md: PR logged"`, after Phase 4k step 10
- `"task moved to DoneTasks"`, at Phase 5

Phase-checkpoint messages (backstop, only fire if a push was missed mid-phase) keep the existing names:

- Phase 0: `"create {task_name}"`
- Phase 1: `"understand {task_name}"`
- Phase 2: `"plan {task_name}"`
- Phase 4: `"complete {task_name}"`
- Phase 5: `"archive {task_name}"`

### Rules

- **Per-edit is the primary cadence**, phase checkpoints are the backstop. A fresh reader of this skill should understand that pushes happen continuously, not in lumps.
- Do it silently, never ask user, just show a one-line `✓ Docs saved: {context}` status (or nothing if there was nothing to push).
- Resolve conflicts autonomously using the strategies below, don't ask user unless content is ambiguous.
- If push fails after conflict resolution, warn but never block the workflow.
- If no local changes and no remote changes (`git status` + `git pull` both clean), skip silently, no status line.
- Related files written in the same model step share one commit. Unrelated files written separately each get their own commit.

## 🚨 CRITICAL SAFETY RULES - ALWAYS ENFORCE

### Rule 1: Detect Workflow Violations When User Asks to Commit

**The ar-taskflow workflow is:**
1. User starts on main branch (ar-taskflow pulls from main)
2. Create `execution_plan.md` with branch name
3. Create feature branch from main (after execution plan exists)
4. Code on feature branch
5. Commit on feature branch

**When user asks to "commit", "verify and commit", or similar:**

**STEP 1: Check current branch**
```bash
git branch --show-current
```

**STEP 2: If output is "main" or "master" → WORKFLOW VIOLATION DETECTED**

This means the user has skipped steps 2-3 above (no execution_plan.md OR didn't create branch).

**IMMEDIATELY STOP and ask:**
```
🚨 STOP: You're on the main/master branch!

The ar-taskflow workflow requires:
1. Creating execution_plan.md first
2. Creating a feature branch from that plan
3. Then committing on the feature branch

I see you're trying to commit directly to main/master, which skips this workflow.

Would you like me to help you follow the proper ar-taskflow process?
- Yes → I'll guide you through creating execution_plan.md and feature branch
- No → Please explain your situation and I can suggest alternatives
```

**STEP 3: If output is a feature branch → Safe to proceed**

The user is following ar-taskflow (execution_plan.md exists, branch was created from it).

### Rule 2: Always Ask, Never Assume

When you detect potentially unsafe situations:
- User asks to commit while on main
- Changes are staged but on main branch
- User seems to be working but no execution_plan.md exists

**Then STOP and ASK** instead of assuming what they want.

Show them the issue and let them choose how to proceed.

### Rule 3: Default to Safe Path

When in doubt, always choose the safer option:
- ✅ Check branch before any commit
- ✅ Ask user for confirmation when detecting violations
- ✅ Guide user through proper ar-taskflow
- ❌ NEVER commit to main without explicit user override
- ❌ NEVER skip the execution_plan.md → branch workflow
- ❌ NEVER assume user wants to bypass safety checks

### Rule 4: Never Fabricate, Extract or Ask

**Every concrete detail in prompt-understanding.md and execution_plan.md must come from code you actually read or from the user, never from inference, memory, or pattern-matching.**

This applies to: URLs, endpoint paths, class names, method names, table names, column names, config keys, enum values, error codes, request/response field names.

**How this fails in practice:**
- You read method bodies but skip the class-level annotation that defines the actual path or name
- You see a similar-looking value in an unrelated file and assume the target shares the same format
- You assume conventional casing or separators (underscores vs hyphens, camelCase vs kebab-case) instead of checking

**The rule:**
1. If you need a specific value (URL, class name, config key, etc.), **read the exact line of code** where it's defined
2. If you haven't read it, **go read it** before writing it into any document
3. If you can't find it in code, **ask the user**, don't guess
4. After writing a document, **spot-check concrete details** against the code you read, did you actually see that exact string?

**Red flags that you're about to fabricate:**
- Writing a value without being able to point to the file and line number where you read it
- Combining fragments from different files into a composite value that may not exist
- Using a "typical" or "conventional" format instead of the actual one
- Filling in a detail from memory or pattern-matching rather than from a tool result in this session

### Rule 5: Commit/PR Permission Posture, Deliberate, Not Faster

The "ask before commit/push/PR" prompts above are the **default (`ask`) posture**. A project may move `git add`/`commit`/`push` and `gh pr create`/`comment` from the permissions `ask` list into `allow` (an autonomous posture, set in `.claude/settings.json`). When that happens, do NOT swing to either extreme:

- ❌ Don't keep narrating "may I commit?", the human checkpoint is gone, and a question that can no longer gate anything just adds noise.
- ❌ Don't start committing frequently/noisily just because you now can.

**Under auto-allow, treat the removed prompt as "act with the care a reviewer would," not "act faster":**
- Commit **deliberately at meaningful logical checkpoints**, not after every small edit. Fewer, well-scoped commits with careful messages, the same quality bar the human "question before commit" checkpoint used to enforce, now enforced by your own judgment.
- Create PRs carefully: correct base branch (story branch vs main, see Phase 4k base detection), complete template-filled description, only when the work is genuinely PR-ready.
- Adjust narration to match: *"Committing at checkpoint: {what}"* instead of *"May I commit?"*.

**Standing project opt-in:** `flow.continuous: true` in `config_hints.json` is the project-level equivalent of the verbal "run autonomously" opt-in, Phase 4i/4j/4k proceed without their ask-prompts and Phase 4l runs after PR creation. The PreToolUse hook guarantees (no commit/push to default branch, no force-push) still apply unchanged.

**Detecting the posture:** check whether the relevant Bash/`gh` commands are in the `allow` list (e.g. read `.claude/settings.json` `permissions.allow`). If commit/push/PR are auto-allowed, follow this rule; otherwise keep the default ask-at-every-step behaviour from Rules 1-3 and the Post-Review / Phase 4k sections.

**Force-push stays forbidden regardless of posture.** Autonomy never includes rewriting pushed history (`git push --force` / `-f` / `--force-with-lease`). Note that Claude Code permission rules are prefix-matched, so a deny like `git push --force:*` won't catch a reordered `git push origin main --force`; a PreToolUse hook scanning the full command for `--force`/`-f` is the only hard guarantee.

## 🔄 Framework-Defect Capture

If during ANY phase the user corrects a behaviour that came from a framework instruction (a skill step, an example, a default), OR uses phrasing like "log this", "record this", "the skill should…", "fix this in the skill", "task-flow should…", or similar, recognise the intent. Don't wait for the user to type the literal `/ar-record-improvement` command.

**Three-prong test**, all three must hold for the defect to be framework-level:

1. The bad behaviour came from an Agentic Repos instruction the model followed literally, not from a project-specific quirk.
2. The fix is to change a framework artifact (SKILL.md, agent prompt, template, default), not the target project's code.
3. Another project on the same framework version would hit the same problem.

If any prong fails, the issue isn't framework-level. Project-specific issues (wrong import path, missing test, bad service method) route to a code fix on the feature branch, not to `ar-record-improvement`.

**Action when the test passes:**

1. Stop and describe the defect in one sentence.
2. Name the framework artifact that produced it (file + section, if you can name it).
3. Ask: *"Want me to also record this as a framework improvement via `ar-record-improvement`?"*
4. On yes, invoke `ar-record-improvement` with `description` / `category` / `target` / `priority` pre-filled from this session's context. Don't make the user re-explain what they just told you.
5. On no, apply the correction for this task only and move on.

**Do NOT auto-record without asking.** The user is the gatekeeper on what counts as framework-worthy.

This rule fires regardless of which phase we're in (Phase 1-5). The session shouldn't wait for "after the PR is done" to capture a defect noticed in Phase 2.

## Prerequisites

- `.claude/skill.config` must exist (run `ar-init-skills` if missing)
- `.claude/config_hints.json` must exist with project configuration
- **Ticket-First Approach:** the tracker for the repo's `tracker_type` is reachable (github needs `gh` authenticated; jira/linear need their MCP configured, or it will be configured during flow). If `tracker_type` is `none`, use Ticket-Late.
- **Ticket-Late Approach:** User creates task folder under `{tasks_folder}/` with `raw_prompt.md`

## 🧭 Learning routing

Follow the rule at `<standards_location>/learning-routing.md` (resolve `standards_location` from `.claude/config_hints.json`): route any learning to a project rule (`docs/ai-rules/`), a framework improvement (`ar-record-improvement`), or conversational-only, never personal auto-memory.

## 🚨 CRITICAL: Always Apply Critical Thinking

**Throughout ALL phases of ar-taskflow, follow `<standards_location>/critical-thinking.md`:**

- **Question ambiguous instructions** - "Don't worry about X" could mean many things - ASK what they mean
- **Challenge architectural violations** - Don't put code in wrong modules or break patterns
- **Verify against codebase** - Check if requested changes make sense with existing structure
- **Suggest alternatives** - Propose better approaches when you spot issues

**The cost of asking is 30 seconds. The cost of misunderstanding is hours of rework.**

## Tracker Integration Reference

**IMPORTANT:** Every ticket operation resolves through the **Tracker Dispatch Table** for the repo's `tracker_type`. Always refer to:
```
<standards_location>/mcp-integration.md
```

This file contains:
- The Tracker Dispatch Table (one row per operation, one column per `tracker.type`: github / jira / linear / none)
- The github default commands (`gh issue view`/`create`/`comment`/`close`)
- The jira/linear branches (Atlassian MCP tool names and parameters, Linear MCP)
- How to extract ticket IDs from URLs
- Request/response structure and error handling patterns

## Workflow Overview

```
         ar-taskflow
         ↓
    Choose Approach: Ticket-First OR Ticket-Late
         ↓                           ↓
    [Ticket-First Path]         [Ticket-Late Path]
    Check tracker reachable     Ask for task folder path
    (dispatch table)                 ↓
         ↓                      Read raw_prompt.md
    Ask for the issue                ↓
    (GitHub # by default)       Ask clarifying questions
         ↓                           ↓
    Fetch ticket via        Create prompt-understanding.md
    dispatch table
         ↓
    Create raw_prompt.md
         ↓                           ↓
         └──────────────────────────┘
                     ↓
    User reviews prompt-understanding ← CHECKPOINT
         ↓
    Create execution_plan.md + decide branch name
         ↓
    User reviews plan
         ↓
    Checkout branch + start coding
         ↓
    Write/Update tests for changed code
         ↓
    Run tests + ensure all pass
         ↓
    Keep execution_plan.md updated
         ↓
    Finish → commit? → ticket.md → pr-description.md
         ↓
    [If Ticket-First] Update the issue via the dispatch table:
      - github: gh issue comment / edit / close
      - jira/linear: archive old description, update, comment (MCP)
      - none: skip
         ↓
    Archive → move to {done_folder} (read from skill.config, never hardcode)
```

## 🎯 Running unattended with `/goal` (opt-in)

**Default behaviour is interactive and unchanged.** By default this skill emits **no** goals. Every phase checkpoint below (prompt-understanding review, plan approval, the acceptance-criteria gate, the commit/PR prompts) still asks the user and waits, exactly as written. Do not print or suggest `/goal` commands unless the user has explicitly opted in.

**Opt-in trigger:** only when the user explicitly says something like *"run autonomously"*, *"run this with /goal"*, or *"drive it unattended"* does this mode activate. When it does, the skill does **not** run `/goal` (or `/loop`) itself, a skill can only produce text, it cannot invoke a slash command. Instead, at each boundary below the skill **PRINTS the exact command in a labelled block for the user to copy-run** (`/goal …` for GOAL A/B; `/loop …` for GOAL C, which needs `/loop`'s self-pacing, see GOAL C). Never claim the skill auto-ran `/goal` or `/loop`.

This splits the workflow into **two sequential goals with a mandatory human gate between them.** The value of running under a goal is **completeness and perseverance** (the write→verify→fix loop runs to a clean state without the user re-nudging it), **not** speed and **not** skipping any gate.

### GOAL A, plan creation (printed at the end of Phase 1)

After `prompt-understanding.md` is written and approved (Phase 1), if the user opted in, print this block for them to run:

```
▶️ Autonomous plan creation, copy-run this to drive the plan to a verified state:

   /goal execution_plan.md has all required sections, contains no TODO or placeholder text, and a_sag_plan_verifier returns zero unresolved discrepancies
```

This goal drives the **write → verify → fix** loop. It is the **same a_sag_plan_verifier loop already defined in Phase 2 step 7**, not a second, parallel mechanism. Build and run that loop exactly once (Phase 2 step 7 is the single source of truth); the goal condition simply keeps the model iterating on it, write the plan, run a_sag_plan_verifier, fix every reported discrepancy, re-run, until the verifier comes back clean. **GOAL A auto-clears** the moment a_sag_plan_verifier reports zero unresolved discrepancies and the plan has no placeholder text.

### HUMAN GATE, plan approval (never inside a goal)

After GOAL A clears, the workflow stops at the **existing Phase 2 approval checkpoint**: the user reviews and approves `execution_plan.md`. The `/goal` flag does **not** auto-pass this gate.

**NEVER put "human approved" (or any human-judgement condition) inside a `/goal` condition.** Such a condition is not self-satisfiable by the model, so the Stop hook can never see it met, it would deadlock the run. The human approval gate stays a plain interactive checkpoint, outside any goal.

### GOAL B, execution → PR (printed after plan approval)

Only after the user has approved the plan, if the user opted in, print this block:

```
▶️ Autonomous execution → PR.

   First switch the session to 'auto' permission mode (so the ask-gated
   `git commit` / `git push` / `gh pr create` proceed without per-command prompts),
   then copy-run:

   /goal every step in execution_plan.md is implemented and checked off, the project compiles, a_sag_test_runner reports all tests green, a commit exists on the feature branch, and the PR is created
```

GOAL B should run under the **`auto` permission mode** so the normally ask-gated `git commit` / `git push` / `gh pr create` proceed without a prompt per command. A skill cannot switch permission mode either, so the printed block tells the **user** to switch to `auto` before running the command (above).

**The B2 PreToolUse hook still fires under `auto`.** Switching to `auto` removes the per-command *prompts*, not the hard guarantee, committing/pushing to the default branch stays blocked by the PreToolUse hook, and force-push stays forbidden, exactly as described in **Rule 5 ("Commit/PR Permission Posture") and its PreToolUse-hook hard guarantee** above. Autonomy never widens what the hook blocks.

### GOAL C, PR verification loop (printed after the PR is created)

If the user opted in (or `flow.continuous: true`), print this block right after 4k returns the PR URL:

```
▶️ Autonomous PR verification, copy-run this to drive the PR to green.
   This one uses /loop (not /goal): the CI + quality round takes ~20-30 min, and
   only /loop's dynamic self-pacing lets the session sleep between checks instead
   of pinning a single turn open for the whole wait.

   /loop drive PR #{number} to verified-green per ar-taskflow Phase 4l, all checks concluded green, quality gate passed, coverage reported (and ≥ verify_pr.coverage_min if configured), zero unresolved review comments
```

**Why `/loop`, not `/goal`, for this one (and how it still "keeps GOAL C").** A Stop-hook `/goal` provides perseverance but has **no delay primitive**, between CI checks it either re-invokes immediately (busy-loop) or forces the model to block one turn for the full ~30-minute wait (the old in-turn 4l design). `/loop` **dynamic mode** gives the model `ScheduleWakeup`, so each pass checks once and then *yields the turn* until the next check, cache-warm, interruptible, and cheap. GOAL C's purpose is unchanged (persevere until the PR is green); the loop's continue-until-done is what now carries it, and the success condition is identical. **Phase 4l is the single source of truth** for the procedure; the loop only paces and persists. The 4l iteration cap still applies, on cap or timeout, the loop ends and surfaces what remains instead of looping forever.

(Users who prefer the Stop-hook semantics can still run the equivalent `/goal PR #{number}: …` form, but it cannot insert inter-check delays, it will pin a turn for the CI wait. `/loop` is recommended for 4l specifically.)

**Everything in this section is opt-in.** Absent the explicit opt-in (verbal or `flow.continuous: true`), ignore it entirely and run the default interactive workflow with every gate intact.

## Phase 0: Choose Approach

**Trigger:** User says "ar-taskflow"

**Steps:**

1. **Read configuration and derive paths**

   ```bash
   # Read user config (absolute paths)
   tasks_root=$(jq -r '.paths.tasks_root' .claude/skill.config)
   docs_root=$(jq -r '.paths.docs_root' .claude/skill.config)

   # Read project hints (platform)
   platform=$(jq -r '.platform' .claude/config_hints.json)

   # Derive all paths at runtime
   coding_tasks_root=$(dirname "$tasks_root")
   tasks_folder="$tasks_root/OnGoingTasks"
   done_folder="$tasks_root/DoneTasks"
   task_summary_folder="$coding_tasks_root/TasksSummary"
   weekly_summaries_folder="$coding_tasks_root/WeeklySummaries"
   ```

2. **Validate and create directories**

   Check that required files exist:
   - `.claude/skill.config` must exist
   - `.claude/config_hints.json` must exist

   **Auto-create directories if missing:**
   ```bash
   mkdir -p "$tasks_folder"
   mkdir -p "$done_folder"
   mkdir -p "$task_summary_folder"
   mkdir -p "$weekly_summaries_folder"
   ```

   **If required files are missing:**
   ```
   ⚠️ Missing required configuration.

   Please run "ar-init-skills" to configure your paths.
   ```

3. **Ask user to choose workflow approach:**

```
How would you like to start this task?

1. **Ticket-First Approach** - Start from an existing issue in your tracker
   - I'll fetch the issue description and create raw_prompt.md for you
   - Best when you already have an issue with details (a GitHub issue by default, or a Jira/Linear key if that is the repo's tracker)

2. **Ticket-Late Approach** - Start from a task folder you've already created
   - You've already created raw_prompt.md manually
   - Optionally fetch issue details later via the Tracker Dispatch Table
   - Best for quick tasks, when the issue doesn't exist yet, or when `tracker_type` is `none`

Which approach? (1 or 2)
```

### Path 1: Ticket-First Approach

If user chooses ticket-first, resolve every tracker step via the **Tracker Dispatch Table** (`<standards_location>/mcp-integration.md`) for the repo's `tracker_type` (defaults to `github` when unset). If `tracker_type` is `none`, there is no tracker to fetch from: tell the user and switch to the ticket-late approach.

**Check the tracker is reachable** (dispatch table "Check configured" row):
- **github (default):** `gh auth status` (already authenticated in most setups; run `gh auth login` if not)
- **jira:** `claude mcp list | grep atlassian`; if missing, offer to set it up: `claude mcp add --scope user --transport http atlassian https://mcp.atlassian.com/v1/mcp` (opens the browser to authenticate)
- **linear:** confirm the Linear MCP is configured

If the tracker is not reachable, tell the user how to configure it (command above) and wait for confirmation, or accept "skip" to switch to the ticket-late approach.

**Fetch the issue:**
1. Ask: "What's the issue? A GitHub issue number or URL by default (e.g., `#247`), or a Jira/Linear key (e.g., `{project_namespace}-XXX`) if that is the repo's tracker."
2. Extract the issue id from a URL if needed (see `<standards_location>/mcp-integration.md` for URL parsing).
3. Fetch it via the dispatch table "Fetch ticket" row for your `tracker_type`: `gh issue view {n} --json title,body,labels,state` for github, `mcp__atlassian__getJiraIssue` for jira, the Linear MCP for linear (see mcp-integration.md for exact usage).
4. Automatically create task folder: `{tasks_folder}/{TicketID}-{sanitized-title}/`
5. Inform user: "Created task folder at {tasks_folder}/{TicketID}-{sanitized-title}/"
6. Create `raw_prompt.md` with the issue description:
   ```markdown
   # {Issue Title}

   **Issue:** {issue link, per the dispatch table "Ticket link format" row: `#{number}` for github, the browse URL for jira, the issue URL for linear}
   **Type:** {Issue Type, if the tracker provides one}
   **Priority:** {Priority, if the tracker provides one}

   ## Description

   {Issue Description}

   ## Acceptance Criteria

   {Acceptance Criteria if available}

   ---
   *Fetched from the tracker on {date}*
   ```

7. **📤 Push docs checkpoint:** Run push-docs procedure with `"create {task_name}"`, saves raw_prompt.md to remote.

8. Proceed to Phase 1

### Path 2: Ticket-Late Approach

If user chooses ticket-late:

**Steps:**
1. Ask user: "Give me the path to your task folder"
2. Verify `raw_prompt.md` exists in that folder
3. Read `raw_prompt.md`
4. **📤 Push docs checkpoint:** Run push-docs procedure with `"create {task_name}"`, saves any uncommitted task files.
5. Proceed to Phase 1

## Phase 1: Prompt Understanding

**After reading raw_prompt.md:**

### Step 1a: Raw Prompt Quality Check

Before doing anything else, read `raw_prompt.md` and assess whether you can clearly understand what needs to be done.

**First, identify the task type:**

**Tech debt task** (refactor, remove, rename, migrate, clean up, deprecate, fix a bug):
- Technical references are expected and fine, class names, column names, table names, file paths
- The bar is simply: is the intent clear? e.g., "remove column `city_code` from `orders` and update impacted APIs and classes" is a perfectly valid raw_prompt
- Short and terse is fine. It doesn't need to explain *why*, tech debt is self-evidently technical

**Feature / product task** (new functionality, changed behaviour, user-facing work):
- Should be readable without knowing the codebase
- The *what* and *why* should be clear, what problem is being solved, what the outcome is
- Technical class names and file paths are noise here; business context matters more
- Short is still fine: "users should be able to filter products by price range" is a perfect raw_prompt

**Regardless of type, the prompt fails if:**
- The intent is genuinely unclear or ambiguous (you can't tell what needs to change)
- It's a wall of implementation details with no clear goal
- It mixes multiple unrelated tasks without indicating priority

**If the prompt fails:**

1. Tell the engineer specifically what's unclear, quote the confusing parts:
   ```
   Your raw_prompt is hard to follow in a few spots.

   For example:
   - [quote the specific unclear parts]

   I'll rewrite it to make the intent clearer while keeping all your information.
   Here's what I'm planning to change:
   - [brief list of changes]

   OK to rewrite?
   ```

2. On confirmation:
   - Preserve ALL intent, don't drop any requirement or context
   - For tech debt: keep technical references, just make the goal sentence clear
   - For features: translate class/method names to what they *do*, surface the business problem
   - **Overwrite `raw_prompt.md`** with the improved version
   - Show the result and continue:
     ```
     Updated raw_prompt.md:

     ---
     [rewritten content]
     ---

     Proceeding with Phase 1...
     ```

3. If the prompt is clear, proceed silently, no comment needed.

**Runs in main session (full context needed for clarifying questions).**

**Steps:**
1. Reads and analyzes raw_prompt.md
2. Reads relevant code to verify claims and understand current state
3. **Asks clarifying questions directly in chat (MANDATORY, do NOT skip)**
   - After reading the code, surface any questions, ambiguities, or assumptions
   - Even if the prompt seems perfectly clear, confirm with the user before proceeding
   - If you genuinely have zero questions, explicitly say: "I've read the code and raw prompt, no clarifying questions. Proceeding to create prompt-understanding.md."
   - **Never silently skip this step.** The purpose is to catch misunderstandings BEFORE writing prompt-understanding.md, not after.
4. Identifies applicable coding rules (see "Rule Detection" section)
5. **Verify all concrete details before writing (Rule 4: Never Fabricate):**
   - Apply Rule 4 (see Critical Rules section), confirm every URL, class name, or config value against the exact source code line before including it
6. Creates prompt-understanding.md with:
   - Cleaner, refined version of requirements
   - Same size as original, just easier to understand
   - Product-level focus (no code noise)
   - `## Applicable Rules` section
   - **`## Change Class` field (required):** one of `BEHAVIOR_PRESERVING` | `CONTRACT_CHANGING` | `FEATURE` (see `test-change-policy.md`). This drives the Phase 3 test policy, behaviour-preserving work must NOT edit existing tests. If unclear from the prompt, ask the user. Carried forward into `execution_plan.md`; a_sag_plan_verifier checks it against the planned file list.
7. **Self-reviews prompt-understanding.md (Rule 4 check):**
   - Re-read what you just wrote
   - For every concrete detail (URL path, class name, config key, field name, etc.), ask: "Can I point to the exact file and line where I read this?"
   - If yes, keep it
   - If no, go read the source now, then fix or remove the detail
   - This step is non-negotiable. Do not present the document to the user until this check passes.

8. **Conditionally create `executive_summary.md` (2-3 line standup digest):**

   This is an **optional artifact**, generated only when raw_prompt.md is verbose or AI-generated-looking. The purpose: a one-glance digest that gets prepended to the issue description and PR body, so a colleague in standup or skimming the ticket gets the picture instantly without reading a wall of text.

   **Trigger heuristic**, evaluate `raw_prompt.md` for these signals:

   | # | Signal | What to count |
   |---|---|---|
   | 1 | **Length** | > 40 lines OR > 500 words |
   | 2 | **Heavy structure** | > 5 markdown headers, OR > 3 levels of list nesting, OR > 8 top-level list items |
   | 3 | **Hedging / filler vocabulary** | 3+ occurrences of: "comprehensive", "robust", "leverage", "facilitate", "seamless", "various", "ensure", "enable", "delightful", "intuitive", "it should be noted", "please note", "consider that", "in order to" |
   | 4 | **Paragraph uniformity** | 3+ paragraphs that are similar in length AND sentence structure (rhythmic, repetitive cadence) |
   | 5 | **Meta-commentary** | Explicit "Why this matters" / "Key considerations" / "Importance" / "Benefits" sections beyond what the task actually needs |

   **Rule:** If **≥3 signals fire**, create `executive_summary.md`. Otherwise skip.

   **User overrides** (check the Phase 1 chat history and `raw_prompt.md`):
   - User says "skip summary" / "no exec summary" / "no summary needed" → force-skip regardless of signals
   - User says "force summary" / "make a summary" / "add exec summary" → force-create regardless of signals

   **Generation rules** when triggered:
   - **Source:** derive from `prompt-understanding.md` (the refined, clarified version), NOT raw_prompt.md
   - **Length:** strictly 2-3 sentences, ~30-50 words total. Hard ceiling.
   - **Content:**
     - Sentence 1: WHAT changes (in product terms)
     - Sentence 2: WHY (the problem being solved / user value)
     - Optional sentence 3: WHERE this lands (service, surface, audience affected)
   - **Forbidden:**
     - Marketing language ("improves user experience", "delightful", "robust")
     - Acceptance criteria, file paths, class names, code references
     - Headers, bullets, or any markdown formatting INSIDE the summary (plain prose only)
     - Hedging vocabulary from signal #3 above
   - **Required:** must be immediately understandable to a non-engineer reading standup notes

   **Examples:**

   ✅ Good:
   ```
   Add a password reset endpoint so users can recover accounts without contacting support. Closes a top-3 support-volume issue. Lands in user-service; affects mobile and web login flows.
   ```

   ❌ Bad (marketing tone, hedging, > 3 sentences):
   ```
   This task aims to comprehensively address user pain points around account recovery by implementing a robust password reset flow that leverages secure tokens to ensure a seamless user experience. Various considerations have been taken into account including security and usability. This will significantly improve the overall user journey.
   ```

   **File header:**
   ```markdown
   # Executive Summary

   {2-3 sentences here}

   ---
   *Auto-generated in Phase 1 because raw_prompt.md triggered N/5 AI-verbose signals: {list which ones fired}. Edit if it misses the point.*
   ```

   The footer note (which signals fired) makes the heuristic auditable, the user can tell why it triggered and tune their next raw_prompt if desired.

   **Drift policy:** If a Change Log entry in `execution_plan.md` records a meaningful intent change post-Phase-2, regenerate this file. Don't carry forward a stale summary.

9. Creates execution-summary.md for session recovery

**Checkpoint:** Ask user:
```
prompt-understanding.md is ready.

Does this capture your requirements correctly?
- Yes → Proceed to Phase 2
- No → What needs adjustment?
```

**Important:** Keep `raw_prompt.md` unchanged. All refinements go to `prompt-understanding.md`.

**Trigger for Phase 2:** User says "looks good", "approved", "correct", or similar confirmation.

**📤 Push docs checkpoint:** After user approves, run push-docs procedure with `"understand {task_name}"`, saves prompt-understanding.md, execution-summary.md, and (if it was generated) executive_summary.md.

**🎯 If (and only if) the user opted into autonomous mode** (see "Running unattended with `/goal`" above): now print the **GOAL A** block for the user to copy-run. This drives the Phase 2 plan write→verify→fix loop to a verified state. Skip this entirely in the default interactive run.


## Phase 2: Plan

**After user approves prompt-understanding.md:**

**Runs in main session (needs deep codebase exploration).**

**Steps:**
1. Read prompt-understanding.md
2. Explore codebase to understand structure
3. Read applicable coding rules
4. Design implementation approach
5. Create execution_plan.md with:
   - Summary
   - Approach and trade-offs
   - Files to change (implementation + tests + docs)
   - Test plan
   - Database schema details (full SQL if applicable)
   - **Documentation updates** (REQUIRED section)
   - Acceptance criteria
   - Branch name: `feature/{namespace}-XXX-description`
   - **NO time estimates**

6. **Create `acceptance_criteria.json` (MANDATORY, machine-checkable mirror of the prose AC):**

   The "Acceptance criteria" section in `execution_plan.md` is the **canonical, human-readable** source, that's what the team reviews. `acceptance_criteria.json` is its **machine-checkable mirror**, generated from the same items, locked at plan approval, and used by Phase 3/4 gates.

   Both files live side by side. The JSON is not a replacement, it is the version Phase 4's gate can read programmatically and Phase 3 can flip per-criterion. Prose stays for humans; JSON stays for the harness.

   **Drift policy:** If the prose AC changes via Change Log post-approval, regenerate `acceptance_criteria.json` and **reset `passes: false`** for any row whose `description` or `verification` changed. New verifications must be earned again, never inherit a green flag through a spec change.

   **Path:** `{task_folder}/acceptance_criteria.json`

   **Schema:**
   ```json
   {
     "task": "{ticket_id_or_task_name}",
     "branch": "feature/{namespace}-XXX-description",
     "locked_at": "{YYYY-MM-DD when plan was approved}",
     "criteria": [
       {
         "id": "AC-1",
         "description": "User-visible behaviour or guarantee in plain language",
         "verification": "Exact step that proves it, test name, curl command, UI flow, or query",
         "passes": false
       }
     ]
   }
   ```

   **Rules for filling it in:**
   - One row per independently verifiable behaviour (no compound "X and Y" rows)
   - `description` is product-level, what an end user or API caller observes
   - `verification` is concrete, "TestClass.testMethodName passes", "POST /v1/x returns 201 with body matching schema Y", "manual: click button, assert toast appears". If it's not concrete enough that someone else could reproduce it, rewrite it.
   - All rows start with `passes: false`
   - Aim for 3-10 rows. If you have 20+, you're either splitting too fine or the task is too large to be one flow.

   **Strong constraints (state these explicitly to yourself before continuing):**
   - After Phase 2 approval, the `id`, `description`, and `verification` fields are **immutable**, they may not be edited, removed, or weakened without the user explicitly approving a Change Log entry.
   - In Phase 3 and 4, the **only** field the model is permitted to mutate is `passes` (false → true), and only after the `verification` step has actually been executed and observed to succeed in this session.
   - Tests referenced in `verification` may not be deleted, skipped, or weakened. If a verification step is wrong, fix the criterion via the Change Log, do not silently rewrite the test.

7. **Run a_sag_plan_verifier agent (foreground, MANDATORY before showing plan to user):**

   **🤖 INVOKE AGENT: a_sag_plan_verifier (Opus)**

   The a_sag_plan_verifier cross-checks every concrete claim in execution_plan.md against the actual source code. This catches fabricated URLs, missed external API calls, wrong config keys, and insufficient seed data, mistakes the plan author has blind spots about.

   1. Invoke `a_sag_plan_verifier` via the Task tool (subagent_type: `a_sag_plan_verifier`, model: opus). Claude Code loads the agent's instructions automatically (the agent comes from agentic-devkit).
   2. Pass to the agent:
      - Full text of execution_plan.md
      - Full text of prompt-understanding.md
      - Project root path
      - config_hints.json content
   3. Review agent output:
      - **VERIFIED** → proceed to checkpoint
      - **ISSUES FOUND** → fix each issue in execution_plan.md, then re-run verification
   4. Do NOT present the plan to the user until verification passes

   **Manual Override:** If user says "skip verification", proceed directly to checkpoint.

**Checkpoint:** After a_sag_plan_verifier passes, ask user:
```
execution_plan.md is ready (verified against codebase).

Review the plan. Approve this implementation approach?
- Yes → Proceed to Phase 3
- No → What needs adjustment?
```

This is the **HUMAN GATE** described in "Running unattended with `/goal`". It stays a plain interactive checkpoint even in autonomous mode, never fold "human approved" into a goal condition.

**Post-Approval Steps:**

1. **Log Task Started:**
   - Follow "Task History Logging" section
   - Add entry to `{coding_tasks_root}/TasksSummary/Backend.md` or `Frontend.md`
   - Mark Completed as `-` (will be filled in Phase 4)

2. **Update execution-summary.md:**
   ```markdown
   ## Current State
   - **Phase:** 2 (Plan) → Ready for Phase 3
   - **Branch:** feature/{namespace}-{name}
   - **Last Action:** Plan approved

   ## Q&A Log
   - (carry forward from Phase 1, add new)

   ## Next Steps
   - Create branch and start coding
   ```

3. **📤 Push docs checkpoint:** Run push-docs procedure with `"plan {task_name}"`, saves execution_plan.md, execution-summary.md, and TasksSummary entry.

4. **🎯 If (and only if) the user opted into autonomous mode:** now, after the plan is approved, print the **GOAL B** block (see "Running unattended with `/goal`" above), including the one-line instruction to switch the session to `auto` permission mode before running it. Skip entirely in the default interactive run.


## Phase 3: Code

**Trigger:** User says "start coding", "approved", or "looks good"

**Prerequisites:**
- User has approved `execution_plan.md` from Phase 2
- execution_plan.md includes a branch name (e.g., `feature/{namespace}-195-add-document-api`)

**Steps:**

1. **Pull latest changes from main:**
   ```bash
   git pull origin main
   ```
   (Task-flow starts on main branch - this is expected and correct)

2. **Verify we're still on main before creating branch:**
   ```bash
   git branch --show-current
   ```
   - Expected output: "main"
   - If already on a feature branch → User may have created it manually (safe to proceed)

### Pre-Product Worktree Reconciliation

**This runs BEFORE the branch/worktree is created below.** Its job is to notice when we are *already* in the right place (a linked worktree that already encodes this ticket) and reuse it, instead of blindly creating a fresh branch or, worse, nesting a worktree inside a worktree. It defaults to safe-and-confirm: when anything is ambiguous it ASKS, it never auto-creates over an unclear state.

**Step A, Detect where we are** (reuse the same idiom as Phase 4i):
```bash
# Are we in a linked worktree?
is_worktree=false
if git rev-parse --git-dir 2>/dev/null | grep -q "worktrees"; then
  is_worktree=true
fi

current_branch=$(git branch --show-current)   # empty string ⇒ detached HEAD
default_branch="main"                           # adapt if the project's default differs

# Clean vs dirty working tree
working_tree="clean"
if git status --porcelain | grep -q .; then
  working_tree="dirty"
fi
```

**Step B, Extract the ticket for THIS task.** Read the ticket prefix from the **target project's** `.claude/config_hints.json` (`project.namespace`, at runtime this is the installed project's config, not the framework's), lowercase it, and namespace-prefix-match it against `raw_prompt.md` / the branch name in `execution_plan.md`:
```bash
namespace_lower=$(jq -r '.project.namespace' .claude/config_hints.json | tr '[:upper:]' '[:lower:]')
# ticket = the {namespace}-NNN token found in raw_prompt.md / execution_plan.md, e.g. "{namespace}-340"
# If no ticket exists yet (ticket-late, ticket-first not yet fetched), treat ticket as UNKNOWN.
```

**Step C, Reconcile against the ticket.** Pick the first case that matches:

| Situation | Action |
|-----------|--------|
| **Current branch already encodes this ticket** (`feature/{namespace_lower}-{ticket}-…`) | **REUSE** this worktree/branch. Do NOT create anything. Print a one-line confirmation: `Reusing existing worktree on branch {current_branch} for {TICKET}.` Skip the creation step below. |
| **In a worktree, but its branch encodes a DIFFERENT ticket** | **AMBIGUOUS → ASK** the user before doing anything: `(1) reuse this worktree as-is`, `(2) create a NEW worktree for {TICKET}`, `(3) abort`. Do not proceed until they choose. |
| **In the main checkout (`is_worktree=false`), clean** | Create normally via `a_g_worktree_init` (see creation step below), this is the happy path. |
| **Dirty working tree, OR detached HEAD, OR on the default branch (`main`) while inside a worktree** | **CONFIRM before acting**, show the detected state and ask how to proceed (stash/commit first, reuse, or create elsewhere). Never silently create on top of uncommitted work or a detached HEAD. |
| **Ticket UNKNOWN (ticket-late, no ticket yet)** | If we are already in a feature worktree, **ASK** whether to use it for this task. **NEVER auto-create** a worktree before the ticket is known. |

**Step D, Hard rule: never nest.** Do **NOT** create a worktree while `is_worktree=true` without **explicit user confirmation** in this session. A worktree nested inside a worktree is almost always a mistake; require the user to say so out loud.

**Step E, Record the decision** so `ar-taskflow-resume` can recover it. Whatever you chose (reuse / create / confirmed-other), write it into `execution-summary.md` using the fields added in the "Create/Update `execution-summary.md`" step below (Worktree, Local Branch, Remote Branch, Reconciliation Result).

Once reconciliation has either chosen REUSE (skip creation) or cleared the way to create, continue:

3. **Create feature branch from main:**

   **Only when reconciliation chose to create** (main checkout clean, or an explicitly-confirmed new worktree). If reconciliation chose REUSE, skip this step entirely.

   In the main checkout, prefer the worktree helper so the new branch lands in its own linked worktree. `a_g_worktree_init` comes from agentic-devkit: in an interactive shell call it by name; from Claude Code's non-interactive Bash tool (helpers not sourced, no auto-cd) run `bash "${AGENTIC_DEVKIT_DIR:-$HOME/agentic-devkit}"/scripts/a_g_worktree_init <branch> -b main` and read the printed worktree path.
   ```bash
   # Creates a linked worktree on a new branch from main
   a_g_worktree_init "feature/${namespace_lower}-<ticket>-<short-description>" -b main
   ```
   Or, when a plain in-place branch is intended (no worktree):
   ```bash
   git checkout -b feature/{namespace}-<branch-name>
   ```
   Use the branch name from execution_plan.md header.

4. **Add execution tracking to `execution_plan.md` header:**
   ```markdown
   ## Execution Tracking
   - **Started:** {today's date, YYYY-MM-DD}
   - **Developer:** developer@email.com
   - **Branch:** feature/{namespace}-195-add-document-api
   - **Collaborators:** (none yet)
   ```

5. **Create/Update `execution-summary.md`** (for session recovery):
   ```markdown
   ## Pull Request
   - *PR not yet created*

   ## Current State
   - **Phase:** 3 (Code)
   - **Branch:** feature/{namespace}-195-add-document-api
   - **Worktree:** {true|false}
   - **Local Branch:** {branch checked out in the working dir}
   - **Remote Branch:** {remote branch name to push/PR, same as Local Branch unless worktree-renamed}
   - **Reconciliation Result:** {reused existing worktree | created new worktree | created in-place branch | confirmed-other, from Pre-Product Worktree Reconciliation}
   - **Last Action:** {what you just did}

   ## Q&A Log
   - Q: {question asked} → A: {user's answer}
   - Q: {another question} → A: {answer}

   ## Next Steps
   - {what comes next}
   ```
   Keep this file small. Log important Q&A as you go.

   The **Worktree / Local Branch / Remote Branch / Reconciliation Result** fields are written by the Pre-Product Worktree Reconciliation step above (and updated by Phase 4i if the remote branch is renamed). They let `ar-taskflow-resume` recover which worktree/branch this task lives in instead of blindly creating a new branch.

6. **Write code** following `<standards_location>/` conventions:

   **Always-apply rules (every task, load whichever the project installed in `<standards_location>`; names/idioms vary by stack):**
   - `coding-conventions.md` (or the project's equivalent) - language/formatting/naming conventions for THIS repo's language
   - `project-structure.md` / `core-engineering-standards.md` (whichever exists) - module/package placement for this repo's layout
   - `critical-thinking.md` - Challenge assumptions, verify against codebase
   - `test-change-policy.md` - When tests may change (Change Class taxonomy + regression-oracle + diagnosis fork)
   - `test-scope-policy.md` - What a test asserts (observable contract, not implementation or framework guarantees)

   **Task-specific rules (from prompt-understanding.md):**
   - Read the `## Applicable Rules` section in `prompt-understanding.md`
   - **Read each listed .md file** before writing code that falls under its scope
   - These were identified in Phase 1 based on the task content

   **Key rule:** Apply Rule 4 (Never Fabricate), every concrete detail must come from code you actually read (see Critical Rules section)

7. **Update Documentation (CHECK execution_plan.md):**

   **IMPORTANT:** Check the "Documentation updates" section in your execution_plan.md.
   If docs were listed, update them NOW before proceeding to tests.

   - **API changes** → Update: `{docs_root}/<your project's API-spec doc>.md`
   - **Database changes** → Update: `{docs_root}/<your project's ERD doc>.md`

   **Triggers requiring doc updates:**
   - New/changed API endpoints or request/response formats → API Specs
   - New/changed DB tables, columns, or constraints → ERD
   - Changed validation rules or business logic → Both if applicable

8. **Testing Requirements (MANDATORY), branch on Change Class first:**

   **Determine the task's `Change Class`** (captured in `prompt-understanding.md` / `execution_plan.md`, see Phase 1/2). It is one of:

   | Change Class | Definition | Test action |
   |---|---|---|
   | **BEHAVIOR_PRESERVING** | Refactor, perf tuning, extract-method, rename a private member, nothing crosses a public method boundary or changes an API/DB/observable contract. | **Do NOT modify existing tests.** Run the unchanged suite as-is, green *is* the proof behaviour was preserved. Add tests only for genuinely new private seams if useful. |
   | **CONTRACT_CHANGING** | A public/observable contract changed (signature, return type, thrown exceptions, API shape, status codes, persisted schema). | Each modified test hunk must map to a **named contract delta** in the plan. Update only the tests the contract change actually invalidates. |
   | **FEATURE** | New behaviour added. | Add new coverage (rules below). Leave unrelated existing tests untouched. |

   > **Why this matters (regression oracle):** for behaviour-preserving work the still-green existing suite is the *only* evidence the change didn't alter behaviour. Editing those tests to make them pass **destroys that evidence**, pollutes the diff, and trains a "make it green by editing the test" reflex. Tests change only when they *must*.

   **Diagnosis fork, when an existing test goes red during a BEHAVIOR_PRESERVING change:** do NOT default to editing the test. Classify the failure first:
   - **Real regression** → fix the **code**, not the test. The optimization changed behaviour it shouldn't have.
   - **Over-coupled / brittle test** (asserted on a private detail you legitimately changed) → **STOP and surface it to the user** with the specific coupling; only adjust the test after the user agrees it tests an implementation detail, and record it in the `execution_plan.md` Change Log.

   See `test-change-policy.md` (always-apply rule, Phase 3 step 6 list) for the full taxonomy + diagnosis flow.

   **For CONTRACT_CHANGING / FEATURE work, the coverage rules below apply.** Follow this project's existing test conventions, mirror the nearest existing test; don't impose patterns from another codebase.

   a. **Find existing tests for the modified code** following the project's convention (look at how tests for sibling code are located and named) and mirror the nearest one.

   b. **Update existing tests only where the contract actually changed:**
      - Add test cases for new functionality
      - Update an existing test **only** when the contract delta invalidates it, never to silence a behaviour-preserving refactor
      - Ensure existing tests still pass with your changes

   c. **Create new tests if none exist:**
      - Follow the existing project test patterns, framework, and style (read a similar existing test for structure and setup)

   d. **Test naming:** follow the conventions of the nearest existing tests in this repo.

   e. **What to test:**
      - Happy path (successful execution)
      - Edge cases (null/empty, boundaries)
      - Error conditions (validation failures, exceptions)
      - Backward compatibility (if applicable)

   f. **Run tests after implementation** using the project's command (`test_command` / `verify.full_command` from `config_hints.json`, else the command documented in the repo). Force a fresh run if the runner caches results.

      **For BEHAVIOR_PRESERVING work (F7):** verify the **original, pre-edit** tests pass against the new code, that's the regression oracle. This only holds if the run includes the opt-in/tagged suites (see Phase 4g): a default test task that skips them can report "behaviour preserved" falsely. Use `verify.full_command` or run the documented integration task too.

   g. **If tests fail:** apply the diagnosis fork above (regression → fix code; brittle test → stop and ask). Never commit with failing tests, and never make a behaviour-preserving test green by editing it.

9. Run the project's linter/formatter (`lint_command` from `config_hints.json`). Skip if the project defines none.

10. **Flip `passes` flags in `acceptance_criteria.json` as you verify each criterion:**

    Before flipping anything, check `execution_plan.md` for unapplied Change Log entries that touched the AC. If found, regenerate the JSON per Phase 2 step 6 drift policy first, never flip a flag on a stale JSON.

    Work one criterion at a time. After implementing the code for `AC-N`:

    a. **Execute the `verification` step exactly as written** in the JSON (run the named test, hit the endpoint, walk through the UI flow). Do not approximate.
    b. **Observe the result.** Only if it succeeds, edit `acceptance_criteria.json` and flip `"passes": false` → `"passes": true` for that row.
    c. Do not edit any other field. Do not flip multiple rows in one go without running each verification.
    d. If the verification fails, fix the code, not the criterion. If the criterion itself is wrong, stop and ask the user; record the change in `execution_plan.md` Change Log before editing the JSON.

    **Forbidden shortcuts:**
    - Flipping `passes: true` because "the code looks right" without running the verification
    - Flipping `passes: true` because a *different* test passed
    - Deleting or rewriting a criterion to make it easier to pass
    - Marking a criterion passed when its verification was only partially executed (e.g., happy path only when the criterion says "rejects invalid input")

11. **Keep files updated as things change (CRITICAL):**

    **After every significant action, update `execution-summary.md`:**
    ```markdown
    ## Current State
    - **Phase:** 3 (Code)
    - **Last Action:** {what you just did}
    - **Next:** {what comes next}
    ```

    **When scope/approach changes, update `execution_plan.md`:**
    - Mark completed items with ✅
    - Add newly discovered files to the list
    - Update approach if it changed
    - Add to Change Log section

    **When user clarifies requirements, update `prompt-understanding.md`**

12. **If someone else joins the task**, add them as collaborator:
    ```markdown
    - **Collaborators:** other@email.com (joined {date})
    ```

13. **If prompt/requirements change**, add to change log at bottom of `execution_plan.md`:
    ```markdown
    ## Change Log
    | Date | Time | Person | Change |
    |------|------|--------|--------|
    | {date} | {time} | dev@email.com | Updated scope to include X |
    ```

## Phase 4: Finish

**Trigger:** User says "done", "finished", "continue", or code is complete

**IMPORTANT:** Always create documentation files FIRST, then ask about commit.

**Steps:**

### Phase 4 pre-condition: Acceptance Criteria Gate (HARD BLOCK)

Before any 4a-4k step below runs, read `{task_folder}/acceptance_criteria.json`. **Every** criterion must have `passes: true`, or Phase 4 stops here.

```bash
if [ -f "{task_folder}/acceptance_criteria.json" ]; then
  jq -r '.criteria[] | select(.passes == false) | "FAIL: \(.id), \(.description)"' \
    "{task_folder}/acceptance_criteria.json"
else
  echo "WARN: acceptance_criteria.json missing (task started before v6.1)"
fi
```

**If any row has `passes: false`:**

```
🚧 BLOCKED: Acceptance criteria not all green.

Still failing:
  - {AC-N}: {description}
    Verification: {verification step}

Phase 4 (commit/PR/ticket) cannot proceed until every criterion in
acceptance_criteria.json has passes=true, and each flip was earned by
actually executing the verification step.

Options:
  1. Go back to Phase 3 and finish the failing criteria (recommended)
  2. If a criterion is no longer applicable, add a Change Log entry in
     execution_plan.md explaining why, then update the JSON with user approval
```

Do not flip flags here to unblock yourself. The flip must be earned in Phase 3, with the verification observed.

**Backward compatibility (pre-v6.1 task):**

If `acceptance_criteria.json` does not exist, do not silently skip, instead:

```
⚠️ acceptance_criteria.json is missing.

This task was likely started before the JSON gate was introduced.

Options:
  1. Generate it now from the "Acceptance criteria" section of execution_plan.md,
     mark items I can verify in this session as passes=true, and resume the gate
  2. Skip the gate this once (note in execution-summary.md → Last Action)

Which?
```

### 4a. Check Rule Checklists

**If your changes involve:**
- Database migration → Check `<standards_location>/database-migrations.md` checklist
- API endpoints → Check `<standards_location>/api-conventions.md` checklist

**If checklist exists, verify all items before proceeding.**

### 4b-4c. Create Documentation

**🤖 INVOKE AGENT: a_sag_task_doc_writer**

```bash
# Invoke a_sag_task_doc_writer agent
# Agent will:
# 1. Read execution_plan.md and prompt-understanding.md
# 2. Read git diff
# 3. Check for executive_summary.md (Phase 1 may have created one)
# 4. Create ticket.md (product-level), prepending executive_summary.md content if present
# 5. Create pr-description.md (technical, using template), prepending executive_summary.md content if present
```

**Agent Input:**
- Task folder path
- execution_plan.md
- prompt-understanding.md
- executive_summary.md (optional, only if Phase 1 generated it)
- Git diff
- PR template (optional)

**Agent Output:**
- ticket.md (product-level description for the tracked issue)
- pr-description.md (PR description for GitHub)

**Executive summary auto-attach:**

If `executive_summary.md` exists in the task folder, prepend its content (verbatim, no rewording) as the **first section** in BOTH ticket.md and pr-description.md, under the header `## Executive Summary`. This goes ABOVE the title block / template header content.

In ticket.md the structure becomes:
```
## Executive Summary
{verbatim copy of executive_summary.md body, the 2-3 lines}

# [{project_namespace}-XXX] Task Title
...rest of ticket as before...
```

In pr-description.md it goes above the template's first section. Reviewers and standup readers see the digest immediately without scrolling.

If `executive_summary.md` does NOT exist, both files are generated exactly as before, no placeholder, no empty section.

**What the agent creates:**

**ticket.md:**
```markdown
{If executive_summary.md exists, its body goes here under "## Executive Summary", verbatim}

# [{project_namespace}-XXX] Task Title
**Ticket link:** per tracker (`#{number}` for github, `https://{tracker_url}/browse/{project_namespace}-XXX` for jira), see the Tracker Dispatch Table in `<standards_location>/mcp-integration.md`

## Problem
(user perspective)

## Solution
(what changes)

## Benefits
(why this matters)

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2
```

- Product-level language only
- Allowed: JSON examples, API formats, table names
- NOT allowed: Class names, file paths, code snippets

**pr-description.md:**
- Reads PR template from `{coding_tasks_root}/Templates/template_pr_backend.md`
- Follows template structure exactly
- Includes: Context, Approach, Testing, Checklist
- Uses [{project_namespace}-XXX] format
- Executive summary (if present) is prepended above the template content

**Keep updated:** If user provides feedback, agent output can be manually adjusted.

**Manual Override:** If user says "skip agent", create ticket.md and pr-description.md directly, and remember to prepend executive_summary.md content if it exists.

### 4d. Verify Documentation Updates (MANDATORY)

**Before proceeding, check `execution_plan.md` for documentation updates:**

1. Read the "Documentation updates" section from execution_plan.md
2. If docs were listed → Verify they were actually updated
3. If docs were NOT updated but should have been → Update them now:
   - **API changes** → Update `{docs_root}/<your project's API-spec doc>.md`
   - **Database changes** → Update `{docs_root}/<your project's ERD doc>.md`

**Common triggers for doc updates:**
- New/changed endpoints
- Changed request/response formats
- New/changed DB tables or columns
- Changed validation rules

**ERD Update Check:**
If `docs/erd.md` exists AND changes include database migrations or entity modifications:
```
Database changes detected. docs/erd.md may be out of date.

Update ERD now?
- Yes → I'll read the new migrations/entities and update the diagram
- No → Skip (remember to update later)
```

If yes, read all migrations/entities and regenerate the affected sections of `docs/erd.md` (Mermaid diagram, table docs, relationships, migration history).

### 4e. Update the Tracked Issue (If Ticket-First Approach)

**IMPORTANT:** Resolve every step here via the **Tracker Dispatch Table** for the repo's `tracker_type` (see `<standards_location>/mcp-integration.md`). Defaults to `github` when unset. If `tracker_type` is `none`, skip this step entirely.

**Only if task started with ticket-first approach:**

1. **Check if this was a ticket-first task:**
   - Read `raw_prompt.md`
   - Look for the `**Issue:**` (or legacy `**Jira Ticket:**`) header with a link
   - If not found → Skip this step

2. **If found, extract the issue reference:**
   - github: the issue `#{number}`
   - jira/linear: the ticket key parsed from the URL (e.g., {namespace}-195), see mcp-integration.md for URL parsing

3. **Check the tracker is reachable** (dispatch table "Check configured" row):
   - github: `gh auth status`
   - jira: `claude mcp list | grep atlassian`; if not configured → Skip with warning: "Tracker not reachable, skipping issue update"
   - linear: confirm the Linear MCP

4. **Update the issue** using the dispatch table "Update / comment" row. Keep the same intent in every tracker: **archive the original description, record the completion, add a PR-follows note.**

   **github (default):** GitHub issues don't overwrite descriptions in place, so post the completion as a comment (the original body stays visible in the issue history):
   ```bash
   gh issue comment {n} --body "$(cat <<'EOF'
   ✅ Task Completed on {date}

   {content_from_ticket.md}

   Branch: feature/{namespace}-{ticket}-{name}
   Completed by: {git_user_email}

   PR will be created with details above.
   EOF
   )"
   ```
   Prefer letting the PR close the issue: put `Closes #{n}` in the PR body (Phase 4k) rather than closing manually. Only run `gh issue close {n}` if the repo does not use the auto-close convention.

   **jira / linear (archive-then-edit the description):**
   a. Fetch the current description (`mcp__atlassian__getJiraIssue`) and store it for backup.
   b. Archive it as a comment (`mcp__atlassian__addCommentToJiraIssue`):
      ```
      📋 Original Description (Archived on {date})

      {original_ticket_description}

      ---
      This description was archived when the task was completed.
      See updated description above for final implementation details.
      ```
   c. Replace the description (`mcp__atlassian__editJiraIssue`) with the `ticket.md` content:
      ```markdown
      ✅ **Task Completed on {date}**

      {content_from_ticket.md}

      ---
      _Original description archived in comments below._
      ```
   d. Add a completion comment (`mcp__atlassian__addCommentToJiraIssue`) with branch, author, date, and a PR-follows note.
      (Linear: apply the same three moves via the Linear MCP.)

5. **Confirm update:**
   - Show message: "Updated issue {issue_ref} with completion details" and its link.

**Error Handling:**
- If a tracker read fails → Warn user but continue workflow
- If a tracker update fails → Warn user and ask if they want to retry or skip
- Never block the workflow due to tracker-update failures

**Important Notes:**
- The original description is never lost (github keeps the original body; jira/linear archive it to a comment)
- The issue now reflects the actual implementation
- Updates use Markdown for readability

### 4f. Log Task Completed

After verifying documentation:
1. Find the task entry in `{coding_tasks_root}/TasksSummary/Backend.md` or `Frontend.md`
2. Update the Completed column with today's date
3. Example: `| {namespace}-195 Simplify payment API | dev@example.com | Jan 17 | - |` → `| {namespace}-195 Simplify payment API | dev@example.com | Jan 17 | Jan 18 |`
4. **📤 Push docs checkpoint:** Run push-docs procedure with `"complete {task_name}"`, saves ticket.md, pr-description.md, TasksSummary completion date, and WeeklySummary updates.

### 4g. Run Full Test Suite (MANDATORY)

**🤖 INVOKE AGENT: a_sag_test_runner**

> **⚠️ The default test command is NOT always the full suite.** Many projects guard slow integration suites so they're *opt-in* and the default test command silently skips them. A green default run then declares the task done while the integration suite breaks in CI, a real defect (one case burned ~45 min across 3 push-wait-fail cycles).

**Pick the verification command in this order:**
1. If `.claude/config_hints.json` (or `.claude/skill.config`) declares a `verify.full_command`, run **that**, it's the project's curated "everything that must be green before merge" command.
2. Otherwise run the project's default test command.

**Skipped-suite detection runs in BOTH cases, including when `verify.full_command` is set.** A `full_command` is only as complete as whoever wrote it: a default test command that skips a guarded/opt-in integration suite (or drops a cache-bypass flag) produces a green that isn't actually full. The runner always checks whether the executed command left an opt-in/guarded/tagged suite unrun, regardless of how the command was chosen. For each suite found, **do not report unqualified green**, surface it explicitly:
   > `⚠️ Integration/opt-in suite <name> was NOT run by this command (even though verify.full_command was used). Run it before merge, or extend verify.full_command to include it.`

```bash
# Agent will:
# 1. Run verify.full_command if set, else the default test task (force a fresh run, e.g. --rerun-tasks)
# 2. Parse test results
# 3. ALWAYS detect opt-in/tagged/guarded/skipped test tasks the command did NOT execute, even for verify.full_command
# 4. Report pass/fail, qualified with any suite that was skipped
```

**Agent Input:**
- `verify.full_command` from config if present, else the project's default test command (the agent resolves it from config/repo, never assume a build tool)
- Project root

**Agent Output:**
- Test results (PASS/FAIL)
- Failure details (if any)
- **Skipped-suite warnings** (any opt-in/tagged module the command did not cover)

**Important:**
- Force a fresh run if the project's test runner caches results
- If tests fail → STOP, fix the issues first
- If tests pass **but a suite was skipped** → this is NOT a clean green. Run the named suite (or `verify.full_command`) before declaring done, or tell the user exactly which suite is unverified.
- If tests pass and nothing was skipped → Proceed to code review
- Never commit with failing tests

**Manual Override:** If user says "skip agent", run `verify.full_command` directly (or, if unset, the project's test command plus its documented integration task).

### 4h. Code Review (BEFORE COMMIT)

**🤖 INVOKE AGENT: a_sag_code_reviewer**

```bash
# Invoke a_sag_code_reviewer agent
# Agent will:
# 1. Read git diff (staged changes)
# 2. Read execution_plan.md
# 3. Check coding rules compliance
# 4. Verify test coverage
# 5. Check security issues
# 6. Validate documentation updates
```

**Agent Input:**
- Task folder path
- Project root
- Git diff (staged changes)
- execution_plan.md

**Agent Output:**
- Review report
- Status: APPROVED / CHANGES REQUIRED
- Issues found (if any)
- Suggestions

**Checkpoint:** After agent completes:
```
Code review complete. See review report.

Status: {APPROVED / CHANGES REQUIRED}

{If CHANGES REQUIRED}
Issues found:
1. {issue description}
2. {issue description}

Fix these issues before committing?
- Yes → Fix issues, then re-run review
- No → Explain why issues can be ignored

{If APPROVED}
Approve to commit?
- Yes → Proceed to get ticket number
- No → Make additional changes
```

**Manual Override:** If user says "skip agent", proceed directly to commit without review.

### 4i. Get Ticket Number and Update Everything

After code review approval:

1. **Ask if an issue exists.** If `tracker_type` is `none`, skip this whole step: there is no tracker, use the task-folder name as the identifier and go straight to step 2. Otherwise:
   ```
   Do you have an issue for this task yet?

   1. Yes, I have an issue number/key
   2. No, create it for me
   3. No, I'll create it myself, I'll give you the number/link
   ```

   **Option 1 (Yes):** Ask "What's the issue number or key?" (a GitHub `#{number}` by default, or a Jira/Linear key like {project_namespace}-195). Continue to step 2.

   **Option 2 (Create it for me):** Create the issue via the dispatch table "Create ticket" row for `tracker_type` (`<standards_location>/mcp-integration.md`):
   - **github (default):** read the task summary from `execution_plan.md`, then
     ```bash
     gh issue create --title "{summary}" --body "{Problem + Solution summary from prompt-understanding.md}"
     ```
     Capture the issue number from the returned URL.
   - **jira:** ask for the Epic/parent key (e.g., {project_namespace}-100), get the account id via `mcp__atlassian__atlassianUserInfo()`, then `mcp__atlassian__createJiraIssue()` with `projectKey` = `{project_namespace}`, `summary` from execution_plan.md, `description` from prompt-understanding.md, `parent` = the Epic key, `assignee_account_id` = your account id. Extract the ticket key.
   - **linear:** create via the Linear MCP with the same summary/description.
   - If creation fails → fall back to Option 3. Continue to step 2.

   **Option 3 (Manual):** Help the user create one:
   - Read `execution_plan.md` to extract the task summary (first heading or summary line)
   - Point them at the tracker's create surface for `tracker_type`: for github, `gh issue create --title "{summary}" --body ...` or the repo's Issues tab; for jira, the board URL:
     ```
     Please create a ticket in Jira:

     https://{tracker_url}/jira/software/projects/{project_namespace}/boards

     Suggested title: {summary from execution_plan.md}

     Once you've created it, tell me the issue number/key (e.g., {project_namespace}-195).
     I'll wait here, the workflow cannot proceed without an issue reference.
     ```
   - **BLOCK and wait**, do NOT proceed until the user provides an issue number/key.

   **Mark the issue as started (ALL paths, tracker-dependent):**

   After obtaining the issue reference, mark it in-progress where the tracker supports it:
   - **github:** optional. GitHub issues have no "In Progress" state; if the repo uses a status label or Project board column, apply it (`gh issue edit {n} --add-label "in progress"` when such a label exists). Otherwise skip silently.
   - **jira:** get transitions via `mcp__atlassian__getTransitionsForJiraIssue()`, find the one whose target status is "In Progress" (common names: "Work started", "Start Progress", "In Progress"), apply via `mcp__atlassian__transitionJiraIssue()`.
   - **linear:** set the workflow state to In Progress via the Linear MCP.

   Rules:
   - Do this silently, just show a one-liner: "Moved {issue_ref} to In Progress"
   - If the tracker is unreachable or the transition fails → warn but don't block workflow
   - If already "In Progress" or beyond → skip silently
   - If no such state exists (or `tracker_type` is `none`) → skip

**🚨 IMMEDIATELY after receiving ticket number, do ALL of these (don't skip any):**

2. **FIRST: Rename branch to include ticket number:**

   **Step 2a: Detect worktree**
   ```bash
   # Check if we're in a git worktree
   is_worktree=false
   if git rev-parse --git-dir 2>/dev/null | grep -q "worktrees"; then
     is_worktree=true
   fi

   current_branch=$(git branch --show-current)
   namespace_lower=$(echo "$project_namespace" | tr '[:upper:]' '[:lower:]')
   target_branch="feature/${namespace_lower}-<ticket>-<short-description>"
   ```

   **Step 2b: Rename or set remote branch name**

   **If NOT in a worktree** → Rename the local branch:
   ```bash
   git branch -m "$current_branch" "$target_branch"
   ```

   **If IN a worktree** → Keep local branch name, track a differently-named remote branch:
   ```bash
   # Do NOT rename the local branch (worktree directory is tied to it).
   # Instead, store the target remote branch name for use during push/PR.
   remote_branch_name="$target_branch"
   ```
   When pushing later (Phase 4j/4k), use a refspec to push to the correct remote name:
   ```bash
   git push -u origin "$current_branch:$remote_branch_name"
   ```
   This keeps the local worktree intact while the remote branch and PR show the correct name.

   **Store the mapping** in `execution-summary.md` so session recovery knows about it:
   ```markdown
   - **Worktree:** true
   - **Local Branch:** {current_branch}
   - **Remote Branch:** {remote_branch_name}
   ```

   - Example (normal): `feature/svc-update-api-paths` → `feature/svc-340-update-api-paths`
   - Example (worktree): local stays `hotfix-some-name`, remote pushed as `hotfix/{namespace}-431-description`
   - If branch already contains ticket (e.g., `feature/svc-340-something`), skip rename, in worktree mode, set `remote_branch_name="$current_branch"` (no remote rename needed either)
   - **This MUST happen before any commits**

3. **Update ticket.md header:**
   - Add ticket number: `# [{project_namespace}-XXX] Task Title`
   - Add the ticket link per tracker: `#{number}` for github, `**Jira:** https://{tracker_url}/browse/{project_namespace}-XXX` for jira (Tracker Dispatch Table in `<standards_location>/mcp-integration.md`)

4. **Update pr-description.md header:**
   - Add ticket number: `# [{project_namespace}-XXX] Task Title`
   - Add reference: `**Related Ticket:** {project_namespace}-XXX`

5. **Update TasksSummary and WeeklySummary (if ticket-late approach):**

   **Check if this was ticket-late approach:**
   - Read TasksSummary file
   - Look for entry starting with "TBD" in Task column
   - If found, this was ticket-late approach and needs updating

   **If ticket-late, perform these updates:**

   a. **Update TasksSummary row:**
      - Find row with "TBD {Task Title}"
      - Replace "TBD" with "{Ticket-ID}" (e.g., "{project_namespace}-195 Add endpoint")
      - Update Weekly Summary link from `{start_date}_{platform}_TBD-{sanitized-title}.md` to `{start_date}_{platform}_{TICKET-ID}-{sanitized-title}.md`

   b. **Rename and update WeeklySummary file:**
      ```bash
      # Find the TBD file
      old_file="{coding_tasks_root}/WeeklySummaries/{week_ending}/{start_date}_{platform}_TBD-{sanitized-title}.md"
      new_file="{coding_tasks_root}/WeeklySummaries/{week_ending}/{start_date}_{platform}_{TICKET-ID}-{sanitized-title}.md"

      # Rename file
      mv "$old_file" "$new_file"
      ```

      - Update file header from `# TBD: {Task Title}` to `# {TICKET-ID}: {Task Title}`
      - Update Ticket field from "TBD" to actual ticket URL

   **Example transformation:**

   Before (Phase 2):
   ```markdown
   | TBD Add API endpoint | dev@example.com | Jan 29 | - | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_TBD-add-endpoint.md) |
   ```

   After (Phase 4h):
   ```markdown
   | {NAMESPACE}-275 Add API endpoint | dev@example.com | Jan 29 | - | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_{NAMESPACE}-275-add-endpoint.md) |
   ```

6. **Ask about commit:**
   - Normal: "All tests passing. Branch renamed to `feature/{lowercase(namespace)}-XXX-...`. Updated ticket.md, pr-description.md, and task tracking. Want me to commit these changes?"
   - Worktree: "All tests passing. Local branch `{current_branch}` will push to remote as `{remote_branch_name}`. Updated ticket.md, pr-description.md, and task tracking. Want me to commit these changes?"
   - **Continuous mode (`flow.continuous: true` or explicit opt-in): do not ask**, state the same line as a status (*"All tests passing, committing and opening the PR."*) and proceed straight through 4j → 4k → 4l.

### 4j. Commit (DO NOT PUSH)

**CRITICAL SAFETY CHECK, run the branch check from "Rule 1: Detect Workflow Violations" (see CRITICAL SAFETY RULES) before committing.** If `git branch --show-current` is `main`/`master`, STOP and use Rule 1's 3-option prompt; do not commit to main without an explicit, justified override. Only proceed when on a feature branch.

**Normal Commit Flow (when on feature branch):**

**Note:** Branch should already be renamed in Phase 4i. If not, rename it now before committing.

**INVOKE AGENT: a_sag_commit_writer (Haiku)**

1. Invoke `a_sag_commit_writer` via the Task tool (subagent_type: `a_sag_commit_writer`, model: haiku); its instructions load automatically (from agentic-devkit).
2. Gather context for the agent:
   - Context summary from execution_plan.md + prompt-understanding.md
   - `git diff --staged` output
   - `git log --oneline -5` for repo style
   - Commit template from `docs/templates/commit-template.md` (if exists)
3. Invoke Task tool with model: haiku, passing agent instructions + context
4. Agent returns the commit message text (no tool or assistant attribution trailers; the commit is authored by the developer)
5. Show user the proposed commit message and staged files
6. On approval, commit with the message. **Continuous mode:** skip the approval wait, show the message and commit in the same step.

**Manual Override:** If user says "skip agent", write the commit message directly in main session.

### Post-Review Fix Commits

> **When PR review comments arrive after the PR is open**, CodeRabbit, human reviewers, SonarQube, or softer phrasings like "comments came in", "got feedback on the PR", "few more comments, please solve", "please fix the comments", **hand off to `ar-taskflow-fix-comments`** instead of fixing ad-hoc. That skill enforces the reply-to-thread *and* resolve-thread steps that close the loop with reviewers. Fixing by hand lands the code change but leaves the inline threads open with no author response, so the reviewer has to dig through commits to see what changed.

When making changes after a `ar-taskflow-review` (e.g., adding doc comments, fixing warnings):

- **ALWAYS create a NEW commit** for post-review fixes
- **NEVER amend the previous commit and force push**
- Use a descriptive message like: `[{namespace}-XXX] Address review feedback: add doc comments and clarifications`
- Then push normally: `git push` (no `--force-with-lease`, no `--force`)

**Why:** Force pushing rewrites remote history, can lose collaborator work, and hides the review iteration trail. Separate commits are cleaner and safer.

**IMPORTANT:** Do NOT push or create PR automatically. After commit, ask:
```
Committed to branch `feature/{namespace}-188-simplify-payment-api`.

What next?
1. Create PR → I'll generate the PR using your project template
2. Push only → push to remote (see worktree-aware command below)
3. Done for now → You can create the PR later with `a_sk_pr`
```

**Push command depends on worktree detection from Phase 4i:**
- **Normal:** `git push -u origin {branch}`
- **Worktree:** `git push -u origin {local_branch}:{remote_branch_name}` (uses refspec from Phase 4i)

If user chooses "Push only" and the branch already has an existing PR (check with `gh pr list --head {branch} --json number,title,url`), log it in execution-summary.md using the same format as Phase 4k step 10.

**NEVER auto-push or auto-create PR.** Wait for explicit user approval at every step.

### 4k. Create PR (Optional; automatic in continuous mode)

**If user chooses to create PR (continuous mode: always, without asking):**

**INVOKE AGENT: a_sag_pr_writer (Haiku)**

1. Invoke `a_sag_pr_writer` via the Task tool (subagent_type: `a_sag_pr_writer`, model: haiku); its instructions load automatically (from agentic-devkit).
2. Gather context for the agent:
   - pr-description.md content (or execution_plan.md if no pr-description.md)
   - `git log --oneline main..HEAD`
   - `git diff main...HEAD --stat`
   - PR template from `docs/templates/pr-template.md` (or `.github/PULL_REQUEST_TEMPLATE.md`)
   - Config from `.claude/config_hints.json`
   - `gh pr list --limit 3` for title style
3. Invoke Task tool with model: haiku, passing agent instructions + context
4. Agent returns: title + `---` + body (no tool or assistant attribution footer; the PR is authored by the developer)
5. Show user the proposed PR title and body
6. **Ask for PR type (default: Draft):**
   ```
   PR type:
   1. Draft PR (Recommended), not ready for review yet
   2. Ready for Review, request reviewers immediately

   Create this PR? (1/2/no)
   ```
   Default to Draft if user just says "yes".
7. **Detect the PR base branch BEFORE invoking `gh pr create`.**

   The PR base is NOT always `main`. In a worktree, the feature branch typically forks from a `story/{namespace}-XXX-...` branch that aggregates multiple sub-task PRs. Sub-task PRs must target the story branch, not `main`, otherwise the story aggregator gets out of sync and the user has to manually retarget (a real defect hit on {namespace}-532 PR #360, 2026-05-19).

   Detection order:

   a. If `.claude/config_hints.json` declares `"default_pr_base"`, use it:
      ```bash
      base_branch=$(jq -r '.default_pr_base // empty' .claude/config_hints.json 2>/dev/null)
      ```

   b. Otherwise, look for a `story/`-prefixed branch in the feature branch's ancestry:
      ```bash
      if [ -z "$base_branch" ]; then
        # Find the repo's default upstream so merge-base has something to anchor on
        default_remote_head=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
          | sed 's@^refs/remotes/origin/@@')
        default_remote_head="${default_remote_head:-main}"
        git fetch origin --quiet || true
        anchor=$(git merge-base HEAD "origin/$default_remote_head" 2>/dev/null)
        raw_candidates=$(git branch -r --contains "$anchor" 2>/dev/null \
          | grep -E 'origin/story/' | sed 's|^[[:space:]]*origin/||' | sort -u | xargs)
        # Filter out any candidate that IS our feature branch's tip
        current_branch=$(git symbolic-ref --short -q HEAD || echo "")
        raw_candidates=$(echo "$raw_candidates" | tr ' ' '\n' | grep -v -x "$current_branch" | xargs)
        # `git branch -r --contains <anchor>` returns every remote branch whose tip
        # contains the merge-base, that includes story branches that share only an
        # early common ancestor on main but aren't actually in HEAD's lineage. Keep
        # only candidates that ARE ancestors of HEAD; otherwise the picker prompts
        # on unrelated story branches that happen to live next to ours.
        candidates=""
        for c in $raw_candidates; do
          if git merge-base --is-ancestor "origin/$c" HEAD 2>/dev/null; then
            candidates="$candidates $c"
          fi
        done
        candidates=$(echo "$candidates" | xargs)
        n=$(echo "$candidates" | wc -w | xargs)
        case "$n" in
          0) ;;  # no story branch, fall through to step (c)
          1) base_branch="$candidates" ;;
          *) echo "Multiple candidate story branches found: $candidates"; \
             echo "Which one is the PR base?"; \
             read -r base_branch ;;
        esac
      fi
      ```

   c. Fall back to the repo's default branch:
      ```bash
      if [ -z "$base_branch" ]; then
        base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
          | sed 's@^refs/remotes/origin/@@')
        base_branch="${base_branch:-main}"
      fi
      ```

   Tell the user which base was chosen before continuing:
   ```
   Targeting PR at base: <branch>. Override later with:
     gh pr edit <num> --base <other-branch>
   (`gh pr edit --base` retargets an open PR without force-push or history rewrite, safe any time.)
   ```

8. On explicit approval only:

   **Push first**, use worktree-aware command from Phase 4i:
   ```bash
   # Normal:   git push -u origin {branch}
   # Worktree: git push -u origin {local_branch}:{remote_branch_name}
   ```

   **Then create PR, every variant passes `--base "$base_branch"`:**

   **Normal (not in worktree):**
   ```bash
   # Draft PR (default)
   gh pr create --base "$base_branch" --draft --title "{title}" --body "$(cat <<'EOF'
   {body}
EOF
   )"

   # Ready for Review (only if user explicitly chose option 2)
   gh pr create --base "$base_branch" --title "{title}" --body "$(cat <<'EOF'
   {body}
EOF
   )"
   ```

   **Worktree, MUST use `--head` flag:**

   When in a worktree, the local branch name differs from the remote branch.
   `gh pr create` doesn't know about the refspec push, so it fails without `--head`.

   ```bash
   # Draft PR (default)
   gh pr create --base "$base_branch" --head "{remote_branch_name}" --draft --title "{title}" --body "$(cat <<'EOF'
   {body}
EOF
   )"

   # Ready for Review (only if user explicitly chose option 2)
   gh pr create --base "$base_branch" --head "{remote_branch_name}" --title "{title}" --body "$(cat <<'EOF'
   {body}
EOF
   )"
   ```

9. **Continuous mode:** create the PR ready-for-review (drop `--draft`), or run `gh pr ready {number}` immediately after creation, a draft that waits for a human to promote it defeats the continuous flow. Then go directly to Phase 4l.
10. Return PR URL to user. If draft, remind: `gh pr ready` when ready for review. If the user spots that the base is wrong (e.g. detection picked main when they wanted a story branch), give them the safe recovery: `gh pr edit {number} --base {correct-branch}`, no force-push, no history rewrite.

10. **Log PR in `execution-summary.md`:**

   Add a `## Pull Request` section **at the top** of execution-summary.md (replace the `*PR not yet created*` placeholder):

   ```markdown
   ## Pull Request
   - **PR:** #{number}, {title}
   - **URL:** {pr_url}
   - **Status:** Draft / Open
   ```

   This ensures the inspector and session recovery can always find the PR, even if the folder name doesn't contain a ticket ID.

**Manual Override:** If user says "skip agent", use pr-description.md content directly.

### 4l. PR Verification Loop (continuous mode / opt-in)

Runs only when `flow.continuous: true` or the user opted in. Interactive default: stop after 4k as before.

Drive the PR to a verified state: **all checks green, quality gate passed, coverage acceptable, zero unresolved review comments.**

**Pacing, self-paced wakeup loop, NOT an in-turn block.** Run this under `/loop` dynamic mode (the GOAL C block above prints the command to copy-run). Each invocation does **one** check-and-act pass and then *yields the turn*; it does **not** sit in a 30-minute in-turn polling loop. This keeps the session cache-warm and interruptible across the CI wall-clock wait. The cap survives across wakeups via a counter recorded in `execution-summary.md` (see step 6).

Each pass:

1. **Check CI once** (do not `sleep`/poll in-turn):
   ```bash
   gh pr checks {number} --json name,state,link 2>/dev/null   # pending|pass|fail per check
   ```
2. **If any check is still `pending`** and the pending-pass count is under the cap (step 6):
   - Schedule the next pass and **end the turn**, call `ScheduleWakeup` with a delay **under 300s** (default **240s**, matching the team's ~4-min CI cadence; staying under 5 min keeps the prompt cache warm). Pass the same `/loop` prompt back so the next firing resumes this procedure.
   - Increment the pending-pass counter in `execution-summary.md`. Do nothing else this turn, the session is free until the wakeup fires.
3. **If all checks have concluded,** evaluate:
   - Any failed check → collect its log link(s).
   - Quality-gate check (e.g. SonarQube): read its conclusion; pull issue details with `"${CLAUDE_PLUGIN_ROOT:-$HOME/.claude}/scripts/ar-sonarqube/fetch-issues.sh"` when available.
   - **Coverage:** read the coverage figure from the quality-gate report/PR comment. Always report it. If `verify_pr.coverage_min` is set and coverage is below it, treat as a failure (add tests for the uncovered changed code, respecting the Change Class policy in Phase 3 step 8).
   - New review comments (human or bot) → count unresolved threads.
4. **All green, coverage OK, no unresolved comments** → report the final summary (checks table + coverage figure), **end the loop** (omit the next `ScheduleWakeup`), and proceed to Phase 5 (Archive) per the normal flow.
5. **Anything failing or commented** → run `ar-taskflow-fix-comments` for this PR (it handles review threads + SonarQube issues + replies/resolution), let it push its fix commits, reset the pending-pass counter, then schedule the next pass (step 2's wakeup) to re-check. Count this as one **fix round**.
6. **Caps, two of them, both durable across wakeups (record counts in `execution-summary.md`):**
   - **Pending-pass cap:** `ceil(verify_pr.timeout_minutes / 4)` consecutive pending passes (≈ 7 at the default 30 min). On reaching it, report which checks are still pending and **end the loop**, don't fix against incomplete signal.
   - **Fix-round cap: 3.** If still not green after 3 fix rounds (step 5), **end the loop** and surface what remains, repeated automated rounds past that point usually mean a real design problem that needs the human.

**⏱ Cost:** this phase waits on CI wall-clock (~20-30 min typical), that's its job; it replaces the human re-checking the PR. With the self-paced loop the session is **idle (not pinned)** between checks, so the wait no longer consumes one long-running turn or re-read the whole conversation uncached on every recheck. It never runs in interactive mode.

**Why a wakeup loop, not in-turn polling (this was a real cost/fragility defect):** the prior 4l blocked a single turn for up to 30 minutes of `sleep`-and-recheck. That pinned context, paid a cold-cache read of the whole conversation on each long wait, and gave the user no clean interruption point. `/loop` + `ScheduleWakeup` is the purpose-built primitive for "wake every few minutes, check external state, act, repeat."

## Phase 5: Archive

**Trigger:** User says "archive task", "move to done", or after PR is merged

**🚨 CRITICAL: Read Configuration First**

Before archiving, you MUST:
1. Read `.claude/skill.config` to get the actual paths
2. Extract `tasks_folder` and `done_folder` values
3. Use the EXACT folder paths from config - NEVER hardcode or guess folder names
4. Common mistake: Using "CompletedTasks" or "Done" instead of configured "DoneTasks"

**Steps:**

1. **Read skill.config and extract paths:**
   ```bash
   cat .claude/skill.config
   ```
   Parse and use the actual `tasks_folder` and `done_folder` values.

2. Run all tests to verify nothing is broken, use the project's test command (`test_command`/`verify.full_command` from `config_hints.json`, else the command documented in the repo):
   ```bash
   ${test_command:-<the project's test command>}
   ```

3. If tests fail → STOP, fix issues first

4. If tests pass → Ask user: "All tests passing. Move to done folder?"

5. If yes, move the task folder using EXACT paths from skill.config:
   ```bash
   mv "{tasks_folder}/{TaskName}" "{done_folder}/{TaskName}"
   ```

   **Example with actual paths (read from config):**
   ```bash
   mv "/path/from/config/OnGoingTasks/{namespace}-195-my-task" "/path/from/config/DoneTasks/{namespace}-195-my-task"
   ```

6. **📤 Push docs checkpoint:** Run push-docs procedure with `"archive {task_name}"`, saves the moved task folder to remote.

7. Confirm: "Task archived to {done_folder_name}."

## Files Created in Task Folder

| File | Who Creates | When | Purpose |
|------|-------------|------|---------|
| `raw_prompt.md` | User or Claude | Phase 0 | Original task description |
| `prompt-understanding.md` | Claude | Phase 1 | Refined, cleaner version of requirements |
| `execution-summary.md` | Claude | Phase 1+ | Session recovery hints (kept small, updated each phase) |
| `execution_plan.md` | Claude | Phase 2 | Implementation plan with branch name |
| `ticket.md` | Claude | Phase 4 | Product-level description for the tracked issue |
| `pr-description.md` | Claude | Phase 4 | PR description for GitHub |

## Ticket Update (Ticket-First Approach)

When a task starts with the **ticket-first approach**, the tracked issue is updated automatically on completion. All tracker calls resolve through the **Tracker Dispatch Table** for the repo's `tracker_type` (see `<standards_location>/mcp-integration.md`); if `tracker_type` is `none`, this is skipped and the work lives in the task-folder docs only. Section 4e above carries the exact per-tracker procedure; this section explains the intent.

### What Happens

**During Phase 0 (Start):**
- Fetch the original issue description via the dispatch table ("Fetch ticket" row)
- Create `raw_prompt.md` with the issue details
- Include an `**Issue:** {link}` header for tracking

**During Phase 4 (Finish):** update the issue via the dispatch table ("Update / comment" row), preserving the original text and recording completion:

- **github (default):** post a completion **comment** (`gh issue comment`). GitHub keeps the original issue body visible in history, so nothing is overwritten. Prefer `Closes #{n}` in the PR body to auto-close on merge.
- **jira / linear:** archive the original description as a comment, replace the description with the `ticket.md` content plus a completion header, then add a completion comment. The archive-then-edit keeps the original text in the comment history.

### Example: Before and After (jira / linear description edit)

For github the completion goes in a comment and the original body stays untouched; the example below shows the jira/linear description-replacement case.

**Original Ticket Description (Before):**
```
Need to simplify the payment API. Frontend is sending too much data.

Acceptance Criteria:
- Reduce request payload size
- Backend should fetch data from database
```

**After Task Completion:**

**Comment 1 (Original Description Archived):**
```
📋 Original Description (Archived on Jan 20, 2026)

Need to simplify the payment API. Frontend is sending too much data.

Acceptance Criteria:
- Reduce request payload size
- Backend should fetch data from database

---
This description was archived when the task was completed.
See updated description above for final implementation details.
```

**Updated Ticket Description:**
```
✅ Task Completed on Jan 20, 2026

## Problem
Frontend was sending redundant data that backend already has in database.

## Solution
Simplified API:
- Frontend now only sends essential IDs
- Backend fetches remaining data from database
- Reduced payload size

## Benefits
- Cleaner API contract
- Less data over network
- Single source of truth (database)

## Acceptance Criteria
✓ Request payload reduced to only essential fields
✓ Backend fetches data from database
✓ All existing tests pass
✓ API documentation updated

---
_Original description archived in comments below._
```

**Comment 2 (Completion Info):**
```
✅ Task Completed

- Branch: feature/{namespace}-195-simplify-api
- Completed by: developer@example.com
- Date: Jan 20, 2026

PR will be created with details from the updated description.
```

### Benefits

1. **Maintains History** - original requirements never lost (github keeps the body; jira/linear archive it to a comment); full audit trail; original vs final comparable.
2. **Updated Documentation** - the issue reflects the actual implementation, with product-level detail and clear acceptance-criteria status.
3. **Automatic Process** - no manual issue updates needed; happens in the normal workflow; never blocks development if the tracker is unreachable.
4. **Team Communication** - clear completion status, what was done, and branch info for review.

### Tracker Requirements

- The repo's `tracker_type` must be reachable: github needs `gh` authenticated (no MCP); jira/linear need their MCP configured (`ar-init-mcps`).
- If the tracker is unreachable → a warning is shown and the workflow continues.
- **Reference:** See `<standards_location>/mcp-integration.md` for the full dispatch table and per-tracker usage patterns.

## Branch Naming

Format: `feature/{lowercase(project_namespace)}-<ticket>-<short-description>`

Examples (for different projects):
- Example (example): `feature/{namespace}-183-simplify-verify-api`
- User Service (SVC): `feature/svc-42-add-auth-endpoint`
- Products (API): `feature/api-204-fix-price-calculation`

If no ticket exists, ask user to create one before commit.

## Quick Commands

| Say | Action |
|-----|--------|
| "ar-taskflow" | Start a NEW task (ticket-first or ticket-late approach) |
| "ar-taskflow-resume" | Resume an EXISTING task from OnGoingTasks |
| "1" or "ticket-first" (after start) | Fetch the issue via the dispatch table (github by default), create raw_prompt.md |
| "2" or "ticket-late" (after start) | Ask for existing task folder path, read raw_prompt.md |
| "ar-init-mcps" | Configure tracker MCP servers (jira/linear; github uses the `gh` CLI, no MCP) |
| "looks good" / "approved" (after prompt-understanding) | Proceed to create execution_plan.md |
| "review plan" | Show plan for approval |
| "start coding" / "approved" (after plan) | ⚠️ Check branch first! Then checkout branch, begin implementation |
| "update plan" | Refresh execution_plan.md with changes |
| "done" / "finished" / "continue" | Create ticket.md + pr-description.md, then commit |
| "commit" / "verify and commit" | 🚨 CHECK BRANCH FIRST! Run safety checks before committing |
| "create ticket" | Generate ticket.md |
| "create PR" | Generate pr-description.md |
| "archive task" | Move task folder to DoneTasks |
| **"ar-taskflow-remember"** or **"remember"** | Quick context recovery when Claude forgets (use ar-taskflow-remember skill) |
| **"fix comments"** / "comments came in" / "got feedback on the PR" / "few more comments, please solve" / "please fix the comments" | Hand off to **ar-taskflow-fix-comments**, fixes feedback AND replies/resolves the review threads (don't fix ad-hoc) |

**Note:** All ticket references use your project's namespace from config_hints.json (e.g., {namespace}-XXX, SVC-XXX, API-XXX).

## Context Recovery

**When Claude forgets or loses track during the same session:**

The user can run `/ar-taskflow-remember` to refresh context instead of doing these steps manually.

**Trigger:** User says "ar-taskflow-remember" or "remember"

**What it does:**
- Quickly re-reads execution-summary.md, execution_plan.md, and prompt-understanding.md
- Checks current git branch
- Presents brief summary of current state
- Gets you back on track without exploring codebase

**See:** the ar-taskflow-remember skill for full details.

**Key difference from ar-taskflow-resume:**
- **ar-taskflow-remember**: Quick context refresh in same session
- **ar-taskflow-resume**: Full session recovery after closing Claude

## Ticket Guidelines

**Good (Product Level):**
```
## Problem
Frontend sends redundant data that backend already has

## Solution
Simplified API - frontend sends only service ID, backend fetches rest from database
```

**Bad (Code Noise):**
```
Updated OrderService.java to call ItemRepository.findById() (example - use your services)
Changed ConfirmItemRequest DTO to remove cityCode field
```

**Allowed Details:**
- API request/response JSON
- Database table and column names
- Configuration values

## Skill Updates

When this skill (ar-taskflow) is updated or requested to be updated, save the update instructions to:

```
{skill_updates_folder}/ar-taskflow-updates.md
```

**Format for updates:**
- Date of update
- What was changed
- Why it was changed
- The actual update content

This ensures all skill modifications are tracked and can be synced across projects.

## Task History Logging

**Purpose:** Track task progress for weekly reports. Tasks are logged to `{coding_tasks_root}/TasksSummary/Backend.md` or `Frontend.md`.

**Note:** The TasksSummary folder is auto-created by ar-init-skills. If it doesn't exist when ar-taskflow runs, create it automatically using `mkdir -p {coding_tasks_root}/TasksSummary`.

### File Format

```markdown
# Backend Tasks Summary

## Week Ending: January 31, 2026

| Task | Owner | Started | Completed | Description | Weekly Summary |
|------|-------|---------|-----------|-------------|----------------|
| {namespace}-193 Fix product validation for checkout flow | dev@example.com | Jan 29 | Jan 30 | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/{namespace}-193.md) |
| {namespace}-191 Payment APIs and confirm API changes | dev@example.com | Jan 28 | Jan 29 | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/{namespace}-191.md) |
| TBD Add document generation endpoint | dev@example.com | Jan 30 | - | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/TBD-add-document-generation.md) |

## Week Ending: January 24, 2026

| Task | Owner | Started | Completed | Description | Weekly Summary |
|------|-------|---------|-----------|-------------|----------------|
| {namespace}-185 Add enrichment endpoint for upstream data | dev@example.com | Jan 22 | Jan 23 | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-24/{namespace}-185.md) |
```

**Note:**
- Task column format: "{Ticket-ID} {Task Title}" for ticket-first approach
- Task column format: "TBD {Task Title}" for ticket-late approach (updated when ticket number is obtained in Phase 4h)
- Description column: Optional additional context (can be left blank if Task column is descriptive enough)

### When to Log

**Task Started (Phase 2):** After `execution_plan.md` is created and approved:

1. **Calculate week ending date** (Friday of current week):
   ```bash
   # If today is Friday, use today. Otherwise, find next Friday.
   if [ "$(date +%u)" = "5" ]; then
     week_date=$(date +%Y-%m-%d)
   else
     week_date=$(date -d "next friday" +%Y-%m-%d 2>/dev/null || date -v +fri +%Y-%m-%d)
   fi

   # Create folder name with "Week-Ending-" prefix
   week_ending="Week-Ending-$week_date"
   ```

2. **Extract task title/description:**

   **Ticket-First Approach:**
   - Use the issue title fetched from the tracker (from `raw_prompt.md` header)
   - Example: "Simplify payment confirmation API"

   **Ticket-Late Approach:**
   - Use the summary from `execution_plan.md` (first section)
   - Example: "Add document generation endpoint for users" (use relevant description for your feature)

   **IMPORTANT:** Description must be a meaningful task title, NOT just the ticket ID.
   - ✅ Good: "Simplify payment confirmation API"
   - ❌ Bad: "{namespace}-195" or empty

3. **Create weekly summary folder** if it doesn't exist:
   ```bash
   mkdir -p "{coding_tasks_root}/WeeklySummaries/$week_ending"
   ```

   Example folder: `WeeklySummaries/Week-Ending-2026-01-31`

4. **Create individual weekly summary file** for this task:

   **For Ticket-First Approach:**
   ```bash
   # File: {coding_tasks_root}/WeeklySummaries/{week_ending}/{start_date}_{platform}_{TICKET-ID}-{sanitized-title}.md
   # Example: WeeklySummaries/Week-Ending-2026-01-31/2026-01-28_Backend_{namespace}-195-simplify-payment-api.md
   ```
   Content template:
   ```markdown
   # {Task Title}

   **Date:** {start_date} | **Developer:** {developer_email} | **Platform:** {Backend|Frontend}

   **What:** (in progress - brief description of what the problem was, 1-2 sentences)

   **Fix:** (in progress - brief description of what was done, 1-2 sentences)
   ```

   **For Ticket-Late Approach (ticket number not yet known):**
   ```bash
   # File: {coding_tasks_root}/WeeklySummaries/{week_ending}/{start_date}_{platform}_TBD-{sanitized-title}.md
   # Example: WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_TBD-add-document-generation.md
   ```
   Content template:
   ```markdown
   # {Task Title}

   **Date:** {start_date} | **Developer:** {developer_email} | **Platform:** {Backend|Frontend}

   **What:** (in progress - brief description of what the problem was, 1-2 sentences)

   **Fix:** (in progress - brief description of what was done, 1-2 sentences)
   ```

   **Note:** For ticket-late, this file will be renamed and updated in Phase 4h when ticket number is obtained.

5. **Add row to TasksSummary** (Backend.md or Frontend.md):

   **Format:** `| Task | Owner | Started | Completed | Description | Weekly Summary |`

   **For Ticket-First Approach:**
   - **Task** - "{Ticket ID} {Task Title}" (e.g., "{namespace}-195 Simplify payment confirmation API")
   - **Owner** - From git config (e.g., dev@example.com)
   - **Started** - Current date (e.g., Jan 29)
   - **Completed** - Leave empty, marked as `-`
   - **Description** - Additional context or leave blank if title is descriptive enough
   - **Weekly Summary** - Link: `[Link](../../WeeklySummaries/{week_ending}/{start_date}_{platform}_{TICKET-ID}-{sanitized-title}.md)`
   - Example: `[Link](../../WeeklySummaries/Week-Ending-2026-01-31/2026-01-28_Backend_{namespace}-195-simplify-payment-api.md)`

   **For Ticket-Late Approach (ticket number not yet known):**
   - **Task** - "TBD {Task Title}" (e.g., "TBD Add document generation endpoint")
   - **Owner** - From git config (e.g., dev@example.com)
   - **Started** - Current date (e.g., Jan 29)
   - **Completed** - Leave empty, marked as `-`
   - **Description** - Additional context or leave blank
   - **Weekly Summary** - Link: `[Link](../../WeeklySummaries/{week_ending}/{start_date}_{platform}_TBD-{sanitized-title}.md)`
   - Example: `[Link](../../WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_TBD-add-document-generation.md)`

   **Note:** For ticket-late, this entry will be updated in Phase 4h when ticket number is obtained.

**Task Completed (Phase 4):** After `pr-description.md` is created:

1. **Update TasksSummary row:**
   - Fill in the Completed date

2. **Update weekly summary file:**
   - Update the **What** section with a brief description of what the problem was (1-2 sentences)
   - Update the **Fix** section with a brief description of what was done (1-2 sentences)
   - Keep it concise - no detailed technical breakdown
   - The detailed information stays in the task folder (execution_plan.md, pr-description.md)

### Week Grouping Rules

- Each week ends on **Friday**
- Calculate week ending: Find the next Friday from current date
- If today is Friday, use today's date
- Tasks appear under the week they were **started**
- If week section doesn't exist, create it (newest weeks at top)

### Determining Platform

Use the `platform` field from `config_hints.json`:
- `"Backend"` → Log to `Backend.md`
- `"Frontend"` → Log to `Frontend.md` (Web)
- `"iOS_Frontend"` → Log to `iOS_Frontend.md`
- `"Android_Frontend"` → Log to `Android_Frontend.md`

The platform is selected by the user during `init skills` and stored in `config_hints.json`.

### Getting Owner

```bash
git config user.email
```

Use the email address as owner (e.g., `dev@example.com`)

### Getting Task Title for Task Column

**The Task column format is now: "{Ticket-ID} {Task Title}" or "TBD {Task Title}"**

**Sources for Task Title (in order of preference):**

1. **Ticket-First:** Use the issue title from the tracker
   - Read from `raw_prompt.md` first line after `# ` header
   - Example: `# Simplify Payment Confirmation API` → "{namespace}-195 Simplify Payment Confirmation API"

2. **Ticket-Late:** Use execution plan summary
   - Read from `execution_plan.md` summary section
   - Should be a clear, one-line description of what the task does
   - Example: "Add document generation endpoint" → "TBD Add document generation endpoint"
   - Will be updated to "{namespace}-275 Add document generation endpoint" in Phase 4h when ticket number is obtained

3. **Fallback:** Parse from task folder name
   - Task folder: `{namespace}-195-simplify-payment-api`
   - Task column: "{namespace}-195 Simplify payment API" (humanize from folder name)

**Important:**
- Task column MUST include both ticket ID and title (or "TBD" + title for ticket-late)
- Description column is now optional and can be used for additional context
- Never use just the ticket ID alone in the Task column

### Example Log Entry Flow

**Ticket-First Approach:**

**Phase 2 (Task Started):**
```markdown
| {NAMESPACE}-195 Simplify API | dev@example.com | Jan 29 | - | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_{NAMESPACE}-195-simplify-api.md) |
```

✅ Task column has ticket number AND title

Weekly summary file created at: `WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_{NAMESPACE}-195-simplify-api.md`

**Phase 4 (Task Completed):**
```markdown
| {NAMESPACE}-195 Simplify API | dev@example.com | Jan 29 | Jan 30 | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_{NAMESPACE}-195-simplify-api.md) |
```

Weekly summary file updated with completion details.

**Ticket-Late Approach:**

**Phase 2 (Task Started - ticket number not yet known):**
```markdown
| TBD Add endpoint | dev@example.com | Jan 29 | - | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_TBD-add-endpoint.md) |
```

✅ Task column uses "TBD" placeholder with title

Weekly summary file created at: `WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_TBD-add-endpoint.md`

**Phase 4h (Ticket number obtained - {NAMESPACE}-275):**
```markdown
| {NAMESPACE}-275 Add endpoint | dev@example.com | Jan 29 | - | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_{NAMESPACE}-275-add-endpoint.md) |
```

✅ Task column updated with actual ticket number
✅ Weekly summary file renamed from `2026-01-29_Backend_TBD-add-endpoint.md` to `2026-01-29_Backend_{NAMESPACE}-275-add-endpoint.md`

**Phase 4 (Task Completed):**
```markdown
| {NAMESPACE}-275 Add endpoint | dev@example.com | Jan 29 | Jan 30 | Additional context | [Link](../../WeeklySummaries/Week-Ending-2026-01-31/2026-01-29_Backend_{NAMESPACE}-275-add-endpoint.md) |
```

Weekly summary file updated with completion details.

## Path Configuration Rules

**IMPORTANT:** Never hardcode full paths. See the ar-init-skills skill for the full two-file configuration approach (`skill.config` + `config_hints.json`).

Phase 0 of this skill already reads and derives all paths. If you need a refresher, the key rules are:
- `skill.config` = user-specific absolute paths (NOT committed)
- `config_hints.json` = project metadata (IS committed, no absolute paths)
- All paths derived at runtime from `tasks_root` and `docs_root`

## Rule Detection

During Phase 1 (Prompt Understanding), analyze the raw prompt to identify which coding rules are especially relevant. This ensures context-specific rules are surfaced and followed during coding.

### Detection Map

Match the task against the rules **actually installed in `<standards_location>/`**, never reference a rule the project doesn't have:

1. List the `.md` files in `<standards_location>/`.
2. For each, derive its topic from the filename and match it against the task/diff (e.g. a `database-*` rule → DB/query/migration work; an `api-*`/`*-handlers` rule → endpoint work; `error-handling` → error paths; `observability` → metrics/tracing; `security` → auth/secrets; `*test*` / `test-change-policy` → test changes).
3. Load every rule that matches.

**Always-apply rules** (every task, load whichever the project installed): `critical-thinking.md`, `test-change-policy.md`, `test-scope-policy.md`, the project's coding-conventions rule, and the project's structure rule.

**Note:** A single task can match multiple rules. List all that apply **and exist in `<standards_location>`**, never invent a reference.

### How It Flows

1. **Phase 1 → Detect:** After writing prompt-understanding.md, scan content against the Detection Map. Append `## Applicable Rules` section listing matched rules with one-line reasoning.
2. **Phase 3 → Apply:** Before coding, read each .md file listed in prompt-understanding.md. Follow their patterns and checklists during implementation.

## References

### Coding Rules

The project's coding rules live in `<standards_location>/`. Read that directory to see which rules this project has installed (they vary by stack) and apply the ones relevant to your change, see the Detection Map above. Always-present universal rules include `critical-thinking.md`, `code-review.md`, `test-change-policy.md`, `test-scope-policy.md`, and `mcp-integration.md`.

**Always refer to the project's installed rules during implementation to ensure consistency.**
