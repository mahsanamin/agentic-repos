---
alwaysApply: true
---
# API Conventions

Standard conventions for building REST APIs. See `project-structure.md` for file locations.

## Request Flow

```
HTTP Request
    ↓
Controller (@Authenticated) → extracts userHash from KongAuthentication
    ↓
Validator (static) → returns List<Error>
    ↓
Mapper (static) → Request DTO → Domain Model
    ↓
Service (@Transactional) → business logic + repository calls
    ↓
Mapper (static) → Domain Model → View DTO
    ↓
Presenter (static) → wraps in ResponseEntity<HttpResponseV2>
    ↓
HTTP Response
```

## URL Conventions

| Type | Path Pattern | Authentication | Use Case |
|------|--------------|----------------|----------|
| **Public** | `{service}/v1/{feature}` | Kong (`@Authenticated`) | Mobile/web app users |
| **Internal** | `internal/{service}/v1/{feature}` | internal-auth header or service token | CMS tools, service-to-service |

- No `/admin` or `/authenticated` in paths - authentication mechanism handles access control
- Version in path (`v1`) for API versioning - increment on breaking data changes
- Feature name as kebab-case (e.g., `your-feature` - use your feature name)

### No PII in GET query parameters

Never accept PII (email, user hash, phone, name) as a GET query parameter, it lands in URLs, access/proxy logs, browser history, and APM traces, all of which are retained and widely readable. When a lookup key is PII, use **POST with the identifier in the request body**, optionally with a `searchBy` discriminator:

```java
// ❌ BAD, email in the URL → logged everywhere
@GetMapping  // GET internal/{service}/v1/members?email=user@example.com

// ✅ GOOD, identifier in the body, never logged in the URL
@PostMapping  // POST internal/{service}/v1/members/lookup  { "searchBy": "EMAIL", "value": "..." }
```

This makes a lookup endpoint a `POST` even though it reads, the PII-safety rule wins over GET-for-reads.

### Contract is the source of truth

Field names, path casing, and response shape must match the canonical API contract (e.g. the API docs repo). Treat the published spec as authoritative: rename to match it rather than inventing local names, keep path placeholders in the documented casing, and **update the docs in the same PR as the code change** so the two never drift.

## Response Model Versions

**Important:** Path version and Response Model version are **independent concepts**.

| Concept | Example | Purpose |
|---------|---------|---------|
| **Path version** | `{service}/v1/...`, `{service}/v2/...` | API contract versioning - increment when breaking changes to request/response data |
| **Response Model version** | `HttpResponseV2`, `BaseControllerV2` | the base framework framework's response envelope format |

We use **V2 Response Models** throughout:
- `BaseControllerV2` - base controller class
- `HttpResponseV2<TData, TError>` - response wrapper
- `HttpResponseSuccessV2` - success response builder
- `ErrorViewV2` - error format
- Presenter methods: `presentSuccessV2()`, `presentCreatedV2()`, `presentNotFoundV2()`

```
Path v1 + Response V2 ✓  (current)
Path v2 + Response V2 ✓  (future breaking API change)
Path v1 + Response V1 ✗  (don't use V1 response models)
```

## Controller Pattern (Public)

```java
@RestController
@RequestMapping("{service}/v1/{feature}")
@Tag(name = "[Public] FeatureController", description = "APIs for feature")
public class FeatureController extends BaseControllerV2 {

  private final FeatureService service;

  public FeatureController(Validator validator, FeatureService service) {
    super(validator);
    this.service = service;
  }

  @Operation(summary = "...", responses = {@ApiResponse(...)})
  @PostMapping(consumes = "application/json", produces = "application/json")
  @Authenticated
  public ResponseEntity<HttpResponseV2<FeatureView, ErrorViewV2>> create(
      @RequestAttribute(name = "sbgKongAuthentication") KongAuthentication kongAuth,
      @RequestBody CreateRequest request) {
    return handleRequest(
        request,
        () -> FeatureValidator.validateCreate(request),  // validation
        () -> {
          String userHash = kongAuth.getUserHash();      // security
          Feature result = service.create(userHash, ...);
          return FeaturePresenter.presentCreatedV2(result);
        });
  }
}
```

**handleRequest variants:**
- `handleRequest(request, validator, supplier)` - POST/PATCH with body + validation
- `handleRequest(validator, supplier)` - GET/DELETE with validation (no body)
- `handleRequest(supplier)` - GET/DELETE without validation

Always extract `userHash` from `KongAuthentication` for ownership checks.

## Controller Pattern (Internal)

