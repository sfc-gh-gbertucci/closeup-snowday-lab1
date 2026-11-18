-- Step 2: AI on Data: Cortex AI Functions
-- Source: lab1b_ai_agent.html

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CLOSEUP_HOL1_WH;

-- Try the functions on a single sentence first
SELECT
    AI_SENTIMENT('Doctors in Santiago report excellent tolerability, but stock-outs are hurting sales.') AS SENTIMENT_OBJECT,
    AI_SENTIMENT('Doctors in Santiago report excellent tolerability, but stock-outs are hurting sales.'):categories[0]:sentiment::VARCHAR AS OVERALL_SENTIMENT,
    AI_CLASSIFY('A competitor launched a cheaper generic in Brazil.',
                ['Competitor Activity', 'Supply / Stock-out', 'Pricing', 'Doctor Feedback', 'Regulatory']):labels[0]::VARCHAR AS CATEGORY;

-- Enrich the 300 field notes with sentiment, category and a one-line summary
CREATE OR REPLACE TABLE CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED
  COMMENT = 'Field notes enriched with AI sentiment, category and one-line summary'
AS
SELECT
    n.NOTE_ID,
    n.NOTE_DATE,
    n.PRODUCT_ID,
    n.COUNTRY,
    n.AUTHOR_ROLE,
    n.NOTE_TEXT,
    -- AI_SENTIMENT returns an OBJECT: take the overall sentiment label
    AI_SENTIMENT(n.NOTE_TEXT):categories[0]:sentiment::VARCHAR AS SENTIMENT,
    -- AI_CLASSIFY returns an OBJECT with the chosen label(s)
    AI_CLASSIFY(
        n.NOTE_TEXT,
        ['Competitor Activity', 'Supply / Stock-out', 'Pricing', 'Doctor Feedback', 'Regulatory']
    ):labels[0]::VARCHAR AS CATEGORY,
    -- AI_COMPLETE: free-form LLM prompt (COALESCE protects against NULLs)
    AI_COMPLETE(
        'llama3.1-70b',
        'Summarize the following pharma field note in ONE sentence of at most 20 words. '
        || 'Return only the sentence. Country: ' || COALESCE(n.COUNTRY, 'unknown')
        || '. Note: ' || COALESCE(n.NOTE_TEXT, '')
    )::VARCHAR AS SUMMARY
FROM CLOSEUP_HOL1.RAW.FIELD_NOTES n
ORDER BY n.NOTE_ID
LIMIT 300;

-- Look at the enriched rows
SELECT NOTE_ID, COUNTRY, SENTIMENT, CATEGORY, SUMMARY, NOTE_TEXT
FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED
LIMIT 10;

-- Distribution of categories and sentiment
SELECT CATEGORY, SENTIMENT, COUNT(*) AS NOTES
FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED
GROUP BY 1, 2
ORDER BY 1, 3 DESC;

-- One executive summary per therapeutic area (aggregates ALL notes of each group)
SELECT
    p.THERAPEUTIC_AREA,
    COUNT(*)                      AS NOTES,
    AI_SUMMARIZE_AGG(f.NOTE_TEXT) AS AREA_SUMMARY
FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED f
JOIN CLOSEUP_HOL1.RAW.PRODUCTS p ON f.PRODUCT_ID = p.PRODUCT_ID
GROUP BY p.THERAPEUTIC_AREA
ORDER BY NOTES DESC;

-- Verification: every note enriched, no empty AI columns
SELECT COUNT(*)                                  AS TOTAL_NOTES,
       COUNT_IF(SENTIMENT IS NULL)               AS MISSING_SENTIMENT,
       COUNT_IF(CATEGORY IS NULL)                AS MISSING_CATEGORY,
       COUNT_IF(SUMMARY IS NULL OR SUMMARY = '') AS MISSING_SUMMARY
FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED;
