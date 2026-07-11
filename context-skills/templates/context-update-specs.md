# Update Specs, Cross-Document Propagation

When a change is made to any spec, this skill ensures every affected document is updated consistently.

**Base path:** `{{BASE_PATH}}`

## Prerequisites

Ensure dirs exist: `{base}/Context/OnGoingKnowledeDiscussionSummary/`, `{base}/Context/OnGoingKnowledeDiscussionSummary/OnGoingEmailsSummary/`. Skip missing registry dirs gracefully.

## Document Registry

<!-- PROJECT-SPECIFIC: Customize this section for your project.
     List every directory/file that may reference specs, grouped by category.
     Example entry:
     | `Context/Engineering/api_specs.md` | Request/response fields, endpoint paths |
-->

| Path | What to check |
|------|---------------|
| `{base}/Context/` | All context documents referencing the changed entity |
| `{base}/Context/OnGoingKnowledeDiscussionSummary/CompiledDiscussionState.md` | Compiled knowledge referencing the changed entity |

## Process

1. **Ask for change details:**
   - Option 1: Auto-detect from git diff. List detected changes, ask for confirmation.
   - Option 2: Manual input from user (e.g., "renamed field X to Y", "added endpoint Z").

2. **Identify change scope:** field rename, endpoint change, flow update, etc.

3. **Read every file in Document Registry.** Search for references to the changed entity (old name, related names, descriptions).

4. **Report findings before editing:**
   ```
   Files affected:
   - path/file.md, [needs X change]
   - path/other.md, [no references found]
   ```

5. **Apply updates.** Preserve existing formatting and structure per file.

6. **Confirm** what was updated and what changed in each file.

## Rules

- Read before editing. Never assume a file does or doesn't reference the changed entity.
- Match each file's formatting conventions (Mermaid, JSON, tables, etc.).
- Only change references to the specific entity modified. Don't refactor surrounding content.
- Flag ambiguity to the user rather than guessing.
