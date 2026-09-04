# PROJECT CONTEXT

This file is the persistent engineering handoff for the AMN Healthcare data-platform case study. Read it before changing the project.

Evidence labels used throughout:

- **[VERIFIED IN REPOSITORY]** Confirmed directly from a versioned file in this workspace.
- **[FROM CONVERSATION HISTORY]** Reported, configured, or tested interactively, but not fully represented by repository code.
- **[PLANNED]** Intended future work.
- **[ASSUMPTION]** A reasoned interpretation that requires confirmation.
- **[UNKNOWN]** The available repository and conversation do not establish the fact.

## 1. Project Overview

**[VERIFIED IN REPOSITORY]** Project: **AMN Healthcare Data Platform Case Study**. It is a learning implementation inspired by Snowflake's public AMN Healthcare customer story; it is not AMN's production system and must not represent synthetic results as AMN production facts.

The business problem is to combine fragmented hospital demand, recruiting, candidate, staffing, schedule, payroll, and pipeline-operational information into a governed analytical platform. The project demonstrates repeatable Azure ingestion, Snowflake workload separation and data layers, metadata/audit controls, idempotent transformations, operational monitoring, and a Power BI workforce dashboard.

Major use cases are:

- initial CSV ingestion and backfill;
- event-driven routing when canonical landing files arrive;
- metadata-driven execution of five source objects;
- simulated operational changes and incremental ingestion;
- staffing-demand, candidate-funnel, schedule, payroll, and pipeline-health analytics;
- infrastructure provisioning and monitoring with Terraform.

The repository correctly calls published AMN metrics—more than 100 GB/day, 1,176 replicated tables, 99.9% pipeline success, and 1–3 minute pipeline SLAs—reference benchmarks, not results achieved by this proof of concept.

## 2. Current Architecture

### Repository-verified flow

```text
Synthetic/public source CSVs
  -> ADLS Gen2 private landing container
  -> Azure Data Factory
       TR_LANDING_CSV_CREATED -> PL_FILE_EVENT_ROUTER -> one PL_COPY_* child
       TR_METADATA_INGEST_BATCH_READY -> PL_METADATA_INGEST -> configured PL_COPY_* children
  -> temporary Azure Blob SAS staging required by the Snowflake V2 connector
  -> Snowflake AMN_DEV.RAW
  -> Snowflake MERGE_* stored procedures
  -> Snowflake AMN_DEV.CURATED
  -> Snowflake AMN_DEV.MARTS views
  -> Power BI DirectQuery semantic model/report

ADF/Key Vault/Storage diagnostics
  -> Log Analytics -> saved KQL queries and Azure Monitor alerts
```

**[VERIFIED IN REPOSITORY]** Source files are held locally under `datasets/` and are uploaded by Terraform or `scripts/publish_existing_data.ps1` to canonical paths in the `landing` container. ADF uses `LS_ADLS_GEN2` for source access through its managed identity, `LS_BLOB_STAGE_SAS` for the Snowflake connector's temporary staging, `LS_SNOWFLAKE_V2` for loading/querying Snowflake, and `LS_KEY_VAULT` for secret references.

**[VERIFIED IN REPOSITORY]** Each `PL_COPY_*` pipeline creates a batch ID, writes a STARTED audit record, copies the CSV to a corresponding RAW table, calls a Snowflake merge procedure, and records SUCCEEDED or FAILED. RAW data preserves source-aligned strings and ingestion metadata; CURATED tables contain typed, de-duplicated business entities; MARTS exposes dimensions, facts, executive KPIs, recruiting, and pipeline views.

### UI/live-environment extension not versioned here

**[FROM CONVERSATION HISTORY]** A simulated Azure SQL operational source was manually created for staffing requests, candidates, schedules, and payroll. Manually built ADF incremental pipelines reportedly use old/new watermarks, delta copies, Snowflake merge procedures, and a two-minute trigger named `TR_INCREMENTAL_OPERATIONAL_2MIN`.

**Important discrepancy:** `monitoring.tf` knows the names of these incremental pipelines and trigger, but the repository contains no Azure SQL Terraform resource, Azure SQL linked-service/dataset JSON, incremental pipeline JSON, watermark/delta DDL, or incremental merge-procedure DDL. The next agent must export/commit the live definitions or reconstruct them only after inspecting the live environment.

## 3. Technology Stack

| Category | Technology actually represented |
|---|---|
| Cloud | Microsoft Azure |
| Ingestion/orchestration | Azure Data Factory, Snowflake V2 connector |
| Storage | ADLS Gen2 (`StorageV2` with HNS), Blob temporary staging |
| Operational database | **[FROM CONVERSATION HISTORY]** Azure SQL Database |
| Warehouse/transformation | Snowflake SQL, SQL stored procedures, warehouses |
| Infrastructure as Code | Terraform >= 1.6, AzureRM ~> 4.0, AzAPI ~> 2.0, Random ~> 3.6 |
| Programming | Python 3.12, pandas, Faker; PowerShell |
| Analytics | Power BI Desktop, PBIP/TMDL, DirectQuery |
| Monitoring | Azure Monitor, Log Analytics, KQL, ADF diagnostic logs |
| Secrets/security | Azure Key Vault, managed identity, Azure RBAC, Snowflake roles |
| Local development | Docker/Compose, VS Code/Codex-compatible workspace |

Debezium was discussed but not adopted. No Spark, Databricks, Airflow, dbt, Azure Functions, Snowflake streams, or Snowflake tasks are implemented in the repository.

## 4. Repository Structure

```text
case_study_01_amn/
├── config/                 Example metadata/source configuration
├── datasets/               CMS, HR, Synthea, and processed synthetic CSVs
├── docs/                   Build, operations, routing, monitoring, BI, and case-study docs
├── infra/
│   ├── adf/                Sanitized ADF linked-service, dataset, and pipeline JSON
│   ├── bootstrap/          Terraform remote-state bootstrap
│   └── terraform/          Main Azure infrastructure, ADF, triggers, secrets, monitoring
├── powerbi/                PBIP semantic models and report definitions/variants
├── scripts/                Data preparation, generation, upload, and PBIP redesign tools
├── sql/snowflake/          Ordered Snowflake platform and validation scripts 001–010
├── .env.example            Non-secret Snowflake environment-variable template
├── AMN_BATCH_READY.json    Batch-ready marker used by the metadata event trigger
├── Dockerfile              Python 3.12 development container
├── compose.yaml            Local bind-mounted development service
├── README.md               Project rationale, target architecture, backlog, acceptance gates
└── requirements.txt        Python dependencies
```

Important caveats:

