-- ===================================================================
-- =     Christofer Lindholm                 2025-11-16              =
-- =     SQL_1_Assignment_2                  DE25                    =
-- ===================================================================

/*
    Builds and refreshes WWI_DW from WideWorldImporters.

    Model:
      - FactSales at order-line grain
      - SCD2 dimensions for customer, salesperson, and product
      - Generated date dimension
      - HistoryLog hashes for change detection

    Refresh order matters: UpdateTables versions existing dimension members
    before PopulateTables resolves surrogate keys for new facts. Both phases
    are transactional and safe to rerun against an unchanged source.

    See README.md for architecture and operations, and tests.sql for executable
    integrity checks.
*/

PRINT '=== Starting ETL Run ===' ;

/*
==============================================================================
Step 1: Procedure to create database and tables if they don't exist
==============================================================================
*/

-- Create the database if it doesn't exist
IF NOT EXISTS (SELECT * FROM sys.databases WHERE [name] = 'WWI_DW')
BEGIN
    PRINT 'Creating Database WWI_DW' ;
    CREATE DATABASE WWI_DW ;
END
GO

USE WWI_DW;
GO


CREATE OR ALTER PROCEDURE dbo.CreateTables
AS

/*============================================================================

Purpose:
    - Creates tables in a star schema design. The procedure creates all dimension
      tables, the fact table, supporting indexes, and foreign key relationships.

Objects Created:
    1.1   FactSales
    1.2   DimCustomer
    1.3   DimSalesPerson
    1.4   DimProduct
    1.5   DimDate
    1.6   HistoryLog
    1.7   Foreign Keys

Notes:
    - Database WWI_DW must already exist.
    - Called only when the complete warehouse schema is absent.
    - Surrogate keys are used for all dimensions.
    - ValidFrom, ValidTo and IsCurrent is created to support SCD2 Logic

============================================================================*/

