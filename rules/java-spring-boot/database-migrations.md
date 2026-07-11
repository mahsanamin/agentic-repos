---
alwaysApply: false
triggers: ["V[0-9].*[.]sql", "CREATE TABLE", "ALTER TABLE", "flyway", "@Entity", "@Table"]
---
## Database Migrations (Flyway)

### Overview
Database migrations use Flyway with version-based migration files. Migrations are executed in lexicographic order and are immutable once deployed.

### Location
`module-migrator/src/main/resources/db/migration/`

### Versioning Strategy

#### Major Versions: `V1.X__Description.sql`
Use for creating new tables or major schema changes (new features).

**Format**: `V1.{next}__Description.sql`

**Examples**:
- `V1.0__CreateOrders.sql` - Creates orders table
- `V1.6__CreateOrderCustomers.sql` - Creates order_customers table
- `V1.34__CreateProducts.sql` - Creates products table

**When to use**:
- Creating a new table
- Major feature requiring multiple table changes
- Significant architectural changes

**One Table Per Migration File (Strict)**:
Each `CREATE TABLE` statement MUST live in its own migration file. Never combine multiple table definitions in a single file, even when the tables are closely related (e.g., parent + child, entity + translations).

```sql
-- ❌ BAD: Two tables in one file (V1.2__CreateTierRulesAndThresholds.sql)
CREATE TABLE IF NOT EXISTS public.tier_rules (...);
CREATE TABLE IF NOT EXISTS public.tier_rule_thresholds (...);

-- ✅ GOOD: Each table gets its own migration
-- V1.2__CreateTierRules.sql
CREATE TABLE IF NOT EXISTS public.tier_rules (...);

-- V1.3__CreateTierRuleThresholds.sql
CREATE TABLE IF NOT EXISTS public.tier_rule_thresholds (...);
```

**Why**: Separate files make it easy to track when each table was created, simplify dependency management, keep diffs clean, and allow sub-version patches (V1.X.Y) to target a specific table unambiguously. Indexes and constraints for a table belong in the same file as its `CREATE TABLE` or in a sub-version of that migration.

**Finding next version**:
```bash
# List all versions sorted
ls module-migrator/src/main/resources/db/migration/ | grep -E "^V[0-9]" | sort -V | tail -1
# If sort -V is unavailable (macOS), use:
ls module-migrator/src/main/resources/db/migration/ | grep -E "^V[0-9]" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1

# Next version is the highest + 1
# If highest is V1.33, use V1.34
```

#### Sub-Versions: `V1.X.Y__Description.sql`
Use for changes related to a table or feature introduced in V1.X, or for inserting migrations between existing versions.

**Format**: `V1.{major}.{minor}__Description.sql`

**Examples**:
- `V1.6.1__AddCustomerSearchIndexes.sql` - Adds indexes to order_customers (created in V1.6)
- `V1.0.1__AddPackageNotesColumn.sql` - Adds column to orders (created in V1.0)
- `V1.34.1__AddProductsCarrierIndex.sql` - Adds index to products (created in V1.34)

**When to use**:
- Adding columns to an existing table
- Adding/removing indexes on an existing table
- Adding/removing constraints on an existing table
- Altering column types on an existing table
- Inserting a migration between existing versions (e.g., V1.23.1 will run before V1.24)

**Guidelines**:
- Use the major version number of the table's creation migration if known
- If the table was created in V1.6, use V1.6.1, V1.6.2, V1.6.3, etc. for related changes
- If unsure which version created the table, use the next available sub-version slot
- Sub-versions allow inserting migrations without renumbering existing ones

### Naming Convention

**Format**: `V{version}__{Description}.sql`

**Rules**:
1. **Version**:
   - Major: `V1.X` (e.g., V1.34)
   - Sub: `V1.X.Y` (e.g., V1.34.1)
   - Use double underscore `__` between version and description
2. **Description**:
   - PascalCase (e.g., `CreateProducts`, `AddCarrierIndex`)
   - No spaces (use PascalCase instead)
   - Be descriptive and concise
   - Start with verb: `Create`, `Add`, `Remove`, `Alter`, `Update`, `Drop`

**Good Examples**:
- ✅ `V1.34__CreateProducts.sql`
- ✅ `V1.34.1__AddProductsCarrierIndex.sql`
- ✅ `V1.0.1__AddPackageNotesColumn.sql`
- ✅ `V1.6.2__AlterCustomerDocumentTypeToVarchar.sql`

**Bad Examples**:
- ❌ `V1.34_CreateProducts.sql` (single underscore)
- ❌ `V1.34__create_products.sql` (snake_case)
- ❌ `V1.34__partner products table.sql` (spaces)
- ❌ `V1.34__Products.sql` (no verb)