```java
@RestController
@RequestMapping("internal/{service}/v1/{feature}")
@Tag(name = "[Internal] FeatureController", description = "Internal APIs for feature")
public class InternalFeatureController extends BaseControllerV2 {

  private final FeatureService service;

  public InternalFeatureController(Validator validator, FeatureService service) {
    super(validator);
    this.service = service;
  }

  @Operation(summary = "...", responses = {@ApiResponse(...)})
  @GetMapping(produces = "application/json")
  public ResponseEntity<HttpResponseV2<FeatureView, ErrorViewV2>> getAll(
      @RequestHeader(AppConstants.Headers.CURRENT_USER_EMAIL) String loginUser,
      @RequestParam(value = "page", defaultValue = "1") Integer page) {
    return handleRequest(
        () -> {
          List<Error> errors = new ArrayList<>();
          CommonValidator.validatePositiveNumber(errors, page, "page");
          return errors;
        },
        () -> {
          // No userHash ownership - internal endpoints access all resources
          List<Feature> results = service.getAll(page);
          return FeaturePresenter.presentListV2(results);
        });
  }
}
```

- No `@Authenticated` annotation - protected by network/gateway
- Use internal-auth header for audit trail (who performed the action)
- No `userHash` ownership checks - internal endpoints can access all resources
- Use `CommonValidator` helper methods for inline validation

## Validator Pattern

```java
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public class FeatureValidator {

  public static List<Error> validateCreate(CreateRequest request) {
    List<Error> errors = new ArrayList<>();
    // business rule validations (not null/format - use Bean Validation for those)
    if (request.getStartDate() != null && request.getStartDate().isBefore(LocalDate.now())) {
      errors.add(Error.builder()
          .setField("startDate")
          .setMessage("Start date cannot be in the past")
          .build());
    }
    return errors;
  }
}
```

- Static utility class with private constructor
- Return `List<Error>` (empty = valid)
- Use `Error.builder().setField().setMessage().build()`
- For nested objects: prefix field with `items[0].fieldName`

### Declarative (Bean) Validation, prefer annotations over hand-rolled checks

Null / blank / format / range / enum-membership checks belong as **Jakarta Bean Validation annotations on the request DTO**, not as hand-written `if` blocks in the controller or a custom validator. The static Validator is for **business rules** only (cross-field invariants, at-least-one-filter, state-machine preconditions). Don't reinvent presence/format checks the annotations already give you.

```java
public class CreateOrderRequest {
  @NotBlank                       private String orderRef;
  @NotNull @Positive              private Integer itemId;
  @NotNull @DecimalMin(value = "0", inclusive = false)  // strictly positive
                                  private BigDecimal unitPrice;
  @NotNull                        private OrderType orderType;  // enum: unknown value → 400 at binding
  @AssertTrue(message = "endDate must be after startDate")
  private boolean isDateRangeValid() { return endDate == null || endDate.isAfter(startDate); }
}
```

- **Reject unknown enum values at the boundary.** Binding a request field to an enum type makes an unrecognized value a 400 at deserialization, far better than letting a typo (`"STANDRD"` for `STANDARD`) flow through and persist as `NULL` or a bad row.
- **Relaxing a field to optional** (a contract change, see `test-change-policy.md`): make the field optional, apply the default in the **mapper** (not scattered in the controller), and suppress null wire output with `@JsonInclude(JsonInclude.Include.NON_NULL)` so the response stays clean. Don't leave a now-optional field still throwing in a hand-rolled validator.

## Query Parameter Validation (CRITICAL)

### When Adding Controllers with Query Parameters

**ALWAYS add validation for query parameters, especially when they are all optional.**

### Problem: Unvalidated Optional Parameters

If ALL query parameters are optional and NO validation is added, users can call the API with zero parameters:

```java
// ❌ BAD - No validation
@GetMapping
public ResponseEntity<?> list(
    @RequestParam(required = false) LocalDate date,
    @RequestParam(required = false) String name,
    @RequestParam(required = false) Long id) {

  return handleRequest(
    () -> service.findByFilters(date, name, id)  // Could receive ALL nulls!
  );
}
```

**Consequences:**
- Full table scan on database (performance disaster)
- PostgreSQL type inference errors with nullable parameters
- No clear error message for users
- Passes tests (H2) but fails in production (PostgreSQL)

### Solution: Require At Least One Filter

✅ **GOOD - Validation prevents empty queries:**

