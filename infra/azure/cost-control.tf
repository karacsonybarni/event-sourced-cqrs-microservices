resource "azurerm_consumption_budget_resource_group" "runtime" {
  name              = "${local.name_prefix}-monthly"
  resource_group_id = azurerm_resource_group.runtime.id
  amount            = var.monthly_budget_usd
  time_grain        = "Monthly"

  time_period {
    start_date = "2026-08-01T00:00:00Z"
    end_date   = "2027-08-01T00:00:00Z"
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThanOrEqualTo"
    threshold_type = "Actual"
    contact_roles  = ["Owner"]
  }

  dynamic "notification" {
    for_each = var.budget_alert_email == null ? [] : [50, 100]
    content {
      enabled        = true
      threshold      = notification.value
      operator       = "GreaterThanOrEqualTo"
      threshold_type = "Actual"
      contact_emails = [var.budget_alert_email]
    }
  }
}