### Migration Content Guidelines

#### 1. Always Use `IF NOT EXISTS` / `IF EXISTS`
Migrations should be safe to re-run during development.

```sql
-- Good
CREATE TABLE IF NOT EXISTS public.products (...);
CREATE INDEX IF NOT EXISTS idx_products_carrier_id ON public.products(carrier_id);
ALTER TABLE IF EXISTS public.orders ADD COLUMN IF NOT EXISTS notes TEXT;

-- Bad
CREATE TABLE public.products (...);
CREATE INDEX idx_products_carrier_id ON public.products(carrier_id);
```

#### 2. Always Specify Schema
Use `public` schema explicitly.

```sql
-- Good
CREATE TABLE public.products (...);

-- Bad
CREATE TABLE products (...);
```

#### 3. Include Comments
Add comments explaining the purpose and context.

```sql
-- Add indexes for a partner products API query performance
-- These indexes support filtering by carrier_id, arrival_date, and departure_date
CREATE INDEX IF NOT EXISTS idx_products_carrier_id
    ON public.products(carrier_id);
```

#### 4. Indexes

**CRITICAL: Only Create Indexes When Actually Needed**

❌ **DO NOT** create indexes "just in case" or for completeness
✅ **DO** create indexes ONLY when you have a specific query that needs them

**When to Create an Index:**
1. **Foreign Key Used in Queries** - You query FROM child TO parent
   ```sql
   -- ✅ NEEDED: We query "find all items for a package"
   CREATE INDEX idx_package_items_package_id ON order_items(order_id);

   -- ❌ NOT NEEDED: We never query "find packages with this item"
   -- DON'T create index on orders(latest_item_id)
   ```

2. **WHERE Clause Filtering** - Column appears in WHERE clause frequently
   ```sql
   -- ✅ NEEDED: Query filters by status
   -- SELECT * FROM orders WHERE status = 'PENDING'
   CREATE INDEX idx_packages_status ON orders(status);
   ```

3. **JOIN Operations** - Column used for joining tables
   ```sql
   -- ✅ NEEDED: Join condition uses this column
   -- JOIN products ON packages.arrival_product_id = products.id
   CREATE INDEX idx_packages_arrival_product_id ON orders(arrival_product_id);
   ```

4. **ORDER BY / Sorting** - Column used for sorting results
   ```sql
   -- ✅ NEEDED: Results ordered by creation date
   -- SELECT * FROM orders ORDER BY created_at DESC
   CREATE INDEX idx_packages_created_at ON orders(created_at);
   ```

**When NOT to Create an Index:**
1. ❌ **One-to-One Foreign Keys (Parent Side)** - Never query in reverse direction
2. ❌ **Low Cardinality Columns** - Boolean fields, status with 2-3 values (unless filtered heavily)
3. ❌ **Columns Never Used in Queries** - Just because a column exists doesn't mean it needs an index
4. ❌ **Write-Heavy Tables** - Every index slows down INSERT/UPDATE/DELETE operations

**Example - Latest Request Pattern:**
```sql
-- Table A has: latest_b_id (FK to Table B)
-- This means: A → B (parent to child reference)
-- Query pattern: "Get package's latest request" (package → request)
-- Do we query "Find all packages with this request"? NO!
-- Conclusion: NO INDEX NEEDED on latest_b_id

-- ❌ BAD (unnecessary index):
CREATE INDEX idx_packages_latest_request ON orders(latest_document_generate_request_id);

-- ✅ GOOD (index on the reverse FK - child to parent):
CREATE INDEX idx_document_requests_package_id ON document_generate_requests(order_id);
```

**Guidelines:**
- Add indexes in the same migration file as table creation OR in a sub-version migration
- Use `IF NOT EXISTS` to avoid errors on re-runs
- Name indexes descriptively: `idx_{table}_{columns}` or `idx_{table}_on_{columns}`
- **Document why each index is needed** in migration comments

**Index Creation Examples:**

```sql
-- ✅ GOOD: We query document requests by package
-- Query: SELECT * FROM document_generate_requests WHERE order_id = ?
CREATE INDEX IF NOT EXISTS idx_document_requests_package_id
    ON public.document_generate_requests(order_id);

-- ✅ GOOD: Composite index for common query
-- Query: SELECT * FROM products WHERE product_id = ? AND product_type = ?
CREATE INDEX IF NOT EXISTS idx_products_composite
    ON public.products(product_id, product_type);

-- ✅ GOOD: Unique constraint (enforces data integrity + provides index)
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_on_ref
    ON public.orders(ref);
```

#### 5. Constraints
- Name constraints explicitly for easier management
- Use `CONSTRAINT` keyword with descriptive names

