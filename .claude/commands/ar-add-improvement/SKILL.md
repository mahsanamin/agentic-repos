---
name: ar-add-improvement
description: Record an improvement, learning, fix, or refinement to the Agentic Repos framework. Invoke when a new pattern emerges, a bug is found in a skill/agent/rule, or a workflow refinement is identified during work. Handles version bumping, CHANGELOG updates, and cross-file consistency. Also user-invocable via "ar-add-improvement" or "update framework".
---

# Add Improvements

Systematically manage updates to the Agentic Repos framework with proper version control and documentation.

## When to Use

Invoke this skill when:
- Adding new skills, agents, or rules to the framework
- Modifying existing skills, agents, or rules
- Fixing bugs or improving documentation
- Importing improvements from other projects
- Making any change that should be tracked in CHANGELOG.md
- Ready to bump the framework version

## What This Skill Does

6-step process:
1. **Import from Projects** (Optional) - Pull improvements from other projects
2. **Detect Changes** - Scan git status to identify what files changed
3. **Determine Version Bump** - Apply VERSIONING.md rules (minor vs major)
4. **Update Documentation** - Update CLAUDE.md version line + CHANGELOG.md entry
5. **Validate Consistency** - Ensure CLAUDE.md version matches CHANGELOG.md
6. **Review** - Present changes for user approval before committing

## Operating Principles (ALWAYS, this is a multi-team framework)

These are standing rules for every run, not optional steps. **This framework is consumed by multiple teams**, so a change that is incoherent, contradictory, or quietly slows everyone down has outsized cost. Run accordingly.

1. **Run as a goal.** Treat "incorporate the pending improvements" as a goal that keeps working until the backlog is applied and coherent, don't stop after one file. Read the whole set first; finish the set.

