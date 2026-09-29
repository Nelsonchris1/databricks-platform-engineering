locals {
  schema_grants = {
    engineers_bronze = {
      schema     = "bronze"
      principal  = "data-engineers"
      privileges = ["USE_SCHEMA", "CREATE_TABLE", "CREATE_VOLUME", "MODIFY", "SELECT"]
    }
    engineers_silver = {
      schema     = "silver"
      principal  = "data-engineers"
      privileges = ["USE_SCHEMA", "CREATE_TABLE", "CREATE_VOLUME", "MODIFY", "SELECT"]
    }
    engineers_gold = {
      schema     = "gold"
      principal  = "data-engineers"
      privileges = ["USE_SCHEMA", "CREATE_TABLE", "CREATE_VOLUME", "MODIFY", "SELECT"]
    }
    analysts_silver = {
      schema     = "silver"
      principal  = "data-analysts"
      privileges = ["USE_SCHEMA", "SELECT"]
    }
    analysts_gold = {
      schema     = "gold"
      principal  = "data-analysts"
      privileges = ["USE_SCHEMA", "SELECT"]
    }
  }
}

resource "databricks_grant" "catalog_use" {
  for_each = toset(["data-engineers", "data-analysts"])

  catalog    = databricks_catalog.this.name
  principal  = each.value
  privileges = ["USE_CATALOG"]
}

resource "databricks_grant" "schema" {
  for_each = local.schema_grants

  schema     = databricks_schema.layer[each.value.schema].id
  principal  = each.value.principal
  privileges = each.value.privileges
}
