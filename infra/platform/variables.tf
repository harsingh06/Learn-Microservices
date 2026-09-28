variable "subscription_id" {
  description = "Azure subscription to deploy into (az account show --query id -o tsv)."
  type        = string
}

# Naming convention (see locals in main.tf):
#   <type>-<workload>-<environment>-<region>-<instance>   e.g. rg-ats-prod-cin-01
# Types that forbid hyphens (ACR, route config) use the same parts without them.

variable "workload" {
  description = "Workload short name, the second part of every resource name."
  type        = string
  default     = "ats"
}

variable "environment" {
  description = "Environment label in resource names and tags: dev, test or prod."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test or prod."
  }
}

variable "instance" {
  description = "Two-digit instance number; bump it (02) to stand up a second copy of the same environment side by side."
  type        = string
  default     = "01"

  validation {
    condition     = can(regex("^[0-9]{2}$", var.instance))
    error_message = "instance must be two digits, e.g. 01."
  }
}

variable "location" {
  description = "Azure region for all resources. Must have a short code in local.region_codes (main.tf)."
  type        = string
  default     = "centralindia"
}

variable "cosmos_database_throughput" {
  description = "Shared RU/s per Cosmos database (400 is the provisioned minimum)."
  type        = number
  default     = 400
}

# Empty string = no custom domain. Held by Front Door (frontdoor.tf), which serves
# the webapp AND the /api routes under it. Its managed certificate is issued once
# the _dnsauth TXT record exists — see DEPLOY.md, custom domain.
variable "custom_domain" {
  description = "Custom hostname for the site (e.g. ats.harsingh.com), or \"\" to skip."
  type        = string
  default     = ""
}
