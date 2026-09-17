---
alwaysApply: false
---
# Code Review Standards

Shared knowledge base for all code review workflows. This file defines **what to check** - skills (`ar-taskflow-review`, `a_sk_review_pr`) define **how to drive** the review.

## Review Agent

All reviews are performed by the project-specific code reviewer agent (e.g., `.claude/agents/{project}-code-reviewer/AGENT.md`), or the generic `a_sag_code_reviewer` agent if no project-specific one exists. The agent reads this file and the rule files selected by the invoking skill.

## Review Entry Points

| Skill | When to Use |
|-------|-------------|
| `ar-taskflow-review` | During ar-taskflow workflow - after code implementation, before PR |
| `a_sk_review_pr` | Standalone - review any PR by number or URL |

Both skills generate a diff, load these rules, and delegate to the same agent.

## Round Budget for Agent-to-Agent Exchanges

An exchange where an automated reviewer posts findings and an automated fixer replies has a **round budget**. A round is one review plus one fix commit answering it. The default is **three rounds**, configurable per project as `review.max_agent_rounds` in `config_hints.json`. Three rounds of findings may be posted and fixed; the review after the third is the summary.

**Rounds are counted from markers, not from prose or from who posted.** Every review an automated reviewer submits carries `<!-- ar-review round={n} -->` in its review body, and every reply an automated fixer posts ends with `<!-- ar-fix round={n} commit={sha} -->`. Each side reads the markers off the PR, so a fresh session with no memory of earlier runs computes the same round; an approval or a human's review does not count; a reviewer that fell back to posting comments one by one does not count once per comment; a round that needed two fix commits is still one round. A review or reply without a marker predates this rule and is counted by the older signals (a non-approval review by the same login, a reply starting `Fixed in {sha}`) as a fallback.

Past the budget both sides stop and hand the decision to a human:

| Side | Skill | What it does instead of another round |
|-------|-------|----------------------------------------|
| Fixer | `ar-taskflow-fix-comments` Phase 6 | Stops with `ROUND CAP` rather than re-entering Phase 1 |
| Reviewer | `ar-global-pr-reviewer` Phase 7, and any standalone PR-review skill posting these markers | Posts one summary in the review body naming what recurred, rather than another finding, and posts nothing at all when its own summary is already the newest review and no commit has landed since |

**A class is a shape, not a file.** Two findings are the same class when they share a shape ("X is missing from list Y", "the number in A disagrees with the number in B", "case Z is not handled", "the same function or block") and the same underlying list, value or heuristic, whichever files they sit in. A count restated in four documents spans files by nature, and requiring the same file made every file's instance a fresh finding. Once a class has two findings on a PR, every further instance is reported as ONE Approach finding; three or more instances arriving in a single review are answered by ONE structural fix or ONE reply, never by one fix each.

**Neither side may extend the budget on its own.** Two things that look like permission to continue are not:

- **Green CI.** Every round of this kind of exchange is green, because each fix is small and correct. A passing run says nothing about whether the exchange should continue.
- **Agreement between the two agents.** A fixer that accepts every finding and a fixer that accepts none reach the same round count. Agreement is not evidence the exchange is converging, and per-round success on both sides is exactly what an exchange with no stopping rule looks like.

Reaching the budget is a signal about the PR's **shape**, not about whether the findings were right. Findings can be individually correct and still not close: scope that grew after the first review, a hand-maintained number a command could print, or a list that models another system's runtime behaviour and therefore always has one more case. A fourth fix round repairs none of those.

The budget binds automated exchanges only. A human reviewer's findings are never counted against it or capped by it.

## Review Criteria

### Architecture & Design
- Changes in correct module per `project-structure.md`
- Layer separation maintained (e.g., controller → service → repository)
- Dependency direction respected per project conventions
- Design patterns consistent with existing codebase
- Dependency injection follows project conventions

### Transaction Boundaries (CRITICAL)
**Reference**: `transaction-boundaries.md`