```java
@GetMapping
public ResponseEntity<?> list(
    @RequestParam(required = false) LocalDate date,
    @RequestParam(required = false) String name,
    @RequestParam(required = false) Long id) {

  return handleRequest(
    () -> FeatureValidator.validateFilters(date, name, id),  // ← Validation FIRST
    () -> {
      List<Feature> results = service.findByFilters(date, name, id);
      return FeaturePresenter.presentListV2(results);
    });
}
```

**Validator Implementation:**

```java
public static List<Error> validateFilters(
    LocalDate date,
    String name,
    Long id) {

  List<Error> errors = new ArrayList<>();

  // Require at least one filter parameter
  if (date == null && name == null && id == null) {
    errors.add(Error.builder()
      .setField("filters")
      .setMessage("At least one filter parameter is required (date, name, or id)")
      .build());
    return errors;
  }

  // Additional validation for specific parameters...
  return errors;
}
```

### Query Parameter Validation Checklist

When adding a controller with query parameters:

- [ ] **Are ALL parameters optional?** → Add "at least one required" validation
- [ ] **Date ranges?** → Validate: fromDate <= toDate, max range limit
- [ ] **Mutually exclusive params?** → Validate: only one group allowed
- [ ] **Page numbers?** → Validate: page >= 1
- [ ] **Enums?** → Validate: value is in allowed list
- [ ] **IDs?** → Validate: positive number
- [ ] **Lists?** → Validate: not empty, max size

### Common Validation Patterns

**1. At Least One Filter Required:**
```java
if (allParamsNull) {
  errors.add(Error.builder()
    .setField("filters")
    .setMessage("At least one filter parameter is required")
    .build());
}
```

**2. Date Range Validation:**
```java
if (fromDate != null && toDate != null) {
  if (fromDate.isAfter(toDate)) {
    errors.add(Error.builder()
      .setField("fromDate")
      .setMessage("fromDate cannot be after toDate")
      .build());
  }

  long days = ChronoUnit.DAYS.between(fromDate, toDate);
  if (days > MAX_RANGE_DAYS) {
    errors.add(Error.builder()
      .setField("fromDate,toDate")
      .setMessage("Date range cannot exceed " + MAX_RANGE_DAYS + " days")
      .build());
  }
}
```

**3. Mutually Exclusive Parameters:**
```java
if (date != null && (fromDate != null || toDate != null)) {
  errors.add(Error.builder()
    .setField("date,fromDate,toDate")
    .setMessage("Cannot use 'date' with 'fromDate'/'toDate'. Use one or the other")
    .build());
}
```

**4. Pagination Validation:**
```java
if (page != null && page < 1) {
  errors.add(Error.builder()
    .setField("page")
    .setMessage("Page number must be >= 1")
    .build());
}
```

### Validation Best Practices

**Why validate at controller:**
- Prevents expensive full table scans
- Catches type inference errors before reaching database
- Returns user-friendly 400 errors instead of 500 errors
- Works consistently across H2 (tests) and PostgreSQL (production)

## Mapper Pattern (HTTP Layer)

```java
public final class FeatureMapper {
  private FeatureMapper() {}

  // Domain → View (for responses)
  public static FeatureView toView(Feature domain) {
    if (domain == null) return null;
    return FeatureView.builder()
        .setId(domain.getId() != null ? domain.getId().toString() : null)
        .setName(domain.getName())
        .build();
  }

  // Request → Domain (for inputs)
  public static Feature toDomain(CreateRequest request) {
    if (request == null) return null;
    return Feature.builder()
        .setName(request.getName())
        .build();
  }
}
```

- Final class with private constructor
- All methods static
- Always null-check inputs
- Convert Integer IDs to String for views

## Presenter Pattern

```java
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public class FeaturePresenter {

  public static ResponseEntity<HttpResponseV2<FeatureView, ErrorViewV2>> presentCreatedV2(
      Feature domain) {
    FeatureView view = FeatureMapper.toView(domain);
    HttpResponseSuccessV2<FeatureView, ErrorViewV2> response = HttpResponseSuccessV2
        .<FeatureView, ErrorViewV2>builder()
        .setData(view)
        .build();
    return new ResponseEntity<>(response, HttpStatus.CREATED);
  }

  public static ResponseEntity<HttpResponseV2<FeatureView, ErrorViewV2>> presentSuccessV2(
      Feature domain) {
    // ... HttpStatus.OK
  }

  public static ResponseEntity<HttpResponseV2<FeatureView, ErrorViewV2>> presentNotFoundV2() {
    HttpResponseSuccessV2<FeatureView, ErrorViewV2> response = HttpResponseSuccessV2
        .<FeatureView, ErrorViewV2>builder()
        .build();
    return new ResponseEntity<>(response, HttpStatus.NOT_FOUND);
  }
}
```