2. **Contradiction check FIRST, before applying anything.** Before editing a single framework file, read **all** the improvements you're about to pick (plus what's already in the framework / open PR) and verify they're mutually consistent:
   - No two picked improvements push the same target/area in **incompatible directions** (opposite fix, conflicting convention, mandate vs carve-out that aren't reconciled).
   - No picked improvement contradicts a change already on the open PR or already shipped.
   - If a contradiction exists: **STOP, surface both to the user, ask which wins**, reconcile, and only then apply. Never apply a contradictory pair and let the later edit silently win.
   - If `improvements/ORDER.md` exists, it already records the reconcile verdict + dependency order, trust it but spot-verify; if it's missing, do the reconcile yourself (mirror `ar-record-improvement` Step 9).

3. **Apply in dependency order.** Consume `improvements/ORDER.md` (or per-item `sequence:` frontmatter) and apply/queue in that order, not arbitrary file order. Out-of-order application breaks dependent fixes (e.g. a "verify original tests pass" fix is a false green unless the opt-in-suite fix landed first).

4. **Flag time/▶step cost.** For every addition, ask "does this add a step, a round-trip, or wall-clock time to a path teams run often?" If yes, **call it out explicitly** to the user and in the CHANGELOG, e.g. "runs the integration suite before declaring green (+N min per verify)", "adds a cold-read sub-agent (+1 agent round-trip)". Prefer designs that make the cost **opt-in / configurable** (a `verify.full_command`, a `--no-verify` flag) over unconditional slowdowns, and say so. The user explicitly wants slowdowns surfaced, not buried.

5. **One PR when asked.** If the user says everything goes in one PR (or an open PR already exists for this line of work), **adjust the existing PR's branch**, commit there, roll the CHANGELOG/version forward in place, instead of opening a new PR.

## Prerequisites

- Working directory: `~/agentic-repos`
- Git repository with changes to document
- Understanding of VERSIONING.md rules

## Version Rules Reference

Read from `VERSIONING.md`:

**Patch bump** (5.0.0 → 5.0.1):
- Bug fixes in existing skills/agents/rules
- Wording improvements
- New optional rules (doesn't break existing installs)
- Template tweaks
- Documentation updates

**Minor bump** (5.0.x → 5.1.0):
- New skills or agents added
- Significant enhancements to existing skills/agents
- New rule categories or workflow steps

**Major bump** (5.x.x → 6.0.0):
- Breaking changes to existing skills/agents
- Workflow changes (new phases, different inputs/outputs)
- Structural reorganization
- New required directories or files

## Step 0: Import or Describe Improvements (Optional)

**IMPORTANT:** There are three ways to get improvements into the framework: import from another project, describe what you want changed, or skip if you've already made changes locally.

### 0a. Ask User About Improvements

```
How would you like to add improvements to the framework?

1. Import from project - Pull improvements from another project
2. Describe improvements - Type what changes you want to make
3. Review recorded improvements - Check improvement inbox from a target project
4. Skip - I've already made local changes, go to version bump

Your choice?
```

If choice 1, proceed to Step 0b (import flow below).
If choice 2, proceed to Step 0b-alt (describe flow below).
If choice 3, proceed to Step 0b-review (recorded improvements flow below).
If choice 4, skip to Step 1.

### 0b-alt. Describe and Apply Improvements

When the user chooses to describe improvements as free-form text:

Ask user:
```
Describe the improvements you want to make to the framework:

Examples:
  "Add retry logic to a_sk_pr skill when API rate limit is hit"
  "New rule for React Query cache invalidation patterns"
  "Update ar-taskflow to support monorepo ticket prefixes"
  "Fix the code-review rule to not flag test files for missing error handling"

Your description:
```

Store as `IMPROVEMENT_DESCRIPTION`.

**Then apply the changes:**

1. Read the description and identify which framework files need to change (skills/, agents/, rules/, setup.md, templates/, etc.)
2. Read those files to understand their current content
3. Make the described changes to the framework files, edit, create, or reorganize as the description requires
4. After making all changes, confirm with the user:

```
I've made the following changes based on your description:

{List each file changed and what was done}

Look correct? (y/n)
```

If the user wants adjustments, make them. When the user is satisfied, proceed to Step 1 (Detect Changes). The changes are now in the working tree for git to detect, and the `IMPROVEMENT_DESCRIPTION` feeds into the CHANGELOG summary.

**Skip Steps 0b-review, 0c-0i**, those are for other flows.

### 0b-review. Review Recorded Improvements

When the user chooses to review recorded improvements (created by the `ar-record-improvement` skill):

Improvements live in the shared improvements directory beside the project's tasks workspace: `{ProjectName}_AgenticRepos/improvements/{date}-{slug}.md`. This step reads the pending improvements there and groups them by the `platform:` frontmatter field.

**Step 1: Locate the shared improvements directory**

Ask the user where the recorded improvements live. Accept either the `_AgenticRepos` directory (or its `improvements/` folder) directly, or a code repo path whose `.claude/skill.config` carries `paths.tasks_root` (from which the directory is derived, `ar-init-skills` writes it).

```
Where are the recorded improvements?

Provide either:
  - A shared improvements dir (e.g., /path/to/Example_AgenticRepos/improvements)
    or its _AgenticRepos parent (/path/to/Example_AgenticRepos)
  - A code repo path (e.g., /path/to/example-service)
    → the _AgenticRepos dir is derived from paths.tasks_root in its skill.config

Path:
```

Store as `SOURCE_PATH`.

```bash
# Resolve the shared _AgenticRepos directory from whatever the user provided.
if [ -d "$SOURCE_PATH/improvements" ]; then
  fw_dir="$SOURCE_PATH"                       # gave the _AgenticRepos dir
elif [ "$(basename "$SOURCE_PATH")" = "improvements" ]; then
  fw_dir="$(dirname "$SOURCE_PATH")"          # gave the improvements dir itself
elif [ -f "$SOURCE_PATH/.claude/skill.config" ]; then
  # gave a code repo: derive from paths.tasks_root (its parent is the _Coding_Tasks
  # root, and the _AgenticRepos dir is that root's sibling)
  tasks_root=$(jq -r '.paths.tasks_root // ""' "$SOURCE_PATH/.claude/skill.config")
  project_name=$(jq -r '.project.name // .project_name' "$SOURCE_PATH/.claude/config_hints.json")
  pascal_name=$(echo "$project_name" | awk -F'[_-]' '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1' OFS='_')
  fw_dir="$(dirname "$(dirname "$tasks_root")")/${pascal_name}_AgenticRepos"
else
  echo "ERROR: Could not locate an _AgenticRepos improvements dir from $SOURCE_PATH"; exit 1
fi

[ -d "$fw_dir/improvements" ] || { echo "No improvements/ dir at $fw_dir"; exit 1; }
SOURCE_PROJECT_NAME=$(basename "$fw_dir" | sed 's/_AgenticRepos$//')
```

**Step 2: Collect improvements**

Read every `status: pending` file in the shared `improvements/` dir. Each improvement is tagged with the platform from its `platform:` frontmatter field.

```bash
declare -a IMPROVEMENT_FILES=()

for f in "$fw_dir/improvements"/*.md; do
  [ -f "$f" ] || continue
  status=$(awk '/^status:/ {print $2; exit}' "$f")
  [ "$status" = "pending" ] || continue
  platform_name=$(awk '/^platform:/ {print $2; exit}' "$f")
  platform_name="${platform_name:-unknown}"
  IMPROVEMENT_FILES+=("$platform_name|$f")
done

if [ ${#IMPROVEMENT_FILES[@]} -eq 0 ]; then
  echo "No pending improvements found in $fw_dir/improvements/."
  # Return to Step 0a
fi
```

**Delete-on-apply semantics:** once an improvement is successfully applied, its content folded into the framework, which is the canonical record (CHANGELOG entry + the edited skill/agent/rule), this skill **removes** the consumed file from the shared `improvements/` dir (Step 5) so applied items don't pile up forever. This is a removal-*after-folding*, not a lossy delete: the repo's own git history preserves the original file verbatim, and the framework CHANGELOG records that the improvement was applied. (Consistent with `ar-record-improvement`'s rule that a record is "removed only after its content is folded into the canonical record"; that skill's "never delete" guard is about the *losing side of an unreconciled contradiction*, a different lifecycle state, not an applied improvement.)

**Step 3: Present improvements grouped by platform**

Iterate `IMPROVEMENT_FILES`, group by the platform prefix (before `|`), read each file's frontmatter (`priority`, `category`, `target`, `description`/body first line):

```
Recorded improvements from {SOURCE_PROJECT_NAME} workspace:

[Backend]
  #  | Priority    | Category | Target     | Description
  ---|-------------|----------|------------|---------------------------
  1  | should-fix  | skill    | a_sk_pr      | Should retry on 403 rate limit errors
  2  | bug         | rule     | general    | Code-review flags test files incorrectly

[Frontend]
  3  | nice-to-have| template | pr-template| Add section for breaking changes

Which improvements to incorporate? (comma-separated numbers, or "all")
```

Store selected improvement file paths (with their platform prefix) as `SELECTED_IMPROVEMENTS`.

**Step 3.5: Contradiction check + ordering (do this before applying, see Operating Principles).**

1. **Read `improvements/ORDER.md`** if present. It carries the reconcile verdict (contradictions + chosen winners) and a dependency-aware pick-up sequence. Apply `SELECTED_IMPROVEMENTS` in that order. If it's absent, read all selected files now and reconcile yourself: confirm they're mutually consistent and order them so dependencies land first.
2. **Verify no contradictions** among the selected set, against the framework, and against any open PR for this work. On a contradiction: STOP, surface both, ask the user which wins, reconcile, then proceed.
3. **Note the time/step cost** of each selected improvement (extra suite runs, sub-agent round-trips, new mandatory steps). Carry these into the Step 4 confirmations and the CHANGELOG; prefer opt-in/configurable designs.

**Step 4: Process each selected improvement** (in ORDER.md sequence)

For each selected improvement:

1. Read the full improvement file (description + context)
2. Identify which framework files need to change based on `category` and `target`.
   **For `category: rule`, route to the correct tier (W8):** read the `tier` frontmatter field and place/edit the rule under `rules/<tier>/` (`universal` = cross-language; `java-spring-boot` / `react` / `go` / … = per-stack). If `tier` is absent (older recordings), infer it: a rule naming language/framework idioms → the matching per-stack dir; a cross-language principle → `universal`. **Never put stack-specific content in `universal/`**, that leaks it to every stack (the rule-layer version of the language-leak bug). If the target per-stack dir doesn't exist yet, create it (this is how new stacks get rules, the W6 path).
   **Tier sanity check:** before saving a rule into `universal/`, scan it for stack idioms (`@`-annotations, `gradlew`/`pom.xml`/`go.mod`, framework class names); if found, it's mis-tiered, move it to the per-stack dir or genericize it.
3. Read those framework files
4. Apply the improvement, edit, create, or reorganize as needed
5. After applying, confirm with user:

```
Applied improvement #{N}: {description}

Changed:
- {list files changed and what was done}

Look correct? (y/n)
```

If user wants adjustments, make them before moving to the next improvement.

**Step 5: Remove applied improvements from the inbox**

After each improvement is successfully applied (and the user confirmed it in Step 4), **delete** its file from the inbox so applied improvements don't accumulate. The content is now folded into the framework, the canonical record, and the workspace repo's git history preserves the original (see "Delete-on-apply semantics" above). Each entry in `SELECTED_IMPROVEMENTS` carries the full absolute path:

```bash
# Remove the consumed improvement file.
# git rm when the file is tracked, stages the deletion so the workspace's normal
# commit / Docs-Auto-Push flow (or the next ar-upgrade audit commit) carries it along.
# Falls back to a plain rm when the file is untracked or has uncommitted local edits
# (git sees the removal as an unstaged deletion in that case).
imp_dir=$(dirname "$IMPROVEMENT_FILE_PATH")
git -C "$imp_dir" rm -q -- "$IMPROVEMENT_FILE_PATH" 2>/dev/null || rm -f -- "$IMPROVEMENT_FILE_PATH"
```

Report each removal in the Step 6 summary (file name + the framework change it folded into).

**Step 6: Summary**

After all selected improvements are processed:

```
Improvement Review Summary

Source: {SOURCE_PROJECT_NAME}
Processed: {N} of {TOTAL} improvements
Skipped: {M} (still pending, left in the inbox)

Applied (folded into the framework, then removed from the inbox):
- #{1}: {description} → {files changed}  (removed {inbox file})
- #{2}: {description} → {files changed}  (removed {inbox file})

Continue to version bump? (y/n)
```

If yes, proceed to Step 1 (Detect Changes). The changes are now in the working tree.

**Skip Steps 0c-0i**, those are import-specific steps.

### 0b. Gather Project Information (Import Flow)

Ask user:
```
Please provide:

1. Project path (absolute path to the project):
   Example: ~/repos/example/user-service

2. What improvements do you want to import?
   a) New/updated rules
   b) Changes to setup.md approach
   c) Other (describe)

3. Brief description of the improvements:
   Example: "New rule for React Query cache invalidation, generalized from user-service"

Your answers:
```

Store:
- `SOURCE_PROJECT_PATH`
- `IMPROVEMENT_TYPE` (rule/setup/other)
- `IMPROVEMENT_DESCRIPTION`

Skills and agents are global (never copied per repo), so the import flow covers only rules and setup changes. To change a skill or agent, edit it in the framework working tree directly (via the "Describe improvements" or "Review recorded improvements" flow).

### 0c. Analyze Source Project Structure

```bash
cd $SOURCE_PROJECT_PATH

# Check if this is an Agentic Repos project
[ -f ".claude/config_hints.json" ] || echo "ERROR: Missing config_hints.json (not an Agentic Repos project)"

# Read project configuration
SOURCE_PROJECT_NAME=$(jq -r '.project.name' .claude/config_hints.json)
SOURCE_PLATFORM=$(jq -r '.platform' .claude/config_hints.json)
SOURCE_NAMESPACE=$(jq -r '.project.namespace // .project.default_namespace' .claude/config_hints.json)
SOURCE_STANDARDS=$(jq -r '.standards_location' .claude/config_hints.json)

echo "Source Project: $SOURCE_PROJECT_NAME"
echo "Platform: $SOURCE_PLATFORM"
echo "Namespace: $SOURCE_NAMESPACE"
echo "Standards: $SOURCE_STANDARDS"
```

### 0d. Smart Extraction Logic

Based on `IMPROVEMENT_TYPE`, extract relevant files:

**For Rules:**
```bash
# List rules in source project's standards location
ls -1 $SOURCE_PROJECT_PATH/$SOURCE_STANDARDS/

# For each rule the user wants to import
RULE_FILE="$SOURCE_PROJECT_PATH/$SOURCE_STANDARDS/{rule-name}.md"
```

### 0e. Filter Project-Specific Details

**Critical:** Before importing, scan for and remove project-specific content:

**Project-specific patterns to filter:**
```bash
# Scan for project-specific references
grep -n "$SOURCE_PROJECT_NAME" "$RULE_FILE"
grep -n "$SOURCE_NAMESPACE" "$RULE_FILE"
grep -n "com\.example\.[a-z]*" "$RULE_FILE"  # Java packages
grep -n "/path/to/.*_Coding_Tasks" "$RULE_FILE"  # Hardcoded paths
```

**What to filter:**
- Project names → Replace with generic placeholders or remove examples
- Namespace prefixes (PROJ-123, SVC-456) → Use generic {namespace}-XXX
- Specific package names (com.example.userservice) → Use {project} placeholder
- Hardcoded paths → Use configuration variables
- Project-specific entity names → Use generic examples

**What to preserve:**
- Logic improvements (retry logic, error handling)
- New workflow steps
- Bug fixes
- Pattern enhancements
- Generalized examples

### 0f. Handle Different Scenarios

**Scenario 1: Setup.md Changes**

If improvements affect how installation works:

```
Source project has custom setup modifications.

Do these changes apply to ALL projects?
1. Yes - Update setup.md in framework
2. No - These are project-specific customizations

Your choice?
```

If choice 1, ask user to describe what setup.md changes are needed:
```
What should change in setup.md?
Example: "Add step to detect and migrate existing rules from .aiRules directory"

Description:
```

Then manually update setup.md with guided input.

**Scenario 2: Rules (Coding Standards)**

```
Source project has {N} rules in $SOURCE_STANDARDS/

Platform-specific rules to import:
{List rules that match SOURCE_PLATFORM and exist in framework}

New rules to add:
{List rules that don't exist in framework}

I'll filter project-specific examples (packages, entities, etc.)

Proceed? (y/n)
```

Filter logic for rules:
```bash
# Replace project-specific packages
sed -i '' "s/com\.example\.$SOURCE_PROJECT_NAME/com.example.{project}/g" rule.md

# Replace project-specific entities
# Use generic examples: User, Order, Item, etc.

# Preserve the pattern/principle being demonstrated
```

### 0g. Conflict Resolution

When merging updated rules, conflicts may occur:

```
Conflict detected in {FILE}:

Framework version has:
  {Section A content}

Source project version has:
  {Section B content}

Both versions differ. Which to keep?
1. Framework version (existing)
2. Source project version (newer)
3. Merge both (I'll combine them)
4. Show me the full context to decide

Your choice?
```

For choice 3:
- Intelligently merge both sections
- Preserve intent from both
- Remove duplication
- Show merged result for approval

### 0h. Summary of Imports

After all imports complete:

```markdown
## Import Summary

**Source Project:** {SOURCE_PROJECT_NAME} ({SOURCE_PLATFORM})
**Source Path:** {SOURCE_PROJECT_PATH}

### Imported Changes

**Updated Rules:**
- {rule-name} - {what changed}

**Setup.md Changes:**
- {describe changes}

### Filtered Content

Project-specific references removed:
- {SOURCE_PROJECT_NAME} → {project}
- {SOURCE_NAMESPACE}-XXX → {namespace}-XXX
- com.example.{specific} → com.example.{project}
- {N} hardcoded paths replaced with variables

All improvements are now framework-ready and generalized.

---

Continue to version bump? (y/n)
```

If yes, proceed to Step 0i.

### 0i. Remove Matching Recorded Improvements

After importing from a project, check if the source project has any recorded improvements (`.claude/improvements/`) that match what was just imported. This keeps the improvement inbox clean by removing items that are now folded into the framework.

```bash
# Check if improvements directory exists in source project
ls -1 $SOURCE_PROJECT_PATH/.claude/improvements/*.md 2>/dev/null
```

If improvements exist, for each `status: pending` file:
1. Read its `category` and `target` fields from the YAML frontmatter
2. Compare against the imported changes, match by category (skill/agent/rule/setup) and target name
3. If the improvement matches something that was just imported, delete it (its content is now in the framework; git history preserves the original, see "Delete-on-apply semantics"):

```bash
imp_file="$SOURCE_PROJECT_PATH/.claude/improvements/{filename}"
git -C "$SOURCE_PROJECT_PATH" rm -q -- "$imp_file" 2>/dev/null || rm -f -- "$imp_file"
```

4. Report what was removed:

```
Removed recorded improvements (folded into the framework):
- {filename}, {description} (matched imported {category}: {target})
```

If no `.claude/improvements/` directory exists or no pending improvements match, skip silently.

Proceed to Step 1.

## Step 1: Detect Changes

**Note:** If Step 0 was executed, changes from imported files are already staged. This step detects both imported and local changes.

Check what files have changed:

```bash
git status
git diff --name-only main...HEAD
```

Categorize changes:
- `skills/**` → Skills modified/added
- `agents/**` → Agents modified/added
- `rules/**` → Rules modified/added
- `templates/**` → Templates modified
- `setup.md` → Installation process changed
- Documentation files → Docs updated

If imports were performed, note:
```
Changes include imports from: {SOURCE_PROJECT_NAME}
- {N} new skills
- {M} updated skills
- {P} new/updated rules
```

Ask user:
```
I see changes in:
{list categories and file counts}

What type of update is this?
1. Bug fix / wording improvement / new optional rules (patch bump)
2. New skill/agent or significant enhancement (minor bump)
3. Breaking change or structural reorganization (major bump)
4. Let me decide based on VERSIONING.md rules

Your choice?
```

If choice 4, analyze changes and recommend version bump based on VERSIONING.md rules.

## Step 2: Determine New Version

Read current version from the canonical source:
```bash
grep '"framework_version"' config_hints.json | sed 's/.*: *"\(.*\)".*/\1/' | tr -d '[:space:]'
```

Parse current version (`major.minor.patch`) and calculate next version:
- If patch bump: increment patch (5.0.0 → 5.0.1)
- If minor bump: increment minor, reset patch to 0 (5.0.1 → 5.1.0)
- If major bump: increment major, reset minor and patch to 0 (5.1.0 → 6.0.0)

Store as `NEW_VERSION` variable.

Ask user:
```
Current version: {CURRENT_VERSION}
Proposed version: {NEW_VERSION}

This will be a {patch/minor/major} version bump.

Proceed with v{NEW_VERSION}? (y/n)
```

## Step 3: Update Documentation Files

Version is tracked in **3 files**: config_hints.json (canonical), CLAUDE.md (human-readable), and CHANGELOG.md (history).

### 3a. Update config_hints.json

Update `framework_version` in `config_hints.json` at the framework root:
```bash
# Update framework_version to new version
sed -i '' "s/\"framework_version\": \".*\"/\"framework_version\": \"${NEW_VERSION}\"/" config_hints.json
```

### 3b. Update CLAUDE.md

Find the line `Version: v{OLD_VERSION}` near the top of CLAUDE.md and update it to `Version: v{NEW_VERSION}`.

### 3c. Update CHANGELOG.md

Add new section at the TOP of CHANGELOG.md (after the header):

```markdown
## v{NEW_VERSION}, {YYYY-MM-DD}

**Summary:** {Brief one-line description}

**Files changed:**
{For each changed file, one line in format:}
- `path/to/file.md`, {What changed in this file}

**Added:** {Optional - if new files added}
- {New file} for {purpose}
```

Follow the exact format of existing entries. Be specific about what changed in each file.

## Step 4: Validate Consistency

Run validation checks:

**Check 0: Source-side gates (no project noise, no stack-idiom leak)**
- **Run the project-noise lints before the version bump**, the leak vector this whole framework exists to keep out of teams' installs:
  ```bash
  bash scripts/ar-lint/generic-skill-lint.sh            # stack idioms in skill/agent bodies, hard fail
  bash scripts/ar-lint/project-noise-lint.sh --changed  # PROJECT_NOISE / PROJECT_SCOPED_ARTIFACT candidates
  ```
  Adjudicate any `project-noise-lint` candidates (an `a_sag_code_reviewer` pass handles the domain-shaped noise regex can't see). **Any confirmed BLOCKING finding STOPS the bump** until fixed. (Touched nothing under `rules/`/`skills/`/`agents/`/`templates/`/`docs/`/`setup.md`? Passes trivially.)
- **After the PR is opened, run the full review: `/ar-self-reviewer <PR>`**, it takes the framework PR as input and posts findings in `a_sk_l_review_pr` comment style for the human to approve. (The lints above are the pre-commit fast path; the gate is the full PR review.)
- If any `skills/*` or `agents/*` file was modified: run/refresh that skill's evals via `skill-creator` and require a passing baseline before the version bump, this catches behavioral regressions from edits/trims. **`skill-creator` is a required prerequisite**, if missing, STOP and have the user install it before bumping.

**Check 1: Version numbers match**
```bash
# Extract version from config_hints.json (canonical source)
CONFIG_VERSION=$(grep '"framework_version"' config_hints.json | sed 's/.*: *"\(.*\)".*/\1/' | tr -d '[:space:]')

# Extract version from CLAUDE.md
CLAUDE_VERSION=$(grep "^Version: v" CLAUDE.md | sed 's/Version: v//')

# Extract latest version from CHANGELOG.md
CHANGELOG_VERSION=$(grep "^## v" CHANGELOG.md | head -1 | sed 's/.*v\([0-9.]*\).*/\1/')

echo "config_hints: $CONFIG_VERSION"
echo "CLAUDE.md:    $CLAUDE_VERSION"
echo "CHANGELOG:    $CHANGELOG_VERSION"
```

All three must match `NEW_VERSION`. If not, identify which file needs correction.

**Check 2: CHANGELOG format**

Verify the new CHANGELOG entry follows the format:
- Has `## v{VERSION}, {DATE}` header
- Has `**Summary:**` line
- Has `**Files changed:**` section with bullet points
- Optional `**Added:**` section if applicable

## Step 5: Review and Present Changes

Show user a comprehensive summary:

```markdown
## Framework Update Summary

**Version bump:** v{OLD_VERSION} → v{NEW_VERSION} ({Minor/Major})

{If imports were done:}
**Imported from:** {SOURCE_PROJECT_NAME} ({SOURCE_PLATFORM})
- {List imported items with filtering applied}

### Files Updated

**CLAUDE.md**
- Updated version line to v{NEW_VERSION}

**CHANGELOG.md**
- Added v{NEW_VERSION} section with {N} file changes

{If setup.md was updated:}
**setup.md**
- {Describe what changed}

### Changes Documented

{List each file change from CHANGELOG.md}

### Validation

✓ CLAUDE.md and CHANGELOG.md versions match
✓ CHANGELOG format matches existing entries
{If imports:}
✓ Project-specific details filtered out
✓ Improvements generalized for framework

---

Ready to commit and create PR? (y/n)
```

If user approves:

### 5a. Create Branch

```bash
git checkout -b feature/{short-description-from-summary}
```

Use a short kebab-case branch name derived from the CHANGELOG summary (e.g., `feature/sonarqube-fetch-script`, `feature/ar-taskflow-retry-logic`).

### 5b. Stage and Commit

```bash
git add CLAUDE.md CHANGELOG.md config_hints.json
# Add any modified skills/rules/scripts/templates
git add skills/ rules/ scripts/ templates/ setup.md .claude/commands/ 2>/dev/null
```

Commit with (no tool or assistant attribution trailers; the commit is authored by the developer):
```
Upgrade framework to v{NEW_VERSION}: {summary}

{One-line description of what changed}
```

### 5c. Push and Create PR

```bash
git push -u origin feature/{branch-name}
```

Create PR:
```bash
gh pr create --title "Upgrade framework to v{NEW_VERSION}: {summary}" --body "$(cat <<'EOF'
## Summary
{Bullet points from CHANGELOG Files changed section}

## Test plan
- [ ] Run ar-upgrade on a target project to verify changes apply correctly
- [ ] Verify version consistency across config_hints.json, CLAUDE.md, CHANGELOG.md
EOF
)"
```

Present the PR URL to the user.

## Additional Features

### Generate CHANGELOG Entry from Git

If user wants help writing the CHANGELOG entry:

```bash
# Show changed files
git diff --name-only main...HEAD

# Show recent commits for context
git log --oneline main..HEAD
```

For each changed file, ask user:
```
File: {filename}
What changed? (brief description for CHANGELOG)
```

Build the `**Files changed:**` section from their answers.

### Validate Rule Files

If rules were modified, offer to run basic validation:

```bash
# Check for common issues
grep -r "TODO\|FIXME\|XXX" rules/
grep -r "\.cursor/rules" rules/ # Should use {standards_location}
```

Warn user if validation finds issues.

### Check Setup.md References

If setup.md was modified, check for consistency:

```bash
# Verify version references
grep -i "version" setup.md
```

Ensure setup.md doesn't hardcode old version numbers.

## Best Practices

1. **Be specific in CHANGELOG** - Don't just say "Updated skill" - say WHAT changed in the skill
2. **Follow existing format exactly** - Match the structure of previous CHANGELOG entries
3. **Update both files** - CLAUDE.md version line + CHANGELOG.md entry
4. **Validate before committing** - Run all validation checks to catch inconsistencies
5. **Keep it simple** - Version in CLAUDE.md, history in CHANGELOG.md, nothing else

## Notes

- This skill does NOT update README content (by design - keep it simple)
- Version changes should be committed separately from feature changes
- Always read VERSIONING.md rules before deciding on version bump
- Target projects have their own config_hints.json with framework_version - those get updated when they re-run setup.md
- **Importing from projects:** When importing improvements, always filter project-specific details (names, namespaces, packages, hardcoded paths)
- **Setup.md updates:** If new skills/agents are added via import, update setup.md to include them in standard installation
- **Conflict resolution:** When importing updates to existing skills, intelligently merge improvements while preserving framework patterns

## Reference Documents

- `VERSIONING.md` - Version bump rules
- `CHANGELOG.md` - Per-version change format
- `README.md` - Just has version number
- [Claude Code Best Practices](https://code.claude.com/docs/en/best-practices)
- [How Claude Code Works](https://code.claude.com/docs/en/how-claude-code-works)
