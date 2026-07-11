---
name: ar-weekly-report
description: Generate a defensible weekly status report from task tracking artifacts. Audience-configurable (CEO/CTO, Engineering Lead, PM, etc.). Reads TasksSummary, WeeklySummaries, ProjectState, and per-task folders to produce evidence-grounded prose. Say "ar-weekly-report" or "weekly report".
disable-model-invocation: true
---

# Weekly Report Generator

Generates a weekly status report for the project, scoped to a defined audience (executive, engineering leadership, product, etc.). Every claim ties to a this-week evidence row from the task tracking system, no fabrication, no padding, no engineering plumbing in management copy.

## Audience and voice (read first)

The audience is configured per project via `config_hints.json` → `weekly_report.audience` (e.g., `"CEO and CTO"`, `"Engineering Lead and PM"`, `"Product team"`). Match voice and detail level to that audience:

- **Executive audience (CEO/CTO):** product and business signal, not engineering internals. Read like a human wrote it, not an AI listing PRs. Short headlines, structured fields, one idea per sentence, no engineering plumbing.
- **Engineering leadership audience:** more technical detail allowed (system names, integration state, perf numbers). Still no PR/branch chatter, that belongs in PR descriptions.
- **Product audience:** outcomes and timelines. Less infra, more "what changes for users / what we learned this week".

When in doubt, **understate**. Overstating delivery, calling something "feature-complete" when it depends on a stub, calling something "shipped" when it sits in a feature branch, actively misleads decisions at every audience level.

## The non-negotiables

These apply to every audience. They are why the report is defensible.

1. **No fabrication.** Every concrete claim, concerns, milestones, dates, mock state, dependencies, named people, must trace to a this-week source you actually read. Previous reports are history, not sources. Older meeting notes are pointers to "this was true at some point", not evidence it is true this week. If you cannot cite a this-week source, the claim does not go in the report.
2. **Better to omit than to pad.** Per-section caps are caps, not quotas. Empty Shipped is fine. Empty Concerns is fine if there are genuinely no live concerns. Don't invent items to fill slots.
3. **Ask the user when in doubt.** Carried-forward concern with no fresh signal? Deploy-status item where production state is unclear? Cross-team dependency you can't verify? Stop and ask one short question rather than ship a guess.
4. **No engineering plumbing in management copy.** No ticket numbers, no PR numbers, no class/service names, no endpoint paths, no branch names (`main`, `release/**`, `story/**`, `develop/**`, `feat/**`, `hotfix/**`), no "merged into X", no "promoted to Y", no "code review", no "PR open". Branch state is the inspector's job (Phase B gates below), not report content. Translate to management outcomes.
5. **Mocks and stubs are part of the status.** A merged PR built against a stubbed dependency is not "feature-complete". Surface the mock state explicitly in the milestone description.
6. **Neutral, non-blaming tone.** Don't lead with negative framing ("missed target", "demo slipped", "behind schedule"). Re-baseline forward: "demo targeted for Fri May 8". For cross-team framing, follow `rules/universal/cross-team-framing.md`, don't name peer teams as the cause of a gap or blocker.

## Cross-cutting rules already covered elsewhere

`rules/universal/document-formatting.md` defines: separators, em dashes (none in body except a standardised title header that already uses them), repetition, filler vocabulary. Read it before drafting. This skill does not duplicate those rules.

`rules/universal/cross-team-framing.md` defines how to describe cross-team situations without naming peer teams as blockers. Apply throughout.

## Prerequisites

- `.claude/skill.config` exists with `paths.tasks_root` and `paths.docs_root`.
- `TasksSummary/<Platform>.md` exists for every platform the project uses.
- A `ProjectState.md` or equivalent at `{docs_root}/ProjectStatus/ProjectState.md` (path is conventional but the skill respects `config_hints.json → weekly_report.project_state_path` if set).
- A previous weekly report exists in `{docs_root}/ProjectStatus/SharedWeeklyReports/` (or the configured `weekly_report.reports_folder` path).

If any of these are missing, the skill says exactly which file is missing and stops, it does not invent the missing source.

## Workflow

### Step 1: Resolve paths and audience

