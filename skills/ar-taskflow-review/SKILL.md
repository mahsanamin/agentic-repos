---
name: ar-taskflow-review
description: Reviews code changes in ar-taskflow workflow against coding rules. Integrates with task folders, tracks iterations. Use after code implementation. Say "ar-taskflow-review" or "review".
disable-model-invocation: false
---

# Task Flow Review

Comprehensive code review that compares current branch changes with main branch and validates against all coding rules.

## 🧭 Learning routing

Follow the rule at `<standards_location>/learning-routing.md` (resolve `standards_location` from `.claude/config_hints.json`): route any learning to a project rule (`docs/ai-rules/`), a framework improvement (`ar-record-improvement`), or conversational-only, never personal auto-memory.

## When to Use

- **During ar-taskflow**: After code implementation is complete and ready to commit/push
- **Before creating a pull request**: Final validation before PR
- **After completing a feature**: Verify code quality and standards compliance
- **Standalone review**: Analyze any branch changes against project patterns

## What It Does

1. **Detect Context** - Determines if running within ar-taskflow or standalone
2. **Generate Diff** - Creates detailed diff comparing current branch with main
3. **Load Coding Rules** - Reads all coding standards files from the project's standards directory
4. **Analyze Changes** - Reviews code against:
   - Critical thinking guidelines
   - Architecture patterns (module structure, layer separation)
   - Database conventions (migrations, JPA, transactions)
   - API conventions (REST patterns, error handling)
   - Code quality (N+1 queries, metrics collection)
5. **Generate Report** - Saves review logs with:
   - ✅ What's done well
   - ⚠️ Potential issues
   - ❌ Violations that must be fixed
   - 💡 Suggestions for improvement
6. **Track Iterations** - Maintains review history with fix logs

## How to Use

### Within ar-taskflow
```
# During Code phase of ar-taskflow, after implementation:
> "ar-taskflow-review"

# Reviews are saved to: reviews_root/<branch>/review-report.md
# Each review iteration is appended with timestamp
```

### Standalone
```
> "ar-taskflow-review"

# Asks for task folder path OR saves to .claude/reviews/
```

## Review Output Location

All review files go to `reviews_root` from `.claude/skill.config`, fully **git-ignored**. This skill does not modify any **tracked** files; its only writes inside the repo tree are review artifacts to the git-ignored `reviews_root` / `.claude/reviews/` fallback. These paths MUST be git-ignored, this is guaranteed at install time (`.claude/reviews/` and `.claude/skill.config` are in `.gitignore`). The "nothing committed" guarantee depends on that gitignore coverage: if `.claude/reviews/` were NOT git-ignored, the review artifacts would dirty the repo.

```
{reviews_root}/                              ← e.g., .../Backend/CodeReviews/
└── feature-{namespace}-372-batch-cancel-api/         ← Named by branch
    ├── review.diff                          ← Latest diff (overwritten each run)
    └── review-report.md                     ← Review iterations (appended)
```

No **tracked** file is modified, the review is a local working artifact written only to the git-ignored `reviews_root`. If you need a permanent record, use `a_sk_review_pr` to post comments on the PR itself.

## Implementation

When this skill is invoked, follow these steps:

### 1. Detect Mode and Task Folder

```bash
# Read skill config
if [ ! -f ".claude/skill.config" ]; then
  MODE="standalone"
else
  tasks_root=$(jq -r '.paths.tasks_root' .claude/skill.config)
  tasks_folder="$tasks_root/OnGoingTasks"

  # Try to auto-detect current task from branch name or ask user
  current_branch=$(git branch --show-current)

  # Check if branch name matches a task folder
  # Example: feature/{namespace}-123 matches {namespace}-123-description
  ticket_prefix=$(echo "$current_branch" | grep -oEi '[A-Za-z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]')

  if [ -n "$ticket_prefix" ]; then
    # Find matching task folder
    task_folder=$(find "$tasks_folder" -maxdepth 1 -type d -name "${ticket_prefix}*" | head -1)

    if [ -n "$task_folder" ]; then
      MODE="ar-taskflow"
      echo "Detected task folder: $task_folder"
    else
      MODE="standalone"
      echo "No matching task folder found for $ticket_prefix"
    fi
  else
    MODE="standalone"
  fi
fi

echo "Review mode: $MODE"
```

### 2. Determine Review Output Path

All review artifacts go to the `reviews_root` from `.claude/skill.config`, fully git-ignored, nothing committed.

```bash
# Read reviews_root from skill.config
reviews_root=$(jq -r '.paths.reviews_root // ""' .claude/skill.config 2>/dev/null)

# Fallback if not configured
if [ -z "$reviews_root" ]; then
  reviews_root=".claude/reviews"
fi

# Create review folder named by branch
current_branch=$(git branch --show-current)
sanitized_branch=$(echo "$current_branch" | tr '/' '-')
review_dir="$reviews_root/$sanitized_branch"
mkdir -p "$review_dir"

review_file="$review_dir/review-report.md"
diff_file="$review_dir/review.diff"

# Remove existing diff file to always have latest version
[ -f "$diff_file" ] && rm -f "$diff_file"

echo "Review will be saved to: $review_dir (git-ignored)"
```

