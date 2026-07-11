---
name: ar-taskflow-progress-fixer
description: Reconcile workspace state against reality. Catches dangling Phase-4 tasks not archived, mismatched branches, stale execution-summary state, missing TasksSummary rows, PR-merge gaps, and docs-repo drift. Renamed from ar-taskflow-inspector in v6.6.0. Say "ar-taskflow-progress-fixer" or "reconcile tasks".
disable-model-invocation: true
---

# Task Flow Progress Fixer

Workspace state ↔ reality reconciliation. Surfaces tasks that should be archived but aren't, branches that don't match what `execution_plan.md` says, PR-merge gaps the team forgot to follow up on, and docs-repo drift that silently corrupts everyone's local copy.

Scan → Check → Report → Fix → Push.

## 🧭 Learning routing, no personal auto-memory

This skill follows the framework's **learning-routing** rule (`rules/universal/learning-routing.md`). Any learning that surfaces during reconciliation routes to one of three destinations:

1. **Project rule** (`docs/ai-rules/<topic>.md`), for project conventions discovered while resolving drift.
2. **Framework improvement** (via `ar-record-improvement`), for framework-level issues that produced the drift in the first place.
3. **Conversational only**, one-off preferences for this reconciliation pass.

Personal auto-memory (`~/.claude/projects/<project>/memory/`) is **not consulted, cited, or written** during this skill.

## Why this skill exists

`ar-taskflow` writes a lot of artifacts per task (`execution_plan.md`, `acceptance_criteria.json`, `execution-summary.md`, `ticket.md`, `pr-description.md`, `TasksSummary/<Platform>.md` rows, `WeeklySummaries/` files). These artifacts drift from reality:

- A PR gets merged but the task folder never moves to `DoneTasks/`
- `execution-summary.md` still says "PR not yet created" days after the PR is open
- The branch named in `execution_plan.md`'s Execution Tracking block doesn't actually exist
- Worktree branch mapping in execution-summary points at a stale remote
- The docs-repo is 92 commits behind origin, so the scan is operating on stale data

This skill reconciles each against actual git/GitHub state, then offers safe auto-fixes for the unambiguous cases.

## When to Run

- Periodic hygiene check on task workspace (weekly recommended)
- Before generating a weekly report (`ar-weekly-report` is much more accurate when the workspace is reconciled first)
- When you suspect tasks fell through the cracks
- After returning from a vacation / context switch
- Developer says "ar-taskflow-progress-fixer", "reconcile tasks", or "inspect tasks"

## Pre-Product

**Read configuration and derive paths:**

```bash
if [ ! -f ".claude/skill.config" ]; then
  echo "❌ .claude/skill.config not found. Run 'ar-init-skills' first."
  exit 1
fi

tasks_root=$(jq -r '.paths.tasks_root' .claude/skill.config)
coding_tasks_root=$(dirname "$tasks_root")
task_summary_folder="$coding_tasks_root/TasksSummary"
weekly_summaries_folder="$coding_tasks_root/WeeklySummaries"
project_namespace=$(jq -r '.project.namespace // .project.default_namespace // ""' .claude/config_hints.json)
```

### Pre-Product Check 0: Docs-Repo Sync State (HARD GATE, new in v6.6.0)

**Why:** If the workspace docs-repo is behind origin, every other check operates on stale data. Warning about "missing TasksSummary rows" when the rows were already added by a colleague yesterday wastes time and erodes trust in the skill.

```bash
cd "$coding_tasks_root"
git fetch --quiet 2>/dev/null

dirty=$(git status --porcelain | wc -l | tr -d ' ')
behind=$(git rev-list --count HEAD..@{upstream} 2>/dev/null || echo 0)
ahead=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo 0)
```

**Decision matrix:**

| Local state | Behind | Ahead | Action |
|---|---|---|---|
| Clean | 0 | 0 | ✅ Proceed |
| Clean | 1-5 | 0 | ⚠️ Warn, offer fast-forward pull, proceed after pull |
| Clean | 6+ | 0 | 🚧 HARD STOP. Tell user to pull manually. Don't auto-pull >5 commits worth of unseen changes. |
| Clean | any | 1-10 | ℹ️ Inform user, offer push at end (proceed) |
| Dirty | any | any | 🚧 HARD STOP. Uncommitted changes risk being lost or polluting the progress-fixer's auto-fixes. |
| Clean | ≥6 AND ahead ≥1 | | 🚧 HARD STOP. Diverged. User must rebase or merge manually. |

**Output the gate result before any other scanning.** cd back before continuing.

### Pre-Product: Determine platforms