- **[VERIFIED IN REPOSITORY]** `docs/DEPLOYMENT.md` contains stale statements saying ADF deployment is a future slice; later files `infra/terraform/adf.tf` and `infra/adf/*` supersede that statement.
- **[VERIFIED IN REPOSITORY]** Three Power BI variants exist: `AMN_Healthcare_Dashboard`, `_Redesigned`, and `_Presentation`. The presentation variant contains the most explicit slicer/card/chart layout generated by `build_amn_presentation_pbip.ps1`.
- **[VERIFIED IN REPOSITORY]** There is no usable Git repository metadata at the workspace root; `git status` reports that it is not a Git repository. File history cannot be reconstructed from commits.

## 5. Data Sources

| Source | Nature | Objects/formats | Repository volume | Key/relationships | Ingestion/destination |
|---|---|---|---:|---|---|
| CMS hospital reference | Public-style/reference, cleaned for demo | `hospitals_reference.csv` | 5,432 rows | `HOSPITAL_ID` | Snapshot CSV -> `RAW.HOSPITALS` -> `CURATED.HOSPITALS` |
| Synthetic AMN HR | Synthetic/demo | candidates, employees, payroll, recruiters, schedules, staffing requests CSV | 20,000; 5,000; 30,000; 100; 20,000; 2,000 rows | candidate/request/employee/hospital IDs | Five configured ingestion objects exclude employees/recruiters as standalone loads |
| Synthea | Synthetic health data | organizations, providers, patients, encounters, claims CSV | 839; 839; 1,131; 64,336; 119,626 rows | remapped IDs and encounter/patient/provider/org relationships | Prepared under `datasets/processed/synthea`; not connected to current ADF/Snowflake first slice |
| Azure SQL operational simulation | Synthetic/demo | staffing requests, candidates, schedules, payroll tables | **[UNKNOWN]** live row count | business PK plus `LAST_MODIFIED_AT`; delete marker discussed | **[FROM CONVERSATION HISTORY]** incremental ADF -> RAW delta -> CURATED |
| Large-volume HR generator | Synthetic/demo | six HR CSVs written to `G:\My Drive\AMN_1M_Data\hr` | Configured total is about 1.1M rows across files: 500 recruiters, 75k requests, 150k candidates, 50k employees, 525k schedules, and ~300k payroll rows | generator validates relationships | **[PARTIALLY TESTED]** generation code exists; no 1M+ output or completed cloud load is present in this repository |

Canonical landing paths are:

- `landing/cms/hospitals/hospitals_reference.csv`
- `landing/hr/candidates/candidates.csv`
- `landing/hr/staffing_requests/staffing_requests.csv`
- `landing/hr/schedules/schedules.csv`
- `landing/hr/payroll/payroll.csv`
- batch marker: `landing/control/AMN_BATCH_READY.json`

The five configured ingestion frequencies are event/batch driven; no fixed frequency is encoded for the blob triggers. SLA metadata is 180 seconds for staffing requests/schedules, 900 seconds for candidates, and 86,400 seconds for hospitals/payroll.

## 6. Database and Data Model

### Snowflake object model

**[VERIFIED IN REPOSITORY]** Database `AMN_DEV` has schemas:

- `RAW`: append-oriented source-aligned tables;
- `CURATED`: typed and idempotently merged business entities;
- `MARTS`: Power BI serving views;
- `CONTROL`: configuration, audit, checkpoint, data-quality, and freshness objects;
- `QUARANTINE`: reserved for rejected rows; no quarantine table DDL is present.

| Layer | Object | Purpose/key |
|---|---|---|
| RAW | `HOSPITALS` | Source hospital rows; `HOSPITAL_ID`, ingestion metadata expected |
| RAW | `STAFFING_REQUESTS` | String-form source records; business key `REQUEST_ID` |
| RAW | `CANDIDATES` | String-form source records; key `CANDIDATE_ID`; request/hospital/employee references |
| RAW | `SCHEDULES` | String-form source records; key `SCHEDULE_ID`; employee/request/hospital references |
| RAW | `PAYROLL` | String-form source records; key `PAYROLL_ID`; employee/hospital references |
| CURATED | same five names | Typed current-state entities, timestamps, declared primary-key constraints |
| CONTROL | `INGESTION_CONFIG` | `(SOURCE_SYSTEM, SOURCE_OBJECT)` config key; path, target, load type, PK, watermark, SLA, enabled flag |
| CONTROL | `PIPELINE_RUN_LOG` | `(RUN_ID, SOURCE_OBJECT)` audit key; batch, timings, counts, status, retry and error fields |
| CONTROL | `LOAD_CHECKPOINT` | `(SOURCE_SYSTEM, SOURCE_OBJECT)` checkpoint key; last watermark/batch |
| CONTROL | `DATA_QUALITY_RESULT` | Per-run checks and blocking/pass status |
| CONTROL | `PIPELINE_FRESHNESS` | View joining audit to SLA config |
| MARTS | `DIM_HOSPITAL`, `DIM_CANDIDATE`, `DIM_DATE` | Reporting dimensions |
| MARTS | `FACT_STAFFING_REQUEST`, `FACT_PLACEMENT_SCHEDULE`, `FACT_PAYROLL` | Reporting facts |
| MARTS | `VW_RECRUITING_FUNNEL`, `VW_EXECUTIVE_KPIS` | Business summary views |
| MARTS | `VW_PIPELINE_RUNS`, `VW_PIPELINE_LATEST_STATUS` | Pipeline operational views |

Power BI model relationships are single-direction dimension-to-fact relationships: hospital to the three facts and candidate; date to staffing, schedule, candidate, and payroll.

No repository DDL creates Snowflake stages, file formats, streams, tasks, functions, or sequences. ADF's Snowflake V2 connector creates temporary stages and therefore receives `CREATE STAGE` on RAW.

## 7. Data Pipeline Architecture

### Versioned pipelines

