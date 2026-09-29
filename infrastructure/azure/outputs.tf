output "workspace_url" {
  description = "Workspace host for browser access and later Databricks provider configuration."
  value       = "https://${azurerm_databricks_workspace.lab.workspace_url}"
}

output "workspace_resource_id" {
  description = "Azure resource ID of the workspace."
  value       = azurerm_databricks_workspace.lab.id
}

output "resource_group_name" {
  description = "Lab resource group to inspect during cleanup."
  value       = azurerm_resource_group.lab.name
}

output "managed_resource_group_name" {
  description = "Databricks-managed resource group to inspect for retained resources after teardown."
  value       = azurerm_databricks_workspace.lab.managed_resource_group_name
}

output "workspace_id" {
  description = "Numeric Databricks workspace ID used for account-level workspace assignment."
  value       = azurerm_databricks_workspace.lab.workspace_id
}

output "unity_catalog_storage_root" {
  description = "ADLS Gen2 root used by the Unity Catalog metastore."
  value       = "abfss://${azurerm_storage_container.unity_catalog.name}@${azurerm_storage_account.unity_catalog.name}.dfs.core.windows.net/"
}

output "unity_catalog_access_connector_id" {
  description = "Azure resource ID of the access connector used by Unity Catalog."
  value       = azurerm_databricks_access_connector.unity_catalog.id
}