```bash
platforms_json=$(jq -c '.platforms // []' .claude/config_hints.json)
if [ "$platforms_json" = "[]" ]; then
  single_platform=$(jq -r '.platform // ""' .claude/config_hints.json)
  if [ -n "$single_platform" ] && [ "$single_platform" != "null" ]; then
    platforms=("$single_platform")
  else
    platforms=()
    for candidate in Backend Frontend iOS Android; do
      if [ -d "$coding_tasks_root/$candidate/OnGoingTasks" ] || [ -d "$tasks_root/OnGoingTasks" ]; then
        platforms+=("$candidate")
      fi
    done
  fi
else
  platforms=($(echo "$platforms_json" | jq -r '.[]'))
fi
```

**For each platform, derive paths:**

```bash
if [ -d "$tasks_root/OnGoingTasks" ]; then
  ongoing_folder="$tasks_root/OnGoingTasks"
  done_folder="$tasks_root/DoneTasks"
else
  ongoing_folder="$coding_tasks_root/${platform}/OnGoingTasks"
  done_folder="$coding_tasks_root/${platform}/DoneTasks"
fi
summary_file="$task_summary_folder/${platform}.md"
github_repo=$(jq -r ".github_repos.${platform} // \"\"" .claude/config_hints.json)
project_repo_root=$(jq -r ".project_repo_root // \"\"" .claude/config_hints.json)
```

**Validate:**
- At least one platform must have an existing `ongoing_folder`. If none → report "No OnGoingTasks folders found" and stop.
- `summary_file`, note if missing.
- `github_repo`, if empty for a platform, note once and skip PR-merge checks for that platform.
- `project_repo_root`, optional; if empty, Check 9 (Branch Reality) is skipped with a one-line note.

## Step 1, Discover

For each platform with an existing `ongoing_folder`:

```bash
ls -1d "$ongoing_folder"/*/
```

For each task folder, record:
- **Platform**
- **Folder name** (e.g., `PROJ-195-simplify-api` or `TBD-add-endpoint`)
- **Files present:** `raw_prompt.md`, `prompt-understanding.md`, `executive_summary.md`, `execution_plan.md`, `acceptance_criteria.json`, `execution-summary.md`, `ticket.md`, `pr-description.md`
- **Last modified date:** most recent file mtime in the folder

**If no task folders found across all platforms:** `"No tasks in OnGoingTasks/. Nothing to reconcile."` and stop.

## Step 2, Analyze

Run the checks below on each task folder.

### Check 1: Phase Detection

| Files Present | Phase | Label |
|---|---|---|
| Only `raw_prompt.md` | 0 | Initialized |
| + `prompt-understanding.md` | 1 | Understood |
| + `execution_plan.md` | 2/3 | Planned / Coding |
| + `ticket.md` AND `pr-description.md` | 4 | Complete |

**No `raw_prompt.md`:** Flag as INVALID, not a proper task folder.

### Check 2: Not Archived (PR-merge-gated)

**Condition:** Phase = 4 but still in `OnGoingTasks/`.

Only flag as auto-fixable WARNING if Check 7 returns `MERGED` AND the `baseRefName` is `main`. Otherwise:
- PR exists, merged, but base is non-main → INFO ("merged to {baseRefName}, not yet shipped to main")
- PR exists but is still open → INFO ("Phase 4 but PR not yet merged")
- No PR found on GitHub → INFO ("Phase 4 but no PR found on GitHub")

### Check 3: TasksSummary Gaps

Three sub-checks against `$summary_file`:

**3a, Missing row:** Task folder exists but no matching row.
- WARNING if Phase 2+; INFO if Phase 0-1.

**3b, Missing completion date:** Row exists, Phase = 4, but Completed column is `-`.
- WARNING.

**3c, Broken WeeklySummary link:** Row has a `[Link](...)` but the file doesn't exist.
- WARNING.

**If `$summary_file` doesn't exist:** Flag once as WARNING and skip sub-checks.

### Check 4: Missing Phase Files

For a task at phase N, earlier phase files should exist:
- Phase 1+ requires `raw_prompt.md`
- Phase 2+ requires `prompt-understanding.md`
- Phase 4 requires `execution_plan.md`

WARNING for any gap.

### Check 5: TBD Ticket

Folder name starts with `TBD-`.
- INFO if Phase 0-2; WARNING if Phase 3+.

### Check 6: Stale Task

```bash
last_modified=$(stat -f "%m" "$folder"/* | sort -rn | head -1)
days_stale=$(( ( $(date +%s) - last_modified ) / 86400 ))
```

INFO if 7-14 days; WARNING if 14+ days.

### Check 7: PR Merge Verification

Squash-and-merge breaks `git log --merges`, so search by ticket ID in PR titles with strict title-text validation.

**Resolve repo:**
```bash
github_repo=$(jq -r ".github_repos.${platform} // \"\"" .claude/config_hints.json)
```
If empty, skip Check 7 for this task.

