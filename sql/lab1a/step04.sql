-- Step 4: Transformation: Views & Dynamic Tables
-- Source: lab1a_data_foundation.html

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CLOSEUP_HOL1_WH;
USE DATABASE CLOSEUP_HOL1;

-- Curated sales view: one row per sale, enriched with product, lab and pharmacy attributes
CREATE OR REPLACE VIEW CLOSEUP_HOL1.CURATED.V_SALES
  COMMENT = 'Sell-out transactions enriched with product, laboratory and pharmacy attributes'
AS
SELECT
    s.SALE_ID,
    s.SALE_DATE,
    DATE_TRUNC('MONTH', s.SALE_DATE)::DATE AS SALE_MONTH,
    s.PHARMACY_ID,
    ph.PHARMACY_NAME,
    ph.CHAIN,
    ph.CITY,
    ph.REGION,
    ph.COUNTRY,
    ph.CHANNEL,
    s.PRODUCT_ID,
    p.BRAND_NAME,
    p.MOLECULE,
    p.ATC_CLASS,
    p.THERAPEUTIC_AREA,
    p.LAB_ID,
    l.LAB_NAME,
    l.IS_CLOSEUP_CLIENT,
    s.UNITS,
    s.NET_AMOUNT_USD
FROM CLOSEUP_HOL1.RAW.SELL_OUT s
JOIN CLOSEUP_HOL1.RAW.PRODUCTS     p  ON s.PRODUCT_ID  = p.PRODUCT_ID
JOIN CLOSEUP_HOL1.RAW.LABORATORIES l  ON p.LAB_ID      = l.LAB_ID
JOIN CLOSEUP_HOL1.RAW.PHARMACIES   ph ON s.PHARMACY_ID = ph.PHARMACY_ID;

-- Curated prescriptions view: one row per prescription, enriched with doctor and product
CREATE OR REPLACE VIEW CLOSEUP_HOL1.CURATED.V_PRESCRIPTIONS
  COMMENT = 'Prescriptions enriched with doctor and product attributes'
AS
SELECT
    r.RX_ID,
    r.RX_DATE,
    DATE_TRUNC('MONTH', r.RX_DATE)::DATE AS RX_MONTH,
    r.DOCTOR_ID,
    d.DOCTOR_NAME,
    d.SPECIALTY,
    d.CITY,
    d.COUNTRY,
    r.PRODUCT_ID,
    p.BRAND_NAME,
    p.MOLECULE,
    p.THERAPEUTIC_AREA,
    p.LAB_ID,
    r.QUANTITY
FROM CLOSEUP_HOL1.RAW.PRESCRIPTIONS r
JOIN CLOSEUP_HOL1.RAW.DOCTORS  d ON r.DOCTOR_ID  = d.DOCTOR_ID
JOIN CLOSEUP_HOL1.RAW.PRODUCTS p ON r.PRODUCT_ID = p.PRODUCT_ID;

-- Quick check: the views must return the same row count as the RAW fact tables
SELECT 'V_SALES' AS VIEW_NAME, COUNT(*) AS ROW_COUNT FROM CLOSEUP_HOL1.CURATED.V_SALES
UNION ALL
SELECT 'V_PRESCRIPTIONS', COUNT(*) FROM CLOSEUP_HOL1.CURATED.V_PRESCRIPTIONS;

-- Monthly market share by country, therapeutic area and laboratory
CREATE OR REPLACE DYNAMIC TABLE CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE
  TARGET_LAG = '1 hour'
  WAREHOUSE  = CLOSEUP_HOL1_WH
  COMMENT    = 'Monthly sales, units and market share % per lab within country + therapeutic area'
