---
alwaysApply: true
---
# Test Scope Policy

**Tests assert the observable contract, not the implementation or the framework.** This governs **WHAT** a test asserts; `test-change-policy.md` governs **WHEN** a test may change. Both apply to tests written in the `ar-taskflow` Code phase and to what the reviewer agents enforce.

## What to assert

1. **Prefer state / return-value assertions over interaction (mock-call) assertions.** Assert the return value, the resulting persisted state, or the emitted side effect, not the inner steps that produced it.
2. **Never use a mocked collaborator's call as a proxy for correctness.** Asserting that a mocked collaborator's method ran (a persistence write, a commit, or the order of calls on a mock) only proves the mock ran. Persistence, transaction/commit mechanics, and dependency wiring are framework or library guarantees, not your contract. If the real persistence behaviour is what's under test, write an integration test against the real datastore that asserts observable state.
3. **Behaviour-preserving inner swaps must produce ZERO test changes.** If a refactor that preserves behaviour breaks a test with no contract delta, the test was over-coupled, rewrite it at the contract seam (the public method's outcome), don't patch it to stay green. (This is the same coupling `test-change-policy.md`'s diagnosis fork sends you to STOP on.)

## When interaction assertions ARE correct

Do not over-correct into "never mock." Interaction / mock verification is legitimate and required **when the collaboration itself IS the observable contract and is not otherwise visible**: publishing a queue/stream event, sending an external notification (CRM/email), calling an external API, and exactly-once / idempotency guarantees. Only delete or rewrite an interaction test when the verified call is an internal mechanism, not a contract.

## What reviewers enforce

A test that asserts an internal mechanism or a framework/third-party guarantee (rather than the observable contract) is a finding, see the "implementation-coupled / framework-tautology test" criterion in `code-review.md`.