| Pipeline | Source -> destination | Trigger/caller | Activities and behavior | Status |
|---|---|---|---|---|
| `PL_COPY_HOSPITALS` | canonical hospital CSV -> RAW -> CURATED | router, metadata parent, or manual | set batch; start audit; Copy; `MERGE_HOSPITALS`; success/failure audit | **[VERIFIED IN REPOSITORY]** JSON exists; **[FROM CONVERSATION HISTORY]** successful UI runs occurred |
| `PL_COPY_STAFFING_REQUESTS` | staffing CSV -> RAW -> CURATED | same | seven-activity audited pattern; generic HR audit procedures | same |
| `PL_COPY_CANDIDATES` | candidates CSV -> RAW -> CURATED | same | seven-activity audited pattern | same |
| `PL_COPY_SCHEDULES` | schedules CSV -> RAW -> CURATED | same | seven-activity audited pattern | same |
| `PL_COPY_PAYROLL` | payroll CSV -> RAW -> CURATED | same | seven-activity audited pattern | same |
| `PL_FILE_EVENT_ROUTER` | trigger folder/file parameters | `TR_LANDING_CSV_CREATED` | Switch validates the exact canonical path and executes exactly one child | **[VERIFIED IN REPOSITORY]** |
| `PL_METADATA_INGEST` | `CONTROL.INGESTION_CONFIG` | `TR_METADATA_INGEST_BATCH_READY` or manual | Lookup enabled configs; ForEach with concurrency up to four; route configured object to child | **[VERIFIED IN REPOSITORY]** |
| `PL_BOOTSTRAP_HR_RAW` | embedded Snowflake script | manual | creates HR RAW objects; not Terraform-deployed in `adf.tf` | **[VERIFIED IN REPOSITORY]** definition only |

The child pipelines have a 12-hour activity timeout and explicit retry count `0`. Failure dependencies call audit procedures. The implementation is replayable at CURATED because merges select the latest RAW row per business key, although repeated snapshot loads can grow RAW.

### Versioned datasets and linked services

- `DS_ADLS_CSV`: parameterized `container`, `directory`, `file_name`.
- `DS_SNOWFLAKE_TABLE`: parameterized `schema_name`, `table_name`.
- `DS_SNOWFLAKE_CONFIG`: reads Snowflake configuration metadata.
- `LS_ADLS_GEN2`, `LS_BLOB_STAGE_SAS`, `LS_KEY_VAULT`, `LS_SNOWFLAKE_V2`.

### Triggers

- `TR_LANDING_CSV_CREATED`: non-empty `Microsoft.Storage.BlobCreated`, prefix `/landing/blobs/`, suffix `.csv`; routes to `PL_FILE_EVENT_ROUTER`.
- `TR_METADATA_INGEST_BATCH_READY`: non-empty BlobCreated, prefix `/landing/blobs/control/`, suffix `AMN_BATCH_READY.json`; runs `PL_METADATA_INGEST`.
- `TR_INCREMENTAL_OPERATIONAL_2MIN`: **[FROM CONVERSATION HISTORY]** schedule trigger for operational pipelines. Only its name is referenced by monitoring code; no trigger resource/JSON is versioned.

Do not activate both file-event contracts for the same delivery: uploading canonical CSVs and then a batch marker can process the same logical batch twice.

## 8. Incremental Loading / CDC

**[FROM CONVERSATION HISTORY]** The adopted operational pattern is watermark-based incremental extraction, not Debezium and not true row-event CDC:

1. Read old watermark from Snowflake control state.
2. Read the source's current maximum `LAST_MODIFIED_AT` as the new watermark.
3. Copy rows satisfying `(old watermark, new watermark]` to an object-specific Snowflake delta table.
4. Merge inserts/updates and interpret `IS_DELETED` for deletes.
5. Advance the watermark only after the merge succeeds.
6. Reuse batch IDs/audit logs for traceability; a failed run retains the prior watermark for replay.

**[FROM CONVERSATION HISTORY]** Azure SQL Change Tracking was discussed/enabled as a possible source-change mechanism, but the executed pipeline design shown in conversation used timestamp watermarks and delete flags. Whether Change Tracking is currently enabled on every live table is **[UNKNOWN]**.

**[VERIFIED IN REPOSITORY]** Only the generic `LOAD_CHECKPOINT` table is versioned. `INGESTION_WATERMARK`, `RAW.*_DELTA`, incremental stored procedures, Azure SQL schemas, and ADF incremental definitions are absent. `sql/snowflake/010_validate_all_adf_trigger_runs.sql` refers only to versioned generic control/core objects and therefore does not prove that all live incremental objects exist.

Duplicate prevention is strong in versioned full-load CURATED merges (`ROW_NUMBER` latest-by-key + `MERGE`) but RAW is append-oriented. Production-grade concurrency locking, overlapping watermark windows, and hard-delete capture are not repository-verified.

## 9. Snowflake Implementation

**[VERIFIED IN REPOSITORY]** Ordered deployment scripts:

1. `001_bootstrap.sql`: `AMN_DEV`, five schemas, three X-Small warehouses (`AMN_INGEST_WH`, `AMN_TRANSFORM_WH`, `AMN_BI_WH`), and roles (`AMN_INGEST_ROLE`, `AMN_TRANSFORM_ROLE`, `AMN_BI_ROLE`). Warehouses auto-resume and auto-suspend after 60 seconds.
2. `002_control_tables.sql`: configuration, audit, checkpoint, quality tables, and freshness view.
3. `003_hospitals_curated.sql`: typed hospitals and owner-rights merge.
4. `004_hospitals_audit.sql`: `START_HOSPITALS_RUN`, `SUCCEED_HOSPITALS_RUN`, `FAIL_HOSPITALS_RUN`.
5. `005_grant_hr_raw_to_adf.sql`: RAW/stage permissions.
6. `006_recreate_hr_raw_tables.sql`: destructive recreation of the four HR RAW tables; run carefully.
7. `007_hr_curated_and_audit.sql`: four CURATED tables; four merge procedures; generic `START_HR_RUN`, `SUCCEED_HR_RUN`, `FAIL_HR_RUN`.
8. `008_metadata_ingestion_config.sql`: five active metadata configurations.
9. `009_power_bi_marts.sql`: dimensions, facts, executive/recruiting/pipeline views and BI grants.
10. `010_validate_all_adf_trigger_runs.sql`: post-run checks for audit status, counts, batches, PK/FK quality, checkpoints, DQ, and MARTS smoke tests.

Owner-rights procedures let the ingestion role execute controlled transformations without broad CURATED writes. BI receives MARTS usage/select only. Actual live grants and object deployment after later UI work are **[UNKNOWN]** without querying Snowflake.

## 10. Azure Implementation

