"""
Populate complete modular GitHub Wiki pages for the repository.
"""

import os

WIKI_DIR = os.path.join(os.path.dirname(__file__), "..", "wiki")
os.makedirs(WIKI_DIR, exist_ok=True)

ARCHITECTURE_MD = r"""# Solution Architecture & Data Flow

> **⚠️ Educational Project Notice:**  
> This architectural design is part of a learning case study inspired by public customer stories. All datasets and operational sources are synthetic and simulated.

```
+----------------------------------------------------------------------------------------------------+
|                                    END-TO-END DATA PIPELINE FLOW                                   |
+----------------------------------------------------------------------------------------------------+
|                                                                                                    |
|  [ DATA SOURCES ]                                                                                  |
|  * CMS Hospital Reference CSV (5,432 facilities)                                                   |
|  * Synthetic AMN HR CSVs (Candidates, Staffing Requests, Schedules, Payroll)                       |
|  * Azure SQL Database (Simulated Real-Time OLTP Source with Watermarks & Soft Deletes)             |
|                                     |                                                              |
|                                     v (Upload / Event Grid / 2-Min Trigger)                        |
|  [ AZURE STORAGE LAYER ]                                                                           |
|  * ADLS Gen2 Data Lake (landing / checkpoint / quarantine / archive)                               |
|  * Temporary Blob SAS Staging Container (Required for Snowflake V2 Connector)                      |
|                                     |                                                              |
|                                     v (Orchestration & Copy Activity)                              |
|  [ AZURE DATA FACTORY (ADF v2) ]                                                                   |
|  * Event Router Pipeline: PL_FILE_EVENT_ROUTER (BlobCreated Trigger -> Dynamic Switching)          |
|  * Metadata Ingest Pipeline: PL_METADATA_INGEST (Control Table Lookup -> Concurrent Copy)          |
|  * Incremental CDC Pipelines: Watermark Extraction -> Delta Copy -> Procedure Execution           |
|  * Security: System-Assigned Managed Identity + Azure Key Vault (Zero Hardcoded Secrets)          |
|                                     |                                                              |
|                                     v (Secure Staged COPY INTO / Stored Procedures)                |
|  [ SNOWFLAKE CLOUD DATA WAREHOUSE (AMN_DEV) ]                                                      |
|  +----------------------------------------------------------------------------------------------+  |
|  |  RAW Schema: Append-only source-aligned tables + Delta staging tables + Ingestion Metadata  |  |
|  |       |                                                                                      |  |
|  |       v (MERGE_* Stored Procedures with Windowed Deduplication & Type Casting)                |  |
|  |  CURATED Schema: Validated, typed, deduplicated business entities (HOSPITALS, CANDIDATES...) |  |
|  |       |                                                                                      |  |
|  |       v (Kimball Dimensional Modeling & Fact Aggregation)                                    |  |
|  |  MARTS Schema: DIM_HOSPITAL, DIM_CANDIDATE, DIM_DATE, FACT_*, VW_EXECUTIVE_KPIS...          |  |
|  |       ^                                                                                      |  |
|  |  CONTROL Schema: INGESTION_CONFIG, PIPELINE_RUN_LOG, LOAD_CHECKPOINT, INGESTION_WATERMARK    |  |
|  +----------------------------------------------------------------------------------------------+  |
|  * Compute Isolation: AMN_INGEST_WH (XS) | AMN_TRANSFORM_WH (XS) | AMN_BI_WH (XS) (Auto-Suspend 60s)|
|                                     |                                                              |
|                                     v (DirectQuery / Snowflake Connector / AMN_BI_ROLE)            |
|  [ POWER BI REPORTING SUITE ]                                                                      |
|  * Page 1: Executive Overview (High-level Demand, Revenue, Placements, Fill Rate)                 |
|  * Page 2: Recruiting & Candidates (Supply Funnel, Specialty Breakdown, Recruiter Performance)     |
|  * Page 3: Staffing Operations (Departmental Needs, Shift Coverage, Priority Requisitions)         |
|  * Page 4: Payroll & Pipeline Health (Regular/OT Hours, Gross/Net Pay, Pipeline SLA & Freshness)  |
|                                                                                                    |
|  [ OBSERVABILITY, DEVOPS & GOVERNANCE ]                                                            |
|  * Observability: Azure Monitor Diagnostic Settings -> Log Analytics Workspace -> KQL & Alerts    |
|  * Infrastructure as Code: HashiCorp Terraform (AzAPI + AzureRM Providers + Remote State Backend)  |
+----------------------------------------------------------------------------------------------------+
```
"""

