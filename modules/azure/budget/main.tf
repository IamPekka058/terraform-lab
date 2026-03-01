resource "azurerm_consumption_budget_resource_group" "budget" {
  name              = var.budget_name
  resource_group_id = var.resource_group_id

  amount     = var.budget_amount
  time_grain = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  dynamic "notification" {
    for_each = var.thresholds
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThan"
      contact_emails = [var.alert_email]
    }
  }

  lifecycle {
    ignore_changes = [
      time_period
    ]
  }
}