**Extract ticket ID:**
1. From folder name: `{NAMESPACE}-XXX` using `project_namespace`
2. For TBD folders: read `ticket.md` or `pr-description.md` for `{NAMESPACE}-XXX`
3. If still no ID → skip Check 7 for this task

**Query GitHub:**
```bash
gh pr list --repo "$github_repo" --state merged --search "$ticket_id in:title" --json number,title,mergedAt,baseRefName --limit 3
gh pr list --repo "$github_repo" --state open   --search "$ticket_id in:title" --json number,title,baseRefName --limit 3
```

**Validate** the ticket ID appears verbatim in the returned PR title.

**Result states:**

| Merged | Open | Result |
|---|---|---|
| Yes (base=main) |, | `MERGED (PR #{n}, merged {date}, base: main)`, auto-archive eligible |
| Yes (base≠main) |, | `MERGED_NONMAIN (PR #{n}, merged into {base})`, NOT auto-archive eligible |
| No | Yes | `PR_OPEN (PR #{n}, base: {base})` |
| No | No | `NO_PR` |

### Check 8: Execution-Summary Freshness (NEW in v6.6.0)

`execution-summary.md` is the file `ar-taskflow-resume` and `ar-taskflow-remember` rely on. Stale = wrong decisions.

**Two sub-checks:**

**8a, Plan-newer-than-summary:**
```bash
plan_mtime=$(stat -f "%m" "$folder/execution_plan.md" 2>/dev/null || echo 0)
summary_mtime=$(stat -f "%m" "$folder/execution-summary.md" 2>/dev/null || echo 0)
if [ "$summary_mtime" -lt "$plan_mtime" ] && [ "$plan_mtime" -gt 0 ]; then
  STALE_SUMMARY=true
fi
```
Plan changed after summary was last updated. Summary is lying about current state. WARNING for Phase 2+.

**8b, Stale PR section:**
```bash
if grep -q "PR not yet created" "$folder/execution-summary.md" 2>/dev/null \
   && { [ "$check7_result" = "MERGED" ] || [ "$check7_result" = "PR_OPEN" ] || [ "$check7_result" = "MERGED_NONMAIN" ]; }; then
  STALE_PR_SECTION=true
fi
```
Summary still says "PR not yet created" but a real PR exists. WARNING.

Fix is informational, point the user at the stale file. The progress-fixer does not auto-rewrite execution-summary because it carries high-context state (Q&A log, decisions, next steps).

### Check 9: Branch Reality (NEW in v6.6.0)

The branch named in `execution_plan.md`'s `## Execution Tracking` block must exist (locally or on origin) for Phase 3+ tasks. If it doesn't, PR target and push are pointed at the wrong place.

**Requires:** `project_repo_root` in `config_hints.json`. Skip Check 9 if absent.

