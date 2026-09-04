######################################################################
# Logic App – ADF pipeline notification
# Sends email to syedshoaibsherazi412002@gmail.com on every
# pipeline SUCCESS or FAILURE via ADF Web Activity HTTP call.
######################################################################

resource "azurerm_logic_app_workflow" "pipeline_notifier" {
  name                = "logic-${local.name_prefix}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags

  # The workflow definition (HTTP trigger + Gmail action) is managed
  # outside Terraform via the Logic App Designer because the Gmail
  # connector requires an interactive OAuth consent flow.
  # Once authorized, the trigger URL is stored in Key Vault below.
}

# Store the Logic App HTTP trigger URL in Key Vault so ADF pipelines
# can reference it without hard-coding the URL in pipeline JSON.
resource "azurerm_key_vault_secret" "logic_app_notify_url" {
  name         = "logic-app-notify-url"
  # Placeholder value — replace via Portal after Gmail connector is authorized
  value        = "https://placeholder-replace-after-portal-setup"
  key_vault_id = azurerm_key_vault.this.id
  tags         = local.tags

  lifecycle {
    ignore_changes = [value]   # URL is updated manually after Portal auth
  }
}
