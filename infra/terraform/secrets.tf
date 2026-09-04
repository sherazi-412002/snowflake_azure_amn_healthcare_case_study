resource "azurerm_role_assignment" "key_vault_secrets_officer" {
  count = var.key_vault_secrets_officer_object_id == null ? 0 : 1

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.key_vault_secrets_officer_object_id
}

resource "azurerm_key_vault_secret" "snowflake_password" {
  count = var.snowflake_password == null ? 0 : 1

  name         = var.snowflake_password_secret_name
  value        = var.snowflake_password
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
}

resource "azurerm_key_vault_secret" "blob_stage_sas_uri" {
  count = var.blob_stage_sas_uri == null ? 0 : 1

  name         = var.blob_stage_sas_secret_name
  value        = var.blob_stage_sas_uri
  key_vault_id = azurerm_key_vault.this.id

  depends_on = [azurerm_role_assignment.key_vault_secrets_officer]
}
