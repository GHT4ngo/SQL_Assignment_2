/*
    WWI_DW validation suite
    -----------------------
    Run after SQL_1_Assignment_2_Christofer_Lindholm.sql.
    Each assertion throws immediately when an invariant is violated.
*/

USE WWI_DW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- Required objects ---------------------------------------------------------
IF (
    SELECT COUNT(*)
    FROM sys.tables AS t
    JOIN sys.schemas AS s ON s.schema_id = t.schema_id
    WHERE s.[name] = 'dbo'
      AND t.[name] IN (
          'FactSales', 'DimCustomer', 'DimSalesPerson',
          'DimProduct', 'DimDate', 'HistoryLog'
      )
) <> 6
    THROW 51001, 'Missing one or more required warehouse tables.', 1;

IF OBJECT_ID('dbo.CreateTables', 'P') IS NULL
   OR OBJECT_ID('dbo.PopulateTables', 'P') IS NULL
   OR OBJECT_ID('dbo.UpdateTables', 'P') IS NULL
    THROW 51002, 'Missing one or more required stored procedures.', 1;

IF OBJECT_ID('dbo.GetCustomerHash', 'IF') IS NULL
   OR OBJECT_ID('dbo.GetSalesPersonHash', 'IF') IS NULL
   OR OBJECT_ID('dbo.GetProductHash', 'IF') IS NULL
    THROW 51003, 'Missing one or more required hash functions.', 1;

-- Uniqueness ---------------------------------------------------------------
IF EXISTS (
    SELECT CustomerID
    FROM dbo.DimCustomer
    WHERE IsCurrent = 1
    GROUP BY CustomerID
    HAVING COUNT(*) > 1
)
    THROW 51010, 'DimCustomer has duplicate current business keys.', 1;

IF EXISTS (
    SELECT SalesPersonID
    FROM dbo.DimSalesPerson
    WHERE IsCurrent = 1
    GROUP BY SalesPersonID
    HAVING COUNT(*) > 1
)
    THROW 51011, 'DimSalesPerson has duplicate current business keys.', 1;

IF EXISTS (
    SELECT SKUNumber
    FROM dbo.DimProduct
    WHERE IsCurrent = 1
    GROUP BY SKUNumber
    HAVING COUNT(*) > 1
)
    THROW 51012, 'DimProduct has duplicate current business keys.', 1;

IF EXISTS (
    SELECT OrderLineID
    FROM dbo.FactSales
    GROUP BY OrderLineID
    HAVING COUNT(*) > 1
)
    THROW 51013, 'FactSales has duplicate OrderLineID values.', 1;

IF EXISTS (
    SELECT DimTable, LogID
    FROM dbo.HistoryLog
    GROUP BY DimTable, LogID
    HAVING COUNT(*) > 1
)
    THROW 51014, 'HistoryLog has duplicate dimension business keys.', 1;

-- SCD2 validity ------------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM dbo.DimCustomer
    WHERE ValidFrom > ValidTo
       OR (IsCurrent = 1 AND ValidTo <> '9999-12-31')
)
    THROW 51020, 'DimCustomer contains an invalid validity interval.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.DimSalesPerson
    WHERE ValidFrom > ValidTo
       OR (IsCurrent = 1 AND ValidTo <> '9999-12-31')
)
    THROW 51021, 'DimSalesPerson contains an invalid validity interval.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.DimProduct
    WHERE ValidFrom > ValidTo
       OR (IsCurrent = 1 AND ValidTo <> '9999-12-31')
)
    THROW 51022, 'DimProduct contains an invalid validity interval.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.DimCustomer AS a
    JOIN dbo.DimCustomer AS b
      ON b.CustomerID = a.CustomerID
     AND b.CustomerKey > a.CustomerKey
     AND a.ValidFrom < b.ValidTo
     AND b.ValidFrom < a.ValidTo
)
    THROW 51023, 'DimCustomer contains overlapping SCD2 intervals.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.DimSalesPerson AS a
    JOIN dbo.DimSalesPerson AS b
      ON b.SalesPersonID = a.SalesPersonID
     AND b.SalesPersonKey > a.SalesPersonKey
     AND a.ValidFrom < b.ValidTo
     AND b.ValidFrom < a.ValidTo
)
    THROW 51024, 'DimSalesPerson contains overlapping SCD2 intervals.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.DimProduct AS a
    JOIN dbo.DimProduct AS b
      ON b.SKUNumber = a.SKUNumber
     AND b.ProductKey > a.ProductKey
     AND a.ValidFrom < b.ValidTo
     AND b.ValidFrom < a.ValidTo
)
    THROW 51025, 'DimProduct contains overlapping SCD2 intervals.', 1;