| Service/resource | Safe known name/pattern | Purpose and dependencies | Status |
|---|---|---|---|
| Resource group | `rg-amn-dev-data` | Groups platform resources | **[FROM CONVERSATION HISTORY + 2026-08-12 audit]** manually created/live |
| ADF | Terraform pattern `adf-amn-dev-<suffix>`; conversation showed both `adf-amn-dev-sss` and `adf-amn-dev-ionqqq` | orchestration, system-assigned managed identity | **[UNKNOWN]** which environment is current; definitions exist |
| ADLS Gen2 | Terraform pattern `stamndev<suffix>` | landing/checkpoint/quarantine/archive, private containers | **[FROM CONVERSATION HISTORY]** live; exact current account uncertain |
| Key Vault | Terraform pattern `kv-amn-dev-<suffix>` | Snowflake password and Blob SAS references | **[FROM CONVERSATION HISTORY]** live; exact current vault uncertain |
| Log Analytics | `log-amn-dev-<suffix>` | ADF/Key Vault/Storage telemetry | **[FROM 2026-08-12 audit]** live |
| Azure SQL server | `sql-amn-dev-sss.database.windows.net` | simulated operational source | **[FROM CONVERSATION HISTORY]** manually created; not Terraform-managed here |
| Azure SQL database | `sqldb-amn-operational-dev` | staffing/candidate/schedule/payroll changeable records | **[FROM CONVERSATION HISTORY]** manually created |
| Azure Monitor action group | `ag-amn-dev-data-operations` | optional email notification target | **[VERIFIED IN REPOSITORY]** defined; deployment unverified |

Terraform region is `eastus2`; the 2026-08-12 live audit recorded manually created foundation resources in Central India. Public network access is currently configured true in `terraform.tfvars`. ADF has a managed virtual network enabled, but no custom integration runtime or managed private endpoint is versioned. ADF receives Storage Blob Data Contributor and Key Vault Secrets User; an optional developer receives Storage Blob Data Contributor. Azure SQL authentication method used by the live linked service is **[UNKNOWN]**; an error showed an empty user and a transient routing timeout before connectivity was adjusted.

## 11. TERRAFORM / INFRASTRUCTURE AS CODE

### Terraform structure

Main root: `infra/terraform/`.

- `versions.tf`: Terraform/provider constraints.
- `providers.tf`: AzureRM configured by subscription variable and AzAPI.
- `backend.tf`: AzureRM remote backend declaration.
- `backend.hcl`: configured backend values; values are intentionally not reproduced here.
- `locals.tf`: naming, tags, four containers, and five source-file paths.
- `main.tf`: resource group, Log Analytics, storage/containers/blobs, ADF, Key Vault, RBAC, diagnostics.
- `secrets.tf`: optional Key Vault secret resources and optional operator role assignment. Secret values would enter Terraform state.
- `adf.tf`: linked services, datasets, five copy pipelines, router, metadata parent, and two Blob event triggers.
- `monitoring.tf`: incremental names, action group, saved searches, and three alerts.
- `variables.tf`: inputs and validation.
- `outputs.tf`: resource, identity, storage, vault, workspace, checkpoint, action group, and saved-query outputs.
- `terraform.tfvars`: current non-secret environment choices plus sensitive/account values; never quote/copy this file into tickets or chat.
- `*.tfplan`: several binary saved plans. Their age and applicability are unknown; do not apply blindly.

Bootstrap root: `infra/bootstrap/` creates a dedicated state resource group, storage account, private `tfstate` container, and operator RBAC. `.terraform.lock.hcl` files exist in both roots. The only discovered `terraform.tfstate` is Terraform's internal backend metadata under `.terraform`; it is not proof of managed resource state.

### Providers

| Provider | Constraint | Authentication |
|---|---|---|
| `hashicorp/azurerm` | `~> 4.0` | Azure CLI/service-principal environment determined at runtime; subscription variable |
| `Azure/azapi` | `~> 2.0` | inherits Azure authentication |
| `hashicorp/random` | `~> 3.6` | local random suffix generation |

No provider aliases are defined.

### Terraform resources

| Terraform Resource | Actual Resource | Service | File | Purpose | Status |
|---|---|---|---|---|---|
| `azurerm_resource_group.this` | `rg-amn-dev-data` | Resource Manager | `main.tf` | platform boundary | manual live resource reported; import/reconciliation required |
| `azurerm_log_analytics_workspace.this` | `log-amn-dev-<suffix>` | Log Analytics | `main.tf` | telemetry | live reported in 2026-08-12 audit; state unverified |
| `azurerm_storage_account.data_lake` | `stamndev<suffix>` | ADLS Gen2 | `main.tf` | HNS data lake | live reported; naming/settings drift |
| `azurerm_storage_container.data_lake[*]` | landing/checkpoint/quarantine/archive | Blob/ADLS | `main.tf` | zones | live reported; audit also mentioned snowflake-stage not currently in local set |
| `azurerm_storage_blob.source_csv[*]` | five canonical CSV paths | Blob | `main.tf` | seed landing data | defined; live import/deployment unverified |
| `azurerm_data_factory.this` | `adf-amn-dev-<suffix>` | ADF | `main.tf` | orchestration | live manual environment reported; exact current suffix uncertain |
| `azurerm_key_vault.this` | `kv-amn-dev-<suffix>` | Key Vault | `main.tf` | secret references | live reported; irreversible-setting drift |
| `azurerm_role_assignment.adf_storage_blob_contributor` | ADF -> Storage Blob Data Contributor | RBAC | `main.tf` | data access | live reported |
| `azurerm_role_assignment.developer_storage_blob_contributor` | optional user assignment | RBAC | `main.tf` | portal data access | configured when object ID supplied; live reported after IAM issue |
| `azurerm_role_assignment.adf_key_vault_secrets_user` | ADF -> Key Vault Secrets User | RBAC | `main.tf` | secret reads | live reported |
| three `azurerm_monitor_diagnostic_setting.*` | send-to-log-analytics | Azure Monitor | `main.tf` | diagnostics | ADF/KV live reported; Storage setting not found in audit |
| four `azapi_resource.adf_linked_service_*` | `LS_*` | ADF | `adf.tf` | ADLS, Blob, KV, Snowflake connections | live reported/import instructions exist |
| three `azapi_resource.adf_dataset_*` | `DS_*` | ADF | `adf.tf` | parameterized datasets | live status differs by audit date; definitions current |
| seven `azapi_resource.adf_pipeline_*` | five copy + router + metadata parent | ADF | `adf.tf` | batch/file ingestion | definitions current; manual live runs reported |
| two `azurerm_data_factory_trigger_blob_event.*` | `TR_METADATA_INGEST_BATCH_READY`, `TR_LANDING_CSV_CREATED` | ADF/Event Grid | `adf.tf` | event-driven starts | both configured activated=true; actual live activation unverified |
| optional `azurerm_key_vault_secret.*` | named password/SAS secrets | Key Vault | `secrets.tf` | connection secrets | only created if sensitive values supplied; deployment unknown |
| optional `azurerm_role_assignment.key_vault_secrets_officer` | operator assignment | RBAC | `secrets.tf` | secret administration | deployment unknown |
| `azurerm_monitor_action_group.data_operations` | `ag-amn-dev-data-operations` | Monitor | `monitoring.tf` | alerts | defined, deployment unknown |
| two `azurerm_log_analytics_saved_search.*` | incremental pipeline/trigger health | Log Analytics | `monitoring.tf` | operational KQL | defined, deployment unknown |
| three `azurerm_monitor_scheduled_query_rules_alert_v2.*` | failure/trigger/SLA alerts | Monitor | `monitoring.tf` | severity 1/2 alerts | defined, controlled by enable variable; deployment unknown |

