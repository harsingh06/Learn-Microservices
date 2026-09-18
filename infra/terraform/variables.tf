variable "subscription_id" {
  description = "Azure subscription to deploy into (az account show --query id -o tsv)."
  type        = string
}

variable "prefix" {
  description = "Short name prefix for all resources."
  type        = string
  default     = "ats"
}

variable "location" {
  description = "Azure region for all resources."
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
# records exist at the registrar — Azure validates ownership at creation time.
variable "webapp_custom_domain" {
  description = "Custom hostname for the webapp (e.g. ats.harsingh.com), or \"\" to skip."
  type        = string
  default     = ""
}
