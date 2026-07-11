---
name: ar-taskflow-planner
description: Plan a large feature with issue-tracker integration. Creates a planning ticket immediately, guides architecture discussion, writes spec, breaks into raw prompts, creates a Story ticket and story branch on approval. Say "ar-taskflow-planner" or "plan feature".
disable-model-invocation: false
---

# Task Flow Planner

Plan Feature -> Create Ticket -> Discuss Architecture -> Write Spec -> Break Into Raw Prompts -> Create Story -> Track

**Tracker-agnostic:** create every ticket below using the row for your `tracker.type` in the **Tracker Dispatch Table** (`<standards_location>/mcp-integration.md`, resolve `standards_location` from `.claude/config_hints.json`), `gh issue create` for github, `createJiraIssue` for jira, Linear MCP for linear, a manual identifier for none. The Epic / Story / transition / JQL steps below are the **Jira path**; a github user substitutes `gh issue create` (no Epic/Story hierarchy, use labels/milestones if desired) and skips the MCP transition steps.

> **🧭 Complexity gate, is this the right skill?** Use the planner for **large, multi-PR features** (architecture discussion + spec + sequential sub-tasks + a Story). For a **single PR-sized ticket** under an epic (a bug fix, one small task), use **`ar-ticket-creator`** instead, it's the fast path with no spec/decomposition/branch. They're siblings; pick by complexity.

## 🧭 Learning routing

Follow the rule at `<standards_location>/learning-routing.md` (resolve `standards_location` from `.claude/config_hints.json`): route any learning to a project rule (`docs/ai-rules/`), a framework improvement (`ar-record-improvement`), or conversational-only, never personal auto-memory.

## What This Skill Does

Guides planning of large features that span multiple PRs. Produces:
1. A **planning ticket** immediately (signals planning has started to team)
2. A comprehensive spec document (committed locally; mirrored to a shared docs store if one is configured)
3. Sequential raw prompts (each one ar-taskflow ready, one PR each)
4. An overview/index with dependency graph
5. A plan manifest (machine-readable bridge to ar-taskflow)
6. A **Story / umbrella ticket** on approval (becomes parent for all implementation work)
7. A story branch for multi-PR integration
8. PLAN entry in TasksSummary

The raw prompts feed directly into `ar-taskflow` for execution. Each prompt becomes a separate PR targeting the story branch.

## Configuration

**Read at start of workflow:**

```bash
# Project config
project_namespace=$(jq -r '.project.namespace' .claude/config_hints.json)
project_name=$(jq -r '.project.name' .claude/config_hints.json)
platform=$(jq -r '.platform' .claude/config_hints.json)
tracker_type=$(jq -r '.project.tracker.type // "github"' .claude/config_hints.json)
tracker_url=$(jq -r '.project.tracker.url // ""' .claude/config_hints.json)  # jira/linear only
docs_store_base=$(jq -r '.path_derivation_rules.docs_store_base // ""' .claude/config_hints.json)  # optional shared docs store; empty → local-only

# User paths
tasks_root=$(jq -r '.paths.tasks_root' .claude/skill.config)
docs_root=$(jq -r '.paths.docs_root' .claude/skill.config)

# Derived paths
coding_tasks_root=$(dirname "$tasks_root")
# Planning workspace: sibling of Coding_Tasks, NOT platform-specific
# e.g., if tasks_root = .../Example_Coding_Tasks/Backend
#   then coding_tasks_root = .../Example_Coding_Tasks
#   and planning_root = .../Example_Planning_Tasks
planning_root=$(echo "$coding_tasks_root" | sed 's/Coding_Tasks$/Planning_Tasks/')
task_summary_folder="$coding_tasks_root/TasksSummary"
weekly_summaries_root="$coding_tasks_root/WeeklySummaries"
plans_folder="$docs_root/UnderProcessing"
```

**Planning workspace convention:**
- `{Project}_Coding_Tasks/Backend/` or `{Project}_Coding_Tasks/Frontend/` - platform-specific coding
- `{Project}_Planning_Tasks/` - planning work (NOT platform-specific, sits alongside Coding_Tasks)

