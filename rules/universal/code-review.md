---
alwaysApply: false
---
# Code Review Standards

Shared knowledge base for all code review workflows. This file defines **what to check** - skills (`ar-taskflow-review`, `a_sk_l_review_pr`) define **how to drive** the review.

## Review Agent

All reviews are performed by the project-specific code reviewer agent (e.g., `.claude/agents/{project}-code-reviewer/AGENT.md`), or the generic `a_sag_code_reviewer` agent if no project-specific one exists. The agent reads this file and the rule files selected by the invoking skill.

## Review Entry Points

| Skill | When to Use |
|-------|-------------|
| `ar-taskflow-review` | During ar-taskflow workflow - after code implementation, before PR |
| `a_sk_l_review_pr` | Standalone - review any PR by number or URL |

Both skills generate a diff, load these rules, and delegate to the same agent.

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

### Test Scope
**Reference**: `test-scope-policy.md`

- **Implementation-coupled / framework-tautology test:** a test that asserts an internal mechanism or a framework/third-party guarantee instead of the observable contract. Flag a mocked collaborator's call used as a proxy for correctness (e.g. asserting a persistence write happened, or call ordering on a mock), against a mock this only proves the mock ran. → **WARNING** (BLOCKING when it is the only assertion standing in for a real persisted-state or side-effect guarantee that an integration test against the real datastore should cover).
- **Allowed:** interaction assertions where the collaboration IS the contract and is not otherwise visible (queue/stream publish, external notification/API call, exactly-once/idempotency). Do not flag these.

## Severity Criteria

Use these criteria to determine how severe an issue is. The invoking skill defines the exact labels and output format.

### Must block merge
- N+1 queries in loops (will multiply with scale)
- Transaction holding connection during external call
- Schema change without migration
- Wrong module placement
- Breaking API change without compatibility
- Entity mutations that are never persisted

### Should review, may not block
- Method >30 lines (likely mixed concerns)
- `noRollbackFor` usage (often hides external ops)
- Method re-querying data the caller already holds
- Missing batch methods in repository
- Test assertions weakened/removed on a behaviour-preserving change without a contract delta (block if it masks a real regression)
- Test asserts an internal mechanism or framework guarantee (mock-call proxy) instead of the observable contract (block if it is the only stand-in for a real persisted-state/side-effect guarantee)

### Does not block
- Style preferences beyond what linters enforce
- Missing Javadoc on non-public method
- Performance optimization that doesn't affect correctness
- Method slightly over 30 lines

**Output format**: Defined by the invoking skill (`a_sk_l_review_pr` or `ar-taskflow-review`), not this file. This file defines **what to check and how severe it is**.