### 3. Generate Diff

```bash
current_branch=$(git branch --show-current)

# Detect base branch (main or master)
base_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$base_branch" ]; then
  git rev-parse --verify origin/main >/dev/null 2>&1 && base_branch="main" || base_branch="master"
fi

echo "Generating diff: $current_branch vs $base_branch"

# Diff scope = everything this branch introduces vs the base, INCLUDING any
# uncommitted working-tree edits (mixed state). Diffing from the merge-base to the
# working tree captures committed + uncommitted in one pass and stays correct even
# if the base branch advanced since this branch was cut.
merge_base=$(git merge-base "$base_branch" HEAD)
diff_scope="$merge_base"
committed_changes=$(git log --oneline "$base_branch..HEAD" | wc -l | tr -d ' ')
uncommitted_changes=$(git status --porcelain | wc -l | tr -d ' ')

if [ "$committed_changes" -gt 0 ] && [ "$uncommitted_changes" -gt 0 ]; then
  diff_type="Committed + uncommitted changes"
elif [ "$committed_changes" -gt 0 ]; then
  diff_type="Committed changes"
else
  diff_type="Uncommitted changes"
fi

git diff "$diff_scope" > "$diff_file"

echo "Diff type: $diff_type"
echo "Stats:"
git diff --stat "$diff_scope"
```

### 4. Load Coding Rules

```bash
# Read standards_location from config_hints.json
standards_dir=$(jq -r '.standards_location // "docs/ai-rules"' .claude/config_hints.json 2>/dev/null || echo "docs/ai-rules")
echo "Loading coding rules from: $standards_dir"
coding_rules=$(find "$standards_dir" -name "*.md" -type f | sort)
echo "$coding_rules"
```

### 5. Run Code Review Analysis

Use the Task tool with the project-specific code reviewer agent:

**Note**: This uses your project's own code reviewer agent if one exists (a `*-code-reviewer` agent under `.claude/agents/` that understands your project's patterns and coding rules). If none exists, it falls back to the general `a_sag_code_reviewer` agent from agentic-devkit.

```
Task(
  subagent_type="a_sag_code_reviewer",  # or your project-specific reviewer
  description="Review code against rules",
  prompt="Review the code changes in {diff_file} against coding rules.

  Branch: {current_branch} vs {base_branch}
  Diff type: {diff_type}

  ## IMPORTANT: Read coding rules BEFORE reviewing

  Read .claude/config_hints.json to find the standards_location.
  Then read ALL *.md files in that directory, these are the coding rules.
  Apply ONLY rules relevant to the patterns you see in the diff.

  For each file in the diff:
  1. Identify what changed (transactions, queries, schema, endpoints, etc.)
  2. Read the FULL source file for context, not just the diff
  3. Apply the matching coding rules
  4. Cite file:line and the specific rule violated

  ## Output Format

  Generate comprehensive review with:

  ## Review Iteration {iteration_number}
  **Date**: {timestamp}
  **Branch**: {current_branch}
  **Files Changed**: {count}

  ### Changes Summary
  [Brief overview of what changed - be specific about what types of changes]

  ### ✅ Passes
  [Things done correctly - be specific with file:line references]
  [Example: \"✅ <file>:45 - Batch-loads records upfront, avoiding N+1\"]

  ### ⚠️ Warnings
  [Potential issues to review - may not be blocking]
  [Example: \"⚠️ <file>:89 - transactional block is 35 lines, may contain non-DB logic\"]

  ### ❌ Issues (Must Fix)
  [Violations that block merge - with file:line references and rule citations]
  [Example: \"❌ DataService.java:156 - repository.findById() inside forEach loop (N+1 query)
  Rule: query-efficiency.md Pattern 1 - batch-load IDs upfront instead\"]

  ### 💡 Suggestions
  [Improvements to consider - reference specific patterns from rules]
  [Example: \"💡 Consider DataContext pattern (see query-efficiency.md) for 3+ lookups\"]

  ### Verdict
  [APPROVED / NEEDS WORK / BLOCKED]

  ### Next Steps
  [Actionable items to address issues with references to patterns in coding rules]

  ---

  If this is a re-review (review-report.md already exists):
  - Read the previous review iterations first
  - Note which previous issues were fixed
  - Identify any new issues introduced
  - Track progress iteration over iteration
  "
)
```

### 6. Save Review Report

Save the agent's output to the review folder (git-ignored, local reference only):

```bash
if [ -f "$review_file" ]; then
  # Append new iteration to existing review report
  echo "" >> "$review_file"
  echo "---" >> "$review_file"
  echo "" >> "$review_file"
  cat {agent_output} >> "$review_file"
  iteration=$(grep -c "## Review Iteration" "$review_file")
  echo "Appended review iteration #$iteration"
else
  # Create new review report
  cat > "$review_file" <<EOF
# Code Review, $current_branch

Review iterations for this branch. All files in this directory are git-ignored.

---

EOF
  cat {agent_output} >> "$review_file"
  echo "Created review report: $review_file"
fi
```