If `@Transactional` methods are in the diff, verify whether these issues actually exist:
- Calls to external APIs inside the transaction → **BLOCKING** (confirm the call is actually inside the boundary, not in a separate method)
- `Thread.sleep()` inside transaction → **BLOCKING**
- File I/O operations inside transaction → **BLOCKING**
- Queue/messaging operations inside transaction → **BLOCKING**
- Method >30 lines (likely mixed concerns) → **WARNING**
- `noRollbackFor` usage (often hides external ops) → **WARNING**

### Query Efficiency (CRITICAL)
**Reference**: `query-efficiency.md`

Verify whether these patterns actually occur in the changed code:
- `findAll()` when specific IDs are already known → **BLOCKING** (confirm the caller has the IDs)
- `.stream().filter()` after `findAll()` (app-level filtering) → **BLOCKING** (confirm a query-level filter is possible)
- `repository.find*()` inside `for`/`forEach`/`stream().map()` → **BLOCKING** (read the actual loop, don't guess from method name)
- `entity.getLazyCollection()` inside loop → **BLOCKING** (confirm the collection is lazy and the loop exists)
- Method re-querying data the caller already holds → **WARNING** (trace the actual caller to verify)
- Helper method accepts ID instead of entity/map (hidden query) → **WARNING**
- Same `findById(id)` called in multiple methods → **WARNING**
- Missing batch methods (`findByIdIn`) in repository → **WARNING**

### Database Migrations
**Reference**: `database-migrations.md`

- Entity/enum change MUST have corresponding migration file → **BLOCKING** if missing
- Migration naming follows project convention
- Uses safe DDL patterns (`IF NOT EXISTS`/`IF EXISTS`)
- Proper dependency ordering (FK target table created first)

### JPA Repositories
**Reference**: `jpa-repositories.md`

- Nullable parameters handled for DB compatibility
- Soft-delete queries include deleted-at check where applicable
- Prefer method-name queries over `@Query` for simple cases
- `@Modifying` annotation on DELETE/UPDATE queries
- Never access lazy collections outside transaction

### API Conventions
**Reference**: `api-conventions.md`

- Request flow follows project conventions
- URL patterns follow project standards
- Proper error handling and HTTP status codes
- When ALL query parameters are optional, require "at least one" validation

### Code Quality
**Reference**: `coding-conventions.md`

- Follows project formatting and naming standards
- No wildcard imports
- Project utility patterns applied correctly
- Constants only if used 3+ times

### Module Structure
**Reference**: `project-structure.md`

- New files in correct module per project structure
- Layer responsibilities respected

### Metrics & Observability
**Reference**: `metrics-collection.md` (if present)

- New features consider metrics collection
- Consistent naming conventions for events

### Critical Thinking
**Reference**: `critical-thinking.md`

- No breaking changes without migration path
- No anti-patterns (duplication, unnecessary complexity)
- Shared enums used correctly
- Question requests that violate established patterns

### Test Changes
**Reference**: `test-change-policy.md`

- **Unjustified / weakened test edit:** a diff that modifies, deletes, or relaxes existing test assertions **without** a corresponding public/observable contract change. For a BEHAVIOR_PRESERVING change the existing suite is the regression oracle, editing it to go green destroys the evidence that behaviour was preserved. Flag any modified test hunk that does not map to a named contract delta.
- Watch specifically for: loosened assertions (tightened→`anyOf`, exact→`contains`), deleted test cases, `@Disabled`/`@Ignore` added, expected values changed to match new output on a "refactor", mocks widened to swallow a new call.
- **Unproved replacement claim:** a deleted test whose PR names another test as its cover, with no red control shown → **BLOCKING**. The red control is: break the production line the deleted test pinned, run the named replacement, observe it fail, restore. A replacement can sit in the right module, at the right rung, asserting the right constraint and still never exercise the deleted path, reproducing the setup rather than covering the code. A reviewer cannot tell those apart by reading, so the evidence has to be in the PR: the line broken, the replacement run, and the failure observed. Absent it, treat the deletion as an unexplained coverage loss, not as a consolidation.

### Test Scope
**Reference**: `test-scope-policy.md`

- **Implementation-coupled / framework-tautology test:** a test that asserts an internal mechanism or a framework/third-party guarantee instead of the observable contract. Flag a mocked collaborator's call used as a proxy for correctness (e.g. asserting a persistence write happened, or call ordering on a mock), against a mock this only proves the mock ran. → **WARNING** (BLOCKING when it is the only assertion standing in for a real persisted-state or side-effect guarantee that an integration test against the real datastore should cover).
- **Allowed:** interaction assertions where the collaboration IS the contract and is not otherwise visible (queue/stream publish, external notification/API call, exactly-once/idempotency). Do not flag these.

### Test Layer
**Reference**: `test-layer-policy.md`

- **Wrong test layer, new full-application-context test:** a new test that boots the whole application when a lower rung would fail for the same reason → **BLOCKING**. Name the rung it belongs on: no framework context for logic; the sliced web-layer context for controller behaviour (routing, request binding, status codes, response serialisation, exception-to-status mapping); the real-database suite for anything a real database can contradict. A full application context is justified only when the wiring itself is the subject, startup, the dependency graph, configuration binding, a filter/interceptor chain end to end.
- **Wrong test layer, in-memory stand-in for the real database:** a new repository or query test whose only run is against an in-memory engine → **BLOCKING**. Name the real-database suite as the rung it belongs on. A pass on a substitute engine carries none of that rung's authority, and the installed database rules set what evidence the claim needs.
- **Unstated rung:** a new test above the no-framework-context rung with no one-line reason for the rung → **WARNING**. The next author copies the rung rather than the judgement.

### Documentation
**Reference**: `lean-docs.md`

Check any doc the diff touches, and any doc the diff makes stale:

- **Stale claim the diff created:** code changed and a doc still states the old behaviour, count, path, or version → **BLOCKING**. A wrong doc gets trusted.
- **Absence claim contradicted by the diff:** a doc says a feature is planned, disabled, or not implemented and this change implements it → **BLOCKING**.
- **Appended instead of cut:** a correct paragraph added beside the wrong one it replaces → **BLOCKING** (both now read as current).
- **Transcribed enumeration:** the diff adds an endpoint/env var/column/module to a list a doc hand-copies, instead of pointing at the source → **WARNING**.
- **Tombstone:** struck-through "resolved", "kept for reference", commented-out section → **WARNING**.
- **Change log in a doc:** "as of {date}", "previously X", migration narrative added to a doc rather than left to the commit → **WARNING**.
- **Rationale deleted:** a doc's only record of why a decision was made removed without relocating it → **BLOCKING**.
- **Broken doc identifier:** a doc path, numbered entry, or anchor referenced from source, config, CI, or a script renamed or renumbered → **BLOCKING**.

### Doc Comments
**Reference**: `lean-doc-comments.md`

A doc comment is a claim about the signature it sits on, so the diff that changes a signature is where it goes wrong:

- **A renamed, removed or reordered parameter whose doc comment was not updated → BLOCKING.** `@param` naming an argument the declaration does not take is a false claim next to working code, and nothing compiles it.
- **A doc comment copied from a sibling declaration and not adapted → BLOCKING.** It documents the wrong contract confidently. Check the siblings too; this defect arrives in groups.
- **A doc comment contradicted by the code or its annotations → BLOCKING.** When they disagree the code is right and the comment is the bug.
- **A new doc comment that only restates the signature → WARNING.** `@param id the id` costs a read and rots on its own.
- **History or a tombstone inside a doc comment → WARNING.** "previously returned", a commented-out signature.

The other half is size. A doc comment that is *correct* still costs a read every time the declaration is read, and correctness review alone does not catch that:

- **A ticket ID, commit hash, or author name in a doc comment → WARNING.** `git blame` carries it and the reader cannot look it up from the call site. If the ticket holds something the caller needs, the fix is to state that thing.
- **A step-by-step restatement of the method body → WARNING.** A numbered list walking through the code below is a second copy of it that rots separately.
- **A doc comment longer than the code it documents → WARNING, unless it names a why, trap, contract, side effect, or lifecycle.** Ask the question; a three-line method can hide a real trap.
- **A block whose declaration name already says everything → WARNING.** Most ORM derived queries need no comment at all.
- **Two doc-comment blocks stacked on one declaration → BLOCKING.** Only the nearest binds; the orphan is invisible to the reference generator and reads as documentation for whatever declaration it happens to sit above.
- **Rationale deleted rather than relocated → BLOCKING.** Cutting is the default, but the only record of a non-obvious decision must survive into whatever replaces it.

Where the language ships a doc-comment check (most do), prefer enabling it over relying on review attention: signature drift is the one documentation defect a build can catch.

### Inline Comments
**Reference**: `lean-inline-comments.md`

- **Commented-out code added or left in a touched block → BLOCKING.** `git` has it and nobody trusts it.
- **A workaround removed but its note kept, or the note removed but the workaround kept → BLOCKING.** Either half alone is worse than both or neither.
- **A directive comment (suppression, pragma, type hint, build marker) deleted as tidying → BLOCKING.** That is a behaviour change.
- **A marker with no owner, or naming closed work → WARNING.**
- **A comment restating the line it sits on → WARNING.**
- **A ticket ID in an inline comment → WARNING, unless it is inside a `TODO`/`FIXME`/`XXX` marker or names a tracker this team does not own.** Those two are required by the marker-has-an-owner finding above and by `lean-inline-comments.md`'s authority earner. Everywhere else `git blame` carries it and the reader cannot open the tracker from the call site. Strip the number, keep the sentence: deleting the whole line because it names a ticket is the more common and more costly error.
- **Design archaeology in a touched block → WARNING.** "It used to be X, then we found Y, so now it is Z" is three facts where one is load-bearing. Keep Z and why Z must stay.
- **The only record of a why deleted rather than moved → BLOCKING.** There is no signature to reconstruct it from.

### Dual-Harness Surfaces
**Reference**: `lean-docs.md`

Agentic Repos installs ONE copy of each skill and links it into every harness surface: `~/.claude/skills/` for Claude Code and `~/.agents/skills/` for Codex both point at `skills/` in the framework repo. There is no generated mirror to keep in step, and that is the point.

- **A diff that edits a path under `.agents/skills/**`, `.codex/agents/**`, or any other installed surface → BLOCKING.** Those are links or build products; the edit is lost on the next install. Change the framework `skills/` source.
- **A diff that adds a second copy of a skill or rule for a second harness → BLOCKING.** Two copies drift and nothing announces it. One source, linked twice.

## Severity Criteria

Use these criteria to determine how severe an issue is. The invoking skill defines the exact labels and output format.

### Must block merge
- N+1 queries in loops (will multiply with scale)
- Transaction holding connection during external call
- Schema change without migration
- Wrong module placement
- Breaking API change without compatibility
- Entity mutations that are never persisted
- Doc left stating the old behaviour after the diff changed it (a wrong doc gets trusted)
- A doc's only record of a decision's rationale deleted without relocating it
- A doc identifier referenced from source/config/CI renamed or renumbered
- An installed or linked harness surface edited directly instead of at its framework source
- A doc comment documenting a parameter the declaration does not have, or cloned from a sibling
- Commented-out code, or half of a workaround-plus-note pair, or a deleted directive comment
- A new test on a full application context, or a new repository test on an in-memory stand-in, where a lower rung would fail for the same reason (name the rung it belongs on)
- A deleted test whose named replacement has not been shown to fail for the reason the deleted one existed

### Should review, may not block
- Method >30 lines (likely mixed concerns)
- `noRollbackFor` usage (often hides external ops)
- Method re-querying data the caller already holds
- Missing batch methods in repository
- Test assertions weakened/removed on a behaviour-preserving change without a contract delta (block if it masks a real regression)
- Test asserts an internal mechanism or framework guarantee (mock-call proxy) instead of the observable contract (block if it is the only stand-in for a real persisted-state/side-effect guarantee)
- A new test above the no-framework-context rung with no stated reason for the rung
- Doc hand-transcribes a list the diff extends, instead of pointing at the source
- Tombstone or change-log prose added to a doc

### Does not block
- Style preferences beyond what linters enforce
- Missing Javadoc on non-public method
- Performance optimization that doesn't affect correctness
- Method slightly over 30 lines

**Output format**: Defined by the invoking skill (`a_sk_review_pr` or `ar-taskflow-review`), not this file. This file defines **what to check and how severe it is**.
