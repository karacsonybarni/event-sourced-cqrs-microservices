locals {
  gateway_origin_refresh_script = <<-SCRIPT
    #!/usr/bin/env bash
    set -Eeuo pipefail

    region="${var.aws_region}"
    api_id="${aws_apigatewayv2_api.platform.id}"
    integration_id="${aws_apigatewayv2_integration.platform.id}"

    for attempt in $(seq 1 30); do
      token="$(curl --fail --silent --show-error \
        --request PUT \
        --header 'X-aws-ec2-metadata-token-ttl-seconds: 300' \
        http://169.254.169.254/latest/api/token 2>/dev/null || true)"
      public_dns=""
      if [[ -n "$${token}" ]]; then
        public_dns="$(curl --fail --silent --show-error \
          --header "X-aws-ec2-metadata-token: $${token}" \
          http://169.254.169.254/latest/meta-data/public-hostname 2>/dev/null || true)"
      fi

      if [[ -n "$${public_dns}" ]] && aws apigatewayv2 update-integration \
        --region "$${region}" \
        --api-id "$${api_id}" \
        --integration-id "$${integration_id}" \
        --integration-uri "http://$${public_dns}:8080" \
        >/dev/null; then
        echo "API Gateway origin refreshed to $${public_dns}:8080"
        exit 0
      fi

      echo "API Gateway origin refresh attempt $${attempt} failed; retrying" >&2
      sleep 10
    done

    echo "API Gateway origin could not be refreshed after $${attempt} attempts" >&2
    exit 1
  SCRIPT

  gateway_origin_refresh_unit = <<-UNIT
    [Unit]
    Description=Refresh API Gateway origin after EC2 address changes
    After=network-online.target
    Wants=network-online.target
    Before=event-sourced-cqrs.service
    StartLimitIntervalSec=0

    [Service]
    Type=oneshot
    ExecStart=/usr/local/bin/refresh-event-sourced-cqrs-origin
    RemainAfterExit=yes
    Restart=on-failure
    RestartSec=15
    TimeoutStartSec=330

    [Install]
    WantedBy=multi-user.target
  UNIT
}

resource "aws_ssm_association" "gateway_origin_refresh" {
  name             = "AWS-RunShellScript"
  association_name = "${var.project_name}-${var.environment}-refresh-api-origin"

  parameters = {
    commands = join("\n", [
      "printf '%s' '${base64encode(local.gateway_origin_refresh_script)}' | base64 --decode > /usr/local/bin/refresh-event-sourced-cqrs-origin",
      "chmod 0755 /usr/local/bin/refresh-event-sourced-cqrs-origin",
      "printf '%s' '${base64encode(local.gateway_origin_refresh_unit)}' | base64 --decode > /etc/systemd/system/event-sourced-cqrs-origin-refresh.service",
      "chmod 0644 /etc/systemd/system/event-sourced-cqrs-origin-refresh.service",
      "systemctl daemon-reload",
      "systemctl enable event-sourced-cqrs-origin-refresh.service",
      "systemctl restart event-sourced-cqrs-origin-refresh.service",
    ])
    executionTimeout = "420"
  }

  targets {
    key    = "InstanceIds"
    values = [aws_instance.platform.id]
  }

  max_concurrency                  = "1"
  max_errors                       = "0"
  wait_for_success_timeout_seconds = 480

  depends_on = [
    aws_iam_role_policy.instance_gateway_origin,
    aws_iam_role_policy_attachment.instance_ssm,
  ]
}
