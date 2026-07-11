---
triggers: ["@Transactional", "transaction", "REQUIRES_NEW", "propagation", "TransactionTemplate"]
---
# Transaction Boundaries - Master Reference

**CRITICAL: Database connections are precious. Never hold them during external operations.**

## 🚨 The Core Rule (Memorize This)

**@Transactional = Database operations ONLY. Everything else = OUTSIDE.**

**⚠ Self-invocation trap:** you cannot split a transaction by calling a `@Transactional` method on `this`. Spring AOP only intercepts calls that cross the proxy (i.e. come from another bean), and the annotation is ignored on non-public methods. A same-class `this.updateInTransaction(...)` call runs with **no transaction at all**, silently. So the two ways to split are:

1. **`TransactionTemplate`**, works within the same class (preferred for the orchestration patterns below).
2. **`@Transactional` on a separate `@Service` bean**, works only for genuine cross-bean calls.

See `coding-conventions.md` § AOP Annotation Placement for the general rule.

```java
// ❌ WRONG - Holds DB connection for 15+ seconds
@Transactional(noRollbackFor = {ApiException.class})
public void pollStatus(Integer id) {
    for (int i = 0; i < 3; i++) {
        Thread.sleep(5000);  // Holds connection!
        StatusData status = api.getStatus(id);
        repository.update(status);
    }
}

// ❌ ALSO WRONG - same-class call to a @Transactional method is NOT proxied → no transaction
public void pollStatus(Integer id) {
    for (int i = 0; i < 3; i++) {
        Thread.sleep(5000);
        StatusData status = api.getStatus(id);
        updateInTransaction(status);   // this.updateInTransaction(), annotation ignored
    }
}
@Transactional
private void updateInTransaction(StatusData status) { repository.update(status); }

// ✅ CORRECT - TransactionTemplate opens a real transaction from within the same class
public void pollStatus(Integer id) {
    for (int i = 0; i < 3; i++) {
        Thread.sleep(5000);  // No connection held
        StatusData status = api.getStatus(id);
        transactionTemplate.execute(txStatus -> {
            repository.update(status);
            return null;
        });
        if (isTerminal(status)) break;
    }
}
```

## ❌ NEVER Do These Inside @Transactional

1. **API calls** - RestClient, WebClient, Feign, external HTTP clients
2. **Thread.sleep()** - Blocks thread while holding connection
3. **File I/O** - Reading/writing files, S3 operations
4. **Queue operations** - Message queue publish/consume
5. **Long computations** - Anything >100ms execution time

**If you need any of these: split using `TransactionTemplate` (same class) or a separate `@Service` bean, never a self-called `@Transactional` method (see the self-invocation trap above).**

## ✅ The Safe Pattern (Use Every Time)

```java
// Main method (NO @Transactional) - orchestration only.
// transactionTemplate is injected (@RequiredArgsConstructor), same-class splitting, real transactions.
public void businessLogic(Integer id) {
    // 1. Quick read transaction
    DataObject data = transactionTemplate.execute(txStatus ->
        repository.findById(id).orElseThrow());

    // 2. External operations (no transaction)
    ExternalResult result = externalApi.process(data);
    Thread.sleep(1000);  // If needed

    // 3. Quick write transaction
    transactionTemplate.execute(txStatus -> {
        Entity entity = repository.findById(id).orElseThrow();
        entity.setResult(result);
        repository.save(entity);
        return null;
    });
}
```

> Need read-only semantics? Configure a second `TransactionTemplate` bean with `setReadOnly(true)`, or call a `@Transactional(readOnly = true)` method **on a separate bean**. A `readOnly` annotation on a self-called private method has no effect (see the self-invocation trap above).

## 🎯 Before-Writing Checklist

Ask yourself before ANY `@Transactional` method:

1. **Does it call `*Api` classes?** → ❌ Split out
2. **Does it have `Thread.sleep()`?** → ❌ Split out
3. **Does it do file/queue operations?** → ❌ Split out
4. **Will it take >100ms?** → ❌ Split out
5. **Is it >30 lines?** → ❌ Split out

**If ANY yes: Refactor into orchestration + helper methods.**

## 📋 Patterns for Common Scenarios

### Pattern 1: Polling Loop
```java
public void poll(Integer id) {
    for (int i = 0; i < 3; i++) {
        Thread.sleep(5000);
        StatusData status = api.getStatus(id);
        transactionTemplate.execute(txStatus -> {
            repository.update(status);
            return null;
        });
        if (isTerminal(status)) break;
    }
}
```

### Pattern 2: Batch Processing
```java
@Service
@RequiredArgsConstructor
public class BatchProcessor {
    private final TransactionTemplate transactionTemplate;

    public void processBatch(List<Data> items) {
        int count = 0;
        for (Data item : items) {
            transactionTemplate.execute(status -> {
                repository.save(toEntity(item));
                return null;
            });

            if (++count % 20 == 0) Thread.sleep(100);
        }
    }
}
```


## 🚩 Red Flags During Code Review

Immediately flag these patterns:

- `@Transactional` method calls `*Api` class
- `@Transactional` method has `Thread.sleep()`
- `@Transactional(noRollbackFor = ...)` - often indicates external operations
- `@Transactional` method >30 lines - likely contains non-DB logic
- **`@Transactional`/`@Cacheable` on a `private`/package-private method, or invoked via `this.` from the same class**, annotation is silently ignored (no transaction/cache). Use `TransactionTemplate` or a separate bean.

**Action: Request refactoring to split transaction boundaries.**

## 📚 Why This Matters

**Problem:** Long transactions hold database connections
**Impact:** Connection pool exhaustion → slow performance → cascading failures
**Solution:** Keep transactions short and DB-focused

**Remember: Transactions are for databases, not workflows.**
