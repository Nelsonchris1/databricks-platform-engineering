locals {
  tags = {
    project     = "databricks-interview"
    environment = "lab"
    managed_by  = "terraform"
    lifecycle   = "disposable"
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_databricks_workspace" "lab" {
  name                        = "${var.name_prefix}-dbw"
  resource_group_name         = azurerm_resource_group.lab.name
  location                    = azurerm_resource_group.lab.location
  sku                         = var.workspace_sku
  managed_resource_group_name = "${var.name_prefix}-managed-rg"

  # Lab trade-off: public workspace access avoids a private network deployment.
  public_network_access_enabled = true
  tags                          = local.tags
}

# Customer-managed Unity Catalog storage. This lives in our resource group,
# rather than the Databricks-managed resource group, so its lifecycle and RBAC
# remain explicit in our Terraform configuration.
resource "azurerm_storage_account" "unity_catalog" {
  name                            = "dbxuc${substr(replace(var.subscription_id, "-", ""), 0, 8)}"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "unity_catalog" {
  name                  = "unity-catalog"
  storage_account_id    = azurerm_storage_account.unity_catalog.id
  container_access_type = "private"
}

resource "azurerm_databricks_access_connector" "unity_catalog" {
  name                = "${var.name_prefix}-uc-connector"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "unity_catalog_storage" {
  scope                = azurerm_storage_account.unity_catalog.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.unity_catalog.identity[0].principal_id
}
