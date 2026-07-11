---
triggers: ["findAll", "@Query", "JOIN FETCH", "@OneToMany", "@ManyToOne", "Pageable"]
---
# Query Efficiency, Spring Boot / JPA

Every database call must satisfy two rules:
- **Selective**, fetch only the rows you need
- **Minimal**, fetch only as often as needed

Violating either degrades performance at scale. You have full context when writing code, if data is already available, use it. Never re-fetch what you already hold.

---

## Group 1: Query Selectivity

**Anti-pattern:** fetching more rows than needed, then filtering in application code.

### Use IDs you already have

When upstream context gives you specific IDs, pass them to the WHERE clause.

```java
// ❌ WRONG, fetches every country, filters in Java
List<Country> needed = countryRepository.findAll().stream()
    .filter(c -> requiredIds.contains(c.getId()))
    .toList();

// ✅ CORRECT, one selective query
List<Country> needed = countryRepository.findByIdIn(requiredIds);
```

The IDs were already available. There is no excuse for `findAll()` when `findByIdIn()` can do the job.

### Never assume a table is small

`findAll()` is only acceptable when every row is genuinely needed and no selective alternative exists. You cannot know a table's current or future size. Treat every `findAll()` as requiring explicit justification.

### Push filtering to the database

If a condition can be expressed in a WHERE clause on an indexed column, it belongs in the query, not in a stream filter after fetching.

```java
// ❌ WRONG, full scan, Java-side filter
List<Order> orders = orderRepository.findAll().stream()
    .filter(o -> o.getStatus() == PENDING)
    .toList();

// ✅ CORRECT, DB filters, returns only what's needed
List<Order> orders = orderRepository.findByStatus(PENDING);
```

> Selective queries are only fast if the filtered columns are indexed. See `jpa-repositories.md` for index setup.

---

## Group 2: Query Minimality (N+1 Prevention)

**Anti-pattern:** executing N queries, or re-executing queries for data already fetched, where a fixed number of batched queries would suffice.

### Pattern 1: Repository Call Inside a Loop

```java
// ❌ WRONG, N queries
for (OrderItem item : items) {
    Product product = productRepository.findById(item.getProductId()).orElse(null);
    item.setProductName(product.getName());
}

// ✅ CORRECT, 1 query
List<Integer> productIds = items.stream().map(OrderItem::getProductId).distinct().toList();
Map<Integer, Product> productsById = productRepository.findByIdIn(productIds).stream()
    .collect(Collectors.toMap(Product::getId, Function.identity()));

for (OrderItem item : items) {
    item.setProductName(productsById.get(item.getProductId()).getName());
}
```

### Pattern 2: Lazy Collection Access in a Loop

```java
// ❌ WRONG, each getItems() fires a SELECT
for (Order order : orders) {
    process(order.getItems());
}

// ✅ CORRECT, JOIN FETCH in repository
@Query("SELECT o FROM Order o LEFT JOIN FETCH o.items WHERE o.id IN :ids")
List<Order> findByIdInWithItems(@Param("ids") List<Integer> ids);
```

### Pattern 3: Helper Method Hiding a Query

```java
// ❌ WRONG, called N times, fires N queries
for (Customer a : customers) {
    dto.setRegion(mapCountryCode(a.getRegionCode()));
}

private String mapCountryCode(String code) {
    return countryRepository.findByCode(code).map(Country::getPartnerCode).orElse(null);
}

// ✅ CORRECT, extract codes, load once, pass the map
List<String> codes = customers.stream().map(Customer::getRegionCode).distinct().toList();
Map<String, Country> byCode = countryRepository.findByCodeIn(codes).stream()
    .collect(Collectors.toMap(Country::getCode, Function.identity()));

for (Customer a : customers) {
    dto.setRegion(mapCountryCode(a.getRegionCode(), byCode));
}

private String mapCountryCode(String code, Map<String, Country> lookup) {
    Country country = lookup.get(code);
    return country != null ? country.getPartnerCode() : null;
}
```

### Pattern 4: Re-fetching Data That's Already Available

If a caller already loaded an entity or result set, pass it down. A called method that accepts an ID and re-queries what the caller already holds is always wrong.

```java
// ❌ WRONG, same row fetched 3 times in one flow
public void process(Integer packageId) {
    Package pkg = packageRepository.findById(packageId).orElseThrow();
    buildHeader(packageId);   // fetches the same row internally
    buildFooter(packageId);   // fetches the same row internally
}

// ✅ CORRECT, fetch once, pass the object
public void process(Integer packageId) {
    Package pkg = packageRepository.findById(packageId).orElseThrow();
    buildHeader(pkg);
    buildFooter(pkg);
}
```

This applies across the entire call chain. If a service method loaded an entity and calls a helper, the helper receives the entity, it does not accept an ID and re-query.

### Pattern 5: Chained N+1

