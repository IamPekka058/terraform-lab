data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg-kuma" {
  name     = "rg-terraform-kuma"
  location = "germanywestcentral"
}

module "budget" {
  source = "../../../modules/azure/budget"

  budget_name       = "budget-kuma"
  resource_group_id = azurerm_resource_group.rg-kuma.id
  budget_amount     = var.monthly_budget
  alert_email       = var.alert_email
}

resource "azurerm_log_analytics_workspace" "kuma_logs" {
  name                = "log-uptime-kuma"
  location            = azurerm_resource_group.rg-kuma.location
  resource_group_name = azurerm_resource_group.rg-kuma.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "kuma_env" {
  name                       = "cae-uptime-kuma"
  location                   = azurerm_resource_group.rg-kuma.location
  resource_group_name        = azurerm_resource_group.rg-kuma.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.kuma_logs.id
}

resource "azuread_application" "kuma_auth" {
  display_name = "kuma-auth-app"
}

resource "azuread_service_principal" "kuma_auth_sp" {
  client_id = azuread_application.kuma_auth.client_id
}

resource "azuread_application_password" "kuma_auth_pwd" {
  application_id = azuread_application.kuma_auth.id
}

resource "azurerm_container_app" "kuma_app" {
  name                         = "ca-uptime-kuma"
  container_app_environment_id = azurerm_container_app_environment.kuma_env.id
  resource_group_name          = azurerm_resource_group.rg-kuma.name
  revision_mode                = "Single"

  secret {
    name  = "microsoft-client-secret"
    value = azuread_application_password.kuma_auth_pwd.value
  }

  template {
    container {
      name   = "uptime-kuma"
      image  = "louislam/uptime-kuma:latest"
      cpu    = 0.5
      memory = "1Gi"
    }
  }

  ingress {
    allow_insecure_connections = false
    external_enabled           = true
    target_port                = 3001

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }
}

resource "azapi_resource" "kuma_auth_config" {
  type      = "Microsoft.App/containerApps/authConfigs@2024-03-01"
  name      = "current"
  parent_id = azurerm_container_app.kuma_app.id

  body = jsonencode({
    properties = {
      platform = {
        enabled = true
      }
      globalValidation = {
        unauthenticatedClientAction = "RedirectToLoginPage"
        redirectToProvider          = "azureActiveDirectory"
        allowedExternalRedirectUrls = ["https://${azurerm_container_app.kuma_app.ingress[0].fqdn}/.auth/login/aad/callback"]

      }
      identityProviders = {
        azureActiveDirectory = {
          registration = {
            clientId                = azuread_application.kuma_auth.client_id
            clientSecretSettingName = "microsoft-client-secret"
            openIdIssuer            = "https://sts.windows.net/${data.azurerm_client_config.current.tenant_id}/v2.0"
          }
        }
      }
    }
  })
}

output "kuma_secure_url" {
  value = "https://${azurerm_container_app.kuma_app.latest_revision_fqdn}"
}