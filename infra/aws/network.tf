data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "platform" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

resource "aws_internet_gateway" "platform" {
  vpc_id = aws_vpc.platform.id

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

# A public address is the deliberate origin for the cost-controlled HTTP API;
# private integration through a VPC Link and load balancer is the production path.
#trivy:ignore:AVD-AWS-0164
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.platform.id
  availability_zone       = data.aws_availability_zones.available.names[0]
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.platform.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.platform.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "platform" {
  name        = "${var.project_name}-${var.environment}"
  description = "Public application gateway only; administration uses Systems Manager"
  vpc_id      = aws_vpc.platform.id

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "gateway" {
  security_group_id = aws_security_group.platform.id
  description       = "API Gateway HTTP proxy to the Spring Cloud gateway"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 8080
  ip_protocol       = "tcp"
  to_port           = 8080
}

# The economical host must reach public package and image registries without a
# chargeable NAT gateway; traffic is restricted to TLS instead of all protocols.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.platform.id
  description       = "TLS access to package, image, GitHub, and AWS endpoints"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  ip_protocol       = "tcp"
  to_port           = 443
}
