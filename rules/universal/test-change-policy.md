---
alwaysApply: true
---
# Test Change Policy

**Tests change only when they *must*.** The existing, still-green test suite is the regression oracle, for a change that is not supposed to alter behaviour, the unchanged suite passing *is the proof* that behaviour was preserved. Editing those tests to make them pass destroys that evidence, pollutes the diff, hides real regressions, and trains a "make it green by editing the test" reflex.

## Change taxonomy

Every code change is one of three classes. Capture it as `Change Class` in `prompt-understanding.md` / `execution_plan.md`.

| Change Class | What it is | Test action |
|---|---|---|
| **BEHAVIOR_PRESERVING** | Refactor, perf tuning, extract-method, inline, rename a private member, nothing crosses a public method boundary or changes an API / DB / observable contract. | **Leave existing tests untouched. Run them as-is.** Green = success. Add tests only for genuinely new internal seams, never to "cover" the refactor. |
| **CONTRACT_CHANGING** | A public/observable contract changed: signature, return type, thrown exceptions, API shape, status codes, persisted schema. | Update **only** the tests the contract delta actually invalidates. Each modified test hunk must map to a named contract delta. |
| **FEATURE** | New behaviour added. | Add new coverage for the new behaviour. Leave unrelated existing tests untouched. |

## Diagnosis fork (an existing test goes red during BEHAVIOR_PRESERVING work)

Do **not** default to editing the test. Classify the failure:

1. **Real regression** → the change altered behaviour it shouldn't have. **Fix the code, not the test.**
2. **Over-coupled / brittle test** → it asserted on a private implementation detail you legitimately changed. **STOP and surface it** to the user with the specific coupling. Only adjust the test after the user agrees it tests an implementation detail, and record it in the `execution_plan.md` Change Log.

"Edit the test until it's green" is never the default branch.

## Verification (regression oracle)

For BEHAVIOR_PRESERVING work, verify the **original, pre-edit** tests pass against the new code. This only holds if the run includes opt-in / tagged integration suites, a default test task that skips them can report "behaviour preserved" falsely. Use the project's `verify.full_command` (or run the documented integration task) so suite selection is complete. See the verify-green step in `ar-taskflow` Phase 4g.

## What reviewers enforce

A diff that modifies or weakens test files **without** a corresponding contract change (or with the only effect being to make a previously-failing assertion pass) is a finding, see the "unjustified/weakened test edit" criterion in `code-review.md`.
