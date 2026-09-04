locals {
  incremental_pipeline_names = [
    "PL_INCREMENTAL_OPERATIONAL_INGEST",
    "PL_INCREMENTAL_STAFFING_REQUESTS",
    "PL_INCREMENTAL_CANDIDATES",
    "PL_INCREMENTAL_SCHEDULES",
    "PL_INCREMENTAL_PAYROLL",
  ]

  incremental_pipeline_names_kql = join(", ", [
    for name in local.incremental_pipeline_names : format("%q", name)
  ])
}

resource "azurerm_monitor_action_group" "data_operations" {
  name                = "ag-${local.name_prefix}-data-operations"
  resource_group_name = azurerm_resource_group.this.name
  short_name          = "amn-dataops"
  tags                = local.tags

  dynamic "email_receiver" {
    for_each = var.monitor_alert_email == null ? [] : [var.monitor_alert_email]

    content {
      name                    = "AMN data operations"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  # Logic App webhook – receives Monitor alerts and forwards email via Gmail
  # callback_url is populated after the Gmail connector is authorized in Portal
  logic_app_receiver {
    name                    = "AMN Pipeline Notifier"
    resource_id             = azurerm_logic_app_workflow.pipeline_notifier.id
    callback_url            = "https://placeholder-replace-after-portal-setup"
    use_common_alert_schema = true
  }
}

resource "azurerm_log_analytics_saved_search" "incremental_pipeline_health" {
  name                       = "AMN-Incremental-Pipeline-Health"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  category                   = "AMN Data Platform"
  display_name               = "AMN incremental pipeline health"
  query                      = <<-KQL
    AzureDiagnostics
    | where ResourceProvider == "MICROSOFT.DATAFACTORY"
    | where Category == "PipelineRuns"
    | where PipelineName_s in (${local.incremental_pipeline_names_kql})
    | summarize Runs=count(), Failures=countif(tolower(Status_s) == "failed"), AverageDurationSeconds=avg(Duration_d / 1000.0) by PipelineName_s, bin(TimeGenerated, 15m)
    | order by TimeGenerated desc
  KQL
}

resource "azurerm_log_analytics_saved_search" "incremental_trigger_health" {
  name                       = "AMN-Incremental-Trigger-Health"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  category                   = "AMN Data Platform"
  display_name               = "AMN incremental trigger health"
  query                      = <<-KQL
    AzureDiagnostics
    | where ResourceProvider == "MICROSOFT.DATAFACTORY"
    | where Category == "TriggerRuns"
    | where TriggerName_s == "TR_INCREMENTAL_OPERATIONAL_5MIN"  # corrected: live resource uses _5MIN
    | project TimeGenerated, TriggerName_s, Status_s, RunId_g, Message
    | order by TimeGenerated desc
  KQL
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "incremental_pipeline_failure" {
  name                 = "alert-${local.name_prefix}-incremental-pipeline-failure"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  description          = "Alerts when an AMN incremental ADF pipeline run fails."
  enabled              = var.incremental_monitoring_alerts_enabled
  severity             = 1
  scopes               = [azurerm_log_analytics_workspace.this.id]
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  criteria {
    query                   = <<-KQL
      AzureDiagnostics
      | where ResourceProvider == "MICROSOFT.DATAFACTORY"
      | where Category == "PipelineRuns"
      | where PipelineName_s in (${local.incremental_pipeline_names_kql})
      | where tolower(Status_s) == "failed"
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.data_operations.id]
  }

  tags       = local.tags
  depends_on = [azurerm_monitor_diagnostic_setting.data_factory]
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "incremental_trigger_failure" {
  name                 = "alert-${local.name_prefix}-incremental-trigger-failure"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  description          = "Alerts when the two-minute AMN incremental ADF trigger fails."
  enabled              = var.incremental_monitoring_alerts_enabled
  severity             = 1
  scopes               = [azurerm_log_analytics_workspace.this.id]
  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"

  criteria {
    query                   = <<-KQL
      AzureDiagnostics
      | where ResourceProvider == "MICROSOFT.DATAFACTORY"
      | where Category == "TriggerRuns"
      | where TriggerName_s == "TR_INCREMENTAL_OPERATIONAL_5MIN"  # corrected: live resource uses _5MIN
      | where tolower(Status_s) == "failed"
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.data_operations.id]
  }

  tags       = local.tags
  depends_on = [azurerm_monitor_diagnostic_setting.data_factory]
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "incremental_pipeline_sla" {
  name                 = "alert-${local.name_prefix}-incremental-sla"
  resource_group_name  = azurerm_resource_group.this.name
  location             = azurerm_resource_group.this.location
  description          = "Alerts when the parent incremental pipeline exceeds the five-minute SLA."
  enabled              = var.incremental_monitoring_alerts_enabled
  severity             = 2
  scopes               = [azurerm_log_analytics_workspace.this.id]
  evaluation_frequency = "PT5M"
  window_duration      = "PT15M"

  criteria {
    query                   = <<-KQL
      AzureDiagnostics
      | where ResourceProvider == "MICROSOFT.DATAFACTORY"
      | where Category == "PipelineRuns"
      | where PipelineName_s == "PL_INCREMENTAL_OPERATIONAL_INGEST"
      | where Duration_d > 300000
    KQL
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.data_operations.id]
  }

  tags       = local.tags
  depends_on = [azurerm_monitor_diagnostic_setting.data_factory]
}
