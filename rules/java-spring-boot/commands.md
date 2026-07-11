---
alwaysApply: false
triggers: ["@Scheduled", "Tasklet", "JobBuilder", "StepBuilder", "Spring Batch", "JobLauncher"]
---
## Commands

## 🚨 CRITICAL: Transaction Boundaries for Command Services

**Command services must use TransactionTemplate, not @Transactional.**

**Key rules:**
1. API calls → OUTSIDE transactions
2. Thread.sleep() → OUTSIDE transactions
3. Batch processing → TransactionTemplate with one transaction per item

**Pattern:** Fetch externally → Process → Save in transactions

**See the Command Service Best Practices section below for complete patterns.**

### Gradle Commands

#### Check Style
Run Checkstyle and validations without running tests.

```bash
./gradlew clean check -x test --no-daemon
```

#### Tests (all modules - force run)
Run all tests across all modules. **IMPORTANT:** Use `--rerun-tasks` to force tests to actually run. Without this flag, Gradle caches test results and may skip tests even when code has changed.

```bash
./gradlew test --rerun-tasks --no-daemon
```

#### Tests (targeted)
Run a specific test class or pattern in a module.

```bash
./gradlew :<module>:test --tests "<pattern>" --no-daemon
```

## CommandLineRunner Tasks (module-commands)

### Overview
CommandLineRunner tasks are batch processing jobs in the `module-commands` module, triggered via Airflow scheduler with `spring.job-name` parameter.

### Pattern

```java
package com.example.app.commands.tasks;

import lombok.RequiredArgsConstructor;
import lombok.extern.log4j.Log4j2;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * Command-line task for [describe purpose].
 * Triggered via Airflow with spring.job-name=[taskName].
 *
 * <p>This task handles:
 * <ol>
 *   <li>[First responsibility]</li>
 *   <li>[Second responsibility]</li>
 * </ol>
 */
@Log4j2
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(name = "spring.job-name", havingValue = "[taskName]")
public class [TaskName]Task implements CommandLineRunner {

  private final [ServiceName] service;

  /**
   * Execute the [task name] task.
   * Delegates to [ServiceName] for the actual business logic.
   *
   * @param args Command line arguments (not used)
   * @throws Exception if task fails
   */
  @Override
  public void run(String... args) throws Exception {
    log.info("Starting [TaskName] task...");
    service.executeTaskLogic();
    log.info("[TaskName] task completed.");
  }
}
```

### Conventions

1. **Location**: `module-commands/src/main/java/com/example/app/commands/tasks/`
2. **Naming**: `[PascalCase]Task.java` (e.g., `SyncPartnerProductsTask`)
3. **Annotations**:
   - `@Log4j2` for logging
   - `@Component` to register as Spring bean
   - `@RequiredArgsConstructor` for constructor injection
   - `@ConditionalOnProperty(name = "spring.job-name", havingValue = "[taskName]")` for conditional execution
4. **Dependencies**: Inject service layer classes from `module-server` (never put business logic in task)
5. **Javadoc**: Document purpose, triggering mechanism, and responsibilities
6. **Logging**: Log start and completion of task
7. **Exception Handling**: Let exceptions bubble up (Spring Boot will handle and log them)
8. **Service Layer Requirements**: Command services MUST follow database best practices (see below)

### Examples

- `SyncCountryMappingsTask` - Syncs country mappings from Place Services and a partner APIs
- `SyncSupportServicesTask` - Syncs support services from a partner API
- `PostPaymentProcessorTask` - Processes packages after payment authorization

### Running Locally

Run a specific task by passing the job name with config location:

```bash
./gradlew :module-commands:bootRun --args='--spring.job-name={taskName} --spring.config.location=file:/absolute/path/to/project/config/application.yml' --no-daemon
```

**IMPORTANT:** You MUST use an absolute path for `spring.config.location`. Relative paths and shell expansion like `$(pwd)` do NOT work inside `--args` because the shell doesn't expand them.

### Testing

Write unit tests for the service layer logic, not the task itself. Tasks are simple wrappers that delegate to services.

## Command Service Best Practices

### Overview

Command services (services called by CommandLineRunner tasks) process large datasets and perform batch operations. To avoid database overload and ensure data integrity, they MUST follow these patterns:

### 1. Use TransactionTemplate for Database Operations

**Why:** Prevents long-running transactions, allows fine-grained transaction control, and ensures proper rollback on errors.

**Pattern:**

```java
@Service
@RequiredArgsConstructor
@Log4j2
public class SyncExampleService {

  private final ExampleRepository repository;
  private final TransactionTemplate transactionTemplate;  // ← REQUIRED

  public void syncData(List<DataDto> data) {
    for (DataDto dto : data) {
      // Wrap each database operation in a transaction
      Boolean success = transactionTemplate.execute(status -> {
        try {
          // Database operations here
          repository.save(entity);
          return true;
        } catch (Exception e) {
          status.setRollbackOnly();  // ← Ensure transaction rolls back
          log.error("Error syncing record", e);
          return false;
        }
      });
    }
  }
}
```

**Key Points:**
- Inject `TransactionTemplate` via constructor (uses `@RequiredArgsConstructor`)
- Wrap EACH database operation in `transactionTemplate.execute()`
- Keep transactions short (one record at a time, not batch)
- Handle exceptions inside the transaction lambda
- Call `status.setRollbackOnly()` in catch block to ensure rollback
- Return success/failure boolean for tracking

**Don't Do:**
```java
// ❌ Bad: Single long-running transaction
@Transactional
public void syncData(List<DataDto> data) {
  for (DataDto dto : data) {
    repository.save(entity);  // Holds transaction for entire loop
  }
}

// ❌ Bad: API calls OR sleep inside @Transactional
@Transactional
public void syncFromApi() {
  List<DataDto> data = externalApi.fetchAll();  // Holds connection!
  Thread.sleep(100);  // Holds connection!
}
```

### 2. Sleep Periodically to Avoid Database Overload

**Why:** Prevents database overload and connection pool exhaustion.

**Pattern:**
```java
private static final int SLEEP_AFTER_RECORDS = 20;  // Typical value
private static final long SLEEP_DURATION_MS = 100;  // Typical value

int recordCount = 0;
for (DataDto dto : dataList) {
  transactionTemplate.execute(status -> {
    try {
      repository.save(entity);
      return true;
    } catch (Exception e) {
      status.setRollbackOnly();
      log.error("Error saving record", e);
      return false;
    }
  });

  recordCount++;

  if (recordCount % SLEEP_AFTER_RECORDS == 0) {
    try {
      Thread.sleep(SLEEP_DURATION_MS);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new RuntimeException("Thread interrupted", e);
    }
  }
}
```

**Rules:**
- Sleep after every N records (typically 20), not after every record
- Use 100ms sleep duration (good balance)
- Handle `InterruptedException` properly (restore interrupt flag)

### 3. Combine Both Patterns

**Flow:** Fetch externally → Process in loop → TransactionTemplate per record → Sleep periodically

**Key points:**
- API calls OUTSIDE loop (fetch all data first)
- TransactionTemplate INSIDE loop (one transaction per record)
- Sleep after N records to prevent overload
- Per-record error handling (one failure doesn't stop entire job)

### Reference Examples

Look for existing sync services in the project's `module-commands` module for real-world examples of TransactionTemplate + periodic sleep patterns.
