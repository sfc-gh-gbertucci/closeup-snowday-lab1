-- Step 1: Snowflake in 5 minutes
-- Source: lab1a_data_foundation.html

-- Use the administrator role for the setup
USE ROLE ACCOUNTADMIN;

-- Compute: extra-small warehouse that suspends after 60 s of inactivity
CREATE WAREHOUSE IF NOT EXISTS CLOSEUP_HOL1_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'Close-Up HOL 1 warehouse';

-- Storage: the lab database
CREATE DATABASE IF NOT EXISTS CLOSEUP_HOL1
    COMMENT = 'Close-Up SnowDay HOL 1 - Pharma Market Intelligence (synthetic data)';

-- One schema per layer
CREATE SCHEMA IF NOT EXISTS CLOSEUP_HOL1.SOURCE_SYSTEM COMMENT = 'Simulated operational source system';
CREATE SCHEMA IF NOT EXISTS CLOSEUP_HOL1.RAW           COMMENT = 'Raw landing zone (loaded from stage)';
CREATE SCHEMA IF NOT EXISTS CLOSEUP_HOL1.CURATED       COMMENT = 'Cleaned and joined business views';
CREATE SCHEMA IF NOT EXISTS CLOSEUP_HOL1.ANALYTICS     COMMENT = 'Aggregated analytics (Dynamic Tables, Semantic View)';
CREATE SCHEMA IF NOT EXISTS CLOSEUP_HOL1.AI            COMMENT = 'AI-enriched data, Cortex Search';

-- Set the session context
USE WAREHOUSE CLOSEUP_HOL1_WH;
USE SCHEMA CLOSEUP_HOL1.SOURCE_SYSTEM;

-- Expected: 5 schemas (AI, ANALYTICS, CURATED, RAW, SOURCE_SYSTEM)
SELECT SCHEMA_NAME, COMMENT
FROM CLOSEUP_HOL1.INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME NOT IN ('INFORMATION_SCHEMA', 'PUBLIC')
ORDER BY SCHEMA_NAME;

-- Warehouse size and auto-suspend setting
SHOW WAREHOUSES LIKE 'CLOSEUP_HOL1_WH';