```sql
-- Unique constraint (idempotent, PostgreSQL has no ADD CONSTRAINT IF NOT EXISTS)
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'uk_product_id_type') THEN
    ALTER TABLE public.products ADD CONSTRAINT uk_product_id_type UNIQUE (product_id, product_type);
  END IF;
END $$;

-- Foreign key constraint
ALTER TABLE public.order_items
    ADD CONSTRAINT fk_package_items_package
    FOREIGN KEY (order_id)
    REFERENCES public.orders(id);

-- Check constraint
ALTER TABLE public.orders
    ADD CONSTRAINT chk_package_dates
    CHECK (departure_date >= arrival_date);
```

#### 6. Default Values and Timestamps
Use database-level defaults for timestamps.

```sql
created_at TIMESTAMP NOT NULL DEFAULT NOW(),
updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
deleted_at TIMESTAMP
```

### Handling Dependencies and Constraints

#### Problem: Clean Migrations Breaking
When running clean migrations (dropping all tables and re-creating), foreign key constraints can cause issues if tables are dropped in the wrong order.

#### Solution: Use Sub-Versions for Dependent Changes

**Example Scenario**:
- V1.0 creates `orders` table
- V1.6 creates `order_items` table with FK to `orders`
- Later need to add a column to `orders` that references `order_items`

**Bad Approach** (will break clean migrations):
```sql
-- V1.0.1__AddLastItemIdToOrders.sql
ALTER TABLE public.orders
    ADD COLUMN last_item_id BIGINT,
    ADD CONSTRAINT fk_packages_last_item
    FOREIGN KEY (last_item_id) REFERENCES public.order_items(id);
```
This breaks because V1.0.1 runs BEFORE V1.6, so `order_items` doesn't exist yet!

**Good Approach** (safe for clean migrations):
```sql
-- V1.6.1__AddLastItemIdToOrders.sql
ALTER TABLE public.orders
    ADD COLUMN IF NOT EXISTS last_item_id BIGINT;

-- PostgreSQL has no ADD CONSTRAINT IF NOT EXISTS, use idempotent DO block
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_packages_last_item') THEN
    ALTER TABLE public.orders ADD CONSTRAINT fk_packages_last_item
      FOREIGN KEY (last_item_id) REFERENCES public.order_items(id);
  END IF;
END $$;
```
Using V1.6.1 ensures this runs AFTER V1.6, when `order_items` already exists.

**Guidelines for Dependent Changes**:
1. If adding FK constraint from Table A → Table B:
   - If Table B was created in V1.X, use V1.X.Y or later for the constraint
   - This ensures Table B exists before the constraint is added
2. If modifying a table that has dependencies:
   - Consider impact on tables that reference it
   - Use sub-versions to maintain execution order
3. If unsure:
   - Test clean migration locally: `./gradlew :module-migrator:flywayClean :module-migrator:flywayMigrate`
   - Verify all tables, constraints, and indexes are created without errors

### Testing Migrations

#### Local Testing
```bash
# Clean and re-run all migrations (destructive - drops all tables)
./gradlew :module-migrator:flywayClean :module-migrator:flywayMigrate

# Run migrations (apply new ones only)
./gradlew :module-migrator:flywayMigrate

# Show migration status
./gradlew :module-migrator:flywayInfo

# Validate migrations
./gradlew :module-migrator:flywayValidate
```

#### Pre-Commit Checklist
Before committing a new migration:
1. ✅ Test clean migration: `flywayClean` then `flywayMigrate`
2. ✅ Verify all indexes are created
3. ✅ Verify all constraints work
4. ✅ Test that dependent migrations still work
5. ✅ Update entity classes if schema changed
6. ✅ Update repository queries if needed
7. ✅ Run application tests to ensure compatibility

### Troubleshooting

#### Migration Failed - How to Fix?
1. **Never modify a migration file that has been run** (Flyway checksums will fail)
2. If migration failed locally:
   - Fix the SQL in the migration file
   - Run `flywayClean` to drop all tables
   - Run `flywayMigrate` to re-run all migrations
3. If migration failed in production:
   - Create a new migration file to fix the issue
   - Use `flywayRepair` if needed (consult with team first)

#### Constraint Violation on Clean Migration?
- Check execution order (Flyway runs migrations in lexicographic order)
- Ensure dependent tables exist before adding foreign keys
- Use sub-versions (V1.X.Y) to control order
- Test with: `./gradlew :module-migrator:flywayClean :module-migrator:flywayMigrate`

#### How to Insert Migration Between Existing Versions?
Use sub-versions:
- If you have V1.23 and V1.24, create V1.23.1 to run between them
- V1.23.1 will execute AFTER V1.23 but BEFORE V1.24
