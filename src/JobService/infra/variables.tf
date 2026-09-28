variable "subscription_id" {
  description = "Azure subscription (az account show --query id -o tsv)."
  type        = string
}

# Set by the JobService pipeline to the image it just built and pushed.
variable "image" {
  description = "Full image reference, e.g. <acr>/job-service:<git sha>."
  type        = string
}
