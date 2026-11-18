-- Step 3: Semantic Layer: Semantic Views
-- Source: lab1b_ai_agent.html

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CLOSEUP_HOL1_WH;

CREATE OR REPLACE SEMANTIC VIEW CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET

  TABLES (
    sales AS CLOSEUP_HOL1.CURATED.V_SALES
      PRIMARY KEY (SALE_ID)
      WITH SYNONYMS ('sell-out', 'pharmacy sales', 'transactions')
      COMMENT = 'Pharmacy sell-out transactions (one row per sale) for the last 24 months',
    products AS CLOSEUP_HOL1.RAW.PRODUCTS
      PRIMARY KEY (PRODUCT_ID)
      WITH SYNONYMS ('drugs', 'medicines', 'SKUs', 'brands')
      COMMENT = 'Product catalog: brand, molecule, ATC class and therapeutic area',
    labs AS CLOSEUP_HOL1.RAW.LABORATORIES
      PRIMARY KEY (LAB_ID)
      WITH SYNONYMS ('laboratories', 'manufacturers', 'pharma companies')
      COMMENT = 'Pharmaceutical laboratories that own the products',
    pharmacies AS CLOSEUP_HOL1.RAW.PHARMACIES
      PRIMARY KEY (PHARMACY_ID)
      WITH SYNONYMS ('drugstores', 'points of sale', 'outlets')
      COMMENT = 'Pharmacies (points of sale) in Argentina, Brazil, Uruguay and Chile'
  )

  RELATIONSHIPS (
    sales_to_products   AS sales (PRODUCT_ID)  REFERENCES products,
    sales_to_pharmacies AS sales (PHARMACY_ID) REFERENCES pharmacies,
    products_to_labs    AS products (LAB_ID)   REFERENCES labs
  )

  FACTS (
    sales.units AS UNITS
      COMMENT = 'Units sold in the transaction',
    sales.net_amount_usd AS NET_AMOUNT_USD
      COMMENT = 'Net sales amount of the transaction in USD',
    sales.unit_price_usd AS NET_AMOUNT_USD / NULLIF(UNITS, 0)
      COMMENT = 'Net price per unit in USD'
  )

  DIMENSIONS (
    sales.sale_date AS SALE_DATE
      WITH SYNONYMS = ('date', 'transaction date')
      COMMENT = 'Date of the sale',
    sales.sale_month AS SALE_MONTH
      WITH SYNONYMS = ('month', 'period')
      COMMENT = 'First day of the month of the sale',
    sales.sale_year AS YEAR(SALE_DATE)
      WITH SYNONYMS = ('year')
      COMMENT = 'Calendar year of the sale',
    products.brand_name AS BRAND_NAME
      WITH SYNONYMS = ('brand', 'product', 'drug name')
      COMMENT = 'Commercial brand name of the product',
    products.molecule AS MOLECULE
      WITH SYNONYMS = ('active ingredient', 'generic name')
      COMMENT = 'Active molecule of the product',
    products.atc_class AS ATC_CLASS
      WITH SYNONYMS = ('ATC', 'ATC code')
      COMMENT = 'Anatomical Therapeutic Chemical classification',
    products.therapeutic_area AS THERAPEUTIC_AREA
      WITH SYNONYMS = ('therapy area', 'TA', 'market', 'segment')
      COMMENT = 'Therapeutic area: Cardiology, Diabetes, Oncology, Respiratory, CNS, Gastroenterology, Dermatology, Analgesics',
    labs.lab_name AS LAB_NAME
      WITH SYNONYMS = ('laboratory', 'manufacturer', 'company', 'competitor')
      COMMENT = 'Name of the laboratory that owns the product',
    labs.is_closeup_client AS IS_CLOSEUP_CLIENT
      WITH SYNONYMS = ('client', 'customer lab')
      COMMENT = 'TRUE if the laboratory is a Close-Up client',
    pharmacies.pharmacy_name AS PHARMACY_NAME
      WITH SYNONYMS = ('pharmacy', 'drugstore')
      COMMENT = 'Name of the pharmacy',
    pharmacies.chain AS CHAIN
      WITH SYNONYMS = ('pharmacy chain', 'banner')
      COMMENT = 'Pharmacy chain name',
    pharmacies.channel AS CHANNEL
      WITH SYNONYMS = ('sales channel')
      COMMENT = 'Channel: Retail Chain, Independent or Hospital',
    pharmacies.city AS CITY
      COMMENT = 'City of the pharmacy',
    pharmacies.region AS REGION
      WITH SYNONYMS = ('state', 'province')
      COMMENT = 'Region / province / state of the pharmacy',
    pharmacies.country AS COUNTRY
      WITH SYNONYMS = ('nation')
      COMMENT = 'Country: Argentina, Brazil, Uruguay or Chile'
  )

  METRICS (
    sales.total_sales_usd AS SUM(sales.net_amount_usd)
      WITH SYNONYMS = ('revenue', 'sales', 'sell-out value', 'turnover')
      COMMENT = 'Total net sales in USD',
    sales.total_units AS SUM(sales.units)
      WITH SYNONYMS = ('volume', 'units sold', 'boxes')
      COMMENT = 'Total units sold',
    sales.avg_price_usd AS SUM(sales.net_amount_usd) / NULLIF(SUM(sales.units), 0)
      WITH SYNONYMS = ('average price', 'price per unit')
      COMMENT = 'Average net price per unit (total sales / total units)',
    sales.pharmacy_count AS COUNT(DISTINCT sales.PHARMACY_ID)
      WITH SYNONYMS = ('number of pharmacies', 'numeric distribution')
      COMMENT = 'Number of distinct pharmacies with sales',
    sales.transaction_count AS COUNT(sales.SALE_ID)
      COMMENT = 'Number of sell-out transactions',
    -- Window metric: total market of ALL labs for the same slice (basis for market share)
    sales.total_market_sales_usd AS SUM(sales.total_sales_usd)
      OVER (PARTITION BY EXCLUDING labs.lab_name)
      WITH SYNONYMS = ('market size', 'total market')
      COMMENT = 'Total market sales of ALL laboratories for the same slice (query it together with lab_name). Lab market share % = 100 * total_sales_usd / total_market_sales_usd'
  )

  COMMENT = 'Close-Up pharma market intelligence: sell-out sales, units, prices and market size by lab, product, therapeutic area and geography';

