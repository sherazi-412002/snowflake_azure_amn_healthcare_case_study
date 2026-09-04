locals {
  normalized_project = lower(replace(var.project_name, "-", ""))
  name_prefix        = "${var.project_name}-${var.environment}"
  resource_group     = coalesce(var.resource_group_name, "rg-${local.name_prefix}-data")

  tags = merge(
    {
      application = "AMN data platform"
      environment = var.environment
      managed_by  = "terraform"
      project     = var.project_name
    },
    var.additional_tags
  )

  containers = toset([
    "landing",
    "checkpoint",
    "quarantine",
    "archive",
  ])

  source_files = {
    hospitals = {
      source = "${path.module}/../../datasets/cms/hospitals_reference.csv"
      target = "cms/hospitals/hospitals_reference.csv"
    }
    candidates = {
      source = "${path.module}/../../datasets/hr/candidates.csv"
      target = "hr/candidates/candidates.csv"
    }
    staffing_requests = {
      source = "${path.module}/../../datasets/hr/staffing_requests.csv"
      target = "hr/staffing_requests/staffing_requests.csv"
    }
    schedules = {
      source = "${path.module}/../../datasets/hr/schedules.csv"
      target = "hr/schedules/schedules.csv"
    }
    payroll = {
      source = "${path.module}/../../datasets/hr/payroll.csv"
      target = "hr/payroll/payroll.csv"
    }
  }
}
