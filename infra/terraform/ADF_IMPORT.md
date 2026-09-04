# Import the manually created ADF objects

Do not run `terraform apply` against `rg-amn-dev-data` until the existing Azure foundation and ADF child objects are imported into the same Terraform state. Otherwise Terraform may attempt to create parallel resources because the current module generates names with a random suffix.

These commands assume the current subscription, resource group, and factory:

```text
subscription:   da21d709-0bcb-4573-a89a-1d55384588eb
resource group: rg-amn-dev-data
factory:        adf-amn-dev-sss
```

After configuring the backend and variables, initialize Terraform:

```powershell
terraform init -backend-config=backend.hcl
```

First import or reconcile the foundation resources, especially `azurerm_resource_group.this`, `azurerm_storage_account.data_lake`, `azurerm_data_factory.this`, and `azurerm_key_vault.this`. The generated naming strategy must be reconciled before planning against this manually created environment.

Then import the published ADF children:

```powershell
$factoryId = "/subscriptions/da21d709-0bcb-4573-a89a-1d55384588eb/resourceGroups/rg-amn-dev-data/providers/Microsoft.DataFactory/factories/adf-amn-dev-sss"

terraform import azapi_resource.adf_linked_service_key_vault "$factoryId/linkedservices/LS_KEY_VAULT"
terraform import azapi_resource.adf_linked_service_adls "$factoryId/linkedservices/LS_ADLS_GEN2"
terraform import azapi_resource.adf_linked_service_snowflake "$factoryId/linkedservices/LS_SNOWFLAKE_V2"
terraform import azapi_resource.adf_linked_service_blob_stage "$factoryId/linkedservices/LS_BLOB_STAGE_SAS"

terraform import azapi_resource.adf_dataset_adls_csv "$factoryId/datasets/DS_ADLS_CSV"
terraform import azapi_resource.adf_dataset_snowflake_table "$factoryId/datasets/DS_SNOWFLAKE_TABLE"

terraform import azapi_resource.adf_pipeline_copy_hospitals "$factoryId/pipelines/PL_COPY_HOSPITALS"
terraform import azapi_resource.adf_pipeline_copy_staffing_requests "$factoryId/pipelines/PL_COPY_STAFFING_REQUESTS"
terraform import azapi_resource.adf_pipeline_copy_candidates "$factoryId/pipelines/PL_COPY_CANDIDATES"
terraform import azapi_resource.adf_pipeline_copy_schedules "$factoryId/pipelines/PL_COPY_SCHEDULES"
terraform import azapi_resource.adf_pipeline_copy_payroll "$factoryId/pipelines/PL_COPY_PAYROLL"

terraform import azapi_resource.adf_dataset_snowflake_config "$factoryId/datasets/DS_SNOWFLAKE_CONFIG"
terraform import azapi_resource.adf_pipeline_metadata_ingest "$factoryId/pipelines/PL_METADATA_INGEST"
```

Import the five existing landing files after importing the storage account and `landing` container. Replace `<storage-account>` with the live account name:

```powershell
terraform import 'azurerm_storage_blob.source_csv["hospitals"]' 'https://<storage-account>.blob.core.windows.net/landing/cms/hospitals/hospitals_reference.csv'
terraform import 'azurerm_storage_blob.source_csv["candidates"]' 'https://<storage-account>.blob.core.windows.net/landing/hr/candidates/candidates.csv'
terraform import 'azurerm_storage_blob.source_csv["staffing_requests"]' 'https://<storage-account>.blob.core.windows.net/landing/hr/staffing_requests/staffing_requests.csv'
terraform import 'azurerm_storage_blob.source_csv["schedules"]' 'https://<storage-account>.blob.core.windows.net/landing/hr/schedules/schedules.csv'
terraform import 'azurerm_storage_blob.source_csv["payroll"]' 'https://<storage-account>.blob.core.windows.net/landing/hr/payroll/payroll.csv'
```

`DS_SNOWFLAKE_CONFIG` and `PL_METADATA_INGEST` only exist after Step 28 is deployed. Do not run those two import commands when the live objects do not exist; allow Terraform to create them after running `sql/snowflake/008_metadata_ingestion_config.sql` in Snowsight.
If Terraform will manage the existing secret objects, supply their sensitive variables first and import their current versions:

```powershell
$env:TF_VAR_snowflake_password = '<retrieve securely>'
$env:TF_VAR_blob_stage_sas_uri = '<retrieve securely>'

terraform import 'azurerm_key_vault_secret.snowflake_password[0]' 'https://kv-amn-dev-sss.vault.azure.net/secrets/snowflake-adf-password'
terraform import 'azurerm_key_vault_secret.blob_stage_sas_uri[0]' 'https://kv-amn-dev-sss.vault.azure.net/secrets/blob-stage-sas-uri'
```

If Terraform will manage the operator assignment, set `key_vault_secrets_officer_object_id` and import the existing role-assignment resource ID returned by Azure. Do not create a second assignment for the same principal, role, and scope.

Run a refresh-only review before any apply:

```powershell
terraform plan -refresh-only
terraform plan
```

Review every proposed replacement carefully. In particular:

- Key Vault secrets must exist before linked-service connection tests can succeed.
- `snowflake-adf-password` contains the Snowflake password and is never stored in this repository.
- `blob-stage-sas-uri` contains a complete Blob service SAS URI and must be rotated before expiry.
- The live ADF Snowflake encrypted credential is intentionally not exported. Terraform deploys a Key Vault reference instead.
- Refresh ADF Studio after Terraform changes; an old browser draft can overwrite published objects.