BEGIN
    -- ------------------------------------------------------------
    -- 1.1  Create FactSales table, added primary key, added OrderLineID to assist
    --      to prevent duplicates, also using the PrimaryKeys from DimTables instead of ID's
    -- ------------------------------------------------------------
    PRINT 'Creating Table FactSales' ;
    CREATE TABLE WWI_DW.dbo.FactSales (
        FactSalesKey             INT             NOT NULL IDENTITY(1,1) PRIMARY KEY
        ,CustomerKey             INT             NOT NULL
        ,SalesPersonKey          INT             NOT NULL
        ,ProductKey              INT             NOT NULL
        ,DateKey                 INT             NOT NULL
        ,OrderLineID             INT             NOT NULL
        ,Quantity                INT             NOT NULL
        ,UnitPrice               DECIMAL(18,2)   NOT NULL
        ,Sales                   DECIMAL(18,2)   NOT NULL
    );


    -- A Unique Index for making sure that the FactSales are Unique using OrderLineID
    CREATE UNIQUE INDEX Uidx_FactSales_OrderLineID
        ON WWI_DW.dbo.FactSales(OrderLineID);

    -- A Index for performance on factjoins
    CREATE INDEX idx_FactSales_Key
        ON WWI_DW.dbo.FactSales(CustomerKey, SalesPersonKey, ProductKey, DateKey);

    -- ------------------------------------------------------------
    -- 1.2  Create DimCustomer table, added a external PK and ValidFrom,
    --      ValidTo and IsCurrent to track changes
    -- ------------------------------------------------------------
    CREATE TABLE WWI_DW.dbo.DimCustomer (
        CustomerKey                 INT             NOT NULL    IDENTITY(1,1) PRIMARY KEY
        ,CustomerID                 INT             NOT NULL
        ,CustomerName               NVARCHAR(100)   NOT NULL
        ,CustomerCategoryName       NVARCHAR(50)
        ,ValidFrom                  DATETIME2(0)    NOT NULL    DEFAULT SYSDATETIME()
        ,ValidTo                    DATETIME2(0)    NOT NULL    DEFAULT '9999-12-31'
        ,IsCurrent                  BIT             NOT NULL    DEFAULT 1
    ) ;

    -- Creating Index to increase performance when searching for current data
    CREATE INDEX idx_DimCustomer_Current
        ON WWI_DW.dbo.DimCustomer(CustomerID, IsCurrent);

    -- Creating Index to increase performance when searching for a historical version at a specific date
    CREATE INDEX idx_DimCustomer_Valid
        ON WWI_DW.dbo.DimCustomer(CustomerID, ValidFrom, ValidTo);

    -- Creating a Unique Index to secure that only one copy of customers is current at the same time
    CREATE UNIQUE INDEX Uidx_DimCustomer_Current
        ON WWI_DW.dbo.DimCustomer (CustomerID)
        WHERE IsCurrent = 1;

    -- ------------------------------------------------------------
    -- 1.3  Create DimSalesPerson table, added a external PK and ValidFrom,
    --      ValidTo and IsCurrent to track changes
    -- ------------------------------------------------------------
    PRINT 'Creating Table DimSalesPerson' ;
    CREATE TABLE WWI_DW.dbo.DimSalesPerson (
        SalesPersonKey              INT             NOT NULL    IDENTITY(1,1) PRIMARY KEY
        ,SalesPersonID              INT             NOT NULL
        ,EmployeeLastName           NVARCHAR(50)
        ,EmployeeFullName           NVARCHAR(50)    NOT NULL
        ,ValidFrom                  DATETIME2(0)    NOT NULL    DEFAULT SYSDATETIME()
        ,ValidTo                    DATETIME2(0)    NOT NULL    DEFAULT '9999-12-31'
        ,IsCurrent                  BIT             NOT NULL    DEFAULT 1
    ) ;

    -- Creating Index to increase performance when searching for current data
    CREATE INDEX idx_DimSalesPerson_Current
        ON WWI_DW.dbo.DimSalesPerson(SalesPersonID, IsCurrent);

    -- Creating Index to increase performance when searching for a historical version at a specific date
    CREATE INDEX idx_DimSalesPerson_Valid
        ON WWI_DW.dbo.DimSalesPerson(SalesPersonID, ValidFrom, ValidTo);

    -- Creating a Uinque Index to secure that only one copy of SalesPerson is current at the same time
    CREATE UNIQUE INDEX Uidx_DimSalesPerson_Current
        ON WWI_DW.dbo.DimSalesPerson (SalesPersonID)
        WHERE IsCurrent = 1;

    -- ------------------------------------------------------------
    -- 1.4  Create DimProduct table, added a external PK aand ValidFrom,
    --      ValidTo and IsCurrent to track changes
    -- ------------------------------------------------------------
    PRINT 'Creating Table DimProduct' ;
    CREATE TABLE WWI_DW.dbo.DimProduct (
        ProductKey                  INT             NOT NULL    IDENTITY(1,1) PRIMARY KEY
        ,SKUNumber                  INT             NOT NULL
        ,ProductName                NVARCHAR(255)   NOT NULL
        ,ValidFrom                  DATETIME2(0)    NOT NULL    DEFAULT SYSDATETIME()
        ,ValidTo                    DATETIME2(0)    NOT NULL    DEFAULT '9999-12-31'
        ,IsCurrent                  BIT             NOT NULL    DEFAULT 1
    ) ;

    -- Creating Index to increase performance when searching for current data
    CREATE INDEX idx_DimProduct_Current
        ON WWI_DW.dbo.DimProduct(SKUNumber, IsCurrent);

    -- Creating Index to increase performance when searching for a historical version at a specific date
    CREATE INDEX idx_DimProduct_Valid
        ON WWI_DW.dbo.DimProduct(SKUNumber, ValidFrom, ValidTo);

    -- Creating a Uinque Index to secure that only one copy of products is current at the same time
    CREATE UNIQUE INDEX Uidx_DimProduct_Current
        ON WWI_DW.dbo.DimProduct (SKUNumber)
        WHERE IsCurrent = 1;


    -- ------------------------------------------------------------
    -- 1.5  Create DimDate table, changed PK name to maintain consistancy
    -- ------------------------------------------------------------
    PRINT 'Creating Table DimDate' ;
    CREATE TABLE WWI_DW.dbo.DimDate (
        DateKey                     INT         NOT NULL    PRIMARY KEY     -- date in the format YYYYMMDD
        ,[Date]                     DATE        NOT NULL                    -- date in the format YYYY-MM-DD
        ,[Year]                     SMALLINT    NOT NULL                    -- YYYY
        ,[Month]                    TINYINT     NOT NULL                    -- month as a number
        ,[MonthName]                VARCHAR(10) NOT NULL                    -- session-language month name
        ,[Weekday]                  TINYINT     NOT NULL                    -- weekday as a number
        ,[WeekdayName]              VARCHAR(10) NOT NULL                    -- session-language weekday name
        ,[Week]                     TINYINT     NOT NULL                    -- week number
        ,[Day]                      TINYINT     NOT NULL                    -- day of the month as a number
        ,[QuarterNumber]            TINYINT     NOT NULL                    -- quarter as a number
        ,[QuarterName]              VARCHAR(2)  NOT NULL                    -- quarter as text (Q1–Q4)
    ) ;

    -- Creating Date Index for performance
    CREATE INDEX idx_DimDate_Date
        ON WWI_DW.dbo.DimDate ([Date]);

    -- ------------------------------------------------------------
    -- 1.6  Create Tracking table, to track id's and changes in database
    -- ------------------------------------------------------------
    PRINT 'Creating Table HistoryLog' ;
    CREATE TABLE WWI_DW.dbo.HistoryLog (
        HistoryLogID                INT             NOT NULL IDENTITY(1,1) PRIMARY KEY
        ,DimTable                   TINYINT         NOT NULL
        ,LogID                      INT             NOT NULL
        ,RowHash                    VARBINARY(32)   NOT NULL
        ,TimeLog                    DATETIME2(0)    NOT NULL
        ,CONSTRAINT CK_HistoryLog_DimTable CHECK (DimTable IN (1, 2, 3))
    ) ;

    -- Creating Index for faster search
    CREATE UNIQUE INDEX idx_DimTable_LogID
        ON WWI_DW.dbo.HistoryLog (DimTable, LogID) ;

    -- ------------------------------------------------------------
    -- 1.7  Creating Foreign Keys connected between FactSales and the DimTables
    -- ------------------------------------------------------------

    -- Customer FK
    ALTER TABLE WWI_DW.dbo.FactSales
    ADD CONSTRAINT FK_FactSales_Customer
        FOREIGN KEY (CustomerKey)
        REFERENCES WWI_DW.dbo.DimCustomer(CustomerKey);

    -- SalesPerson FK
    ALTER TABLE WWI_DW.dbo.FactSales
    ADD CONSTRAINT FK_FactSales_SalesPerson
        FOREIGN KEY (SalesPersonKey)
        REFERENCES WWI_DW.dbo.DimSalesPerson(SalesPersonKey);

    -- Product FK
    ALTER TABLE WWI_DW.dbo.FactSales
    ADD CONSTRAINT FK_FactSales_Product
        FOREIGN KEY (ProductKey)
        REFERENCES WWI_DW.dbo.DimProduct(ProductKey);

    -- Date FK
    ALTER TABLE WWI_DW.dbo.FactSales
    ADD CONSTRAINT FK_FactSales_Date
        FOREIGN KEY (DateKey)
        REFERENCES WWI_DW.dbo.DimDate(DateKey);