```bash
declared_branch=$(grep -oE '^- \*\*Branch:\*\* `?[^`]+`?' "$folder/execution_plan.md" 2>/dev/null \
  | sed 's/^- \*\*Branch:\*\* `*//; s/`*$//' | head -1)

if [ -n "$declared_branch" ] && [ -n "$project_repo_root" ]; then
  local_exists=$(git -C "$project_repo_root" show-ref --verify --quiet "refs/heads/$declared_branch" && echo yes || echo no)
  remote_exists=$(git -C "$project_repo_root" show-ref --verify --quiet "refs/remotes/origin/$declared_branch" && echo yes || echo no)

  if [ "$local_exists" = "no" ] && [ "$remote_exists" = "no" ]; then
    BRANCH_MISSING=true
  fi
fi
```

- WARNING for Phase 3+ tasks (you're actively coding; branch should exist)
- INFO for Phase 2 (branch may not be created yet)

### Check 10: Worktree Mapping Reality (NEW in v6.6.0)

If `execution-summary.md` mentions Worktree Local/Remote Branch lines, validate against `git worktree list`. A wrong mapping silently pushes to the wrong remote.

**Requires:** `project_repo_root` in `config_hints.json`. Skip Check 10 if absent.

```bash
worktree_local=$(grep -oE 'Worktree Local Branch[: ]+`?[^`]+`?' "$folder/execution-summary.md" 2>/dev/null \
  | sed 's/.*: *`*//; s/`*$//' | head -1)
worktree_remote=$(grep -oE 'Remote Branch[: ]+`?[^`]+`?' "$folder/execution-summary.md" 2>/dev/null \
  | sed 's/.*: *`*//; s/`*$//' | head -1)

if [ -n "$worktree_local" ] && [ -n "$project_repo_root" ]; then
  # Get the actual worktree list
  actual=$(git -C "$project_repo_root" worktree list --porcelain 2>/dev/null \
    | awk '/^branch/ {sub(/^branch refs\/heads\//, ""); print}')

  if ! echo "$actual" | grep -qx "$worktree_local"; then
    WORKTREE_MAPPING_WRONG=true
  fi
fi
```

WARNING. A wrong worktree mapping is exactly the silent-corruption case the progress-fixer exists to catch.

## Step 3, Report

Output a structured report, grouped by platform when more than one is in scope.

**Single-platform format:**

```markdown
# Task Flow Progress Fixer Report

**Docs-repo state:** ✅ clean, in sync with origin
**Scanned:** {n} tasks in OnGoingTasks/ ({platform})
**Issues:** {n} total, {n} WARNING, {n} INFO
**Clean:** {n} tasks with no issues

## Task Status

| # | Task | Phase | Merge Status | Issues |
|---|------|-------|--------------|--------|
| 1 | PROJ-195-simplify-api | 4 (Complete) | MERGED (PR #50, base:main) | NOT_ARCHIVED, COMPLETION_DATE |
| 2 | PROJ-200-fix-auth | 3 (Coding) | NO_PR | BRANCH_MISSING, STALE_SUMMARY |
| 3 | PROJ-210-add-cache | 4 (Complete) | MERGED (PR #88, base:story/X) | NOT_TRULY_SHIPPED |

## Findings

### ⚠️ Not Archived (PR merged to main)
- **PROJ-195-simplify-api**, PR #50 merged Jan 18 to main. Should be in DoneTasks/.

### ⚠️ Not Truly Shipped (merged to non-main base)
- **PROJ-210-add-cache**, PR #88 squashed into `story/X`, not main. Treat as In progress, do not archive.

### ⚠️ Stale execution-summary
- **PROJ-200-fix-auth**, execution-summary.md older than execution_plan.md. Re-sync needed.

### ⚠️ Branch Mismatch
- **PROJ-200-fix-auth**, execution_plan declares branch `feature/proj-200-fix-auth`, but no such branch exists locally or on origin.

### ⚠️ TasksSummary Gaps
- **PROJ-195-simplify-api**, Row exists but Completed = `-` (Phase 4 is done)
```

**Multi-platform format:** Add platform breakdown to header; prefix every task name with `[{platform}]`.

**If no issues:** `"All {n} tasks across {platforms} are reconciled. No issues found."`

## Step 4, Offer Fixes

**Auto-fixable:**
1. Archive tasks with `MERGED` to `main` base + Phase 4
2. Fill completion dates from `mergedAt`
3. Fast-forward pull docs-repo when behind ≤5 commits (offered in Pre-Product 0)

**Manual-action items (informational only):**
1. Stale execution-summary → user re-syncs
2. Stale PR section in execution-summary → user updates
3. Branch mismatch → user investigates
4. Worktree mapping mismatch → user fixes manually
5. Tasks merged to non-main base → user decides whether to keep waiting or escalate
6. TBD ticket → user obtains ticket number from Jira
7. Stale task → user resumes or archives

**Require explicit approval before any auto-fix.**

## Step 5, Apply Fixes

### Archive Fix

**Pre-condition:** PR confirmed `MERGED` AND `baseRefName == main`. Refuse otherwise.

```bash
mkdir -p "$done_folder"
mv "$ongoing_folder/{task_name}" "$done_folder/{task_name}"
```

### Add Missing TasksSummary Row

Extract title/start-date, compute week-ending Friday, insert row, create WeeklySummary file if missing.

### Fill Completion Date

Prefer `mergedAt` from GitHub; fall back to `pr-description.md` mtime, then today.

### Post-Fix: Push Docs

Follow Push-Docs Procedure from the ar-taskflow skill. Commit message: `"ar-taskflow-progress-fixer: {n} fixes applied"`.

### Post-Fix: Verify

Re-run affected checks; output before/after.

## Configuration reference

```json
{
  "project": { "namespace": "PROJ" },
  "platforms": ["Backend", "Frontend"],
  "github_repos": {
    "Backend": "your-org/example-service",
    "Frontend": "your-org/example-web"
  },
  "project_repo_root": "~/repos/example/example-service"
}
```

- `project.namespace`, ticket ID prefix (e.g., `PROJ` for `PROJ-195`)
- `platforms`, explicit list; falls back to `.platform` for single-platform projects
- `github_repos.<platform>`, repo for PR-merge checks; required for Check 7
- `project_repo_root`, path to the project code repo; enables Checks 9 (Branch Reality) and 10 (Worktree Mapping). Optional but recommended.

## Renamed from ar-taskflow-inspector (v6.6.0)

This skill was previously called `ar-taskflow-inspector`. The rename reflects what the skill actually does: reconcile workspace state against reality (PR merge state, branch existence, summary freshness, archive state). Projects upgrading from v6.5.0 or earlier get the directory renamed automatically by `ar-upgrade`'s migration step.
