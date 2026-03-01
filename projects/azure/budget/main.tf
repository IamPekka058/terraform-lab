terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.62.0"
    }
  }
  cloud {
    organization = "IamPekka058"

    workspaces {
      name = "terraform-lab"
    }
  }
}

resource "azurerm_resource_group" "lab-template-budget" {
  name     = "rg-terraform-lab-template-budget"
  location = "westeurope"
}

resource "azurerm_consumption_budget_resource_group" "lab-template-budget_budget" {
  name              = "budget-lab-template-budget"
  resource_group_id = azurerm_resource_group.lab-template-budget.id

  amount     = var.monthly_budget
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 50.0
    operator       = "GreaterThan"
    contact_emails = [var.alert_email_adress]
  }

  notification {
    enabled        = true
    threshold      = 90.0
    operator       = "GreaterThan"
    contact_emails = [var.alert_email_adress]
  }

  lifecycle {
    ignore_changes = [
      time_period
    ]
  }
}