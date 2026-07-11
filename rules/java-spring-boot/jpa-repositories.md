---
triggers: ["JpaRepository", "@Entity", "@Repository", "@Query", "findBy", "EntityManager"]
---
## JPA Repository Conventions

### Overview

Spring Data JPA repositories provide database access. This project uses **PostgreSQL in production** and **H2 for testing**. These databases have different behaviors, so queries must be compatible with both.

### Location and Structure

- **Naming**: `[Entity]Repository` (e.g., `ProductRepository`, `OrderRepository`)
- **Extends**: `CrudRepository<EntityType, IdType>`

### Basic Pattern

```java
package com.example.{project}.repositories;

import com.example.{project}.entities.ExampleEntity;
import org.springframework.data.repository.CrudRepository;
import org.springframework.stereotype.Repository;

/**
 * Repository for accessing ExampleEntity data.
 * Brief description of what this repository is used for.
 */
@Repository
public interface ExampleRepository extends CrudRepository<ExampleEntity, Long> {

  // Spring Data JPA method name queries
  Optional<ExampleEntity> findByIdAndUserHashAndDeletedAtIsNull(Long id, String userHash);

  // Custom JPQL/SQL queries
  @Query("SELECT e FROM ExampleEntity e WHERE e.name = :name")
  List<ExampleEntity> findByName(@Param("name") String name);
}
```

**🚨 CRITICAL**: See transaction-boundaries.md in your project's coding standards directory for transaction patterns with repositories.

## CRITICAL: Validate Before Querying

### Defense in Depth: Controller Validation First

**ALWAYS validate query parameters at the controller level BEFORE calling the repository.**

This prevents bad queries from reaching the database and provides better error messages to users.

**Example - a partner Products API:**

```java
@GetMapping
public ResponseEntity<?> list(
    @RequestParam(required = false) LocalDate date,
    @RequestParam(required = false) String arrivalProductNo,
    @RequestParam(required = false) Long carrierId) {

  return handleRequest(
    // Validation FIRST - prevents null parameters from reaching repository
    () -> ProductsValidator.validateDateParameters(date, null, null,
        arrivalProductNo, null, carrierId),
    () -> {
      // Only execute if validation passes
      List<Product> products = service.getAllProducts(date, date,
          arrivalProductNo, null, carrierId);
      return presenter.present(products);
    });
}
```

**Validator Example:**

```java
public static List<Error> validateDateParameters(..., String productNo, Long carrierId) {
  List<Error> errors = new ArrayList<>();

  // Require at least one filter to prevent full table scans
  if (date == null && fromDate == null && toDate == null
      && productNo == null && carrierId == null) {
    errors.add(Error.builder()
      .setField("filters")
      .setMessage("At least one filter parameter is required")
      .build());
    return errors;
  }

  // ... other validation
  return errors;
}
```

**Benefits:**
1. Prevents expensive full table scans
2. Catches type inference errors before hitting database
3. Returns user-friendly 400 errors instead of 500 errors
4. Works consistently across H2 (tests) and PostgreSQL (production)

## CRITICAL: PostgreSQL vs H2 Compatibility

**Tests use H2 (in-memory), Production uses PostgreSQL. They behave differently!**

### Rule #1: Nullable Parameters in Queries

**Problem**: PostgreSQL cannot infer types for nullable parameters in `IS NULL OR` patterns.

❌ **Bad - Fails in PostgreSQL:**
```java
@Query("SELECT h FROM Product h WHERE (:date IS NULL OR h.arrivalDate >= :date)")
List<Product> findByFilters(@Param("date") LocalDateTime date);
// Error: could not determine data type of parameter $1
```

✅ **Good - Three Options:**

**1. Native SQL with CAST (for complex optional filters):**
```java
@Query(value = """
  SELECT * FROM products
  WHERE (CAST(:date AS timestamp) IS NULL OR arrival_date >= CAST(:date AS timestamp))
    AND (CAST(:carrierId AS bigint) IS NULL OR carrier_id = CAST(:carrierId AS bigint))
    AND (CAST(:origin AS varchar) IS NULL OR origin = CAST(:origin AS varchar))
    AND (CAST(:destination AS varchar) IS NULL OR destination = CAST(:destination AS varchar))
    AND (CAST(:productNo AS varchar) IS NULL OR arrival_product_no = CAST(:productNo AS varchar))
  """, nativeQuery = true)
List<Product> findByFilters(
    @Param("date") LocalDateTime date,
    @Param("carrierId") Long carrierId,
    @Param("origin") String origin,
    @Param("destination") String destination,
    @Param("productNo") String productNo);
```

**2. Method name queries (for simple queries):**
```java
List<Product> findByArrivalProductNo(String productNo);
List<Product> findByArrivalDateBetween(LocalDateTime start, LocalDateTime end);
```