END
GO


/*
==============================================================================
Step 2: Procedure to populate the tables, and add new rows
==============================================================================
*/

CREATE OR ALTER PROCEDURE dbo.PopulateTables
AS
/*============================================================================

Purpose:
    - Populates all dimension and fact tables in the WWI_DW database
      from the WideWorldImporters source database.

Procedure:
    - Loads new customers, salespeople, products, dates, and facts.
    - Records initial hashes for new dimension business keys.
    - Uses current-dimension key maps to resolve fact surrogate keys.

Tracking:
    - HistoryLog stores SHA2_256 hashes of source rows, used to detect
      new or changed dimension members
    - ValidFrom, ValidTo, and IsCurrent are used to track history
    - Dimtable tracks the different DimTables:  1 = DimCustomer
                                                2 = DimSalesPerson
                                                3 = DimProduct
Conditions:
    - Target tables must already exist

Hashbyte logic:
    - Tracked attributes are length-delimited and hashed with SHA2_256.

Temptable logic:
    - Temptables with unique indexes are made:

        #Customer_ID_Key
        #Salpesperson_ID_Key
        #Product_ID_Key

      They will include only ID and Key number and will only be made out of
      rows that have IsCurrent = 1. The indexes will ensure that the data in
      the temptables will only contain unique data.

      The temptables are made to make sure that unique data will populate the
      the FactSales table. It will also increase the performance of the insert.

Grain:
    - One row per OrderLine, Product, Customer, SalesPerson, Order Date

Notes:
    - Designed to be executed as often as needed
    - Inserts only new rows; existing facts are not duplicated

============================================================================*/

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @LoadTime DATETIME2(0) = SYSDATETIME();

    BEGIN TRY
        BEGIN TRANSACTION;

    -- ------------------------------------------------------------
    -- 2.10 Populate DimCustomer with new rows, also updates ValidTo/From and sets IsCurrent to 1
    --      Populating only rows that doesn't already have a existing CustomerID in DimCustomer
    -- ------------------------------------------------------------
    INSERT INTO WWI_DW.dbo.DimCustomer (
        CustomerID
        ,CustomerName
        ,CustomerCategoryName
        ,ValidFrom
        ,ValidTo
        ,IsCurrent
    )
    SELECT
        c.CustomerID
        ,c.CustomerName
        ,cc.CustomerCategoryName
        ,@LoadTime
        ,'9999-12-31'
        ,1

    FROM WideWorldImporters.Sales.Customers             AS c

    JOIN WideWorldImporters.Sales.CustomerCategories    AS cc
        ON c.CustomerCategoryID = cc.CustomerCategoryID

    WHERE NOT EXISTS (
        SELECT 1
        FROM WWI_DW.dbo.DimCustomer                     AS d
        WHERE d.CustomerID = c.CustomerID
    );

    PRINT 'Rows inserted into DimCustomer: ' + CAST(@@ROWCOUNT AS VARCHAR(15));

    -- ------------------------------------------------------------
    -- 2.11 Populate HistoryLog with the new rows in DimCustomer
    --      Hashbytes are used to assist in identifying if rows have changed
    --      Inserts only rows in HistoryLog that does'nt exist there using CustomerID
    -- ------------------------------------------------------------
    INSERT INTO WWI_DW.dbo.HistoryLog (
        DimTable
        ,LogID
        ,RowHash
        ,TimeLog
        )

    SELECT
        1 -- DimCustomer
        ,c.CustomerID
        ,HASHBYTES('SHA2_256', CONCAT(
            c.CustomerID, N'|',
            LEN(c.CustomerName), N':', c.CustomerName, N'|',
            LEN(cc.CustomerCategoryName), N':', cc.CustomerCategoryName
        ))
        ,@LoadTime

    FROM WideWorldImporters.Sales.Customers             AS c

    JOIN WideWorldImporters.Sales.CustomerCategories    AS cc
        ON c.CustomerCategoryID = cc.CustomerCategoryID

    WHERE NOT EXISTS (
        SELECT 1
        FROM WWI_DW.dbo.HistoryLog AS h
        WHERE h.DimTable    = 1  -- DimCustomer
          AND h.LogID       = c.CustomerID
    ) ;

    -- ------------------------------------------------------------
    -- 2.20 Populate DimSalesPerson with new rows, also updates ValidTo/From and sets IsCurrent to 1
    --      Populating only rows that doesn't already have a existing SalesPersonID in DimSalesPerson
    --      and have the flag IsSalesperson = 1 in WideWorldImportes
    -- ------------------------------------------------------------
    INSERT INTO WWI_DW.dbo.DimSalesPerson (
        SalesPersonID
        ,EmployeeLastName
        ,EmployeeFullName
        ,ValidFrom
        ,ValidTo
        ,IsCurrent
        )

    SELECT
        p.PersonID
        ,CASE
            WHEN CHARINDEX(' ', FullName) > 0
            THEN RIGHT(p.FullName, CHARINDEX(' ', REVERSE(FullName)) - 1)
            ELSE NULL
        END
        ,p.FullName
        ,@LoadTime
        ,'9999-12-31'
        ,1

    FROM WideWorldImporters.[Application].People        AS p

    WHERE p.IsSalesperson = 1
     AND NOT EXISTS (
         SELECT 1
         FROM WWI_DW.dbo.DimSalesPerson                 AS d
         WHERE d.SalesPersonID = p.PersonID
    );

    PRINT 'Rows inserted into DimSalesPerson: ' + CAST(@@ROWCOUNT AS VARCHAR(15)) ;

    -- ------------------------------------------------------------
    -- 2.21 Populate HistoryLog with the new rows in DimSalesPerson
    --      Hashbytes are used to assist in identifying if rows have changed
    --      Inserts only rows in HistoryLog that does'nt exist there using PersonID
    -- ------------------------------------------------------------
    INSERT INTO WWI_DW.dbo.HistoryLog (
        DimTable
        ,LogID
        ,RowHash
        ,TimeLog
        )

    SELECT
        2 --DimSalesPerson
        ,p.PersonID
        ,HASHBYTES('SHA2_256', CONCAT(
            p.PersonID, N'|', LEN(p.FullName), N':', p.FullName
        ))
        ,@LoadTime

    FROM WideWorldImporters.[Application].People        AS p

    WHERE p.IsSalesperson = 1
      AND NOT EXISTS (
        SELECT 1
        FROM WWI_DW.dbo.HistoryLog                      AS h
        WHERE h.DimTable = 2 -- DimSalesPerson
          AND h.LogID    = p.PersonID
    ) ;

    -- ------------------------------------------------------------
    -- 2.30 Populate DimProduct with new rows, also updates ValidTo/From and sets IsCurrent to 1
    --      Populating only rows that doesn't already have a existing StockItemID in DimProduct
    -- ------------------------------------------------------------
    INSERT INTO WWI_DW.dbo.DimProduct (
        SKUNumber
        ,ProductName
        ,ValidFrom
        ,ValidTo
        ,IsCurrent
    )

    SELECT
        s.StockItemID
        ,s.StockItemName
        ,@LoadTime
        ,'9999-12-31'
        ,1

    FROM WideWorldImporters.Warehouse.StockItems        AS s

    WHERE NOT EXISTS (
        SELECT 1
        FROM WWI_DW.dbo.DimProduct                      AS d
        WHERE d.SKUNumber = s.StockItemID
    );

    PRINT 'Rows inserted into DimProduct: ' + CAST(@@ROWCOUNT AS VARCHAR(15));

    -- ------------------------------------------------------------
    -- 2.31 Populate HistoryLog with the new rows in DimProduct
    --      Hashbytes are used to assist in identifying if rows have changed
    --      Inserts only rows in HistoryLog that does'nt exist there using StockItemID
    -- ------------------------------------------------------------
    INSERT INTO WWI_DW.dbo.HistoryLog (
        DimTable
        ,LogID
        ,RowHash
        ,TimeLog
        )

    SELECT
        3 -- DimProduct
        ,s.StockItemID
        ,HASHBYTES('SHA2_256', CONCAT(
            s.StockItemID, N'|', LEN(s.StockItemName), N':', s.StockItemName
        ))
        ,@LoadTime

    FROM WideWorldImporters.Warehouse.StockItems        AS s

    WHERE NOT EXISTS (
        SELECT 1
        FROM WWI_DW.dbo.HistoryLog                      AS h
        WHERE h.DimTable = 3 -- DimProduct
          AND h.LogID    = s.StockItemID
    ) ;

    -- ------------------------------------------------------------
    -- 2.40 Populate DimDate from first orderdate to last orderdate plus one year
    --      Will add new rows if more recent OrderDates is found in WorldWideImporters
    -- ------------------------------------------------------------
    DECLARE @DateMin    DATE;
    DECLARE @DateMax    DATE;
    DECLARE @DayCnt     INT = 0 ;
    DECLARE @Rows       INT ;
    DECLARE @Date       DATE ;
    DECLARE @AddedRows  INT = 0 ;

    -- Start DimDate from same date as first order
    SELECT @DateMin = MIN(OrderDate)
    FROM WideWorldImporters.Sales.Orders ;

    -- End DimDate one Year after last order
    SELECT @DateMax = DATEADD(YEAR, 1, MAX(OrderDate))
    FROM WideWorldImporters.Sales.Orders ;

    -- Set Language to Swedish and set first day in week to monday
    SET LANGUAGE Swedish ;
    SET DATEFIRST 1 ;

    -- Adds another row if all rows are'nt made yet
    SET @Rows = DATEDIFF(DAY, @DateMin, @DateMax) ;
    WHILE @DayCnt <= @Rows
    BEGIN

        -- Updates @date for the current row
        SET @Date = DATEADD(DAY, @DayCnt, @DateMin) ;

        -- only ad new rows it they doesn't already exist
        IF NOT EXISTS (SELECT 1 FROM WWI_DW.dbo.DimDate WHERE [Date] = @Date)
        BEGIN

            -- Insert row into table
            INSERT INTO WWI_DW.dbo.DimDate
                SELECT
                    YEAR(@Date) * 10000 + MONTH(@Date) * 100 + DAY(@Date)   AS [DateKey]
                    ,@Date                                                  AS [Date]
                    ,YEAR(@Date)                                            AS [Year]
                    ,DATEPART(MONTH, @Date)                                 AS [Month]
                    ,DATENAME(MONTH, @Date)                                 AS [MonthName]
                    ,DATEPART(WEEKDAY, @Date)                               AS [Weekday]
                    ,DATENAME(WEEKDAY, @Date)                               AS [WeekdayName]
                    ,DATEPART(WEEK, @Date)                                  AS [Week]
                    ,DATEPART(DAY, @Date)                                   AS [Day]
                    ,DATEPART(QUARTER, @Date)                               AS [QuarterNumber]
                    ,'Q' + CAST(DATEPART(QUARTER, @Date) AS VARCHAR (1))    AS [QuarterName]

            -- Counts amount of Rows added
            SET @AddedRows = @AddedRows + 1;
        END

        -- Adds one to the daycount
        SET @DayCnt = @DayCnt + 1 ;

    END

    PRINT 'Rows inserted into DimDate: ' + CAST(@AddedRows AS VARCHAR(10)) ;

    -- ------------------------------------------------------------
    -- 2.50 Creating temporary tables with indexes to store the ID's and the Key's to speed up
    --      FactSales poulation and ensure that only unique data is used
    -- ------------------------------------------------------------
    SELECT  CustomerID, CustomerKey
    INTO    #Customer_ID_Key
    FROM    WWI_DW.dbo.DimCustomer
    WHERE   IsCurrent = 1 ;

    CREATE UNIQUE CLUSTERED INDEX idx_Customer_ID_Key
        ON #Customer_ID_Key(CustomerID);

    SELECT  SalesPersonID, SalesPersonKey
    INTO    #SalesPerson_ID_Key
    FROM    WWI_DW.dbo.DimSalesPerson
    WHERE   IsCurrent = 1 ;

    CREATE UNIQUE CLUSTERED INDEX idx_SalesPerson_ID_Key
        ON #SalesPerson_ID_Key(SalesPersonID);

    SELECT  SKUNumber, ProductKey
    INTO    #Product_ID_Key
    FROM    WWI_DW.dbo.DimProduct
    WHERE   IsCurrent = 1 ;

    CREATE UNIQUE CLUSTERED INDEX idx_Product_ID_Key
        ON #Product_ID_Key(SKUNumber);

    -- ------------------------------------------------------------
    -- 2.60 Populate FactSales from WideWorldImporters and the temporary ID/Key Tables.
    --      Will only add rows that doesn't exist using OrderLineID
    -- ------------------------------------------------------------
    INSERT INTO WWI_DW.dbo.FactSales (
        CustomerKey
        ,SalesPersonKey
        ,ProductKey
        ,DateKey
        ,OrderLineID
        ,Quantity
        ,UnitPrice
        ,Sales
    )
    SELECT
        c.CustomerKey
        ,sp.SalesPersonKey
        ,p.ProductKey
        ,YEAR(o.OrderDate) * 10000
            + MONTH(o.OrderDate) * 100
            + DAY(o.OrderDate)
        ,ol.OrderLineID
        ,ol.Quantity
        ,ol.UnitPrice
        ,ol.Quantity * ol.UnitPrice

    FROM WideWorldImporters.Sales.Orders                    AS o

    JOIN WideWorldImporters.Sales.OrderLines                AS ol
        ON o.OrderID = ol.OrderID

    JOIN #Customer_ID_Key                                   AS c
        ON c.CustomerID = o.CustomerID

    JOIN #SalesPerson_ID_Key                                AS sp
        ON sp.SalesPersonID = o.SalespersonPersonID

    JOIN #Product_ID_Key                                    AS p
        ON p.SKUNumber = ol.StockItemID

    WHERE NOT EXISTS (
        SELECT 1
        FROM WWI_DW.dbo.FactSales                           AS f
        WHERE f.OrderLineID = ol.OrderLineID
    );

    PRINT 'Rows inserted into FactSales: ' + CAST(@@ROWCOUNT AS VARCHAR(15));

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        PRINT 'PopulateTables failed. No changes were saved.';
        PRINT 'SQL Server message: ' + ERROR_MESSAGE();
        RETURN 1;
    END CATCH;

    RETURN 0;