AS
WITH products AS (          -- deduplicated dimension: exactly one row per product
    SELECT DISTINCT PRODUCT_ID, LAB_ID, THERAPEUTIC_AREA
    FROM CLOSEUP_HOL1.RAW.PRODUCTS
),
labs AS (
    SELECT DISTINCT LAB_ID, LAB_NAME
    FROM CLOSEUP_HOL1.RAW.LABORATORIES
),
pharmacies AS (
    SELECT DISTINCT PHARMACY_ID, COUNTRY
    FROM CLOSEUP_HOL1.RAW.PHARMACIES
),
sales_pre AS (              -- pre-aggregate the fact BEFORE joining (no fan-out)
    SELECT DATE_TRUNC('MONTH', SALE_DATE)::DATE AS MONTH,
           PHARMACY_ID, PRODUCT_ID,
           SUM(UNITS)          AS UNITS,
           SUM(NET_AMOUNT_USD) AS SALES_USD
    FROM CLOSEUP_HOL1.RAW.SELL_OUT
    GROUP BY 1, 2, 3
),
agg AS (
    SELECT s.MONTH, ph.COUNTRY, p.THERAPEUTIC_AREA, l.LAB_ID, l.LAB_NAME,
           SUM(s.UNITS)     AS UNITS,
           SUM(s.SALES_USD) AS SALES_USD
    FROM sales_pre s
    JOIN products   p  ON s.PRODUCT_ID  = p.PRODUCT_ID
    JOIN labs       l  ON p.LAB_ID      = l.LAB_ID
    JOIN pharmacies ph ON s.PHARMACY_ID = ph.PHARMACY_ID
    GROUP BY 1, 2, 3, 4, 5
)
SELECT MONTH, COUNTRY, THERAPEUTIC_AREA, LAB_ID, LAB_NAME, UNITS, SALES_USD,
       ROUND(100 * SALES_USD
             / NULLIF(SUM(SALES_USD) OVER (PARTITION BY MONTH, COUNTRY, THERAPEUTIC_AREA), 0), 2)
         AS MARKET_SHARE_PCT
FROM agg;

-- Monthly prescription trends by country, specialty and therapeutic area
CREATE OR REPLACE DYNAMIC TABLE CLOSEUP_HOL1.ANALYTICS.DT_PRESCRIPTION_TRENDS
  TARGET_LAG = '1 hour'
  WAREHOUSE  = CLOSEUP_HOL1_WH
  COMMENT    = 'Monthly prescription count and units by country, specialty and therapeutic area'
AS
WITH doctors AS (
    SELECT DISTINCT DOCTOR_ID, SPECIALTY, COUNTRY
    FROM CLOSEUP_HOL1.RAW.DOCTORS
),
products AS (
    SELECT DISTINCT PRODUCT_ID, THERAPEUTIC_AREA
    FROM CLOSEUP_HOL1.RAW.PRODUCTS
),
rx_pre AS (                 -- pre-aggregate prescriptions before joining
    SELECT DATE_TRUNC('MONTH', RX_DATE)::DATE AS MONTH,
           DOCTOR_ID, PRODUCT_ID,
           COUNT(*)      AS RX_COUNT,
           SUM(QUANTITY) AS UNITS
    FROM CLOSEUP_HOL1.RAW.PRESCRIPTIONS
    GROUP BY 1, 2, 3
)
SELECT r.MONTH, d.COUNTRY, d.SPECIALTY, p.THERAPEUTIC_AREA,
       SUM(r.RX_COUNT) AS RX_COUNT,
       SUM(r.UNITS)    AS UNITS
FROM rx_pre r
JOIN doctors  d ON r.DOCTOR_ID  = d.DOCTOR_ID
JOIN products p ON r.PRODUCT_ID = p.PRODUCT_ID
GROUP BY 1, 2, 3, 4;

-- Force a manual refresh (normally Snowflake refreshes automatically to meet TARGET_LAG)
ALTER DYNAMIC TABLE CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE REFRESH;
ALTER DYNAMIC TABLE CLOSEUP_HOL1.ANALYTICS.DT_PRESCRIPTION_TRENDS REFRESH;

-- Refresh history of both Dynamic Tables
SELECT NAME, STATE, REFRESH_ACTION, REFRESH_TRIGGER,
       REFRESH_START_TIME, REFRESH_END_TIME,
       DATEDIFF('second', REFRESH_START_TIME, REFRESH_END_TIME) AS DURATION_SEC
FROM TABLE(CLOSEUP_HOL1.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
WHERE NAME IN ('DT_MONTHLY_MARKET_SHARE', 'DT_PRESCRIPTION_TRENDS')
ORDER BY REFRESH_START_TIME DESC;

-- Current status, target lag and refresh mode
SHOW DYNAMIC TABLES IN SCHEMA CLOSEUP_HOL1.ANALYTICS;

-- Verification: market shares per (month, country, therapeutic area) must add up to ~100%
SELECT MONTH, COUNTRY, THERAPEUTIC_AREA,
       COUNT(*)              AS LABS,
       SUM(SALES_USD)        AS SALES_USD,
       SUM(MARKET_SHARE_PCT) AS TOTAL_SHARE_PCT
FROM CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE
GROUP BY 1, 2, 3
ORDER BY MONTH DESC, COUNTRY, THERAPEUTIC_AREA
LIMIT 20;
