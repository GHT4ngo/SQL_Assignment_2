# Wide World Importers Data Warehouse (WWI_DW)

A complete ETL solution that builds and maintains a star schema data warehouse from the WideWorldImporters source database, implementing SCD Type 2 for all dimensions with automated change detection and historical tracking.

## Overview

This SQL Server project creates a dimensional data warehouse (WWI_DW) with a fact table for sales data and four dimension tables. The system automatically detects changes in source data and maintains historical versions using Slowly Changing Dimension Type 2 (SCD2) logic.

## Features

- Automated database and table creation
- Star schema design with fact and dimension tables
- SCD Type 2 implementation for all dimensions
- Hash-based change detection using custom table functions
- Optimized indexing strategy for query performance
- Foreign key constraints for referential integrity
- Configurable index management for bulk operations
- Auto-scaling date dimension
- Historical tracking with ValidFrom, ValidTo, and IsCurrent columns

## Database Schema

### Fact Table

**FactSales**
- Sales transactions from WideWorldImporters
- Links to all dimension tables via surrogate keys
- Includes quantity, unit price, and total sales amount

### Dimension Tables

**DimCustomer**
- Customer information with category
- Tracks customer attribute changes over time

**DimSalesPerson**
- Sales employee information
- Maintains historical employee data

**DimProduct**
- Product catalog with SKU numbers
- Preserves product name changes

**DimDate**
- Calendar dimension for time-based analysis
- Auto-generates dates one year beyond latest order

### Supporting Tables

**HistoryLog**
- Stores row hashes for change detection
- Tracks last update timestamp for each dimension row

## Architecture

### Star Schema Structure
```
                    FactSales
                        |
        +---------------+---------------+
        |               |               |
   DimCustomer    DimSalesPerson   DimProduct
                        |
                     DimDate
```

### SCD Type 2 Implementation

Each dimension table includes:
- **ValidFrom**: Start date of the record version
- **ValidTo**: End date of the record version
- **IsCurrent**: Flag indicating active record (1 = current, 0 = historical)

When data changes:
1. Old record: `IsCurrent` set to 0, `ValidTo` updated to current date
2. New record: Inserted with `IsCurrent` = 1, `ValidFrom` = current date

## Stored Procedures

### 1. CreateTables

Creates the database schema including all tables, indexes, and foreign key constraints.

**Purpose:**
- Creates WWI_DW database if it doesn't exist
- Creates all dimension and fact tables
- Establishes indexes for performance optimization
- Sets up foreign key relationships

**Usage:**
```sql
EXEC dbo.CreateTables;
```

**Tables Created:**
- FactSales
- DimCustomer
- DimSalesPerson
- DimProduct
- DimDate
- HistoryLog

### 2. PopulateTables

Loads initial data from WideWorldImporters into the data warehouse.

**Purpose:**
- Populates dimension tables with current source data
- Loads fact table with sales transactions
- Initializes HistoryLog with row hashes
- Optional index management for large data loads

**Parameters:**
- `@DropIndex` (VARCHAR(3)): Controls index behavior during population
  - `'On'`: Drops and rebuilds indexes for better bulk insert performance
  - `'Off'`: Keeps indexes active (recommended for smaller datasets)

**Usage:**
```sql
-- For large data volumes
EXEC dbo.PopulateTables @DropIndex = 'On';

-- For small to medium data volumes
EXEC dbo.PopulateTables @DropIndex = 'Off';
```

**Process:**
1. Optionally drops non-unique indexes and foreign keys
2. Populates all dimension tables
3. Populates FactSales table
4. Initializes HistoryLog with row hashes
5. Rebuilds indexes and foreign keys if dropped

### 3. UpdateTables

Detects and processes changes in source data, maintaining SCD Type 2 history.

**Purpose:**
- Compares current source data against data warehouse
- Marks changed records as historical (IsCurrent = 0)
- Inserts new versions of changed records
- Handles deleted records by marking them inactive
- Updates HistoryLog with new hashes

**Usage:**
```sql
EXEC dbo.UpdateTables;
```

**Process for each dimension:**
1. Calculate hash of current source data
2. Compare with stored hash in HistoryLog
3. If changed:
   - Set `IsCurrent = 0` and `ValidTo = GETDATE()` on old record
   - Insert new record with `IsCurrent = 1`
   - Update HistoryLog with new hash
4. Mark deleted records as inactive

## Table Functions

Three hash calculation functions support change detection:

### dbo.GetCustomerHash()

Calculates hash values for customer records from WideWorldImporters.

**Returns:**
- CustomerID
- CustomerName
- CustomerCategoryName
- cHash (computed hash value)

### dbo.GetSalesPersonHash()

Calculates hash values for sales person records.

**Returns:**
- PersonID
- FullName
- sHash (computed hash value)

### dbo.GetProductHash()

Calculates hash values for product records.

**Returns:**
- StockItemID
- StockItemName
- pHash (computed hash value)

## Indexes and Constraints

### Performance Indexes

