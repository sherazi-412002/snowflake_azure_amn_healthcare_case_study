variable "subscription_id" {
  description = "Azure subscription ID used for the Terraform state resources."
  type        = string
  sensitive   = true
}

variable "location" {
  description = "Azure region for Terraform state resources."
  type        = string
  default     = "eastus2"
}

variable "project_name" {
  description = "Lowercase project identifier."
  type        = string
  default     = "amn"
}

