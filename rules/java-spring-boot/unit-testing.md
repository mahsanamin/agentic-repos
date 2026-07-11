---
triggers: ["@Test", "assertThat", "MockitoExtension", "@SpringBootTest", "@InjectMocks", "jacoco", "coverage"]
---
# Unit Testing

Unit tests are **mandatory** for all new and changed code, written in the same PR as the code, never as a follow-up. SonarQube enforces a coverage threshold **on new code** (commonly 80%) and blocks the PR if it isn't met; aim for 90%+ to keep buffer.

This rule covers *writing* tests for new/changed code. For *when an existing test may be modified* (and when a failing test is the regression oracle, not something to edit), see `test-change-policy.md`. For *what a test should assert* (observable contract over mock-call/implementation/framework guarantees, e.g. don't `verify(repo).save(...)` as a proxy for correctness), see `test-scope-policy.md`. For assertion idioms and dead-code findings, see `sonarqube-compliance.md`.

## When to Write Tests

Every PR that adds or modifies Java source in `module-server` or `module-http` must include corresponding unit tests. The test commit may be separate from the code commit, but both ship in the same PR.

## What to Test by Layer

### Mappers (pure functions, highest ROI)
- Null input returns null (null-guard path)
- Happy path with all fields populated
- Conditional branches (e.g. `next != null` vs `null`)

### Services (mock dependencies)
- Happy path
- Every exception path (`orElseThrow`, thrown business exceptions, …)
- Branch conditions (null checks, state checks, empty collections)
- Side effects verified (`verify(repo).save(...)`, counter increments)

Use `@ExtendWith(MockitoExtension.class)` + `@Mock` + `@InjectMocks`; mock repositories and dependencies; verify interactions with `verify()`.

### Presenters (pure functions)
- Each `present*` method returns the correct HTTP status
- Response body contains the expected fields
- Null/absent optional fields handled

### Controllers (mock services)
- Each endpoint returns the correct status for success and error paths
- Exception-to-status mapping
- **Construct the controller directly with mocked dependencies, no Spring context.** Controller tests exercise the real `BaseControllerV2.handleRequest()` flow without `@SpringBootTest`:

```java
controller = new FeatureController(mockValidator, mockService);
var response = controller.create(kongAuth, request);
assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
```

(Full `@SpringBootTest` + `MockMvc` integration tests still belong with the controller per `api-conventions.md`; the direct-construction unit test is the fast, coverage-bearing complement.)

## What NOT to Unit Test

- **Lombok-generated code**, POJOs with `@Getter`/`@Builder` only, no custom logic
- **Repository interfaces**, JPA-derived queries are covered by `@DataJpaTest` / integration tests
- **Framework boilerplate**, Spring annotations, configuration classes
- **Cross-module flows**, these belong in integration tests, not unit tests

## Time-Dependent Tests

**Never hardcode an absolute date/timestamp in a test whose assertion depends on the value being in the past or future relative to "now".** A literal future date passes until that calendar date arrives, then fails on an unrelated branch, a time bomb that breaks `main` for whoever happens to build that day.

```java
// Bad, passes until 2026-06-01, then the "future date" branch stops firing
LocalDate serviceDate = LocalDate.of(2026, 6, 1);

// Good, always future relative to runtime
LocalDate serviceDate = LocalDate.now().plusDays(30);

// Good, for deterministic assertions on "now", inject a fixed Clock
Clock clock = Clock.fixed(Instant.parse("2025-01-01T00:00:00Z"), ZoneOffset.UTC);
```

Derive relative dates with `LocalDate.now().plusDays(...)` / `minusDays(...)`, or inject a fixed `Clock` into the code under test so "now" is controllable. The same applies to assertions that compare against `Instant.now()` / `LocalDateTime.now()`.

## Coverage Verification

Before pushing, confirm every new mapper has null-input + happy-path tests; every new/changed service, presenter, and controller method has happy-path and error-path tests; the project's test command passes with caches bypassed (see `commands.md`, Gradle caches test results, so force a rerun); and no unused imports remain in test files. To close coverage gaps mechanically against the report, use the `a_sk_sonarqube_coverage` skill.

### Reading the JaCoCo report

The coverage command must bypass Gradle's cache (`--rerun-tasks`) or it serves stale results that don't reflect new tests:

```bash
./gradlew testCodeCoverageReport --rerun-tasks --no-daemon   # aggregated report
./gradlew :<module>:test :<module>:jacocoTestReport --rerun-tasks --no-daemon   # a module not in jacocoAggregation
```

Report locations: aggregated → `build/reports/jacoco/testCodeCoverageReport/testCodeCoverageReport.xml`; per-module → `<module>/build/reports/jacoco/test/jacocoTestReport.xml`. Each `<sourcefile>` has per-line `<line nr ci mi cb mb/>` attributes (`ci`/`mi` = covered/missed instructions, `cb`/`mb` = covered/missed branches). Classify a line as: **not covered** when `mi>0 && ci==0`; **partially covered** when `mi>0 && ci>0`; **branch gap** when `mb>0`; **non-executable** (skip) when `mi==0 && ci==0`. A class can appear in multiple `<package>` blocks when the aggregated report combines modules, match by source-file name **and** package path.
