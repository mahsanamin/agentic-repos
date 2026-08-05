---
name: ar-record-improvement
description: Record a framework improvement suggestion from any target project. Saves structured improvement files to the workspace's shared improvements/ directory for ar-add-improvement to consume later. Say "ar-record-improvement" or "record improvement".
disable-model-invocation: false
---

# Record Improvement

Quick 4-step capture: describe the issue, confirm category, set priority, done.

## When to Use

- You notice a skill bug or missing feature while working in a target project
- You discover a better pattern that should be in the framework
- You want to suggest a new rule, agent, or template
- You worked around a framework limitation and want it fixed

## Prerequisites

- Current project must be an Agentic Repos target project (has `.claude/config_hints.json`)
- The target's `.claude/skill.config` should carry `paths.tasks_root` (written by `ar-init-skills`); it locates the shared improvements directory

## Where output goes

Improvements are written to the **shared improvements directory** that sits beside the project's tasks workspace:

```
{ProjectName}_AgenticRepos/improvements/{YYYY-MM-DD}-{slug}.md
```

This directory is derived from `paths.tasks_root` in `.claude/skill.config`: the `_Coding_Tasks` root has a sibling `{ProjectName}_AgenticRepos` directory, and improvements land under its `improvements/` folder. For example, an improvement recorded from `example-service` (Backend) lands in:

```
/path/to/Example_AgenticRepos/improvements/2026-05-15-a_sk_pr-retry-rate-limit.md
```

All platforms write to the same `improvements/` directory. The `platform: <Backend|Frontend|...>` frontmatter field distinguishes platform-specific items when needed. Concurrent same-day-same-slug collisions append `-2`, `-3`, ... so file-level concurrency is safe.

## Steps

### Step 1: Detect Project Context

```bash
# Verify this is an Agentic Repos project
[ -f ".claude/config_hints.json" ] || { echo "ERROR: Not an Agentic Repos project"; exit 1; }

# Anchor TARGET_PROJECT to the current working directory. All later steps reference
# $TARGET_PROJECT/.claude/skill.config and $TARGET_PROJECT/.claude/config_hints.json
# explicitly rather than relying on relative paths, this is robust against cd's
# inside the discovery helpers.
TARGET_PROJECT="$(pwd)"

# Read project info
PROJECT_NAME=$(jq -r '.project.name // .project_name' "$TARGET_PROJECT/.claude/config_hints.json")
FRAMEWORK_VERSION=$(jq -r '.framework_version' "$TARGET_PROJECT/.claude/config_hints.json")
```

### Step 2: Locate the shared improvements directory + resolve platform

`ar-init-skills` writes `paths.tasks_root` into `.claude/skill.config` (the runtime config). That path is `.../{ProjectName}_Coding_Tasks/{Platform}`; its parent is the `_Coding_Tasks` root, and the shared `{ProjectName}_AgenticRepos` directory is that root's sibling. Derive everything from it, with a prompt fallback, no cross-repo config reads.

```bash
SKILL_CONFIG="$TARGET_PROJECT/.claude/skill.config"
TASKS_ROOT=$(jq -r '.paths.tasks_root // ""' "$SKILL_CONFIG" 2>/dev/null)

if [ -z "$TASKS_ROOT" ] || [ ! -d "$TASKS_ROOT" ]; then
  echo "Could not read paths.tasks_root from $SKILL_CONFIG."
  echo "Provide the tasks root for this project (e.g. /path/to/{ProjectName}_Coding_Tasks/{Platform}):"
  read -r TASKS_ROOT
fi

# The _Coding_Tasks root. The shared _AgenticRepos dir is its sibling (derived in Step 7).
TASKS_WORKSPACE="$(dirname "$TASKS_ROOT")"

# Platform: prefer the config_hints value, else the tasks_root leaf.
PLATFORM=$(jq -r '.platform // ""' "$TARGET_PROJECT/.claude/config_hints.json")
[ -z "$PLATFORM" ] && PLATFORM="$(basename "$TASKS_ROOT")"
```

### Step 3: Ask What to Improve

```
What improvement do you want to record?

Examples:
  "a_sk_pr skill should retry on 403 rate limit errors"
  "Add a rule for React Query cache invalidation patterns"
  "ar-taskflow Phase 3 doesn't handle monorepo ticket prefixes"
  "a_sag_code_reviewer agent flags test files for missing error handling"

Your description:
```

Store as `DESCRIPTION`.

### Step 4: Determine Category

Auto-detect category from the description:
- Mentions a skill name (ar-taskflow, a_sk_pr, etc.) → `skill`
- Mentions agent (a_sag_code_reviewer, a_sag_test_runner, etc.) → `agent`
- Mentions rule, pattern, convention → `rule`
- Mentions setup, installation, update → `setup`
- Mentions template, PR template, commit template → `template`
- Otherwise → `other`