END
GO

/*
==============================================================================
Step 3.1: Creating Table Functions
==============================================================================

Purpose:
    - These table functions create hash values for source data used in the
      dimension tables.
    - The hashes are used to detect when data has changed
      to assist when tables needs to be updated
    - The functions are used by the UpdateTable procedure to avoid repeating logic
      and make the code easier to read and maintain.

Notes:
    - The functions only read WideWorldImporters and do not
      update or insert any data into the WWI_DW database
    - More information about the Hash Logic at the top of the Query

==============================================================================
*/

-- 3.1.1 DimCustomer Hashrows
CREATE OR ALTER FUNCTION dbo.GetCustomerHash()
RETURNS TABLE
AS
RETURN (
    SELECT
        c.CustomerID
        ,c.CustomerName
        ,cc.CustomerCategoryName
        ,HASHBYTES('SHA2_256', CONCAT(
            c.CustomerID, N'|',
            LEN(c.CustomerName), N':', c.CustomerName, N'|',
            LEN(cc.CustomerCategoryName), N':', cc.CustomerCategoryName
        ))                                              AS cHash
    FROM WideWorldImporters.Sales.Customers             AS c

    JOIN WideWorldImporters.Sales.CustomerCategories    AS cc
        ON c.CustomerCategoryID = cc.CustomerCategoryID
);
GO