-- Referential integrity ---------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM dbo.FactSales AS f
    LEFT JOIN dbo.DimCustomer AS d ON d.CustomerKey = f.CustomerKey
    WHERE d.CustomerKey IS NULL
)
    THROW 51030, 'FactSales contains an orphaned CustomerKey.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.FactSales AS f
    LEFT JOIN dbo.DimSalesPerson AS d ON d.SalesPersonKey = f.SalesPersonKey
    WHERE d.SalesPersonKey IS NULL
)
    THROW 51031, 'FactSales contains an orphaned SalesPersonKey.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.FactSales AS f
    LEFT JOIN dbo.DimProduct AS d ON d.ProductKey = f.ProductKey
    WHERE d.ProductKey IS NULL
)
    THROW 51032, 'FactSales contains an orphaned ProductKey.', 1;

IF EXISTS (
    SELECT 1
    FROM dbo.FactSales AS f
    LEFT JOIN dbo.DimDate AS d ON d.DateKey = f.DateKey
    WHERE d.DateKey IS NULL
)
    THROW 51033, 'FactSales contains an orphaned DateKey.', 1;

-- Source alignment ---------------------------------------------------------
IF EXISTS (
    SELECT 1
    FROM dbo.DimSalesPerson AS d
    LEFT JOIN WideWorldImporters.[Application].People AS p
      ON p.PersonID = d.SalesPersonID
     AND p.IsSalesperson = 1
    WHERE d.IsCurrent = 1
      AND p.PersonID IS NULL
)
    THROW 51040, 'A current DimSalesPerson row is not an active source salesperson.', 1;

IF EXISTS (
    SELECT 1
    FROM WideWorldImporters.Sales.Customers AS s
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.DimCustomer AS d
        WHERE d.CustomerID = s.CustomerID AND d.IsCurrent = 1
    )
)
    THROW 51041, 'A source customer has no current dimension row.', 1;

IF EXISTS (
    SELECT 1
    FROM WideWorldImporters.Warehouse.StockItems AS s
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.DimProduct AS d
        WHERE d.SKUNumber = s.StockItemID AND d.IsCurrent = 1
    )
)
    THROW 51042, 'A source product has no current dimension row.', 1;

-- Stable-source rerun ------------------------------------------------------
DECLARE @BeforeFactCount BIGINT = (SELECT COUNT_BIG(*) FROM dbo.FactSales);
DECLARE @BeforeCustomerCount BIGINT = (SELECT COUNT_BIG(*) FROM dbo.DimCustomer);
DECLARE @BeforeSalesPersonCount BIGINT = (SELECT COUNT_BIG(*) FROM dbo.DimSalesPerson);
DECLARE @BeforeProductCount BIGINT = (SELECT COUNT_BIG(*) FROM dbo.DimProduct);

EXEC dbo.UpdateTables;
EXEC dbo.PopulateTables;

IF @BeforeFactCount <> (SELECT COUNT_BIG(*) FROM dbo.FactSales)
   OR @BeforeCustomerCount <> (SELECT COUNT_BIG(*) FROM dbo.DimCustomer)
   OR @BeforeSalesPersonCount <> (SELECT COUNT_BIG(*) FROM dbo.DimSalesPerson)
   OR @BeforeProductCount <> (SELECT COUNT_BIG(*) FROM dbo.DimProduct)
    THROW 51050, 'A stable-source rerun inserted unexpected rows.', 1;

PRINT 'PASS: all WWI_DW validation checks succeeded.';
