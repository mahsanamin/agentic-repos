# Process Discussion

Process raw discussion file(s), update compiled knowledge + meeting log, archive raw file.

**Base path:** `{{BASE_PATH}}`

## Prerequisites

Ensure these directories exist (create with `mkdir -p` if missing):
- `{base}/RawInformation/meetings/`, `{base}/RawInformation/emails/`
- `{base}/Context/OnGoingKnowledeDiscussionSummary/`, `{base}/Context/OnGoingKnowledeDiscussionSummary/OnGoingEmailsSummary/`
- `{{ARCHIVE_PATH}}/OnGoingDiscussions/meetings/`, `{{ARCHIVE_PATH}}/OnGoingDiscussions/emails/`

Create `CompiledDiscussionState.md` or `Meetings_Summaries.md` with minimal templates if missing.

## Formatting Rules (inline)

- Never use `---` horizontal rules.
- No repetition across sections. Keep concise.
- Preserve exact phrasing from key speakers. Use their actual words.
- Infer the "why" behind decisions from context. Write naturally, not like a transcript parser.

## Instructions

1. **Find raw files** in `{base}/RawInformation/meetings/` and `{base}/RawInformation/emails/`. Process argument file if given, else all. If empty, ask the user for input.

2. **Read compiled doc** at `{base}/Context/OnGoingKnowledeDiscussionSummary/CompiledDiscussionState.md`. Skim for existing topics to avoid duplication.

3. **Read and analyze each raw file.** Extract: decisions, action items, technical details, new information. For emails from clients: extract technical facts and blockers, preserve exact quotes.

4. **Prepend meeting summary** to `{base}/Context/OnGoingKnowledeDiscussionSummary/Meetings_Summaries.md` using the format from `context-meeting-minutes`. Latest first. For emails, set Type to `Email Thread`.

5. **For email threads**, update/create the matching file in `{base}/Context/OnGoingKnowledeDiscussionSummary/OnGoingEmailsSummary/` per the `context-collect-emails` format.

6. **Update compiled knowledge doc:**
   - Merge into existing sections or create new ones for new topics.
   - No duplication across sections.
   - Update **Last Updated** date, add Changelog row, add Sources row (Sources table always last).

7. **Archive raw file as-is** (no reformatting, no transcript cleanup):
   - `mv` meetings to `{{ARCHIVE_PATH}}/OnGoingDiscussions/meetings/`
   - `mv` emails to `{{ARCHIVE_PATH}}/OnGoingDiscussions/emails/`

8. **Confirm** in 2-3 lines: file processed, what was added, archived.

## Token Efficiency

- Do NOT rewrite or clean up the raw transcript. The value is in the summary and compiled doc, not the archive.
- Read files in parallel where possible (raw file + compiled doc + meetings log).
- Write meeting summary and compiled doc update in parallel (independent edits).
- Keep the confirmation short.