-- 3.1.2 DimSalesPerson Hashrows
CREATE OR ALTER FUNCTION dbo.GetSalesPersonHash()
RETURNS TABLE
AS
RETURN (
    SELECT
        p.PersonID,
        p.FullName,
        HASHBYTES('SHA2_256', CONCAT(
            p.PersonID, N'|', LEN(p.FullName), N':', p.FullName
        ))                                              AS sHash
    FROM WideWorldImporters.[Application].People        AS p
    WHERE p.IsSalesperson = 1
);
GO

-- 3.1.3 DimProduct Hashrows
CREATE OR ALTER FUNCTION dbo.GetProductHash()
RETURNS TABLE
AS
RETURN (
    SELECT
        s.StockItemID,
        s.StockItemName,
        HASHBYTES('SHA2_256', CONCAT(
            s.StockItemID, N'|', LEN(s.StockItemName), N':', s.StockItemName
        ))                                              AS pHash
    FROM WideWorldImporters.Warehouse.StockItems        AS s
);
GO

/*
==============================================================================
Step 3.2: Procedure to check and update if any data have changed
==============================================================================
*/

CREATE OR ALTER PROCEDURE dbo.UpdateTables
AS

/*
==============================================================================

Purpose:
    - Detects changes in source data and updates the DimTables with updated data
    - Keeps dimension history accurate by closing old records and inserting
      new versions when source data changes.
    - Marks dimension rows as inactive when source records are deleted.

DimTable "keys" :
    - DimCustomer    = 1
    - DimSalesPerson = 2
    - DimProduct     = 3

Needed Table functions:
    - dbo.GetCustomerHash()
    - dbo.GetSalesPersonHash()
    - dbo.GetProductHash()

Execution:
    3.2.10 Expire DimCustomer rows with mismatched hashes
       .11 Insert new updated rows in DimCustomer
       .12 Update HistoryLog with new hash and date
       .13 Expire customers deleted from the source

    3.2.20 Expire DimSalesPerson rows with mismatched hashes
       .21 Insert new updated rows in DimSalesPerson
       .22 Update HistoryLog with new hash and date
       .23 Expire people who are no longer source salespeople

    3.2.30 Expire DimProduct rows with mismatched hashes
       .31 Insert new updated rows in DimProduct
       .32 Update HistoryLog with new hash and date
       .33 Expire products deleted from the source

How it works:
    1. Compare current dimension rows with source data using table functions.
    2. If data has changed:
        - Expire the current dimension row by setting IsCurrent = 0, set ValidTo current date
        - Insert a new row with updated values and setting IsCurrent = 1
    3. Update HistoryLog with the new hash values.
    4. If a source row no longer exists:
        - Mark the row with IsCurrent = 0, set ValidTo current date

Notes:
    - Safe to run as often as needed to update WWI_DW database

==============================================================================
*/

BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ChangeTime DATETIME2(0) = SYSDATETIME();

    BEGIN TRY
        BEGIN TRANSACTION;
    -- ------------------------------------------------------------
    -- 3.2.10 Expire changed customers
    -- ------------------------------------------------------------
    UPDATE d
    SET d.IsCurrent = 0
        ,d.ValidTo  = @ChangeTime

    FROM WWI_DW.dbo.DimCustomer                             AS d

    JOIN dbo.GetCustomerHash()                              AS ch
        ON d.CustomerID = ch.CustomerID

    JOIN WWI_DW.dbo.HistoryLog                              AS h
        ON h.LogID = d.CustomerID
        AND h.DimTable = 1 -- DumCustomer

    WHERE h.RowHash <> ch.cHash
        AND d.IsCurrent = 1;

    -- ------------------------------------------------------------
    -- 3.2.11 Insert new updated rows in DimCustomer
    -- ------------------------------------------------------------s
    INSERT INTO WWI_DW.dbo.DimCustomer (
        CustomerID
        ,CustomerName
        ,CustomerCategoryName
        ,ValidFrom
        ,ValidTo
        ,IsCurrent
    )
    SELECT
        ch.CustomerID
        ,ch.CustomerName
        ,ch.CustomerCategoryName
        ,@ChangeTime
        ,'9999-12-31'
        ,1
    FROM dbo.GetCustomerHash()                              AS ch

    JOIN WWI_DW.dbo.HistoryLog                              AS h
        ON h.LogID = ch.CustomerID
        AND h.DimTable = 1 -- DimCustomer

    WHERE NOT EXISTS (
            SELECT 1
            FROM WWI_DW.dbo.DimCustomer                     AS d
            WHERE d.CustomerID = ch.CustomerID
        AND d.IsCurrent = 1
    ) ;

    PRINT 'Rows updated in DimCustomer: ' + CAST((@@ROWCOUNT) AS VARCHAR(15)) ;

    -- ------------------------------------------------------------
    -- 3.2.12 Update HistoryLog with new hash and date
    -- ------------------------------------------------------------
    UPDATE h
    SET h.RowHash = ch.cHash
        ,h.TimeLog = @ChangeTime

    FROM WWI_DW.dbo.HistoryLog                              AS h

    JOIN dbo.GetCustomerHash()                              AS ch
        ON h.LogID = ch.CustomerID

    WHERE h.DimTable = 1 -- DimCustomer
        AND h.RowHash <> ch.cHash ;

    -- ------------------------------------------------------------
    -- 3.2.13 Expire deleted customers
    -- ------------------------------------------------------------
    UPDATE d
    SET d.IsCurrent = 0
        ,d.ValidTo  = @ChangeTime

    FROM WWI_DW.dbo.DimCustomer                             AS d

    WHERE d.IsCurrent = 1
        AND NOT EXISTS (
            SELECT 1
            FROM dbo.GetCustomerHash()                      AS ch
            WHERE ch.CustomerID = d.CustomerID
    ) ;

    -- ------------------------------------------------------------
    -- 3.2.20 Expire changed salespeople
    -- ------------------------------------------------------------
    UPDATE d
    SET d.IsCurrent = 0
        ,d.ValidTo  = @ChangeTime

    FROM WWI_DW.dbo.DimSalesPerson                          AS d

    JOIN dbo.GetSalesPersonHash()                           AS sp
        ON d.SalesPersonID = sp.PersonID

    JOIN WWI_DW.dbo.HistoryLog                              AS h
        ON h.LogID = d.SalesPersonID
        AND h.DimTable = 2   -- DimSalesPerson

    WHERE h.RowHash <> sp.sHash
        AND d.IsCurrent = 1;

    -- ------------------------------------------------------------
    -- 3.2.21 Insert new updated rows in DimSalesPerson
    -- ------------------------------------------------------------
    INSERT INTO WWI_DW.dbo.DimSalesPerson (
        SalesPersonID
        ,EmployeeFullName
        ,EmployeeLastName
        ,ValidFrom
        ,ValidTo
        ,IsCurrent
    )
    SELECT
        sp.PersonID
        ,sp.FullName
        ,CASE WHEN CHARINDEX(' ', sp.FullName) > 0
             THEN RIGHT(sp.FullName, CHARINDEX(' ', REVERSE(sp.FullName)) - 1)
             ELSE NULL
        END
        ,@ChangeTime
        ,'9999-12-31'
        ,1

    FROM dbo.GetSalesPersonHash()                           AS sp

    JOIN WWI_DW.dbo.HistoryLog                              AS h
        ON h.LogID = sp.PersonID
        AND h.DimTable = 2 -- DimSalesPerson

    WHERE NOT EXISTS (
            SELECT 1
            FROM WWI_DW.dbo.DimSalesPerson d
            WHERE d.SalesPersonID = sp.PersonID
        AND d.IsCurrent = 1
  ) ;

    PRINT 'Rows updated in DimSalesPerson: ' + CAST((@@ROWCOUNT) AS VARCHAR(15)) ;

    -- ------------------------------------------------------------
    -- 3.2.22 Update HistoryLog with new hash and date
    -- ------------------------------------------------------------
    UPDATE h
    SET h.RowHash = sp.sHash,
        h.TimeLog = @ChangeTime

    FROM WWI_DW.dbo.HistoryLog                              AS h

    JOIN dbo.GetSalesPersonHash()                           AS sp
        ON h.LogID = sp.PersonID

    WHERE h.DimTable = 2 --DimSalesPerson
        AND h.RowHash <> sp.sHash ;

    -- ------------------------------------------------------------
    -- 3.2.23 Expire people who are no longer salespeople
    -- ------------------------------------------------------------
    UPDATE d
    SET d.IsCurrent = 0
        ,d.ValidTo  = @ChangeTime

    FROM WWI_DW.dbo.DimSalesPerson                          AS d

    WHERE d.IsCurrent = 1
        AND NOT EXISTS (
            SELECT 1
            FROM dbo.GetSalesPersonHash()                   AS sp
            WHERE sp.PersonID = d.SalesPersonID
  ) ;

    -- ------------------------------------------------------------
    -- 3.2.30 Expire changed products
    -- ------------------------------------------------------------  0
    UPDATE d
    SET d.IsCurrent = 0
        ,d.ValidTo  = @ChangeTime

    FROM WWI_DW.dbo.DimProduct                              AS d

    JOIN dbo.GetProductHash()                               AS ph
        ON d.SKUNumber = ph.StockItemID

    JOIN WWI_DW.dbo.HistoryLog                              AS h
        ON h.LogID = d.SKUNumber
        AND h.DimTable = 3   -- DimProduct

    WHERE h.RowHash <> ph.pHash
      AND d.IsCurrent = 1 ;

    -- ------------------------------------------------------------
    -- 3.2.31 Insert new updated rows in DimProduct
    -- ------------------------------------------------------------
    INSERT INTO WWI_DW.dbo.DimProduct (
        SKUNumber
        ,ProductName
        ,ValidFrom
        ,ValidTo
        ,IsCurrent
    )
    SELECT
        ph.StockItemID
        ,ph.StockItemName
        ,@ChangeTime
        ,'9999-12-31'
        ,1

    FROM dbo.GetProductHash()                               AS ph

    JOIN WWI_DW.dbo.HistoryLog                              AS h
        ON h.LogID = ph.StockItemID
        AND h.DimTable = 3 -- DimProduct

    WHERE NOT EXISTS (
            SELECT 1
            FROM WWI_DW.dbo.DimProduct                      AS d
            WHERE d.SKUNumber = ph.StockItemID
        AND d.IsCurrent = 1
    );

    PRINT 'Rows updated in DimProduct: ' + CAST((@@ROWCOUNT) AS VARCHAR(15)) ;

    -- ------------------------------------------------------------
    -- 3.2.32 Update HistoryLog with new hash and date
    -- ------------------------------------------------------------
    UPDATE h
    SET h.RowHash = ph.pHash,
        h.TimeLog = @ChangeTime

    FROM WWI_DW.dbo.HistoryLog                              AS h

    JOIN dbo.GetProductHash()                               AS ph
        ON h.LogID = ph.StockItemID

    WHERE h.DimTable = 3 -- DimProduct
        AND h.RowHash <> ph.pHash ;

    -- ------------------------------------------------------------
    -- 3.2.33 Expire deleted products
    -- ------------------------------------------------------------
    UPDATE d
    SET d.IsCurrent = 0
        ,d.ValidTo  = @ChangeTime

    FROM WWI_DW.dbo.DimProduct                              AS d

    WHERE d.IsCurrent = 1
        AND NOT EXISTS (
            SELECT 1
            FROM dbo.GetProductHash()                       AS ph
            WHERE ph.StockItemID = d.SKUNumber
    ) ;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;

        PRINT 'UpdateTables failed. No changes were saved.';
        PRINT 'SQL Server message: ' + ERROR_MESSAGE();
        RETURN 1;
    END CATCH;

    RETURN 0;
