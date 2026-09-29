provider "databricks" {
  alias           = "account"
  host            = "https://accounts.azuredatabricks.net"
  account_id      = var.databricks_account_id
  auth_type       = "azure-cli"
  azure_tenant_id = var.azure_tenant_id
}

provider "databricks" {
  alias           = "workspace"
  host            = var.workspace_host
  auth_type       = "azure-cli"
  azure_tenant_id = var.azure_tenant_id
}
