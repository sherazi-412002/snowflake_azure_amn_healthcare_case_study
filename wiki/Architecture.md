# Solution Architecture & Data Flow

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
