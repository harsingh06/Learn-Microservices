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

# Two-step deploy: infra first (false) so the app URLs and registry exist,
# then build/push images, then apply again with true to create the apps.
variable "deploy_apps" {
  description = "Create the container apps. Keep false until images are pushed to ACR."
  type        = bool
  default     = false
}

variable "image_tag" {
  description = "Tag of the service images in ACR that the container apps run."
  type        = string
  default     = "v1"
}

variable "cosmos_database_throughput" {
  description = "Shared RU/s per Cosmos database (400 is the provisioned minimum)."
  type        = number
  default     = 400
}

variable "min_replicas" {
  description = "Minimum replicas per container app. 0 = scale to zero (cheap, cold starts)."
  type        = number
  default     = 0
}

# Empty string = no custom domain. Set only AFTER the TXT (asuid.<sub>) and CNAME
# records exist at the registrar, and the managed certificate has been created —
# see DEPLOY.md, custom domain.
# Bound to the route config, so it serves the webapp AND the /api routes.
variable "webapp_custom_domain" {
  description = "Custom hostname for the site (e.g. ats.harsingh.com), or \"\" to skip."
  type        = string
  default     = ""
}
