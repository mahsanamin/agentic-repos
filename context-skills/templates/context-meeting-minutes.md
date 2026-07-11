# Meeting Minutes Extractor

Prepend a compact summary to `Meetings_Summaries.md`. Latest first, one file for all meetings. Does NOT archive files or update compiled doc (those belong to `context-collect-discussions`).

**Base path:** `{{BASE_PATH}}`
**Output:** `{base}/Context/OnGoingKnowledeDiscussionSummary/Meetings_Summaries.md`

Create the file with `# Meeting Summaries` header if missing.

## Format

```markdown
## [Meeting Title]
**Date:** YYYY-MM-DD | **Participants:** [Names (Role)] | **Type:** [1-on-1 / Group / Standup / Adhoc / Email Thread]
**Source:** [Slack URL, only for Slack-sourced, omit for files]
**[Link Label]:** [URL, Figma, PRD, etc. if found]

**Context:** One sentence on why + deadline if any.

**Key Points:**
- [Decision, fact, or open question. 1-2 short sentences max. 4-6 bullets.]

**Expected Tasks:**
- **[Person]:** [Concrete deliverable + timeline if stated.]

**TODOs:**
- **[Person]:** [Immediate action. Full sentence.]
```

## Rules

- Be precise and dense. Strip filler. Use shorthand ("=" for "which is", parenthetical context).
- Direct quotes from key speakers: only the most impactful phrase, not paragraphs.
- **Key Points** = facts, decisions, constraints (not things to do).
- **Expected Tasks** = deliverables to build/produce. Named person required.
- **TODOs** = immediate actions: meetings to schedule, coordination. Named person required.
- No dash character in prose. No paragraphs. No extra headers.
- No duplicate info across sections.

## What to Discard

- Stale numbers (sprint days, countdowns)
- Generic management actions ("define tasks", "keep teams updated")
- Repeated context already in Tasks/TODOs
- Casual mentions without concrete actions
- Relative urgency without actual deadlines

## Input

Raw transcript (file or pasted) or Slack thread link. For Slack: read full thread including replies, treat final state as source of truth. Check for existing entry by URL/title+date before adding.

## Process

1. Read `Meetings_Summaries.md`. Check for existing entry (update in place if found).
2. Extract: participants, date, type, decisions, blockers, commitments, links.
3. Prepend new section after header. Keep existing entries untouched.
4. Confirm what was added (1 line).
