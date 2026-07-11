---
alwaysApply: true
---

## Java Spring Boot Project Structure

**⚠️ NOTE:** This structure document uses examples from various projects. Package names (e.g., `com.example.app`), module names, and entity names are examples only. Adapt them to match your project's actual structure.

Use this as a current map for where to add or change things in a typical Java Spring Boot multi-module project.

### Modules Overview

- `module-server`: Core domain logic, services, entities, repositories, configurations, and business rules
- `module-http`: Spring Boot HTTP layer (REST controllers, presenters, mappers, validation, exception handling)
- `module-messages`: Shared DTOs, request/response models, business objects, enums, and configurations
- `module-migrator`: Database migration service using Flyway for PostgreSQL schema management
- `module-commands`: Command-line utilities and batch processing tasks for data migration and maintenance

### Top-Level Tooling & Support

- `config/`: Sample Spring Boot configuration files (application.yml.sample)
- `docker-compose*.yml`, `docker-utils.sh`: Docker orchestration for PostgreSQL, Memcached, and application services
- `style-guide/`: IDE code formatting configurations (Google Java Style for IntelliJ and Eclipse)
- `.github/workflows/`: CI/CD pipeline configuration and health check scripts
- `gradle/`, `gradlew*`: Gradle build system with wrapper for consistent builds

### Module Details

#### `module-server`

- Entry points: `ServerConfigurations` (Spring configuration class at `com.example.{project}.server.ServerConfigurations`)
- Package root: `src/main/java/com/example/{project}/server/`
- `configs/`: Application configuration classes (e.g., HttpClientConfigProperties)
- `entities/`: JPA entities for PostgreSQL. Use `@NoArgsConstructor(access = PROTECTED)`.
- `services/`: Business service layer. Use constructor injection with `@RequiredArgsConstructor`.
- `repositories/`: Spring Data JPA repositories extending `CrudRepository`. Include `UserHash` + `DeletedAtIsNull` in queries.
- `mappers/`: Entity ↔ Domain model transformations
- `utils/`: Utility classes
- `src/test/java/com/example/{project}/server/**`: Unit tests (JUnit 5 + Spring Boot Test); mirrors main package layout

#### `module-http`

- Entry point: `HttpApplication` at `com.example.{project}.http.HttpApplication` wires Spring Boot with OpenAPI documentation, caching, and scheduling
- Package root: `src/main/java/com/example/{project}/http/`
- `controllers/`: REST controllers using Spring MVC. HealthCheckController at root level. Authenticated controllers under `v1/`. Use `@RestController`, `@Tag` for OpenAPI.
- `presenters/`: Response presentation layer. Organize by feature.
- `mappers/`: HTTP-specific mappers for request/response transformation. Organize by feature.
- `models/`: HTTP layer models (requests/, responses/). Use `@Getter @Setter` for requests, `@Getter @Builder(setterPrefix = "set")` for views.
- `configs/`: HTTP-specific configurations (e.g., WebConfig)
- `validators/`: Custom validation logic returning `List<Error>`
- `src/test/java/com/example/{project}/http/**`: Controller and integration tests; leverage Spring Boot test utilities
- `src/test/resources/wiremock/`: WireMock mappings and response files for integration testing

#### `module-messages`

- Package root: `src/main/java/com/example/{project}/messages/`
- `MessagesConfigurations.java`: Spring configuration class at `com.example.{project}.messages.MessagesConfigurations`
- `models/{domain}/`: Domain models organized by business domain
- `models/{domain}/enums/`: Domain-specific enums
- Use immutable-style DTOs with Lombok `@Getter` + `@Builder(setterPrefix = "set")`.

#### `module-migrator`

- Entry point: `MigratorApplication` at `com.example.{project}.migrator.MigratorApplication` (Spring Boot application with transaction management)
- Package root: `src/main/java/com/example/{project}/migrator/`
- `src/main/resources/db/migration/`: Flyway SQL migration scripts following naming convention `V{version}__{description}.sql`
- Uses Flyway for PostgreSQL database schema management and data migrations

#### `module-commands`

- Entry point: `CommandApplication` at `com.example.{project}.commands.CommandApplication` (Spring Boot application for command-line operations)
- Package root: `src/main/java/com/example/{project}/commands/`
- `tasks/`: Batch processing tasks (placeholders for future background jobs)

### HTTP API (module-http)

- HTTP layer models organized under `module-http/src/main/java/com/example/{project}/http/models/` (requests/, responses/).
- Response views are feature-based DTOs. Use `@Getter` + `@Builder(setterPrefix = "set")`.
- HTTP-to-business mappers in `module-http/src/main/java/com/example/{project}/http/mappers/{feature}/`.
- Business-to-view transformation handled by presenters in `module-http/src/main/java/com/example/{project}/http/presenters/{feature}/`.

### Services, Repositories, Entities (module-server)

- Services: `services/`; feature-based organization. Prefer constructor injection (`@RequiredArgsConstructor`).
- Repositories: Spring Data JPA repositories under `repositories/` extending `CrudRepository`. Include `UserHash` + `DeletedAtIsNull` in queries.
- Entities: JPA entities under `entities/`. Avoid `@Data`; prefer `@Getter/@Setter` and `@Builder(setterPrefix = "set")`.
- Converters: AttributeConverters under `entities/converters/` for JSON fields.
- Mappers: Entity ↔ Domain transformations under `mappers/`.

### Configuration Management

