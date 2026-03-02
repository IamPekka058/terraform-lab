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

resource "random_string" "storage_suffix" {
  length  = 6
  special = false
  upper   = false
}


resource "azurerm_storage_account" "kuma_storage" {
  name                     = "stkuma${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg-kuma.name
  location                 = azurerm_resource_group.rg-kuma.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}


resource "azurerm_storage_share" "kuma_share" {
  name               = "kuma-data"
  storage_account_id = azurerm_storage_account.kuma_storage.id
  quota              = 1
}

resource "azurerm_container_app_environment_storage" "kuma_env_storage" {
  name                         = "kuma-storage-link"
  container_app_environment_id = azurerm_container_app_environment.kuma_env.id
  account_name                 = azurerm_storage_account.kuma_storage.name
  share_name                   = azurerm_storage_share.kuma_share.name
  access_key                   = azurerm_storage_account.kuma_storage.primary_access_key
  access_mode                  = "ReadWrite"
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

locals {
  container_fqdn = "ca-uptime-kuma.${azurerm_container_app_environment.kuma_env.default_domain}"
}

resource "azuread_application" "kuma_auth" {
  display_name = "kuma-auth-app"
  web {
    redirect_uris = [
      "https://${local.container_fqdn}/.auth/login/aad/callback"
    ]

    implicit_grant {
      id_token_issuance_enabled = true
    }
  }
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
    
    volume {
      name         = "kuma-volume"
      storage_name = azurerm_container_app_environment_storage.kuma_env_storage.name
      storage_type = "AzureFile"
    }

    container {
      name   = "uptime-kuma"
      image  = "louislam/uptime-kuma:latest"
      cpu    = 0.5
      memory = "1Gi"

      volume_mounts {
        name = "kuma-volume"
        path = "/app/data"
      }
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

  depends_on = [
    azurerm_container_app_environment_storage.kuma_env_storage
  ]
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
  depends_on = [
    azurerm_container_app.kuma_app,
    azuread_application_password.kuma_auth_pwd
  ]
}

output "kuma_secure_url" {
  value = "https://${local.container_fqdn}"
}