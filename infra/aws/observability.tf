resource "aws_cloudwatch_log_group" "containers" {
  name              = "/${var.project_name}/${var.environment}/containers"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/${var.project_name}/${var.environment}/api-gateway"
  retention_in_days = 7
}

resource "aws_cloudwatch_metric_alarm" "instance_status" {
  alarm_name          = "${var.project_name}-${var.environment}-instance-status"
  alarm_description   = "EC2 system or instance health check failed"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = aws_instance.platform.id
  }
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project_name}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = true
    include_refund = true
  }

  dynamic "notification" {
    for_each = var.budget_alert_email == null ? [] : [50, 80]

    content {
      comparison_operator        = "GREATER_THAN"
      notification_type          = "ACTUAL"
      subscriber_email_addresses = [var.budget_alert_email]
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
    }
  }

  dynamic "notification" {
    for_each = var.budget_alert_email == null ? [] : [100]

    content {
      comparison_operator        = "GREATER_THAN"
      notification_type          = "FORECASTED"
      subscriber_email_addresses = [var.budget_alert_email]
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
    }
  }
}
