# AMN Platform Deployment

This runbook starts the implementation without regenerating the existing CSV data. All Azure infrastructure is provisioned through Terraform. Azure CLI is used only for authentication and the data-plane upload of existing files.

## What is implemented

The first infrastructure increment contains:

- Terraform-managed remote state storage
- Azure resource group
- ADLS Gen2 storage account
- Private `landing`, `checkpoint`, `quarantine`, and `archive` containers
- Azure Data Factory with a system-assigned managed identity and managed virtual network
- Azure Key Vault using Azure RBAC
- Log Analytics
- ADF, Key Vault, and storage diagnostics
- ADF access to ADLS and Key Vault through RBAC
- Snowflake database, schemas, warehouses, functional roles, and control-plane SQL
- A safe script that uploads five existing CSVs without overwriting them

This increment does not yet deploy the ADF pipeline or Snowflake linked service. Those are the next implementation slice after both cloud foundations are available.

## 1. Authenticate and select the Azure subscription

```powershell
az login
az account list --output table
az account set --subscription "<subscription-id>"
az account show --query "{name:name,id:id,tenantId:tenantId}" --output table
```

Do not continue until the displayed subscription is the intended development subscription.

## 2. Bootstrap remote Terraform state

The bootstrap stack intentionally uses local state because it creates the remote state storage itself.

```powershell
Set-Location infra\bootstrap
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set the subscription ID. Then run:

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan -out bootstrap.tfplan
terraform apply bootstrap.tfplan
terraform output -raw backend_hcl
```

Copy the `backend_hcl` output into `infra/terraform/backend.hcl`. Do not commit the generated state or personal variable files.

Checkpoint: the Azure portal shows the state resource group, storage account, and private `tfstate` container.

## 3. Configure the development platform

Return to the repository root and prepare the main Terraform inputs:

```powershell
Set-Location ..\..
Copy-Item infra\terraform\terraform.tfvars.example infra\terraform\terraform.tfvars
```

Edit `infra/terraform/terraform.tfvars`:

- Set the correct subscription ID.
- Choose an approved Azure region.
- Replace placeholder tags.
- Keep public access enabled only for the initial development deployment.

Do not store passwords, Snowflake secrets, or storage keys in Terraform variables.

## 4. Initialize and review the main Terraform plan

```powershell
Set-Location infra\terraform
terraform init -reconfigure -backend-config=backend.hcl
terraform fmt -check -recursive
terraform validate
terraform plan -out amn-dev.tfplan
terraform show amn-dev.tfplan
```

Review the plan carefully. It should create the platform foundation; it should not delete or replace unrelated resources.

Apply only after review:

```powershell
terraform apply amn-dev.tfplan
terraform output
```

Applying changes creates billable Azure resources. The development defaults use low-cost SKUs, but storage, logs, ADF activity, and network traffic can still incur charges.

## 5. Grant the operator permission to upload data

Terraform grants ADF access automatically. Your signed-in operator also needs `Storage Blob Data Contributor` on the new data-lake storage account to upload through Azure CLI.

Get the output values:

```powershell
$resourceGroup = terraform output -raw resource_group_name
$storageAccount = terraform output -raw storage_account_name
$operatorObjectId = az ad signed-in-user show --query id --output tsv
$storageId = az storage account show --resource-group $resourceGroup --name $storageAccount --query id --output tsv
```

An Azure administrator should grant the operator role. For a learning subscription where you have authorization, this can later be added as a Terraform variable and role assignment. It is deliberately not granted to every Terraform operator by default.

## 6. Upload the already-generated data

Return to the repository root. Do not run the data generators.

```powershell
Set-Location ..\..
$storageAccount = terraform -chdir=infra\terraform output -raw storage_account_name
.\scripts\publish_existing_data.ps1 -StorageAccountName $storageAccount
```

The script uploads:

- CMS hospitals
- HR candidates
- HR staffing requests
- HR schedules
- HR payroll

It passes `--overwrite false`, so an existing blob is not silently replaced.

Verify the landing data:

```powershell
az storage blob list `
  --account-name $storageAccount `
  --container-name landing `
  --auth-mode login `
  --query "[].{name:name,size:properties.contentLength}" `
  --output table
```

## 7. Bootstrap Snowflake

Use Snowsight or SnowSQL with an authorized administrative role:

```text
sql/snowflake/001_bootstrap.sql
sql/snowflake/002_control_tables.sql
```

The first script creates development schemas, isolated warehouses, and functional roles. The second creates ingestion configuration, checkpoints, run logs, data-quality results, and an SLA freshness view.

Review all grants with your Snowflake administrator before production. Assign functional roles to named users/service users separately; the repository does not guess who should receive access.

## 8. Validate the deployment

Azure checks:

```powershell
terraform -chdir=infra\terraform output
az datafactory show `
  --factory-name (terraform -chdir=infra\terraform output -raw data_factory_name) `
  --resource-group (terraform -chdir=infra\terraform output -raw resource_group_name) `
  --output table
```

Snowflake checks:

```sql
SHOW SCHEMAS IN DATABASE AMN_DEV;
SHOW WAREHOUSES LIKE 'AMN_%';
SHOW TABLES IN SCHEMA AMN_DEV.CONTROL;
SELECT * FROM AMN_DEV.CONTROL.PIPELINE_FRESHNESS LIMIT 10;
```

## 9. Current security boundary

The development configuration permits public endpoints to support initial deployment from a local workstation. Authentication still uses Azure identities, storage shared keys are disabled, containers are private, Key Vault uses RBAC, and TLS 1.2 is required.

Before production, add:

- A hub/spoke or approved virtual network
- Private endpoints for ADLS, Key Vault, and ADF
- Private DNS zones and links
- Approved egress from ADF to Snowflake
- Defender and organization-specific Azure Policy assignments
- Customer-managed keys if policy requires them
- Zone/region recovery objectives and tested recovery procedures

## 10. Next implementation slice

After this foundation is deployed and validated:

1. Create the ADF ADLS linked service using managed identity.
2. Create the Snowflake linked service with its secret in Key Vault.
3. Add parameterized datasets.
4. Add the metadata-driven lookup/ForEach/copy pipeline.
5. Create raw Snowflake tables from the verified CSV contracts.
6. Execute the first five-table snapshot load.
7. Add reconciliation and audit logging.
8. Add simulated incremental files because the existing CSVs have no update watermark.

Do not claim the 1-3 minute SLA during the snapshot phase. SLA validation begins when change timestamps are present and incremental ingestion is running.

