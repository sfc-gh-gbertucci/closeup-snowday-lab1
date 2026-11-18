# Lab 1A — Data Foundation

**Duration: ~50 min · Difficulty: Beginner → Intermediate · 5 steps**

> This is the Markdown version of the guide, for reading on GitHub. For **Copy** buttons and progress tracking, download and open `lab1a_data_foundation.html` in your browser.

## Contents

- [Step 1: Snowflake in 5 minutes (~5 min)](#step-1-snowflake-in-5-minutes-5-min)
- [Step 2: Ingestion: Stages & COPY (~15 min)](#step-2-ingestion-stages--copy-15-min)
- [Step 3: Storage & Exploring Data (~8 min)](#step-3-storage--exploring-data-8-min)
- [Step 4: Transformation: Views & Dynamic Tables (~12 min)](#step-4-transformation-views--dynamic-tables-12-min)
- [Step 5: Your first Snowsight dashboard (~10 min)](#step-5-your-first-snowsight-dashboard-10-min)

## Overview

In this lab you will build an end-to-end pharma market intelligence solution on Snowflake: from ingesting raw operational data to a conversational AI agent that answers quantitative and qualitative questions for business users.

### What you will learn

- Snowflake architecture (storage, compute, cloud services) and navigating Snowsight
- Loading data with internal stages, file formats and COPY INTO (CSV and JSON)
- Exploring, documenting and validating data quality
- Building declarative transformations with views and Dynamic Tables
- Enriching unstructured field notes with Cortex AI Functions
- Creating a Semantic View as the business layer for Cortex Analyst
- Creating a Cortex Search service over field notes
- Building and using a Cortex Agent in Snowflake Intelligence following best practices

### Technologies

Snowsight · Stages & COPY · Dynamic Tables · Cortex AI Functions · Semantic Views · Cortex Search · Cortex Agents · Snowflake Intelligence

> **Day 1 of 2 (25/11).**  This is Lab 1A: the data foundation
> (ingestion, storage, transformation and a dashboard). Tomorrow, Lab 1B continues from the objects you create today
> and adds AI, the semantic layer and the agent.

> **Synthetic data** All data in this lab (pharmacies, laboratories, products, doctors, prescriptions, sales and field notes) is synthetically generated for training purposes only. It does not represent real Close-Up, customer or market data.

---

## Step 1: Snowflake in 5 minutes (~5 min)

### Snowflake in five minutes

Snowflake is a fully managed data platform for storing, processing, sharing and running AI on data. Nothing needs to be installed, tuned or patched. It has three layers that scale independently:

| Layer | What it does | Why it matters for Close-Up |
| --- | --- | --- |
| **Storage** | Data is stored once in compressed, columnar *micro-partitions* on cloud object storage (AWS / Azure / GCP). | One copy of the sell-out, prescription and audit data for every team. You pay only for compressed TB stored. |
| **Compute (Virtual Warehouses)** | Independent compute clusters that run queries. They start in seconds, suspend automatically and can be resized at any time. | Loading, BI and data science each get their own warehouse, so one team's workload never slows down another's. |
| **Cloud Services** | The "brain": authentication, metadata, query optimization, transactions, security, governance and the AI services. | Security and governance work the same way across all data and all users. |

### Warehouses and credits

- A **virtual warehouse** is compute that you turn on and off. Sizes run from `XSMALL` (1 credit/hour) to `6XLARGE`, and each size up doubles both the credits and the compute power.
- Billing is **per second** (60-second minimum each time the warehouse resumes). With `AUTO_SUSPEND = 60` an idle warehouse stops after 1 minute, and `AUTO_RESUME` starts it again on the next query.
- Because **storage and compute are separate**, many warehouses can read the same data at the same time with no copies and no contention.

### Quick Snowsight tour

- **Home / Search**: the search bar at the top (Universal Search) finds tables, columns, worksheets and documentation.
- **Projects > Workspaces**: write and run SQL and Python. Use this to run the code in this lab.
- **Catalog > Database Explorer**: browse databases, schemas and tables, and preview data and lineage.
- **AI & ML**: Cortex AI functions, Cortex Search, Cortex Analyst, Agents and Snowflake Intelligence.
- **Monitoring**: query history, Dynamic Table and task graphs, copy history.
- **Admin**: warehouses, cost management, users & roles.

> **Tip:**  Open a new SQL file in *Projects > Workspaces* and keep it open for the whole lab. Use the Copy button on each code block and run the statements in order.

### Create the lab environment

The commands below create a small, cost-controlled warehouse, the lab database, and one schema for each stage of the data flow: `SOURCE_SYSTEM` (simulated operational system) → `RAW` (landing) → `CURATED` (clean views) → `ANALYTICS` (aggregates and semantic layer) → `AI` (AI enrichment and search).

```sql
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
```

### Verification

```sql
-- Expected: 5 schemas (AI, ANALYTICS, CURATED, RAW, SOURCE_SYSTEM)
SELECT SCHEMA_NAME, COMMENT
FROM CLOSEUP_HOL1.INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME NOT IN ('INFORMATION_SCHEMA', 'PUBLIC')
ORDER BY SCHEMA_NAME;

-- Warehouse size and auto-suspend setting
SHOW WAREHOUSES LIKE 'CLOSEUP_HOL1_WH';
```

> **Note:**  `ACCOUNTADMIN` is used here only to keep the setup simple. In production, objects are created by dedicated functional roles (for example `SYSADMIN` or a team role), and `ACCOUNTADMIN` is kept for account administration.

---

## Step 2: Ingestion: Stages & COPY (~15 min)

### The scenario

A real ingestion pipeline reads files exported from an operational system. To make the lab self-contained, the steps are:

1. **Simulate the source system**: generate 7 synthetic tables in `SOURCE_SYSTEM`.
2. **Export files**: unload the tables to an internal stage as CSV (and JSON for the field notes).
3. **Ingest**: load the files into the `RAW` layer with `COPY INTO`, the same way files from any external system are loaded.

| Table | Rows | Description |
| --- | --- | --- |
| LABORATORIES | 15 | Pharmaceutical laboratories (fictional), some of them Close-Up clients |
| PRODUCTS | 80 | Brands across 8 therapeutic areas, with molecule, ATC class and list price |
| PHARMACIES | 400 | Retail chains, independents and hospital pharmacies in AR, BR, UY, CL |
| DOCTORS | 600 | Prescribing physicians by specialty and city |
| SELL\_OUT | 150,000 | Pharmacy sales transactions, last 24 months |
| PRESCRIPTIONS | 60,000 | Prescription audit records |
| FIELD\_NOTES | 300 | Free-text field reports from reps and analysts |

> **How synthetic data is generated:**  `TABLE(GENERATOR(ROWCOUNT => N))` produces N rows, `SEQ4()` numbers them, `LPAD` builds readable IDs (`PRD001`), `UNIFORM(min, max, RANDOM())` creates random values and foreign keys within the primary key range, and `ARRAY_CONSTRUCT(...)[i]` picks realistic names from lists. All names are fictional.

### 2.1 Laboratories and products

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CLOSEUP_HOL1_WH;
USE SCHEMA CLOSEUP_HOL1.SOURCE_SYSTEM;

-- 15 fictional laboratories
CREATE OR REPLACE TABLE CLOSEUP_HOL1.SOURCE_SYSTEM.LABORATORIES AS
SELECT
    'LAB' || LPAD(SEQ4() + 1, 3, '0') AS LAB_ID,
    ARRAY_CONSTRUCT('Andina Pharma','Rioplata Laboratorios','Austral BioScience','Pampa Health','Cordillera Farma',
                    'Atlantica Labs','Solaris Therapeutics','Vitalis Sur','Meridian Pharma','Novagen Latam',
                    'Puerto Azul Farmaceutica','BioCruz','Terra Medica','Celestia Pharma','Horizonte Labs')[SEQ4()]::VARCHAR AS LAB_NAME,
    ARRAY_CONSTRUCT('Argentina','Argentina','Chile','Argentina','Chile','Brazil','USA','Uruguay','Switzerland','Brazil',
                    'Uruguay','Brazil','Germany','France','Brazil')[SEQ4()]::VARCHAR AS HQ_COUNTRY,
    (SEQ4() % 3 <> 2) AS IS_CLOSEUP_CLIENT
FROM TABLE(GENERATOR(ROWCOUNT => 15));

-- 80 products: 10 per therapeutic area, each with a real molecule
CREATE OR REPLACE TABLE CLOSEUP_HOL1.SOURCE_SYSTEM.PRODUCTS AS
WITH areas AS (
    SELECT ARRAY_CONSTRUCT('Cardiology','Diabetes','Oncology','Respiratory','CNS','Gastroenterology','Dermatology','Analgesics') AS ta,
           ARRAY_CONSTRUCT('C','A10','L01','R03','N06','A02','D07','N02') AS atc,
           ARRAY_CONSTRUCT(
               ARRAY_CONSTRUCT('Atorvastatin','Rosuvastatin','Losartan','Amlodipine','Bisoprolol','Valsartan','Clopidogrel','Enalapril','Rivaroxaban','Sacubitril/Valsartan'),
               ARRAY_CONSTRUCT('Metformin','Sitagliptin','Empagliflozin','Dapagliflozin','Gliclazide','Insulin Glargine','Liraglutide','Semaglutide','Vildagliptin','Linagliptin'),
               ARRAY_CONSTRUCT('Capecitabine','Imatinib','Letrozole','Anastrozole','Tamoxifen','Erlotinib','Abiraterone','Bicalutamide','Temozolomide','Lenalidomide'),
               ARRAY_CONSTRUCT('Salbutamol','Budesonide/Formoterol','Fluticasone/Salmeterol','Montelukast','Tiotropium','Beclometasone','Ipratropium','Desloratadine','Levocetirizine','Indacaterol'),
               ARRAY_CONSTRUCT('Sertraline','Escitalopram','Quetiapine','Clonazepam','Levetiracetam','Pregabalin','Venlafaxine','Aripiprazole','Lamotrigine','Duloxetine'),
               ARRAY_CONSTRUCT('Omeprazole','Pantoprazole','Esomeprazole','Domperidone','Trimebutine','Mesalazine','Lactulose','Ondansetron','Rabeprazole','Simethicone'),
               ARRAY_CONSTRUCT('Betamethasone','Mometasone','Clobetasol','Adapalene','Isotretinoin','Terbinafine','Tacrolimus','Mupirocin','Hydrocortisone','Calcipotriol'),
               ARRAY_CONSTRUCT('Ibuprofen','Paracetamol','Diclofenac','Ketorolac','Naproxen','Tramadol','Metamizole','Etoricoxib','Celecoxib','Aspirin')
           ) AS molecules,
           ARRAY_CONSTRUCT('Tablets 10 mg x 30','Tablets 20 mg x 30','Capsules 40 mg x 28','Tablets 500 mg x 60','Inhaler 200 doses',
                           'Cream 30 g','Injectable pen 3 ml','Oral solution 100 ml','Tablets 5 mg x 30','Capsules 150 mg x 14') AS presentations,
           ARRAY_CONSTRUCT('Cardio','Gluco','Onco','Respi','Neuro','Gastro','Derma','Algi') AS prefixes,
           ARRAY_CONSTRUCT('vex','tril','max','fort','zen','plus','xa','dol','lin','cor') AS suffixes
),
base AS (
    SELECT SEQ4() AS n, FLOOR(SEQ4() / 10) AS ta_idx, MOD(SEQ4(), 10) AS mol_idx
    FROM TABLE(GENERATOR(ROWCOUNT => 80))
)
SELECT
    'PRD' || LPAD(b.n + 1, 3, '0')                                  AS PRODUCT_ID,
    'LAB' || LPAD(MOD(b.n * 7, 15) + 1, 3, '0')                     AS LAB_ID,
    a.prefixes[b.ta_idx]::VARCHAR || a.suffixes[b.mol_idx]::VARCHAR AS BRAND_NAME,
    a.molecules[b.ta_idx][b.mol_idx]::VARCHAR                       AS MOLECULE,
    a.atc[b.ta_idx]::VARCHAR                                        AS ATC_CLASS,
    a.ta[b.ta_idx]::VARCHAR                                         AS THERAPEUTIC_AREA,
    a.presentations[MOD(b.n * 3, 10)]::VARCHAR                      AS PRESENTATION,
    -- Oncology is expensive, Diabetes mid-range, the rest are low-cost packs
    ROUND(CASE WHEN b.ta_idx = 2 THEN UNIFORM(150, 1200, RANDOM())
               WHEN b.ta_idx = 1 THEN UNIFORM(15, 180, RANDOM())
               ELSE UNIFORM(4, 60, RANDOM()) END + UNIFORM(0, 99, RANDOM()) / 100, 2)::NUMBER(10,2) AS LIST_PRICE_USD,
    DATEADD(DAY, -UNIFORM(365, 5500, RANDOM()), CURRENT_DATE())::DATE AS LAUNCH_DATE
FROM base b CROSS JOIN areas a;
```

### 2.2 Pharmacies and doctors (LATAM)

```sql
-- 400 pharmacies: ~55% retail chains, ~30% independents, ~15% hospitals
CREATE OR REPLACE TABLE CLOSEUP_HOL1.SOURCE_SYSTEM.PHARMACIES AS
WITH geo AS (
    SELECT ARRAY_CONSTRUCT('Buenos Aires','Cordoba','Rosario','Mendoza','Sao Paulo','Rio de Janeiro','Belo Horizonte','Porto Alegre','Curitiba','Montevideo','Punta del Este','Salto','Santiago','Valparaiso','Concepcion','Antofagasta') AS city,
           ARRAY_CONSTRUCT('AMBA','Centro','Litoral','Cuyo','Sudeste','Sudeste','Sudeste','Sul','Sul','Montevideo','Maldonado','Norte','Metropolitana','Valparaiso','Biobio','Norte Grande') AS region,
           ARRAY_CONSTRUCT('Argentina','Argentina','Argentina','Argentina','Brazil','Brazil','Brazil','Brazil','Brazil','Uruguay','Uruguay','Uruguay','Chile','Chile','Chile','Chile') AS country,
           ARRAY_CONSTRUCT('Farmacity','Farmacias del Pueblo','Drogaria Sol','Rede SaudeMais','Farmashop','Farmacias Ahumada','Cruz Verde Sur','Salcobrand Norte') AS chains,
           ARRAY_CONSTRUCT('San Martin','Central','La Esperanza','Santa Lucia','Del Parque','Vida','Nova','Del Sol','Belgrano','Libertad') AS names
),
base AS (SELECT SEQ4() AS n, UNIFORM(0, 15, RANDOM()) AS g, UNIFORM(1, 100, RANDOM()) AS r
         FROM TABLE(GENERATOR(ROWCOUNT => 400)))
SELECT
    'PH' || LPAD(b.n + 1, 4, '0') AS PHARMACY_ID,
    CASE WHEN b.r <= 55 THEN geo.chains[MOD(b.n, 8)]::VARCHAR || ' #' || (b.n + 1)
         WHEN b.r <= 85 THEN 'Farmacia ' || geo.names[MOD(b.n, 10)]::VARCHAR
         ELSE 'Hospital ' || geo.names[MOD(b.n, 10)]::VARCHAR || ' Pharmacy' END AS PHARMACY_NAME,
    CASE WHEN b.r <= 55 THEN geo.chains[MOD(b.n, 8)]::VARCHAR ELSE NULL END AS CHAIN,
    geo.city[b.g]::VARCHAR    AS CITY,
    geo.region[b.g]::VARCHAR  AS REGION,
    geo.country[b.g]::VARCHAR AS COUNTRY,
    CASE WHEN b.r <= 55 THEN 'Retail Chain' WHEN b.r <= 85 THEN 'Independent' ELSE 'Hospital' END AS CHANNEL
FROM base b CROSS JOIN geo;

-- 600 doctors
CREATE OR REPLACE TABLE CLOSEUP_HOL1.SOURCE_SYSTEM.DOCTORS AS
WITH ref AS (
    SELECT ARRAY_CONSTRUCT('Buenos Aires','Cordoba','Rosario','Mendoza','Sao Paulo','Rio de Janeiro','Belo Horizonte','Porto Alegre','Curitiba','Montevideo','Punta del Este','Salto','Santiago','Valparaiso','Concepcion','Antofagasta') AS city,
           ARRAY_CONSTRUCT('Argentina','Argentina','Argentina','Argentina','Brazil','Brazil','Brazil','Brazil','Brazil','Uruguay','Uruguay','Uruguay','Chile','Chile','Chile','Chile') AS country,
           ARRAY_CONSTRUCT('Cardiologist','Endocrinologist','Oncologist','Pulmonologist','Psychiatrist','Neurologist','Gastroenterologist','Dermatologist','General Practitioner','Internal Medicine') AS spec,
           ARRAY_CONSTRUCT('Maria','Juan','Ana','Carlos','Lucia','Pedro','Sofia','Diego','Camila','Rafael','Valentina','Martin','Fernanda','Joao','Isabel','Andres','Paula','Tomas','Beatriz','Gabriel') AS fn,
           ARRAY_CONSTRUCT('Gonzalez','Silva','Rodriguez','Santos','Fernandez','Oliveira','Lopez','Pereira','Martinez','Costa','Garcia','Souza','Perez','Alves','Sanchez','Rojas','Diaz','Lima','Torres','Munoz') AS ln
),
base AS (SELECT SEQ4() AS n, UNIFORM(0, 15, RANDOM()) AS g, UNIFORM(0, 9, RANDOM()) AS s,
                UNIFORM(0, 19, RANDOM()) AS f, UNIFORM(0, 19, RANDOM()) AS l
         FROM TABLE(GENERATOR(ROWCOUNT => 600)))
SELECT
    'DR' || LPAD(b.n + 1, 4, '0')                               AS DOCTOR_ID,
    'Dr. ' || ref.fn[b.f]::VARCHAR || ' ' || ref.ln[b.l]::VARCHAR AS DOCTOR_NAME,
    ref.spec[b.s]::VARCHAR                                      AS SPECIALTY,
    ref.city[b.g]::VARCHAR                                      AS CITY,
    ref.country[b.g]::VARCHAR                                   AS COUNTRY
FROM base b CROSS JOIN ref;
```

### 2.3 Transactions: sell-out and prescriptions

To make the sales data realistic, product popularity is skewed (a few brands sell much more than the rest), most baskets have 1–4 packs, and the net amount is `LIST_PRICE_USD × UNITS × discount` (0–20% pharmacy discount).

```sql
CREATE OR REPLACE TABLE CLOSEUP_HOL1.SOURCE_SYSTEM.SELL_OUT AS
WITH gen AS (
    SELECT
        SEQ4() AS n,
        DATEADD(DAY, -UNIFORM(1, 730, RANDOM()), CURRENT_DATE())::DATE AS sale_date,
        'PH' || LPAD(UNIFORM(1, 400, RANDOM()), 4, '0') AS pharmacy_id,
        -- popularity skew: squaring a uniform [0,1) value favours some products
        'PRD' || LPAD(FLOOR(POW(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()), 2) * 80) + 1, 3, '0') AS product_id,
        CASE WHEN UNIFORM(1, 100, RANDOM()) <= 70 THEN UNIFORM(1, 4, RANDOM())
             ELSE UNIFORM(5, 24, RANDOM()) END AS units,
        UNIFORM(80, 100, RANDOM()) / 100 AS discount_factor
    FROM TABLE(GENERATOR(ROWCOUNT => 150000))
)
SELECT
    'SO' || LPAD(g.n + 1, 7, '0') AS SALE_ID,
    g.sale_date                   AS SALE_DATE,
    g.pharmacy_id                 AS PHARMACY_ID,
    g.product_id                  AS PRODUCT_ID,
    g.units                       AS UNITS,
    ROUND(p.LIST_PRICE_USD * g.units * g.discount_factor, 2)::NUMBER(12,2) AS NET_AMOUNT_USD
FROM gen g
JOIN CLOSEUP_HOL1.SOURCE_SYSTEM.PRODUCTS p ON p.PRODUCT_ID = g.product_id;

CREATE OR REPLACE TABLE CLOSEUP_HOL1.SOURCE_SYSTEM.PRESCRIPTIONS AS
SELECT
    'RX' || LPAD(SEQ4() + 1, 7, '0')                                AS RX_ID,
    DATEADD(DAY, -UNIFORM(1, 730, RANDOM()), CURRENT_DATE())::DATE  AS RX_DATE,
    'DR' || LPAD(UNIFORM(1, 600, RANDOM()), 4, '0')                 AS DOCTOR_ID,
    'PRD' || LPAD(FLOOR(POW(UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()), 2) * 80) + 1, 3, '0') AS PRODUCT_ID,
    UNIFORM(1, 3, RANDOM())                                         AS QUANTITY
FROM TABLE(GENERATOR(ROWCOUNT => 60000));
```

### 2.4 Field notes (unstructured text)

Field reports are built by combining an opening (competitor launch, stock-out, price change, doctor feedback, regulation), a context sentence and a recommended action. Later in the lab these notes are processed with AI functions.

```sql
CREATE OR REPLACE TABLE CLOSEUP_HOL1.SOURCE_SYSTEM.FIELD_NOTES AS
WITH frag AS (
    SELECT
        ARRAY_CONSTRUCT(
            'A competitor launched a lower-priced generic of %B this month',
            'Several pharmacies reported a stock-out of %B for more than two weeks',
            'The list price of %B increased by around 8 percent after the last price update',
            'Doctors in the region gave very positive feedback on the tolerability of %B',
            'The health authority published a new regulation affecting the reimbursement of %B',
            'A rival laboratory started an aggressive sampling campaign against %B',
            'Distributors confirmed delayed deliveries of %B due to import permit issues',
            'Pharmacy chains are offering a 2x1 discount on a competing brand of %B',
            'Specialists complained about side effects reported by patients using %B',
            'The new clinical guideline now recommends %B as first-line therapy'
        ) AS openers,
        ARRAY_CONSTRUCT(
            ' in {C}, and independent pharmacies are switching patients quickly.',
            ' in {C}; hospital buyers are asking for revised commercial conditions.',
            ' across {C}, which is already visible in weekly sell-out data.',
            ' in {C}, although chain pharmacies have not yet changed their orders.',
            ' throughout {C}, and medical reps expect the impact to last at least one quarter.',
            ' in {C}; key opinion leaders are discussing it at local congresses.'
        ) AS middles,
        ARRAY_CONSTRUCT(
            ' Recommended action: reinforce visits to high-prescribing doctors.',
            ' Recommended action: review pricing strategy with the regional team.',
            ' Recommended action: coordinate inventory with the main distributor.',
            ' Recommended action: monitor market share closely over the next 8 weeks.',
            ' No immediate action required, follow-up next month.',
            ''
        ) AS closers,
        ARRAY_CONSTRUCT('Argentina','Brazil','Uruguay','Chile') AS countries,
        ARRAY_CONSTRUCT('Medical Representative','Key Account Manager','Market Analyst','Regional Manager','Market Access Lead') AS roles
),
base AS (
    SELECT SEQ4() AS n,
           UNIFORM(0, 9, RANDOM()) AS o, UNIFORM(0, 5, RANDOM()) AS m, UNIFORM(0, 5, RANDOM()) AS c,
           UNIFORM(0, 3, RANDOM()) AS k, UNIFORM(0, 4, RANDOM()) AS r,
           'PRD' || LPAD(UNIFORM(1, 80, RANDOM()), 3, '0') AS product_id,
           DATEADD(DAY, -UNIFORM(1, 365, RANDOM()), CURRENT_DATE())::DATE AS note_date
    FROM TABLE(GENERATOR(ROWCOUNT => 300))
)
SELECT
    'FN' || LPAD(b.n + 1, 4, '0') AS NOTE_ID,
    b.note_date                   AS NOTE_DATE,
    b.product_id                  AS PRODUCT_ID,
    f.countries[b.k]::VARCHAR     AS COUNTRY,
    f.roles[b.r]::VARCHAR         AS AUTHOR_ROLE,
    REPLACE(REPLACE(f.openers[b.o]::VARCHAR || f.middles[b.m]::VARCHAR || f.closers[b.c]::VARCHAR,
            '%B', p.BRAND_NAME || ' (' || p.MOLECULE || ')'),
            '{C}', f.countries[b.k]::VARCHAR) AS NOTE_TEXT
FROM base b
CROSS JOIN frag f
JOIN CLOSEUP_HOL1.SOURCE_SYSTEM.PRODUCTS p ON p.PRODUCT_ID = b.product_id;

-- Quick look
SELECT NOTE_ID, COUNTRY, AUTHOR_ROLE, NOTE_TEXT
FROM CLOSEUP_HOL1.SOURCE_SYSTEM.FIELD_NOTES
LIMIT 5;
```

### 2.5 Stage and file formats

- A **stage** is a location that holds files to be loaded or unloaded. An *internal* stage is storage managed by Snowflake. An *external* stage points to your own S3 / Azure Blob / GCS bucket. The `COPY INTO` commands are the same for both.
- A **file format** is a reusable definition of how files are parsed: delimiter, header, compression, NULL handling and JSON options.

```sql
-- CSV: skip the header line when loading; empty fields become NULL
CREATE OR REPLACE FILE FORMAT CLOSEUP_HOL1.RAW.FF_CSV
    TYPE = CSV
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL')
    EMPTY_FIELD_AS_NULL = TRUE
    COMPRESSION = GZIP;

-- JSON: one document per line (NDJSON); also accepts a top-level array
CREATE OR REPLACE FILE FORMAT CLOSEUP_HOL1.RAW.FF_JSON
    TYPE = JSON
    STRIP_OUTER_ARRAY = TRUE
    COMPRESSION = GZIP;

-- Internal stage with a directory table (lets you browse the files in Snowsight)
CREATE OR REPLACE STAGE CLOSEUP_HOL1.RAW.LANDING_STAGE
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = 'Internal landing stage for files coming from the source system';
```

### 2.6 Unload the source tables to files

`COPY INTO @stage FROM table` **unloads** data to files. `HEADER = TRUE` writes the column names on the first line. For the field notes, `OBJECT_CONSTRUCT(*)` turns each row into a JSON document, which is how semi-structured data usually arrives from APIs and applications.

```sql
COPY INTO @CLOSEUP_HOL1.RAW.LANDING_STAGE/laboratories/
    FROM CLOSEUP_HOL1.SOURCE_SYSTEM.LABORATORIES
    FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV') HEADER = TRUE OVERWRITE = TRUE;

COPY INTO @CLOSEUP_HOL1.RAW.LANDING_STAGE/products/
    FROM CLOSEUP_HOL1.SOURCE_SYSTEM.PRODUCTS
    FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV') HEADER = TRUE OVERWRITE = TRUE;

COPY INTO @CLOSEUP_HOL1.RAW.LANDING_STAGE/pharmacies/
    FROM CLOSEUP_HOL1.SOURCE_SYSTEM.PHARMACIES
    FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV') HEADER = TRUE OVERWRITE = TRUE;

COPY INTO @CLOSEUP_HOL1.RAW.LANDING_STAGE/doctors/
    FROM CLOSEUP_HOL1.SOURCE_SYSTEM.DOCTORS
    FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV') HEADER = TRUE OVERWRITE = TRUE;

COPY INTO @CLOSEUP_HOL1.RAW.LANDING_STAGE/sell_out/
    FROM CLOSEUP_HOL1.SOURCE_SYSTEM.SELL_OUT
    FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV') HEADER = TRUE OVERWRITE = TRUE;

COPY INTO @CLOSEUP_HOL1.RAW.LANDING_STAGE/prescriptions/
    FROM CLOSEUP_HOL1.SOURCE_SYSTEM.PRESCRIPTIONS
    FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV') HEADER = TRUE OVERWRITE = TRUE;

-- Field notes as JSON (one object per row)
COPY INTO @CLOSEUP_HOL1.RAW.LANDING_STAGE/field_notes/
    FROM (SELECT OBJECT_CONSTRUCT(*) FROM CLOSEUP_HOL1.SOURCE_SYSTEM.FIELD_NOTES)
    FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_JSON') OVERWRITE = TRUE;

-- See the files that were produced (expected: 7 compressed files)
LIST @CLOSEUP_HOL1.RAW.LANDING_STAGE;
```

> **Tip:**  In Snowsight, open *Catalog > Database Explorer > CLOSEUP\_HOL1 > RAW > Stages > LANDING\_STAGE* to browse the files. You can also upload local files there by drag and drop.

### 2.7 Load the files into the RAW layer

`COPY INTO table FROM @stage` **loads** files in parallel. Snowflake keeps **load metadata** for 64 days, so running the same COPY again skips files that were already loaded. Loads are idempotent by default.

```sql
-- RAW tables: same names and columns as the source system
CREATE OR REPLACE TABLE CLOSEUP_HOL1.RAW.LABORATORIES (LAB_ID VARCHAR, LAB_NAME VARCHAR, HQ_COUNTRY VARCHAR, IS_CLOSEUP_CLIENT BOOLEAN);
CREATE OR REPLACE TABLE CLOSEUP_HOL1.RAW.PRODUCTS (PRODUCT_ID VARCHAR, LAB_ID VARCHAR, BRAND_NAME VARCHAR, MOLECULE VARCHAR, ATC_CLASS VARCHAR,
                                                   THERAPEUTIC_AREA VARCHAR, PRESENTATION VARCHAR, LIST_PRICE_USD NUMBER(10,2), LAUNCH_DATE DATE);
CREATE OR REPLACE TABLE CLOSEUP_HOL1.RAW.PHARMACIES (PHARMACY_ID VARCHAR, PHARMACY_NAME VARCHAR, CHAIN VARCHAR, CITY VARCHAR,
                                                     REGION VARCHAR, COUNTRY VARCHAR, CHANNEL VARCHAR);
CREATE OR REPLACE TABLE CLOSEUP_HOL1.RAW.DOCTORS (DOCTOR_ID VARCHAR, DOCTOR_NAME VARCHAR, SPECIALTY VARCHAR, CITY VARCHAR, COUNTRY VARCHAR);
CREATE OR REPLACE TABLE CLOSEUP_HOL1.RAW.SELL_OUT (SALE_ID VARCHAR, SALE_DATE DATE, PHARMACY_ID VARCHAR, PRODUCT_ID VARCHAR,
                                                   UNITS NUMBER, NET_AMOUNT_USD NUMBER(12,2));
CREATE OR REPLACE TABLE CLOSEUP_HOL1.RAW.PRESCRIPTIONS (RX_ID VARCHAR, RX_DATE DATE, DOCTOR_ID VARCHAR, PRODUCT_ID VARCHAR, QUANTITY NUMBER);

-- Semi-structured landing table: one VARIANT column holds each JSON document
CREATE OR REPLACE TABLE CLOSEUP_HOL1.RAW.FIELD_NOTES_JSON (V VARIANT);

-- Load the CSV files
COPY INTO CLOSEUP_HOL1.RAW.LABORATORIES  FROM @CLOSEUP_HOL1.RAW.LANDING_STAGE/laboratories/  FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV');
COPY INTO CLOSEUP_HOL1.RAW.PRODUCTS      FROM @CLOSEUP_HOL1.RAW.LANDING_STAGE/products/      FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV');
COPY INTO CLOSEUP_HOL1.RAW.PHARMACIES    FROM @CLOSEUP_HOL1.RAW.LANDING_STAGE/pharmacies/    FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV');
COPY INTO CLOSEUP_HOL1.RAW.DOCTORS       FROM @CLOSEUP_HOL1.RAW.LANDING_STAGE/doctors/       FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV');
COPY INTO CLOSEUP_HOL1.RAW.SELL_OUT      FROM @CLOSEUP_HOL1.RAW.LANDING_STAGE/sell_out/      FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV');
COPY INTO CLOSEUP_HOL1.RAW.PRESCRIPTIONS FROM @CLOSEUP_HOL1.RAW.LANDING_STAGE/prescriptions/ FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_CSV');

-- Load the JSON files
COPY INTO CLOSEUP_HOL1.RAW.FIELD_NOTES_JSON FROM @CLOSEUP_HOL1.RAW.LANDING_STAGE/field_notes/ FILE_FORMAT = (FORMAT_NAME = 'CLOSEUP_HOL1.RAW.FF_JSON');

-- Peek at the raw JSON
SELECT V FROM CLOSEUP_HOL1.RAW.FIELD_NOTES_JSON LIMIT 3;
```

### 2.8 Typing the semi-structured data

A `VARIANT` column stores JSON as is. You read fields with path notation (`V:FIELD`) and cast them with `::TYPE`. Here a typed, relational `RAW.FIELD_NOTES` table is created from the JSON.

```sql
CREATE OR REPLACE TABLE CLOSEUP_HOL1.RAW.FIELD_NOTES AS
SELECT
    V:NOTE_ID::VARCHAR     AS NOTE_ID,
    V:NOTE_DATE::DATE      AS NOTE_DATE,
    V:PRODUCT_ID::VARCHAR  AS PRODUCT_ID,
    V:COUNTRY::VARCHAR     AS COUNTRY,
    V:AUTHOR_ROLE::VARCHAR AS AUTHOR_ROLE,
    V:NOTE_TEXT::VARCHAR   AS NOTE_TEXT
FROM CLOSEUP_HOL1.RAW.FIELD_NOTES_JSON;
```

### Verification

```sql
-- Expected: 15 / 80 / 400 / 600 / 150,000 / 60,000 / 300
SELECT 'LABORATORIES' AS table_name, COUNT(*) AS row_count FROM CLOSEUP_HOL1.RAW.LABORATORIES
UNION ALL SELECT 'PRODUCTS',      COUNT(*) FROM CLOSEUP_HOL1.RAW.PRODUCTS
UNION ALL SELECT 'PHARMACIES',    COUNT(*) FROM CLOSEUP_HOL1.RAW.PHARMACIES
UNION ALL SELECT 'DOCTORS',       COUNT(*) FROM CLOSEUP_HOL1.RAW.DOCTORS
UNION ALL SELECT 'SELL_OUT',      COUNT(*) FROM CLOSEUP_HOL1.RAW.SELL_OUT
UNION ALL SELECT 'PRESCRIPTIONS', COUNT(*) FROM CLOSEUP_HOL1.RAW.PRESCRIPTIONS
UNION ALL SELECT 'FIELD_NOTES',   COUNT(*) FROM CLOSEUP_HOL1.RAW.FIELD_NOTES;

-- Load audit: which file went to which table, rows loaded, errors
SELECT TABLE_NAME, FILE_NAME, STATUS, ROW_COUNT, ERROR_COUNT, LAST_LOAD_TIME
FROM CLOSEUP_HOL1.INFORMATION_SCHEMA.LOAD_HISTORY
WHERE SCHEMA_NAME = 'RAW'
ORDER BY LAST_LOAD_TIME DESC;

-- COPY_HISTORY: per-table detail (also covers Snowpipe loads)
SELECT TABLE_NAME, FILE_NAME, STATUS, ROW_COUNT, ROW_PARSED, FIRST_ERROR_MESSAGE, LAST_LOAD_TIME
FROM TABLE(CLOSEUP_HOL1.INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'CLOSEUP_HOL1.RAW.SELL_OUT',
    START_TIME => DATEADD(HOUR, -1, CURRENT_TIMESTAMP())));
```

> **Try it:**  run the `COPY INTO CLOSEUP_HOL1.RAW.SELL_OUT ...` statement again. The result is *"Copy executed with 0 files processed"* because Snowflake remembers which files it already loaded. `FORCE = TRUE` overrides this, but it creates duplicate rows.

---

## Step 3: Storage & Exploring Data (~8 min)

### Find your data with Universal Search

1. Click the **Search** bar at the top of Snowsight (or press `/`).
2. Type `sell out` or `pharmacies`. Universal Search matches table names, column names and **comments**, and it understands natural language (for example *"pharmacy sales by product"*).
3. Open `CLOSEUP_HOL1.RAW.SELL_OUT` and look at the *Columns*, *Data Preview* and *Lineage* tabs.

Search results are only as good as the metadata. Adding descriptions to tables and columns makes data easier to find for people, and the same descriptions are used later by the semantic view and the AI agent.

### 3.1 Document the key tables

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CLOSEUP_HOL1_WH;

-- SELL_OUT
COMMENT ON TABLE  CLOSEUP_HOL1.RAW.SELL_OUT IS 'Pharmacy sell-out transactions (synthetic): one row per product sale at a pharmacy, last 24 months';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.SELL_OUT.SALE_ID        IS 'Unique sale transaction identifier (PK)';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.SELL_OUT.SALE_DATE      IS 'Date the product was dispensed/sold at the pharmacy';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.SELL_OUT.PHARMACY_ID    IS 'FK to RAW.PHARMACIES.PHARMACY_ID';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.SELL_OUT.PRODUCT_ID     IS 'FK to RAW.PRODUCTS.PRODUCT_ID';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.SELL_OUT.UNITS          IS 'Number of packs (boxes) sold';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.SELL_OUT.NET_AMOUNT_USD IS 'Net sales value in USD after pharmacy discounts';

-- PRODUCTS
COMMENT ON TABLE  CLOSEUP_HOL1.RAW.PRODUCTS IS 'Pharmaceutical product catalog (brand, molecule, ATC class, therapeutic area, list price)';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PRODUCTS.PRODUCT_ID       IS 'Unique product identifier (PK)';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PRODUCTS.LAB_ID           IS 'FK to RAW.LABORATORIES.LAB_ID (manufacturer)';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PRODUCTS.BRAND_NAME       IS 'Commercial brand name of the product';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PRODUCTS.MOLECULE         IS 'Active ingredient (INN)';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PRODUCTS.ATC_CLASS        IS 'Anatomical Therapeutic Chemical (ATC) classification code';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PRODUCTS.THERAPEUTIC_AREA IS 'Therapeutic area, e.g. Cardiology, Oncology, CNS';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PRODUCTS.LIST_PRICE_USD   IS 'List price per pack in USD';

-- PHARMACIES
COMMENT ON TABLE  CLOSEUP_HOL1.RAW.PHARMACIES IS 'Pharmacy master data (retail chains, independents, hospitals) in Argentina, Brazil, Uruguay and Chile';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PHARMACIES.PHARMACY_ID IS 'Unique pharmacy identifier (PK)';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PHARMACIES.CHAIN       IS 'Pharmacy chain name; NULL for independent and hospital pharmacies';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PHARMACIES.COUNTRY     IS 'Country: Argentina, Brazil, Uruguay or Chile';
COMMENT ON COLUMN CLOSEUP_HOL1.RAW.PHARMACIES.CHANNEL     IS 'Distribution channel: Retail Chain, Independent or Hospital';

-- Check the result
SELECT TABLE_NAME, ROW_COUNT, BYTES, COMMENT
FROM CLOSEUP_HOL1.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
ORDER BY TABLE_NAME;
```

> **Tip:**  `ROW_COUNT` and `BYTES` come from metadata, so this query returns instantly without scanning data. Snowflake also uses metadata to answer `COUNT(*)`, `MIN` and `MAX` on many tables without using the warehouse.

### 3.2 Basic data quality checks

Before building anything on top of the RAW layer, check that the data is complete and consistent.

```sql
-- 1) Row counts per table
SELECT 'LABORATORIES' AS table_name, COUNT(*) AS row_count FROM CLOSEUP_HOL1.RAW.LABORATORIES
UNION ALL SELECT 'PRODUCTS',      COUNT(*) FROM CLOSEUP_HOL1.RAW.PRODUCTS
UNION ALL SELECT 'PHARMACIES',    COUNT(*) FROM CLOSEUP_HOL1.RAW.PHARMACIES
UNION ALL SELECT 'DOCTORS',       COUNT(*) FROM CLOSEUP_HOL1.RAW.DOCTORS
UNION ALL SELECT 'SELL_OUT',      COUNT(*) FROM CLOSEUP_HOL1.RAW.SELL_OUT
UNION ALL SELECT 'PRESCRIPTIONS', COUNT(*) FROM CLOSEUP_HOL1.RAW.PRESCRIPTIONS
UNION ALL SELECT 'FIELD_NOTES',   COUNT(*) FROM CLOSEUP_HOL1.RAW.FIELD_NOTES;

-- 2) NULLs, invalid values and duplicate keys in SELL_OUT (all should be 0)
SELECT
    COUNT(*)                                             AS total_rows,
    COUNT_IF(SALE_ID IS NULL)                            AS null_sale_id,
    COUNT_IF(SALE_DATE IS NULL)                          AS null_sale_date,
    COUNT_IF(PHARMACY_ID IS NULL)                        AS null_pharmacy,
    COUNT_IF(PRODUCT_ID IS NULL)                         AS null_product,
    COUNT_IF(UNITS IS NULL OR UNITS <= 0)                AS bad_units,
    COUNT_IF(NET_AMOUNT_USD IS NULL OR NET_AMOUNT_USD <= 0) AS bad_amount,
    COUNT(*) - COUNT(DISTINCT SALE_ID)                   AS duplicate_ids
FROM CLOSEUP_HOL1.RAW.SELL_OUT;

-- Expected NULLs: CHAIN is NULL for independent and hospital pharmacies
SELECT CHANNEL, COUNT(*) AS pharmacies, COUNT_IF(CHAIN IS NULL) AS null_chain
FROM CLOSEUP_HOL1.RAW.PHARMACIES
GROUP BY CHANNEL;

-- 3) Orphan foreign keys (all should be 0)
SELECT 'SELL_OUT -> PRODUCTS' AS fk_check, COUNT(*) AS orphan_rows
FROM CLOSEUP_HOL1.RAW.SELL_OUT s
LEFT JOIN CLOSEUP_HOL1.RAW.PRODUCTS p ON s.PRODUCT_ID = p.PRODUCT_ID
WHERE p.PRODUCT_ID IS NULL
UNION ALL
SELECT 'SELL_OUT -> PHARMACIES', COUNT(*)
FROM CLOSEUP_HOL1.RAW.SELL_OUT s
LEFT JOIN CLOSEUP_HOL1.RAW.PHARMACIES ph ON s.PHARMACY_ID = ph.PHARMACY_ID
WHERE ph.PHARMACY_ID IS NULL
UNION ALL
SELECT 'PRESCRIPTIONS -> DOCTORS', COUNT(*)
FROM CLOSEUP_HOL1.RAW.PRESCRIPTIONS r
LEFT JOIN CLOSEUP_HOL1.RAW.DOCTORS d ON r.DOCTOR_ID = d.DOCTOR_ID
WHERE d.DOCTOR_ID IS NULL
UNION ALL
SELECT 'PRODUCTS -> LABORATORIES', COUNT(*)
FROM CLOSEUP_HOL1.RAW.PRODUCTS p
LEFT JOIN CLOSEUP_HOL1.RAW.LABORATORIES l ON p.LAB_ID = l.LAB_ID
WHERE l.LAB_ID IS NULL;

-- 4) Date coverage (sell-out and prescriptions: ~24 months)
SELECT 'SELL_OUT' AS table_name, MIN(SALE_DATE) AS min_date, MAX(SALE_DATE) AS max_date,
       DATEDIFF(MONTH, MIN(SALE_DATE), MAX(SALE_DATE)) AS months_covered
FROM CLOSEUP_HOL1.RAW.SELL_OUT
UNION ALL
SELECT 'PRESCRIPTIONS', MIN(RX_DATE), MAX(RX_DATE), DATEDIFF(MONTH, MIN(RX_DATE), MAX(RX_DATE))
FROM CLOSEUP_HOL1.RAW.PRESCRIPTIONS
UNION ALL
SELECT 'FIELD_NOTES', MIN(NOTE_DATE), MAX(NOTE_DATE), DATEDIFF(MONTH, MIN(NOTE_DATE), MAX(NOTE_DATE))
FROM CLOSEUP_HOL1.RAW.FIELD_NOTES;
```

### 3.3 How Snowflake stores data: micro-partitions and Time Travel

Every table is automatically split into immutable, compressed, columnar **micro-partitions** (50–500 MB uncompressed each). For each partition Snowflake stores metadata such as the min/max value of every column, so a filter like `WHERE SALE_DATE >= '2026-01-01'` reads only the partitions that can contain matching rows (*partition pruning*). No indexes or manual partitioning are needed. Because partitions are never modified in place (changes write new partitions), Snowflake can keep previous versions. This is **Time Travel**: you can query, clone or restore a table as it was at a point in the past (1 day by default, up to 90 days on Enterprise Edition), and recover dropped objects with `UNDROP`.

```sql
-- Time Travel: the table as it was 60 seconds ago, compared with now
SELECT
    (SELECT COUNT(*) FROM CLOSEUP_HOL1.RAW.SELL_OUT AT(OFFSET => -60)) AS rows_60_seconds_ago,
    (SELECT COUNT(*) FROM CLOSEUP_HOL1.RAW.SELL_OUT)                   AS rows_now;
```

> **Warning:**  Time Travel cannot go back to before the table existed. If you loaded `RAW.SELL_OUT` less than 60 seconds ago, the query returns an error or 0 rows. Wait a minute and run it again.

### Verification

```sql
-- Expected: SELL_OUT, PRODUCTS and PHARMACIES have comments; documented columns listed
SELECT TABLE_NAME, COLUMN_NAME, DATA_TYPE, COMMENT
FROM CLOSEUP_HOL1.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'RAW'
  AND TABLE_NAME IN ('SELL_OUT', 'PRODUCTS', 'PHARMACIES')
  AND COMMENT IS NOT NULL
ORDER BY TABLE_NAME, ORDINAL_POSITION;
```

---

## Step 4: Transformation: Views & Dynamic Tables (~12 min)

Raw data is rarely ready for analysis. In this step we build a simple, layered architecture
(a "medallion-ish" design) entirely inside Snowflake, using only SQL:

| Layer | Schema | Object type | Purpose |
| --- | --- | --- | --- |
| Raw / Bronze | `RAW` | Tables | Data exactly as loaded from the source (Step 2). |
| Curated / Silver | `CURATED` | Views | Cleaned and joined business entities: one row per sale / prescription with all attributes. |
| Analytics / Gold | `ANALYTICS` | Dynamic Tables | Pre-aggregated, always-fresh KPIs (market share, prescription trends) ready for BI and AI. |

> **Views vs. Dynamic Tables** 
>
> A **view** stores only the query: it is computed every time you read it (always up to date, no storage). A **Dynamic Table** stores the result and Snowflake keeps it fresh automatically within a `TARGET_LAG` you choose. No tasks, no schedulers, no orchestration code: you declare *what* you want, Snowflake figures out *when* and *how* to refresh it (incrementally when possible).

### 4.1 Set the context

```sql
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE CLOSEUP_HOL1_WH;
USE DATABASE CLOSEUP_HOL1;
```

### 4.2 Curated layer: business views

`V_SALES` joins every sell-out transaction with its product, laboratory and pharmacy, and adds a
`SALE_MONTH` column. Because each sale matches exactly one product and one pharmacy, the row count is preserved.

```sql
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
```

`V_PRESCRIPTIONS` does the same for prescriptions, adding the doctor's specialty and country.

```sql
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
```

### 4.3 Analytics layer: Dynamic Tables

`DT_MONTHLY_MARKET_SHARE` calculates, for every month, country and therapeutic area, the sales of each
laboratory and its **market share %** using a window function (`SUM(...) OVER (PARTITION BY ...)`).

```sql
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
```

> **Avoid join fan-out** 
>
> Joining a fact table to a dimension that accidentally has duplicate keys multiplies rows and inflates sums. The pattern above protects you: dimensions are wrapped in CTEs with `DISTINCT` and the fact table is **pre-aggregated** (`sales_pre`) before joining. It is also cheaper: we join ~thousands of aggregated rows instead of 150,000 transactions.

`DT_PRESCRIPTION_TRENDS` follows the same pattern for prescriptions, by doctor specialty.

```sql
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
```

> **Refresh mode** 
>
> When you create these tables Snowflake may report that `FULL` refresh mode was selected (window functions and multi-level aggregations are complex for incremental maintenance). That is fine for this data volume. For large pipelines you can set `REFRESH_MODE = INCREMENTAL` explicitly and design the query so only changed rows are reprocessed.

### 4.4 Refresh and monitor

Dynamic Tables refresh by themselves, but you can also trigger a refresh on demand and inspect the history:

```sql
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
```

In the history you will see a `CREATION` refresh (initial load) and your `MANUAL` one.
If no source data changed, the action is `NO_DATA`: Snowflake skips the work and you pay nothing.

### 4.5 See the pipeline graph in Snowsight

1. In Snowsight go to **Catalog → Database Explorer** (or **Data → Databases**) → `CLOSEUP_HOL1` → `ANALYTICS` → **Dynamic Tables**.
2. Click `DT_MONTHLY_MARKET_SHARE` and open the **Graph** tab: you will see the lineage from the RAW tables to the Dynamic Table.
3. Open the **Refresh History** tab to see each refresh, its duration and its lag compared to the target.
4. Alternatively, **Transformation → Dynamic Tables** (Monitoring) lists all Dynamic Tables in the account with their state.

### 4.6 Verification

```sql
-- Verification: market shares per (month, country, therapeutic area) must add up to ~100%
SELECT MONTH, COUNTRY, THERAPEUTIC_AREA,
       COUNT(*)              AS LABS,
       SUM(SALES_USD)        AS SALES_USD,
       SUM(MARKET_SHARE_PCT) AS TOTAL_SHARE_PCT
FROM CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE
GROUP BY 1, 2, 3
ORDER BY MONTH DESC, COUNTRY, THERAPEUTIC_AREA
LIMIT 20;
```

Expected: `TOTAL_SHARE_PCT` is 100.00 (or 99.99 / 100.01 due to rounding) for every row.

---

## Step 5: Your first Snowsight dashboard (~10 min)

You now have curated views and Dynamic Tables. Before going to AI tomorrow, let's turn them into a
**Snowsight dashboard** — no BI tool required. Each tile is just a SQL query plus a chart.

### 5.1 Create the dashboard

1. In Snowsight go to **Projects » Dashboards » + Dashboard**. Name it `Close-Up Market Overview`.
2. Set the role to `ACCOUNTADMIN` and the warehouse to `CLOSEUP_HOL1_WH` (top right).
3. Click **+ New Tile » From SQL Worksheet** for each query below, run it, open the **Chart** tab and pick the chart type suggested.

### 5.2 Tile 1 — Monthly sales trend (Line chart)

```sql
SELECT MONTH, SUM(SALES_USD) AS SALES_USD
FROM CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE
GROUP BY MONTH
ORDER BY MONTH;
```

Chart: **Line**, X = `MONTH`, Y = `SALES_USD`.

### 5.3 Tile 2 — Market share by laboratory (Bar chart)

```sql
SELECT LAB_NAME, ROUND(SUM(SALES_USD) / SUM(SUM(SALES_USD)) OVER () * 100, 2) AS SHARE_PCT
FROM CLOSEUP_HOL1.ANALYTICS.DT_MONTHLY_MARKET_SHARE
GROUP BY LAB_NAME
ORDER BY SHARE_PCT DESC;
```

Chart: **Bar**, X = `LAB_NAME`, Y = `SHARE_PCT`.

### 5.4 Tile 3 — Prescriptions by specialty and therapeutic area (Heatgrid)

```sql
SELECT SPECIALTY, THERAPEUTIC_AREA, SUM(RX_COUNT) AS RX_COUNT
FROM CLOSEUP_HOL1.ANALYTICS.DT_PRESCRIPTION_TRENDS
GROUP BY 1, 2
ORDER BY 1, 2;
```

Chart: **Heatgrid**, rows = `SPECIALTY`, columns = `THERAPEUTIC_AREA`, cell = `RX_COUNT`.

### 5.5 Tile 4 — Top 10 pharmacies (Table) with a filter

```sql
SELECT PHARMACY_NAME, CHAIN, CITY, COUNTRY, SUM(NET_AMOUNT_USD) AS SALES_USD
FROM CLOSEUP_HOL1.CURATED.V_SALES
WHERE SALE_DATE = :daterange
GROUP BY 1, 2, 3, 4
ORDER BY SALES_USD DESC
LIMIT 10;
```

> **System filters.**  `:daterange` is a built-in Snowsight filter: the dashboard shows a date picker at the top and every tile that uses it is filtered together.

### 5.6 Verification

Your dashboard shows 4 tiles and changing the date range updates Tile 4. Share it with a colleague via **Share** (top right).

> **See you tomorrow!**  Do *not* run any cleanup today — Lab 1B continues from these objects.

## Resources

- [Cortex Agents documentation](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents)
- [Semantic Views documentation](https://docs.snowflake.com/en/user-guide/views-semantic/overview)
- [Dynamic Tables documentation](https://docs.snowflake.com/en/user-guide/dynamic-tables-about)
- [Guide: Build an End-to-End AI App on Snowflake](https://www.snowflake.com/en/developers/guides/sfguide-build-end-to-end-ai-app-on-snowflake/)
- [Guide: Best Practices to Building Cortex Agents](https://www.snowflake.com/en/developers/guides/best-practices-to-building-cortex-agents/)

## Congratulations!

You went from zero to a working AI agent: ingestion, transformation, AI enrichment, a semantic layer, search and an agent in Snowflake Intelligence — all on a single platform.

---

© 2026 Snowflake Inc. All Rights Reserved.
