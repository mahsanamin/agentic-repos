# Update Project State

Read the current project state and apply updates to milestones, blockers, shipped items, roadmap, and team status.

**Target file:** `{{BASE_PATH}}/ProjectStatus/ProjectState.md`

## Prerequisites

Ensure dirs exist: `{{BASE_PATH}}/ProjectStatus/`, `{{BASE_PATH}}/Context/OnGoingKnowledeDiscussionSummary/`. Create `ProjectState.md` with minimal template if missing.

## Instructions

1. **Read current ProjectState.md.**

2. **Ask the user what changed:**
   1. Milestone update (shipped item, status change)
   2. Blocker change (new, resolved, escalation)
   3. Roadmap update (new items, reprioritization, completion)
   4. Team change (new member, role, availability)
   5. Decision or context update
   6. Auto-detect from recent discussions

3. **For auto-detect (option 6):**
   - Read `CompiledDiscussionState.md`, `Meetings_Summaries.md`, and `OnGoingEmailsSummary/` from `{base}/Context/OnGoingKnowledeDiscussionSummary/`
   - Compare "Last Updated" date in ProjectState.md against discussion dates
   - Present detected changes, ask confirmation before applying

4. **Apply updates** to correct sections. Update "Last updated" date. Preserve existing structure.

5. **Confirm** what was updated, which sections changed (2-3 lines).

## Rules

- Never remove history. Keep completed items visible.
- Preserve context notes in each section. Update them, don't delete.
- Use absolute dates (YYYY-MM-DD). Convert relative dates.
- Flag contradictions to user before applying.
- Don't touch Documentation Map unless asked.

## Context Sources (priority order for auto-detect)

1. Recent meeting summaries (decisions and status changes)
2. Email thread updates (external blockers)
3. Compiled discussion state (confirming decisions, may lag)
4. Git log (`git log --oneline -20` for what actually shipped)
