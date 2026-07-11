---
triggers: ["assertThat", "when(", "verify(", "@Schema", "@Test", "@FeignClient", "Objects.equals", "SonarQube", "sonar"]
---
# SonarQube Compliance

Rules to prevent common SonarQube findings. Apply when writing or reviewing Java code. These are the findings reviewers catch by hand most often, encode them so they never reach review.

For formatting, imports (no fully-qualified names), and AOP annotation placement, see `coding-conventions.md`, not repeated here.

## Swagger / OpenAPI Annotations

- **Do NOT use** `@Schema(required = true)`, the `required` attribute is deprecated. Omit it: `@Schema(description = "...")`. Requiredness is controlled by validation annotations (`@NotNull`, `@NotBlank`) and the OpenAPI spec, not by `@Schema.required`.

```java
// Bad, deprecated attribute
@Schema(description = "Category ID", required = true)
private Integer categoryId;

// Good, drop required; @NotNull conveys it
@NotNull
@Schema(description = "Category ID")
private Integer categoryId;
```

## Boxed Type Equality (`S4973`, BUG severity)

`==` and `!=` on `Integer`, `Long`, `String`, or any reference type are **reference comparisons**, not value comparisons. For boxed integers they only happen to work inside the `-128..127` cache range, the bug hides in tests with small IDs and surfaces in production once IDs grow.

Use `Objects.equals(a, b)` (null-safe) or `a.equals(b)` when both sides are known non-null. Primitive `int`/`long`/`boolean` comparisons with `==`/`!=` are fine, the rule only applies to reference types.

```java
// Bad, entity.getId() is a boxed Integer; this is reference comparison
if (resolved.getId() != base.getId()) { ... }

// Good, value comparison, null-safe
if (!Objects.equals(resolved.getId(), base.getId())) { ... }
```

Watch the hidden case: a JPA `getId()` looks numeric but usually returns a boxed `Integer` (so the column can be `NULL` before insert). Treat any non-primitive return type as a reference-comparison hazard.

## Loop Control Flow (`S135`)

Keep `break` and `continue` to **at most one per loop**. Multiple exits force the reader to track several paths and obscure the termination condition. Most cases collapse into a single loop condition or an extracted helper. An early `return` is a method-level exit and is **not** flagged.

```java
// Bad, two breaks, ambiguous exit
while (true) {
  List<Foo> batch = repo.findPage(cursor, PAGE_SIZE);
  if (batch.isEmpty()) break;
  for (Foo foo : batch) process(foo);
  if (batch.size() < PAGE_SIZE) break;
}

// Good, single exit via loop condition (iterating an empty batch is a no-op)
boolean more = true;
while (more) {
  List<Foo> batch = repo.findPage(cursor, PAGE_SIZE);
  for (Foo foo : batch) process(foo);
  more = batch.size() == PAGE_SIZE;
}
```

If the in-loop work takes the whole batch (`process(batch)`), an empty list isn't a no-op, guard with `if (!batch.isEmpty())` before dropping the empty-check break, or use the `for`-over-batch idiom above which sidesteps it.

## Dead Code (`S2094`, `S1130`)

- Remove unused private fields, parameters, and imports.
- Remove `throws` declarations for exceptions the body can't actually throw (`S1130`), common on tests written as `void myTest() throws Exception` with no throwing call.
- **Delete empty classes** rather than keeping them as future-extension placeholders (`S2094`). Empty marker classes referenced only as framework placeholders (e.g. `@FeignClient(configuration = EmptyConfig.class)`) are still flagged, drop the framework reference and let defaults apply until you actually need to override something.

```java
// Bad, empty class kept "for future use", flagged by S2094
public class FeatureClientConfig {}

@FeignClient(name = "x", url = "${...}", configuration = FeatureClientConfig.class)
public interface FeatureClient { ... }

// Good, drop the placeholder and the configuration attribute
@FeignClient(name = "x", url = "${...}")
public interface FeatureClient { ... }
```

## Mockito Matchers (`S6068`)

Don't wrap raw values in `eq()` when no other matcher is in play, Mockito accepts raw values directly when *all* arguments are concrete. Only use `eq()` when at least one argument is an `any*()` (or other) matcher, because Mockito's all-or-nothing rule then requires every argument to be a matcher.

```java
// Bad, pointless eq() wrappers (S6068)
when(svc.getItem(eq(2), eq("en"))).thenReturn(item);

// Good, pass values directly
when(svc.getItem(2, "en")).thenReturn(item);

// Good, eq() required when mixed with another matcher
verify(svc, never()).getItem(anyInt(), eq("en"));
```

**`verifyNoInteractions(mock)` over `verify(mock, never()).method(anyString())`** when asserting a dependency was untouched: the `never()` form with `anyString()` silently misses a call made with a `null` argument (`anyString()` rejects null), so a real violation passes. `verifyNoInteractions` catches any call.

## AssertJ / Test Assertion Idioms (`S5838`, `S5853`, `S5778`)

- **Semantic methods:** `isZero()` over `isEqualTo(0)`; `isEmpty()` over `isEqualTo("")`/`hasSize(0)`; `isOne()`; `isTrue()`/`isFalse()` over `isEqualTo(true/false)`.
- **`containsEntry(k, v)`** for a map key/value (`S5838`) instead of `assertThat(map.get(k)).isEqualTo(v)`.
- **One throwing call per `assertThatThrownBy` lambda** (`S5778`), the lambda must hold only the call expected to throw, or the assertion is ambiguous.
- **`BigDecimal`:** compare with `isEqualByComparingTo` (or `compareTo`), never `isEqualTo`/`equals`, the latter are scale-sensitive (`2.0` ≠ `2.00`). The same trap hits `containsEntry` on a `Map<_, BigDecimal>`.

```java
// Bad, scale-sensitive, brittle
assertThat(total).isEqualTo(new BigDecimal("2.0"));
assertThat(count).isEqualTo(0);

// Good
assertThat(total).isEqualByComparingTo("2.0");
assertThat(count).isZero();
```

## Test Quality

- Every `@Test` method must contain **at least one assertion** (`assertThat`, `assertThatThrownBy`, …). Action-only tests are flagged Blocker.
- Empty catch blocks need a comment explaining why the exception is intentionally ignored.
- Avoid commented-out code, including prose containing tokens like `<=` or identifiers that the parser reads as commented-out code (`S125`), delete it; version history preserves intent.

## Spring Proxy Self-Invocation

`@Cacheable`/`@Transactional` called via `this`, or placed on a non-public method, silently bypass the proxy, the annotation has no effect. **Canonical fix:** the helper pattern in `coding-conventions.md` § AOP Annotation Placement (annotations on `public` methods only; same-class callers use an unannotated package-private helper or `TransactionTemplate`). See also `transaction-boundaries.md`.
