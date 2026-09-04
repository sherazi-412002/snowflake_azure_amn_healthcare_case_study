# Azure Data Factory definitions

This directory contains the sanitized ADF definitions used by Terraform for the AMN first data-platform slice.

## Inventory

| Type | Name |
|---|---|
| Linked service | `LS_KEY_VAULT` |
| Linked service | `LS_ADLS_GEN2` |
| Linked service | `LS_SNOWFLAKE_V2` |
| Linked service | `LS_BLOB_STAGE_SAS` |
| Dataset | `DS_ADLS_CSV` |
| Dataset | `DS_SNOWFLAKE_TABLE` |
| Dataset | `DS_SNOWFLAKE_CONFIG` |
| Pipeline | `PL_COPY_HOSPITALS` |
| Pipeline | `PL_COPY_STAFFING_REQUESTS` |
| Pipeline | `PL_COPY_CANDIDATES` |
| Pipeline | `PL_COPY_SCHEDULES` |
| Pipeline | `PL_COPY_PAYROLL` |
| Pipeline | `PL_METADATA_INGEST` |
| Pipeline | `PL_FILE_EVENT_ROUTER` |
| Blob event trigger | `TR_METADATA_INGEST_BATCH_READY` |
| Blob event trigger | `TR_LANDING_CSV_CREATED` |

The five child ingestion pipelines contain batch creation, start/success/failure auditing, staged ADLS-to-Snowflake RAW copying, and RAW-to-CURATED merge calls. `PL_METADATA_INGEST` reads enabled rows from `AMN_DEV.CONTROL.INGESTION_CONFIG`, processes up to four entries concurrently, and routes each configured first-slice object to its tested child pipeline.

`PL_FILE_EVENT_ROUTER` receives `folderPath` and `fileName` from `TR_LANDING_CSV_CREATED`. It validates the complete canonical path and executes only the corresponding child pipeline. The trigger watches non-empty `.csv` blobs beneath the `landing` container and is disabled by default. It is intended for full-load/backfill files; Azure SQL incremental pipelines remain the operational change-ingestion path.

Run `sql/snowflake/008_metadata_ingestion_config.sql` before executing the metadata parent pipeline. It seeds the five configuration rows and grants the ADF ingestion role permission to read them.

There are no custom integration runtimes or data flows. The JSON files intentionally exclude live encrypted credentials and secret values. Terraform renders `${...}` placeholders and deploys the definitions through `azapi_resource`.

Do not deploy Terraform over manually created Azure objects until they have been imported into the intended Terraform state. See `infra/terraform/ADF_IMPORT.md`.
