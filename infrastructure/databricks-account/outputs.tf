output "metastore_id" {
  description = "Unity Catalog metastore ID assigned to the lab workspace."
  value       = var.metastore_id
}

output "workspace_id" {
  description = "Numeric workspace ID attached to the metastore."
  value       = databricks_metastore_assignment.workspace.workspace_id
}

output "lab_group_names" {
  description = "Account groups assigned to the lab workspace."
  value       = sort([for group in databricks_group.lab : group.display_name])
}