**3. Dynamic queries in service (for complex logic):**
```java
if (carrierId != null) return repository.findByCarrierIdAndDate(carrierId, date);
else return repository.findByDate(date);
```

**PostgreSQL Type Mapping:**
| Java Type | PostgreSQL | Example |
|-----------|-----------|---------|
| `LocalDateTime` | `timestamp` | `CAST(:date AS timestamp)` |
| `Long` | `bigint` | `CAST(:id AS bigint)` |
| `Integer` | `integer` | `CAST(:count AS integer)` |
| `String` | `varchar` | `:name` (no CAST needed for non-null; use `CAST(:name AS varchar)` for nullable in IS NULL patterns) |

## Rule #2: Always Include UserHash and DeletedAt

For user-specific entities (multi-tenant data), ALWAYS include these filters:

```java
@Query("SELECT p FROM Package p WHERE p.id = :id AND p.userHash = :userHash AND p.deletedAt IS NULL")
Optional<Package> findByIdAndUserHashAndDeletedAtIsNull(
  @Param("id") Long id,
  @Param("userHash") String userHash
);
```

**Exceptions**: Shared data tables (like `partner_products`, `support_services`, `survey_questions`) don't have `user_hash` or `deleted_at` columns.

## Rule #3: Prefer Method Name Queries for Simple Cases

Spring Data JPA can generate queries from method names automatically. This is safer and more maintainable.

✅ **Good (Auto-generated):**
```java
Optional<Item> findByIdAndType(Long id, Integer type);
List<Package> findByUserHashAndDeletedAtIsNull(String userHash);
List<Item> findByCreatedAtBetween(LocalDateTime start, LocalDateTime end);
```

❌ **Bad (Unnecessary @Query):**
```java
@Query("SELECT h FROM Product h WHERE h.productId = :productId AND h.productType = :productType")
Optional<Product> findByProductIdAndProductType(@Param("productId") Long productId, @Param("productType") Integer productType);
```

## Rule #4: Ensure Indexes Align with Query WHERE Clauses

**CRITICAL**: When writing custom queries, ensure indexes exist for ALL filtered columns.

**Without index**: Sequential scan (reads every row) ❌
**With index**: Index scan (fast lookup) ✅

### How to Add Indexes

**1. Identify columns in WHERE clause:**
```sql
WHERE arrival_product_no = :productNo  -- arrival_product_no needs index
  AND carrier_id = :carrierId        -- carrier_id needs index
```

**2. Add via sub-version migration:**
```sql
-- V1.34.1__AddProductsIndexes.sql
CREATE INDEX IF NOT EXISTS idx_partner_products_arrival_product_no
    ON public.partner_products(arrival_product_no);
```

**3. Update entity @Table annotation:**
```java
@Table(indexes = {
  @Index(name = "idx_partner_products_arrival_product_no", columnList = "arrival_product_no")
})
```

### Single vs Composite Indexes

**Single-column (start here):**
```sql
CREATE INDEX idx_arrival_date ON products(arrival_date);
CREATE INDEX idx_carrier_id ON products(carrier_id);
```
✅ Covers all filter combinations (PostgreSQL combines with bitmap scan)

**Composite (only if profiling shows need):**
```sql
CREATE INDEX idx_date_carrier ON products(arrival_date, carrier_id);
```
✅ Faster for high-frequency patterns using both columns
❌ Slows writes, uses more disk space

**Verify with EXPLAIN ANALYZE:**
```sql
EXPLAIN ANALYZE SELECT * FROM products WHERE arrival_product_no = 'SV123';
-- Good: "Index Scan using idx_products_arrival_product_no"
-- Bad: "Seq Scan on products" (missing index!)
```

## Rule #5: Use @Modifying for DELETE/UPDATE

Queries that modify data require `@Modifying` annotation:

```java
@Modifying
@Query("DELETE FROM Product h WHERE h.departureDate < :cutoffDate")
int deleteByDepartureDateBefore(@Param("cutoffDate") LocalDateTime cutoffDate);

@Modifying
@Query("UPDATE Package p SET p.status = :status WHERE p.id = :id")
int updateStatus(@Param("id") Integer id, @Param("status") String status);
```

**Important**: Call these methods within a transaction (use `TransactionTemplate` in services).

## Rule #6: Avoid LazyInitializationException

**Problem**: Accessing lazy collection outside Hibernate session throws `LazyInitializationException`.

**Common causes:**
1. Calling `entity.getLazyCollection()` outside `@Transactional` method
2. Calling `@Transactional` method from WITHIN same class (Spring proxy limitation)

**Solutions (in order of preference):**

