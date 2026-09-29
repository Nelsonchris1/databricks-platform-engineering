variable "subscription_id" {
  description = "Explicit Azure subscription to deploy into; authenticate locally with Azure CLI."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "Provide an Azure subscription UUID."
  }
}

variable "location" {
  description = "Azure region selected after availability, quota and price checks."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]+$", var.location))
    error_message = "Use an Azure region identifier such as uksouth, not a display name."
  }
}

variable "workspace_sku" {
  description = "Explicit tier choice: trial only if eligible; premium otherwise requires a budget review."
  type        = string

  validation {
    condition     = contains(["trial", "premium"], var.workspace_sku)
    error_message = "Select trial or premium for this governance lab."
  }
}

variable "name_prefix" {
  description = "Stable prefix for this disposable lab's Azure resources."
  type        = string
  default     = "dbx-interview-lab"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,29}$", var.name_prefix))
    error_message = "Use 3–30 lowercase letters, digits or hyphens, starting with a letter."
  }
}