```bash
tasks_root=$(jq -r '.paths.tasks_root' .claude/skill.config)
docs_root=$(jq -r '.paths.docs_root' .claude/skill.config)
coding_tasks_root=$(dirname "$tasks_root")

# Shared task tracking paths
task_summary_folder="$coding_tasks_root/TasksSummary"
weekly_summaries_folder="$coding_tasks_root/WeeklySummaries"

# Per-project weekly-report config (with defaults)
audience=$(jq -r '.weekly_report.audience // "Engineering Lead and PM"' .claude/config_hints.json)
reports_folder=$(jq -r '.weekly_report.reports_folder // "ProjectStatus/SharedWeeklyReports"' .claude/config_hints.json)
weekly_reports_folder="$docs_root/$reports_folder"
project_state=$(jq -r '.weekly_report.project_state_path // "ProjectStatus/ProjectState.md"' .claude/config_hints.json)
project_state_path="$docs_root/$project_state"

# Optional context sources (skip if not configured)
meetings_summaries=$(jq -r '.weekly_report.meetings_path // ""' .claude/config_hints.json)
compiled_state=$(jq -r '.weekly_report.compiled_discussion_path // ""' .claude/config_hints.json)
```

### Step 2: Determine the week to report on

- Friday-Sunday: report on the week just ended (last Friday).
- Monday-Thursday: report on the previous week (last Friday).

### Step 3: Read sources (in this order)

This step is the difference between a defensible report and a fabricated one. Don't shortcut it.

**Strategic context:**

1. `project_state_path`, current phase, blackout status, exceptions, key dependencies, roadmap.
2. `meetings_summaries` (if configured), entries dated within the report week. Read **both** decisions and open TODOs. Open TODOs mean the matter is still ongoing.
3. `compiled_state` (if configured), entries dated within the report week.
4. **The previous two weekly reports**, list every In progress and Next item. Each becomes a row that must be accounted for in this week's classification (carried forward, deprioritized with reason, completed, paused with explicit status, never silently dropped).

**Priority when sources conflict:** ProjectState > CompiledDiscussionState > Meetings > previous reports. ProjectState is authoritative.

**Task-level evidence (this is where most fabrications start):**

5. `TasksSummary/<Platform>.md` for every platform, rows for the report week AND the prior week.
6. **For every task referenced this week, open its task folder** at `{coding_tasks_root}/<Platform>/{OnGoingTasks|DoneTasks}/<task-name>/` and read:
   - `executive_summary.md` (if present), 2-3 line digest of what was supposed to land
   - `ticket.md`, the actual change set, the PR link, what's mocked vs real
   - `prompt-understanding.md`, what the developer flagged as deferred, mocked, blocked
   - `execution_plan.md`, mocking strategy, follow-up tickets
   - `acceptance_criteria.json` (if present), `passes:true/false` rows tell you exactly what's done
   - Grep for: `mock`, `mocked`, `stub`, `stubbed`, `fake`, `wiremock`, `tunnelmole`, `placeholder`, `TODO`, `follow-up`, `pending`, `not yet built`, `disabled on staging`, `feature flag`. Hits go straight into Phase A as evidence rows.
7. The corresponding weekly summary file at `WeeklySummaries/Week-Ending-YYYY-MM-DD/`. Too compressed to be the only source for any claim, it points at the real source (task folder).

**External delivery state:**

8. `gh pr list --search "<ticket> in:title" --state all` for each ticket referenced. Capture `mergedAt` AND `baseRefName`. **If `baseRefName` ≠ `main`, the work is not Shipped or Development Done regardless of how complete it looks.**
9. `gh pr view <num> --json baseRefName` for each PR you intend to mention. Use `github_repos.<platform>` from `config_hints.json` to know which repo to query per task.

### Step 4: Verify task-tracking completeness

For each platform listed in `config_hints.json → platforms`:

```bash
ls "$coding_tasks_root/<Platform>/OnGoingTasks"
ls "$coding_tasks_root/<Platform>/DoneTasks"
```

Compare folder names against `TasksSummary/<Platform>.md` rows. For each task in folders but missing from the summary, add a row using the task's `execution_plan.md` for title, `git config user.email` for owner, the earliest file mtime for start date, and the appropriate week-ending Friday.

