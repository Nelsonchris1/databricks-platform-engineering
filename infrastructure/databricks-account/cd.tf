variable "github_oidc_subject" {
  description = "Exact GitHub environment OIDC subject; empty disables the disposable CD identity."
  type        = string
  default     = ""
}

resource "databricks_service_principal" "cd" {
  provider                 = databricks.account
  count                    = var.github_oidc_subject == "" ? 0 : 1
  display_name             = "dbx-interview-lab-cd-dev"
  disable_as_user_deletion = false
}

resource "databricks_service_principal_federation_policy" "github" {
  provider             = databricks.account
  count                = var.github_oidc_subject == "" ? 0 : 1
  service_principal_id = databricks_service_principal.cd[0].id
  description          = "Disposable lab: GitHub dev environment only"
  oidc_policy = {
    issuer    = "https://token.actions.githubusercontent.com"
    audiences = [var.databricks_account_id]
    subject   = var.github_oidc_subject
  }
}

resource "databricks_permission_assignment" "cd" {
  provider     = databricks.workspace
  count        = var.github_oidc_subject == "" ? 0 : 1
  principal_id = databricks_service_principal.cd[0].id
  permissions  = ["USER"]
}

output "cd_application_id" {
  description = "GitHub dev environment's DATABRICKS_CLIENT_ID, or empty when CD is disabled."
  value       = try(databricks_service_principal.cd[0].application_id, "")
}
