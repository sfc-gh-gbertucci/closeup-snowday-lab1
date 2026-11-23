-- Step 5: Dashboards & reports with AI
-- Source: lab1a_data_foundation.html
-- Step 5 is done in Snowsight Workspaces with CoCo (Dashboards + HTML reports).
-- These are reference tile queries in case you build the dashboard by hand.
-- {{ filter('sale_date') }} is a dashboard filter placeholder: it only works inside a .dash tile.

-- Scorecard: total sales
SELECT SUM(SALES_USD) AS TOTAL_SALES_USD
FROM CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE;

-- Line chart: monthly sales
SELECT MONTH, SUM(SALES_USD) AS SALES_USD
FROM CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE
GROUP BY MONTH
ORDER BY MONTH;

-- Bar chart: market share by laboratory
SELECT LAB_NAME, ROUND(SUM(SALES_USD) / SUM(SUM(SALES_USD)) OVER () * 100, 2) AS SHARE_PCT
FROM CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE
GROUP BY LAB_NAME
ORDER BY SHARE_PCT DESC;

-- Heatmap: prescriptions by specialty and therapeutic area
SELECT SPECIALTY, THERAPEUTIC_AREA, SUM(RX_COUNT) AS RX_COUNT
FROM CLOSEUP_HOL1.ANALYTICS.DT_PRESCRIPTION_TRENDS
GROUP BY 1, 2
ORDER BY 1, 2;

-- Table: top 10 pharmacies, filtered by the dashboard date range
SELECT PHARMACY_NAME, CHAIN, CITY, COUNTRY, SUM(NET_AMOUNT_USD) AS SALES_USD
FROM CLOSEUP_HOL1.CURATED.V_SALES
WHERE {{ filter('sale_date') }}
GROUP BY 1, 2, 3, 4
ORDER BY SALES_USD DESC
LIMIT 10;
