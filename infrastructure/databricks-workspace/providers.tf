# Workspace-scoped provider: it talks to the workspace API, not the account API.
# No account_id here — account-level objects (metastore, assignment, data access)
# belong to infrastructure/databricks-account and are not managed by this root.
provider "databricks" {
  host            = var.workspace_host
  auth_type       = "azure-cli"
  azure_tenant_id = var.azure_tenant_id
}
