# AMN Case Study Implementation: Baby Steps

This guide turns the AMN-inspired architecture into small implementation tasks. Complete each checkpoint before moving forward. The goal is to prove a five-table pipeline locally, move it to Snowflake and Azure Data Factory (ADF), meet a measurable freshness target, and only then scale toward millions of changes and 1,100+ tables.

## What you are building

```text
CSV/source systems
      |
      v
ADF or local loader
      |
      v
Snowflake RAW -> CURATED -> MARTS -> Power BI
                     |
                     v
             audit and SLA metrics
```

Use these five tables for the first end-to-end slice:

1. Hospitals
2. Candidates
3. Staffing requests
4. Schedules
5. Payroll

Do not start with 1,100 tables. The same reusable pipeline will later load them from configuration.

## Step 0: Understand the success criteria

For this learning project, success means:

- The five tables load successfully into Snowflake.
- Running the same load twice does not create duplicate records.
- Inserts and updates reach the curated layer within three minutes at p95.
- Every run records start time, end time, row counts, status, and errors.
- A failed run can restart without manually repairing data.
- Source and target row counts reconcile.

The published AMN figures are reference targets, not results already achieved here.

## Step 1: Prepare your accounts and tools

Install or obtain access to:

- Python 3.10 or newer
- VS Code or another editor
- Git
- A Snowflake trial/development account
- An Azure subscription
- Azure Data Factory
- Azure Storage with an ADLS Gen2 container
- Power BI Desktop

Create a local Python environment from the repository root:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install pandas faker snowflake-connector-python python-dotenv
```

Checkpoint:

```powershell
python --version
python -c "import pandas, faker, snowflake.connector; print('Dependencies OK')"
```

Expected result: Python prints its version and then `Dependencies OK`.

## Step 2: Understand the repository data

The current folders contain:

```text
datasets/cms                 hospital reference data
datasets/synthea             healthcare source data
datasets/processed/synthea   cleaned healthcare data and ID mappings
datasets/hr                  synthetic AMN-style workforce data
scripts                      preparation and generation scripts
```

The important HR files are:

- `candidates.csv`
- `staffing_requests.csv`
- `schedules.csv`
- `payroll.csv`
- `employees.csv`
- `recruiters.csv`

Open each file and identify:

- Its primary key
- Foreign keys
- Date/timestamp columns
- Sensitive columns
- Columns that can change

Write these findings down because they become pipeline configuration later.

## Step 3: Generate and prepare sample data

The CMS cleaning script currently uses paths relative to the `scripts` directory. Run it there:

```powershell
Push-Location scripts
python clean_hospitals_data.py
Pop-Location
```

Then prepare Synthea data and generate the HR data from the repository root:

```powershell
python scripts/prepare_synthea_for_amn.py
python scripts/generate_amn_hr_data.py
```

Checkpoint:

```powershell
Get-ChildItem datasets\cms\hospitals_reference.csv
Get-ChildItem datasets\processed\synthea\*.csv
Get-ChildItem datasets\hr\*.csv
```

Expected result: all three commands list generated CSV files with non-zero sizes.

## Step 4: Profile the source files

Before loading any data, check row counts, columns, duplicates, and missing values. Start with this temporary exploration in a Python shell or notebook:

```python
from pathlib import Path
import pandas as pd

files = [
    Path("datasets/cms/hospitals_reference.csv"),
    Path("datasets/hr/candidates.csv"),
    Path("datasets/hr/staffing_requests.csv"),
    Path("datasets/hr/schedules.csv"),
    Path("datasets/hr/payroll.csv"),
]

for path in files:
    df = pd.read_csv(path)
    print(path.name)
    print("rows:", len(df))
    print("columns:", df.columns.tolist())
    print("null cells:", int(df.isna().sum().sum()))
    print()
```

Create a small data contract for each table containing:

| Field | Meaning |
|---|---|
| source file | Input location |
| primary key | Column(s) uniquely identifying a row |
| watermark | Updated timestamp used for incremental loads |
| required columns | Columns that must exist |
| sensitive columns | Fields requiring masking/restricted access |
| SLA tier | Tier 1, 2, or 3 |

Checkpoint: every first-slice table has a known primary key. If a table has no update timestamp, plan to add one to the simulation rather than pretending incremental loading is possible.

## Step 5: Create the Snowflake structure

Open a Snowflake worksheet as an administrator and create a development database and schemas:

```sql
CREATE DATABASE IF NOT EXISTS AMN_DEV;