## Docs Auto-Push

The docs directory (`coding_tasks_root`) is a separate git repo and is the **source of truth** for every planning artifact. Push at checkpoints marked with the push icon. If your project also configures a shared docs store (see below), mirroring to it is optional and never replaces the committed local copy.

**Shared docs store (optional):** if `docs_store_base` is set in `config_hints.json`, the skill also publishes each artifact to that store (a wiki, an object store, a notes service, or any other shared location your project uses). When `docs_store_base` is empty, the skill runs in local-only mode and the committed docs repo is the only copy. The store is a convenience mirror, so a failure to publish there is never fatal: the local files always win.

**Push-Docs Procedure** (same as ar-taskflow):

```bash
cd "$coding_tasks_root"
if git status --porcelain | grep -q .; then
  git add -A
  git commit -m "ar-taskflow-planner: {context_message}"
fi
if ! git pull --rebase 2>/dev/null; then
  # Resolve conflicts (same strategy as ar-taskflow)
  # For TasksSummary: extract rows from both sides, deduplicate by Task column
fi
git push || echo "Push failed - push $coding_tasks_root manually"
cd -
```

---

## Phase 0: Initialize & Create Planning Ticket

**Trigger:** User says "ar-taskflow-planner", "plan feature", or "plan initiative"

### Step 0a: Read Configuration

Read `.claude/skill.config` and `.claude/config_hints.json`. Derive all paths listed above.

**If skill.config missing:**
```
Configuration missing. Run "ar-init-skills" first.
```

### Step 0b: Get Feature Description

Ask the user:

```
What feature or initiative do you want to plan?

Give me a brief description (1-2 sentences).

Examples:
- "Replace Airflow cron jobs with event-driven processing"
- "Add multi-currency support across the payment pipeline"
- "Build item recommendation engine for browsing packages"
```

### Step 0c: Generate Plan Identifiers

From the user's description, generate:
- **Plan title**: Human-readable (e.g., "Replace Cron Jobs with Event-Driven Worker")
- **Plan slug (folder)**: PascalCase, max 40 chars (e.g., `EventDrivenWorker`)
- **Plan slug (branch)**: kebab-case (e.g., `event-driven-worker`)
- **Ticket summary**: `{project_namespace}:Plan:{Plan Title}`

Confirm with user:
```
Plan: {title}
Ticket: {project_namespace}:Plan:{title}
Folder: {planning_root}/{project_namespace}-Plan-{PascalSlug}/

Correct? (yes / adjust)
```

### Step 0d: Ask for the parent (Jira path, Epic)

For github there is no Epic; skip this step (optionally note a label/milestone to apply).

```
Which Jira Epic should this plan be attached to?

Provide the Epic key (e.g., {namespace}-31) or "none" to skip.
```

If user provides an Epic key, validate it exists (Jira path):
```bash
# Use Atlassian MCP to verify the Epic exists
# mcp__claude_ai_Atlassian_2__getJiraIssue(cloudId="{tracker_url}", issueIdOrKey="{epic_key}")
```

### Step 0e: Create Planning Ticket

Create the planning ticket immediately to signal to the team that planning has started.
Use the **Create-ticket** row for your `tracker.type` in the Tracker Dispatch Table
(`<standards_location>/mcp-integration.md`). For github:

```bash
gh issue create --title "{project_namespace}:Plan:{Plan Title}" \
  --body "Planning has started for: {Plan Title}

{user's original description}

This ticket tracks the planning phase. A Story ticket will be created once the plan is finalized with implementation tasks."
```

**(Jira path)** create the Task ticket via the Atlassian MCP:
```bash
# mcp__claude_ai_Atlassian_2__createJiraIssue(
#   cloudId="{tracker_url}",
#   projectKey="{project_namespace}",
#   issueType="Task",
#   summary="{project_namespace}:Plan:{Plan Title}",
#   description="Planning has started for: {Plan Title}\n\n{user's original description}\n\nThis ticket tracks the planning phase. A Story ticket will be created once the plan is finalized with implementation tasks.",
#   parentKey="{epic_key}"  # if provided
# )
```

