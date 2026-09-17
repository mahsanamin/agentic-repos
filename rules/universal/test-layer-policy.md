---
alwaysApply: true
---
# Test Layer Policy

**A new test runs at the cheapest layer that can still fail for the reason the test exists**, a rung higher is slower, flakier, and tells you nothing more. This governs **WHICH LAYER** a test runs at; `test-scope-policy.md` governs **WHAT** it asserts and `test-change-policy.md` governs **WHEN** an existing one may change. The cheapest thing an author can do is copy the neighbouring test, so the layer is a decision to make, not one to inherit.

## The rungs

| Rung | Context | Belongs here |
|---|---|---|
| **1** | No framework context, the subject constructed directly, its collaborators substituted. | Logic: mapping, calculation, branching, validation, error translation. **The default.** |
| **2** | Sliced framework context, the framework loads one layer and substitutes what sits behind it; for an HTTP API, the web layer. | Behaviour only that layer can fail: routing, request binding and deserialisation, status codes, response serialisation, exception-to-status mapping. |
| **3** | Real-database suite, the same engine and version as production. | Anything a real database can contradict: query semantics, type coercion, null handling, constraints, migrations, transaction and isolation behaviour, persisted state. |
| **4** | Full application context, the whole application wired up. | **Only when the wiring is the subject:** startup, the dependency graph, configuration binding, a filter or interceptor chain end to end. |

Rung 4 is on this ladder, not off it, reachable, never by default. An **in-memory database standing in for the real one is not rung 3 at all**: it is a substitute engine, so it carries none of rung 3's authority. What evidence it can support is the installed database rules' call, not this rule's.

## Rules

- **Controller behaviour is rung 2**, where the stack has an HTTP layer. Booting the application to assert a status code exercises the framework's own routing, which the framework already tests.
- **Say what forced it up.** A test above rung 1 states in one line what forced it there, where the next author will read it. An unexplained rung gets copied.

Persistence and side-effect claims arrive here from `test-scope-policy.md`: when it rules that a mocked collaborator's call cannot stand in for real persisted state, rung 3 is where that assertion goes.

## A check that cannot fail is not a check

**A check that cannot distinguish "passed" from "never ran" is not a gate, and a replacement that cannot fail is not a replacement.** This holds at both ends of the ladder. It is why a test's rung is chosen by what has to be able to fail, and why moving a test to a cheaper rung is only safe once something still fails for the reason the original existed.

So a deletion that names another test as its cover is not finished on the naming. Break the production line the deleted test pinned, run the named replacement, and require it to go red; then restore and confirm green. A replacement in the right module, at the right rung, asserting the right constraint can still never touch the deleted path.

## What reviewers enforce

A new test on a full application context, or a new repository test on an in-memory database, is a finding that names the rung it belongs on, see the "wrong test layer" criterion in `code-review.md`. A deleted test whose named replacement was never shown to fail is a finding too, see "unproved replacement claim".