```java
// ❌ WRONG, 2N queries for N items
for (Item item : items) {
    ServiceMapping mapping = mappingRepository.findById(item.getMappingId()).get();
    OperatorPackage pkg = operatorRepository.findById(mapping.getOperatorId()).get();
}

// ✅ CORRECT, 2 queries total
List<Integer> mappingIds = items.stream().map(Item::getMappingId).distinct().toList();
Map<Integer, ServiceMapping> mappingsById = mappingRepository.findByIdIn(mappingIds).stream()
    .collect(Collectors.toMap(ServiceMapping::getId, Function.identity()));

List<Integer> operatorIds = mappingsById.values().stream()
    .map(ServiceMapping::getOperatorId).distinct().toList();
Map<Integer, OperatorPackage> operatorsById = operatorRepository.findByIdIn(operatorIds).stream()
    .collect(Collectors.toMap(OperatorPackage::getId, Function.identity()));
```

### Required: Batch Methods in Every Repository

Every repository involved in collection processing must expose batch variants:

```java
List<Product> findByIdIn(List<Integer> ids);
List<Answer> findByCustomerIdIn(List<Integer> customerIds);
List<Country> findByCodeIn(List<String> codes);
```

---

## The DataContext Pattern

When a service method needs 3+ lookups across multiple helper methods, consolidate all fetching into a DataContext. This satisfies both rules simultaneously: one fetch phase (selective and batched), one build phase (zero queries, pure in-memory).

### Define the context

```java
@Getter
@Builder(setterPrefix = "set")
public class OrderDataContext {
    private final Order order;
    private final List<OrderItem> items;
    private final Map<Integer, Product> productsById;
    private final Map<String, Country> countriesByCode;
    private final Map<Integer, List<Answer>> answersByCustomerId;
}
```

### Populate in one @Transactional(readOnly = true) method

Collect all required IDs from data already in memory, then fetch selectively.

```java
@Transactional(readOnly = true)
public OrderDataContext fetchAllData(Integer orderId) {
    Order order = orderRepository.findById(orderId).orElseThrow();
    List<OrderItem> items = itemRepository.findByOrderIdWithPrices(orderId);
    List<Customer> customers = customerRepository.findByOrderId(orderId);

    // Derive IDs from data already loaded, no guessing, no over-fetching
    List<Integer> productIds = items.stream().map(OrderItem::getProductId).distinct().toList();
    List<String> countryCodes = customers.stream().map(Customer::getRegionCode).distinct().toList();
    List<Integer> customerIds = customers.stream().map(Customer::getId).distinct().toList();

    return OrderDataContext.builder()
        .setOrder(order)
        .setItems(items)
        .setProductsById(productRepository.findByIdIn(productIds).stream()
            .collect(Collectors.toMap(Product::getId, Function.identity())))
        .setCountriesByCode(countryRepository.findByCodeIn(countryCodes).stream()
            .collect(Collectors.toMap(Country::getCode, Function.identity())))
        .setAnswersByCustomerId(answerRepository.findByCustomerIdIn(customerIds).stream()
            .collect(Collectors.groupingBy(Answer::getCustomerId)))
        .build();
}
```

### Build methods receive context, no repository access

```java
private ItemDto buildItem(OrderItem item, OrderDataContext ctx) {
    Product product = ctx.getProductsById().get(item.getProductId()); // map lookup, no query
    // ...
}
```

### When to use DataContext vs simple batch-load

| Situation | Approach |
|---|---|
| 1-2 lookups in one method | Batch-load into Map at method start |
| 3+ lookups across helper methods | DataContext |
| Same data needed by 4+ helpers | DataContext |

---

## Before Writing Any Service Method

1. What rows do I need? Use specific IDs or filters, never fetch all rows speculatively
2. Do I have IDs already? Pass them to `findByIdIn()`, not `findAll()`
3. Is data already available from a caller? Accept it as a parameter, never re-query
4. Am I inside a loop? Batch-load before the loop, not inside it
5. Do helpers fetch independently? Use DataContext
6. Target: **O(1) queries regardless of collection size**

---

## Red Flags

| Pattern | Problem | Fix |
|---|---|---|
| `findAll()` when IDs are known | Over-fetching | `findByIdIn(knownIds)` |
| `.stream().filter()` after `findAll()` | App-level filtering | Push condition to WHERE clause |
| `repository.find*()` inside `for`/`forEach`/`stream()` | N+1 | Batch-load into Map before loop |
| Helper method accepting an ID, not an object or map | Hidden query | Pass entity or lookup map |
| Method re-querying data the caller already holds | Redundant fetch | Pass the already-loaded object |
| 3+ lookups scattered across helper methods | Fragmented fetching | DataContext |
| `entity.getLazyCollection()` in a loop | Lazy N+1 | JOIN FETCH or batch query |
