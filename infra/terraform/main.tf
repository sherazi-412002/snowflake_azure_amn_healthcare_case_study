resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = local.resource_group
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

resource "azurerm_storage_account" "data_lake" {
  name                              = "st${local.normalized_project}${var.environment}${random_string.suffix.result}"
  resource_group_name               = azurerm_resource_group.this.name
  location                          = azurerm_resource_group.this.location
  account_tier                      = "Standard"
  account_replication_type          = var.environment == "prod" ? "ZRS" : "LRS"
  account_kind                      = "StorageV2"
  is_hns_enabled                    = true
  min_tls_version                   = "TLS1_2"
  public_network_access_enabled     = var.storage_public_network_access_enabled
  shared_access_key_enabled         = var.storage_shared_access_key_enabled
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = var.environment == "prod"

  blob_properties {

    delete_retention_policy {
      days = var.environment == "prod" ? 30 : 7
    }

    container_delete_retention_policy {
      days = var.environment == "prod" ? 30 : 7
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "data_lake" {
  for_each = local.containers

  name                  = each.value
  storage_account_id    = azurerm_storage_account.data_lake.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "source_csv" {
  for_each = local.source_files

  name                   = each.value.target
  storage_account_name   = azurerm_storage_account.data_lake.name
  storage_container_name = azurerm_storage_container.data_lake["landing"].name
  type                   = "Block"
  source                 = each.value.source
  content_type           = "text/csv"
}
resource "azurerm_data_factory" "this" {
  name                            = "adf-${local.name_prefix}-${random_string.suffix.result}"
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  public_network_enabled          = var.data_factory_public_network_enabled
  managed_virtual_network_enabled = true

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-${local.name_prefix}-${random_string.suffix.result}"
  location                      = azurerm_resource_group.this.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = var.environment == "prod"
  soft_delete_retention_days    = var.environment == "prod" ? 90 : 7
  public_network_access_enabled = var.key_vault_public_network_access_enabled

  tags = local.tags
}

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "adf_storage_blob_contributor" {
  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "developer_storage_blob_contributor" {
  count = var.storage_blob_data_contributor_object_id == null ? 0 : 1

  scope                = azurerm_storage_account.data_lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.storage_blob_data_contributor_object_id
  principal_type       = "User"
}
resource "azurerm_role_assignment" "adf_key_vault_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_data_factory.this.identity[0].principal_id
}

resource "azurerm_monitor_diagnostic_setting" "data_factory" {
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_data_factory.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_key_vault.this.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage" {
  name                       = "send-to-log-analytics"
  target_resource_id         = azurerm_storage_account.data_lake.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_metric {
    category = "Transaction"
  }
}