| Index Name | Table | Columns | Purpose |
|------------|-------|---------|---------|
| idx_FactSales_Key | FactSales | CustomerKey, SalesPersonKey, ProductKey, DateKey | Optimize fact table joins |
| idx_DimCustomer_Current | DimCustomer | CustomerID, IsCurrent | Fast current record lookup |
| idx_DimCustomer_Valid | DimCustomer | CustomerID, ValidFrom, ValidTo | Historical point-in-time queries |
| idx_DimSalesPerson_Current | DimSalesPerson | SalesPersonID, IsCurrent | Fast current record lookup |
| idx_DimSalesPerson_Valid | DimSalesPerson | SalesPersonID, ValidFrom, ValidTo | Historical queries |
| idx_DimProduct_Current | DimProduct | SKUNumber, IsCurrent | Fast current record lookup |
| idx_DimProduct_Valid | DimProduct | SKUNumber, ValidFrom, ValidTo | Historical queries |
| idx_DimDate_Date | DimDate | Date | Date filtering performance |
| idx_DimTable_LogID | HistoryLog | LogID, DimTable | Change detection performance |

### Unique Indexes

| Index Name | Table | Purpose |
|------------|-------|---------|
| Uidx_FactSales_OrderLineID | FactSales | Prevent duplicate sales records |
| Uidx_DimCustomer_Current | DimCustomer | Ensure only one current customer version |
| Uidx_DimSalesPerson_Current | DimSalesPerson | Ensure only one current salesperson version |
| Uidx_DimProduct_Current | DimProduct | Ensure only one current product version |

### Foreign Keys

| Constraint Name | From Table | To Table |
|-----------------|-----------|----------|
| FK_FactSales_Customer | FactSales | DimCustomer |
| FK_FactSales_SalesPerson | FactSales | DimSalesPerson |
| FK_FactSales_Product | FactSales | DimProduct |
| FK_FactSales_Date | FactSales | DimDate |

## Installation

### Prerequisites

- SQL Server 2016 or later
- WideWorldImporters database installed
- Permissions to create databases and execute stored procedures

### Setup Steps

1. Ensure WideWorldImporters database exists on your SQL Server instance

2. Execute the complete SQL script:
```sql
-- The script will automatically:
-- 1. Create WWI_DW database
-- 2. Create all tables and procedures
-- 3. Populate initial data
-- 4. Set up all indexes and constraints
```

3. Verify installation:
```sql
USE WWI_DW;
GO

-- Check tables exist
SELECT TABLE_NAME 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_TYPE = 'BASE TABLE';

-- Check row counts
SELECT 'FactSales' AS TableName, COUNT(*) AS RowCount FROM FactSales
UNION ALL
SELECT 'DimCustomer', COUNT(*) FROM DimCustomer
UNION ALL
SELECT 'DimSalesPerson', COUNT(*) FROM DimSalesPerson
UNION ALL
SELECT 'DimProduct', COUNT(*) FROM DimProduct
UNION ALL
SELECT 'DimDate', COUNT(*) FROM DimDate;
```

## Usage

### Initial Setup

Run the script once to create and populate the data warehouse:
```sql
-- Script executes automatically:
-- 1. Creates tables if needed
-- 2. Populates with initial data
-- 3. Updates based on source changes
```

### Regular Updates

For ongoing maintenance, execute only the populate and update procedures:
```sql
-- Daily/weekly ETL run
EXEC dbo.PopulateTables @DropIndex = 'Off';
EXEC dbo.UpdateTables;
```

### Large Data Loads

When expecting significant data volume:
```sql
-- Use index optimization for better performance
EXEC dbo.PopulateTables @DropIndex = 'On';
EXEC dbo.UpdateTables;
```

## Query Examples

### Get Current Customer Data
```sql
SELECT 
    CustomerID,
    CustomerName,
    CustomerCategoryName
FROM DimCustomer
WHERE IsCurrent = 1;
```

### Get Historical Customer Data at Specific Date
```sql
SELECT 
    CustomerID,
    CustomerName,
    CustomerCategoryName,
    ValidFrom,
    ValidTo
FROM DimCustomer
WHERE CustomerID = 123
  AND '2024-06-15' BETWEEN ValidFrom AND ValidTo;
```

### Sales Analysis with Current Dimensions
```sql
SELECT 
    c.CustomerName,
    sp.EmployeeFullName,
    p.ProductName,
    d.Date,
    f.Quantity,
    f.Sales
FROM FactSales f
JOIN DimCustomer c ON f.CustomerKey = c.CustomerKey AND c.IsCurrent = 1
JOIN DimSalesPerson sp ON f.SalesPersonKey = sp.SalesPersonKey AND sp.IsCurrent = 1
JOIN DimProduct p ON f.ProductKey = p.ProductKey AND p.IsCurrent = 1
JOIN DimDate d ON f.DateKey = d.DateKey
WHERE d.Date >= '2024-01-01';
```

