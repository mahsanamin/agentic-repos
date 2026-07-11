---
triggers: ["MetricsCollectionService", "MetricsEvent", "metricsCollectionService"]
requires: "MetricsCollectionService"
---
# Metrics Collection

> **Infrastructure-dependent rule.** This documents a concrete in-house pattern (a
> `MetricsCollectionService` facade with per-entity collectors). It is installed **only when the
> target repo already contains that facade**, the installer probes for the `requires:` symbol
> above and skips this file otherwise (see `setup.md` Step 9, "Infrastructure-dependent rules").
> Installing it into a repo that lacks the facade would instruct Claude to call code that does not
> exist. If your project wants this pattern, build the facade first, then re-run install/upgrade.

## Pattern

```java
metricsCollectionService.collect(SomeMetricsEvent.builder()
    .eventType(SomeMetricsEvent.EventType.SOME_ACTION)
    .errorKey(errorKey)  // null = success, enum value = failure
    .build());
```

## Key Concepts

- **EventType**: Noun describing the metric, not verb (e.g., `PAYMENT_CAPTURE` not `PAYMENT_CAPTURED`)
- **ErrorKey**: null for success, enum value for failure reason (enums ensure low cardinality and prevent typos)
- **success attribute**: Derived automatically (null errorKey → true, non-null → false)

This structure allows filtering by `success:false` and grouping by `error_key` to see failure breakdown per event type in Datadog.

## Architecture

| Component | Purpose |
|-----------|---------|
| `MetricsCollectionService` | Facade - inject this to collect metrics |
| `OrderMetricsCollector` | Handles `OrderMetricsEvent` (example - use your entity) |
| `CustomerDocumentMetricsCollector` | Handles `CustomerDocumentMetricsEvent` |

Separate collectors per model allow different attributes and helper methods to grow independently.

## Event Models

| Model | Use For |
|-------|---------|
| `OrderMetricsEvent` | Package lifecycle events (example - adapt to your domain) |
| `CustomerDocumentMetricsEvent` | Document processing per customer |

## Adding New Metrics

1. **Update event model** - add new EventType/ErrorKey to existing model, or create new model if different domain
2. **Update/create collector** - if new model, create a collector and register in `MetricsCollectionService`
3. **Call `metricsCollectionService.collect()`** at the right place

## Example: Package Metrics

```java
// Success
// Example from an example service - use your event type
metricsCollectionService.collect(OrderMetricsEvent.builder()
    .eventType(OrderMetricsEvent.EventType.BOOKING_COMPLETION)
    .errorKey(null)
    .build());

// Failure
// Example from an example service - use your event type
metricsCollectionService.collect(OrderMetricsEvent.builder()
    .eventType(OrderMetricsEvent.EventType.BOOKING_COMPLETION)
    .errorKey(OrderMetricsEvent.ErrorKey.BOOKINGS_ALL_FAILED)
    .build());
```

## Example Events

**OrderMetricsEvent** (example - adapt to your entity):

| EventType | ErrorKey | success |
|-----------|----------|---------|
| `BOOKING_COMPLETION` | null | true |
| `BOOKING_COMPLETION` | `BOOKINGS_ALL_FAILED` | false |
| `PAYMENT_CAPTURE` | `PAYMENT_CAPTURE_REJECTED` | false |

**CustomerDocumentMetricsEvent**:

| EventType | ErrorKey | success |
|-----------|----------|---------|
| `DOCUMENT_PROCESSING` | null | true |
| `DOCUMENT_PROCESSING` | `FILE_SIZE_EXCEEDED` | false |

See event model classes for full list.
