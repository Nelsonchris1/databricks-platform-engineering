terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.128.0"
    }
  }

  # Bootstrap only: state stays on this machine, outside the disposable workspace.
  # Migrate to a separately managed remote backend before introducing CI/CD.
  backend "local" {
    path = "terraform.tfstate"
  }
}