-- What does the semantic view expose?
DESCRIBE SEMANTIC VIEW CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET;
SHOW SEMANTIC METRICS    IN CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET;
SHOW SEMANTIC DIMENSIONS IN CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET;

-- Sales, units, price and numeric distribution by country and therapeutic area
SELECT * FROM SEMANTIC_VIEW(
    CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET
    DIMENSIONS pharmacies.country, products.therapeutic_area
    METRICS    sales.total_sales_usd, sales.total_units, sales.avg_price_usd, sales.pharmacy_count
)
ORDER BY total_sales_usd DESC
LIMIT 20;

-- Market share of each laboratory in Cardiology, by country
SELECT country, lab_name, total_sales_usd, total_market_sales_usd,
       ROUND(100 * total_sales_usd / NULLIF(total_market_sales_usd, 0), 2) AS market_share_pct
FROM SEMANTIC_VIEW(
    CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET
    DIMENSIONS pharmacies.country, labs.lab_name
    METRICS    sales.total_sales_usd, sales.total_market_sales_usd
    WHERE      products.therapeutic_area = 'Cardiology'
)
ORDER BY country, market_share_pct DESC;

-- Verification: lab market shares must add up to 100% in every country
SELECT country,
       COUNT(*) AS labs,
       ROUND(SUM(100 * total_sales_usd / NULLIF(total_market_sales_usd, 0)), 2) AS total_share_pct
FROM SEMANTIC_VIEW(
    CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET
    DIMENSIONS pharmacies.country, labs.lab_name
    METRICS    sales.total_sales_usd, sales.total_market_sales_usd
    WHERE      products.therapeutic_area = 'Cardiology'
)
GROUP BY country
ORDER BY country;