**Better:** run `ar-taskflow-progress-fixer` first if you suspect drift, it does this check (and more) systematically.

### Step 5: Phase A, Evidence table

Build a scratch table of raw facts. No prose, no synthesis, no adjectives.

| Source type | Source (cite) | Fact (verbatim or near-verbatim) |
|---|---|---|
| PR merged | `gh pr view <num>` + baseRefName | e.g., "PROJ-555 merged 2026-04-30, base=`PROJ-492--Story--Product-verification-and-checkout`" |
| Mock/stub state | task `ticket.md` / `prompt-understanding.md` line | e.g., "PROJ-555 ticket: `/confirm` and `/v2/details` mocked until PROJ-559" |
| Prod deploy | release tag / deploy log / user confirmation | e.g., "Waitlist live in prod per user confirmation 2026-04-29", write `UNKNOWN` if no source |
| Meeting decision | meetings summary file | e.g., "Apr 13 Slack (Faical): meals/seats/baggage deferred from MVP. TODOs: none." |
| Meeting open TODO | meetings summary file | e.g., "Apr 10 meeting TODO: Monday follow-up on checkout flow, not yet closed" |
| ProjectState change | ProjectState.md section + line | e.g., "Apr 13: waitlist go-live added as #1 priority" |
| Prior-report carry | previous 2 reports, In progress/Next items | e.g., "24 Apr report: Bundle pricing in In progress" |
| Blocker fresh signal | this-week ticket/Slack/user confirmation | e.g., "DataDog env still not configured per Apr 13 user confirm", UNKNOWN otherwise |
| Acceptance gate state | `acceptance_criteria.json` for the task | e.g., "PROJ-555: 3/5 passes=true, AC-4 still failing" |

**Rule:** If a row would require a source you didn't actually read this turn, drop the row.

### Step 6: Phase B, Classify each row

Single decision matrix. No exceptions.

| Evidence shape | Destination |
|---|---|
| PR merged to `main` + deploy confirmed + user-visible | **Shipped** |
| PR merged to `main` + deploy not yet confirmed (pre-launch / blackout) | **Development Done** |
| PR merged to `main` + internal scaffolding only (framework upgrades, docs, internal renames, test harness) | **In progress** as a milestone under the parent initiative, not its own bullet |
| PR merged to a non-main branch (any name other than `main`) | **In progress**, period. Independent of how complete the underlying work is. |
| PR open, in review, WIP | **In progress** |
| Meeting held, TODOs still open | **In progress** with the open TODO named in the milestone |
| Meeting held, specific artifact delivered (signed doc, code, config, credentials) | **In progress** or **Shipped** depending on the artifact |
| Prior-report blocker, specific ask delivered | **Δ** as `addressed` (not `resolved`) |
| Prior-report blocker, fresh this-week signal it is still live | **Concerns / Blockers** with the fresh detail |
| Prior-report blocker, no this-week signal | **DROP.** Don't carry forward, don't re-tone. If uncertain, ask the user. |
| Prior-report In progress with no activity | **In progress** with explicit "no activity this week, blocked on X" or "iteration ongoing, no merges this week". Do not silently drop. |
| Prior-report Next not started | **Next** again with updated context, OR explicitly deprioritized with a reason |
| New priority announced this week | **Δ** headline + In progress/Next detail |
| Planning task, architecture completed this week | **In progress**: "Architecture plan completed for X, N tasks sequenced" |
| Planning task, child prompts in execution | **In progress**: "M of N tasks done for X" |
| Planning task, never goes to Shipped (planning produces specs, not deploys) | n/a |

**Mock state is a milestone modifier, not a classification change.** A merged-to-main PR built against stubs is still Development Done in classification, but the milestone description must spell out which calls are real and which are mocked, and name the follow-up that switches them. Same for tunnelled URLs, feature-flagged disabled paths, and "disabled on staging" code.

**Exception items: ask the user.** ProjectState may explicitly call out items as exceptions (e.g., a single page live during a launch-blackout). For those, the default deploy assumption flips. Don't guess in either direction, ask "is X live in production this week?" and classify on the answer. If you can't ask, classify as In progress with `deploy status not confirmed` and surface the uncertainty in your turn-summary.