END
GO

/*
==============================================================================
Step 4: Execution of the procedures
==============================================================================

Execution order:
    1. Create the complete warehouse schema when absent.
    2. Apply SCD2 changes to existing dimension members.
    3. Load new members, dates, and order-line facts.

==============================================================================
*/

-- ------------------------------------------------------------
-- Step 1:  Creates tables if they don't exist
-- ------------------------------------------------------------

DECLARE @WarehouseTableCount INT = (
    SELECT COUNT(*)
    FROM WWI_DW.sys.tables AS t
    JOIN WWI_DW.sys.schemas AS s ON s.schema_id = t.schema_id
    WHERE s.[name] = 'dbo'
      AND t.[name] IN (
          'FactSales', 'DimCustomer', 'DimSalesPerson',
          'DimProduct', 'DimDate', 'HistoryLog'
      )
);

DECLARE @WarehouseIsReady BIT = 1;

IF @WarehouseTableCount = 0
BEGIN
    EXEC dbo.CreateTables;
END
ELSE IF @WarehouseTableCount < 6
BEGIN
    PRINT 'The warehouse is only partly created.';
    PRINT 'Repair or remove the incomplete warehouse tables, then run the script again.';
    SET @WarehouseIsReady = 0;
END;

IF @WarehouseIsReady = 1
BEGIN
    DECLARE @UpdateResult INT;
    DECLARE @PopulateResult INT;

    -- ------------------------------------------------------------
    -- Step 2: Apply dimension changes before loading new facts
    -- ------------------------------------------------------------
    EXEC @UpdateResult = dbo.UpdateTables;

    -- Populate only when the update completed successfully.
    IF @UpdateResult = 0
    BEGIN
        -- ------------------------------------------------------------
        -- Step 3: Load new dimension members, dates, and facts
        -- ------------------------------------------------------------
        EXEC @PopulateResult = dbo.PopulateTables;

        IF @PopulateResult = 0
            PRINT 'Warehouse load completed successfully.';
    END
    ELSE
    BEGIN
        PRINT 'PopulateTables was skipped because UpdateTables failed.';
    END;
END;