Bootstrap separately defines state resource group, storage account, `tfstate` container, random suffix, and current-operator Storage Blob Data Contributor.

### Terraform state and deployment status

**[VERIFIED IN REPOSITORY]** Backend type is remote AzureRM and `backend.hcl` is configured. Workspace name is **[UNKNOWN]**. No readable main state snapshot proving current ownership exists in the repository.

- **DEPLOYED:** **[FROM CONVERSATION HISTORY / dated live audit only]** resource group, storage, containers, ADF, Key Vault, Log Analytics, key RBAC, several ADF objects.
- **DEFINED BUT DEPLOYMENT UNVERIFIED:** all current main/ADF/trigger/monitoring resources.
- **MANUALLY CREATED / NOT TERRAFORM MANAGED HERE:** Azure SQL server/database; incremental linked service, datasets, pipelines, and two-minute trigger; possibly multiple Azure environments/suffixes.
- **PLANNED:** reconcile/import live objects and capture incremental resources in code.
- **UNKNOWN:** current remote state contents, latest plan, drift after 2026-08-12, action-group/alert deployment.

Known safe commands from documentation/history include `terraform init -backend-config=backend.hcl`, `terraform fmt`, `terraform validate`, `terraform plan -refresh-only`, `terraform plan`, targeted `terraform import`, and—only with explicit approval—`terraform apply`. Never run `terraform destroy`. Do not apply saved `.tfplan` files without recreating/reviewing them.

Known Terraform risks:

- manual resource names use fixed suffixes while Terraform generates a random suffix;
- live audit region was Central India but tfvars is eastus2;
- storage shared-key, Key Vault purge/retention, diagnostic categories, and storage diagnostics have drift;
- applying before import can create parallel resources or force replacement;
- Terraform-managed secrets enter state;
- the manually added incremental/Azure SQL layer is outside current Terraform coverage.

## 12. Power BI / Analytics

**[VERIFIED IN REPOSITORY]** Power BI connects to Snowflake `AMN_DEV.MARTS` through `AMN_BI_WH` using the BI role and DirectQuery. The semantic model contains three dimensions, three facts, four operational/summary views, eight relationships, and measures for staffing, recruiting, schedules, payroll, and pipeline health.

Four pages exist:

1. Executive Overview
2. Recruiting & Candidates
3. Staffing Operations
4. Payroll & Pipeline Health

The presentation build script adds consistent headers/navigation, up to six KPI cards in one row, dropdown slicers for year/hospital/state, and titled charts. Measures include Open Requests, Open Positions, Fill Rate, Average Time to Fill, candidate/placement metrics, planned/worked/overtime hours, gross/net/overtime payroll, pipeline success, SLA compliance, runtime, retries, rows processed, and last successful load.

**[FROM CONVERSATION HISTORY]** The report was repeatedly redesigned after blank template imports, overlapping cards, poor slicers, and blank/error visuals. The last screenshots showed the themed four-page PBIP with cards/slicers, but some charts were blank and Power BI warned that modified relationships needed refresh. Therefore the semantic model/report is **partially completed**, not production-polished. The likely immediate checks are refresh relationships, inspect each blank visual's fields, confirm MARTS values/categories exist, and validate DirectQuery credentials—not regenerate the report blindly.

Power BI Service publishing, gateway/credentials, scheduled refresh, sharing URL, and access control are **[NOT TESTED/UNKNOWN]**. DirectQuery reduces dataset-refresh dependence but published service credentials still must be configured.

## 13. Security

- ADF uses a system-assigned managed identity for ADLS and Key Vault.
- Storage containers are private; OAuth is the default storage authentication.
- Key Vault uses RBAC, soft delete, TLS, and optional purge protection.
- Secrets are referenced, not embedded in sanitized ADF JSON. Never expose `snowflake-adf-password`, Blob SAS URI, Azure SQL credentials, or Terraform sensitive inputs.
- Snowflake separates ingestion, transformation, and BI roles/warehouses.
- Power BI must consume MARTS, not RAW/CURATED.
- Public network access is currently enabled in tfvars for development. Private endpoints/managed private endpoints and production network hardening are not implemented.
- Snowflake password authentication exists for the learning connector; key-pair authentication is recommended for shared/production use.

When documenting values, replace them with `<SECRET>`, `<PASSWORD>`, `<TOKEN>`, or `<CONNECTION_STRING>`.

## 14. Naming Conventions

- Azure: `<service>-amn-<environment>-<suffix>`, e.g. `adf-amn-dev-<suffix>`, `kv-amn-dev-<suffix>`; resource group `rg-amn-dev-data`.
- Terraform: snake_case logical names such as `data_lake`, `adf_pipeline_copy_hospitals`.
- Snowflake: uppercase database/schema/object names; `AMN_DEV`, `RAW`, `CURATED`, `MARTS`, `CONTROL`.
- ADF pipelines: `PL_COPY_<OBJECT>`, `PL_METADATA_INGEST`, `PL_FILE_EVENT_ROUTER`, and conversation-only `PL_INCREMENTAL_<OBJECT>`.
- ADF datasets: `DS_<PLATFORM>_<TYPE>`; linked services: `LS_<SERVICE>`; triggers: `TR_<EVENT/PURPOSE>`.
- Procedures: `MERGE_<OBJECT>`, `START_*_RUN`, `SUCCEED_*_RUN`, `FAIL_*_RUN`.
- Ingestion metadata: underscore prefix (`_BATCH_ID`, `_SOURCE_FILE`, `_INGESTED_AT`).

## 15. Important Configuration