- Static utility class
- Use V2 methods: `presentCreatedV2`, `presentSuccessV2`, `presentNotFoundV2`
- Status codes: 201 (created), 200 (success), 404 (not found)

## Service Pattern

```java
@Service
@RequiredArgsConstructor
public class FeatureService {

  private final FeatureRepository repository;

  public Feature create(String userHash, ...) {
    FeatureEntity entity = FeatureEntity.builder()
        .setUserHash(userHash)  // ownership
        .build();
    FeatureEntity saved = repository.save(entity);
    return FeatureMapper.toModel(saved);
  }

  public Optional<Feature> getDetails(String userHash, Integer id) {
    return repository.findByIdAndUserHashAndDeletedAtIsNull(id, userHash)
        .map(FeatureMapper::toModel);
  }

  @Transactional
  public Feature update(String userHash, Integer id, ...) {
    FeatureEntity entity = repository
        .findByIdAndUserHashAndDeletedAtIsNull(id, userHash)
        .orElseThrow(() -> new IllegalArgumentException("Not found"));
    // update fields...
    return FeatureMapper.toModel(repository.save(entity));
  }
}
```

- Constructor injection via `@RequiredArgsConstructor`
- Always pass `userHash` for ownership verification
- Use `findBy...AndUserHashAndDeletedAtIsNull` for secure queries
- Use `@Transactional` for multi-step operations

## Repository Pattern

```java
public interface FeatureRepository extends CrudRepository<FeatureEntity, Integer> {
  Optional<FeatureEntity> findByIdAndUserHashAndDeletedAtIsNull(Integer id, String userHash);
  List<FeatureEntity> findAllByUserHashAndDeletedAtIsNull(String userHash);
}
```

- Extend `CrudRepository<Entity, IdType>`
- Include `UserHash` in queries for ownership
- Include `DeletedAtIsNull` for soft-delete support

## Security Checklist (Public Endpoints)

For user-owned resources accessed via public endpoints:

- [ ] Controller has `@Authenticated` annotation
- [ ] Controller extracts `userHash` from `kongAuthentication.getUserHash()`
- [ ] Service receives `userHash` as parameter
- [ ] Repository queries include `AndUserHashAndDeletedAtIsNull`
- [ ] No direct ID-only lookups for user-owned resources

Note: Internal endpoints skip `userHash` checks as they access all resources.

## Request/Response DTOs

**Request** (`module-http/models/requests/`):
```java
@Getter
@Setter
public class CreateRequest {
  private String name;
  private LocalDate startDate;
  private List<ItemDraft> items;  // nested DTOs
}
```

**Response View** (`module-http/models/responses/`):
```java
@Getter
@Builder(setterPrefix = "set")
public class FeatureView {
  private String id;        // String, not Integer
  private String name;
  private List<ItemView> items;
}
```

- Request DTOs: `@Getter @Setter`
- Response Views: `@Getter @Builder(setterPrefix = "set")`
- IDs as String in views, Integer internally

## Test Patterns

**Controller Test** (integration):
```java
@SpringBootTest
@ContextConfiguration(classes = HttpApplication.class)
@ActiveProfiles("test")
@AutoConfigureMockMvc
class FeatureControllerTest {

  @Autowired private MockMvc mockMvc;

  private MockHttpServletRequestBuilder withAuth(MockHttpServletRequestBuilder builder) {
    return builder
        .header(Headers.X_USER_HASH, "test-user-hash")
        .header(Headers.X_USER_ID_HASH, "test-user-id-hash")
        .header(Headers.X_AUTH_STATUS, String.valueOf(HttpStatus.OK.value()));
  }

  @Test
  void create_success() throws Exception {
    mockMvc.perform(withAuth(post(ENDPOINT)
        .contentType(MediaType.APPLICATION_JSON)
        .content(payload)))
        .andExpect(status().isCreated())
        .andExpect(jsonPath("$.data.id", notNullValue()));
  }
}
```

**Service Test** (unit with mocks):
```java
@ExtendWith(MockitoExtension.class)
class FeatureServiceTest {

  @Mock private FeatureRepository repository;
  @InjectMocks private FeatureService service;

  @Test
  void getDetails_found() {
    when(repository.findByIdAndUserHashAndDeletedAtIsNull(1, "user-hash"))
        .thenReturn(Optional.of(entity));
    Optional<Feature> result = service.getDetails("user-hash", 1);
    assertThat(result).isPresent();
  }
}
```