### Step 7: Phase C, Write prose

**Open the two most recent weekly reports first and read their bullets.** Their cadence is the target for voice consistency. Older reports of this series typically have tighter, more human voice; recent ones may have drifted into AI-style compound prose. Match the older voice.

**Format per section:**

- **Status line**, `🔴/🟡/🟢 (one-line why) | ETA: <date> | Δ since last week: <terse, headlines only>`. No parenthetical sources.
  - **Δ must thread last week's items into this week's narrative.** A reader of last week's report should be able to read this week's Δ and see what happened to each prior thread. Use phrases like "picks up last week's X", "Y matured this week", "Z delivered", "W stays at the skeleton stage, no further pieces this week", "new this week:". Do not introduce major initiatives without saying when they kicked off; do not silently drop prior initiatives. The Δ is where continuity is made visible.
- **SLOs**, fixed line (project-specific format; copy from prior reports).
- **Shipped (≤3)**, `**Initiative**, what shipped (date) | Impact: <one line, user/business outcome>`. If none: `No customer-facing production deploys this week. <reason>.`
- **Development Done (≤3)**, `**Initiative**, engineering complete and integrated (date) | awaiting <deploy/launch/cutover> | <one-line user-facing outcome that will land when it deploys>`. If none: `Nothing reached this stage this week.`
- **In progress (≤3)**, `**Initiative**, short status (date if relevant) | Milestone: <one line, user-facing> | ETA: <date or "in active build">`.
- **Concerns / Blockers (≤3)**, `🟡/🔴 **Risk** | Impact: <line> | Mitigation: <line> | ETA to unblock: <date>`. If status colour is 🟡 or 🔴, this section must not be empty.
- **Next (≤3, next 1-2 weeks)**, `<Milestone> | ETA: <date> | Success: <one-line user/business outcome>`.

**Voice rules** (all flow from `rules/universal/document-formatting.md`):

- **One idea per sentence.** Three-or-more comma/and clauses → split into separate sentences or convert to a list. Long compound sentences are an AI tell.
- **Active voice.** "We finished X" not "X was finished." "Users see Y" not "Y was rendered."
- **Lead with the user/business headline. Drop housekeeping.** Test coverage, refactors, framework upgrades, internal renames, data-shape cleanups do NOT get their own clause, even if they were real PRs. They count toward the parent initiative; they don't get a sentence.
- **Editorial hierarchy: 1 headline + ≤2 supporting details per bullet.** If a bullet runs more than 4 lines on screen, cut by half. Cut detail, not headline.
- **Vary sentence length.** Short. Then a longer one with context. Short again.
- **Cut filler aggressively.** `essentially`, `broadly`, `across the board`, `rolls into`, `in active build for`, `the whole effort`, `all of this is`, `all of which`, strip them all.
- **No engineering jargon in body** for executive audience. Translate every implementation noun to "what does the manager get from this".
- **Dates only with sources.** Specific dates only if an evidence row contains that date. Otherwise: `near-term`, `in active build`, `TBD pending X`, `~early June`.
- **People only when sourced.** Name a person only if the evidence table has a source confirming that specific person did/owns the thing. Otherwise: "product leadership", "the team".

### Step 8: Self-review (before presenting)

Run these in order. Any failure → revise, do not present.