| Setting | Value/status |
|---|---|
| Environment/project | `dev` / `amn` |
| Terraform desired region | `eastus2` |
| Dated live-audit region | Central India; conflict requires reconciliation |
| Resource group | `rg-amn-dev-data` |
| Snowflake database | `AMN_DEV` |
| Warehouses | `AMN_INGEST_WH`, `AMN_TRANSFORM_WH`, `AMN_BI_WH` |
| Schemas | RAW, CURATED, MARTS, CONTROL, QUARANTINE |
| Storage containers | landing, checkpoint, quarantine, archive |
| Python | 3.12 container |
| Generator output | `G:\My Drive\AMN_1M_Data\hr` |
| ADF trigger flags in tfvars | metadata and landing CSV triggers currently `true` |
| Incremental alerts | variable-controlled; live enablement unknown |
| Power BI mode | DirectQuery |

## 16. Major Technical Decisions

### Decision: use Snowflake layered schemas and separate warehouses

- **REASON:** governance, workload isolation, raw traceability, typed trusted data, and stable BI contracts.
- **ALTERNATIVES CONSIDERED:** Power BI directly on RAW or one shared warehouse/schema.
- **WHY REJECTED:** weak governance and unpredictable resource contention.
- **CURRENT STATUS:** **[VERIFIED IN REPOSITORY]**.

### Decision: use ADF + Snowflake V2 staged copy

- **REASON:** ADLS Gen2 Managed Identity source is not eligible for the connector's direct-copy path; Blob SAS staging is required.
- **ALTERNATIVES:** legacy Snowflake connector/direct copy.
- **WHY REJECTED:** connector constraints and legacy status.
- **CURRENT STATUS:** **[VERIFIED IN REPOSITORY]**.

### Decision: keep secrets in Key Vault

- **REASON:** avoid credentials in ADF JSON/repository.
- **ALTERNATIVES:** inline credentials or Terraform values.
- **WHY REJECTED:** secret exposure and state risk.
- **CURRENT STATUS:** **[VERIFIED IN REPOSITORY]** design; actual secrets not inspected.

### Decision: two distinct file trigger contracts

- **REASON:** one supports immediate canonical-file routing; one supports coordinated batch readiness/metadata fan-out.
- **ALTERNATIVES:** attach one trigger separately to many pipelines.
- **WHY REJECTED:** weak routing/control and duplicate/irrelevant runs.
- **CURRENT STATUS:** **[VERIFIED IN REPOSITORY]**; avoid using both for one delivery.

### Decision: watermark micro-batches instead of Debezium

- **REASON:** simpler, lower operational overhead, and appropriate for a small Azure/ADF/Snowflake case-study source.
- **ALTERNATIVES:** Debezium/Kafka and native CDC/event-per-change.
- **WHY REJECTED:** unnecessary infrastructure and complexity for this proof of concept.
- **CURRENT STATUS:** **[FROM CONVERSATION HISTORY]** live UI implementation only; repository incomplete.

### Decision: DirectQuery Power BI over MARTS

- **REASON:** current data without an import-refresh delay and governed serving objects.
- **ALTERNATIVES:** Import mode or RAW/CURATED connection.
- **WHY REJECTED:** refresh latency or unstable/untrusted model contracts.
- **CURRENT STATUS:** **[VERIFIED IN REPOSITORY]**.

### Decision: use PBIP source rather than a theme/template alone

- **REASON:** a `.pbit`/theme does not automatically create bound visuals; PBIP permits versionable semantic/report definitions.
- **ALTERNATIVES:** import theme/template and expect a complete dashboard.
- **WHY REJECTED:** produced blank pages.
- **CURRENT STATUS:** **[VERIFIED IN REPOSITORY + HISTORY]**; visual polish still incomplete.

## 17. Problems Encountered and Solutions

### Landing container showed no items/permission error

- **Root cause:** signed-in Entra user lacked data-plane Blob role; this was not proof that Terraform failed to create the container.
- **Solution:** optional `developer_storage_blob_contributor` Terraform role assignment using the user's object ID; wait for propagation/re-authenticate.
- **Affected:** storage IAM, `main.tf`, tfvars.
- **Status:** **Resolved per conversation; live state unverified.**

### Snowflake `ROWS_WRITTEN` invalid identifier

- **Root cause:** query referenced a column not present in `PIPELINE_RUN_LOG`; the actual column is `ROWS_INSERTED` (plus updated/deleted/rejected).
- **Solution:** align monitoring SQL to `002_control_tables.sql`.
- **Status:** Resolved conceptually.

### `INGESTION_WATERMARK` not found/not authorized

- **Root cause:** incremental walkthrough referenced an object not versioned/created in the repository, or the ADF role lacked access.
- **Solution attempted:** create/seed the control object manually and use the correct Snowflake role.
- **Status:** **Partially resolved in live UI; repository discrepancy remains.**

### Azure SQL `SqlFailedToConnect` / routing timeout

- **Root cause:** networking/firewall/linked-service configuration; the error also showed an empty user.
- **Solution attempted:** allow Azure services, client firewall rule, review connector/timeout; connection later reported working.
- **Status:** **Resolved per conversation, not independently verified.**

### Snowflake incremental merge procedure unknown

- **Root cause:** ADF called `AMN_DEV.CONTROL.SP_MERGE_STAFFING_REQUESTS_INCREMENTAL` before a matching callable procedure existed/was visible; a procedure call later failed internally on invalid column `SPECIALTY` because the delta schema did not match CURATED (`REQUIRED_ROLE`/`DEPARTMENT`).
- **Solution:** inspect actual schemas, recreate procedure with correct column mapping/types, then call with batch ID.
- **Status:** **Conversation reports later tests completed; procedure DDL is missing from repository.**

### Power BI template imported as blank

- **Root cause:** a theme/template cannot synthesize bound visuals; earlier artifact did not contain report visuals.
- **Solution:** create PBIP report definitions and build scripts with explicit visuals/model bindings.
- **Status:** blank-template issue resolved; visual data issues remain.

### Overlapping/blank Power BI visuals

- **Root cause:** generated layout/card dimensions and later relationship/field changes; screenshots showed a manual relationship refresh warning and blank category charts.
- **Solution attempted:** redesigned/presentation PBIP, dropdown slicers, consistent theme and top-row cards.
- **Status:** **Partially resolved.** Refresh model and repair remaining visual bindings.

### Workspace error 267 / inaccessible path

- **Root cause:** Codex session pointed to a nonexistent OneDrive path; the real repository was on Desktop and later moved to `C:\dev\case_study_01_amn`.
- **Solution:** use `Set-Location`/`cd` with a quoted existing path and restart from correct workspace. File patching was later verified.
- **Status:** Resolved.

### Limited disk space for 1M+ data

- **Root cause:** C: had only a few GB free. Google Drive mounted as G: initially displayed local cache capacity, not cloud entitlement.
- **Solution:** use Google Drive streaming and generate outputs in `G:\My Drive\AMN_1M_Data\hr`; do not mirror large folders locally.
- **Status:** generator path updated; end-to-end large load unverified.

