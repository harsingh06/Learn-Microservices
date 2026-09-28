variable "subscription_id" {
  description = "Azure subscription (az account show --query id -o tsv)."
  type        = string
}

# Set by the WebApp pipeline to the image it just built and pushed.
variable "image" {
  description = "Full image reference, e.g. <acr>/webapp:<git sha>."
  type        = string
}