### 7. Display Summary

```bash
echo ""
echo "======================================"
echo "Code Review Complete!"
echo "======================================"
echo ""
echo "Branch: $current_branch vs $base_branch"
echo "Review saved to: $review_dir (git-ignored)"
echo ""
echo "Quick Summary:"
grep -A 1 "### Verdict" "$review_file" | tail -1
echo ""
echo "Next Steps:"
echo "  1. Address ❌ issues (blocking)"
echo "  2. Consider ⚠️ warnings and 💡 suggestions"
echo "  3. Run 'ar-taskflow-review' again after fixes to track progress"
echo ""
```

## Violation Example

Each finding cites the file:line and the specific rule. **Illustrative, produce findings in THIS project's language and cite only rules installed in `<standards_location>`. Use the same shape for ❌ issues, ⚠️ warnings, and ✅ good-pattern callouts.**

```
❌ <file>:89 - transactional block calls an external API
   Violation: calls an external service inside the open transaction
   Rule: <the project's transaction-scope rule, if installed>
   Impact: holds the database connection during the external call
   Fix: split into fetch [transactional] → external call [no transaction] → update [transactional]
```

## Example Output

```
Code Review Complete! ,  Branch: feature/ticket-123 vs main  (ar-taskflow)
Review saved to: <reviews_root>/<branch>/review-report.md

Verdict: ⚠️ NEEDS WORK
  ❌ Missing migration for the enum change
  ⚠️ Potential N+1 in the related-data lookup
  💡 Consider adding metrics
Next: fix, then run 'ar-taskflow-review' again   (iteration #1)
```

## Review Log Format

The `review-report.md` file maintains all iterations:

```markdown
# Code Review Logs

This file contains all code review iterations for this task.
Each review is timestamped and tracks issues, fixes, and progress.

---

## Review Iteration 1
**Date**: 2026-02-10 15:45:22
**Branch**: feature/ticket-123-new-feature
**Files Changed**: 8

### Changes Summary
Added new status value to enum and related processing logic...

### ✅ Passes
- Proper module structure: changes in correct modules
- Transaction boundaries correctly maintained

### ⚠️ Warnings
- DataService.findRelated() may have N+1 query issue

### ❌ Issues (Must Fix)
- StatusEnum.java:42 - Missing migration for new enum value

### 💡 Suggestions
- Consider adding metrics collection for new feature

### Verdict
NEEDS WORK

### Next Steps
1. Add migration for enum change
2. Review N+1 query concern
3. Re-run ar-taskflow-review after fixes

---

## Review Iteration 2
**Date**: 2026-02-10 16:12:05
**Branch**: feature/ticket-123-new-feature
**Files Changed**: 10

### Changes Summary
Added migration file and fixed N+1 query...

### Progress from Iteration 1
✅ Fixed: Migration added (V{timestamp}__add_status_value.sql)
✅ Fixed: N+1 resolved with batch loading pattern

### ✅ Passes
- All previous issues resolved
- Migration follows naming conventions
- Query optimization properly implemented

### 💡 Suggestions
- Metrics collection still recommended (optional)

### Verdict
✅ APPROVED

### Next Steps
Ready for PR!

---
```

## Integration with ar-taskflow

The ar-taskflow-review skill is designed to integrate with ar-taskflow at the **Code phase**:

```
ar-taskflow phases:
1. Understand
2. Plan
3. Code → [After implementation] → ar-taskflow-review ← YOU ARE HERE
4. Document
5. PR
```

**Recommended workflow:**
1. Complete code implementation
2. Run `ar-taskflow-review` to validate
3. Fix any issues
4. Run `ar-taskflow-review` again to verify fixes
5. Proceed to documentation and PR

## Post-Review Fix Rules

When the user approves fixes suggested by the review:

1. Make the code changes
2. Run tests to verify
3. **Create a NEW commit**, never amend the previous one
4. **Push normally**, never force push
5. Optionally re-run `ar-taskflow-review` to verify fixes

Example commit message:
```
[{namespace}-XXX] Address review feedback: add doc comments and clarifications
```

**CRITICAL:** Do not use `git commit --amend` or `git push --force-with-lease` for post-review changes. Always create a fresh commit and do a normal push.

## Tips

- **Run early, run often**: Don't wait until code is "perfect" - review as you go
- **Track progress**: Each review iteration shows what was fixed
- **Learn patterns**: Reviews teach you project conventions over time
- **Automate compliance**: Use before every PR to catch issues early

## Notes

- All review files are **git-ignored**, no **tracked** file is modified. The only writes are to git-ignored AI-framework paths (the `reviews_root` / `.claude/reviews/` fallback), which are git-ignored at install time; if they were not, those writes would dirty the repo.
- Review output is saved to `reviews_root` from `.claude/skill.config` (falls back to `.claude/reviews/`)
- Each run overwrites the diff and appends to the review report
- To post review feedback permanently, use `a_sk_review_pr` to post comments on the PR
- Uses **project-specific a_sag_code_reviewer agent** which deeply understands project patterns
