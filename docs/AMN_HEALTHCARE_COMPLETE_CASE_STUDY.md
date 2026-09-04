<div align="center">

# AMN Healthcare Data Platform

## Azure Data Factory Case Study

**End-to-end healthcare staffing data engineering implementation**

Azure Data Lake Storage Gen2 · Azure Data Factory · Azure Key Vault  
Azure SQL Database · Snowflake · Power BI · Terraform · Azure Monitor

**Environment:** Development proof of concept  
**Prepared:** August 2026

</div>

> This repository is a learning implementation inspired by AMN Healthcare's published Snowflake customer story. Published AMN outcomes are reference benchmarks; they are not claimed as measurements achieved by this proof of concept.

```{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```

# 2. About AMN Healthcare

AMN Healthcare is a healthcare workforce and talent-solutions organization headquartered in Coppell, Texas. It helps healthcare organizations obtain the people, skills and workforce visibility required to deliver patient care. Its business spans healthcare staffing, recruiting, scheduling, workforce management and related talent services.

The official Snowflake customer story describes AMN as serving more than **10,000 clients** and having as many as **25,000 professionals on assignment** at one time. This operating model creates a continuous need to combine information about hospitals, candidates, staffing requests, assignments, schedules and payroll.

## Why data matters to AMN

- Hospitals need visibility into open positions, required specialties, filled positions and staffing gaps.
- Recruiting teams need candidate availability, credentials, location, status and funnel conversion.
- Operations teams need schedules, planned hours, worked hours and placement coverage.
- Finance teams need payroll, overtime and cost information.
- Executives need trusted, current metrics across multiple operational systems.

## Published Snowflake reference outcomes

| Measure | Published AMN result |
|---|---:|
| Daily data written | More than 100 GB |
| Replicated tables | 1,176 |
| Pipeline success rate | 99.9% |
| Processing-pipeline SLA | 1–3 minutes |
| Runtime improvement | Up to 75% |
| Data-environment cost reduction | From about $200,000/month to $14,000/month |
| Estimated annual savings | $2.2 million |