Store the created ticket key/number as `PLAN_TICKET` (e.g., `{namespace}-540`, or `#540` for github).

### Step 0f: Move Ticket to In Progress (Jira path)

For github there is no status workflow to advance here, skip. **(Jira path)** transition the planning ticket to "In Progress":

```bash
# Get available transitions
# mcp__claude_ai_Atlassian_2__getTransitionsForJiraIssue(cloudId="{tracker_url}", issueIdOrKey="{PLAN_TICKET}")
# Find the "In Progress" transition ID
# mcp__claude_ai_Atlassian_2__transitionJiraIssue(cloudId="{tracker_url}", issueIdOrKey="{PLAN_TICKET}", transitionId="{in_progress_id}")
```

Tell the user:
```
Planning ticket created: {PLAN_TICKET} - {project_namespace}:Plan:{title}
Status: In Progress
Epic: {epic_key or "none"}

Your team can now see that planning has started.
```

### Step 0g: Create Planning Directory

```bash
plan_dir="$planning_root/{project_namespace}-Plan-{PascalSlug}"
mkdir -p "$plan_dir/raw_prompts"
```

### Step 0h: Check for Existing Plan

Check if `{plans_folder}/{PascalSlug}/plan_manifest.json` exists locally first, so resume works offline and deterministically. Only if the local copy is missing, fall back to a configured shared docs store:

```bash
# Local check first (offline/deterministic resume)
if [ -f "{plans_folder}/{PascalSlug}/plan_manifest.json" ]; then
  : # existing plan found locally → Resume/Update (Phase 6)
elif [ -n "$docs_store_base" ]; then
  : # no local copy → fetch plan_manifest.json from the shared docs store at
    # "{docs_store_base}/UnderProcessing/{PascalSlug}/plan_manifest.json" (skip if no store)
fi
```

**If plan exists:** Jump to Phase 6 (Resume/Update).

---

## Phase 1: Discovery & Architecture Discussion

**Purpose:** Interactive architecture discussion. Think it through before writing.

### Step 1a: Understand Current State

1. Read relevant codebase areas to understand the current implementation
2. Read any existing docs the user points to (local files, a wiki page, a shared docs store, etc.)
3. If the user references a document in a shared docs store, fetch it from that store using whatever access method the store provides

### Step 1b: Guided Discussion

