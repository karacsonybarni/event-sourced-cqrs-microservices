resource "aws_apigatewayv2_api" "platform" {
  name          = "${var.project_name}-${var.environment}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "platform" {
  api_id                 = aws_apigatewayv2_api.platform.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "http://${aws_instance.platform.public_dns}:8080"
  payload_format_version = "1.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.platform.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.platform.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.platform.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      httpMethod       = "$context.httpMethod"
      integrationError = "$context.integrationErrorMessage"
      ip               = "$context.identity.sourceIp"
      latency          = "$context.responseLatency"
      path             = "$context.path"
      requestId        = "$context.requestId"
      responseLength   = "$context.responseLength"
      status           = "$context.status"
    })
  }

  default_route_settings {
    detailed_metrics_enabled = true
    throttling_burst_limit   = 20
    throttling_rate_limit    = 10
  }
}
