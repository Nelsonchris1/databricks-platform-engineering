variable "databricks_account_id" {
  description = "Azure Databricks account ID from the account console."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.databricks_account_id))
    error_message = "Provide the Azure Databricks account UUID."
  }
}

variable "azure_tenant_id" {
  description = "Microsoft Entra tenant containing the Azure Databricks account."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.azure_tenant_id))
    error_message = "Provide the Microsoft Entra tenant UUID."
  }
}

variable "workspace_id" {
  description = "Numeric Databricks workspace ID to attach to the metastore."
  type        = number
}

variable "workspace_host" {
  description = "Workspace URL used to assign account groups to the lab workspace."
  type        = string

  validation {
    condition     = startswith(var.workspace_host, "https://")
    error_message = "The workspace host must be a full https:// URL."
  }
}

variable "lab_admin_user_name" {
  description = "Account user added to the lab groups for hands-on testing."
  type        = string
}

variable "metastore_id" {
  description = "Existing regional Unity Catalog metastore assigned to the lab workspace."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.metastore_id))
    error_message = "Provide the existing Unity Catalog metastore UUID."
  }
}
