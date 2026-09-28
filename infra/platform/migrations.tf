# One-time migration: the container apps moved from this stack to their own
# service stacks (src/<Service>/infra, built on infra/modules/container-app-service).
# `removed` + destroy = false makes Terraform FORGET them — drop them from this
# state without touching Azure. Each service stack adopts its app with an
# `import` block. Neither side writes to Azure, so the order they run in doesn't
# matter.
#
# Delete this file after the first successful apply on main.

removed {
  from = azurerm_container_app.candidate
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_container_app.job
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_container_app.application
  lifecycle {
    destroy = false
  }
}

removed {
  from = azurerm_container_app.webapp
  lifecycle {
    destroy = false
  }
}
