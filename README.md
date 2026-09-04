# AMN Healthcare Data Platform Case Study

This repository is a learning implementation inspired by the [AMN Healthcare Snowflake case study](https://www.snowflake.com/en/customers/all-customers/case-study/amn-healthcare/). The published result describes more than **100 GB written per day**, **1,176 replicated tables**, a **99.9% pipeline success rate**, and **1–3 minute processing-pipeline SLAs**. Those are target-scale reference metrics, not results already achieved by this repository.

The implementation goal is to build a smaller proof of concept first, prove correctness and latency, and then scale the same metadata-driven pattern to 1,100+ tables and millions of changed rows.

## 1. Target outcome

Build a healthcare staffing analytics platform with:

- Snowflake as the governed source of truth.
- Azure Data Factory (ADF) for orchestration and bulk/backfill movement.
- Change Data Capture (CDC) or micro-batches for frequently changing operational data.
- Separate raw, curated, and serving layers.
- Power BI dashboards for staffing, recruiting, payroll, and operational monitoring.
- End-to-end observability, replay, reconciliation, and 99.9% successful pipeline runs.

> Important: “daily replication of 1,176 tables” and a “1–3 minute processing SLA” are different measurements. Do not run all tables as one daily batch and expect minute-level freshness. Use CDC/micro-batches for SLA-critical tables and scheduled incremental loads for the rest.

## 2. Reference architecture

```text
Operational DBs / APIs / files
          |
          | CDC, watermark queries, or ADF Copy
          v
Azure Data Lake landing (optional) ----> quarantine/dead-letter
          |
          | Snowpipe / Snowpipe Streaming / ADF Copy
          v
Snowflake RAW
          |
          | Streams + Tasks or Dynamic Tables
          v
Snowflake CURATED
          |
          | dimensional models / secure views
          v
Snowflake MARTS ----> Power BI / secure data sharing

Control plane: table metadata, audit log, SLA metrics, alerts, RBAC, masking
```

For the local proof of concept, the CSV files in `datasets/` act as source systems. At production scale, replace file polling on critical tables with log-based CDC. ADF can remain the orchestrator, but it should not launch 1,176 hand-built pipelines.

## 3. Start with a measurable SLA

Define freshness per table tier before building pipelines:

| Tier | Example data | Target | Ingestion pattern |
|---|---|---:|---|
| Tier 1 | staffing requests, schedules, placements | 1–3 minutes p95 | CDC or 30–60 second micro-batch |
| Tier 2 | candidates, employees, encounters, claims | 5–15 minutes p95 | CDC or incremental watermark |
| Tier 3 | reference and low-change tables | daily | scheduled batch |

Measure latency as:

```text
freshness_seconds = curated_available_at - source_commit_at
```

The 1–3 minute budget must include source capture, transfer, Snowflake load, transformation, and publication. Store each timestamp separately so the slow stage is visible.

## 4. Prerequisites

- Python 3.10+
- `pandas` and `faker` for the existing data-generation scripts
- An Azure subscription with ADF and, optionally, ADLS Gen2
- A Snowflake account with permission to create databases, schemas, warehouses, stages, streams/tasks, roles, and resource monitors
- Power BI Desktop or service for the reporting phase
- A secrets manager such as Azure Key Vault; never commit credentials

Local setup:

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install pandas faker
```

## 5. Prepare the current sample data

The repository already contains CMS hospital reference data, Synthea healthcare data, synthetic AMN-style HR data, and preparation scripts.

Run scripts from the repository root:

```powershell
python scripts/clean_hospitals_data.py
python scripts/prepare_synthea_for_amn.py
python scripts/generate_amn_hr_data.py
```

Expected subject areas:

- `datasets/cms`: hospital reference data
- `datasets/synthea`: patients, providers, organizations, encounters, and claims
- `datasets/processed/synthea`: cleaned AMN-shaped Synthea data and ID mappings
- `datasets/hr`: candidates, recruiters, employees, staffing requests, schedules, and payroll

Before loading, add automated checks for required columns, unique business keys, valid foreign keys, row counts, null thresholds, and timestamps. Treat failed records as quarantined data rather than silently dropping them.

## 6. Build the Snowflake foundation

Create separate environments and layers, for example:

```text
AMN_DEV.RAW
AMN_DEV.CURATED
AMN_DEV.MARTS
AMN_DEV.CONTROL
```

Then create:

1. Roles for platform admin, ingestion, transformation, BI read-only, and data steward access.
2. Separate warehouses for ingestion, transformation, and BI so workloads do not block one another.
3. Auto-suspend, auto-resume, query timeouts, and resource monitors.
4. File formats and internal/external stages for CSV landing files.
5. Masking and row-access policies for PII/PHI-like fields.
6. Retention, Time Travel, tags, ownership, and audit policies.

Use surrogate keys in curated dimensions, but retain source system and source primary key for traceability. Cluster only after query evidence shows it is necessary.

## 7. Implement one vertical slice first

Do not begin with all 1,100+ tables. Prove the complete path with these related tables:

1. hospitals/organizations
2. candidates
3. staffing requests
4. schedules or placements
5. payroll

For each table, implement:

- Initial snapshot/backfill into `RAW`.
- Incremental extraction with a source commit timestamp, CDC sequence, or monotonic watermark.
- Idempotent load using a deterministic batch ID and `MERGE` into `CURATED`.
- Insert, update, and delete handling (soft delete where required).
- Schema-drift detection and quarantine.
- Reconciliation of source counts/checksums against Snowflake.
- A serving view or fact/dimension model consumed by one Power BI report.

Exit criterion: replaying the same batch creates no duplicates, injected failures recover from the last checkpoint, and Tier-1 freshness is under three minutes at p95.

## 8. Make ingestion metadata-driven

Create a control table similar to:

```sql
CREATE TABLE AMN_DEV.CONTROL.INGESTION_CONFIG (
  source_system       STRING,
  source_schema       STRING,
  source_table        STRING,
  target_table        STRING,
  load_type           STRING,   -- CDC, WATERMARK, SNAPSHOT
  primary_key_columns STRING,
  watermark_column    STRING,
  sla_seconds         NUMBER,
  schedule_expression STRING,
  enabled             BOOLEAN
);
```

ADF should read this table and execute a reusable pipeline template. Parameterize source, target, keys, watermark, partitioning, and retry policy. Generate table configurations from source catalog metadata, then review them before activation. This is the key step that makes 1,176-table onboarding manageable.

Maintain a separate run log containing at least:

- pipeline, table, and batch ID
- extraction start/end and source high watermark
- landing, raw, curated, and published timestamps
- rows read/inserted/updated/deleted/rejected
- status, retry count, error category, and error message

## 9. Meet the 1–3 minute target

For Tier-1 tables:

1. Capture database log changes instead of repeatedly scanning full tables.
2. Land changes continuously or every 30–60 seconds.
3. Keep files/batches large enough to avoid the small-file problem but small enough for the latency budget.
4. Use Snowpipe Streaming or event-triggered Snowpipe when appropriate; use ADF micro-batches where that is the available platform constraint.
5. Transform only changed rows with Streams/Tasks, Dynamic Tables, or incremental SQL.
6. Precompute the small number of business aggregates needed by dashboards.
7. Isolate ingestion, transformation, and BI warehouses; scale out only when concurrency metrics justify it.
8. Alert before breach (for example at 120 seconds for a 180-second SLA).

Do not claim the SLA from average duration alone. Test p50, p95, p99, maximum latency, backlog recovery, and consecutive breaches under peak volume.

## 10. Scale toward millions of rows and 1,100+ tables

Scale in controlled waves:

| Phase | Scope | Purpose |
|---|---:|---|
| 0 | 5 tables | End-to-end vertical slice |
| 1 | 25 tables | Validate metadata and schema drift |
| 2 | 100 tables | Tune concurrency and warehouse sizing |
| 3 | 300 tables | Exercise operational support and cost controls |
| 4 | 1,100+ tables | Production rollout by domain and SLA tier |

At each gate, run volume tests using generated changes rather than repeatedly duplicating full snapshots. Test peak change rate, table-count concurrency, wide rows, skewed tables, deletes, late events, schema changes, source outage, Snowflake suspension, and replay after failure.

Use a bounded worker pool in ADF. Unlimited parallel copies can overload source databases, integration runtimes, cloud storage, or Snowflake even when each individual job is fast. Give large/high-change tables dedicated configurations and group small tables into sensible batches.

## 11. Curated data model

A useful first star schema is:

- Dimensions: `DIM_HOSPITAL`, `DIM_CANDIDATE`, `DIM_EMPLOYEE`, `DIM_RECRUITER`, `DIM_ROLE`, `DIM_DATE`
- Facts: `FACT_STAFFING_REQUEST`, `FACT_PLACEMENT_SCHEDULE`, `FACT_PAYROLL`, `FACT_ENCOUNTER`, `FACT_CLAIM`

Initial dashboard metrics can include open requests, time to fill, fill rate, active placements, available candidates by location/role, scheduled hours, overtime, payroll cost, and placement cost by hospital.

Keep raw history immutable. Apply business rules and deduplication in `CURATED`, and expose stable semantic views from `MARTS`.

## 12. Testing and acceptance criteria

Automate these checks in CI and in every pipeline run:

- Unit tests for normalization, mappings, and incremental SQL.
- Contract tests for required columns and compatible type changes.
- Data tests for uniqueness, nulls, relationships, accepted values, and reconciliation.
- Idempotency and delete-propagation tests.
- Performance tests at expected and 2x peak change volume.
- Failure tests for network loss, partial batches, duplicate events, late events, and restart.
- Security tests for least privilege, masked columns, and unauthorized tenant/client access.

Suggested proof-of-concept acceptance criteria:

```text
Tier-1 freshness:       p95 <= 180 seconds
Pipeline success:       >= 99.9% over the agreed measurement window
Reconciliation:         100% of committed source changes accounted for
Duplicate business keys: 0
Recovery:               no manual data repair after a replayable failure
Cost:                   within an agreed cost per GB / per million changes
```

## 13. Operations and monitoring

Create an operational dashboard showing:

- freshness by table and SLA tier
- success rate and consecutive failures
- backlog/change lag
- row throughput and rejected records
- ADF activity duration and integration-runtime utilization
- Snowflake queue time, spill, credits, and warehouse saturation
- reconciliation differences and schema changes

Route alerts by severity: an approaching Tier-1 breach pages the on-call owner; a disabled daily reference table creates a lower-priority ticket. Write runbooks for replay, backfill, schema drift, credential rotation, warehouse saturation, and source recovery.

## 14. Recommended implementation backlog

- [ ] Record the source inventory, owners, keys, change rate, sensitivity, and SLA tier.
- [ ] Fix each source table's extraction method: CDC, watermark, or snapshot.
- [ ] Create Snowflake databases, roles, warehouses, stages, and policies.
- [ ] Create control/configuration, audit, checkpoint, and quarantine tables.
- [ ] Load the five-table vertical slice and prove idempotent replay.
- [ ] Add incremental curated models and one Power BI dashboard.
- [ ] Instrument end-to-end freshness and configure pre-breach alerts.
- [ ] Build load and failure-test generators for millions of changes.
- [ ] Expand through 25-, 100-, 300-, and 1,100-table gates.
- [ ] Document cost baselines, recovery procedures, ownership, and production sign-off.

## 15. First sprint (practical starting point)

1. Run the existing scripts and profile every generated CSV.
2. Create the four Snowflake schemas and three workload warehouses.
3. Load hospitals, candidates, staffing requests, schedules, and payroll into `RAW`.
4. Add batch IDs, source timestamps, ingestion timestamps, and row hashes.
5. Build idempotent `MERGE` models in `CURATED`.
6. Add `INGESTION_CONFIG`, checkpoint, and run-log tables.
7. Build one parameterized ADF pipeline and drive all five tables from metadata.
8. Simulate inserts, updates, and deletes every minute.
9. Measure source-to-curated p95 freshness and tune until it is below 180 seconds.
10. Publish a small staffing dashboard and perform a failure/replay demonstration.

Completing this sprint provides evidence that the architecture works. Only then increase data volume and table count; otherwise scale will multiply correctness and operational problems.