**1. Fetch from repository directly (RECOMMENDED):**
```java
// ✅ GOOD - Use child repository
List<Item> items = itemRepository.findAllByPackageIdAndDeletedAtIsNull(packageId);
```

**2. Make outer method @Transactional:**
```java
@Transactional(readOnly = true)
public void process(Integer packageId) {
    Package pkg = repository.findById(packageId).orElseThrow();
    List<Item> items = pkg.getItems(); // Works now
}
```

**3. Use JOIN FETCH:**
```java
@Query("SELECT p FROM Package p LEFT JOIN FETCH p.customers WHERE p.id = :id")
Optional<Package> findByIdWithCustomers(@Param("id") Integer id);
```

**Key Rules:**
- NEVER call `entity.getLazyCollection()` outside transaction
- NEVER rely on `@Transactional` for internal method calls (Spring proxy doesn't intercept)
- PREFER child repository over lazy navigation
- USE JOIN FETCH only when you know you need the collection

## Rule #7: Testing Repository Queries

### Use @DataJpaTest for Repository Tests

```java
@DataJpaTest  // Uses H2 in-memory database
@DisplayName("ProductRepository")
class ProductRepositoryTest {

  @Autowired
  private TestEntityManager entityManager;

  @Autowired
  private ProductRepository repository;

  @Test
  void findByFilters_withNullParams_shouldWork() {
    // This will use H2, but query must work in PostgreSQL too!
    List<Product> results = repository.findByFilters(null, null, null, null, null);
    assertThat(results).isNotNull();
  }
}
```

### The H2 vs PostgreSQL Gap

**Problem**: Tests pass with H2 but fail with PostgreSQL.

**Why**:
- H2 is lenient with type inference
- PostgreSQL is strict about type hints
- Nullable parameters need explicit CAST in PostgreSQL

**Mitigation**:
1. ✅ **Use native SQL with CAST** for nullable parameters (see Rule #1)
2. ✅ **Test against real PostgreSQL** in local development before committing
3. ✅ **Use method name queries** when possible (Spring Data handles compatibility)
4. ✅ **Document this pattern** in coding rules (this file!)

### Local PostgreSQL Testing

Before committing repository changes with custom queries, test against real PostgreSQL:

```bash
# Start PostgreSQL via Docker
docker-compose up -d postgres

# Run the application against PostgreSQL (not H2)
./gradlew :module-http:bootRun

# Test the API endpoint manually
curl "http://localhost:8080/api/v1/items?date=2026-01-25"
```

**When to test against PostgreSQL:**
- Creating new `@Query` annotations with nullable parameters
- Using native SQL queries
- Complex WHERE clauses with optional filters

## Complete Repository Example

```java
package com.example.{project}.repositories;

import com.example.{project}.entities.Item;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.CrudRepository;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

@Repository
public interface ItemRepository extends CrudRepository<Item, Long> {

  // Auto-generated, no @Query needed
  Optional<Item> findByIdAndType(Long id, Integer type);

  // Date range, auto-generated
  List<Item> findByCreatedAtBetween(LocalDateTime start, LocalDateTime end);

  // Complex nullable filters, native SQL with CAST for PostgreSQL compatibility
  @Query(value = """
    SELECT * FROM items
    WHERE (CAST(:fromDate AS timestamp) IS NULL OR created_at >= CAST(:fromDate AS timestamp))
      AND (CAST(:toDate AS timestamp) IS NULL OR created_at <= CAST(:toDate AS timestamp))
      AND (:status IS NULL OR status = :status)
      AND (CAST(:ownerId AS bigint) IS NULL OR owner_id = CAST(:ownerId AS bigint))
    """, nativeQuery = true)
  List<Item> findByFilters(
    @Param("fromDate") LocalDateTime fromDate,
    @Param("toDate") LocalDateTime toDate,
    @Param("status") String status,
    @Param("ownerId") Long ownerId
  );

  // Soft delete, requires @Modifying, must be called within a transaction
  @Modifying
  @Query("DELETE FROM Item i WHERE i.createdAt < :cutoffDate")
  int deleteByCreatedAtBefore(@Param("cutoffDate") LocalDateTime cutoffDate);
}
```

## Quick Reference

| Scenario | Solution | Example |
|----------|----------|---------|
| Simple lookup | Method name query | `findByProductIdAndProductType()` |
| Date range | Method name query | `findByArrivalDateBetween()` |
| Multiple optional filters | Native SQL + CAST | See complete example above |
| Delete/Update | @Modifying + @Query | `@Modifying @Query("DELETE...")` |
| User-specific data | Include UserHash + DeletedAt | `findByUserHashAndDeletedAtIsNull()` |
| Access lazy collection | Fetch from child repository | `itemRepo.findAllByPackageId()` |
| Need lazy collection | JOIN FETCH in query | `LEFT JOIN FETCH p.customers` |
