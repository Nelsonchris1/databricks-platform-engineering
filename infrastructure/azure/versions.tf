terraform {
  required_version = ">= 1.5.0, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Bootstrap only: keep state on this machine, outside disposable Azure resources.
  # Migrate to a separately managed remote backend before introducing CI/CD.
  backend "local" {
    path = "terraform.tfstate"
  }
}
