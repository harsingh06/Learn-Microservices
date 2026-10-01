# Two test users (one per role) and who gets which role on which app.
#
# Note: the tenant's security defaults will ask them to register MFA (Microsoft
# Authenticator) when they first sign in — expected.

data "azuread_domains" "initial" {
  only_initial = true # <tenant>.onmicrosoft.com
}

locals {
  test_users = {
    recruiter     = { display_name = "ATS Recruiter (test)", role = "Recruiter" }
    hiringmanager = { display_name = "ATS Hiring Manager (test)", role = "HiringManager" }
  }
}

resource "random_password" "test_user" {
  for_each = local.test_users

  length           = 20
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "!#%*-_=+"
}

resource "azuread_user" "test" {
  for_each = local.test_users

  user_principal_name   = "ats-${each.key}@${data.azuread_domains.initial.domains[0].domain_name}"
  display_name          = each.value.display_name
  mail_nickname         = "ats-${each.key}"
  password              = random_password.test_user[each.key].result
  force_password_change = false
}

locals {
  # Who holds which role. Keys are static so Terraform can plan the for_each
  # before the test users exist.
  role_members = concat(
    [for key, user in local.test_users : { key = "test-${key}", role = user.role, object_id = azuread_user.test[key].object_id }],
    var.assign_current_user_as_recruiter ? [{ key = "current-user", role = "Recruiter", object_id = data.azuread_client_config.current.object_id }] : [],
    [for id in var.extra_recruiter_object_ids : { key = "recruiter-${id}", role = "Recruiter", object_id = id }],
    [for id in var.extra_hiring_manager_object_ids : { key = "hiringmanager-${id}", role = "HiringManager", object_id = id }],
  )

  service_principal_object_ids = merge(
    { for key, sp in azuread_service_principal.api : key => sp.object_id },
    { web = azuread_service_principal.web.object_id },
  )

  # Every member gets their role on every app (3 APIs + web): each API reads the
  # roles assigned on itself, so they must match everywhere.
  role_assignments = {
    for pair in setproduct(local.role_apps, local.role_members) :
    "${pair[0]}-${pair[1].key}" => { app = pair[0], member = pair[1] }
  }
}

resource "azuread_app_role_assignment" "member" {
  for_each = local.role_assignments

  app_role_id         = random_uuid.role["${each.value.app}-${each.value.member.role}"].result
  principal_object_id = each.value.member.object_id
  resource_object_id  = local.service_principal_object_ids[each.value.app]
}
