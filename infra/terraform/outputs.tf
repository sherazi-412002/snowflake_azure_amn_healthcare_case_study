output "resource_group_name" {
  description = "Resource group containing the AMN data platform."
  value       = azurerm_resource_group.this.name
}

output "data_factory_name" {
  description = "Azure Data Factory name."
  value       = azurerm_data_factory.this.name
}

output "data_factory_principal_id" {
  description = "ADF system-assigned managed identity principal ID."
  value       = azurerm_data_factory.this.identity[0].principal_id
}

output "storage_account_name" {
  description = "ADLS Gen2 storage account name."
  value       = azurerm_storage_account.data_lake.name
}

output "storage_dfs_endpoint" {
  description = "ADLS Gen2 DFS endpoint."
  value       = azurerm_storage_account.data_lake.primary_dfs_endpoint
}

output "landing_container_name" {
  description = "Container for inbound source data."
  value       = azurerm_storage_container.data_lake["landing"].name
}

output "key_vault_name" {
  description = "Key Vault used for pipeline secrets."
  value       = azurerm_key_vault.this.name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID."
  value       = azurerm_log_analytics_workspace.this.id
}


output "checkpoint_container_name" {
  description = "Container used by the temporary Snowflake Blob staging SAS."
  value       = azurerm_storage_container.data_lake["checkpoint"].name
}

output "monitor_action_group_id" {
  description = "Action group used by AMN incremental pipeline and trigger alerts."
  value       = azurerm_monitor_action_group.data_operations.id
}

output "incremental_monitoring_saved_queries" {
  description = "Saved Log Analytics queries for incremental pipeline and trigger health."
  value = {
    pipeline_health = azurerm_log_analytics_saved_search.incremental_pipeline_health.display_name
    trigger_health  = azurerm_log_analytics_saved_search.incremental_trigger_health.display_name
  }
}
