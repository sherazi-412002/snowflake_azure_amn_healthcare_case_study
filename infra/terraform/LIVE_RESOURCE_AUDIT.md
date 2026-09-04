# Live resource audit: rg-amn-dev-data

Audit date: 2026-08-12

## Coverage

| Live resource/configuration | Terraform representation | Status |
|---|---|---|
| Resource group | `azurerm_resource_group.this` | Present |
| Storage account | `azurerm_storage_account.data_lake` | Present; settings drift noted below |
| Containers: landing, checkpoint, quarantine, archive, snowflake-stage | `azurerm_storage_container.data_lake` | Present |
| Azure Data Factory | `azurerm_data_factory.this` | Present; settings drift noted below |
| Key Vault | `azurerm_key_vault.this` | Present; settings drift noted below |
| Log Analytics workspace | `azurerm_log_analytics_workspace.this` | Present |
| ADF Storage Blob Data Contributor | `azurerm_role_assignment.adf_storage_blob_contributor` | Present |
| ADF Key Vault Secrets User | `azurerm_role_assignment.adf_key_vault_secrets_user` | Present |
| Operator Key Vault Secrets Officer | `azurerm_role_assignment.key_vault_secrets_officer` | Present when object ID is supplied |
| ADF diagnostic setting | `azurerm_monitor_diagnostic_setting.data_factory` | Present; category selection differs |
| Key Vault diagnostic setting | `azurerm_monitor_diagnostic_setting.key_vault` | Present |
| Storage diagnostic setting | `azurerm_monitor_diagnostic_setting.storage` | Terraform-only; no live setting found |
| Four ADF linked services | `azapi_resource.adf_linked_service_*` | Present |
| Two ADF datasets | `azapi_resource.adf_dataset_*` | Present |
| Hospitals ADF pipeline | `azapi_resource.adf_pipeline_copy_hospitals` | Present |
| Key Vault Snowflake-password secret | `azurerm_key_vault_secret.snowflake_password` | Optional sensitive input |
| Key Vault Blob-SAS-URI secret | `azurerm_key_vault_secret.blob_stage_sas_uri` | Optional sensitive input |
| ADF triggers, custom IRs, data flows | None exist live | No resources required |

## Drift requiring a decision before import/apply

| Setting | Live Azure | Current Terraform default/configuration |
|---|---|---|
| Region | Central India | `eastus2` default |
| Storage shared-key access | Enabled | Disabled in `main.tf` |
| Key Vault purge protection | Enabled | Disabled for dev |
| Key Vault soft-delete retention | 90 days | 7 days for dev |
| Storage diagnostic setting | None | Terraform creates one |
| ADF diagnostic categories | Selected categories | Terraform uses `allLogs` category group |
| Resource names | Fixed manual suffix `sss` | Terraform uses `random_string.suffix` |

Do not apply against the manually created environment until these differences are intentionally reconciled and the resources are imported. Some settings, including Key Vault retention/purge behavior and resource location/name, can force replacement or cannot be reduced safely.

Secret resources are optional because secret values enter Terraform state when Terraform manages them. Use a secured remote backend, state encryption, and restricted state access before supplying `TF_VAR_snowflake_password` or `TF_VAR_blob_stage_sas_uri`.
