locals {
  adf_definition_dir = "${path.module}/../adf"

  adf_template_values = {
    key_vault_uri                  = azurerm_key_vault.this.vault_uri
    data_lake_dfs_endpoint         = azurerm_storage_account.data_lake.primary_dfs_endpoint
    snowflake_account_identifier   = var.snowflake_account_identifier
    snowflake_host                 = var.snowflake_host
    snowflake_database             = var.snowflake_database
    snowflake_warehouse            = var.snowflake_warehouse
    snowflake_user                 = var.snowflake_user
    snowflake_password_secret_name = var.snowflake_password_secret_name
  }
}

resource "azapi_resource" "adf_linked_service_key_vault" {
  type      = "Microsoft.DataFactory/factories/linkedservices@2018-06-01"
  name      = "LS_KEY_VAULT"
  parent_id = azurerm_data_factory.this.id
  body = jsondecode(templatefile(
    "${local.adf_definition_dir}/linkedService.LS_KEY_VAULT.json",
    local.adf_template_values
  ))
  depends_on = [azurerm_role_assignment.adf_key_vault_secrets_user]
}

resource "azapi_resource" "adf_linked_service_adls" {
  type                      = "Microsoft.DataFactory/factories/linkedservices@2018-06-01"
  name                      = "LS_ADLS_GEN2"
  parent_id                 = azurerm_data_factory.this.id
  schema_validation_enabled = false
  body = jsondecode(templatefile(
    "${local.adf_definition_dir}/linkedService.LS_ADLS_GEN2.json",
    local.adf_template_values
  ))
  depends_on = [azurerm_role_assignment.adf_storage_blob_contributor]
}

resource "azapi_resource" "adf_linked_service_snowflake" {
  type      = "Microsoft.DataFactory/factories/linkedservices@2018-06-01"
  name      = "LS_SNOWFLAKE_V2"
  parent_id = azurerm_data_factory.this.id
  body = jsondecode(templatefile(
    "${local.adf_definition_dir}/linkedService.LS_SNOWFLAKE_V2.json",
    local.adf_template_values
  ))
  depends_on = [azapi_resource.adf_linked_service_key_vault]
}

resource "azapi_resource" "adf_linked_service_blob_stage" {
  type      = "Microsoft.DataFactory/factories/linkedservices@2018-06-01"
  name      = "LS_BLOB_STAGE_SAS"
  parent_id = azurerm_data_factory.this.id
  body = jsondecode(templatefile(
    "${local.adf_definition_dir}/linkedService.LS_BLOB_STAGE_SAS.json",
    { blob_stage_sas_secret_name = var.blob_stage_sas_secret_name }
  ))
  depends_on = [azapi_resource.adf_linked_service_key_vault]
}

resource "azapi_resource" "adf_dataset_adls_csv" {
  type       = "Microsoft.DataFactory/factories/datasets@2018-06-01"
  name       = "DS_ADLS_CSV"
  parent_id  = azurerm_data_factory.this.id
  body       = jsondecode(file("${local.adf_definition_dir}/dataset.DS_ADLS_CSV.json"))
  depends_on = [azapi_resource.adf_linked_service_adls]
}

resource "azapi_resource" "adf_dataset_snowflake_table" {
  type       = "Microsoft.DataFactory/factories/datasets@2018-06-01"
  name       = "DS_SNOWFLAKE_TABLE"
  parent_id  = azurerm_data_factory.this.id
  body       = jsondecode(file("${local.adf_definition_dir}/dataset.DS_SNOWFLAKE_TABLE.json"))
  depends_on = [azapi_resource.adf_linked_service_snowflake]
}

resource "azapi_resource" "adf_pipeline_copy_hospitals" {
  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  name      = "PL_COPY_HOSPITALS"
  parent_id = azurerm_data_factory.this.id
  body      = jsondecode(file("${local.adf_definition_dir}/pipeline.PL_COPY_HOSPITALS.json"))
  depends_on = [
    azapi_resource.adf_dataset_adls_csv,
    azapi_resource.adf_dataset_snowflake_table,
    azapi_resource.adf_linked_service_blob_stage
  ]
}
resource "azapi_resource" "adf_pipeline_copy_staffing_requests" {
  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  name      = "PL_COPY_STAFFING_REQUESTS"
  parent_id = azurerm_data_factory.this.id
  body      = jsondecode(file("${local.adf_definition_dir}/pipeline.PL_COPY_STAFFING_REQUESTS.json"))
  depends_on = [
    azapi_resource.adf_dataset_adls_csv,
    azapi_resource.adf_dataset_snowflake_table,
    azapi_resource.adf_linked_service_blob_stage
  ]
}

resource "azapi_resource" "adf_pipeline_copy_candidates" {
  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  name      = "PL_COPY_CANDIDATES"
  parent_id = azurerm_data_factory.this.id
  body      = jsondecode(file("${local.adf_definition_dir}/pipeline.PL_COPY_CANDIDATES.json"))
  depends_on = [
    azapi_resource.adf_dataset_adls_csv,
    azapi_resource.adf_dataset_snowflake_table,
    azapi_resource.adf_linked_service_blob_stage
  ]
}

