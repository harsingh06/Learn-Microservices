# What a service may choose. Everything else — ingress visibility, identity,
# registry auth, workload profile, revision mode — is fixed by the module (main.tf).

variable "name" {
  description = "Container app name. Take it from the platform's app_names output, not a literal."
  type        = string
}

# The platform's container_app_platform output, passed through whole so a
# service can't wire itself to a different environment/registry/identity.
variable "platform" {
  description = "The platform stack's container_app_platform output."
  type = object({
    resource_group_name = string
    resource_group_id   = string
    environment_id      = string
    default_domain      = string
    registry_server     = string
    identity_id         = string
    tags                = map(string)
  })
}

variable "container_name" {
  description = "Name of the (single) container inside the app."
  type        = string
}

variable "image" {
  description = "Full image reference, e.g. <acr>/candidate-service:<git sha>. Set by the service pipeline."
  type        = string
}

variable "target_port" {
  description = "Port the container listens on."
  type        = number
}

# One map for plain AND secret-backed variables, applied in key order: set
# exactly one of `value` or `secret` (the name of an entry in var.secrets).
variable "env" {
  description = "Environment variables: name => { value } or { secret = <secret name> }."
  type = map(object({
    value  = optional(string)
    secret = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for e in values(var.env) : (e.value == null) != (e.secret == null)])
    error_message = "Each env entry needs exactly one of value or secret."
  }
}

variable "secrets" {
  description = "App secrets: secret name => value."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "min_replicas" {
  description = "Minimum replicas. 0 = scale to zero (cheap, cold starts)."
  type        = number
  default     = 0
}

variable "max_replicas" {
  description = "Maximum replicas."
  type        = number
  default     = 1
}

variable "cpu" {
  description = "vCPU per replica."
  type        = number
  default     = 0.25
}

variable "memory" {
  description = "Memory per replica; must pair with cpu (0.25 -> 0.5Gi)."
  type        = string
  default     = "0.5Gi"
}
