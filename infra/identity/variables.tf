variable "tenant_id" {
  description = "Entra tenant that holds the app registrations and users."
  type        = string
  default     = "bc007f10-f168-4358-87be-cc46d95c87ef"
}

# Where the browser app may be served from. Entra only redirects back to these
# after sign-in (SPA platform, auth-code flow with PKCE).
variable "spa_redirect_uris" {
  description = "Origins the web app is served from (must end with '/')."
  type        = list(string)
  default = [
    "http://localhost:5173/", # npm run dev
    "http://localhost:5100/", # docker compose
    "https://ats.harsingh.com/",
  ]
}

# Extra people to give a role, by Entra object ID (az ad user show --id <upn>
# --query id -o tsv). The two test users and you (as Recruiter) are added automatically.
variable "extra_recruiter_object_ids" {
  description = "Additional users who get the Recruiter role."
  type        = list(string)
  default     = []
}

variable "extra_hiring_manager_object_ids" {
  description = "Additional users who get the HiringManager role."
  type        = list(string)
  default     = []
}

variable "assign_current_user_as_recruiter" {
  description = "Give the signed-in admin (you) the Recruiter role, e.g. for az-CLI tokens in tests."
  type        = bool
  default     = true
}

# Principal (object) ID of ApplicationService's managed identity in Azure — the
# platform stack's `application_identity_principal_id` output. Empty until that
# identity exists; then re-apply with it to create the federated credential that
# lets ApplicationService do On-Behalf-Of in Azure without any secret.
variable "application_managed_identity_principal_id" {
  description = "Object ID of ApplicationService's user-assigned managed identity, or \"\"."
  type        = string
  default     = ""
}
