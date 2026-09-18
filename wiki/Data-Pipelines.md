# Data Pipelines & Engineering Mechanics

## 1. Dual Ingestion Contracts

* **Contract A: Event-Driven & Metadata Batch Ingestion**
  * Target: Canonical reference CSV files and historical backfills.
  * Trigger: `TR_LANDING_CSV_CREATED` (BlobCreated) or `TR_METADATA_INGEST_BATCH_READY` (`AMN_BATCH_READY.json`).
  * Process: ADF copies files to `RAW` via SAS staging, then calls `MERGE_*` stored procedures to idempotently merge into `CURATED`.

* **Contract B: Watermark-Based Incremental CDC**
  * Target: Frequently mutating hospital staffing requests, candidates, schedules, and payroll.
  * Trigger: `TR_INCREMENTAL_OPERATIONAL_2MIN` (2-minute recurring schedule).
  * Process: Queries `(old_watermark, new_watermark]` from Azure SQL, stages delta in Snowflake, executes merge, and advances checkpoint in `CONTROL.INGESTION_WATERMARK` only upon success.

## 2. Idempotent Deduplication Merge Example

```sql
MERGE INTO AMN_DEV.CURATED.STAFFING_REQUESTS tgt
USING (
    SELECT REQUEST_ID, HOSPITAL_ID, REQUIRED_ROLE, DEPARTMENT, 
           REQUIRED_STAFF, FILLED_STAFF, HOURLY_RATE_USD, REQUEST_STATUS,
           _BATCH_ID, _INGESTED_AT,
           ROW_NUMBER() OVER (PARTITION BY REQUEST_ID ORDER BY _INGESTED_AT DESC) as rn
    FROM AMN_DEV.RAW.STAFFING_REQUESTS
    WHERE _BATCH_ID = :batch_id
) src
ON tgt.REQUEST_ID = src.REQUEST_ID AND src.rn = 1
WHEN MATCHED THEN UPDATE SET ...
WHEN NOT MATCHED THEN INSERT (...);
```
