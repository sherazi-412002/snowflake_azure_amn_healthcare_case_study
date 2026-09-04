# Azure Portal and Snowflake Snowsight Implementation: Baby Steps

This guide implements the first AMN data-platform slice manually through the Azure Portal, Azure Data Factory Studio, and Snowflake Snowsight. It uses the data already present in this repository; do not rerun the data generators.

Manual UI creation is useful for learning and validating the architecture. Terraform remains the source-of-truth approach for repeatable environments. Do not create the same resource with both Terraform and the portal unless you plan to import the manual resource into Terraform afterward.

## What you will build

```text
Existing local CSV files
          |
          | Azure Portal upload
          v
ADLS Gen2 landing container
          |
          | ADF Copy activity
          v
Snowflake RAW tables
          |
          | SQL validation and MERGE
          v
Snowflake CURATED tables
          |
          v
CONTROL audit and SLA records
```

The first five sources are:

1. Hospitals
2. Candidates
3. Staffing requests
4. Schedules
5. Payroll

## Before you begin

You need:

- An Azure subscription where you can create resources and role assignments.
- A Snowflake account where you can create databases, schemas, warehouses, roles, users, and tables.
- The existing files in `datasets/cms` and `datasets/hr`.
- Permission to create secrets in Azure Key Vault.
- An approved Azure region and a naming prefix unique to your organization.

Creating and running cloud resources can incur charges. Use a development subscription/account, X-Small Snowflake warehouses, ADF debug runs, and storage lifecycle controls.

Use example names consistently:

| Resource | Example |
|---|---|
| Azure resource group | `rg-amn-dev-data` |
| Storage account | `stamndev<unique>` |
| Data Factory | `adf-amn-dev-<unique>` |
| Key Vault | `kv-amn-dev-<unique>` |
| Snowflake database | `AMN_DEV` |

Additional names used by this guide:

| Object | Exact name |
|---|---|
| ADLS linked service | `LS_ADLS_GEN2` |
| Key Vault linked service | `LS_KEY_VAULT` |
| Snowflake linked service | `LS_SNOWFLAKE_V2` |
| Blob staging linked service | `LS_BLOB_STAGE_SAS` |
| Parameterized CSV dataset | `DS_ADLS_CSV` |
| Parameterized Snowflake dataset | `DS_SNOWFLAKE_TABLE` |
| First pipeline | `PL_COPY_HOSPITALS` |
| First Copy activity | `COPY_HOSPITALS_TO_RAW` |

## Conventions that prevent common setup failures

1. Snowflake object names created without double quotes are stored in uppercase. Enter `RAW` and `HOSPITALS` in ADF, not `raw` and `hospitals`.
2. A linked-service test only proves that authentication works. Dataset preview additionally proves access to a particular schema and table.
3. ADF dataset parameter defaults are used during authoring and preview. Pipeline activity values override those defaults at runtime.
4. Never leave a blank row in an ADF Parameters grid. A blank row produces `Parameter name can't be empty` and `Parameter "" value can't be empty`.
5. The Snowflake password and Blob SAS URI are different secrets. Never select `snowflake-adf-password` when configuring Blob staging.
6. With the ADLS Gen2 Managed Identity source used in this guide, Snowflake V2 needs built-in staged copy through an Azure Blob Storage linked service.
7. Select **Save/Create** in each editor and **Publish all** only after validation and debug succeed.

Azure Storage, Data Factory, and Key Vault names must be globally unique where Azure requires it. Replace `<unique>` with a short lowercase suffix.

# Part A: Azure Portal implementation

## Step 1: Confirm the Azure subscription

