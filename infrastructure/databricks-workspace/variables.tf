variable "workspace_host" {
  description = "Workspace URL from the Azure root's workspace_url output; changes when the workspace is recreated."
  type        = string

  validation {
    condition     = startswith(var.workspace_host, "https://")
    error_message = "The workspace host must be a full https:// URL."
  }
}

variable "azure_tenant_id" {
  description = "Microsoft Entra tenant used for Azure CLI authentication to the workspace."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.azure_tenant_id))
    error_message = "Provide the Microsoft Entra tenant UUID."
  }
}

variable "access_connector_id" {
  description = "Azure resource ID of the Databricks access connector used by the storage credential."
  type        = string

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Databricks/accessConnectors/[^/]+$", var.access_connector_id))
    error_message = "Provide a complete Azure Databricks access connector resource ID."
  }
}

variable "storage_url" {
  description = "ADLS Gen2 container URL governed by the Unity Catalog external location."
  type        = string

  validation {
    condition     = can(regex("^abfss://[^@]+@[^/]+\\.dfs\\.core\\.windows\\.net/?$", var.storage_url))
    error_message = "Provide an abfss:// ADLS Gen2 container URL."
  }
}

variable "catalog_name" {
  description = "Unity Catalog catalog for this environment; one catalog per logical environment."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{1,62}$", var.catalog_name))
    error_message = "Use 2–63 lowercase letters, digits or underscores, starting with a letter."
  }
}

variable "schema_names" {
  description = "Medallion layers to create as schemas inside the catalog."
  type        = set(string)
  default     = ["bronze", "silver", "gold"]

  validation {
    condition     = length(var.schema_names) > 0
    error_message = "Provide at least one schema name."
  }

  validation {
    condition     = alltrue([for name in var.schema_names : can(regex("^[a-z][a-z0-9_]{1,62}$", name))])
    error_message = "Each schema name must be 2–63 lowercase letters, digits or underscores, starting with a letter."
  }
}
