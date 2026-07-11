---
alwaysApply: true
---
# Coding Conventions (Java)

Unified coding standards for Java/Spring Boot development.

## ⚠️ CRITICAL: Transaction Boundaries

**Never put API calls, Thread.sleep(), or slow operations inside `@Transactional`.**

**See the commands.md rule file for complete TransactionTemplate patterns and examples.**

## AOP Annotation Placement

Spring's AOP annotations, `@Transactional`, `@Cacheable`, `@Async`, `@Retryable`, take effect **only** when the call goes through the Spring proxy. Two conditions must both hold, or the annotation silently does nothing:

1. **The method is `public`.** Annotations on `private`/`package-private`/`protected` methods are ignored, the proxy can't intercept them.
2. **The call comes from another bean.** A call to `this.method()` (self-invocation, including same-class helper calls) bypasses the proxy entirely, even if the method is public.

**Canonical fix, the helper pattern:** keep the AOP annotation on a `public` entry point, and put the same-class logic in an **unannotated package-private helper** that the public method calls. For splitting a transaction *within the same class*, use `TransactionTemplate` instead of a self-called `@Transactional` method (see `transaction-boundaries.md`).

```java
// ❌ WRONG, self-call to a private @Transactional method: proxy never sees it, no transaction
public void process(Integer id) {
  doWork(id);                 // plain this.doWork(), annotation ignored
}
@Transactional
private void doWork(Integer id) { ... }

// ✅ RIGHT, annotation on the public entry point; helper is plain
@Transactional
public void process(Integer id) {
  doWork(id);                 // runs inside the transaction opened by process()
}
void doWork(Integer id) { ... }   // package-private, no annotation
```

- Do **not** use `@Lazy` self-injection to re-enter the proxy, the helper pattern is the standard and makes the proxy boundary explicit.
- Never return a managed JPA entity from a `@Cacheable` method, a detached/lazy entity served from cache triggers `LazyInitializationException` or stale-state bugs. Cache a model/DTO instead.

## Formatting Essentials

- Line length: 120
- Indentation: 2 spaces; wraps +2 (no tabs)
- Encoding: UTF-8
- Braces: open same line; close on own line
- Control flow: always use braces; one statement per line
- switch: must include a default

## Imports

- No wildcards
- Static imports first; then non-static A-Z
- Blank line between static and non-static groups
- Use explicit imports; never use fully qualified names inline
- Remove unused imports; checkstyle will flag them

**NEVER use fully qualified class names (FQN) in code** - always add proper imports instead.

```java
// Bad
public MyController(com.example.app.server.services.ValidationService service) {}

// Good
import com.example.app.server.services.ValidationService;
public MyController(ValidationService service) {}
```

**Exception:** Only use FQN when there's a name conflict that cannot be resolved with imports.

## Wrapping & Operators

- Break long expressions; place the operator at the start of the wrapped line

## Annotations

- One annotation per line at the target's indent
- Variables may share a line for multiple annotations

## Whitespace

- Empty lines: no spaces/tabs
- Strip trailing whitespace
- Space around binary operators and after commas
- No space between method name and '('
- Space after control keywords: `if (x)` not `if(x)`
- No space before commas or semicolons
- End files with exactly one trailing newline

## Vertical Spacing

- One blank line between:
  - package and imports
  - import groups
  - class members (fields, constructors, methods)
- Use blank lines to group related code; avoid multiple consecutive blanks

## Constants and Literals

**RULE**: Only create constants if value is used **more than 2 times** (3+ occurrences).

- Do NOT create constants for values used 1-2 times - inline them directly
- Use meaningful names: UPPER_SNAKE_CASE
- Extract magic numbers and repeated strings only at 3+ occurrences

```java
// Bad - only used twice
private static final String STATUS_PENDING = "pending";
record.setStatus(STATUS_PENDING);
otherRecord.setStatus(STATUS_PENDING);

// Good - used 3+ times, extract constant
private static final String STATUS_PENDING = "pending";
record1.setStatus(STATUS_PENDING);
record2.setStatus(STATUS_PENDING);
record3.setStatus(STATUS_PENDING);
```

## Lombok Best Practices

- Use `@Data` for simple DTOs only; avoid on JPA entities - prefer `@Getter/@Setter`
- Constructor injection: `@RequiredArgsConstructor` on services with final fields
- Immutables: use `@Value`; combine with `@Builder` for flexible creation
- Builders: use `@Builder(setterPrefix="set")`; use `@Builder.Default` for defaulted fields
- Constructors: `@NoArgsConstructor(access = PROTECTED)` for JPA entities
- Utility classes: `@NoArgsConstructor(access = PRIVATE)` to prevent instantiation
- Inheritance builders: use `@SuperBuilder` on parent and child
- Exclude sensitive/derived fields: `@ToString.Exclude` and `@EqualsAndHashCode.Exclude`

## Idioms Used in This Repo

### String Validation
- **ALWAYS** use `StringUtils.isBlank(str)` instead of `str == null || str.isBlank()`
- **ALWAYS** use `StringUtils.isNotBlank(str)` instead of `str != null && !str.isBlank()`
- **ALWAYS** use `StringUtils.isEmpty(str)` instead of `str == null || str.isEmpty()`
- **ALWAYS** use `StringUtils.isNotEmpty(str)` instead of `str != null && !str.isEmpty()`

```java
// Bad - verbose null/blank checking
if (userHash == null || userHash.isBlank()) { ... }
if (name != null && !name.isBlank()) { ... }

// Good - use StringUtils
if (StringUtils.isBlank(userHash)) { ... }
if (StringUtils.isNotBlank(name)) { ... }

// Bad - verbose null/empty checking
if (value == null || value.isEmpty()) { ... }
if (text != null && !text.isEmpty()) { ... }

// Good - use StringUtils
if (StringUtils.isEmpty(value)) { ... }
if (StringUtils.isNotEmpty(text)) { ... }
```

**Note:**
- `StringUtils.isBlank()` checks for null, empty (""), and whitespace-only strings
- `StringUtils.isEmpty()` checks for null and empty ("") strings only (does NOT check for whitespace)
- Choose based on whether you want to treat whitespace-only strings as valid or not

### Collection Validation
- Use `CollectionUtils.emptyIfNull(collection)` instead of explicit isEmpty checks
- Use `ObjectUtils.isEmpty(object)` instead of manual null/isEmpty/blank check

### Other Patterns
- Prefer Optional pipelines over null checks/ternaries
- Use `stream().toList()` instead of `stream().collect(Collectors.toList())`; wrap with `new ArrayList<>(...)` if mutation is needed

## Javadoc

Add Javadoc to every method, including private ones:

```java
/**
 * Summarize the purpose of the method.
 * Describe internal logic or important steps.
 *
 * @param name Describe each parameter and how it is used
 * @return Explain the return value; use "void" when nothing is returned
 */
```

- Update Javadoc whenever you change a method
- If you discover a method without Javadoc, add it before moving on
