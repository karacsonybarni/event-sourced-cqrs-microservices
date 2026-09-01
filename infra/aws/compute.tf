data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "platform" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.platform.id]
  iam_instance_profile        = aws_iam_instance_profile.platform.name
  associate_public_ip_address = true
  monitoring                  = false
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/templates/user-data.sh.tftpl", {
    aws_region               = var.aws_region
    buildx_sha256            = var.buildx_sha256
    buildx_version           = var.buildx_version
    compose_version          = var.compose_version
    container_log_group_name = aws_cloudwatch_log_group.containers.name
    repository_ref           = var.repository_ref
    repository_url           = var.repository_url
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 1
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    encrypted             = true
    delete_on_termination = true
    volume_size           = var.root_volume_size_gib
    volume_type           = "gp3"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }

  depends_on = [
    aws_cloudwatch_log_group.containers,
    aws_iam_role_policy.instance_logs,
    aws_iam_role_policy_attachment.instance_ssm,
    aws_route_table_association.public,
  ]
}

resource "aws_eip" "platform" {
  domain   = "vpc"
  instance = aws_instance.platform.id

  tags = {
    Name = "${var.project_name}-${var.environment}-origin"
  }

  depends_on = [aws_internet_gateway.platform]
}
