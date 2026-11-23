# Lab 1B — From Data to AI Agent

**Duration: ~75 min · Difficulty: Beginner → Intermediate · 8 steps**

> This is the Markdown version of the guide, for reading on GitHub. For **Copy** buttons and progress tracking, download and open `lab1b_ai_agent.html` in your browser.

## Contents

- [Step 1: Check Day 1 & catch up (~5 min)](#step-1-check-day-1--catch-up-5-min)
- [Step 2: AI on Data: Cortex AI Functions (~10 min)](#step-2-ai-on-data-cortex-ai-functions-10-min)
- [Step 3: Semantic Layer: Semantic Views (~15 min)](#step-3-semantic-layer-semantic-views-15-min)
- [Step 4: Cortex Search (~8 min)](#step-4-cortex-search-8-min)
- [Step 5: Build the Agent (~15 min)](#step-5-build-the-agent-15-min)
- [Step 6: Use the Agent in Snowflake Intelligence (~12 min)](#step-6-use-the-agent-in-snowflake-intelligence-12-min)
- [Step 7: Security & Consumption (~10 min)](#step-7-security--consumption-10-min)
- [Step 8: Cleanup (after the event) (After the event)](#step-8-cleanup-after-the-event-after-the-event)

## Overview

In this second part you turn yesterday's data foundation into a conversational AI agent that answers quantitative and qualitative questions for business users, and then make it secure and cost-controlled.

### What you will learn

- Enriching unstructured field notes with Cortex AI Functions
- Creating a Semantic View as the business layer for Cortex Analyst
- Creating a Cortex Search service over field notes
- Building and using a Cortex Agent in Snowflake Intelligence following best practices
- Least-privilege roles, resource monitors and monitoring consumption

### Technologies

Cortex AI Functions · Semantic Views · Cortex Analyst · Cortex Search · Cortex Agents · Snowflake Intelligence · RBAC · Resource Monitors

> **Day 2 of 2 (26/11).**  This is Lab 1B. It continues from the objects
> you built in Lab 1A yesterday. Step 1 checks them and shows how to catch up if anything is missing.

> **Synthetic data** All data in this lab (pharmacies, laboratories, products, doctors, prescriptions, sales and field notes) is synthetically generated for training purposes only. It does not represent real Close-Up, customer or market data.

---

## Step 1: Check Day 1 & catch up (~5 min)

Lab 1B continues from what you built yesterday in Lab 1A. First, confirm that everything is in place.

### 1.1 Check yesterday's objects

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CLOSEUP_HOL1_WH;

SELECT 'RAW.SELL_OUT'                       AS OBJECT, COUNT(*) AS ROWS_ FROM CLOSEUP_HOL1.RAW.SELL_OUT
UNION ALL SELECT 'RAW.FIELD_NOTES',                    COUNT(*) FROM CLOSEUP_HOL1.RAW.FIELD_NOTES
UNION ALL SELECT 'CURATED.V_SALES',                    COUNT(*) FROM CLOSEUP_HOL1.CURATED.V_SALES
UNION ALL SELECT 'ANALYTICS.DT_MONTHLY_MARKET_SHARE',  COUNT(*) FROM CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE
UNION ALL SELECT 'ANALYTICS.DT_PRESCRIPTION_TRENDS',   COUNT(*) FROM CLOSEUP_HOL1.ANALYTICS.DT_PRESCRIPTION_TRENDS;
```

Expected: 5 rows, all with `ROWS_ > 0`.

### 1.2 Missing something? Catch up in 10 minutes

> **If any query above fails**  (you missed Day 1 or are on a new account),
> open **Lab 1A** and run every code block of steps 2, 3 and 4 in order. They are idempotent
> (`CREATE OR REPLACE`), so running them again is safe. Steps 1 and 5 of Lab 1A are not required.

### 1.3 Recap: where we are

RAW tables → CURATED views → ANALYTICS Dynamic Tables. Today we add the **AI layer** on top:
AI functions on field notes, a semantic view, a search service and an agent — and then we lock it down and keep costs under control.

---

### Recap: what you built in Step 1

- **You checked:** that the Lab 1A objects (RAW tables, curated views, Dynamic Tables) are in place, or rebuilt them with the catch-up script.
- **Starting point for today:** governed analytics data in `CLOSEUP_HOL1`. Everything you build next sits on top of it.

## Step 2: AI on Data: Cortex AI Functions (~10 min)

Close-Up's field force produces hundreds of free-text notes: competitor launches, stock-outs, price
changes, doctor feedback, regulatory news. With **Snowflake Cortex AISQL** functions we can turn that
unstructured text into structured, queryable columns, with plain SQL, without moving the data out of Snowflake.

| Function | What it does | Returns |
| --- | --- | --- |
| `AI_SENTIMENT` | Detects sentiment of a text | OBJECT → `:categories[0]:sentiment` = positive / negative / neutral / mixed |
| `AI_CLASSIFY` | Assigns a text to one of your labels | OBJECT → `:labels[0]` |
| `AI_COMPLETE` | Sends any prompt to an LLM (row by row) | Text |
| `AI_SUMMARIZE_AGG` | Aggregate function: summarizes many rows into one text | Text |

### 2.1 Try the functions

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CLOSEUP_HOL1_WH;
```

```sql
-- Try the functions on a single sentence first
SELECT
    AI_SENTIMENT('Doctors in Santiago report excellent tolerability, but stock-outs are hurting sales.') AS SENTIMENT_OBJECT,
    AI_SENTIMENT('Doctors in Santiago report excellent tolerability, but stock-outs are hurting sales.'):categories[0]:sentiment::VARCHAR AS OVERALL_SENTIMENT,
    AI_CLASSIFY('A competitor launched a cheaper generic in Brazil.',
                ['Competitor Activity', 'Supply / Stock-out', 'Pricing', 'Doctor Feedback', 'Regulatory']):labels[0]::VARCHAR AS CATEGORY;
```

> **Sentiment is a label, not a number** 
>
> `AI_SENTIMENT` returns an object such as `{"categories":[{"name":"overall","sentiment":"mixed"}]}`. Always extract the label with `:categories[0]:sentiment::VARCHAR` and compare it with strings like `'negative'`, never with numbers.

### 2.2 Enrich all field notes

One `CREATE TABLE ... AS SELECT` applies the three functions to the 300 notes and stores the results in
`AI.FIELD_NOTES_ENRICHED`. This table is the input for Cortex Search and the agent in the next steps.
It takes about a minute.

```sql
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
```

> **Model availability** 
>
> Model availability depends on your account region. If you get `unknown model`, either use another model available in your region (see `SHOW MODELS IN SNOWFLAKE.MODELS`, or the Cortex AI model list in the docs) or enable cross-region inference: `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';`

### 2.3 Explore the results

**Before and after.** Put the raw note next to what the AI added. Before, each note is only free text: to know whether it is negative or about a competitor, someone has to read it. After, the same note has structured columns that you can filter, group and count.

```sql
-- BEFORE (RAW.FIELD_NOTES) vs AFTER (AI.FIELD_NOTES_ENRICHED), side by side
SELECT
    r.NOTE_ID,
    r.COUNTRY,
    r.NOTE_TEXT              AS before_raw_text,
    e.SENTIMENT              AS after_sentiment,
    e.CATEGORY               AS after_category,
    e.SUMMARY                AS after_summary,
    LENGTH(r.NOTE_TEXT)      AS raw_chars,
    LENGTH(e.SUMMARY)        AS summary_chars
FROM CLOSEUP_HOL1.RAW.FIELD_NOTES r
JOIN CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED e
  ON e.NOTE_ID = r.NOTE_ID
ORDER BY r.NOTE_ID
LIMIT 10;

-- A question that was impossible BEFORE (free text only) and is one GROUP BY AFTER:
-- "Which countries have the most negative notes about competitor activity?"
SELECT COUNTRY, COUNT(*) AS negative_competitor_notes
FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED
WHERE CATEGORY = 'Competitor Activity'
  AND SENTIMENT = 'negative'
GROUP BY COUNTRY
ORDER BY negative_competitor_notes DESC;
```

> **What to notice:** the long `before_raw_text` becomes a sentiment label, one of five categories and a summary of about 20 words. If the last query returns no rows, run `SELECT DISTINCT SENTIMENT FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED;` to check which labels your model returned.

```sql
-- Look at the enriched rows
SELECT NOTE_ID, COUNTRY, SENTIMENT, CATEGORY, SUMMARY, NOTE_TEXT
FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED
LIMIT 10;

-- Distribution of categories and sentiment
SELECT CATEGORY, SENTIMENT, COUNT(*) AS NOTES
FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED
GROUP BY 1, 2
ORDER BY 1, 3 DESC;
```

### 2.4 Executive summary per therapeutic area

`AI_SUMMARIZE_AGG` works like `SUM` or `LISTAGG` but for meaning: it reads all
the notes of each group (here, joined to `RAW.PRODUCTS` to get the therapeutic area) and writes a single summary.
It handles inputs larger than the model context window automatically.

```sql
-- One executive summary per therapeutic area (aggregates ALL notes of each group)
SELECT
    p.THERAPEUTIC_AREA,
    COUNT(*)                      AS NOTES,
    AI_SUMMARIZE_AGG(f.NOTE_TEXT) AS AREA_SUMMARY
FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED f
JOIN CLOSEUP_HOL1.RAW.PRODUCTS p ON f.PRODUCT_ID = p.PRODUCT_ID
GROUP BY p.THERAPEUTIC_AREA
ORDER BY NOTES DESC;
```

> **Cost and tokens** 
>
> - AISQL functions are billed by **tokens** (input + output), not by warehouse size: an XSMALL warehouse is enough.
> - Persist results (CTAS) instead of calling the LLM in every dashboard query, and process only new rows in production.
> - Use task-specific functions (`AI_SENTIMENT`, `AI_CLASSIFY`) when possible: they are cheaper than a generic `AI_COMPLETE` prompt.
> - Keep prompts short and ask for short outputs ("one sentence, max 20 words").
> - Estimate before running at scale with `AI_COUNT_TOKENS` and monitor spend in `SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY`.

### 2.5 Verification

```sql
-- Verification: every note enriched, no empty AI columns
SELECT COUNT(*)                                  AS TOTAL_NOTES,
       COUNT_IF(SENTIMENT IS NULL)               AS MISSING_SENTIMENT,
       COUNT_IF(CATEGORY IS NULL)                AS MISSING_CATEGORY,
       COUNT_IF(SUMMARY IS NULL OR SUMMARY = '') AS MISSING_SUMMARY
FROM CLOSEUP_HOL1.AI.FIELD_NOTES_ENRICHED;
```

Expected: `TOTAL_NOTES = 300` and all `MISSING_*` columns = 0.

---

### Recap: what you built in Step 2

- **You built:** `AI.FIELD_NOTES_ENRICHED`: the 300 field notes with three new columns created by AI functions: `SENTIMENT` (`AI_SENTIMENT`), `CATEGORY` (`AI_CLASSIFY`) and `SUMMARY` (`AI_COMPLETE`), plus an executive summary per therapeutic area.
- **Before vs after:** free text that someone had to read became columns you can filter, group and count.
- **Key idea:** AI functions are plain SQL, run inside Snowflake, and respect the same roles and policies as any other query.
- **Take it to your projects:** any free-text column (call notes, complaints, survey answers) can be enriched the same way with a single `CREATE TABLE ... AS SELECT`.

## Step 3: Semantic Layer: Semantic Views (~15 min)

An LLM does not know that "sell-out", "revenue" and `NET_AMOUNT_USD` mean the same thing, which
table holds the therapeutic area, or how to compute market share. A **semantic view** is a schema-level
Snowflake object that captures this business knowledge once:

- **Logical tables** and their **relationships** (how to join safely).
- **Facts** (row-level numbers), **dimensions** (how to slice) and **metrics** (how to aggregate).
- **Synonyms and comments**: the business vocabulary that Cortex Analyst and agents use to map a question to SQL.

It becomes the **single source of truth**: the same definition of "total sales" or "market share" is used by
the AI agent, by SQL users and by BI tools, so everyone gets the same number.

### 3.1 Create the semantic view with SQL

Our model: the `sales` fact (from `CURATED.V_SALES`) references `products` and
`pharmacies`, and `products` references `labs`. Note the order of the clauses
(`TABLES` → `RELATIONSHIPS` → `FACTS` → `DIMENSIONS` → `METRICS`), which is mandatory.

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CLOSEUP_HOL1_WH;
```

```sql
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
```

> **How market share works here** 
>
> `total_market_sales_usd` is a **window metric**: `PARTITION BY EXCLUDING labs.lab_name` sums the sales of all laboratories for whatever other dimensions you query (country, month, therapeutic area...). Query it together with `lab_name` and divide: `total_sales_usd / total_market_sales_usd` = market share. The pre-computed version for monthly reporting lives in `ANALYTICS.DT_MONTHLY_MARKET_SHARE` (Lab 1A, step 4).

### 3.2 Inspect and query it

```sql
-- What does the semantic view expose?
DESCRIBE SEMANTIC VIEW CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET;
SHOW SEMANTIC METRICS    IN CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET;
SHOW SEMANTIC DIMENSIONS IN CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET;
```

You query a semantic view with the `SEMANTIC_VIEW(...)` clause: you only name the dimensions and metrics,
and Snowflake generates the joins and the `GROUP BY` for you.

```sql
-- Sales, units, price and numeric distribution by country and therapeutic area
SELECT * FROM SEMANTIC_VIEW(
    CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET
    DIMENSIONS pharmacies.country, products.therapeutic_area
    METRICS    sales.total_sales_usd, sales.total_units, sales.avg_price_usd, sales.pharmacy_count
)
ORDER BY total_sales_usd DESC
LIMIT 20;
```

```sql
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
```

### 3.3 Alternative: create it in the Snowsight UI

1. Go to **AI & ML → Cortex Analyst** and click **Create new → Create new Semantic View**.
2. Choose the location `CLOSEUP_HOL1.ANALYTICS`, a name (for example `SV_PHARMA_MARKET_UI`) and a description.
3. Optionally provide context (SQL queries or Tableau files) so the wizard (Semantic View Autopilot) can suggest metrics and relationships.
4. Select the tables `CURATED.V_SALES`, `RAW.PRODUCTS`, `RAW.LABORATORIES` and `RAW.PHARMACIES` and the columns to include.
5. Snowflake generates descriptions, synonyms and sample values with AI. **Review them**: edit synonyms, set primary keys and define relationships in the editor.
6. Click **Save**. You can also open our SQL-created `SV_PHARMA_MARKET` in the same editor to change it visually.

### 3.4 Add verified queries and sample questions

Verified queries are question → SQL pairs that you have checked to be correct. Cortex Analyst uses them as
examples, which strongly improves accuracy for similar questions.

1. Open `SV_PHARMA_MARKET` in **AI & ML → Cortex Analyst**.
2. In the **Playground** on the right, ask a question such as *"What was the market share of each laboratory in Cardiology in Brazil last month?"*.
3. Review the generated SQL and the result. If it is correct, click **Save as verified query** (add it to the *Verified queries* section).
4. Mark a few of them as **onboarding questions** (*"Use as onboarding question"*): they are shown to users as suggested sample questions.
5. Good candidates: *"Top 10 brands by sales in Argentina this year"*, *"Average price per unit by therapeutic area"*, *"Number of pharmacies selling Oncology products by country"*.

The same can be done in SQL with the `AI_VERIFIED_QUERIES` clause of `CREATE SEMANTIC VIEW`.

> **Semantic view best practices** 
>
> - Name things the way the business talks (`total_sales_usd`, not `sum_amt`) and write a **comment for every** table, dimension, fact and metric.
> - Add **synonyms** for local vocabulary: "sell-out", "TA", "lab", "drugstore", including terms your users write in Spanish or Portuguese.
> - Declare **primary keys and relationships** so joins are safe (no fan-out).
> - Define metrics once here (ratios as `SUM/SUM`, not `AVG` of ratios) and reuse them everywhere.
> - Keep it focused: one semantic view per business domain, only the columns users really need.
> - Add 5–20 **verified queries** for the most frequent questions and iterate with real user questions.

### 3.5 Verification

```sql
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
```

Expected: one row per country with `TOTAL_SHARE_PCT = 100.00`.

---

### Recap: what you built in Step 3

- **You built:** the semantic view `ANALYTICS.SV_PHARMA_MARKET`, with tables, relationships, dimensions, metrics, synonyms and verified queries.
- **Key idea:** the semantic view is the business dictionary that tells the AI what "market share" or "sell-out" means and how tables join. It is a governed object with grants, and you can also query it with SQL.
- **Take it to your projects:** define each metric once in the semantic view and reuse it for the agent and for BI, instead of rewriting the logic in every report.

## Step 4: Cortex Search (~8 min)

### What is Cortex Search?

Cortex Analyst (via the semantic view from step 3) answers **structured** questions with SQL. But a large part of market intelligence lives in **unstructured text**: the field notes written by reps about competitor launches, stock-outs, price changes and doctor feedback. **Cortex Search** is Snowflake's fully managed retrieval engine for that text.

- **Hybrid search:** combines vector (semantic) similarity with keyword (lexical) matching and a re-ranker, so "shortage" also finds notes that say "out of stock" or "supply disruption".
- **Fully managed:** no embeddings pipeline, no vector database. You define a SELECT and Snowflake keeps the index fresh according to `TARGET_LAG`.
- **Filterable attributes:** columns listed in `ATTRIBUTES` (here `COUNTRY` and `CATEGORY`) can be used as filters at query time.
- **Agent-ready:** the service becomes the `field_intelligence` tool of our agent in step 5 (RAG over field notes).

> **Why a title column?** We build a short `NOTE_TITLE` (category | country | date) so the agent and Snowflake Intelligence can show readable citations for each retrieved note.

### Create the search service

```sql
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
```

The initial index build takes about a minute for 300 notes. Check its state:

```sql
SHOW CORTEX SEARCH SERVICES IN SCHEMA CLOSEUP_HOL1.AI;
DESCRIBE CORTEX SEARCH SERVICE CLOSEUP_HOL1.AI.CS_FIELD_NOTES;
```

### Test it with SEARCH\_PREVIEW

A simple semantic query across all countries:

```sql
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
```

Now the same idea with a **filter** on the attributes: stock-out notes in Brazil only.

```sql
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
```

> **Filter operators:** `@eq`, `@contains` (arrays), `@gte` / `@lte` (numbers and dates), combined with `@and`, `@or`, `@not`. Only columns declared in `ATTRIBUTES` can be filtered.

### Verification

```sql
SELECT COUNT(*) AS results_returned
FROM TABLE(FLATTEN(
  PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
    'CLOSEUP_HOL1.AI.CS_FIELD_NOTES',
    '{"query": "price increase", "columns": ["NOTE_ID"], "limit": 5}'
  )):results
));
-- Expected: 5
```

---

### Recap: what you built in Step 4

- **You built:** the Cortex Search service `AI.CS_FIELD_NOTES` over the enriched field notes.
- **Key idea:** semantic search over text, fully managed: no embedding pipeline or vector database to maintain, and it refreshes automatically when the source changes.
- **Two tools ready:** the semantic view answers questions about numbers; Cortex Search answers questions about what the representatives wrote.

## Step 5: Build the Agent (~15 min)

### From tools to an agent

We now have two governed building blocks: the semantic view `SV_PHARMA_MARKET` (numbers) and the search service `CS_FIELD_NOTES` (text). A **Cortex Agent** puts an LLM orchestrator on top: it interprets the question, plans, chooses the right tool (or both), reflects on the results and writes the answer. Agents stored in `SNOWFLAKE_INTELLIGENCE.AGENTS` appear automatically in Snowflake Intelligence / CoWork.

### Best-practice principles we apply

| Principle | How it shows up in PHARMA\_MARKET\_AGENT |
| --- | --- |
| **Narrow, clear purpose** | Only pharma market intelligence for 4 LATAM countries. No HR, finance or forecasting. Out-of-scope questions are declined. |
| **Map use cases to tools** | "How much / who / trend" questions need SQL → Cortex Analyst. "What is being said / why" questions need text → Cortex Search. Exactly two tools, nothing more. |
| **Orchestration instructions** | Role, scope, users, domain context (what "sales" and "share" mean), tool selection rules, business rules (default period, top-N, no forecasts) and a "why" workflow (quantify first, then explain). |
| **Response instructions** | Tone, structure, tables vs charts, units and period always stated, how to cite field notes. |
| **Tool names & descriptions** | Names state domain + function (`market_analytics`, `field_intelligence`). Descriptions say what, which data, when to use and *when NOT to use*. This is the #1 factor for correct tool selection. |
| **Don't repeat the base prompt** | No generic "think step by step / call tools in order" text. Snowflake already provides base orchestration instructions. |

### Prepare the agent database, schema and grants

```sql
USE ROLE ACCOUNTADMIN;

-- Agents created here are discoverable in Snowflake Intelligence / CoWork
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_INTELLIGENCE;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS;

-- Let users see the agents (fine for a lab; use a dedicated role in production)
GRANT USAGE ON DATABASE SNOWFLAKE_INTELLIGENCE TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS TO ROLE PUBLIC;
GRANT CREATE AGENT ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS TO ROLE ACCOUNTADMIN;

-- Optional: allow models outside your region (recommended for 'auto' model selection)
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
```

> The role that *uses* the agent also needs USAGE on the agent, SELECT on the semantic view and its tables, USAGE on the search service and on `CLOSEUP_HOL1_WH`. In this lab we stay on ACCOUNTADMIN, which owns everything.

### Option A — Build the agent in the Snowsight UI

1. In Snowsight, go to **AI & ML → Agents** and click **Create agent**.
2. Database / schema: `SNOWFLAKE_INTELLIGENCE.AGENTS`. Agent object name: `PHARMA_MARKET_AGENT`. Display name: `Pharma Market Agent`. Click **Create agent**, then open it and click **Edit**.
3. **About** tab: paste the description below.
4. **Instructions** tab: paste the orchestration instructions and the response instructions (separate boxes), then add the sample questions.
5. **Tools** tab → **Cortex Analyst → + Add**: select *Semantic view* `CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET`, Name `market_analytics`, Warehouse `CLOSEUP_HOL1_WH` (custom warehouse), paste the description. Click **Add**.
6. **Tools** tab → **Cortex Search Services → + Add**: select `CLOSEUP_HOL1.AI.CS_FIELD_NOTES`, Name `field_intelligence`, ID column `NOTE_ID`, Title column `NOTE_TITLE`, paste the description. Click **Add**.
7. **Orchestration** tab: leave model as `auto`; optionally set a time budget (60 s) and a token budget (32,000).
8. Click **Save**. Use the preview chat on the right to ask one sample question.

#### About → Description

```text
Pharma market intelligence assistant for Close-Up International. Answers questions about pharmaceutical sell-out (sales in USD, units, rankings, trends, market share) by laboratory, product, therapeutic area, pharmacy and country in Argentina, Brazil, Uruguay and Chile, and explains them with qualitative signals from field-rep notes (competitor activity, stock-outs, pricing, doctor feedback, regulatory news).
```

#### Instructions → Orchestration instructions

```text
Your role: You are "Pharma Market Agent", a market intelligence assistant for Close-Up International.
Your scope: pharmaceutical sell-out performance (sales in USD, units, market share) by laboratory, product, molecule,
therapeutic area, pharmacy, channel and country, plus qualitative field intelligence reported by field reps
(competitor activity, stock-outs, pricing, doctor feedback, regulatory news).
Your users: Close-Up analysts, account managers and pharma lab clients in Argentina, Brazil, Uruguay and Chile.

Domain context:
- "Sales" means sell-out net amount in USD (metric total_sales_usd); "volume" means units (metric total_units).
- Market share = a lab's or product's sales divided by total market sales for the same period, country and therapeutic area.
- Therapeutic areas: Cardiology, Diabetes, Oncology, Respiratory, CNS, Gastroenterology, Dermatology, Analgesics.
- Data covers the last 24 months. All data in this lab is synthetic.

Tool selection:
- Use market_analytics for any question that needs numbers: sales, units, rankings, trends, growth, share, comparisons.
- Use field_intelligence for questions about what is being said in the field: reasons, comments, stock-outs,
  competitor launches, price changes, doctor feedback, regulatory news.
- For "why" questions about a number (e.g. why did sales drop), first use market_analytics to quantify the change,
  then use field_intelligence filtered by the same country and topic to find possible explanations.

Business rules:
- If no time period is given, use the last 12 months and say so.
- If no country is given for a ranking, show all four countries and break down by country when it is useful.
- Limit rankings to the top 10 unless the user asks for more.
- Do not forecast or predict future sales; you may describe historical trends only.
- If a question is outside pharma market intelligence, say it is out of scope.
```

#### Instructions → Response instructions

```text
- Be concise and professional. Lead with the direct answer, then supporting details.
- Use tables for more than 3 rows and charts for trends over time and rankings.
- Always include units (USD, units, %) and the time period and country used.
- Format USD with thousands separators and no more than 1 decimal for percentages.
- When citing field notes, quote briefly and mention the note date and country.
- Clearly separate facts from data (market_analytics) and qualitative signals (field_intelligence).
```

#### Instructions → Sample questions (add one by one)

```text
Who are the top 5 laboratories by sales in Brazil over the last 6 months?
What are field reps saying about stock-outs in Oncology?
How did Cardiology sales trend month by month in Argentina over the last year, and what explains the changes?
```

#### Tool: market\_analytics (Cortex Analyst) → Description

```text
Answers quantitative questions about pharmaceutical sell-out in Argentina, Brazil, Uruguay and Chile using the
semantic view SV_PHARMA_MARKET (sales, products, laboratories, pharmacies). Metrics: total_sales_usd (net sell-out
amount in USD) and total_units. Dimensions include sale date/month, laboratory, brand, molecule, ATC class,
therapeutic area, pharmacy, chain, channel, city, region and country.
Use it for rankings, totals, trends, growth, market share and comparisons.
Do NOT use it for field comments, opinions, reasons or news; use field_intelligence for those.
```

#### Tool: field\_intelligence (Cortex Search) → Description

```text
Searches field notes written by Close-Up field reps and market analysts (about 300 short reports) covering
competitor activity, supply / stock-outs, pricing, doctor feedback and regulatory news. Each note has a country,
category, sentiment, date and product.
Use it for qualitative "what is happening / why" questions. Filter by COUNTRY ('Argentina','Brazil','Uruguay','Chile')
and CATEGORY ('Competitor Activity','Supply / Stock-out','Pricing','Doctor Feedback','Regulatory') when the user
mentions them. Do NOT use it to compute sales numbers or rankings; use market_analytics for those.
```

### Option B (optional) — The same agent as code

Everything you configured in the UI is stored as a YAML specification. You can create (or recreate) the identical agent with SQL — ideal for CI/CD and versioning. If you already built it in the UI, running this simply replaces it.

```sql
CREATE OR REPLACE AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.PHARMA_MARKET_AGENT
  COMMENT = 'Close-Up pharma market intelligence agent (LATAM sell-out + field notes)'
  PROFILE = '{"display_name": "Pharma Market Agent", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    budget:
      seconds: 60
      tokens: 32000

  instructions:
    orchestration: |
      Your role: You are "Pharma Market Agent", a market intelligence assistant for Close-Up International.
      Your scope: pharmaceutical sell-out performance (sales in USD, units, market share) by laboratory, product, molecule,
      therapeutic area, pharmacy, channel and country, plus qualitative field intelligence reported by field reps
      (competitor activity, stock-outs, pricing, doctor feedback, regulatory news).
      Your users: Close-Up analysts, account managers and pharma lab clients in Argentina, Brazil, Uruguay and Chile.

      Domain context:
      - "Sales" means sell-out net amount in USD (metric total_sales_usd); "volume" means units (metric total_units).
      - Market share = a lab's or product's sales divided by total market sales for the same period, country and therapeutic area.
      - Therapeutic areas: Cardiology, Diabetes, Oncology, Respiratory, CNS, Gastroenterology, Dermatology, Analgesics.
      - Data covers the last 24 months. All data in this lab is synthetic.

      Tool selection:
      - Use market_analytics for any question that needs numbers: sales, units, rankings, trends, growth, share, comparisons.
      - Use field_intelligence for questions about what is being said in the field: reasons, comments, stock-outs,
        competitor launches, price changes, doctor feedback, regulatory news.
      - For "why" questions about a number (e.g. why did sales drop), first use market_analytics to quantify the change,
        then use field_intelligence filtered by the same country and topic to find possible explanations.

      Business rules:
      - If no time period is given, use the last 12 months and say so.
      - If no country is given for a ranking, show all four countries and break down by country when it is useful.
      - Limit rankings to the top 10 unless the user asks for more.
      - Do not forecast or predict future sales; you may describe historical trends only.
      - If a question is outside pharma market intelligence, say it is out of scope.
    response: |
      - Be concise and professional. Lead with the direct answer, then supporting details.
      - Use tables for more than 3 rows and charts for trends over time and rankings.
      - Always include units (USD, units, %) and the time period and country used.
      - Format USD with thousands separators and no more than 1 decimal for percentages.
      - When citing field notes, quote briefly and mention the note date and country.
      - Clearly separate facts from data (market_analytics) and qualitative signals (field_intelligence).
    sample_questions:
      - question: "Who are the top 5 laboratories by sales in Brazil over the last 6 months?"
      - question: "What are field reps saying about stock-outs in Oncology?"
      - question: "How did Cardiology sales trend month by month in Argentina over the last year, and what explains the changes?"

  tools:
    - tool_spec:
        type: "cortex_analyst_text_to_sql"
        name: "market_analytics"
        description: |
          Answers quantitative questions about pharmaceutical sell-out in Argentina, Brazil, Uruguay and Chile using the
          semantic view SV_PHARMA_MARKET (sales, products, laboratories, pharmacies). Metrics: total_sales_usd (net sell-out
          amount in USD) and total_units. Dimensions include sale date/month, laboratory, brand, molecule, ATC class,
          therapeutic area, pharmacy, chain, channel, city, region and country.
          Use it for rankings, totals, trends, growth, market share and comparisons.
          Do NOT use it for field comments, opinions, reasons or news; use field_intelligence for those.
    - tool_spec:
        type: "cortex_search"
        name: "field_intelligence"
        description: |
          Searches field notes written by Close-Up field reps and market analysts (about 300 short reports) covering
          competitor activity, supply / stock-outs, pricing, doctor feedback and regulatory news. Each note has a country,
          category, sentiment, date and product.
          Use it for qualitative "what is happening / why" questions. Filter by COUNTRY ('Argentina','Brazil','Uruguay','Chile')
          and CATEGORY ('Competitor Activity','Supply / Stock-out','Pricing','Doctor Feedback','Regulatory') when the user
          mentions them. Do NOT use it to compute sales numbers or rankings; use market_analytics for those.

  tool_resources:
    market_analytics:
      semantic_view: "CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET"
      execution_environment:
        type: "warehouse"
        warehouse: "CLOSEUP_HOL1_WH"
    field_intelligence:
      search_service: "CLOSEUP_HOL1.AI.CS_FIELD_NOTES"
      id_column: "NOTE_ID"
      title_column: "NOTE_TITLE"
      max_results: 5
  $$;
```

> **Spec keys:** `models.orchestration` (use `auto`), `orchestration.budget` (seconds / tokens caps), `instructions` (orchestration, response, sample\_questions), `tools[].tool_spec` (type, name, description) and `tool_resources` keyed by tool name (semantic view + warehouse; search service + id/title columns).

### Verification

```sql
SHOW AGENTS IN SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS;
DESCRIBE AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.PHARMA_MARKET_AGENT;
-- Expected: one row for PHARMA_MARKET_AGENT; agent_spec contains market_analytics and field_intelligence
```

---

### Recap: what you built in Step 5

- **You built:** the agent `SNOWFLAKE_INTELLIGENCE.AGENTS.PHARMA_MARKET_AGENT`, combining the semantic view (Cortex Analyst) and the search service, with instructions written following best practices.
- **The flow so far:** analytics tables → semantic view + search service → agent.
- **Key idea:** the agent decides which tool to use for each question, and it runs with the role of the user who asks.

## Step 6: Use the Agent in Snowflake Intelligence (~12 min)

### Open Snowflake Intelligence (CoWork)

1. Open [ai.snowflake.com](https://ai.snowflake.com) (or in Snowsight: **AI & ML → Snowflake Intelligence**) and sign in with the same account.
2. In the agent selector of the chat box, choose **Pharma Market Agent**.
3. Make sure your role is `ACCOUNTADMIN` for this lab (the agent runs with the caller's privileges).

> Answers are governed: the agent can only read what the current role can read. A user without SELECT on the semantic view tables will get a permissions message, not data.

### Ask these 8 questions

Copy them one at a time. Notice which tool the agent picks; the expected tool is shown in the last column.

| # | Type | Question | Expected tool |
| --- | --- | --- | --- |
| 1 | Quantitative | Who are the top 5 laboratories by sales in Brazil over the last 6 months? | `market_analytics` |
| 2 | Quantitative | Show monthly total units for Diabetes in Chile over the last 12 months as a chart. | `market_analytics` |
| 3 | Quantitative | Which therapeutic area grew the most in sales in Argentina, comparing the last 6 months vs. the previous 6 months? | `market_analytics` |
| 4 | Quantitative | Compare Retail Chain vs Independent vs Hospital channel sales by country for the last quarter. | `market_analytics` |
| 5 | Qualitative | What are field reps saying about stock-outs in Oncology? | `field_intelligence` |
| 6 | Qualitative | Summarize competitor activity reported in Uruguay, citing the most recent notes. | `field_intelligence` |
| 7 | Mixed | How did Cardiology sales trend month by month in Argentina over the last year, and what do the field notes say that could explain the changes? | `both` |
| 8 | Mixed | Which are the top 3 products by sales in Brazil, and is there any negative doctor feedback or pricing news about them? | `both` |

```text
Who are the top 5 laboratories by sales in Brazil over the last 6 months?
Show monthly total units for Diabetes in Chile over the last 12 months as a chart.
Which therapeutic area grew the most in sales in Argentina, comparing the last 6 months vs. the previous 6 months?
Compare Retail Chain vs Independent vs Hospital channel sales by country for the last quarter.
What are field reps saying about stock-outs in Oncology?
Summarize competitor activity reported in Uruguay, citing the most recent notes.
How did Cardiology sales trend month by month in Argentina over the last year, and what do the field notes say that could explain the changes?
Which are the top 3 products by sales in Brazil, and is there any negative doctor feedback or pricing news about them?
```

### Inspect how the agent reasoned

- **Thinking / planning:** expand the "Thinking" or steps panel above the answer to see how the orchestrator interpreted the question and planned tool calls.
- **Tool calls:** each step shows the tool used (`market_analytics` or `field_intelligence`), its input (the rewritten question or search query + filters) and its output.
- **Generated SQL:** for Cortex Analyst steps, open **Show SQL** to see the exact query run against `SV_PHARMA_MARKET`. Check the date filter and country filter match your intent.
- **Citations:** for Cortex Search steps, click the citations to see the original field notes (title = `NOTE_TITLE`, id = `NOTE_ID`).
- **Monitoring & tokens:** in Snowsight, **AI & ML → Agents → PHARMA\_MARKET\_AGENT → Monitoring** lists each conversation with its trace: duration, tool spans, model, and input/output token counts. Use it to find slow or expensive questions.

```sql
-- Account-level view of Snowflake Intelligence / agent consumption (may lag up to a few hours)
SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWFLAKE_INTELLIGENCE_USAGE_HISTORY
ORDER BY START_TIME DESC
LIMIT 20;
```

> ACCOUNT\_USAGE views have latency, so today's questions may not appear yet. The Monitoring tab of the agent is the fastest place to see per-question traces and tokens.

### Checklist: how to improve answers

| Symptom | Fix | Where |
| --- | --- | --- |
| Agent misunderstands a business term ("revenue", "players", "chains") | Add **synonyms** and better descriptions on dimensions/metrics | Semantic view |
| SQL is correct but not how the business calculates it (e.g. market share) | Add a **verified query** for that question pattern, or a dedicated metric | Semantic view (UI: Verified queries) |
| Wrong tool chosen | Sharpen the tool **descriptions**, especially the "Do NOT use for..." line | Agent → Tools |
| Inconsistent defaults (period, top-N, country) | Add explicit **business rules** | Orchestration instructions |
| Answers too long / wrong format | Tighten **response instructions** | Response instructions |
| Agent answers off-topic questions | Narrow the **scope** and add explicit boundaries | Orchestration instructions |
| Search returns irrelevant notes | Add attributes to filter on, improve the indexed text or title | Cortex Search service |

Iterate with a fixed set of ~20 real business questions: change one thing, re-ask, compare.

### Controlling tokens and consumption

- **Budget:** set `orchestration.budget` (seconds and tokens) so a single question cannot run away. We used 60 s / 32,000 tokens.
- **Model:** `auto` picks the best available model; for high-volume, simple use cases you can pin a smaller/cheaper orchestration model.
- **Narrow tools:** fewer, well-described tools mean fewer exploratory tool calls. Keep `max_results` on Cortex Search small (we use 5).
- **Good semantic view:** verified queries and clear metrics reduce retries and failed SQL.
- **Warehouse:** the Analyst tool runs SQL on `CLOSEUP_HOL1_WH` (XSMALL, auto-suspend 60 s); the search service refreshes on the same warehouse per `TARGET_LAG`.
- **Guardrails:** use budgets / resource monitors and review the Monitoring tab regularly.

### Verification

```sql
-- Confirm the agent and both tools it depends on exist and are reachable
SHOW AGENTS IN SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS;
SHOW CORTEX SEARCH SERVICES IN SCHEMA CLOSEUP_HOL1.AI;
SHOW SEMANTIC VIEWS IN SCHEMA CLOSEUP_HOL1.ANALYTICS;
```

---

### Recap: what you built in Step 6

- **You did:** asked the agent business questions in Snowflake Intelligence, combining numbers (semantic view) and context from field notes (search) in one answer.
- **Key idea:** business users get answers in natural language without writing SQL, on the same governed data the analysts use.
- **Take it to your projects:** start with a small set of well-defined questions, add them as verified queries, and grow the agent from real usage.

## Step 7: Security & Consumption (~10 min)

An agent is only production-ready when the right people can use it — and nobody can overspend.
This step uses features available in **every edition**, including Standard.

### 7.1 A least-privilege role for business users

```sql
USE ROLE USERADMIN;
CREATE ROLE IF NOT EXISTS HOL1_BUSINESS_USER COMMENT = 'Read curated data and use the market agent';

USE ROLE SECURITYADMIN;
GRANT USAGE ON WAREHOUSE CLOSEUP_HOL1_WH                  TO ROLE HOL1_BUSINESS_USER;
GRANT USAGE ON DATABASE CLOSEUP_HOL1                      TO ROLE HOL1_BUSINESS_USER;
GRANT USAGE ON SCHEMA CLOSEUP_HOL1.ANALYTICS              TO ROLE HOL1_BUSINESS_USER;
GRANT USAGE ON SCHEMA CLOSEUP_HOL1.AI                     TO ROLE HOL1_BUSINESS_USER;
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA CLOSEUP_HOL1.ANALYTICS TO ROLE HOL1_BUSINESS_USER;
GRANT SELECT ON SEMANTIC VIEW CLOSEUP_HOL1.ANALYTICS.SV_PHARMA_MARKET TO ROLE HOL1_BUSINESS_USER;
GRANT USAGE ON CORTEX SEARCH SERVICE CLOSEUP_HOL1.AI.CS_FIELD_NOTES TO ROLE HOL1_BUSINESS_USER;
GRANT USAGE ON DATABASE SNOWFLAKE_INTELLIGENCE            TO ROLE HOL1_BUSINESS_USER;
GRANT USAGE ON SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS       TO ROLE HOL1_BUSINESS_USER;
GRANT USAGE ON AGENT SNOWFLAKE_INTELLIGENCE.AGENTS.PHARMA_MARKET_AGENT TO ROLE HOL1_BUSINESS_USER;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER                 TO ROLE HOL1_BUSINESS_USER;

-- Give the role to yourself to test it
SET ME = CURRENT_USER();
GRANT ROLE HOL1_BUSINESS_USER TO USER IDENTIFIER($ME);
```

Note what the role does **not** get: the RAW schema (with the raw field notes) and any write privilege.

### 7.2 Test it

```sql
USE ROLE HOL1_BUSINESS_USER;
USE SECONDARY ROLES NONE;   -- test ONLY this role's privileges
SELECT COUNT(*) FROM CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE;   -- works
SELECT COUNT(*) FROM CLOSEUP_HOL1.RAW.SELL_OUT;                         -- fails: not authorized (expected!)

-- Back to normal
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES ALL;
```

> **Secondary roles.**  Many accounts default to `USE SECONDARY ROLES ALL`, so your session silently keeps the privileges of every role you have (including ACCOUNTADMIN). `USE SECONDARY ROLES NONE` makes you test exactly like a business user.

Then open Snowflake Intelligence with role `HOL1_BUSINESS_USER` and ask the agent a question — it works with only these grants.

### 7.3 Guardrail: a resource monitor on the warehouse

```sql
USE ROLE ACCOUNTADMIN;
CREATE OR REPLACE RESOURCE MONITOR CLOSEUP_HOL1_RM
  WITH CREDIT_QUOTA = 20 FREQUENCY = MONTHLY START_TIMESTAMP = IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND
           ON 110 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE CLOSEUP_HOL1_WH SET RESOURCE_MONITOR = CLOSEUP_HOL1_RM;
SHOW RESOURCE MONITORS LIKE 'CLOSEUP_HOL1_RM';
```

### 7.4 Where did the credits go?

```sql
-- Warehouse compute by day (ACCOUNT_USAGE has up to ~3h latency)
SELECT TO_DATE(START_TIME) AS DAY, WAREHOUSE_NAME, ROUND(SUM(CREDITS_USED), 3) AS CREDITS
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2 ORDER BY 1 DESC, 3 DESC;

-- Most expensive queries of the lab (elapsed time as a proxy)
SELECT QUERY_ID, LEFT(QUERY_TEXT, 80) AS QUERY, WAREHOUSE_NAME,
       TOTAL_ELAPSED_TIME / 1000 AS SECONDS, BYTES_SCANNED
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('day', -2, CURRENT_TIMESTAMP())
  AND DATABASE_NAME = 'CLOSEUP_HOL1'
ORDER BY TOTAL_ELAPSED_TIME DESC
LIMIT 10;
```

> **AI costs.**  AI functions, Cortex Search and agents are billed separately from warehouses.
> In Snowsight, **Admin » Cost Management** breaks spend down by service type (AI Services, Cortex Search, warehouses).

### 7.5 Verification

```sql
USE ROLE ACCOUNTADMIN;
SHOW GRANTS TO ROLE HOL1_BUSINESS_USER;
SHOW WAREHOUSES LIKE 'CLOSEUP_HOL1_WH';   -- column resource_monitor = CLOSEUP_HOL1_RM
```

---

### Recap: what you built in Step 7

- **You built:** the role `HOL1_BUSINESS_USER` with read access to curated data and the agent, and the resource monitor `CLOSEUP_HOL1_RM` on the lab warehouse.
- **Key idea:** access is granted to roles, never to users, and the agent inherits it: a user only sees through the agent what their role can see. Resource monitors cap warehouse credits.
- **Take it to your projects:** create functional roles per audience (business, analyst, engineer) and put a resource monitor on every warehouse from day one.

## Step 8: Cleanup (after the event) (After the event)

### Clean up

Run this only when you are done exploring. It removes every object created in this lab.

> **Irreversible for the agent and search service.** The database can be recovered with `UNDROP DATABASE` within the Time Travel retention period, but do not run this in an account where others are still working on the lab.

```sql
USE ROLE ACCOUNTADMIN;

-- 1. Agent
DROP AGENT IF EXISTS SNOWFLAKE_INTELLIGENCE.AGENTS.PHARMA_MARKET_AGENT;

-- 2. Cortex Search service (stops index refreshes)
DROP CORTEX SEARCH SERVICE IF EXISTS CLOSEUP_HOL1.AI.CS_FIELD_NOTES;

-- 3. Lab database (schemas, tables, views, dynamic tables, semantic view, stage)
DROP DATABASE IF EXISTS CLOSEUP_HOL1;

-- 4. Warehouse
DROP WAREHOUSE IF EXISTS CLOSEUP_HOL1_WH;

-- Optional: only if nothing else uses it
-- DROP DATABASE IF EXISTS SNOWFLAKE_INTELLIGENCE;
```

```sql
-- Objects added in Lab 1B, step 7
USE ROLE ACCOUNTADMIN;
DROP RESOURCE MONITOR IF EXISTS CLOSEUP_HOL1_RM;
DROP ROLE IF EXISTS HOL1_BUSINESS_USER;
```

### Verification

```sql
SHOW DATABASES LIKE 'CLOSEUP_HOL1';
SHOW WAREHOUSES LIKE 'CLOSEUP_HOL1_WH';
SHOW AGENTS LIKE 'PHARMA_MARKET_AGENT' IN SCHEMA SNOWFLAKE_INTELLIGENCE.AGENTS;
-- Expected: 0 rows for each
```

### Congratulations!

In about two and a half hours you went **from zero to an AI agent** on Close-Up-style pharma market data, entirely inside Snowflake.

| Step | What you built |
| --- | --- |
| 1. Snowflake basics | Warehouse, database and medallion-style schemas |
| 2. Ingestion | Stage, file formats, COPY INTO for CSV and JSON |
| 3. Exploring | Comments, data quality checks, micro-partitions, Time Travel |
| 4. Transformation | Curated views and Dynamic Tables for market share and prescriptions |
| 5. AI on data | AI\_SENTIMENT, AI\_CLASSIFY, AI\_COMPLETE, AI\_SUMMARIZE\_AGG on field notes |
| 6. Semantic layer | SV\_PHARMA\_MARKET semantic view with metrics and synonyms |
| 7. Cortex Search | Hybrid search service over field notes with filters |
| 8. Agent | PHARMA\_MARKET\_AGENT following best practices (UI and SQL) |
| 9. Snowflake Intelligence | Quantitative, qualitative and mixed questions, traces and tuning |

### Next steps

- Replace the synthetic tables with a real Close-Up dataset and reuse the same semantic view and agent pattern.
- Collect the top 20 questions from analysts and lab clients and turn them into verified queries and evaluation sets.
- Expose the agent through the Cortex Agents REST API inside your own applications.
- Read [Build agents (Snowflake docs)](https://docs.snowflake.com/en/user-guide/snowflake-cortex/snowflake-cowork/build-agents).

## Resources

- [Cortex Agents documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
- [Semantic Views documentation](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [Dynamic Tables documentation](https://docs.snowflake.com/en/user-guide/dynamic-tables-about)
- [Guide: Build an End-to-End AI App on Snowflake](https://www.snowflake.com/en/developers/guides/sfguide-build-end-to-end-ai-app-on-snowflake/)
- [Guide: Best Practices to Building Cortex Agents](https://www.snowflake.com/en/developers/guides/best-practices-to-building-cortex-agents/)

## Congratulations!

You went from raw data to a governed, cost-controlled AI agent: AI enrichment, a semantic layer, search and an agent in Snowflake Intelligence — all on a single platform.

---

© 2026 Snowflake Inc. All Rights Reserved.