Ask structured questions (adapt to context - skip what's already clear):

1. **Problem**: What problem does this solve? What's the business motivation?
2. **Current state**: What exists today? What are the limitations?
3. **Constraints**: Infrastructure limits, timeline, team capacity, external dependencies?
4. **Options**: Are there multiple architecture approaches to evaluate?

### Step 1c: Evaluate Options (if applicable)

If multiple approaches exist:
1. Create a comparison table (aspects: complexity, cost, infra needed, scalability, vendor lock-in, etc.)
2. Discuss trade-offs with the user
3. Help user choose an approach
4. Document why the chosen approach was selected and why others were rejected

### Step 1d: Confirm Approach

Summarize the chosen approach:

```
Architecture approach confirmed:
- Approach: {summary}
- Key constraint: {constraint}
- Key trade-off: {trade-off}
- Planning ticket: {PLAN_TICKET}

Ready to write the spec document?
```

Wait for user confirmation before proceeding.

---

## Phase 2: Create Spec Document

**Purpose:** Write the comprehensive architecture/design document.

### Step 2a: Write Spec

Write `spec.md` covering (adapt sections to the feature - not all are required):

- **Overview** - what and why (1-2 paragraphs)
- **Why this change?** - problem statement, current limitations
- **Comparison table** (if alternatives were evaluated) - why this approach over others
- **Architecture diagram** (mermaid) - system-level view
- **Component design** - each major piece described
- **Error handling** - failure scenarios and recovery
- **Reliability / degradation** - what happens when things break
- **Monitoring** - what to observe, alert thresholds
- **Migration / rollout plan** - how to safely deploy
- **Implementation checklist** - high-level task list

Write in product-focused language. Prefer mermaid for diagrams.

### Step 2b: Publish Spec

Write the canonical copies locally (these get committed when you push docs):

1. **Local:** `$planning_root/{project_namespace}-Plan-{PascalSlug}/spec.md`
2. **Docs folder:** `$plans_folder/{PascalSlug}/spec.md`
3. **Shared docs store (optional):** if `docs_store_base` is set, also publish the same content to `{docs_store_base}/UnderProcessing/{PascalSlug}/spec.md` using the store's write method (creating or overwriting the page as needed). If no store is configured, skip this, the committed local files are the source of truth.

### Step 2c: Update Planning Ticket

Add the spec as a comment on the planning ticket:

```bash
# mcp__claude_ai_Atlassian_2__addCommentToJiraIssue(
#   cloudId="{tracker_url}",
#   issueIdOrKey="{PLAN_TICKET}",
#   body="Spec document created.\n\nLocal: {local_path}\nShared docs store: {store_path or 'n/a'}\n\nProceeding to break into implementation tasks."
# )
```

### Step 2d: User Review

```
Spec document created:
- Local: {local_path}
- Shared docs store: {store_path or "local-only"}
- Planning ticket: {PLAN_TICKET} (comment added)

Please review the spec. Approve to proceed to prompt breakdown, or tell me what to adjust.
```

Wait for user confirmation. If adjustments needed, edit and re-publish.

**Push docs.**

---

## Phase 3: Break Into Raw Prompts

**Purpose:** Decompose the spec into sequential, PR-sized ar-taskflow prompts.

### Step 3a: Identify Task Boundaries

Analyze the spec and identify natural boundaries where each chunk:
- Produces one PR
- Is independently testable
- Has clear dependencies on prior tasks
- Is small enough for one ar-taskflow session

### Step 3b: Draft Prompt Breakdown

Present as a table:

```
Proposed {N} raw prompts:

| # | Title | What it delivers | Depends on |
|---|-------|-----------------|------------|
| 01 | {title} | {deliverable} | - |
| 02 | {title} | {deliverable} | - |
| 03 | {title} | {deliverable} | 01 |
| 04 | {title} | {deliverable} | 01, 02 |
...

Tasks {01, 02} can run in parallel.
Task {04} is the critical path after {01, 02}.
```

### Step 3c: User Review

```
Adjust? (reorder, split, merge, add, remove)
Or approve to write them?
```

Wait for user to approve the breakdown.

---

## Phase 4: Write Prompts & Create Artifacts

**Purpose:** Write all raw prompts, overview, and manifest.

### Step 4a: Write Raw Prompts

For each prompt (01 through NN):

1. Write content following the Raw Prompt Convention (see below)
2. Save locally: `$planning_root/{project_namespace}-Plan-{PascalSlug}/raw_prompts/{NN}_{slug}.md`
3. Also save to docs: `$plans_folder/{PascalSlug}/raw_prompts/{NN}_{slug}.md`
4. If `docs_store_base` is set, also publish the same content to `{docs_store_base}/UnderProcessing/{PascalSlug}/raw_prompts/{NN}_{slug}.md` in the shared docs store. Skip when no store is configured.

### Step 4b: Write Overview

Write `00_overview.md` with:
- Plan title and description
- Planning ticket reference: `{PLAN_TICKET}`
- Link to the full spec (relative doc path, or `{docs_store_base}/...` when a store is configured)
- Task sequence table (same as Step 3b)
- Dependency graph (ASCII or mermaid)
- Parallelism notes (which tasks can run concurrently)
- Migration notes (if applicable)

Save locally, to the docs folder, and publish to the shared docs store if one is configured.

### Step 4c: Write Plan Manifest

Write `plan_manifest.json`:

```json
{
  "plan_id": "{branch-slug}",
  "plan_title": "{title}",
  "plan_ticket": "{PLAN_TICKET}",
  "story_ticket": null,
  "created": "{YYYY-MM-DD}",
  "owner": "{git user.email}",
  "status": "planned",
  "story_branch": null,
  "spec_path": "spec.md",
  "docs_store_base": "{docs_store_base}/UnderProcessing/{PascalSlug}",
  "prompt_count": {N},
  "prompts": [
    {
      "sequence": 1,
      "file": "01_{slug}.md",
      "title": "{prompt title}",
      "depends_on": [],
      "status": "planned",
      "task_flow_folder": null,
      "branch": null,
      "pr": null
    }
  ]
}
```

(`docs_store_base` is only meaningful when a shared store is configured; in local-only mode set it to `null` or omit it.)

Save locally and, if a store is configured, publish to the shared docs store.

### Step 4d: Verify

Confirm each file was written correctly by reading back the first few lines from its canonical local copy (and from the shared docs store as well, if one is configured).

**Push docs.**

---

## Phase 5: Create Story & Track

**Purpose:** On user's final approval, create the Story ticket, story branch, and log the plan.

### Step 5a: Final Confirmation

```
Plan is ready:
- Spec: {spec_path}
- Raw prompts: {N} implementation tasks
- Planning ticket: {PLAN_TICKET}

Ready to create the Story ticket and story branch? (yes / adjust)
```

Wait for user confirmation.

### Step 5b: Create Story Ticket

Create the parent ticket for all implementation work using the **Create-ticket** row for
your `tracker.type` in the Tracker Dispatch Table. For github there is no Story/Epic
hierarchy, create a tracking issue (`gh issue create`) and use it as the umbrella (link
children via `Tracks #N` in the issue body, or a milestone/label). **(Jira path)** create a
Story ticket via the Atlassian MCP:

```bash
# Build story description from the overview and prompt list
# mcp__claude_ai_Atlassian_2__createJiraIssue(
#   cloudId="{tracker_url}",
#   projectKey="{project_namespace}",
#   issueType="Story",
#   summary="{Plan Title}",
#   description="## Overview\n{spec overview}\n\n## Implementation Tasks\n{numbered list of raw prompts with titles}\n\n## Spec\nFull spec: {spec doc path}\n\n## Raw Prompts\n{list of doc paths to each prompt}\n\nCreated by ar-taskflow-planner from planning ticket {PLAN_TICKET}.",
#   parentKey="{epic_key}"  # same epic as planning ticket
# )
```

Store the created ticket key as `STORY_TICKET` (e.g., `{namespace}-528`).

### Step 5c: Move Story to In Progress (Jira path)

For github there is no status workflow to advance, skip. **(Jira path)**:

```bash
# mcp__claude_ai_Atlassian_2__getTransitionsForJiraIssue(cloudId="{tracker_url}", issueIdOrKey="{STORY_TICKET}")
# mcp__claude_ai_Atlassian_2__transitionJiraIssue(cloudId="{tracker_url}", issueIdOrKey="{STORY_TICKET}", transitionId="{in_progress_id}")
```

### Step 5d: Link Planning Ticket to Story

Add a comment on the planning ticket linking to the story:

```bash
# mcp__claude_ai_Atlassian_2__addCommentToJiraIssue(
#   cloudId="{tracker_url}",
#   issueIdOrKey="{PLAN_TICKET}",
#   body="Story created: {STORY_TICKET} - {Plan Title}\n\nPlan finalized with {N} implementation tasks.\nStory branch: story/{STORY_TICKET}-{branch-slug}\n\nThis planning ticket can be closed."
# )
```

Optionally transition the planning ticket to Done (ask user):

```
Planning ticket {PLAN_TICKET} can be closed now that the story is created.
Close it? (yes / no)
```

### Step 5d-2: Link implementation tickets (Jira path, native issue links)

This step uses Jira's native issue-link types. For github there are no typed links -
express the same dependencies as `Blocked by #N` / `Tracks #N` references in the issue body
(still derived mechanically from `plan_manifest.json`). **(Jira path)** whenever implementation tickets are created for this plan's prompts (now or later), derive the links **mechanically from `plan_manifest.json`**, never leave dependencies as prose-only:

1. Find the "Blocks" link type once: `getIssueLinkTypes` (cloudId = `{tracker_url}`).
2. **Every implementation ticket blocks the Story**: `createIssueLink(type="Blocks", inwardIssue={STORY_TICKET}, outwardIssue={ticket})`, the blocker is the `outwardIssue` ("blocks"); the `inwardIssue` "is blocked by" it. So the ticket blocks the Story, and the Story shows its full dependency list natively.
3. **Inter-ticket links from the dependency graph**: for each prompt with `depends_on: [X]`, the ticket of X blocks this prompt's ticket: `createIssueLink(type="Blocks", inwardIssue={this_ticket}, outwardIssue={ticket_of_X})`, `ticket_of_X` (the blocker) is the `outwardIssue`.

**Lifecycle rule (applies to every ticket this skill creates or updates):** after creating/updating, check "does its status/assignee match what is actually true right now?", e.g. tickets for already-implemented work transition to their real state (Ready for QA), not left at To Do. Fix it in the same step, don't wait for the user to point it out.

### Step 5e: Create Story Branch

```bash
cd "$(git rev-parse --show-toplevel)"   # repo root, run from anywhere inside the repo
git checkout main
git pull origin main
git checkout -b "story/{STORY_TICKET}-{branch-slug}"
git push -u origin "story/{STORY_TICKET}-{branch-slug}"
git checkout main  # return to main
```

### Step 5f: Update Plan Manifest

Update `plan_manifest.json` with story details:

```json
{
  "story_ticket": "{STORY_TICKET}",
  "story_branch": "story/{STORY_TICKET}-{branch-slug}",
  "status": "ready"
}
```

Publish the updated manifest to the local plan folder and docs folder, and to the shared docs store if one is configured.

### Step 5g: Calculate Week Ending

```bash
# macOS
current_day=$(date +%A)
if [ "$current_day" = "Friday" ]; then
  week_date=$(date +%Y-%m-%d)
else
  week_date=$(date -d "next friday" +%Y-%m-%d 2>/dev/null || date -v +fri +%Y-%m-%d)
fi
```

### Step 5h: Create Weekly Summary File

Write to `$weekly_summaries_root/Week-Ending-{week_date}/{start_date}_{platform}_PLAN-{branch-slug}.md`:

```markdown
# PLAN: {Plan Title}

**Date:** {YYYY-MM-DD} | **Developer:** {git user.email} | **Platform:** {platform}

**Planning Ticket:** {PLAN_TICKET}
**Story Ticket:** {STORY_TICKET}

**What:** {1-2 sentence problem statement}

**Output:** Comprehensive spec document + {N} sequential raw prompts ready for ar-taskflow execution. Dependencies mapped. Story branch created.
```

### Step 5i: Log in TasksSummary

Add row to `$task_summary_folder/{platform}.md` in the appropriate week section:

```markdown
| PLAN {Plan Title} | {git user.email} | {date} | - | {N} raw prompts, {approach summary}. Story: {STORY_TICKET} | [Link](../../WeeklySummaries/Week-Ending-{week_date}/{start_date}_{platform}_PLAN-{branch-slug}.md) |
```

**Push docs.**

### Step 5j: Present Summary

```
Plan complete!

Planning ticket: {PLAN_TICKET} (closed)
Story ticket: {STORY_TICKET} - {Plan Title}
Spec: {spec_path}
Overview: {overview_path}
Raw prompts: {N} files ({prompts_path}/01..{NN})
Manifest: {manifest_path}
Story branch: story/{STORY_TICKET}-{branch-slug}
TasksSummary: PLAN {title} logged

To start executing:
  1. Run "ar-taskflow"
  2. Choose ticket-late approach
  3. Point to raw prompt 01 (or any prompt with no unstarted dependencies)
  4. When Claude asks for context in Phase 1, tell it:
     "This is part of story/{STORY_TICKET}-{branch-slug}. Branch from it and target PRs to it."
     Claude will add the branching strategy to prompt-understanding.md automatically.
  
  The raw prompt links the spec for full context.
  Tasks {list independent ones} can be parallelized.
```

---

## Phase 6: Resume / Update

**Trigger:** Phase 0h detected an existing plan.

### Step 6a: Read Current State

Read `plan_manifest.json` from its canonical local copy at `{plans_folder}/{PascalSlug}/plan_manifest.json`. If the local copy is missing and a shared docs store is configured, fetch it from `{docs_store_base}/UnderProcessing/{PascalSlug}/plan_manifest.json` instead.

Parse the manifest. Count prompts by status.

### Step 6b: Present Options

```
Existing plan found: {title}
Planning ticket: {plan_ticket}
Story ticket: {story_ticket or "not yet created"}
Created: {date}
Status: {planned} planned, {in_progress} in progress, {completed} completed out of {total} prompts

What would you like to do?
1. Add more prompts (extend the plan)
2. Update the spec (requirements changed)
3. View child task status
4. Archive this plan
```

### Option 1: Add More Prompts

- Continue numbering from NN+1
- Write new prompts following the same conventions
- Update `00_overview.md` with new entries
- Update `plan_manifest.json` with new prompt entries
- Update story ticket description with new prompt list
- Push docs

### Option 2: Update Spec

- Re-enter Phase 2 with existing spec as base
- After spec update, ask if prompts need adjustment
- If yes, update affected prompts (don't renumber existing ones)
- Add comment on story ticket about spec update
- Push docs

### Option 3: View Status

- Read manifest
- For each prompt with a `task_flow_folder`, check task folder status
- For each prompt with a `pr`, check PR merge status via `gh pr view`
- Report:
  ```
  Plan: {title} ({M}/{N} prompts active)
  Story: {STORY_TICKET} | Branch: story/{STORY_TICKET}-{slug}
  
  | # | Title | Status | Branch | PR |
  |---|-------|--------|--------|----| 
  | 01 | ... | completed | feature/{namespace}-530-... | #312 (merged) |
  | 02 | ... | in_progress | feature/{namespace}-531-... | #313 (open) |
  | 03 | ... | planned | - | - |
  ```

### Option 4: Archive

- Move local plan folder to `$plans_folder/Archive/{PascalSlug}`
- Update TasksSummary: set Completed date on the PLAN row
- Transition story ticket to Done (if all prompts completed)
- Push docs

---

## Raw Prompt Writing Convention

Every raw prompt generated by this skill MUST follow these rules:

### Content Rules

1. **Describe WHAT to achieve, not HOW to implement.** No class names, file paths, method signatures, config property names, or code snippets. Let ar-taskflow's prompt-understanding phase discover implementation details from the actual codebase.

2. **Conversational tone.** Write like you're explaining to a colleague who understands the domain but hasn't seen the code. Not a formal spec, not a code review.

3. **Include investigation directives.** Tell the AI to read the code before deciding on approach:
   - "Investigate how the existing batch processing services find pending packages"
   - "Look at the actual service implementations to understand the flow"
   - "Follow the existing project patterns"

4. **State the problem first.** Why does this task exist? What user or system problem does it solve?

5. **Be specific about outcomes, vague about implementation.** 
   - Good: "Build a listener that processes packages immediately after payment capture"
   - Bad: "Create PostPaymentListener.java implementing StreamListener<String, MapRecord>"

6. **State dependencies explicitly.** `**Depends on:** Task 01 (description), Task 02 (description)`

7. **Keep it concise.** 10-20 lines per prompt. Enough context to understand the task, not so much that it constrains the solution.

8. **Plain, readable English** (applies to every ticket/prompt this convention governs, raw prompts, ticket descriptions, ar-ticket-creator output):
   - Short sentences. One idea per sentence.
   - Simple words. No dense, em-dash-heavy, multi-clause prose.
   - Prefer numbered steps and short bullets over paragraph walls.
   - A "Human version" must read like explaining to a colleague over coffee, no unexplained jargon.
   - Read it back: if a sentence needs two passes to parse, rewrite it.
   - Good: "Make one shared checkout function with an explicit flag: run the optional upstream checks, or skip them. Keep: price calculation, discount eligibility, cart validation. Remove: the inventory re-check, the tax recalculation, and the shipping-estimate call."
   - Bad: "Refactor so one shared checkout function takes an explicit flag controlling whether the optional upstream checks run, keeping price calculation, discount eligibility and cart validation but making no inventory re-check, no tax recalculation, and no shipping-estimate call."

### Footer Convention

Every raw prompt ends with a reference to the full spec so ar-taskflow can read it for context:

```markdown

See full architecture plan: {path_to_spec}
```

The path can be a local doc path or, if a shared docs store is configured, a `{docs_store_base}/...` path, depending on where the spec was published. The user will provide this to ar-taskflow when starting a child task.

### Story Branch in prompt-understanding.md

Raw prompts intentionally do NOT contain branching instructions (keeping them clean and non-noisy). Instead, when ar-taskflow runs Phase 1 on a child prompt, the user should tell Claude the story branch. Claude then adds a standardized section to `prompt-understanding.md`:

```markdown
## Branching Strategy

This task is part of a multi-PR story. Branch from and target PRs to the story branch:
- **Story branch:** story/{STORY_TICKET}-{branch-slug}
- **Feature branch:** feature/{namespace}-XXX-{task-slug} (branched from story/{STORY_TICKET}-{branch-slug})
- **PR target:** story/{STORY_TICKET}-{branch-slug} (not main)
```

This ensures ar-taskflow's Phase 3 (branch creation) and Phase 4k (PR creation) naturally follow the story branch strategy - because the execution plan will be built from the prompt-understanding that includes this section.

---

## PLAN Prefix Convention

### In TasksSummary

```markdown
| PLAN {Plan Title} | owner | date | - | N raw prompts, approach summary. Story: {STORY_TICKET} | [Link](...) |
```

- **Prefix is always `PLAN`** (not `PLAN-XXX`, no number)
- **Completed column** (`-` until done): Set when all raw prompts have been picked up by ar-taskflow (planning work is done). Individual child prompts track their own completion via {NS}-XXX rows.
- **PLAN rows never convert to {NS}-XXX.** They stay as PLAN. Child prompts get their own rows.
- **Description column**: Always includes prompt count, approach summary, and Story ticket.

### In Weekly Reports

- PLAN tasks **never** appear in "Shipped" (no PR, no deploy, no user-visible change)
- PLAN tasks appear in "In Progress" with planning-specific language:
  - "Architecture plan completed for {feature}, {N} implementation tasks sequenced"
  - Or when child tasks are executing: "{M}/{N} tasks in progress for {feature}"

### Relationship to Child Tasks

```
TasksSummary:
| PLAN Event Driven Worker | dev | Apr 20 | Apr 22 | 8 prompts, Redis Streams. Story: {namespace}-528 | [Link] |
| {namespace}-530 Worker Skeleton   | dev | Apr 23 | Apr 24 | module-worker Spring Boot                | [Link] |
| {namespace}-531 Extract Methods   | dev | Apr 23 | Apr 25 | per-package processing                   | [Link] |
...
```

The PLAN row is the parent. {NS}-XXX rows are children created by ar-taskflow when executing the raw prompts. Both appear in TasksSummary but are independently tracked.

---

## Error Handling

**skill.config missing:**
```
Configuration missing. Run "ar-init-skills" first.
```

**Atlassian MCP not configured:**
```
Atlassian MCP not configured. Run "ar-init-mcps" to set up Jira integration.
Planning can continue without Jira (tickets will be created manually).
```

If MCP is not available, skip Jira steps (0e, 0f, 2c, 5b, 5c, 5d) and tell the user to create tickets manually. The rest of the workflow works without Jira.

**Shared docs store unavailable:**
```
Shared docs store could not be reached (or none is configured).
Falling back to local-only mode, the committed docs repo is the source of truth.
```
The local files are canonical, so this never blocks planning. Note it to the user and continue.

**Story branch already exists:**
```
Branch story/{slug} already exists. Using existing branch.
```

**Shared docs store publish fails (page already exists):**
Overwrite the existing page in the store rather than creating a new one. If the store cannot be written to at all, drop to local-only mode (above), the committed local copy is authoritative.

**Jira ticket creation fails:**
```
Could not create Jira ticket. Error: {error}
Continuing without Jira. Create the ticket manually and provide the key.
```

Ask user for the ticket key if they created it manually.