## 18. Rejected Approaches

- Debezium/Kafka for this proof of concept: too much operational overhead relative to ADF watermark micro-batches.
- Power BI directly against RAW/CURATED: violates the governed MARTS contract.
- Expecting a theme or PBIT import to create a complete bound dashboard: themes style visuals but do not create them.
- One generic file-arrival event attached indiscriminately to all child pipelines: causes irrelevant or duplicate executions; use the router.
- Simultaneously using canonical-file and batch-marker triggers for the same delivery: risks double ingestion.
- Blind Terraform apply over manually created Azure resources: can create parallel resources or destructive replacement; import/reconcile first.
- Storing Snowflake passwords/SAS URIs in the repository or casually in Terraform state: use Key Vault and secured state.
- True per-row immediate ADF triggering from database updates: ADF schedule/micro-batch watermarks are more appropriate here; database-row events require additional change-event infrastructure.

## 19. Testing Completed

| Component | Test | Expected / actual | Status |
|---|---|---|---|
| Five CSV child pipelines | ADF debug runs and activity outputs | screenshots/history showed successful copy/merge/audit runs | **PASSED [HISTORY]** |
| Metadata parent | Lookup + ForEach + Switch/child execution | screenshot showed successful routed children | **PASSED [HISTORY]** |
| Snowflake base SQL | created/queried core tables and procedures | multiple Snowsight results; initial identifier errors were corrected | **PARTIALLY TESTED** |
| Incremental staffing | old/new watermark, delta copy, merge | initial watermark/procedure/schema failures; later user said tests done | **PARTIALLY TESTED [HISTORY]** |
| Other operational incrementals | candidates/schedules/payroll simulation | user reported tests done; definitions/results absent | **PARTIALLY TESTED [HISTORY]** |
| Azure storage IAM | portal list access after Terraform RBAC | reported working later | **PASSED [HISTORY]** |
| Azure SQL connection | ADF linked-service/pipeline connectivity | failed with routing timeout, later reported working | **PARTIALLY TESTED [HISTORY]** |
| Event router | canonical multi-path routing | Terraform/JSON and test procedure documented; no retained run evidence | **PARTIALLY TESTED** |
| Monitoring | KQL saved queries and alert definitions | Terraform exists; no live alert firing evidence | **NOT TESTED** |
| Power BI semantic model | DirectQuery tables/relationships/measures | cards returned data; some charts blank | **PARTIALLY TESTED** |
| 1M+ generator | code configured for ~1.1M rows | output stored outside repo, completion not demonstrated | **NOT VERIFIED** |
| 1M+ ADF-to-Snowflake load | run and count validation | no successful run evidence | **NOT TESTED/NOT VERIFIED** |
| Post-trigger checker | `010_validate_all_adf_trigger_runs.sql` created | syntax inspected locally; not executed against Snowflake | **NOT TESTED** |
| Terraform | fmt/validate/plans historically produced | binary plans exist; current config/state/live drift not revalidated | **PARTIALLY TESTED** |

## 20. Current Project Status

### COMPLETED

- Repository sample/synthetic data and preparation/generation scripts.
- Terraform definitions for the Azure foundation, ADF CSV/metadata ingestion, two file triggers, RBAC, diagnostics, and incremental monitoring.
- Sanitized ADF definitions for five child pipelines, router, metadata parent, three datasets, and four linked services.
- Snowflake 001–009 base/control/curated/mart scripts.
- Power BI PBIP semantic model, measures, four-page report variants, and build/redesign scripts.
- `010_validate_all_adf_trigger_runs.sql` post-run validation script.

### PARTIALLY COMPLETED

- Live Terraform ownership/import and drift reconciliation.
- Azure SQL operational incremental ingestion: built/tested through UI according to history but not source-controlled.
- Power BI visuals: themed pages/cards/slicers exist; some charts remain blank or need relationship refresh.
- Monitoring definitions: code exists, deployment/alerts unverified.
- Complete documentation has some stale/conflicting sections.

### NOT STARTED / NOT VERIFIED

- Source-control export of Azure SQL linked service, datasets, incremental pipelines, schedule trigger, SQL DDL, and Terraform.
- A verified 1M+ end-to-end run through landing/ADF/Snowflake/MARTS/Power BI.
- Power BI Service publish/share configuration and production authentication.
- Production network hardening/private endpoints, key-pair Snowflake authentication, formal CI/CD.

### BLOCKED

No hard local-workspace blocker exists. Cloud continuation requires access to the correct Azure/Snowflake environment and confirmation of which resource suffix/environment is authoritative. Terraform apply is unsafe until imports and drift are resolved.

## 21. Current Blocker

Development stopped after creating the post-trigger Snowflake validation script and discussing the missing proof of a 1M+ load.

- **Task:** validate a generated 1M+ dataset through the complete ADF/Snowflake pipeline and preserve the incremental implementation.
- **Problem:** the large output is outside the repository; no ADF run evidence or Snowflake counts establish completion. Incremental UI resources/DDL are also absent from source control.
- **Suspected cause:** work was performed manually across Azure/Snowflake and not exported; multiple Azure suffixes may represent different environments.
- **Attempts:** generator redirected to Google Drive; ADF/file/incremental tests performed interactively; `010_validate_all_adf_trigger_runs.sql` added.
- **Current state:** validation tooling exists but has not been run against a demonstrated 1M+ load.
- **Recommended investigation:** identify the authoritative live factory/storage/Snowflake account; export live incremental definitions read-only; run counts before loading; upload one controlled large dataset; monitor ADF; execute SQL 010; record exact evidence.

## 22. Next Implementation Steps

### STEP 1 — Establish the authoritative environment

- Objective: resolve `sss` versus `ionqqq` and current subscription/resource names.
- Files: `infra/terraform/LIVE_RESOURCE_AUDIT.md`, `ADF_IMPORT.md`, tfvars (do not expose secrets).
- Prerequisites: read-only Azure/ADF access.
- Validation: inventory names, regions, trigger states, and resource IDs; save only non-secret findings.

### STEP 2 — Export and source-control the incremental implementation

- Objective: close the largest repository/live discrepancy.
- Expected changes: sanitized Azure SQL linked service/datasets, four child incremental pipelines, parent pipeline, schedule trigger, Azure SQL source DDL, Snowflake watermark/delta/procedure DDL, and matching Terraform resources/import notes.
- Validation: JSON parses; SQL object references match real columns; Terraform fmt/validate; no secrets.

### STEP 3 — Reconcile Terraform state safely

