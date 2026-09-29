terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.128.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}
