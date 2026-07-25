# Wide World Importers Data Warehouse

> This project has moved to
> [`sql-assignments/assignment-02-data-warehouse`](https://github.com/GHT4ngo/sql-assignments/tree/main/assignment-02-data-warehouse).
> This repository is retained as a read-only archive.

A SQL Server ETL assignment that builds a small star-schema warehouse from
Microsoft's `WideWorldImporters` sample database. It loads sales facts, maintains
three Slowly Changing Dimension Type 2 (SCD2) dimensions, and keeps a generated
calendar dimension.

## What the project demonstrates

- Dimensional modelling with surrogate keys
- Incremental and idempotent fact loading
- SCD2 history for customers, salespeople, and products
- Hash-based source-change detection
- Filtered unique indexes enforcing one current dimension row
- Transactional ETL with automatic rollback on failure
- Referential-integrity and rerun validation

## Requirements

- SQL Server 2016 or later
- The `WideWorldImporters` sample database
- Permission to create the `WWI_DW` database and its objects
- A client that supports `GO`, such as SQL Server Management Studio or
  Azure Data Studio

## Files

| File | Purpose |
| --- | --- |
| `SQL_1_Assignment_2_Christofer_Lindholm.sql` | Creates and runs the warehouse ETL |
| `tests.sql` | Runs integrity and idempotency checks |

## Warehouse model

```text
                         FactSales
                /            |            \
       DimCustomer   DimSalesPerson   DimProduct
                \            |            /
                           DimDate
```

`FactSales` has one row per Wide World Importers order line. `OrderLineID` is
unique and provides the incremental-load boundary.

The three descriptive dimensions use surrogate keys and retain history:

| Column | Meaning |
| --- | --- |
| `ValidFrom` | Timestamp at which this version became effective |
| `ValidTo` | Timestamp at which it stopped being effective |
| `IsCurrent` | `1` for the active version, otherwise `0` |

Current rows use `9999-12-31` as the open-ended `ValidTo` value. Filtered unique
indexes guarantee that each business key has at most one current version.

## ETL design

The script creates three stored procedures:

### `dbo.CreateTables`

Creates the fact table, dimensions, tracking table, indexes, and foreign keys.
The script calls it only when none of the six warehouse tables exist. If the
schema is only partly created, the script prints a clear message and skips the
load instead of attempting an unsafe partial rebuild.

### `dbo.UpdateTables`

Processes existing business keys before new facts are loaded:

1. Calculate deterministic SHA-256 hashes from the source attributes.
2. Expire current rows whose attributes changed.
3. Insert a current version for changed or restored members.
4. Refresh stored hashes.
5. Expire members no longer present in the applicable source set.

Only people with `IsSalesperson = 1` participate in `DimSalesPerson`. A person
who loses that status is expired; a later promotion restores a current version.

### `dbo.PopulateTables`

Loads new business keys, their initial hashes, missing calendar dates, and new
order-line facts. Temporary indexed key maps resolve source business keys to
current warehouse surrogate keys.

Both update and population phases use a transaction. If a phase fails, its
changes are rolled back, a readable SQL Server message is printed, and the
procedure returns `1`. A successful procedure returns `0`.

## Execution order

Run the main script from a SQL Server client:

```text
SQL_1_Assignment_2_Christofer_Lindholm.sql
```

It performs this sequence automatically:

1. Create `WWI_DW` if needed.
2. Select `WWI_DW` as the active database.
3. Create or update procedures and hash functions.
4. Create the warehouse tables when the schema is absent.
5. Apply SCD2 changes to existing members.
6. Load new members, dates, and facts.

The update phase precedes fact loading so newly inserted facts resolve to the
dimension versions current at load time.

For a scheduled refresh after installation, execute:

```sql
USE WWI_DW;
GO

EXEC dbo.UpdateTables;
EXEC dbo.PopulateTables;
```

## Validation

After the main script finishes, run `tests.sql` in the same SQL Server instance.
It checks:

- required tables, procedures, and functions
- duplicate current dimension members
- duplicate facts and tracking rows
- invalid SCD2 validity intervals
- orphaned fact foreign keys
- current salesperson eligibility
- source coverage for active business keys
- repeat-run idempotency when the source is unchanged

The separate validation script stops on the first failed assertion and prints a
success message when every check passes.

## Operational notes

### Reruns

The ETL is designed for repeated execution. Existing `OrderLineID` values are
not inserted again, and unchanged dimensions do not receive new versions.

### Partial schema

If only some required warehouse tables exist, the main script prints an
explanation and skips the load. This protects existing data from an ambiguous
automatic repair. Restore the missing object deliberately or recreate the
incomplete development database.

### Hashes

`HistoryLog` stores one SHA-256 hash per dimension business key. Attribute values
are length-delimited before hashing so different value boundaries cannot produce
the same input string through simple concatenation ambiguity.

### SCD2 timestamps

Validity columns use `DATETIME2(0)`. Each procedure captures one timestamp per
run, ensuring all changes in that atomic phase share the same boundary.

### Historical fact interpretation

Facts store the surrogate dimension keys resolved when they are loaded. They
therefore retain the associated dimension version even after a later SCD2
change. Do not add `IsCurrent = 1` when querying historical facts unless the
analysis intentionally excludes older dimension versions.

## Example queries

Current customers:

```sql
SELECT CustomerID, CustomerName, CustomerCategoryName
FROM WWI_DW.dbo.DimCustomer
WHERE IsCurrent = 1;
```

Customer history:

```sql
SELECT CustomerID, CustomerName, CustomerCategoryName,
       ValidFrom, ValidTo, IsCurrent
FROM WWI_DW.dbo.DimCustomer
WHERE CustomerID = 123
ORDER BY ValidFrom;
```

Sales with the dimension versions stored on each fact:

```sql
SELECT
    d.[Date],
    c.CustomerName,
    sp.EmployeeFullName,
    p.ProductName,
    f.Quantity,
    f.UnitPrice,
    f.Sales
FROM WWI_DW.dbo.FactSales AS f
JOIN WWI_DW.dbo.DimDate AS d
  ON d.DateKey = f.DateKey
JOIN WWI_DW.dbo.DimCustomer AS c
  ON c.CustomerKey = f.CustomerKey
JOIN WWI_DW.dbo.DimSalesPerson AS sp
  ON sp.SalesPersonKey = f.SalesPersonKey
JOIN WWI_DW.dbo.DimProduct AS p
  ON p.ProductKey = f.ProductKey;
```

## Scope

This is an educational warehouse implementation. It intentionally focuses on
clear SQL Server dimensional-loading patterns rather than orchestration,
deployment automation, or enterprise-scale partition management.

## Author

Christofer Lindholm — Data Engineering DE25, assignment 2.