### Point-in-Time Sales Analysis
```sql
-- Sales with dimension attributes as they were on a specific date
SELECT 
    c.CustomerName,
    sp.EmployeeFullName,
    p.ProductName,
    d.Date,
    f.Sales
FROM FactSales f
JOIN DimCustomer c 
    ON f.CustomerKey = c.CustomerKey 
    AND d.Date BETWEEN c.ValidFrom AND c.ValidTo
JOIN DimSalesPerson sp 
    ON f.SalesPersonKey = sp.SalesPersonKey 
    AND d.Date BETWEEN sp.ValidFrom AND sp.ValidTo
JOIN DimProduct p 
    ON f.ProductKey = p.ProductKey 
    AND d.Date BETWEEN p.ValidFrom AND p.ValidTo
JOIN DimDate d ON f.DateKey = d.DateKey
WHERE d.Date = '2024-06-15';
```

### Track Customer Changes Over Time
```sql
SELECT 
    CustomerID,
    CustomerName,
    CustomerCategoryName,
    ValidFrom,
    ValidTo,
    IsCurrent
FROM DimCustomer
WHERE CustomerID = 123
ORDER BY ValidFrom;
```

## Performance Considerations

### Index Management Strategy

**Small to Medium Datasets:**
- Use `@DropIndex = 'Off'`
- Keeps indexes active during population
- Acceptable performance impact for moderate volumes

**Large Datasets:**
- Use `@DropIndex = 'On'`
- Drops indexes before bulk insert
- Rebuilds indexes after population
- Significantly faster for large data volumes

### Date Dimension Auto-Scaling

The DimDate table automatically extends to cover:
- All historical dates in FactSales
- Future dates up to one year beyond the latest order date
- No manual maintenance required

### Change Detection Optimization

The HistoryLog table stores hashes to minimize comparison overhead:
- Only changed records trigger SCD2 updates
- Hash comparison is faster than full row comparison
- Reduces unnecessary dimension updates

## Maintenance

### Regular Tasks

**Daily/Weekly:**
```sql
EXEC dbo.PopulateTables @DropIndex = 'Off';
EXEC dbo.UpdateTables;
```

**Monthly (for performance):**
```sql
-- Rebuild indexes
ALTER INDEX ALL ON FactSales REBUILD;
ALTER INDEX ALL ON DimCustomer REBUILD;
ALTER INDEX ALL ON DimSalesPerson REBUILD;
ALTER INDEX ALL ON DimProduct REBUILD;

-- Update statistics
UPDATE STATISTICS FactSales;
UPDATE STATISTICS DimCustomer;
UPDATE STATISTICS DimSalesPerson;
UPDATE STATISTICS DimProduct;
```

### Monitoring

Check ETL execution status:
```sql
-- View HistoryLog updates
SELECT 
    DimTable,
    COUNT(*) AS RecordCount,
    MAX(TimeLog) AS LastUpdate
FROM HistoryLog
GROUP BY DimTable;

-- Check for inactive records
SELECT 
    'DimCustomer' AS TableName,
    COUNT(*) AS InactiveRecords
FROM DimCustomer WHERE IsCurrent = 0
UNION ALL
SELECT 'DimSalesPerson', COUNT(*) FROM DimSalesPerson WHERE IsCurrent = 0
UNION ALL
SELECT 'DimProduct', COUNT(*) FROM DimProduct WHERE IsCurrent = 0;
```

## Limitations and Notes

- Requires WideWorldImporters database to be present
- All procedures and functions must remain intact for proper operation
- DimDate automatically scales but requires UpdateTables execution
- Hash-based change detection may miss changes if hash collision occurs (extremely rare)
- SCD Type 2 causes dimension tables to grow over time
- Only handles inserts and updates; does not purge old historical data

## Troubleshooting

### Issue: Duplicate Key Errors

**Cause:** Unique indexes prevent duplicate current records

**Solution:** 
```sql
-- Check for duplicate current records
SELECT CustomerID, COUNT(*) 
FROM DimCustomer 
WHERE IsCurrent = 1 
GROUP BY CustomerID 
HAVING COUNT(*) > 1;

-- Manually fix duplicates if found
```

### Issue: Foreign Key Violations

**Cause:** Fact table references non-existent dimension keys

**Solution:**
```sql
-- Ensure dimensions are populated before facts
EXEC dbo.PopulateTables @DropIndex = 'Off';
```

### Issue: Slow Performance During Updates

**Cause:** Large dataset without index optimization

**Solution:**
```sql
-- Use index dropping for large loads
EXEC dbo.PopulateTables @DropIndex = 'On';
```

## Author

**Christofer Lindholm**
- Assignment: SQL_1_Assignment_2
- Course: DE25
- Date: 2025-11-16

## License

This project is part of an educational assignment. Please check with the author for usage rights.

## References

- [Star Schema Design](https://en.wikipedia.org/wiki/Star_schema)
- [Slowly Changing Dimensions](https://en.wikipedia.org/wiki/Slowly_changing_dimension)
- [SQL Server Indexing Best Practices](https://docs.microsoft.com/en-us/sql/relational-databases/indexes/)
