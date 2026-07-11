# Collect & Compile Email Thread

Process raw email content into a structured thread summary. Preserve exact quotes from external parties.

**Base path:** `{{BASE_PATH}}`

## Prerequisites

Ensure dirs exist (`mkdir -p`): `{base}/RawInformation/emails/`, `{base}/Context/OnGoingKnowledeDiscussionSummary/OnGoingEmailsSummary/`, `{{ARCHIVE_PATH}}/OnGoingDiscussions/emails/`. Create `CompiledDiscussionState.md` if missing.

## Instructions

1. **Find raw emails** in `{base}/RawInformation/emails/`. Process argument file if given, else all. If empty, ask user for input.

2. **Identify thread:** subject/topic, participants (Name + Org), date range.

3. **Check for existing thread summary** in `{base}/Context/OnGoingKnowledeDiscussionSummary/OnGoingEmailsSummary/`. Match by topic. Update if found, create new if not.

4. **Write/update thread summary** using the format below. When updating: add new exchanges to chronology (latest first), move resolved blockers to Recently Resolved, add new blockers, update Confirmed items and Pending items.

5. **Update compiled doc**, merge key decisions and blockers into `CompiledDiscussionState.md`. Add Changelog + Sources rows.

6. **Archive raw file as-is**, `mv` to `{{ARCHIVE_PATH}}/OnGoingDiscussions/emails/`.

7. **Confirm** in 2-3 lines.

## Thread Summary Format

File naming: `[Topic_Snake_Case]_Email_Thread.md` in `OnGoingEmailsSummary/`.

```markdown
# [Thread Topic] - Email Thread

**Status:** [Active / Resolved / Waiting on External]
**Last Update:** [Date]
**Participants:** [Name (Org), ...]

## Current Status

### Confirmed Items
- [Fact confirmed by person on date]

### Current Blockers ([Date])
1. **[Title]**, Status: [desc] | Impact: [what it blocks] | Latest: [update]

### Known Limitations
- [Limitation with context]

### Pending Items
- [Item + owner]

### Recently Resolved ([Date Range])
- [Item + resolution date]

## Thread Chronology

### [Date], [Subject]
**From:** [Sender] | **To:** [Recipients]
[Key content. Exact quotes for technical details, config, commitments.]
**Action Items:** [Person]: [Action]
```

## Rules

- Preserve exact quotes from external parties. Extract specific values: endpoints, IDs, config, error codes.
- Track promised vs delivered, with dates. Mark "confirmed by [person] on [date]."
- No editorializing. No paraphrasing technical details. No pleasantries/boilerplate. No raw email addresses (use Name (Org)).
- Discard: signatures, "please find attached" filler, CC lists, repeated forwarded content.
