output "catalog_name" {
  description = "Unity Catalog catalog created by this root."
  value       = databricks_catalog.this.name
}

output "schema_names" {
  description = "Schemas created inside the catalog, sorted."
  value       = sort([for schema in databricks_schema.layer : schema.name])
}

output "fully_qualified_schema_names" {
  description = "Sorted catalog.schema names for use in later pipeline configuration."
  value       = sort([for schema in databricks_schema.layer : "${schema.catalog_name}.${schema.name}"])
}

output "storage_credential_name" {
  description = "Unity Catalog storage credential backed by the Azure access connector."
  value       = databricks_storage_credential.unity_catalog.name
}

output "external_location_url" {
  description = "Governed ADLS Gen2 location used by this lab."
  value       = databricks_external_location.unity_catalog.url
}

output "catalog_storage_location" {
  description = "Effective managed storage location for the dev catalog."
  value       = databricks_catalog.this.storage_location
}