CREATE SCHEMA IF NOT EXISTS AMN_DEV.RAW;
CREATE SCHEMA IF NOT EXISTS AMN_DEV.CURATED;
CREATE SCHEMA IF NOT EXISTS AMN_DEV.MARTS;
CREATE SCHEMA IF NOT EXISTS AMN_DEV.CONTROL;
CREATE SCHEMA IF NOT EXISTS AMN_DEV.QUARANTINE;
```

Create separate warehouses so ingestion, transformation, and reporting do not block each other:

```sql
CREATE WAREHOUSE IF NOT EXISTS AMN_INGEST_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

CREATE WAREHOUSE IF NOT EXISTS AMN_TRANSFORM_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

CREATE WAREHOUSE IF NOT EXISTS AMN_BI_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;
```

For a real environment, create least-privilege roles for ingestion, transformation, BI, and administration. Do not give application identities `ACCOUNTADMIN`.

Checkpoint:

```sql
SHOW SCHEMAS IN DATABASE AMN_DEV;
SHOW WAREHOUSES LIKE 'AMN_%';
```

## Step 6: Create control and audit tables

Create a configuration table. One reusable loader will read this instead of requiring one pipeline per source table.

```sql
CREATE TABLE IF NOT EXISTS AMN_DEV.CONTROL.INGESTION_CONFIG (
  SOURCE_SYSTEM        STRING NOT NULL,
  SOURCE_OBJECT        STRING NOT NULL,
  SOURCE_PATH          STRING,
  TARGET_TABLE         STRING NOT NULL,
  LOAD_TYPE            STRING NOT NULL,
  PRIMARY_KEY_COLUMNS  STRING NOT NULL,
  WATERMARK_COLUMN     STRING,
  SLA_SECONDS          NUMBER,
  ENABLED              BOOLEAN DEFAULT TRUE,
  CREATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Create a run log:

```sql
CREATE TABLE IF NOT EXISTS AMN_DEV.CONTROL.PIPELINE_RUN_LOG (
  RUN_ID               STRING NOT NULL,
  BATCH_ID             STRING NOT NULL,
  SOURCE_OBJECT        STRING NOT NULL,
  TARGET_TABLE         STRING NOT NULL,
  SOURCE_HIGH_WATERMARK TIMESTAMP_NTZ,
  EXTRACT_STARTED_AT   TIMESTAMP_NTZ,
  EXTRACT_FINISHED_AT  TIMESTAMP_NTZ,
  RAW_LOADED_AT        TIMESTAMP_NTZ,
  CURATED_AT           TIMESTAMP_NTZ,
  ROWS_READ            NUMBER DEFAULT 0,
  ROWS_INSERTED        NUMBER DEFAULT 0,
  ROWS_UPDATED         NUMBER DEFAULT 0,
  ROWS_REJECTED        NUMBER DEFAULT 0,
  STATUS               STRING,
  ERROR_MESSAGE        STRING
);
```

Create a checkpoint table:

```sql
CREATE TABLE IF NOT EXISTS AMN_DEV.CONTROL.LOAD_CHECKPOINT (
  SOURCE_OBJECT        STRING NOT NULL,
  TARGET_TABLE         STRING NOT NULL,
  LAST_WATERMARK       TIMESTAMP_NTZ,
  LAST_BATCH_ID        STRING,
  UPDATED_AT           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (SOURCE_OBJECT, TARGET_TABLE)
);
```

Checkpoint: all three tables appear in `AMN_DEV.CONTROL`.

## Step 7: Add the first five configurations

Insert one row per source. Replace the example primary keys and watermarks after checking the actual CSV headers.

```sql
INSERT INTO AMN_DEV.CONTROL.INGESTION_CONFIG
  (SOURCE_SYSTEM, SOURCE_OBJECT, SOURCE_PATH, TARGET_TABLE,
   LOAD_TYPE, PRIMARY_KEY_COLUMNS, WATERMARK_COLUMN, SLA_SECONDS)
VALUES
  ('CMS', 'HOSPITALS', 'datasets/cms/hospitals_reference.csv',
   'HOSPITALS', 'SNAPSHOT', 'HOSPITAL_ID', NULL, 86400),
  ('AMN_HR', 'CANDIDATES', 'datasets/hr/candidates.csv',
   'CANDIDATES', 'WATERMARK', 'CANDIDATE_ID', 'UPDATED_AT', 900),
  ('AMN_HR', 'STAFFING_REQUESTS', 'datasets/hr/staffing_requests.csv',
   'STAFFING_REQUESTS', 'WATERMARK', 'REQUEST_ID', 'UPDATED_AT', 180),
  ('AMN_HR', 'SCHEDULES', 'datasets/hr/schedules.csv',
   'SCHEDULES', 'WATERMARK', 'SCHEDULE_ID', 'UPDATED_AT', 180),
  ('AMN_HR', 'PAYROLL', 'datasets/hr/payroll.csv',
   'PAYROLL', 'WATERMARK', 'PAYROLL_ID', 'UPDATED_AT', 900);
```

Important: these key names are a template. Query or inspect the real headers and correct the configuration before executing it.

## Step 8: Create Azure storage landing zones

In Azure:

1. Create a storage account with hierarchical namespace enabled.
2. Create a container named `amn-landing`.
3. Create folders:
   - `cms/hospitals/`
   - `hr/candidates/`
   - `hr/staffing_requests/`
   - `hr/schedules/`
   - `hr/payroll/`
   - `quarantine/`
4. Upload one copy of each source CSV.
5. Store credentials in Azure Key Vault.
6. Grant ADF's managed identity the minimum required storage access.

Use batch-specific paths when pipelines begin running:

```text
amn-landing/hr/staffing_requests/load_date=2026-08-03/batch_id=<uuid>/data.csv
```

Checkpoint: ADF can list and read the five files using its managed identity.

## Step 9: Connect ADF to Snowflake

In ADF Studio:

1. Create an ADLS Gen2 linked service using managed identity.
2. Create a Snowflake linked service.
3. Keep Snowflake credentials in Key Vault.
4. Test both connections.
5. Create parameterized datasets for delimited files and Snowflake tables.

Dataset parameters should include:

- `source_path`
- `file_name`
- `target_schema`
- `target_table`
- `batch_id`

Checkpoint: both linked-service tests succeed, and a preview of one CSV works.

## Step 10: Build the initial full-load pipeline

Create an ADF pipeline named `PL_METADATA_INGEST`:

1. Lookup enabled rows from `INGESTION_CONFIG`.
2. Pass the results to a `ForEach` activity.
3. Set a safe concurrency such as 4 for the proof of concept.
4. Inside the loop, generate `run_id` and `batch_id`.
5. Write a `STARTED` row to `PIPELINE_RUN_LOG`.
6. Copy the source file into the matching Snowflake `RAW` table.
7. Add metadata columns to every raw row:
   - `_BATCH_ID`
   - `_SOURCE_SYSTEM`
   - `_SOURCE_OBJECT`
   - `_SOURCE_FILE`
   - `_SOURCE_COMMIT_AT`
   - `_INGESTED_AT`
   - `_ROW_HASH`
   - `_IS_DELETED`
8. Run the curated merge procedure.
9. Update the checkpoint only after the curated merge succeeds.
10. Mark the log `SUCCEEDED`; on failure mark it `FAILED` with the error.

For the first run, it is acceptable to create raw table columns manually from the CSV profiles. Later, generate DDL from metadata and require approval for type changes.

Checkpoint: one ADF debug run loads all five raw tables and produces five successful audit rows.

## Step 11: Make curated loading idempotent

Raw data is append-only. Curated tables contain the latest trusted version of each business record.

The merge pattern is:

```sql
MERGE INTO AMN_DEV.CURATED.STAFFING_REQUESTS AS T
USING (
  SELECT *
  FROM AMN_DEV.RAW.STAFFING_REQUESTS
  WHERE _BATCH_ID = :BATCH_ID
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY REQUEST_ID
    ORDER BY _SOURCE_COMMIT_AT DESC, _INGESTED_AT DESC
  ) = 1
) AS S
ON T.REQUEST_ID = S.REQUEST_ID
WHEN MATCHED AND S._IS_DELETED THEN DELETE
WHEN MATCHED AND T._ROW_HASH <> S._ROW_HASH THEN UPDATE SET
  /* assign business columns here */
  T._ROW_HASH = S._ROW_HASH,
  T.UPDATED_AT = CURRENT_TIMESTAMP()
WHEN NOT MATCHED AND NOT S._IS_DELETED THEN INSERT (
  /* business columns */, _ROW_HASH, CREATED_AT, UPDATED_AT
) VALUES (
  /* source values */, S._ROW_HASH, CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()
);
```

Implement this pattern for one table first. Then either create one stored procedure per table from a template or build a safe metadata-driven procedure.

Idempotency test:

1. Record the curated row count.
2. Run the same batch again.
3. Compare the new row count.

Expected result: the count and business values remain unchanged.

## Step 12: Simulate incremental changes

Create a copy of a source file and make a small controlled change set:

- Add 10 rows.
- Update 10 existing rows.
- Mark or represent 5 rows as deleted.
- Give every changed record a source commit timestamp.

For a production database, use log-based CDC for Tier-1 tables. For this CSV proof of concept, a change file is enough to validate the downstream design.

Name each change file with a timestamp or batch ID and never overwrite a previously processed file.

Checkpoint: the curated table shows exactly 10 inserts, 10 updates, and 5 deletes after processing the change batch.

## Step 13: Measure the 1–3 minute SLA

The freshness measurement is:

```text
freshness_seconds = curated_at - source_commit_at
```

Query recent performance:

```sql
SELECT
  SOURCE_OBJECT,
  COUNT(*) AS RUNS,
  APPROX_PERCENTILE(
    DATEDIFF('second', SOURCE_HIGH_WATERMARK, CURATED_AT), 0.50
  ) AS P50_SECONDS,
  APPROX_PERCENTILE(
    DATEDIFF('second', SOURCE_HIGH_WATERMARK, CURATED_AT), 0.95
  ) AS P95_SECONDS,
  APPROX_PERCENTILE(
    DATEDIFF('second', SOURCE_HIGH_WATERMARK, CURATED_AT), 0.99
  ) AS P99_SECONDS
FROM AMN_DEV.CONTROL.PIPELINE_RUN_LOG
WHERE STATUS = 'SUCCEEDED'
  AND SOURCE_HIGH_WATERMARK IS NOT NULL
GROUP BY SOURCE_OBJECT;
```

Run Tier-1 micro-batches every 30–60 seconds. Alert at 120 seconds so the team can react before a 180-second breach.

Do not use only average duration. The acceptance target is p95 freshness at or below 180 seconds for Tier-1 tables.

## Step 14: Add data-quality checks

After each curated merge, check:

- Primary keys are not null.
- Primary keys are unique.
- Required foreign keys exist.
- Required values are not null.
- Dates and numeric values are valid.
- Row counts and change counts reconcile.
- Rejected rows are copied to `QUARANTINE` with a reason.

Example duplicate check:

```sql
SELECT REQUEST_ID, COUNT(*)
FROM AMN_DEV.CURATED.STAFFING_REQUESTS
GROUP BY REQUEST_ID
HAVING COUNT(*) > 1;
```

Expected result: zero rows.

Do not advance the checkpoint when a critical quality check fails.

## Step 15: Test failure and restart

Perform these controlled tests:

1. Supply a malformed CSV row.
2. Remove a required column.
3. Stop a pipeline after raw loading but before curated merging.
4. Submit the same batch twice.
5. Submit an older update after a newer update.
6. Temporarily suspend the Snowflake warehouse.

For each test, confirm:

- The run log contains a useful error.
- Bad data is quarantined where appropriate.
- The checkpoint is not advanced on failure.
- Restarting processes the batch safely.
- No duplicate curated rows appear.

## Step 16: Build the first dimensional model

Create these first dimensions:

- `DIM_HOSPITAL`
- `DIM_CANDIDATE`
- `DIM_EMPLOYEE`
- `DIM_RECRUITER`
- `DIM_DATE`

Create these first facts:

- `FACT_STAFFING_REQUEST`
- `FACT_PLACEMENT_SCHEDULE`
- `FACT_PAYROLL`

Keep source identifiers for traceability while using warehouse surrogate keys for joins. Create stable views in `AMN_DEV.MARTS` for Power BI.

Checkpoint: one SQL query joins a staffing request to its hospital, candidate/employee placement, schedule, and payroll information without duplicate fact rows.

## Step 17: Create the first Power BI dashboard

Connect Power BI to the `AMN_BI_WH` warehouse and MARTS views. Start with:

- Open staffing requests
- Fill rate
- Average time to fill
- Active placements
- Scheduled hours
- Payroll cost
- Candidates by role and location
- Pipeline freshness and last successful load

Use Import mode first unless the business requirement truly needs DirectQuery. Keep pipeline monitoring on a separate operational page.

Checkpoint: refreshing the report does not query RAW tables and does not require an administrator role.

## Step 18: Add security and governance

Implement:

- Least-privilege Snowflake roles
- Managed identities/service principals for automation
- Key Vault secrets and credential rotation
- Network policies/private connectivity where required
- Masking policies for sensitive fields
- Row-access policies for client-specific data
- Object tags, owners, descriptions, and retention rules
- No real PHI in development unless the environment is approved for it

Checkpoint: a BI-only user can query approved MARTS views but cannot query RAW sensitive columns or modify objects.

## Step 19: Load-test millions of changes

Do not create millions of identical full snapshots. Generate realistic change events with:

- Inserts, updates, and deletes
- Large and small tables
- Skewed keys
- Wide records
- Late and out-of-order events
- Schema changes
- Peak bursts

Test at expected peak and 2x peak. Record:

- Rows per second
- p50, p95, and p99 freshness
- Snowflake queue time and spill
- ADF integration runtime utilization
- Error and retry rates
- Credits/cost per million changes

Tune batch size and bounded concurrency before increasing warehouse size.

## Step 20: Scale table count in gates

Use this rollout sequence:

| Gate | Tables | Required evidence |
|---|---:|---|
| Proof | 5 | Correctness, replay, SLA measurement |
| Pilot | 25 | Metadata-driven onboarding works |
| Domain | 100 | Concurrency and cost are controlled |
| Multi-domain | 300 | Monitoring and support model work |
| Production scale | 1,100+ | Automated onboarding and operations proven |

For every new table, configuration must include:

- Owner and business domain
- Source and target names
- Primary key
- CDC/watermark/snapshot method
- Watermark column
- Expected change volume
- SLA tier
- Sensitivity classification
- Data-quality rules
- Backfill strategy

Do not enable a table with an unknown key or undefined incremental strategy.

## Step 21: Production readiness checklist

- [ ] Five-table vertical slice works end to end.
- [ ] Re-running a batch is idempotent.
- [ ] Inserts, updates, and deletes are correct.
- [ ] Checkpoints advance only after success.
- [ ] Source-to-target reconciliation passes.
- [ ] Tier-1 p95 freshness is at most 180 seconds.
- [ ] Alerts fire before SLA breach.
- [ ] Failures restart without manual data repair.
- [ ] Sensitive data is masked and access-tested.
- [ ] Warehouses auto-suspend and have resource monitors.
- [ ] Power BI uses MARTS rather than RAW.
- [ ] Peak and 2x-peak tests pass.
- [ ] Cost per GB or million changes is documented.
- [ ] Runbooks exist for replay, backfill, schema drift, and outages.
- [ ] Each table has an owner and SLA tier.

## Suggested four-week learning plan

### Week 1: Local data and Snowflake

- Prepare and profile the sample data.
- Create Snowflake schemas and warehouses.
- Create control and audit tables.
- Manually load one table into RAW.
- Build one idempotent curated merge.

### Week 2: ADF automation

- Configure storage, Key Vault, and linked services.
- Build the metadata-driven ADF pipeline.
- Load all five vertical-slice tables.
- Add checkpoints, audit logs, and quarantine handling.

### Week 3: Incremental loading and SLA

- Generate change files.
- Process inserts, updates, and deletes.
- Schedule Tier-1 micro-batches.
- Measure p50/p95/p99 freshness.
- Test failure and replay.

### Week 4: Analytics and scale test

- Build curated facts and dimensions.
- Publish the first Power BI dashboard.
- Apply masking and least privilege.
- Generate a million-change workload.
- Document results and decide whether the 25-table gate is ready.

## What to implement next in this repository

The documentation describes the target path. The next code changes should be made in this order:

1. Add a `requirements.txt` or `pyproject.toml`.
2. Add a reusable data-profiling script.
3. Add source data contracts/configuration files.
4. Add Snowflake bootstrap SQL for schemas, roles, warehouses, and control tables.
5. Add raw-table and curated-table DDL.
6. Add idempotent merge procedures.
7. Add a change-event generator for load testing.
8. Add data-quality and reconciliation tests.
9. Add ADF deployment templates or infrastructure as code.
10. Add an operational SLA dashboard.

Implement and verify one item at a time. A small pipeline that is correct, observable, and restartable is the foundation for the 1,100-table version.