Also extract the specific target name if mentioned (e.g., "a_sk_pr" from "a_sk_pr skill should retry").

### Step 4b: For `rule` category, determine the tier (W8)

If `CATEGORY = rule`, also decide which **rule tier** it belongs to, so `ar-add-improvement` places it correctly (rules are tiered: `universal/` = cross-language, plus per-stack `java-spring-boot/`, `react/`, `go/`, …). Misfiling a stack-specific rule under `universal/` would leak it to every stack, the same class of bug we fixed for skills.

Decide `TIER`:
- **`universal`**, the rule is a cross-language principle (review discipline, critical thinking, test-change policy, doc/observability conventions that don't depend on language).
- **`<stack>`**, the rule names language/framework idioms (annotations, ORM, build tool, language-specific patterns). Default `<stack>` to this project's stack from `config_hints.json` (`.stack`, else `.platform`).

Confirm with user:

```
Detected:
  Category: {category}
  Target: {target name or "general"}
{if category == rule:}  Tier: {universal | <stack>}  (where stack-specific rules live)

Correct? (y/n, or type the correct category/tier)
```

Store `CATEGORY`, `TARGET`, and (for rules) `TIER`.

### Step 5: Ask Priority

```
Priority?
  1. bug - Something is broken or produces wrong results
  2. should-fix - Significant gap or frequent pain point
  3. nice-to-have - Would be better but not blocking

Your choice:
```

Store as `PRIORITY`.

### Step 6: Optional Context

```
Want to add context? (code snippet, file path, diff, or workaround you used)

Type it below, or press enter to skip:
```

If provided, store as `CONTEXT`.

### Step 6.5: Dedup + Contradiction Gate (before writing)

**Do not write blind.** Before creating a new file, scan the existing pending backlog and classify the new improvement against it. The goal is a **coherent end state**, not fewer files, never silently drop content.

Scan all `status: pending` items in the shared `improvements/` dir.

**A. Semantic dedup, match on meaning, not slug.** The `-2`/`-3` same-slug suffix only catches *identical* slugs; two recordings of the *same issue* with different wording slip through (this actually happened: `verify-step-skips-opt-in-integration-tests` vs `ar-taskflow-verify-green-skips-opt-in-integration-tests`, same gap, different slugs). Match on frontmatter `target` overlap **AND** topical overlap (keyword/area), not the generated slug.

**B. Contradiction detection.** Flag when an existing pending item proposes an **incompatible direction** for the same target/area (opposite fix, conflicting convention). This matters because multiple teams consume this framework, a contradictory backlog ships an incoherent change.

**Resolution (never silent removal):**

| Finding | Action |
|---|---|
| **Duplicate / overlap** | Default to **enriching the existing canonical record in place**, append a dated `## Update (YYYY-MM-DD)` block, merge the new context, reconcile frontmatter (e.g. raise `priority`). Only create a separate file if the user confirms the slices are genuinely distinct. |
| **Contradiction** | Present **both** to the user, **ask which to prefer**, then **adjust the records** to reflect the decision, reconcile into one, or mark the superseded one `status: superseded` with a pointer to the winner. The loser is annotated, never deleted. |
| **No match** | Proceed to Step 7 (write a new file). |

This mirrors correct manual handling: update-then-dedupe, not delete. A duplicate is removed only *after* its content is folded into the canonical record.

### Step 7: Write Improvement File

```bash
# Derive the shared _AgenticRepos dir. Improvements are shared across platforms;
# the `platform:` frontmatter field distinguishes platform-specific items. The
# _Coding_Tasks root (TASKS_WORKSPACE, from Step 2) has a sibling
# {ProjectName}_AgenticRepos dir. PROJECT_NAME comes from the code repo's
# config_hints (resolved in Step 1).
#
# Normalise PROJECT_NAME into a directory-safe token: treat whitespace as a word
# separator alongside `_` and `-`, capitalise each word, join with `_`. A name that
# is already pascal/snake-cased passes through unchanged ("Example_Project" stays
# put), "user-service" becomes "User_Service", and a name containing a space
# ("My Service") becomes "My_Service" instead of leaking the space into a
# directory name. `ar-add-improvement` derives this same token, keep the two in sync.
pascal_name=$(echo "$PROJECT_NAME" | awk -F'[_[:space:]-]+' '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1' OFS='_')

fw_dir="$(dirname "$TASKS_WORKSPACE")/${pascal_name}_AgenticRepos"
improvements_dir="$fw_dir/improvements"
mkdir -p "$improvements_dir"

# Generate a slug from the description (first 5-6 meaningful words, kebab-case)
DATE=$(date +%Y-%m-%d)
slug=$(echo "$DESCRIPTION" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -dc 'a-z0-9-' | cut -c1-60)
filename="${DATE}-${slug}.md"
target_file="$improvements_dir/$filename"

# Collision handling: append -N suffix if file already exists
n=2
while [ -e "$target_file" ]; do
  filename="${DATE}-${slug}-${n}.md"
  target_file="$improvements_dir/$filename"
  n=$((n+1))
done

cat > "$target_file" <<EOF
---
source_project: ${PROJECT_NAME}
platform: ${PLATFORM}
framework_version: ${FRAMEWORK_VERSION}
category: ${CATEGORY}
target: ${TARGET}
${TIER:+tier: ${TIER}
}priority: ${PRIORITY}
recorded: ${DATE}
status: pending
---

${DESCRIPTION}

## Context
${CONTEXT:-No additional context provided.}
EOF
```

### Step 8: Confirm + Auto-Commit

```
Recorded improvement:

  {DESCRIPTION}
  Platform: {PLATFORM}
  Category: {CATEGORY} ({TARGET})
  Priority: {PRIORITY}
  Source: {PROJECT_NAME} (v{FRAMEWORK_VERSION})
  Saved to: {target_file}

This will be picked up next time someone runs "ar-add-improvement" in the agentic-repos repo
and chooses "Review recorded improvements".
```

Then auto-commit and push the repo that owns the improvements directory, staging only `$target_file`:

- **Resolve the git repo from `dirname "$target_file"`.** The `_AgenticRepos` directory is a sibling of the `_Coding_Tasks` root, so resolving from the improvement file's own directory points at the correct toplevel (resolving from elsewhere risks a "pathspec is outside repository" failure).
- **No "other-changes" safety guard.** `git add -- "$target_file"` is precise, it cannot pick up unrelated changes. The earlier safety check (porcelain status filter) was over-conservative AND wrong about untracked-directory entries (`git status` reports the parent dir, not the file, so the file-level exclusion didn't match). Dropped.

```bash
# Resolve the git repo that actually owns $target_file.
repo_root=$(git -C "$(dirname "$target_file")" rev-parse --show-toplevel 2>/dev/null)

if [ -z "$repo_root" ]; then
  echo "⚠️  $target_file is not inside a git repo."
  echo "   The improvement was saved locally but NOT committed or pushed."
  echo "   To make it visible to other team members, place $(dirname "$(dirname "$target_file")") under git tracking, or commit the file manually."
else
  git -C "$repo_root" add -- "$target_file"
  if git -C "$repo_root" diff --cached --quiet -- "$target_file"; then
    echo "Note: no staged change for $target_file (already committed in a previous run?). Skipping commit/push."
  else
    git -C "$repo_root" commit -m "ar-record-improvement: $(basename "$target_file" .md)"
    git -C "$repo_root" pull --rebase || {
      echo "⚠️ Pull-rebase failed (likely a conflict). Resolve in $repo_root, then push manually."
    }
    git -C "$repo_root" push || echo "⚠️ Push failed, push manually from $repo_root."
  fi
fi
```

### Step 9: Reconcile + Sequence the backlog (coherence pass)

After recording, run a coherence pass over the **entire** pending set so the backlog stays sane and `ar-add-improvement` knows what order to apply things in. (The user may frame this as a `/goal` so it keeps working until the backlog is coherent.)

1. **Verify internal consistency**, no leftover contradictions, no near-duplicates the new entry introduced (re-run the Step 6.5 checks across the whole set, not just the new file).
2. **Assign a dependency-aware pick-up sequence.** Some fixes depend on others being in place first, e.g. the behaviour-preserving-test improvement's "verify original tests pass against new code" depends on the opt-in-integration-suite fix already landing; applying them out of order gives a false green. Encode the order as an `improvements/ORDER.md` index (and/or a `sequence:` frontmatter field per item) that the adder consumes.

`ORDER.md` format (regenerate on each reconcile; it is an index, not an improvement, give it `kind: index` and no `status: pending` so it isn't itself picked up):

```markdown
---
kind: index
generated: YYYY-MM-DD
note: Pick-up sequence for pending improvements. ar-add-improvement applies in this order.
---
# Pending improvements, pick-up sequence

| # | Order | File | Target | Priority | Depends on |
|---|-------|------|--------|----------|-----------|
| 1 | apply first | <file> | <target> | <priority> |, |
| 2 | after #1 | <file> | <target> | <priority> | #1 |

## Contradictions
(none), or list each with the user's chosen winner and how the loser was annotated.
```

If a future recording contradicts an existing one, the reconcile pass must surface **both**, ask the user which to prefer, and adjust the records, never silently drop content.

## Notes

- Output lives in the shared `{ProjectName}_AgenticRepos/improvements/` directory (not the code repo), so every platform's recordings collect in one place for `ar-add-improvement` to consume.
- File-per-improvement means concurrent workers don't conflict at the file level. Same-day-same-slug collisions append `-2`, `-3`.
- The improvements directory is derived deterministically from `paths.tasks_root` in `.claude/skill.config`; nothing is written back to `config_hints.json`, which is install-time configuration.
- Keep descriptions actionable, say what should change, not just what's wrong.
