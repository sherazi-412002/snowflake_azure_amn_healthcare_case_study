-- AMN Healthcare: post-run validation for all three ADF trigger paths.
--
-- Trigger paths covered:
--   1. TR_LANDING_CSV_CREATED
--      File-arrival routing to the individual CSV copy pipelines.
--   2. TR_METADATA_INGEST_BATCH_READY
--      AMN_BATCH_READY.json arrival to PL_METADATA_INGEST.
--   3. TR_INCREMENTAL_OPERATIONAL_2MIN
--      Azure SQL watermark-based incremental operational ingestion.
--
-- Run this worksheet after the ADF runs finish. Change LOOKBACK_HOURS if needed.
-- Snowflake validates the persisted result; the exact ADF trigger/pipeline run ID
-- must still be inspected in ADF Monitor unless it is written to PIPELINE_RUN_LOG.

USE ROLE SYSADMIN;
USE WAREHOUSE AMN_TRANSFORM_WH;
USE DATABASE AMN_DEV;

SET LOOKBACK_HOURS = 24;

-- ---------------------------------------------------------------------------
-- 1. Latest audited ADF result for each AMN object
-- Expected: one row per object, STATUS = SUCCEEDED, and recent timestamps.
-- SOURCE_SYSTEM = AZURE_SQL identifies operational incremental runs when the
-- incremental pipelines write that value to PIPELINE_RUN_LOG.
-- ---------------------------------------------------------------------------
SELECT
  SOURCE_SYSTEM,
  SOURCE_OBJECT,
  RUN_ID,
  BATCH_ID,
  STATUS,
  ROWS_READ,
  ROWS_INSERTED,
  ROWS_UPDATED,
  ROWS_DELETED,
  ROWS_REJECTED,
  EXTRACT_STARTED_AT,
  EXTRACT_FINISHED_AT,
  RAW_LOADED_AT,
  CURATED_AT,
  DATEDIFF('second', EXTRACT_STARTED_AT, EXTRACT_FINISHED_AT) AS RUN_SECONDS,
  ERROR_CATEGORY,
  ERROR_MESSAGE
FROM AMN_DEV.CONTROL.PIPELINE_RUN_LOG
WHERE CREATED_AT >= DATEADD('hour', -$LOOKBACK_HOURS, CURRENT_TIMESTAMP())
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY SOURCE_SYSTEM, SOURCE_OBJECT
  ORDER BY COALESCE(EXTRACT_STARTED_AT, CREATED_AT) DESC
) = 1
ORDER BY SOURCE_SYSTEM, SOURCE_OBJECT;

-- ---------------------------------------------------------------------------
-- 2. Recent audit summary
-- Expected: FAILED_RUNS = 0. A zero TOTAL_RUNS means audit logging did not run
-- or LOOKBACK_HOURS is too small; it does not prove that no ADF run occurred.
-- ---------------------------------------------------------------------------
SELECT
  COUNT(*) AS TOTAL_RUNS,
  COUNT_IF(STATUS = 'SUCCEEDED') AS SUCCEEDED_RUNS,
  COUNT_IF(STATUS = 'FAILED') AS FAILED_RUNS,
  COUNT_IF(STATUS = 'STARTED') AS STILL_STARTED_RUNS,
  SUM(COALESCE(ROWS_READ, 0)) AS TOTAL_ROWS_READ,
  SUM(COALESCE(ROWS_INSERTED, 0)) AS TOTAL_ROWS_INSERTED,
  SUM(COALESCE(ROWS_UPDATED, 0)) AS TOTAL_ROWS_UPDATED,
  SUM(COALESCE(ROWS_DELETED, 0)) AS TOTAL_ROWS_DELETED,
  MAX(COALESCE(CURATED_AT, RAW_LOADED_AT, EXTRACT_FINISHED_AT)) AS LAST_COMPLETED_AT
FROM AMN_DEV.CONTROL.PIPELINE_RUN_LOG
WHERE CREATED_AT >= DATEADD('hour', -$LOOKBACK_HOURS, CURRENT_TIMESTAMP());

