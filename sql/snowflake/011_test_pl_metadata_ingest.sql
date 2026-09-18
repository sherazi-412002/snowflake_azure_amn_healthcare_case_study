-- =====================================================================================
-- AMN Healthcare: Snowflake Post-Execution Validation for PL_METADATA_INGEST
-- Script 011: Test & Validate PL_METADATA_INGEST Runs
-- =====================================================================================
-- Purpose:
--   Run this worksheet in Snowsight after executing the parent ADF pipeline
--   `PL_METADATA_INGEST` (triggered by AMN_BATCH_READY.json or manual trigger).
--
-- Validation Checks:
--   1. INGESTION_CONFIG state verification (Enabled datasets & SLA thresholds)
--   2. PIPELINE_RUN_LOG execution status for parent and child pipelines
--   3. LOAD_CHECKPOINT watermark & batch synchronization
--   4. RAW layer ingestion verification (Batch IDs, timestamps, row counts)
--   5. CURATED layer merge verification & deduplication
--   6. Business rule & data integrity validation across entities
-- =====================================================================================

USE ROLE SYSADMIN;
USE WAREHOUSE AMN_TRANSFORM_WH;
USE DATABASE AMN_DEV;

-- Parameter: Adjust lookback window (in hours) as needed
SET LOOKBACK_HOURS = 2;

-- -------------------------------------------------------------------------------------
-- 1. Verify Ingestion Configuration & Target Metadata
-- Expected: All 5 active datasets (HOSPITALS, STAFFING_REQUESTS, CANDIDATES, SCHEDULES, PAYROLL)
-- -------------------------------------------------------------------------------------
SELECT
    SOURCE_SYSTEM,
    SOURCE_OBJECT,
    SOURCE_PATH,
    TARGET_SCHEMA,
    TARGET_TABLE,
    LOAD_TYPE,
    PRIMARY_KEY_COLUMNS,
    SLA_SECONDS,
    ENABLED,
    UPDATED_AT
FROM AMN_DEV.CONTROL.INGESTION_CONFIG
ORDER BY SOURCE_SYSTEM, SOURCE_OBJECT;


-- -------------------------------------------------------------------------------------
-- 2. Audit Trail & Pipeline Execution Logs (Parent & Child Pipelines)
-- Expected: STATUS = 'SUCCEEDED' for all child pipelines and parent metadata batch
-- -------------------------------------------------------------------------------------
SELECT
    RUN_ID,
    BATCH_ID,
    SOURCE_SYSTEM,
    SOURCE_OBJECT,
    TARGET_TABLE,
    STATUS,
    ROWS_READ,
    ROWS_INSERTED,
    ROWS_UPDATED,
    ROWS_DELETED,
    ROWS_REJECTED,
    EXTRACT_STARTED_AT,
    EXTRACT_FINISHED_AT,
    DATEDIFF('second', EXTRACT_STARTED_AT, EXTRACT_FINISHED_AT) AS DURATION_SECONDS,
    RAW_LOADED_AT,
    CURATED_AT,
    ERROR_MESSAGE
FROM AMN_DEV.CONTROL.PIPELINE_RUN_LOG
WHERE CREATED_AT >= DATEADD('hour', -$LOOKBACK_HOURS, CURRENT_TIMESTAMP())
ORDER BY CREATED_AT DESC;


-- -------------------------------------------------------------------------------------
-- 3. Execution Summary KPI Metrics
-- Expected: FAILED_COUNT = 0, SUCCEEDED_COUNT >= 5
-- -------------------------------------------------------------------------------------
SELECT
    COUNT(*) AS TOTAL_RUNS,
    COUNT_IF(STATUS = 'SUCCEEDED') AS SUCCEEDED_COUNT,
    COUNT_IF(STATUS = 'FAILED') AS FAILED_COUNT,
    COUNT_IF(STATUS = 'STARTED') AS IN_PROGRESS_COUNT,
    SUM(COALESCE(ROWS_READ, 0)) AS TOTAL_ROWS_PROCESSED,
    SUM(COALESCE(ROWS_INSERTED, 0)) AS TOTAL_ROWS_INSERTED,
    SUM(COALESCE(ROWS_UPDATED, 0)) AS TOTAL_ROWS_UPDATED,
    MIN(EXTRACT_STARTED_AT) AS BATCH_START_TIME,
    MAX(COALESCE(CURATED_AT, EXTRACT_FINISHED_AT)) AS BATCH_END_TIME