- Objective: make Terraform accurately describe existing resources.
- Prerequisites: secured remote backend and explicit user approval for any state mutation.
- Method: imports and `terraform plan -refresh-only`; resolve region/name/purge/shared-key drift. Do not apply until replacement-free plan is understood.
- Validation: normal plan has no unintended replacement/parallel resources.

### STEP 4 — Prove the 1M+ source data

- Objective: generate and profile the configured ~1.1M HR rows on streamed Google Drive storage.
- Files: `scripts/generate_amn_hr_data.py`.
- Validation: generator relationship checks pass; record per-file row counts, sizes, keys, and disk/cache behavior. Do not commit million-row files.

### STEP 5 — Run one controlled large ingestion

- Objective: test throughput without triggering duplicate contracts.
- Prerequisites: choose either canonical file trigger or batch marker and disable the other for that delivery; warehouse/cost approval.
- Validation: ADF trigger/router/child statuses, duration, rows copied, Snowflake query history, and no overlapping run.

### STEP 6 — Execute Snowflake post-run validation

- File: `sql/snowflake/010_validate_all_adf_trigger_runs.sql`.
- Expected: successful recent audits, correct batches/counts, zero null/duplicate PKs, zero unexpected FK issues, current checkpoints, and populated MARTS.
- Record results without credentials or sensitive query history.

### STEP 7 — Repair and validate Power BI

- Objective: eliminate blank charts and relationship warnings.
- Files: presentation PBIP, `009_power_bi_marts.sql`, build script.
- Method: refresh relationships/metadata, verify each blank visual's category and measure, test slicer interactions, and confirm DirectQuery sees the new counts.
- Validation: all four pages render, no error visuals, no overlap, relevant dropdown slicers filter data.

### STEP 8 — Verify monitoring and document acceptance results

- Objective: prove failure and SLA telemetry.
- Files: `monitoring.tf`, `docs/INCREMENTAL_MONITORING.md`.
- Validation: saved KQL returns runs; controlled non-destructive failure produces alert; record recovery and end-to-end freshness.

## 23. Important Files for the Next Agent

| Priority | File | Why Read It |
|---|---|---|
| CRITICAL | `PROJECT_CONTEXT.md` | Persistent handoff, discrepancies, safety, next steps |
| CRITICAL | `infra/terraform/LIVE_RESOURCE_AUDIT.md` | Dated live/manual-vs-Terraform drift |
| CRITICAL | `infra/terraform/ADF_IMPORT.md` | Safe import ordering and warnings |
| CRITICAL | `infra/terraform/adf.tf` | Versioned ADF objects and file triggers |
| CRITICAL | `sql/snowflake/010_validate_all_adf_trigger_runs.sql` | Current last completed task and post-load validation |
| HIGH | `infra/adf/README.md` | ADF inventory and intended behavior |
| HIGH | `infra/adf/pipeline.PL_METADATA_INGEST.json` | Metadata orchestration |
| HIGH | `infra/adf/pipeline.PL_FILE_EVENT_ROUTER.json` | Canonical file routing |
| HIGH | `sql/snowflake/002_control_tables.sql` | Authoritative audit/config/checkpoint schema |
| HIGH | `sql/snowflake/007_hr_curated_and_audit.sql` | HR typed merges/auditing |
| HIGH | `sql/snowflake/009_power_bi_marts.sql` | BI serving contract |
| HIGH | `scripts/generate_amn_hr_data.py` | 1M+ synthetic-data generator and external output path |
| HIGH | `powerbi/AMN_Healthcare_Dashboard_Presentation/AMN_Healthcare_Dashboard_Complete.pbip` | Most presentation-oriented dashboard entry point |
| MEDIUM | `docs/FILE_EVENT_ROUTING.md` | Trigger activation and duplicate-run warning |
| MEDIUM | `docs/INCREMENTAL_MONITORING.md` | KQL and portal monitoring procedure |
| MEDIUM | `docs/AMN_HEALTHCARE_COMPLETE_CASE_STUDY.md` | Business narrative and historical intended architecture |
| MEDIUM | `docs/AZURE_SNOWFLAKE_CONSOLE_UI_STEPS.md` | Detailed manual first-slice setup/troubleshooting |
| LOW | `README.md` | Original target architecture/backlog and benchmark caveats |

## 24. Agent Safety Instructions

- Read this document before modifying the project.
- Inspect existing code before creating new files.
- Treat repository state as the source of truth for current implementation.
- Never assume infrastructure exists because Terraform defines it.
- Never expose secrets, passwords, tokens, keys, SAS URIs, or connection strings.
- Never delete resources without explicit approval.
- Never run `terraform destroy`.
- Never run `terraform apply` without explicit user approval.
- Never modify Terraform state or import resources without explicit approval.
- Never apply an old binary plan.
- Never replace working architecture without understanding why it exists.
- Prefer extending the existing implementation over rebuilding it.
- Ask before destructive infrastructure or data changes.
- Do not run `006_recreate_hr_raw_tables.sql` against populated RAW tables without explicit confirmation and recovery planning.
- Do not activate both file trigger contracts for one delivery.
- Do not commit generated million-row datasets or credentials.
- Validate the correct live Azure environment before acting; conversation screenshots referenced more than one suffix.

## 25. Quick Start for the Next Agent

**PROJECT:** AMN Healthcare Azure Data Factory -> Snowflake -> Power BI learning case study.

**CURRENT STATE:** Versioned full-load/event/metadata ingestion, Snowflake layered model, monitoring Terraform, synthetic-data tooling, and four-page PBIP exist. UI-created incremental resources are not versioned.

**CURRENT BLOCKER:** No verified 1M+ end-to-end load evidence; authoritative live Azure environment and incremental definitions must be identified.

**LAST COMPLETED TASK:** Created `sql/snowflake/010_validate_all_adf_trigger_runs.sql` for post-trigger validation.

**NEXT TASK:** Read-only inventory/export of the authoritative live incremental/Azure SQL implementation, then controlled 1M+ run and SQL 010 validation.

**IMPORTANT FILES:** this file, `LIVE_RESOURCE_AUDIT.md`, `ADF_IMPORT.md`, `adf.tf`, ADF JSON, Snowflake SQL 002/007/009/010, generator, presentation PBIP.

**INFRASTRUCTURE STATUS:** Manual/live Azure foundation and ADF work were reported; exact current suffix and deployment state are not repository-verifiable. Azure SQL is manual and outside Terraform.

**TERRAFORM STATUS:** Remote AzureRM backend configured; definitions and saved plans exist; state ownership/drift are unresolved. Import/reconcile before any approved apply.