Source: [Snowflake—AMN Healthcare customer story](https://www.snowflake.com/en/resources/case-study/amn-healthcare-switches-to-snowflake-and-reduces-data-lake-costs-by-93/).

```{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```

# 3. Business Problem and Proposed Solution

## Before Snowflake

AMN needed timely, dependable analytics without querying production systems directly. Direct reporting against operational databases caused contention and reporting delays. Its earlier data-lake environment was difficult to administer and scale, while a third-party onboarding tool increased cost and complexity. Even after consolidating on Databricks, the team still faced performance and cost optimization challenges. The published story reports expensive job troubleshooting, software patching and limited cost allocation transparency.

The central business problems were therefore:

1. Fragmented hospital, recruiting, scheduling and payroll data.
2. Slow or disruptive reporting against transactional systems.
3. Fragile pipelines requiring significant operational support.
4. Difficulty scaling ingestion across many tables while meeting short SLAs.
5. High platform cost and weak workload-level cost visibility.

## Solution presented in this repository

| Concern | Implemented approach |
|---|---|
| Secure cloud foundation | Terraform-managed resource group, ADLS Gen2, ADF, Key Vault, Azure SQL, Log Analytics and RBAC |
| File ingestion | Event-driven BlobCreated trigger, validated file router and five ADF ingestion pipelines |
| Operational changes | Azure SQL simulated source plus watermark-based incremental ADF pipelines |
| Central platform | Snowflake `RAW`, `CURATED`, `MARTS` and `CONTROL` schemas |
| Reliable processing | Batch IDs, audit records, idempotent merge procedures, watermarks and failure branches |
| Workload isolation | Separate Snowflake ingestion, transformation and BI warehouses |
| Analytics | Power BI DirectQuery semantic model and four report pages |
| Operations | ADF diagnostics, Log Analytics queries, SLA monitoring and alert definitions |

The solution provides two complementary ingestion contracts: canonical CSV files for initial loads/backfills and incremental Azure SQL extraction for frequently changing operational records. ADF orchestrates movement and stored-procedure calls; Snowflake performs governed storage, transformation and serving; Power BI consumes only the `MARTS` layer.

```{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```

# 4. AMN Data Structures and Schemas

## Core business datasets

| Dataset | Business key | Representative attributes | Purpose |
|---|---|---|---|
| Hospitals | `HOSPITAL_ID` | name, city, state, type, ownership, emergency services, rating | Client/facility reference |
| Candidates | `CANDIDATE_ID` | profession, specialty, location, availability, credentials, recruiter, status | Recruiting supply and funnel |
| Staffing requests | `REQUEST_ID` | hospital, required role, department, required/filled staff, priority, dates, rate | Workforce demand and fill analysis |
| Schedules | schedule/placement ID | request, candidate, hospital, shift, work date, planned/worked/overtime hours | Assignment coverage and utilization |
| Payroll | payroll ID | employee/candidate, hospital, period, regular/overtime hours, gross/net pay | Labor cost and payroll analysis |

## Snowflake logical organization

| Schema | Objects and responsibility |
|---|---|
| `AMN_DEV.RAW` | Landing-aligned tables, delta tables and ingestion metadata such as batch ID, source file and ingestion timestamp |
| `AMN_DEV.CURATED` | Typed, validated and deduplicated hospital, candidate, staffing, schedule and payroll tables |
| `AMN_DEV.MARTS` | `DIM_DATE`, `DIM_HOSPITAL`, `DIM_CANDIDATE`, staffing/schedule/payroll facts, executive KPI and pipeline views |
| `AMN_DEV.CONTROL` | Ingestion configuration, watermarks, pipeline-run audit, batch status and stored merge procedures |

## Example staffing-request progression

```text
Azure SQL operational record
REQUEST_ID, HOSPITAL_ID, SPECIALTY, REQUIRED_STAFF, FILLED_STAFF,
REQUEST_STATUS, PRIORITY, REQUEST_DATE, LAST_MODIFIED_AT, IS_DELETED
                         |
                         v
RAW.STAFFING_REQUESTS_DELTA
+ BATCH_ID, INGESTED_AT
                         |
                         v
CURATED.STAFFING_REQUESTS
typed business columns + CREATED_AT, UPDATED_AT
                         |
                         v
MARTS.FACT_STAFFING_REQUEST -> Power BI measures and visuals
```

Dimensions have one-to-many, single-direction relationships to facts. Pipeline-operational views remain separate from business facts. RAW preserves source fidelity; CURATED applies business rules; MARTS exposes stable reporting contracts.

```{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```

# 5. Data Sources, Simulation and Complete Process

## How the proof-of-concept data is obtained

- CMS-style hospital reference CSV supplies hospital and facility attributes.
- Synthetic AMN-style HR files supply candidates, staffing requests, schedules and payroll.
- Repository preparation scripts clean hospital data and generate/shape HR test data.
- Azure SQL Database simulates operational applications by holding changeable staffing, candidate, schedule and payroll records.
- Insert, update and delete test statements simulate real operational transactions. `LAST_MODIFIED_AT` and soft-delete indicators support incremental extraction.

## Initial load and backfill flow

1. A canonical CSV arrives in the private ADLS Gen2 `landing` container.
2. `TR_LANDING_CSV_CREATED` receives the BlobCreated event for a non-empty `.csv` file.
3. `PL_FILE_EVENT_ROUTER` validates the full folder and filename.
4. Only the matching `PL_COPY_*` pipeline runs: hospitals, candidates, staffing requests, schedules or payroll.
5. ADF creates a batch ID, writes a STARTED audit row, stages the file through Blob SAS, and copies rows to Snowflake RAW.
6. A Snowflake stored procedure validates/types data and merges it into CURATED.
7. Success or failure is written to CONTROL audit tables. Unsupported files fail safely.

## Incremental operational flow

1. ADF reads the previous watermark from `CONTROL.INGESTION_WATERMARK`.
2. It obtains the current maximum `LAST_MODIFIED_AT` from the Azure SQL source.
3. It copies only records in the `(old watermark, new watermark]` window into a Snowflake delta table.
4. A merge procedure applies inserts, updates and soft deletes to CURATED idempotently.
5. The watermark advances only after a successful merge, allowing safe retry after failure.
6. MARTS views expose updated KPIs; Power BI DirectQuery requests current results from Snowflake.
7. ADF diagnostic logs flow to Log Analytics for pipeline, trigger, duration and SLA monitoring.

The metadata-driven parent pipeline reads enabled configurations and runs reusable child pipelines with bounded concurrency. The separate `AMN_BATCH_READY.json` marker supports coordinated multi-file batches; it must not overlap with the individual-file contract for the same delivery.

```{=openxml}
<w:p><w:r><w:br w:type="page"/></w:r></w:p>
```

# 6. AMN Solution Architecture

![AMN Healthcare enhanced Azure–Snowflake architecture](AMN%20(1).jpg){ width=6.5in }

## Architecture reading guide

Data moves from hospital, HR and recruiting sources through Azure Data Factory into Snowflake. Snowflake separates ingestion storage, governed transformation and business-serving layers, with independent compute warehouses. Power BI consumes the governed reporting layer. The implemented enhancement also includes ADLS landing/checkpoint/quarantine/archive zones, Key Vault secrets, Azure SQL incremental simulation, event and schedule triggers, metadata control, audit/watermark tables, Azure Monitor and Terraform infrastructure-as-code.

**Operational principle:** source events initiate work, ADF controls orchestration, Snowflake controls data quality and transformation, and Power BI presents trusted staffing and operational outcomes.