FROM AMN_DEV.CONTROL.PIPELINE_RUN_LOG
WHERE CREATED_AT >= DATEADD('hour', -$LOOKBACK_HOURS, CURRENT_TIMESTAMP());


-- -------------------------------------------------------------------------------------
-- 4. Verify Checkpoints & High Watermarks
-- Expected: Updated timestamps matching the latest batch execution
-- -------------------------------------------------------------------------------------
SELECT
    SOURCE_SYSTEM,
    SOURCE_OBJECT,
    TARGET_TABLE,
    LAST_WATERMARK,
    LAST_BATCH_ID,
    UPDATED_AT
FROM AMN_DEV.CONTROL.LOAD_CHECKPOINT
ORDER BY SOURCE_SYSTEM, SOURCE_OBJECT;


-- -------------------------------------------------------------------------------------
-- 5. Data Reconciliation: RAW vs CURATED Layer Row Counts
-- -------------------------------------------------------------------------------------
SELECT
    'HOSPITALS' AS ENTITY,
    (SELECT COUNT(*) FROM AMN_DEV.RAW.HOSPITALS) AS RAW_ROW_COUNT,
    (SELECT COUNT(*) FROM AMN_DEV.CURATED.HOSPITALS) AS CURATED_ROW_COUNT,
    (SELECT MAX(_INGESTED_AT) FROM AMN_DEV.RAW.HOSPITALS) AS LAST_RAW_INGESTED_AT,
    (SELECT MAX(UPDATED_AT) FROM AMN_DEV.CURATED.HOSPITALS) AS LAST_CURATED_UPDATED_AT
UNION ALL
SELECT
    'STAFFING_REQUESTS',
    (SELECT COUNT(*) FROM AMN_DEV.RAW.STAFFING_REQUESTS),
    (SELECT COUNT(*) FROM AMN_DEV.CURATED.STAFFING_REQUESTS),
    (SELECT MAX(_INGESTED_AT) FROM AMN_DEV.RAW.STAFFING_REQUESTS),
    (SELECT MAX(UPDATED_AT) FROM AMN_DEV.CURATED.STAFFING_REQUESTS)
UNION ALL
SELECT
    'CANDIDATES',
    (SELECT COUNT(*) FROM AMN_DEV.RAW.CANDIDATES),
    (SELECT COUNT(*) FROM AMN_DEV.CURATED.CANDIDATES),
    (SELECT MAX(_INGESTED_AT) FROM AMN_DEV.RAW.CANDIDATES),
    (SELECT MAX(UPDATED_AT) FROM AMN_DEV.CURATED.CANDIDATES)
UNION ALL
SELECT
    'SCHEDULES',
    (SELECT COUNT(*) FROM AMN_DEV.RAW.SCHEDULES),
    (SELECT COUNT(*) FROM AMN_DEV.CURATED.SCHEDULES),
    (SELECT MAX(_INGESTED_AT) FROM AMN_DEV.RAW.SCHEDULES),
    (SELECT MAX(UPDATED_AT) FROM AMN_DEV.CURATED.SCHEDULES)
UNION ALL
SELECT
    'PAYROLL',
    (SELECT COUNT(*) FROM AMN_DEV.RAW.PAYROLL),
    (SELECT COUNT(*) FROM AMN_DEV.CURATED.PAYROLL),
    (SELECT MAX(_INGESTED_AT) FROM AMN_DEV.RAW.PAYROLL),
    (SELECT MAX(UPDATED_AT) FROM AMN_DEV.CURATED.PAYROLL);