SERVICES_MD = r"""# Services & Alternatives Breakdown

This wiki page documents all 9 technologies used in the AMN Healthcare data platform modernization case study, how each works, alternatives evaluated, and the rationale for selection.

| Service | Category | How It Works in This Project | Industry Alternatives | Selection Rationale |
|:---|:---|:---|:---|:---|
| **ADLS Gen2** | Enterprise Storage | Stores raw batch CSVs across 4 zones (`landing`, `checkpoint`, `quarantine`, `archive`) with Hierarchical Namespace (HNS). | AWS S3, Google Cloud Storage, Flat Blob | Native Azure Event Grid integration; atomic directory renames; Managed Identity zero-trust access. |
| **Azure Data Factory (v2)** | Orchestration | Serverless dynamic routing (`PL_FILE_EVENT_ROUTER`), metadata-driven batch loops (`PL_METADATA_INGEST`), and incremental copy. | Apache Airflow, Synapse, Databricks Workflows, Fivetran | True serverless pricing; optimized Snowflake V2 connector; native Event Grid event triggers. |
| **Azure Key Vault** | Secrets Management | Stores Snowflake passwords, SAS URIs, and SQL connection strings with zero credentials in code. | HashiCorp Vault, AWS Secrets Manager, Local `.env` | Native Azure Managed Identity integration; FIPS 140-2 Level 2 HSMs; soft-delete and purge protection. |
| **Azure SQL Database** | Transactional Source | Simulates hospital EHR/VMS OLTP system with `LAST_MODIFIED_AT` timestamps and `IS_DELETED` soft-delete flags. | Cosmos DB, PostgreSQL, Debezium + Kafka | Enterprise representation of clinical software backends; fast index-backed watermark queries. |
| **Snowflake Data Warehouse** | Analytical Engine | 4-tier schema (`RAW`, `CURATED`, `MARTS`, `CONTROL`) + 3 isolated warehouses (`AMN_INGEST_WH`, `AMN_TRANSFORM_WH`, `AMN_BI_WH`). | Databricks Lakehouse, BigQuery, Redshift, Synapse SQL | Complete compute/storage decoupling; zero workload contention; 60s auto-suspend saving 93% cost. |
| **Power BI (PBIP/TMDL)** | Business Intelligence | DirectQuery semantic model connecting to `MARTS` via `AMN_BI_WH`; 4-page responsive executive reporting suite. | Tableau, Looker, ThoughtSpot, Superset | Ubiquitous healthcare adoption; optimized DirectQuery pushdown; version-controllable PBIP format. |
| **HashiCorp Terraform** | IaC & DevOps | Automated multi-provider provisioning (`azurerm`, `azapi`, `random`) with remote state locking in Azure Blob. | Azure Bicep, ARM Templates, Pulumi | Multi-cloud support (Azure + Snowflake); reliable declarative state locking and drift detection. |
| **Azure Monitor & Log Analytics** | Observability | Ingests diagnostic logs from ADF, Key Vault, and Storage; powers KQL queries and scheduled alert rules. | Datadog, Dynatrace, Splunk, Prometheus | Agentless 1st-party integration; sub-second query performance; cost-effective pay-per-GB model. |
| **Docker** | Local Environment | Containerizes Python 3.12 with `pandas`, `faker`, `pyarrow`, and `snowflake-connector-python` for local testing. | Local Python venv, Dedicated VMs | 100% environment parity across developer machines (Windows, macOS, Linux); zero installation drift. |
"""

