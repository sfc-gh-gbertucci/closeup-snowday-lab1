-- Step 2: Ingestion: Stages & COPY
-- Source: lab1a_data_foundation.html

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

CREATE OR REPLACE TABLE CLOSEUP_HOL1.RAW.FIELD_NOTES AS
SELECT
    V:NOTE_ID::VARCHAR     AS NOTE_ID,
    V:NOTE_DATE::DATE      AS NOTE_DATE,
    V:PRODUCT_ID::VARCHAR  AS PRODUCT_ID,
    V:COUNTRY::VARCHAR     AS COUNTRY,
    V:AUTHOR_ROLE::VARCHAR AS AUTHOR_ROLE,
    V:NOTE_TEXT::VARCHAR   AS NOTE_TEXT
FROM CLOSEUP_HOL1.RAW.FIELD_NOTES_JSON;

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