- Spring Boot configuration in `module-http/src/main/resources/application.yml` with PostgreSQL, Flyway, and OpenAPI settings
- Environment-specific configurations handled through Spring profiles
- Database configuration for PostgreSQL with JPA/Hibernate
- Datadog and Sentry integration for monitoring

### Security & Exceptions

- Global exception handling in `module-http` using `@ControllerAdvice`
- Authentication using JWT tokens with `@Authenticated` annotation from the base framework
- Authorization checks in controllers using `KongAuthentication.getUserIdHash()`
- Validation using Bean Validation annotations and custom validators (CommonValidator)

### Database Migrations (Flyway)

- Migration scripts: `module-migrator/src/main/resources/db/migration/`
- Naming convention: `V{version}__{description}.sql`
- Prerequisites: PostgreSQL database via Docker; configuration in `application.yml`
- Commands: Run migrator application or use Flyway Gradle plugin
- Tips: Keep migrations idempotent, test against Docker DB before committing

### Testing

- Unit tests under `*/src/test/java` (JUnit 5, Spring Boot Test). Mirror package structure of main code.
- Integration tests using Spring Boot test slices (`@WebMvcTest`, `@DataJpaTest`, etc.)
- Test configuration files under `src/test/resources/`
- H2 database for testing (configured in test dependencies)

### Caching Strategy

- Redis integration for caching (RedisConfig)
- Cache annotations (`@Cacheable`) for service layer methods as needed

### Add/Update API Checklist

- **Controller**: add `*Controller` in `module-http/src/main/java/com/example/{project}/http/controllers` with Spring MVC annotations and OpenAPI documentation. Place admin/internal controllers under `v1/` subdirectory.
- **Models**: create HTTP models under `module-http/src/main/java/com/example/{project}/http/models/{feature}/` with validation. Organize by feature area (request, response).
- **Service**: add business logic in `module-server/src/main/java/com/example/{project}/server/services`; use constructor injection with `@RequiredArgsConstructor`
- **Repository**: add data access in `module-server/src/main/java/com/example/{project}/server/repositories`; follow standard Spring Data JPA naming convention
- **Entity**: add JPA entity in `module-server/src/main/java/com/example/{project}/server/entities` with proper Lombok annotations (`@NoArgsConstructor(access = PROTECTED)`)
- **Business Models**: add domain objects in `module-messages/src/main/java/com/example/{project}/messages/models/` organized by feature area
- **Presenter**: add response transformation in `module-http/src/main/java/com/example/{project}/http/presenters/{feature}/`
- **Mapper**: add transformation logic in `module-http/src/main/java/com/example/{project}/http/mappers/{feature}/` or `module-server/src/main/java/com/example/{project}/server/mappers/` as appropriate
- **Tests**: cover services, repositories, and controllers with appropriate test types in corresponding test directories
- **Migration**: add database schema changes via Flyway migrations in `module-migrator/src/main/resources/db/migration/`

### Dependency Management

- Uses Gradle multi-module build with Spring Boot dependency management
- Internal dependencies: app-core, app-ops, app-httpcore (internal libraries)
- External dependencies: Spring Boot, PostgreSQL, Memcached, Flyway, Jackson, Lombok, JUnit 5
- Module dependencies: http → server → messages (layered architecture)

#### Dependency Placement Rules

**Before adding any dependency, analyze its usage:**

1. **Common Dependencies** (used by 2+ modules or core framework):

   - Place in root `build.gradle` under `subprojects { dependencies { ... } }`
   - Examples: Spring Boot starters, Jackson, Lombok, JUnit, Apache Commons, OpenTelemetry
   - These are shared across all modules

2. **Module-Specific Dependencies** (used by only one module):

   - Place in the specific module's `build.gradle` (e.g., `module-server/build.gradle`)
   - Examples: PostgreSQL driver (module-server), Flyway (module-migrator), WireMock (module-http tests)
   - Keep dependencies scoped to where they're actually needed

3. **Version Management**:
   - **ALWAYS** define versions in `gradle.properties` file
   - Use property references in build.gradle: `${propertyName}`
   - Example: `implementation "org.postgresql:postgresql:${postgresqlVersion}"`
   - Never hardcode versions directly in build.gradle files
   - Follow existing naming convention: `{libraryName}Version` (e.g., `lombokVersion`, `postgresqlVersion`)

**Decision Flow:**

```
Is dependency used by multiple modules?
  → YES: Add to root build.gradle + version in gradle.properties
  → NO: Add to module build.gradle + version in gradle.properties
```

**Examples:**

- ✅ Common: `implementation "org.springframework.boot:spring-boot-starter-validation:${springBootStarterVersion}"` → root build.gradle
- ✅ Module-specific: `implementation "org.postgresql:postgresql:${postgresqlVersion}"` → module-server/build.gradle
- ✅ Version: `postgresqlVersion=42.7.4` → gradle.properties

### Docker & Deployment

- Multi-stage Docker build with Java 21 (eclipse-temurin:21-jre-alpine)
- Docker Compose setup for local development (PostgreSQL + Redis + Application)
- Datadog Java agent integration for monitoring
- Environment variable configuration for different deployment environments
- Health check endpoints for monitoring and deployment verification

### Localization

- Multi-language support using MessageSource and `.properties` files
- LocalizationResolver for runtime message lookup
- Phrase integration for translation management (.phrase.yml configuration)
- Translation files in `module-http/src/main/resources/language/` (messages.properties, messages_ar.properties)
- Makefile commands for pulling/cleaning translations