DATA_PIPELINES_MD = r"""# Data Pipelines & Engineering Mechanics

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
"""

POWER_BI_MD = r"""# Power BI DirectQuery Dashboard

## Semantic Model Topology
The reporting semantic model connects directly to Snowflake's `AMN_DEV.MARTS` schema using the **DirectQuery** engine via `AMN_BI_WH`.

```
                      +-------------------+
                      |   DIM_HOSPITAL    |
                      +-------------------+
                         | 1         | 1
                         |           +-----------------------+
                         | *                                 | *
             +-----------------------+           +-----------------------+
             | FACT_STAFFING_REQUEST |           | FACT_PLACEMENT_SCHED  |
             +-----------------------+           +-----------------------+
                         | *                                 | *
                         |                                   |
                         | 1                                 | 1
                      +-------------------+                  |
                      |     DIM_DATE      |------------------+
                      +-------------------+                  |
                         | 1                                 |
                         |                                   |
                         | *                                 | *
             +-----------------------+           +-----------------------+
             |     DIM_CANDIDATE     |           |     FACT_PAYROLL      |
             +-----------------------+           +-----------------------+
```

## 4-Page Executive Reporting Suite
1. **Executive Overview:** High-level demand, placements, fill rates, invoiced revenue, and clinical time-to-fill.
2. **Recruiting & Candidate Supply:** Candidate qualification funnel conversion, specialty breakdowns, and recruiter productivity.
3. **Staffing Operations:** Departmental open shifts, hospital demand distribution, and urgent requisitions.
4. **Payroll & Pipeline Health:** Regular vs. Overtime hours, gross vs. net payroll, and real-time pipeline SLA compliance (99.9%).
"""

TROUBLESHOOTING_MD = r"""# Troubleshooting & Engineering Learnings

| Challenge | Root Cause | Resolution |
|:---|:---|:---|
| **ADLS 403 Forbidden in Portal** | User had Subscription Contributor but lacked Storage Data-Plane permissions. | Added `Storage Blob Data Contributor` RBAC role assignment via Terraform. |
| **Snowflake SQL Error: Invalid Identifier `ROWS_WRITTEN`** | Query referenced non-existent audit column. | Updated queries to use `ROWS_INSERTED`, `ROWS_UPDATED`, and `ROWS_REJECTED`. |
| **Azure SQL Connectivity Timeout** | Server firewall blocked Azure IP traffic and user was uninitialized. | Enabled `Allow Azure services to access this server` and configured credentials in Key Vault. |
| **Incremental Procedure Column Mismatch** | Delta table loaded `SPECIALTY` instead of `REQUIRED_ROLE` and `DEPARTMENT`. | Standardized delta schema and updated stored procedure mappings. |
| **Power BI Template Blank Visuals** | `.pbit` template only held theme metadata without visual containers. | Re-built report using native Power BI Project (`.pbip`) format with Tabular Model Definition Language (TMDL). |
"""

def write_wiki_pages():
    pages = {
        "Architecture.md": ARCHITECTURE_MD,
        "Services-and-Alternatives.md": SERVICES_MD,
        "Data-Pipelines.md": DATA_PIPELINES_MD,
        "Power-BI-Dashboard.md": POWER_BI_MD,
        "Troubleshooting-and-Learnings.md": TROUBLESHOOTING_MD,
    }
    for filename, content in pages.items():
        filepath = os.path.join(WIKI_DIR, filename)
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(content.strip() + "\n")
        print(f"Wrote {filepath}")

if __name__ == "__main__":
    write_wiki_pages()
