---
alwaysApply: false
triggers: ["seed", "backfill", "migrate", "one-off", "batch job"]
---
## Seed Jobs vs One-Off Data Migrations, Name and Catalog Them Separately

### Rule

A `seed*` job is reserved for populating **persistent, system-owned reference data or metadata that the system re-derives on a recurring, re-runnable basis**, reference-data syncs, regenerated catalog/browse data, lookup tables, local test fixtures. A seed represents an **ongoing capability**: it is expected to be re-run.

Fixing or backfilling **existing historical or user data** is **not** a seed. It is a **one-time migration/backfill**: it runs once against real data and then becomes dead weight.

Name and categorize the two separately:

- A one-off historical-data fix must be named `backfill*` / `migrate*`, **never** `seed*`.
- Document it under a distinct **"one-off migrations"** heading, **not** in the recurring seed-jobs catalog, and note that it is **removable after its single production run**.
- The runner mechanism is the same and correct for both categories (a batch-job entrypoint guarded by a job-name switch, or the project's equivalent). **Only the naming and catalog placement differ.**

### Why

Mislabeling a one-off backfill as a seed implies an ongoing capability, lets it linger permanently in the seed catalog, and risks it being swept into any routine "re-run all seeds" operation long after the data is already captured. Keeping the two categories distinct keeps the job catalog honest about what is a permanent capability versus a spent migration.

### When This Applies

- Any backend that runs seed jobs and/or one-off data backfills through a batch-job or command-runner entrypoint.
- This concerns **data-population/backfill jobs**, which is distinct from schema/DDL migration files (versioned schema changes), those follow the project's schema-migration rule.