-- -------------------------------------------------------------------------------------
-- 6. Inspect Latest Ingestion Batch Per Table in RAW
-- -------------------------------------------------------------------------------------
WITH LATEST_RAW AS (
    SELECT 'HOSPITALS' AS TABLE_NAME, _BATCH_ID, _SOURCE_FILE, COUNT(*) AS RECORD_COUNT, MAX(_INGESTED_AT) AS INGESTED_AT
    FROM AMN_DEV.RAW.HOSPITALS GROUP BY _BATCH_ID, _SOURCE_FILE
    UNION ALL
    SELECT 'STAFFING_REQUESTS', _BATCH_ID, _SOURCE_FILE, COUNT(*), MAX(_INGESTED_AT)
    FROM AMN_DEV.RAW.STAFFING_REQUESTS GROUP BY _BATCH_ID, _SOURCE_FILE
    UNION ALL
    SELECT 'CANDIDATES', _BATCH_ID, _SOURCE_FILE, COUNT(*), MAX(_INGESTED_AT)
    FROM AMN_DEV.RAW.CANDIDATES GROUP BY _BATCH_ID, _SOURCE_FILE
    UNION ALL
    SELECT 'SCHEDULES', _BATCH_ID, _SOURCE_FILE, COUNT(*), MAX(_INGESTED_AT)
    FROM AMN_DEV.RAW.SCHEDULES GROUP BY _BATCH_ID, _SOURCE_FILE
    UNION ALL
    SELECT 'PAYROLL', _BATCH_ID, _SOURCE_FILE, COUNT(*), MAX(_INGESTED_AT)
    FROM AMN_DEV.RAW.PAYROLL GROUP BY _BATCH_ID, _SOURCE_FILE
)
SELECT *
FROM LATEST_RAW
QUALIFY ROW_NUMBER() OVER (PARTITION BY TABLE_NAME ORDER BY INGESTED_AT DESC) = 1
ORDER BY TABLE_NAME;


-- -------------------------------------------------------------------------------------
-- 7. Data Quality & Referential Integrity Verification in CURATED
-- Expected: All checks return 0 issues
-- -------------------------------------------------------------------------------------
-- Check A: Orphaned Staffing Requests (hospital not found in CURATED.HOSPITALS)
SELECT 'ORPHANED_STAFFING_REQUESTS' AS INTEGRITY_TEST, COUNT(*) AS FAILED_RECORD_COUNT
FROM AMN_DEV.CURATED.STAFFING_REQUESTS r
LEFT JOIN AMN_DEV.CURATED.HOSPITALS h ON r.HOSPITAL_ID = h.HOSPITAL_ID
WHERE h.HOSPITAL_ID IS NULL

UNION ALL

-- Check B: Candidates attached to invalid staffing requests
SELECT 'ORPHANED_CANDIDATE_REQUESTS', COUNT(*)
FROM AMN_DEV.CURATED.CANDIDATES c
LEFT JOIN AMN_DEV.CURATED.STAFFING_REQUESTS r ON c.REQUEST_ID = r.REQUEST_ID
WHERE c.REQUEST_ID IS NOT NULL AND r.REQUEST_ID IS NULL

UNION ALL

-- Check C: Schedules with negative planned/worked hours
SELECT 'INVALID_SCHEDULE_HOURS', COUNT(*)
FROM AMN_DEV.CURATED.SCHEDULES
WHERE PLANNED_HOURS < 0 OR WORKED_HOURS < 0 OR OVERTIME_HOURS < 0

UNION ALL

-- Check D: Payroll records with negative net pay
SELECT 'NEGATIVE_NET_PAY_RECORDS', COUNT(*)
FROM AMN_DEV.CURATED.PAYROLL
WHERE NET_PAY < 0;
