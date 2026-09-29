locals {
  # Medallion-layer descriptions. A schema name outside this map still gets a
  # generic comment rather than failing the plan.
  schema_comments = {
    bronze = "Bronze layer: raw ingested data with minimal transformation."
    silver = "Silver layer: validated, cleaned and conformed data."
    gold   = "Gold layer: business-ready aggregates and reporting datasets."
  }

  default_schema_comment = "Managed by Terraform; medallion layer not documented."
}

resource "databricks_storage_credential" "unity_catalog" {
  name    = "dbx-interview-lab-managed-identity"
  comment = "Managed identity credential for the disposable interview lab."

  azure_managed_identity {
    access_connector_id = var.access_connector_id
  }
}

resource "databricks_external_location" "unity_catalog" {
  name            = "dbx-interview-lab-storage"
  url             = trimsuffix(var.storage_url, "/")
  credential_name = databricks_storage_credential.unity_catalog.id
  comment         = "Governed ADLS Gen2 container for the disposable interview lab."
  force_destroy   = true
}

resource "databricks_catalog" "this" {
  name         = var.catalog_name
  comment      = "Orders platform ${var.catalog_name} environment, managed by Terraform."
  storage_root = "${trimsuffix(databricks_external_location.unity_catalog.url, "/")}/managed/${var.catalog_name}"

  # Lab trade-off: force_destroy lets `terraform destroy` drop the catalog and
  # everything in it, because this lab holds only regenerable synthetic data.
  # Production should leave this unset so a destroy fails loudly instead of
  # silently deleting real tables.
  force_destroy = true

  properties = {
    environment = "dev"
    managed_by  = "terraform"
    purpose     = "orders-platform"
  }
}

resource "databricks_schema" "layer" {
  for_each = var.schema_names

  catalog_name = databricks_catalog.this.name
  name         = each.key
  comment      = lookup(local.schema_comments, each.key, local.default_schema_comment)

  # Same lab trade-off as the catalog: schemas are destroyed before their catalog,
  # so without this a teardown fails once these layers hold tables.
  force_destroy = true

  properties = {
    environment = "dev"
    layer       = each.key
    managed_by  = "terraform"
  }

  lifecycle {
    replace_triggered_by = [databricks_catalog.this]
  }
}
