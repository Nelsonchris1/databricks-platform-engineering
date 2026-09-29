locals {
  lab_group_names = toset([
    "data-engineers",
    "data-analysts",
  ])
}

data "databricks_user" "lab_admin" {
  provider  = databricks.account
  user_name = var.lab_admin_user_name
}

resource "databricks_group" "lab" {
  provider = databricks.account
  for_each = local.lab_group_names

  display_name = each.value
}

resource "databricks_group_member" "lab_admin" {
  provider = databricks.account
  for_each = databricks_group.lab

  group_id  = each.value.id
  member_id = data.databricks_user.lab_admin.id
}

resource "databricks_permission_assignment" "lab" {
  provider = databricks.workspace
  for_each = databricks_group.lab

  principal_id = each.value.id
  permissions  = ["USER"]
}
