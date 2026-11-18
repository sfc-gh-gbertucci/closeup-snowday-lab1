-- Step 4: Cortex Search
-- Source: lab1b_ai_agent.html

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CLOSEUP_HOL1_WH;

CREATE OR REPLACE CORTEX SEARCH SERVICE CLOSEUP_HOL1.AI.CS_FIELD_NOTES
  ON NOTE_TEXT                      -- column that is indexed for hybrid search
  ATTRIBUTES COUNTRY, CATEGORY      -- columns usable as filters
  WAREHOUSE = CLOSEUP_HOL1_WH       -- compute used to build / refresh the index
  TARGET_LAG = '1 hour'             -- max staleness vs. the source table
  COMMENT = 'Hybrid search over Close-Up field notes (market reports from field reps)'
AS
SELECT
    NOTE_ID,
    NOTE_TEXT,
    NOTE_DATE,
    PRODUCT_ID,
    COUNTRY,
    AUTHOR_ROLE,
    SENTIMENT,
    CATEGORY,
    SUMMARY,
    CONCAT(CATEGORY, ' | ', COUNTRY, ' | ', TO_VARCHAR(NOTE_DATE)) AS NOTE_TITLE
FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED;

SHOW CORTEX SEARCH SERVICES IN SCHEMA CLOSEUP_HOL1.AI;
DESCRIBE CORTEX SEARCH SERVICE CLOSEUP_HOL1.AI.CS_FIELD_NOTES;

SELECT r.value:NOTE_ID::VARCHAR   AS note_id,
       r.value:COUNTRY::VARCHAR   AS country,
       r.value:CATEGORY::VARCHAR  AS category,
       r.value:NOTE_TEXT::VARCHAR AS note_text
FROM TABLE(FLATTEN(
  PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'CLOSEUP_HOL1.AI.CS_FIELD_NOTES',
    '{"query": "competitor launched a cheaper generic",
      "columns": ["NOTE_ID","COUNTRY","CATEGORY","NOTE_TEXT"],
      "limit": 5}'
  )):results
)) r;

SELECT r.value:NOTE_ID::VARCHAR   AS note_id,
       r.value:NOTE_DATE::VARCHAR AS note_date,
       r.value:COUNTRY::VARCHAR   AS country,
       r.value:CATEGORY::VARCHAR  AS category,
       r.value:NOTE_TEXT::VARCHAR AS note_text
FROM TABLE(FLATTEN(
  PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'CLOSEUP_HOL1.AI.CS_FIELD_NOTES',
    '{"query": "stock-out shortage at pharmacies",
      "columns": ["NOTE_ID","NOTE_DATE","COUNTRY","CATEGORY","NOTE_TEXT"],
      "filter": {"@and": [
          {"@eq": {"COUNTRY": "Brazil"}},
          {"@eq": {"CATEGORY": "Supply / Stock-out"}}
      ]},
      "limit": 5}'
  )):results
)) r;

SELECT COUNT(*) AS results_returned
FROM TABLE(FLATTEN(
  PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'CLOSEUP_HOL1.AI.CS_FIELD_NOTES',
    '{"query": "price increase", "columns": ["NOTE_ID"], "limit": 5}'
  )):results
));
-- Expected: 5