1. Open [Azure Portal](https://portal.azure.com/).
2. Select your profile in the upper-right corner.
3. Confirm the correct tenant/directory.
4. Search for **Subscriptions**.
5. Open the intended development subscription.
6. Record its subscription name and ID.

Checkpoint: you can see the subscription overview and have permission to create a resource group. Stop if the selected subscription is not the intended one.

## Step 2: Create the resource group

1. Search for **Resource groups**.
2. Select **Create**.
3. Choose the correct subscription.
4. Enter `rg-amn-dev-data`.
5. Choose the approved region, such as `East US 2`.
6. Under **Tags**, add:
   - `application = AMN data platform`
   - `environment = dev`
   - `owner = <your-name-or-team>`
   - `managed_by = manual-ui`
7. Select **Review + create**.
8. Select **Create**.

Checkpoint: the resource group deployment succeeds and contains no resources yet.

## Step 3: Create ADLS Gen2 storage

1. Search for **Storage accounts**.
2. Select **Create**.
3. Choose the development subscription and `rg-amn-dev-data`.
4. Enter a unique lowercase name such as `stamndevabc123`.
5. Select the same region as the resource group.
6. Select **Standard** performance.
7. Select **Locally-redundant storage (LRS)** for the development exercise.
8. Open the **Advanced** tab.
9. Under **Data Lake Storage Gen2**, enable **Hierarchical namespace**.
10. Require secure transfer and keep minimum TLS at 1.2 or later.
11. Keep anonymous blob access disabled.
12. For this first local upload, leave public network access enabled. Production should use private endpoints and approved networks.
13. Add the project tags.
14. Select **Review + create**, then **Create**.

The hierarchical namespace is what gives the StorageV2 account ADLS Gen2 capabilities.

Checkpoint:

1. Open the storage account.
2. Select **Data Lake Storage** or **Configuration**.
3. Confirm **Hierarchical namespace = Enabled**.
4. Confirm anonymous access is disabled.

## Step 4: Create storage containers and folders

1. In the storage account, select **Data storage > Containers**.
2. Create each container with **Private (no anonymous access)**:
   - `landing`
   - `checkpoint`
   - `quarantine`
   - `archive`
3. Open `landing`.
4. Create these directories:

```text
cms/hospitals
hr/candidates
hr/staffing_requests
hr/schedules
hr/payroll
```

Checkpoint: the four private containers exist and the five folder paths appear under `landing`.

## Step 5: Upload the existing CSV files through the portal

Upload these mappings one at a time:

| Local file | ADLS destination |
|---|---|
| `datasets/cms/hospitals_reference.csv` | `landing/cms/hospitals/hospitals_reference.csv` |
| `datasets/hr/candidates.csv` | `landing/hr/candidates/candidates.csv` |
| `datasets/hr/staffing_requests.csv` | `landing/hr/staffing_requests/staffing_requests.csv` |
| `datasets/hr/schedules.csv` | `landing/hr/schedules/schedules.csv` |
| `datasets/hr/payroll.csv` | `landing/hr/payroll/payroll.csv` |

For each file:

1. Open its destination directory in the `landing` container.
2. Select **Upload**.
3. Browse to the existing local CSV.
4. Leave overwrite disabled if the file already exists.
5. Select **Upload**.

Checkpoint: each destination contains one non-empty CSV. Download or preview one file and confirm that its header is readable.

## Step 6: Create Azure Data Factory

1. Search for **Data factories**.
2. Select **Create**.
3. Choose the development subscription and `rg-amn-dev-data`.
4. Enter `adf-amn-dev-<unique>`.
5. Choose the same region.
6. Select the latest available V2 type/version if the portal asks.
7. Under Git configuration, choose **Configure Git later** for the first exercise, or connect an approved repository if it already exists.
8. Enable a managed virtual network if the creation page exposes the option.
9. Add the project tags.
10. Select **Review + create**, then **Create**.

After deployment:

1. Open the Data Factory resource.
2. Select **Properties**.
3. Confirm a system-assigned managed identity exists.
4. Record its object/principal ID.
5. Select **Launch studio**.

Azure creates a system-assigned managed identity for a Data Factory created in the portal. Use this identity instead of storage keys whenever a connector supports it.

## Step 7: Give ADF access to ADLS

1. Return to the ADLS storage account.
2. Select **Access control (IAM)**.
3. Select **Add > Add role assignment**.
4. Choose **Storage Blob Data Contributor**.
5. Select **Next**.
6. For assignment type, select **Managed identity**.
7. Select **Select members**.
8. Choose your subscription.
9. Choose **Data Factory** as the managed-identity type.
10. Select `adf-amn-dev-<unique>`.
11. Select **Review + assign** twice.

Role propagation may take several minutes.

Checkpoint: the storage account's role assignments list the ADF managed identity as `Storage Blob Data Contributor`.

## Step 8: Create Key Vault

1. Search for **Key vaults**.
2. Select **Create**.
3. Choose the development subscription and `rg-amn-dev-data`.
4. Enter `kv-amn-dev-<unique>`.
5. Choose the same region.
6. Use the Standard pricing tier.
7. Enable soft delete; enable purge protection for production.
8. On the access configuration page, choose **Azure role-based access control** rather than legacy access policies.
9. Leave public access enabled for the first development setup only.
10. Add tags, review, and create.

Checkpoint: the Key Vault overview shows the Azure RBAC permission model.

## Step 9: Grant Key Vault roles

ADF needs read-only access to secret values:

1. Open the Key Vault.
2. Select **Access control (IAM)**.
3. Select **Add > Add role assignment**.
4. Choose **Key Vault Secrets User**.
5. Select **Managed identity**.
6. Choose the ADF managed identity.
7. Select **Review + assign**.

Your operator needs permission to create secrets:

1. Add another role assignment.
2. Choose **Key Vault Secrets Officer**.
3. Select **User, group, or service principal**.
4. Select only your approved user/group.
5. Review and assign.

Do not give ADF Secrets Officer or Administrator access. ADF only needs to read connection secrets.

Checkpoint: ADF has `Key Vault Secrets User`; your approved operator has `Key Vault Secrets Officer`.

## Step 10: Create Log Analytics and diagnostic settings

1. Search for **Log Analytics workspaces**.
2. Select **Create**.
3. Use the AMN resource group and region.
4. Name it `log-amn-dev-<unique>`.
5. Set development retention to at least 30 days.
6. Create the workspace.

For Data Factory:

1. Open the Data Factory Azure resource.
2. Select **Monitoring > Diagnostic settings**.
3. Select **Add diagnostic setting**.
4. Name it `send-to-log-analytics`.
5. Enable available pipeline, activity, trigger, and integration-runtime logs.
6. Enable metrics.
7. Send them to the new Log Analytics workspace.
8. Save.

Repeat diagnostic configuration for Key Vault audit logs and storage metrics.

Checkpoint: each resource shows an enabled diagnostic setting targeting the same workspace.

# Part B: Snowflake Snowsight implementation

## Step 11: Sign in and open a SQL workspace

1. Sign in to Snowflake Snowsight.
2. Open **Projects > Workspaces** and create/open a SQL file. Some accounts may still display **Projects > Worksheets**.
3. Use the context selector to choose an administrative role authorized for setup.
4. Select an existing administrative warehouse for the setup commands.

Snowflake is replacing legacy Worksheets with Workspaces, so the exact editor label can differ by account rollout. The SQL is the same.

Checkpoint:

```sql
SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE();
```

Confirm that you are using the expected user, role, and warehouse.

## Step 12: Create the Snowflake platform objects

1. Open the repository file `sql/snowflake/001_bootstrap.sql`.
2. Copy its SQL into the Snowsight SQL file.
3. Review all names and grants.
4. Run one logical section at a time:
   - Database and schemas as `SYSADMIN`
   - Warehouses as `SYSADMIN`
   - Roles and grants as `SECURITYADMIN`
5. Inspect every result before continuing.

The script creates:

```text
Database:   AMN_DEV
Schemas:    RAW, CURATED, MARTS, CONTROL, QUARANTINE
Warehouses: AMN_INGEST_WH, AMN_TRANSFORM_WH, AMN_BI_WH
Roles:      AMN_INGEST_ROLE, AMN_TRANSFORM_ROLE, AMN_BI_ROLE
```

Checkpoint:

```sql
SHOW SCHEMAS IN DATABASE AMN_DEV;
SHOW WAREHOUSES LIKE 'AMN_%';
SHOW ROLES LIKE 'AMN_%';
```

Expected result: five AMN schemas, three warehouses, and three functional roles.

## Step 13: Create control and SLA objects

1. Open `sql/snowflake/002_control_tables.sql`.
2. Copy it into a new Snowsight SQL file.
3. Select `SYSADMIN` and `AMN_TRANSFORM_WH` as context.
4. Run the script.

It creates:

- `INGESTION_CONFIG`
- `PIPELINE_RUN_LOG`
- `LOAD_CHECKPOINT`
- `DATA_QUALITY_RESULT`
- `PIPELINE_FRESHNESS`

Checkpoint:

```sql
SHOW TABLES IN SCHEMA AMN_DEV.CONTROL;
SHOW VIEWS IN SCHEMA AMN_DEV.CONTROL;
```

## Step 14: Create a dedicated ADF Snowflake user

For the learning implementation, create a service user instead of using a personal administrator account. Review authentication policy with your Snowflake administrator.

Run as `USERADMIN` or another authorized role:

```sql
USE ROLE USERADMIN;

CREATE USER IF NOT EXISTS AMN_ADF_SVC
  PASSWORD = '<temporary-strong-password>'
  DEFAULT_ROLE = AMN_INGEST_ROLE
  DEFAULT_WAREHOUSE = AMN_INGEST_WH
  MUST_CHANGE_PASSWORD = FALSE
  COMMENT = 'Development service user for Azure Data Factory';

USE ROLE SECURITYADMIN;
GRANT ROLE AMN_INGEST_ROLE TO USER AMN_ADF_SVC;
```

Important:

- Do not put the real password in a repository or shared worksheet.
- Prefer Snowflake key-pair authentication for shared/production environments.
- If account policy disallows password service users, follow the approved key-pair/OAuth method instead.
- Apply a suitable network and authentication policy before production.

Checkpoint:

```sql
SHOW USERS LIKE 'AMN_ADF_SVC';
SHOW GRANTS TO USER AMN_ADF_SVC;
```

## Step 15: Store the Snowflake password in Key Vault

1. Return to the Azure Portal.
2. Open the AMN Key Vault.
3. Select **Objects > Secrets**.
4. Select **Generate/Import**.
5. Enter `snowflake-adf-password` as the name.
6. Paste the temporary service-user password as the value.
7. Set an expiration and rotation date according to your policy.
8. Select **Create**.

Checkpoint: the secret appears as enabled. Do not copy its value into ADF JSON, source control, or screenshots.

## Step 15A: Create the temporary Blob staging SAS secret

This step is required because the source dataset uses the ADLS Gen2 connector with Managed Identity. Snowflake V2 cannot use that linked service for direct copy, so ADF must write temporary files to Blob storage before Snowflake runs `COPY INTO`.

Use the existing `checkpoint` container for temporary staging:

1. Open the storage account in Azure Portal.
2. Select **Data storage > Containers > checkpoint**.
3. Open the container's **Shared access tokens** or **Generate SAS** page.
4. Select these permissions:
   - Read
   - Add
   - Create
   - Write
   - Delete
   - List
5. Allow HTTPS only.
6. Set a short development expiration that covers the exercise.
7. Generate the SAS.
8. Copy the complete **Blob SAS URL/URI**, not only the token. It must resemble:

```text
https://<storage-account>.blob.core.windows.net/checkpoint?<sas-query-string>
```

9. Open the AMN Key Vault.
10. Select **Objects > Secrets > Generate/Import**.
11. Create:

```text
Name:  blob-stage-sas-uri
Value: <the complete checkpoint-container Blob SAS URI>
```

12. Do not reuse or overwrite `snowflake-adf-password`.

Checkpoint: Key Vault contains two different enabled secrets:

| Secret | Purpose |
|---|---|
| `snowflake-adf-password` | Authentication for `LS_SNOWFLAKE_V2` |
| `blob-stage-sas-uri` | Temporary Blob staging for Snowflake Copy |

If ADF reports `The remote name could not be resolved: '<password-value>'`, the Snowflake password secret was selected by mistake. Select `blob-stage-sas-uri`.

# Part C: Connect ADF to Azure and Snowflake

## Step 16: Create the Key Vault linked service

1. Open ADF Studio.
2. Select **Manage** (toolbox icon).
3. Select **Linked services**.
4. Select **New**.
5. Search for and choose **Azure Key Vault**.
6. Name it `LS_KEY_VAULT`.
7. Select the correct subscription and Key Vault.
8. Use the Data Factory managed identity.
9. Select **Test connection**.
10. Select **Create**.

If the test fails, wait for RBAC propagation and confirm ADF has `Key Vault Secrets User`.

## Step 17: Create the ADLS Gen2 linked service

1. In **Manage > Linked services**, select **New**.
2. Search for **Azure Data Lake Storage Gen2**.
3. Name it `LS_ADLS_GEN2`.
4. Use **AutoResolveIntegrationRuntime** for the initial public-endpoint development setup.
5. Select **Managed identity** authentication.
6. Select the subscription and storage account.
7. Test the connection.
8. Create the linked service.

Checkpoint: the test succeeds without an account key or SAS token.

## Step 18: Create the Snowflake V2 linked service

1. In **Manage > Linked services**, select **New**.
2. Search for **Snowflake**.
3. Select the current Snowflake V2 connector.
4. Name it `LS_SNOWFLAKE_V2`.
5. Enter the account identifier in `organization-account` form.
6. Enter database `AMN_DEV`.
7. Enter warehouse `AMN_INGEST_WH`.
8. Select Basic authentication for this development exercise, unless key-pair authentication is already approved.
9. Enter username `AMN_ADF_SVC`.
10. For the password, select the Key Vault linked service and secret `snowflake-adf-password` if the UI exposes Key Vault secret selection. If not, use a secure linked-service parameter/reference supported by your tenant rather than placing the secret in source JSON.
11. Test the connection.
12. Create the linked service.

The connector must be Snowflake V2. Do not create a new implementation using the legacy connector.

Checkpoint: the connection test succeeds and Snowflake query history shows the service user connecting with `AMN_INGEST_WH`.

## Step 18A: Create the Azure Blob staging linked service

This is a fourth linked service in addition to ADLS, Key Vault, and Snowflake.

1. In ADF Studio, select **Manage > Linked services > New**.
2. Search for **Azure Blob Storage**. Do not choose Azure Data Lake Storage Gen2.
3. Name it `LS_BLOB_STAGE_SAS`.
4. Select **SAS URI** authentication.
5. Select **Azure Key Vault** as the secret source.
6. Select `LS_KEY_VAULT`.
7. Select secret `blob-stage-sas-uri`.
8. Leave secret version as **Latest version** unless your rotation process pins versions.
9. Use `AutoResolveIntegrationRuntime`.
10. Select **Test connection**.
11. Select **Create**.

Checkpoint: the linked-services list contains all four:

```text
LS_KEY_VAULT
LS_ADLS_GEN2
LS_SNOWFLAKE_V2
LS_BLOB_STAGE_SAS
```

Troubleshooting:

- `Remote name could not be resolved`: the selected secret is not a complete Blob SAS URI.
- Authorization failure: regenerate the container SAS with Read, Add, Create, Write, Delete, and List permissions.
- Secret access failure: confirm the ADF Managed Identity has `Key Vault Secrets User`.

## Step 19: Create a parameterized ADLS dataset

1. Select **Author** in ADF Studio.
2. Select **+ > Dataset**.
3. Choose **Azure Data Lake Storage Gen2**.
4. Choose **DelimitedText**.
5. Name it `DS_ADLS_CSV`.
6. Select `LS_ADLS_GEN2`.
7. Add dataset parameters:
   - `container` (String), default `landing`
   - `directory` (String), default `cms/hospitals`
   - `file_name` (String), default `hospitals_reference.csv`
8. Set the dataset path using dynamic content:
   - Container: `@dataset().container`
   - Directory: `@dataset().directory`
   - File: `@dataset().file_name`
9. Set first row as header.
10. Set delimiter to comma and quote character to double quote.
11. Preview `landing/cms/hospitals/hospitals_reference.csv`.

Checkpoint: the preview displays named columns and data rows rather than one unsplit text column.

Before leaving the Parameters tab, delete any completely blank parameter row. Blank rows later cause pipeline validation errors.

## Step 20: Create initial Snowflake RAW tables

Use Snowsight and run the following as a role with create-table access. Start with string-heavy raw tables so ingestion does not lose data because of premature type conversion. Business typing happens in CURATED.

```sql
USE ROLE SYSADMIN;
USE WAREHOUSE AMN_INGEST_WH;
USE DATABASE AMN_DEV;
USE SCHEMA RAW;

CREATE TABLE IF NOT EXISTS HOSPITALS (
  HOSPITAL_ID VARCHAR,
  HOSPITAL_NAME VARCHAR,
  CITY VARCHAR,
  STATE VARCHAR,
  HOSPITAL_TYPE VARCHAR,
  OWNERSHIP VARCHAR,
  EMERGENCY_SERVICES VARCHAR,
  HOSPITAL_RATING VARCHAR,
  _BATCH_ID VARCHAR,
  _SOURCE_FILE VARCHAR,
  _INGESTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Create the four HR RAW tables with the exact repository CSV headers. Keep RAW columns as `VARCHAR` during this first ingestion slice so values such as `Not Available`, dates, and decimals are preserved without load-time conversion failures.

```sql
CREATE TABLE IF NOT EXISTS CANDIDATES (
  CANDIDATE_ID VARCHAR,
  REQUEST_ID VARCHAR,
  HOSPITAL_ID VARCHAR,
  HOSPITAL_NAME VARCHAR,
  RECRUITER_ID VARCHAR,
  CANDIDATE_NAME VARCHAR,
  EMAIL VARCHAR,
  PHONE VARCHAR,
  PROFESSION VARCHAR,
  DEPARTMENT VARCHAR,
  EXPERIENCE_YEARS VARCHAR,
  LICENSE_STATE VARCHAR,
  LICENSE_STATUS VARCHAR,
  CERTIFICATIONS VARCHAR,
  SOURCE_CHANNEL VARCHAR,
  APPLICATION_DATE VARCHAR,
  CANDIDATE_STATUS VARCHAR,
  BACKGROUND_CHECK_STATUS VARCHAR,
  CREDENTIAL_STATUS VARCHAR,
  EMPLOYEE_ID VARCHAR,
  _BATCH_ID VARCHAR,
  _SOURCE_FILE VARCHAR,
  _INGESTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS STAFFING_REQUESTS (
  REQUEST_ID VARCHAR,
  HOSPITAL_ID VARCHAR,
  HOSPITAL_NAME VARCHAR,
  CITY VARCHAR,
  STATE VARCHAR,
  REQUIRED_ROLE VARCHAR,
  DEPARTMENT VARCHAR,
  EMPLOYMENT_TYPE VARCHAR,
  SHIFT_PREFERENCE VARCHAR,
  REQUIRED_STAFF VARCHAR,
  FILLED_STAFF VARCHAR,
  OPEN_POSITIONS VARCHAR,
  PRIORITY VARCHAR,
  REQUEST_STATUS VARCHAR,
  REQUEST_DATE VARCHAR,
  ASSIGNMENT_START_DATE VARCHAR,
  ASSIGNMENT_END_DATE VARCHAR,
  DURATION_WEEKS VARCHAR,
  HOURLY_BILL_RATE VARCHAR,
  _BATCH_ID VARCHAR,
  _SOURCE_FILE VARCHAR,
  _INGESTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS SCHEDULES (
  SCHEDULE_ID VARCHAR,
  EMPLOYEE_ID VARCHAR,
  REQUEST_ID VARCHAR,
  HOSPITAL_ID VARCHAR,
  HOSPITAL_NAME VARCHAR,
  WORK_DATE VARCHAR,
  SHIFT_TYPE VARCHAR,
  SHIFT_START_TIME VARCHAR,
  SHIFT_END_TIME VARCHAR,
  PLANNED_HOURS VARCHAR,
  WORKED_HOURS VARCHAR,
  OVERTIME_HOURS VARCHAR,
  SCHEDULE_STATUS VARCHAR,
  _BATCH_ID VARCHAR,
  _SOURCE_FILE VARCHAR,
  _INGESTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS PAYROLL (
  PAYROLL_ID VARCHAR,
  EMPLOYEE_ID VARCHAR,
  HOSPITAL_ID VARCHAR,
  HOSPITAL_NAME VARCHAR,
  PAYROLL_MONTH VARCHAR,
  REGULAR_HOURS VARCHAR,
  OVERTIME_HOURS VARCHAR,
  HOURLY_PAY_RATE VARCHAR,
  REGULAR_PAY VARCHAR,
  OVERTIME_PAY VARCHAR,
  BONUS VARCHAR,
  GROSS_PAY VARCHAR,
  TAX_AMOUNT VARCHAR,
  BENEFITS_DEDUCTION VARCHAR,
  NET_PAY VARCHAR,
  PAYMENT_STATUS VARCHAR,
  _BATCH_ID VARCHAR,
  _SOURCE_FILE VARCHAR,
  _INGESTED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Because these tables were created while using `SYSADMIN`, explicitly grant the ADF ingestion role access. Run as `SECURITYADMIN`:

```sql
USE ROLE SECURITYADMIN;

GRANT USAGE ON DATABASE AMN_DEV TO ROLE AMN_INGEST_ROLE;
GRANT USAGE ON SCHEMA AMN_DEV.RAW TO ROLE AMN_INGEST_ROLE;
GRANT USAGE ON WAREHOUSE AMN_INGEST_WH TO ROLE AMN_INGEST_ROLE;
GRANT CREATE STAGE ON SCHEMA AMN_DEV.RAW TO ROLE AMN_INGEST_ROLE;

GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA AMN_DEV.RAW
  TO ROLE AMN_INGEST_ROLE;
GRANT SELECT, INSERT ON FUTURE TABLES IN SCHEMA AMN_DEV.RAW
  TO ROLE AMN_INGEST_ROLE;
```

`CREATE STAGE` is required because the Snowflake V2 connector creates and drops a temporary stage while loading.

Verify existence as `SYSADMIN`:

```sql
USE ROLE SYSADMIN;
SHOW TABLES IN SCHEMA AMN_DEV.RAW;
```

Verify the same access ADF will use:

```sql
USE ROLE AMN_INGEST_ROLE;
USE WAREHOUSE AMN_INGEST_WH;
SELECT * FROM AMN_DEV.RAW.HOSPITALS LIMIT 1;
```

An empty result is successful; it means the table is accessible but has not been loaded.

For the first UI exercise, ADF imports mappings from the CSV and Snowflake table. Before production, commit this DDL to `sql/snowflake` and add `_SOURCE_SYSTEM`, `_SOURCE_OBJECT`, `_SOURCE_COMMIT_AT`, `_ROW_HASH`, and `_IS_DELETED` metadata.

Checkpoint: `Catalog > Database Explorer > AMN_DEV > RAW > Tables` lists exactly the five first-slice tables and the query under `AMN_INGEST_ROLE` succeeds.

## Step 21: Create a parameterized Snowflake dataset

1. In ADF Studio, select **+ > Dataset**.
2. Search for Snowflake and choose the **Snowflake V2** dataset.
3. Name it `DS_SNOWFLAKE_TABLE`.
4. Select `LS_SNOWFLAKE_V2`.
5. Open the **Parameters** tab.
6. Add exactly these parameters and defaults:

| Name | Type | Default value |
|---|---|---|
| `schema_name` | String | `RAW` |
| `table_name` | String | `HOSPITALS` |

7. Delete any blank parameter row.
8. Return to **Connection**.
9. Select **Enter manually** if the schema/table selector does not expose separate dynamic fields.
10. In the schema field, select **Add dynamic content** and enter:

```adf
@dataset().schema_name
```

11. In the table field, select **Add dynamic content** and enter:

```adf
@dataset().table_name
```

12. Preview data using the default values.

Expected preview:

- Object is `RAW.HOSPITALS`.
- Column headers appear.
- `No data available` is expected before the first pipeline run.

Do not use `raw/hospitals`, `AMN_DEV.raw`, or lowercase parameter values. If the error contains `AMN_DEV."raw"`, ADF is passing lowercase `raw`; change the dataset default and any pipeline override to uppercase `RAW`.

Checkpoint: ADF retrieves the `RAW.HOSPITALS` columns using the Snowflake service user. This proves table access even when the table contains zero rows.

## Step 22: Build the first hospitals copy pipeline

Start with one table before attempting metadata-driven loading.

1. Select **Author > + > Pipeline**.
2. Name it `PL_COPY_HOSPITALS`.
3. Drag a **Copy data** activity onto the canvas.
4. Name the activity `COPY_HOSPITALS_TO_RAW`.
5. On **Source**:
   - Dataset: `DS_ADLS_CSV`
   - Container: `landing`
   - Directory: `cms/hospitals`
   - File: `hospitals_reference.csv`
6. On **Sink**:
   - Dataset: `DS_SNOWFLAKE_TABLE`
   - `schema_name`: `RAW`
   - `table_name`: `HOSPITALS`
7. Confirm the activity values are uppercase. Activity values override dataset defaults.
8. On **Mapping**, select **Import schemas**.
9. Keep these eight explicit business mappings:

| CSV source | Snowflake sink |
|---|---|
| `hospital_id` | `HOSPITAL_ID` |
| `hospital_name` | `HOSPITAL_NAME` |
| `city` | `CITY` |
| `state` | `STATE` |
| `hospital_type` | `HOSPITAL_TYPE` |
| `ownership` | `OWNERSHIP` |
| `emergency_services` | `EMERGENCY_SERVICES` |
| `hospital_rating` | `HOSPITAL_RATING` |

10. Delete mappings whose source is empty and sink is `_BATCH_ID`, `_SOURCE_FILE`, or `_INGESTED_AT`. Empty source cells cause `Mapping source is empty`. For this first load, the first two remain null and Snowflake supplies the default ingestion timestamp when the third column is omitted.
11. On **Sink**, keep automatic table creation disabled. The table already exists.
12. Open the Copy activity's **Settings** tab.
13. Enable **Staging**.
14. Select `LS_BLOB_STAGE_SAS`.
15. Enter staging path:

```text
snowflake-stage/hospitals
```

16. Select **Validate**.
17. Resolve every error before debugging.
18. Select **Debug**.
19. Wait for the activity to reach **Succeeded**.
20. Open the activity output and record rows read, rows copied, duration, and throughput.

Why staging is mandatory here:

```text
ADLS Gen2 source through Managed Identity
              |
              v
ADF writes temporary converted files to checkpoint Blob storage
              |
              v
Snowflake temporary external stage and COPY INTO RAW.HOSPITALS
              |
              v
ADF cleans up the temporary files
```

If validation says direct copy is only supported from Azure Blob Storage or Amazon S3, staging is still disabled or `LS_BLOB_STAGE_SAS` is not selected.

If schema import says `AMN_DEV."raw" does not exist`, change the sink activity parameter from `raw` to `RAW`.

If validation says a parameter name/value is empty, remove blank rows from both dataset Parameters tabs and populate all five activity parameter values.

Checkpoint in Snowsight:

```sql
SELECT COUNT(*) FROM AMN_DEV.RAW.HOSPITALS;
SELECT * FROM AMN_DEV.RAW.HOSPITALS LIMIT 10;
```

The repository file contains 5,432 data rows excluding the header, so the first clean load should return `5432`. The sample rows must have correctly aligned columns. Preview `DS_SNOWFLAKE_TABLE` again; it should now show records instead of `No data available`.

## Step 23: Prevent duplicate snapshot loads

Copying the same snapshot twice into RAW appends duplicate source rows. RAW may retain those copies as ingestion history, but CURATED must remain idempotent. Do not debug the Copy activity repeatedly while diagnosing later activities unless you accept additional RAW rows.

Check the current RAW state:

```sql
SELECT
  COUNT(*) AS TOTAL_RAW_ROWS,
  COUNT(DISTINCT HOSPITAL_ID) AS DISTINCT_HOSPITALS,
  COUNT(*) - COUNT(DISTINCT HOSPITAL_ID) AS DUPLICATE_ROWS
FROM AMN_DEV.RAW.HOSPITALS;
```

For the current project, prevent duplicate business records by deduplicating inside the CURATED merge:

```text
ADLS immutable file
    -> RAW.HOSPITALS append-only landing
    -> keep latest row per HOSPITAL_ID
    -> MERGE into CURATED.HOSPITALS by HOSPITAL_ID
```

The merge implemented in Step 24 uses `ROW_NUMBER()` and `_INGESTED_AT` to choose one current record for each hospital. Running it repeatedly produces no duplicate CURATED keys.

For a temporary clean development reload only, you may truncate `RAW.HOSPITALS` as `SYSADMIN` immediately before rerunning the Copy activity:

```sql
TRUNCATE TABLE AMN_DEV.RAW.HOSPITALS;
```

Do not put that command into a production pipeline and never truncate CURATED as a routine ingestion strategy.

## Step 24: Create the first curated table and MERGE

1. Open `sql/snowflake/003_hospitals_curated.sql`.
2. Copy the full script into a new Snowsight SQL file.
3. Run the object-creation and grant sections.
4. The script creates:
   - `AMN_DEV.CURATED.HOSPITALS`
   - `AMN_DEV.CURATED.MERGE_HOSPITALS()`
   - Execute permission for `AMN_INGEST_ROLE`
5. Run the included manual `CALL` once.
6. Run the same `CALL` a second time.

The procedure executes with owner rights. ADF receives permission to call this one transformation without receiving general write access to the CURATED schema.

Checkpoint:

```sql
CALL AMN_DEV.CURATED.MERGE_HOSPITALS();

SELECT COUNT(*) FROM AMN_DEV.CURATED.HOSPITALS;

SELECT HOSPITAL_ID, COUNT(*)
FROM AMN_DEV.CURATED.HOSPITALS
GROUP BY HOSPITAL_ID
HAVING COUNT(*) > 1;
```

Expected:

- CURATED count equals the number of distinct nonblank RAW hospital IDs.
- Duplicate-key query returns zero rows.
- A second procedure call reports zero affected rows when source values did not change.

## Step 25: Add a Snowflake transformation activity in ADF

1. Return to `PL_COPY_HOSPITALS`.
2. Expand **General** in the Activities panel.
3. Drag a **Script** activity onto the canvas.
4. Name it `MERGE_HOSPITALS_TO_CURATED`.
5. Drag the green success connector from `COPY_HOSPITALS_TO_RAW` to the Script activity.
6. Open the Script activity's **Settings**.
7. Select linked service `LS_SNOWFLAKE_V2`.
8. Add one **Query** script.
9. Enter:

```sql
CALL AMN_DEV.CURATED.MERGE_HOSPITALS();
```

10. Keep sensitive input/output disabled unless a later script contains secrets.
11. Select **Validate**.
12. Select **Debug**.

If Script activity parameters or multiple statements are needed later, edit `LS_SNOWFLAKE_V2` and select connector version 1.1. This single `CALL` does not require multiple statements.

Checkpoint:

```sql
SELECT COUNT(*) FROM AMN_DEV.CURATED.HOSPITALS;
```

One ADF run must show both `COPY_HOSPITALS_TO_RAW` and `MERGE_HOSPITALS_TO_CURATED` as **Succeeded**.

## Step 26: Add basic audit logging

### Step 26A: Create the audit procedures

1. Open `sql/snowflake/004_hospitals_audit.sql`.
2. Copy it into a new Snowsight SQL file.
3. Run the entire script.
4. It creates three narrowly scoped owner-rights procedures:

```text
AMN_DEV.CONTROL.START_HOSPITALS_RUN(VARCHAR, VARCHAR)
AMN_DEV.CONTROL.SUCCEED_HOSPITALS_RUN(VARCHAR, NUMBER, NUMBER)
AMN_DEV.CONTROL.FAIL_HOSPITALS_RUN(VARCHAR, VARCHAR, VARCHAR)
```

### Step 26B: Add the pipeline variable

1. Select a blank area of `PL_COPY_HOSPITALS`.
2. Open **Variables**.
3. Add:

| Name | Type | Default |
|---|---|---|
| `batch_id` | String | leave blank |

4. Add a **Set variable** activity named `SET_BATCH_ID`.
5. Select variable `batch_id`.
6. Set its value with dynamic content:

```adf
@guid()
```

### Step 26C: Record STARTED

1. Add a Script activity named `AUDIT_HOSPITALS_STARTED`.
2. Connect `SET_BATCH_ID` to it with the green success dependency.
3. Use `LS_SNOWFLAKE_V2`.
4. For its Query, select **Add dynamic content** and enter:

```adf
@concat(
  'CALL AMN_DEV.CONTROL.START_HOSPITALS_RUN(''',
  pipeline().RunId,
  ''',''',
  variables('batch_id'),
  ''');'
)
```

5. Remove the old incoming dependency to `COPY_HOSPITALS_TO_RAW`, if one exists.
6. Connect `AUDIT_HOSPITALS_STARTED` to `COPY_HOSPITALS_TO_RAW` with green success.

The success sequence must now be:

```text
SET_BATCH_ID
  -> AUDIT_HOSPITALS_STARTED
  -> COPY_HOSPITALS_TO_RAW
  -> MERGE_HOSPITALS_TO_CURATED
```

### Step 26D: Record SUCCEEDED

1. Add a Script activity named `AUDIT_HOSPITALS_SUCCEEDED`.
2. Connect the green success output of `MERGE_HOSPITALS_TO_CURATED` to it.
3. Use `LS_SNOWFLAKE_V2`.
4. Add this dynamic Query:

```adf
@concat(
  'CALL AMN_DEV.CONTROL.SUCCEED_HOSPITALS_RUN(''',
  pipeline().RunId,
  ''',',
  string(activity('COPY_HOSPITALS_TO_RAW').output.rowsRead),
  ',',
  string(activity('COPY_HOSPITALS_TO_RAW').output.rowsCopied),
  ');'
)
```

If your successful Copy output uses a different field name, open its output JSON and select the exact row-count properties displayed by your tenant.

### Step 26E: Record failures

Use separate failure loggers so a Copy failure and a Merge failure are both handled.

1. Add a Script activity named `AUDIT_COPY_HOSPITALS_FAILED`.
2. Connect the red failure output of `COPY_HOSPITALS_TO_RAW` to it.
3. Use this dynamic Query:

```adf
@concat(
  'CALL AMN_DEV.CONTROL.FAIL_HOSPITALS_RUN(''',
  pipeline().RunId,
  ''',''COPY_FAILED'',''',
  replace(activity('COPY_HOSPITALS_TO_RAW').error.message,'''',''''''),
  ''');'
)
```

4. Add another Script activity named `AUDIT_MERGE_HOSPITALS_FAILED`.
5. Connect the red failure output of `MERGE_HOSPITALS_TO_CURATED` to it.
6. Use:

```adf
@concat(
  'CALL AMN_DEV.CONTROL.FAIL_HOSPITALS_RUN(''',
  pipeline().RunId,
  ''',''MERGE_FAILED'',''',
  replace(activity('MERGE_HOSPITALS_TO_CURATED').error.message,'''',''''''),
  ''');'
)
```

7. Select **Validate** and then **Debug**.

Checkpoint:

```sql
SELECT *
FROM AMN_DEV.CONTROL.PIPELINE_RUN_LOG
ORDER BY CREATED_AT DESC;
```

Every debug run should have one `HOSPITALS` record with final status `SUCCEEDED` or `FAILED`. A successful record should contain nonzero `ROWS_READ` and `ROWS_INSERTED`.

## Step 27: Build and test the other four end-to-end pipelines

The four HR pipelines reuse `DS_ADLS_CSV`, `DS_SNOWFLAKE_TABLE`, `LS_SNOWFLAKE_V2`, and `LS_BLOB_STAGE_SAS`. Run Snowflake scripts `005`, `006`, and `007` first.

| Pipeline | ADLS source | Target | Key | Tested rows |
|---|---|---|---|---:|
| `PL_COPY_STAFFING_REQUESTS` | `landing/hr/staffing_requests/staffing_requests.csv` | `STAFFING_REQUESTS` | `REQUEST_ID` | 2,000 |
| `PL_COPY_CANDIDATES` | `landing/hr/candidates/candidates.csv` | `CANDIDATES` | `CANDIDATE_ID` | 20,000 |
| `PL_COPY_SCHEDULES` | `landing/hr/schedules/schedules.csv` | `SCHEDULES` | `SCHEDULE_ID` | 20,000 |
| `PL_COPY_PAYROLL` | `landing/hr/payroll/payroll.csv` | `PAYROLL` | `PAYROLL_ID` | 30,000 |

### Step 27A: Seven-activity workflow

```text
SET_BATCH_ID
 -> AUDIT_<OBJECT>_STARTED
 -> COPY_<OBJECT>_TO_RAW
      |-- Failed -> AUDIT_COPY_<OBJECT>_FAILED
      `-- Succeeded -> MERGE_<OBJECT>_TO_CURATED
                           |-- Failed -> AUDIT_MERGE_<OBJECT>_FAILED
                           `-- Succeeded -> AUDIT_<OBJECT>_SUCCEEDED
```

Create String variable `batch_id` with value `@guid()`. Use the generic `START_HR_RUN`, `SUCCEED_HR_RUN`, and `FAIL_HR_RUN` procedures from script `007`. Use the matching CURATED merge procedure for each object.

For every Copy activity, set the source path from the table, target `RAW.<OBJECT>`, enable `LS_BLOB_STAGE_SAS`, and explicitly map lowercase CSV headers to uppercase Snowflake columns.

### Step 27B: Validation checkpoint

All four pipelines were validated, published, and tested. Copy, MERGE, and final audit activities succeeded with the row counts above.

```sql
SELECT SOURCE_OBJECT, STATUS, ROWS_READ, ROWS_INSERTED, EXTRACT_STARTED_AT, CURATED_AT
FROM AMN_DEV.CONTROL.PIPELINE_RUN_LOG
WHERE SOURCE_OBJECT IN ('STAFFING_REQUESTS','CANDIDATES','SCHEDULES','PAYROLL')
ORDER BY CREATED_AT DESC;
```

Snapshot reruns may append RAW rows, but each MERGE retains one current CURATED row per primary key.

## Step 28: Convert the five pipelines to metadata-driven loading

Once all five loads work:

1. Populate `CONTROL.INGESTION_CONFIG`.
2. Create one parent pipeline named `PL_METADATA_INGEST`.
3. Add a Lookup activity that reads enabled configuration rows.
4. Add a `ForEach` using Lookup output.
5. Set development concurrency to 4.
6. Inside the loop, use parameterized source and sink datasets.
7. Pass source path, schema, table, key, and SLA values from configuration.
8. Call a table-specific or metadata-driven merge procedure.
9. Record audit and checkpoint results.

This is the pattern that later scales to 1,100+ configured tables. The table count grows in metadata rather than through 1,100 manually drawn pipelines.

## Step 29: Publish the ADF work

Debug execution does not replace publishing.

1. Select **Validate all**.
2. Resolve every error.
3. Select **Publish all**.
4. Review the pending changes.
5. Publish.
6. Open **Monitor** and inspect pipeline and activity runs.

For a team environment, connect ADF to Git and promote through CI/CD instead of editing the live factory directly.

## Step 30: Understand the current SLA limitation

The existing CSV files are snapshots and do not contain source commit timestamps. Therefore:

- You can measure pipeline duration.
- You can measure ADLS-to-CURATED latency.
- You cannot yet prove true source-to-CURATED freshness.

To test the 1-3 minute SLA next:

1. Generate change files containing inserts, updates, and deletes.
2. Include `_SOURCE_COMMIT_AT` on every change.
3. Upload immutable change files every 30-60 seconds.
4. Trigger or schedule incremental ingestion.
5. Set `CURATED_AT` after a successful merge.
6. Query `CONTROL.PIPELINE_FRESHNESS`.
7. Require p95 freshness of at most 180 seconds for Tier-1 tables.

# Fast troubleshooting reference

| Message or symptom | Meaning | Correction |
|---|---|---|
| `AMN_DEV."raw" does not exist or not authorized` | ADF passed a quoted lowercase schema | Use uppercase `RAW` in dataset defaults and activity overrides |
| `AMN_DEV.RAW.HOSPITALS does not exist or not authorized` | Table is missing or the ADF role lacks access | Run `SHOW TABLES`, then grant database/schema/table access to `AMN_INGEST_ROLE` |
| Preview shows columns and `No data available` | Connection and schema access work; table is empty | Continue to the Copy pipeline |
| `Mapping source is empty` for metadata columns | CSV has no matching metadata fields | Delete those mapping rows for the first load |
| `Parameter name can't be empty` | A dataset has an accidental blank parameter row | Delete the blank row |
| `Parameter "" value can't be empty` | A required dataset parameter has no default/activity value | Supply all source and sink values |
| Direct copy only supports Azure Blob/S3 | ADLS Gen2 Managed Identity source is not eligible for direct Snowflake copy | Enable staging and select `LS_BLOB_STAGE_SAS` |
| Remote name cannot resolve a password-like value | Blob linked service is using the Snowflake password secret | Select `blob-stage-sas-uri` |
| Snowflake temporary-stage privilege error | ADF role cannot create the connector stage | Grant `CREATE STAGE` on `AMN_DEV.RAW` |
| Debug succeeds but rerun doubles the count | Snapshot was appended twice | Follow Step 23; truncate only in development or use staged MERGE |

# Final verification checklist

- [ ] Correct Azure subscription and tenant confirmed.
- [ ] Resource group created.
- [ ] ADLS Gen2 hierarchical namespace enabled.
- [ ] Four private containers created.
- [ ] Five existing CSVs uploaded without regeneration.
- [ ] ADF created with managed identity.
- [ ] ADF has Blob Data Contributor on storage.
- [ ] Key Vault uses Azure RBAC.
- [ ] ADF has Key Vault Secrets User.
- [ ] Diagnostics flow to Log Analytics.
- [ ] Snowflake database, schemas, warehouses, and roles created.
- [ ] Snowflake control tables created.
- [ ] Dedicated ADF Snowflake user created securely.
- [ ] Key Vault contains separate `snowflake-adf-password` and `blob-stage-sas-uri` secrets.
- [ ] ADLS, Blob staging, Key Vault, and Snowflake V2 linked services test successfully.
- [ ] All five RAW tables exist with columns matching the repository CSV headers.
- [ ] `AMN_INGEST_ROLE` can select/insert RAW tables and create temporary stages.
- [ ] Both parameterized datasets have defaults and contain no blank parameter rows.
- [ ] Snowflake dataset preview resolves uppercase `RAW.HOSPITALS`.
- [ ] Hospitals Copy activity has eight explicit business-column mappings.
- [ ] Blob staging is enabled for `COPY_HOSPITALS_TO_RAW`.
- [ ] First hospitals load succeeds and `RAW.HOSPITALS` contains 5,432 rows.
- [ ] Hospitals MERGE produces unique CURATED rows.
- [ ] All five snapshot pipelines reconcile successfully.
- [ ] ADF changes are validated and published.
- [ ] No 1-3 minute SLA claim is made until timestamped incremental changes exist.

# Official references

- [Create an ADLS Gen2 storage account](https://learn.microsoft.com/en-us/azure/storage/blobs/create-data-lake-storage-account)
- [Azure Data Factory managed identity](https://learn.microsoft.com/en-us/azure/data-factory/data-factory-service-identity)
- [Azure Key Vault RBAC guidance](https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide)
- [Azure Data Factory Snowflake V2 connector](https://learn.microsoft.com/en-us/azure/data-factory/connector-snowflake)
- [Snowflake Snowsight Workspaces](https://docs.snowflake.com/en/user-guide/ui-snowsight/workspaces)
- [Snowflake Database Explorer](https://docs.snowflake.com/en/user-guide/ui-snowsight-data)

