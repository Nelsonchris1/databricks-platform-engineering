resource "databricks_metastore_assignment" "workspace" {
  provider = databricks.account

  workspace_id = var.workspace_id
  metastore_id = var.metastore_id
}