resource "azapi_resource" "adf_pipeline_copy_schedules" {
  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  name      = "PL_COPY_SCHEDULES"
  parent_id = azurerm_data_factory.this.id
  body      = jsondecode(file("${local.adf_definition_dir}/pipeline.PL_COPY_SCHEDULES.json"))
  depends_on = [
    azapi_resource.adf_dataset_adls_csv,
    azapi_resource.adf_dataset_snowflake_table,
    azapi_resource.adf_linked_service_blob_stage
  ]
}

resource "azapi_resource" "adf_pipeline_copy_payroll" {
  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  name      = "PL_COPY_PAYROLL"
  parent_id = azurerm_data_factory.this.id
  body      = jsondecode(file("${local.adf_definition_dir}/pipeline.PL_COPY_PAYROLL.json"))
  depends_on = [
    azapi_resource.adf_dataset_adls_csv,
    azapi_resource.adf_dataset_snowflake_table,
    azapi_resource.adf_linked_service_blob_stage
  ]
}

resource "azapi_resource" "adf_pipeline_file_event_router" {
  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  name      = "PL_FILE_EVENT_ROUTER"
  parent_id = azurerm_data_factory.this.id
  body      = jsondecode(file("${local.adf_definition_dir}/pipeline.PL_FILE_EVENT_ROUTER.json"))
  depends_on = [
    azapi_resource.adf_pipeline_copy_hospitals,
    azapi_resource.adf_pipeline_copy_staffing_requests,
    azapi_resource.adf_pipeline_copy_candidates,
    azapi_resource.adf_pipeline_copy_schedules,
    azapi_resource.adf_pipeline_copy_payroll
  ]
}

resource "azapi_resource" "adf_dataset_snowflake_config" {
  type       = "Microsoft.DataFactory/factories/datasets@2018-06-01"
  name       = "DS_SNOWFLAKE_CONFIG"
  parent_id  = azurerm_data_factory.this.id
  body       = jsondecode(file("${local.adf_definition_dir}/dataset.DS_SNOWFLAKE_CONFIG.json"))
  depends_on = [azapi_resource.adf_linked_service_snowflake]
}

resource "azapi_resource" "adf_pipeline_metadata_ingest" {
  type      = "Microsoft.DataFactory/factories/pipelines@2018-06-01"
  name      = "PL_METADATA_INGEST"
  parent_id = azurerm_data_factory.this.id
  body      = jsondecode(file("${local.adf_definition_dir}/pipeline.PL_METADATA_INGEST.json"))
  depends_on = [
    azapi_resource.adf_dataset_snowflake_config,
    azapi_resource.adf_pipeline_copy_hospitals,
    azapi_resource.adf_pipeline_copy_staffing_requests,
    azapi_resource.adf_pipeline_copy_candidates,
    azapi_resource.adf_pipeline_copy_schedules,
    azapi_resource.adf_pipeline_copy_payroll
  ]
}
resource "azurerm_data_factory_trigger_blob_event" "metadata_ingest" {
  name                  = "TR_METADATA_INGEST_BATCH_READY"
  data_factory_id       = azurerm_data_factory.this.id
  storage_account_id    = azurerm_storage_account.data_lake.id
  events                = ["Microsoft.Storage.BlobCreated"]
  blob_path_begins_with = "/landing/blobs/control/"
  blob_path_ends_with   = "AMN_BATCH_READY.json"
  ignore_empty_blobs    = true
  activated             = var.metadata_ingest_trigger_activated
  description           = "Runs PL_METADATA_INGEST when a non-empty AMN batch-ready marker arrives in ADLS."

  annotations = ["AMN", "event-driven", "batch-ready", "terraform-managed"]

  pipeline {
    name = azapi_resource.adf_pipeline_metadata_ingest.name
  }

  depends_on = [azapi_resource.adf_pipeline_metadata_ingest]
}

resource "azurerm_data_factory_trigger_blob_event" "landing_csv_created" {
  name                  = "TR_LANDING_CSV_CREATED"
  data_factory_id       = azurerm_data_factory.this.id
  storage_account_id    = azurerm_storage_account.data_lake.id
  events                = ["Microsoft.Storage.BlobCreated"]
  blob_path_begins_with = "/landing/blobs/"
  blob_path_ends_with   = ".csv"
  ignore_empty_blobs    = true
  activated             = var.landing_csv_trigger_activated
  description           = "Routes a canonical landing CSV to only its matching AMN full-load ingestion pipeline."

  annotations = ["AMN", "event-driven", "file-router", "full-load-backfill", "terraform-managed"]

  pipeline {
    name = azapi_resource.adf_pipeline_file_event_router.name
    parameters = {
      folderPath = "@triggerBody().folderPath"
      fileName   = "@triggerBody().fileName"
    }
  }

  depends_on = [azapi_resource.adf_pipeline_file_event_router]
}