-- ---------------------------------------------------------------------------
-- 3. Current row counts through the complete data path
-- RAW can be greater than CURATED because RAW is append-oriented and CURATED
-- merges multiple versions of the same business key.
-- ---------------------------------------------------------------------------
SELECT 'RAW' AS DATA_LAYER, 'HOSPITALS' AS DATA_OBJECT, COUNT(*) AS ROW_COUNT FROM AMN_DEV.RAW.HOSPITALS
UNION ALL SELECT 'CURATED', 'HOSPITALS', COUNT(*) FROM AMN_DEV.CURATED.HOSPITALS
UNION ALL SELECT 'RAW', 'STAFFING_REQUESTS', COUNT(*) FROM AMN_DEV.RAW.STAFFING_REQUESTS
UNION ALL SELECT 'CURATED', 'STAFFING_REQUESTS', COUNT(*) FROM AMN_DEV.CURATED.STAFFING_REQUESTS
UNION ALL SELECT 'RAW', 'CANDIDATES', COUNT(*) FROM AMN_DEV.RAW.CANDIDATES
UNION ALL SELECT 'CURATED', 'CANDIDATES', COUNT(*) FROM AMN_DEV.CURATED.CANDIDATES
UNION ALL SELECT 'RAW', 'SCHEDULES', COUNT(*) FROM AMN_DEV.RAW.SCHEDULES
UNION ALL SELECT 'CURATED', 'SCHEDULES', COUNT(*) FROM AMN_DEV.CURATED.SCHEDULES
UNION ALL SELECT 'RAW', 'PAYROLL', COUNT(*) FROM AMN_DEV.RAW.PAYROLL
UNION ALL SELECT 'CURATED', 'PAYROLL', COUNT(*) FROM AMN_DEV.CURATED.PAYROLL
ORDER BY DATA_OBJECT, DATA_LAYER;

-- ---------------------------------------------------------------------------
-- 4. Latest file/batch received in each RAW table
-- Expected after either file trigger: a new batch ID, recent ingestion time,
-- and a positive row count for the object delivered.
-- ---------------------------------------------------------------------------
WITH RAW_BATCHES AS (
  SELECT 'HOSPITALS' AS DATA_OBJECT, _BATCH_ID AS BATCH_ID, MAX(_INGESTED_AT) AS INGESTED_AT, COUNT(*) AS ROW_COUNT
  FROM AMN_DEV.RAW.HOSPITALS GROUP BY _BATCH_ID
  UNION ALL
  SELECT 'STAFFING_REQUESTS', _BATCH_ID, MAX(_INGESTED_AT), COUNT(*) FROM AMN_DEV.RAW.STAFFING_REQUESTS GROUP BY _BATCH_ID
  UNION ALL
  SELECT 'CANDIDATES', _BATCH_ID, MAX(_INGESTED_AT), COUNT(*) FROM AMN_DEV.RAW.CANDIDATES GROUP BY _BATCH_ID
  UNION ALL
  SELECT 'SCHEDULES', _BATCH_ID, MAX(_INGESTED_AT), COUNT(*) FROM AMN_DEV.RAW.SCHEDULES GROUP BY _BATCH_ID
  UNION ALL
  SELECT 'PAYROLL', _BATCH_ID, MAX(_INGESTED_AT), COUNT(*) FROM AMN_DEV.RAW.PAYROLL GROUP BY _BATCH_ID
)
SELECT DATA_OBJECT, BATCH_ID, INGESTED_AT, ROW_COUNT,
       IFF(INGESTED_AT >= DATEADD('hour', -$LOOKBACK_HOURS, CURRENT_TIMESTAMP()), 'PASS', 'OLD') AS RECENCY_CHECK
FROM RAW_BATCHES
QUALIFY ROW_NUMBER() OVER (PARTITION BY DATA_OBJECT ORDER BY INGESTED_AT DESC NULLS LAST) = 1
ORDER BY DATA_OBJECT;

-- ---------------------------------------------------------------------------
-- 5. CURATED primary-key quality checks
-- Expected: NULL_KEYS = 0 and DUPLICATE_KEYS = 0 for every object.
-- ---------------------------------------------------------------------------
SELECT 'HOSPITALS' AS DATA_OBJECT,
       COUNT_IF(HOSPITAL_ID IS NULL OR TRIM(HOSPITAL_ID) = '') AS NULL_KEYS,
       COUNT(*) - COUNT(DISTINCT HOSPITAL_ID) AS DUPLICATE_KEYS
FROM AMN_DEV.CURATED.HOSPITALS
UNION ALL
SELECT 'STAFFING_REQUESTS',
       COUNT_IF(REQUEST_ID IS NULL OR TRIM(REQUEST_ID) = ''),
       COUNT(*) - COUNT(DISTINCT REQUEST_ID)
FROM AMN_DEV.CURATED.STAFFING_REQUESTS
UNION ALL
SELECT 'CANDIDATES',
       COUNT_IF(CANDIDATE_ID IS NULL OR TRIM(CANDIDATE_ID) = ''),
       COUNT(*) - COUNT(DISTINCT CANDIDATE_ID)
FROM AMN_DEV.CURATED.CANDIDATES
UNION ALL
SELECT 'SCHEDULES',
       COUNT_IF(SCHEDULE_ID IS NULL OR TRIM(SCHEDULE_ID) = ''),
       COUNT(*) - COUNT(DISTINCT SCHEDULE_ID)
