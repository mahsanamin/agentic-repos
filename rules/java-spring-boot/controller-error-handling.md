---
triggers: ["@ExceptionHandler", "@ControllerAdvice", "@RestController", "ResponseEntity", "throw new", "@GetMapping", "@PostMapping"]
---
# Error Handling

## Architecture

Error handling follows a three-layer pattern. Services signal errors by throwing the base framework's `BaseApiException` subclasses. Controllers stay clean, no try/catch for business errors. The global `@ControllerAdvice` handler catches all exceptions and returns standardized responses.

```text
Service Layer                    → throws BadRequestException, ResourceNotFoundException, etc.
       ↓ (exception bubbles up)
Controller Layer                 → no try/catch needed, stays clean
       ↓ (exception bubbles up)
BaseControllerExceptionHandler   → catches, returns HttpResponseFailure with correct HTTP status
```

Our `ControllerExceptionHandler` extends the base framework's `BaseControllerExceptionHandler`, which already handles all `BaseApiException` subclasses.

---

## Exception Mapping

Use the right exception for the situation:

| Situation | Exception | HTTP Status |
|---|---|---|
| Resource not found (DB lookup returned empty) | `ResourceNotFoundException` | 404 |
| Business rule violation (invalid state, validation failure) | `BadRequestException` | 400 |
| Duplicate resource (already exists) | `DuplicateResourceException` | 409 |
| Resource permanently removed | `ResourceGoneException` | 410 |
| Internal failure | `InternalServerErrorException` | 500 |

All exceptions are in `com.example.framework.core.exceptions` and extend `BaseApiException`.

---

## Service Layer Pattern

Services throw exceptions with descriptive messages. The message reaches the API consumer as-is.

```java
// CORRECT, throw BaseApiException subclasses from service layer
public OrderEntity createOrder(String userId, int itemId, ...) {
    ItemEntity item = itemService.getItemById(itemId)
        .orElseThrow(() -> new ResourceNotFoundException("Item not found: " + itemId));

    if (!item.isAvailable()) {
        throw new BadRequestException("Item " + itemId + " is not available for ordering");
    }
    // ... business logic
}
```

For frequently used lookups, add throwing convenience methods:

```java
public UserEntity getUser(String userHash) {
    return userRepository.findByUserHash(userHash)
        .orElseThrow(() -> new ResourceNotFoundException(
            "User not found: " + userHash));
}
```

Keep `Optional`-returning methods for internal service-to-service use where empty is a valid outcome (not an error).

---

## Controller Layer Pattern

Controllers call services directly. No try/catch for business errors.

```java
// CORRECT, clean controller, no error handling needed
return handleRequest(
    () -> validateRequest(request),
    () -> {
        OrderEntity order = orderService.createOrder(
            request.getUserHash(), request.getItemId(), ...);
        return OrderPresenter.presentCreated(order);
    }
);
```

---

## Anti-Patterns

**NEVER catch service exceptions in controllers to build error responses:**

```java
// WRONG, manual error handling in controller
catch (IllegalStateException e) {
    HttpResponseFailureV2<OrderView, ErrorViewV2> response = HttpResponseFailureV2
        .<OrderView, ErrorViewV2>builder()
        .setMessage("Cannot create order")
        .setError(errorView)
        .build();
    return new ResponseEntity<>(response, HttpStatus.BAD_REQUEST);
}
```

**NEVER throw generic Java exceptions from service layer:**

```java
// WRONG, generic exceptions bypass the global handler
throw new IllegalStateException("User is already enrolled");
throw new IllegalArgumentException("Resource not found");
```

**NEVER use `HttpResponseSuccessV2` for error responses:**

```java
// WRONG, semantic violation
HttpResponseSuccessV2.builder().setStatus("not_found").build();
```

**NEVER write `presentNotFound()` / `presentConflict()` methods in presenters.**
Presenters are for success responses only. Error responses come from the global exception handler.

---

## Error Response Format

The `BaseControllerExceptionHandler` returns `HttpResponseFailure`:

```json
{
  "success": false,
  "message": "Resource not found: WG123456",
  "errorCode": 404
}
```

The `message` field is the exception message from the service layer, write clear, user-facing messages.
