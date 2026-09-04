# Incremental ADF monitoring

Terraform configures the existing ADF diagnostic setting to send all pipeline and
trigger logs to the project Log Analytics workspace. `infra/terraform/monitoring.tf`
adds focused monitoring for:

- `PL_INCREMENTAL_OPERATIONAL_INGEST`
- `PL_INCREMENTAL_STAFFING_REQUESTS`
- `PL_INCREMENTAL_CANDIDATES`
- `PL_INCREMENTAL_SCHEDULES`
- `PL_INCREMENTAL_PAYROLL`
- `TR_INCREMENTAL_OPERATIONAL_2MIN`

## Alerts

Three scheduled-query alerts are evaluated every five minutes:

1. Any incremental pipeline failure (severity 1).
2. Incremental trigger failure (severity 1).
3. Parent pipeline duration greater than 300 seconds (severity 2).

Set the notification recipient in `terraform.tfvars` without committing a real
address to source control:

```hcl
monitor_alert_email                   = "data.operations@example.com"
incremental_monitoring_alerts_enabled = true
```

These settings enable Azure Monitor alert evaluation only. They do not start
`TR_INCREMENTAL_OPERATIONAL_2MIN` or execute an ADF pipeline.

## Verify in Azure Portal

1. Open the project Log Analytics workspace.
2. Select **Logs**.
3. Open **Queries** and select category **AMN Data Platform**.
4. Run **AMN incremental pipeline health**.
5. Run **AMN incremental trigger health**.
6. Open **Azure Monitor > Alerts > Alert rules** and confirm all three AMN rules
   are enabled.
7. Open **Azure Monitor > Alerts > Action groups** and confirm the configured
   email receiver.

Diagnostic records can take several minutes to appear after the first ADF run.

## Useful ad-hoc query

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.DATAFACTORY"
| where Category in ("PipelineRuns", "TriggerRuns")
| where PipelineName_s startswith "PL_INCREMENTAL_"
    or TriggerName_s == "TR_INCREMENTAL_OPERATIONAL_2MIN"
| project TimeGenerated, Category, PipelineName_s, TriggerName_s, Status_s,
          RunId_g, Duration_d, Message
| order by TimeGenerated desc
```