FROM AMN_DEV.CURATED.SCHEDULES
UNION ALL
SELECT 'PAYROLL',
       COUNT_IF(PAYROLL_ID IS NULL OR TRIM(PAYROLL_ID) = ''),
       COUNT(*) - COUNT(DISTINCT PAYROLL_ID)
FROM AMN_DEV.CURATED.PAYROLL
ORDER BY DATA_OBJECT;

-- ---------------------------------------------------------------------------
-- 6. Referential/business checks across CURATED tables
-- Expected: every issue count is 0. Empty optional foreign keys are excluded.
-- ---------------------------------------------------------------------------
SELECT 'STAFFING_REQUEST_WITH_UNKNOWN_HOSPITAL' AS CHECK_NAME, COUNT(*) AS ISSUE_COUNT
FROM AMN_DEV.CURATED.STAFFING_REQUESTS S
LEFT JOIN AMN_DEV.CURATED.HOSPITALS H ON H.HOSPITAL_ID = S.HOSPITAL_ID
WHERE NULLIF(TRIM(S.HOSPITAL_ID), '') IS NOT NULL AND H.HOSPITAL_ID IS NULL
UNION ALL
SELECT 'CANDIDATE_WITH_UNKNOWN_REQUEST', COUNT(*)
FROM AMN_DEV.CURATED.CANDIDATES C
LEFT JOIN AMN_DEV.CURATED.STAFFING_REQUESTS S ON S.REQUEST_ID = C.REQUEST_ID
WHERE NULLIF(TRIM(C.REQUEST_ID), '') IS NOT NULL AND S.REQUEST_ID IS NULL
UNION ALL
SELECT 'SCHEDULE_WITH_UNKNOWN_REQUEST', COUNT(*)
FROM AMN_DEV.CURATED.SCHEDULES X
LEFT JOIN AMN_DEV.CURATED.STAFFING_REQUESTS S ON S.REQUEST_ID = X.REQUEST_ID
WHERE NULLIF(TRIM(X.REQUEST_ID), '') IS NOT NULL AND S.REQUEST_ID IS NULL
UNION ALL
SELECT 'STAFFING_NEGATIVE_OPEN_POSITIONS', COUNT(*)
FROM AMN_DEV.CURATED.STAFFING_REQUESTS
WHERE OPEN_POSITIONS < 0;

-- ---------------------------------------------------------------------------
-- 7. Checkpoints used by repeatable ingestion
-- Expected: recent UPDATED_AT values and populated LAST_BATCH_ID/watermarks for
-- the source objects processed by the corresponding trigger path.
-- ---------------------------------------------------------------------------
SELECT
  SOURCE_SYSTEM,
  SOURCE_OBJECT,
  TARGET_TABLE,
  LAST_WATERMARK,
  LAST_BATCH_ID,
  UPDATED_AT,
  IFF(UPDATED_AT >= DATEADD('hour', -$LOOKBACK_HOURS, CURRENT_TIMESTAMP()), 'PASS', 'OLD') AS RECENCY_CHECK
FROM AMN_DEV.CONTROL.LOAD_CHECKPOINT
ORDER BY SOURCE_SYSTEM, SOURCE_OBJECT;

-- ---------------------------------------------------------------------------
-- 8. Data-quality results written by the metadata pipeline
-- Expected: FAILED_BLOCKING_CHECKS = 0.
-- ---------------------------------------------------------------------------
SELECT
  SOURCE_OBJECT,
  COUNT(*) AS CHECKS_EXECUTED,
  COUNT_IF(PASSED) AS CHECKS_PASSED,
  COUNT_IF(NOT PASSED) AS CHECKS_FAILED,
  COUNT_IF(NOT PASSED AND IS_BLOCKING) AS FAILED_BLOCKING_CHECKS,
  MAX(CHECKED_AT) AS LAST_CHECKED_AT
FROM AMN_DEV.CONTROL.DATA_QUALITY_RESULT
WHERE CHECKED_AT >= DATEADD('hour', -$LOOKBACK_HOURS, CURRENT_TIMESTAMP())
GROUP BY SOURCE_OBJECT
ORDER BY SOURCE_OBJECT;

-- ---------------------------------------------------------------------------
-- 9. Power BI serving-layer smoke tests
-- Expected: both queries return rows after CURATED transformations complete.
-- ---------------------------------------------------------------------------
SELECT * FROM AMN_DEV.MARTS.VW_EXECUTIVE_KPIS;

SELECT
  SOURCE_SYSTEM,
  SOURCE_OBJECT,
  STATUS,
  RUN_DURATION_SECONDS,
  WITHIN_RUN_SLA,
  ROWS_READ,
  ROWS_INSERTED,
  ROWS_UPDATED,
  ROWS_DELETED
FROM AMN_DEV.MARTS.VW_PIPELINE_LATEST_STATUS
ORDER BY SOURCE_SYSTEM, SOURCE_OBJECT;

