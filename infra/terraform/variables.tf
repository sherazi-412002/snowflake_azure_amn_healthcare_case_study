variable "subscription_id" {
  description = "Azure subscription ID used by the AzureRM provider."
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Short lowercase project identifier used in resource names."
  type        = string
  default     = "amn"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,9}$", var.project_name))
    error_message = "project_name must be 2-10 lowercase alphanumeric characters and start with a letter."
  }
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test, or prod."
  }
}

variable "location" {
  description = "Primary Azure region."
  type        = string
  default     = "eastus2"
}

variable "resource_group_name" {
  description = "Optional resource group name. A standard name is generated when null."
  type        = string
  default     = null
}

variable "data_factory_public_network_enabled" {
  description = "Allow ADF public network access. Keep true for the first development deployment; use managed private endpoints before production."
  type        = bool
  default     = true
}

variable "storage_shared_access_key_enabled" {
  description = "Enable storage account keys for the temporary development Blob SAS workflow documented in the console guide. Disable after replacing SAS staging with an approved identity-based integration."
  type        = bool
  default     = true
}
variable "storage_public_network_access_enabled" {
  description = "Allow storage public network access. Needed for the initial local upload unless private connectivity is configured."
  type        = bool
  default     = true
}

variable "key_vault_public_network_access_enabled" {
  description = "Allow Key Vault public network access during development. Disable after private endpoint/DNS implementation."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log Analytics retention in days."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730
    error_message = "log_retention_days must be between 30 and 730."
  }
}

variable "additional_tags" {
  description = "Additional tags applied to supported resources."
  type        = map(string)
  default     = {}
}

variable "snowflake_account_identifier" {
  description = "Snowflake organization-account identifier used by ADF."
  type        = string
}

variable "snowflake_host" {
  description = "Snowflake account hostname without an https:// prefix."
  type        = string
}

variable "snowflake_database" {
  description = "Default Snowflake database used by ADF."
  type        = string
  default     = "AMN_DEV"
}

variable "snowflake_warehouse" {
  description = "Default Snowflake ingestion warehouse used by ADF."
  type        = string
  default     = "AMN_INGEST_WH"
}

variable "snowflake_user" {
  description = "Dedicated Snowflake service user used by ADF."
  type        = string
  default     = "AMN_ADF_SVC"
}

variable "snowflake_password_secret_name" {
  description = "Name of the pre-existing Key Vault secret containing the Snowflake password."
  type        = string
  default     = "snowflake-adf-password"
}

variable "blob_stage_sas_secret_name" {
  description = "Name of the pre-existing Key Vault secret containing the complete Blob service SAS URI."
  type        = string
  default     = "blob-stage-sas-uri"
}

variable "snowflake_password" {
  description = "Optional Snowflake service-user password to create in Key Vault. Supply securely through TF_VAR_snowflake_password; never commit it."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "blob_stage_sas_uri" {
  description = "Optional complete Blob service SAS URI to create in Key Vault. Supply securely through TF_VAR_blob_stage_sas_uri; never commit it."
  type        = string
  sensitive   = true
  default     = null
  nullable    = true
}

variable "key_vault_secrets_officer_object_id" {
  description = "Optional Entra object ID of the human/group that manages development secrets."
  type        = string
  default     = null
  nullable    = true
}


variable "metadata_ingest_trigger_activated" {
  description = "Start the event-driven metadata-ingestion trigger. Keep false until the Event Grid subscription and marker-file test are verified."
  type        = bool
  default     = false
}

variable "landing_csv_trigger_activated" {
  description = "Start the broad landing CSV event trigger. Keep false until all five canonical file routes have been tested independently."
  type        = bool
  default     = false
}

variable "storage_blob_data_contributor_object_id" {
  description = "Optional Entra user or group object ID granted Storage Blob Data Contributor for development data access."
  type        = string
  default     = null
  nullable    = true
}

variable "monitor_alert_email" {
  description = "Optional email address that receives incremental pipeline, trigger, and SLA alerts."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.monitor_alert_email == null || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.monitor_alert_email))
    error_message = "monitor_alert_email must be null or a valid email address."
  }
}

variable "incremental_monitoring_alerts_enabled" {
  description = "Enable Azure Monitor alerts for incremental ADF pipeline failures, trigger failures, and the five-minute SLA. This does not start the ADF trigger."
  type        = bool
  default     = true
}

variable "notification_email" {
  description = "Email address that receives ADF pipeline notifications via Logic App (success and failure)."
  type        = string
  default     = "syedshoaibsherazi412002@gmail.com"

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.notification_email))
    error_message = "notification_email must be a valid email address."
  }
}
