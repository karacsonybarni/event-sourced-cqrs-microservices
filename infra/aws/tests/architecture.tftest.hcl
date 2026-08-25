mock_provider "aws" {
  override_data {
    target = data.aws_availability_zones.available
    values = {
      names = ["eu-central-1a"]
    }
  }

  override_data {
    target = data.aws_ssm_parameter.al2023_ami
    values = {
      value = "ami-1234567890abcdef0"
    }
  }

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = data.aws_partition.current
    values = {
      partition = "aws"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.instance_assume_role
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.instance_logs
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  override_data {
    target          = data.aws_iam_policy_document.github_assume_role
    override_during = plan
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Federated\":\"arn:aws:iam::123456789012:oidc-provider/token.actions.githubusercontent.com\"},\"Action\":\"sts:AssumeRoleWithWebIdentity\",\"Condition\":{\"StringEquals\":{\"token.actions.githubusercontent.com:sub\":\"repo:karacsonybarni@14146083/event-sourced-cqrs-microservices@1343825530:environment:cloud\"}}}]}"
    }
  }

  override_data {
    target = data.aws_iam_policy_document.github_deploy
    values = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

}

run "cost_controlled_cloud_topology" {
  command = plan

  variables {
    github_repository_owner_id = "14146083"
    github_repository_id       = "1343825530"
  }

  assert {
    condition     = aws_instance.platform.instance_type == "m7i-flex.large"
    error_message = "The default instance must match the Free-plan-eligible measured eight-GiB runtime capacity."
  }

  assert {
    condition     = aws_instance.platform.metadata_options[0].http_tokens == "required"
    error_message = "The deployment host must require IMDSv2."
  }

  assert {
    condition     = aws_instance.platform.root_block_device[0].encrypted
    error_message = "The stateful deployment volume must be encrypted."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.gateway.from_port == 8080 && aws_vpc_security_group_ingress_rule.gateway.to_port == 8080
    error_message = "Only the application gateway port may be exposed by the instance security group."
  }

  assert {
    condition     = aws_apigatewayv2_stage.default.default_route_settings[0].throttling_rate_limit == 10
    error_message = "The public endpoint must have a cost-protective request throttle."
  }

  assert {
    condition     = local.github_oidc_subject == "repo:karacsonybarni@14146083/event-sourced-cqrs-microservices@1343825530:environment:cloud"
    error_message = "The deployment role must trust only the immutable repository identity and cloud environment."
  }
}
