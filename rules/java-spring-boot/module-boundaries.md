---
triggers: ["import com.example", "Entity", "Mapper", "toModel", "toEntity", "module-server", "module-http", "module-messages"]
---
# Module Boundaries

Strict rules for what each module can import and expose. These boundaries enforce the layered architecture (`http → server → messages`) and prevent entity leakage across layers.

**See `project-structure.md` for file placement. See `api-conventions.md` for the request flow.**

## The Core Rule

```
Entities NEVER leave module-server.
Models (module-messages) are the contract between all modules.
```

### What flows where

```
module-http                    module-server                module-messages
─────────────                  ─────────────                ───────────────
Request DTOs                   Entities (JPA)               Domain Models
Response Views                 Repositories                 Enums
HTTP Mappers                   Server Mappers               Shared Config
Presenters                     Services
Controllers                    Clients

Services accept and return Models (module-messages), never Entities.
```

## Boundary Rules

### 1. Entities are confined to module-server

Entities (`com.example.{project}.server.entities.*`) must NEVER be imported in `module-http`, `module-commands`, `module-migrator`, or `module-messages`. Inside `module-server` they are used only by repositories (query/persist), services (orchestrate), and server mappers (entity ↔ model).

**No entity reference escapes a service method's return type**, services convert to models before returning.

```java
// WRONG, service returns entity
public FeatureEntity getFeature(String userHash) {
  return repository.findByUserHash(userHash).orElseThrow();
}

// RIGHT, service returns model
public Optional<Feature> getFeature(String userHash) {
  return repository.findByUserHashAndDeletedAtIsNull(userHash)
      .map(FeatureMapper::toModel);
}
```

### 2. Request DTOs and Views are confined to module-http

Request DTOs (`...http.models.requests.*`) and Response Views (`...http.models.responses.*`) must NEVER be imported in `module-server`, `module-commands`, or `module-messages`. Gradle already enforces this (module-server doesn't depend on module-http), stating it explicitly prevents a future dependency change from breaking the boundary.

### 3. Models are the shared contract

Domain models in `module-messages` (`...messages.models.*`) are the only types that flow between modules:
- Pure POJOs, no JPA annotations, no HTTP annotations
- Immutable, `@Getter` + `@Builder(setterPrefix = "set")`
- The return type of all service methods; the input type for presenters and HTTP mappers

## Two-Mapper Pattern

Each layer has its own mapper with distinct responsibilities.

**Server Mapper** (`module-server/mappers/`), entity ↔ domain model, used only inside module-server:

```java
@NoArgsConstructor(access = AccessLevel.PRIVATE)
public class FeatureMapper {
  /** Entity → Domain model (for service return values). */
  public static Feature toModel(FeatureEntity entity) {
    if (entity == null) return null;
    return Feature.builder().setId(entity.getId()).setUserHash(entity.getUserHash()).build();
  }
  /** Domain model → Entity (for persistence). */
  public static FeatureEntity toEntity(Feature model) {
    if (model == null) return null;
    return FeatureEntity.builder().setUserHash(model.getUserHash()).build();
  }
}
```

**HTTP Mapper** (`module-http/mappers/{feature}/`), request DTO ↔ domain model ↔ response view, used only inside module-http. Naming: `{Feature}Mapper` (the module path already implies "HTTP", no `Http` suffix).

## Where Mapping Happens

| Conversion | Who | Where |
|------------|-----|-------|
| Entity → Model / Model → Entity | Server Mapper | inside Service methods |
| Request → Model | HTTP Mapper | in Controller (before service call) |
| Model → View | HTTP Mapper | in Presenter (after service returns) |

Mapping does **not** happen inline in services or controllers, they call the mapper. Services never build entities/models with inline `.builder()` calls.

## Violation Detection (for code review)

Red-flag imports:

```java
// In ANY file under module-http or module-commands:
import com.example.{project}.server.entities.*;     // VIOLATION: entity outside module-server

// In ANY file under module-server or module-commands:
import com.example.{project}.http.models.*;          // VIOLATION: request/view outside module-http
```

A service method returning an entity type (`FeatureEntity`, `List<FeatureEntity>`, `Optional<FeatureEntity>`) is **always** a violation, the return type must be the model.

## Severity

- Entity imported in module-http/commands → **BLOCKING**
- Service returns an entity type → **BLOCKING**
- Request/View imported in module-server → **BLOCKING**
- Mapping logic inline in a service or controller → **BLOCKING** (must use a mapper)