1. **Source pointer.** Every concrete claim in the report points at a specific row in the Phase A evidence table. Concerns/Blockers especially: each must cite a fresh this-week source. No source, drop the bullet.
2. **Mock-state truthfulness.** Any milestone using strong words (`feature-complete`, `user-ready`, `pipeline in place`, `done`), re-confirm against the task folder's `ticket.md` and `prompt-understanding.md`. If the work depends on stubs, that fact appears in the bullet.
3. **Branch reality.** Every Shipped or Development Done bullet, the underlying PR's `baseRefName` is `main`. Anything else: move to In progress.
4. **Carried-forward integrity.** Every item in In progress / Next from the previous two reports is accounted for: shipped, development done, in progress, completed-and-now-shipped, deprioritized-with-reason, or paused-with-status. None silently dropped.
5. **Plumbing scan.** Grep the body for: `main`, `master`, `trunk`, `release/`, `story/`, `develop/`, `feat/`, `feature/`, `hotfix/`, `branch`, `merged into`, `promoted`, `repo`, `repository`, `code review`, `PR`, `pull request`, ticket numbers (`[A-Z]+-\d+`), CamelCase identifiers, endpoint paths (`/v1/`, `/api/`), em dashes in body. Each hit means the AI's internal check is leaking; rewrite to management language.
6. **Robot-prose scan.** For each bullet:
   - Sentences with 3+ comma/and clauses → split.
   - Passive verbs (`was`, `were`, `has been`, `have been`, `is being`, `landed`, `merged`) → rewrite or drop.
   - Filler words → cut.
   - Implementation-detail-only clauses (test coverage, refactor, framework upgrade) → drop the clause.
   - Bullets longer than 4 lines → halve, keeping the headline.
7. **Voice match.** Read one bullet from a prior report aloud, then the same-section bullet from this draft aloud. If the cadence and density don't match, the draft is still wrong.

### Step 9: Save the report

Path: `{weekly_reports_folder}/{day} {Month} {Year}.md`, e.g., `30 Jan 2026.md`. Naming convention is configurable via `weekly_report.report_filename_pattern` in `config_hints.json` if the team uses a different format.

After saving, check whether `ProjectState.md` needs updating (a roadmap item completed, a blocker resolved, a status changed). Update it in the same turn.

### Step 10: Inform the user

```
✅ Weekly report generated: {file_path}

Tasks verified:
{per platform: X ongoing, Y done, Z tracked in TasksSummary}

Added {N} missing task rows to TasksSummary.

Completed this week: {total} tasks ({breakdown per platform}).
```

Surface any uncertainties from the self-review (e.g., "deploy status of X not re-confirmed this turn, flag if anything has changed").

## Configuration reference

Per-project audience and paths via `config_hints.json`:

```json
{
  "weekly_report": {
    "audience": "CEO and CTO",
    "reports_folder": "ProjectStatus/SharedWeeklyReports",
    "project_state_path": "ProjectStatus/ProjectState.md",
    "meetings_path": "Context/OnGoingKnowledgeDiscussionSummary/Meetings_Summaries.md",
    "compiled_discussion_path": "Context/OnGoingKnowledgeDiscussionSummary/CompiledDiscussionState.md",
    "report_filename_pattern": "{day} {Month} {Year}.md"
  }
}
```

All fields optional. Sensible defaults are used when absent (audience defaults to `"Engineering Lead and PM"`, paths default to common conventions).

## Error handling

- `skill.config` missing → `❌ Configuration missing. Run 'ar-init-skills' first.`
- No tasks completed in the week → `⚠️ No tasks completed in week ending {date}. Report will show only in-progress work and blockers.`
- Weekly summary file missing for a completed task → create it from the task folder's `execution-summary.md`.
- Required source file missing (project_state_path, etc.) → tell the user which file is missing and stop. Do not invent content.

## Worked example bullets (voice anchor)

Three In progress bullets in the target voice, drawn from real-world projects:

- **Product integration**, pipeline in place, ticket-issue still mocked | Milestone: fare re-validation at checkout calls the real products API; checkout reference is created on the products side after payment; confirmation page shows the booked product. The final ticket-issue and ticket-status calls are mocked until the upstream team delivers the confirmation endpoint. | ETA: real wiring before the June launch.
- **Timeline View**, replaces the linear checkout wizard | Milestone: 9 architecture pieces feature-complete. Users see one editable timeline (document, products, item, services) with a docked summary that prices the trip live. Edit pencils open in-place modals; legacy wizard removed. | ETA: ships with the June launch.
- **Bundles + pricing** | Milestone: bundle cards now show indicative prices, computed from a worldwide routes dataset combined with a rates feed. Homepage hero search filters the bundles list. | ETA: ships with the June launch.

Each is one headline, one milestone with at most two facts, one ETA. No git terms. No engineering nouns. No housekeeping. Match this density when writing.
