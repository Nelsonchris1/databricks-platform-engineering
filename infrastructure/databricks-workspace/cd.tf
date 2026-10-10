variable "deployment_application_id" {
  description = "Disposable CD principal application UUID from the account root; empty disables CD grants."
  type        = string
  default     = ""

  validation {
    condition     = var.deployment_application_id == "" || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.deployment_application_id))
    error_message = "Provide a service principal application UUID or an empty string."
  }
}

resource "databricks_grant" "cd_catalog" {
  count      = var.deployment_application_id == "" ? 0 : 1
  catalog    = databricks_catalog.this.name
  principal  = var.deployment_application_id
  privileges = ["USE_CATALOG"]
}

resource "databricks_grant" "cd_schema" {
  for_each   = var.deployment_application_id == "" ? toset([]) : var.schema_names
  schema     = databricks_schema.layer[each.key].id
  principal  = var.deployment_application_id
  privileges = ["USE_SCHEMA", "CREATE_TABLE", "SELECT", "MODIFY"]
}

resource "databricks_directory" "cd" {
  count = var.deployment_application_id == "" ? 0 : 1
  path  = "/Shared/.bundle/dbx-interview-lab/dev-ci"
}

resource "databricks_permissions" "cd_directory" {
  count          = var.deployment_application_id == "" ? 0 : 1
  directory_path = databricks_directory.cd[0].path
  access_control {
    service_principal_name = var.deployment_application_id
    permission_level       = "CAN_MANAGE"
  }
}
