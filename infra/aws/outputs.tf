output "public_api_url" {
  description = "Stable HTTPS entry point managed by Amazon API Gateway."
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "instance_id" {
  description = "Systems Manager deployment target."
  value       = aws_instance.platform.id
}

output "deployment_role_arn" {
  description = "Least-privilege role assumed by the GitHub cloud environment."
  value       = aws_iam_role.github_deploy.arn
}

output "aws_account_id" {
  description = "Account guard used by the GitHub credentials action."
  value       = data.aws_caller_identity.current.account_id
}

output "container_log_group" {
  description = "CloudWatch log group receiving all Compose container streams."
  value       = aws_cloudwatch_log_group.containers.name
}

data "aws_caller_identity" "current" {}
