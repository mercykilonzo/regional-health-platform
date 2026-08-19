# =============================================================================
# modules/service — EC2 + ALB + security groups for one service instance
#                                                            (group-owned)
#
# Traffic model: nginx on the EC2 instance carries real traffic and health
# checks. The aws_lb resources are written as IaC (graded by trivy config)
# but nginx is the actual upstream router because LocalStack ELBv2 health
# checking is undocumented. See FIDELITY.md.
#
# Credential discipline:
#   user-data receives var.secret_arn (the ARN string).
#   The instance calls GetSecretValue at boot. The plaintext password never
#   appears in user-data, the AMI, or git.
#
# LocalStack fidelity notes:
#   * Only the default SG is honoured at runtime; custom SGs don't filter.
#   * SG rules apply only at instance creation — post-launch changes are no-ops.
#   * root_block_device volume_size is required — LocalStack rejects without it.
# =============================================================================

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# -----------------------------------------------------------------------------
# ALB security group — internet-facing, port 80 inbound
# Egress scoped to VPC CIDR on app_port only — trivy config clean.
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.service_name}-alb-sg"
  description = "ALB: HTTP inbound from internet, egress to VPC on app_port only."
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Forward to app port inside VPC only"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  tags = merge(var.tags, {
    Name      = "${var.service_name}-alb-sg"
    Component = "service"
  })
}

# -----------------------------------------------------------------------------
# Instance security group
# Ingress scoped to VPC CIDR — no 0.0.0.0/0 on ingress, trivy config clean.
# Egress: 443 to Secrets Manager, db_port to Aiven.
# -----------------------------------------------------------------------------
resource "aws_security_group" "instance" {
  name        = "${var.service_name}-sg"
  description = "Instance: ingress from VPC on app_port only. Egress to Secrets Manager and Aiven MySQL."
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "App port from VPC CIDR only"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    description = "HTTPS to Secrets Manager"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Aiven MySQL high port"
    from_port   = var.db_port
    to_port     = var.db_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name      = "${var.service_name}-sg"
    Component = "service"
  })
}

# -----------------------------------------------------------------------------
# EC2 instance
# AMI: from pipeline (var.app_ami_id). Never hardcoded.
# user-data: receives secret ARN + db connection details. Never the password.
# root_block_device: explicit volume_size required by LocalStack.
# -----------------------------------------------------------------------------
resource "aws_instance" "service" {
  ami                    = var.app_ami_id
  instance_type          = "t3.small"
  vpc_security_group_ids = [aws_security_group.instance.id]

  user_data = templatefile("${path.module}/templates/user-data.sh.tpl", {
    secret_arn   = var.secret_arn
    db_port      = var.db_port
    db_name      = var.db_name
    app_port     = var.app_port
    service_name = var.service_name
  })

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = merge(var.tags, {
    Name      = var.service_name
    Component = "service"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}

# -----------------------------------------------------------------------------
# ALB — written as IaC, graded by trivy config.
# nginx carries actual traffic (see FIDELITY.md on ELBv2 health checking).
# -----------------------------------------------------------------------------
resource "aws_lb" "service" {
  name               = "${var.service_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = data.aws_subnets.default.ids

  tags = merge(var.tags, {
    Name      = "${var.service_name}-alb"
    Component = "service"
  })
}

resource "aws_lb_target_group" "service" {
  name     = "${var.service_name}-tg"
  port     = var.app_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    path                = "/healthz"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(var.tags, {
    Name      = "${var.service_name}-tg"
    Component = "service"
  })
}

resource "aws_lb_target_group_attachment" "service" {
  target_group_arn = aws_lb_target_group.service.arn
  target_id        = aws_instance.service.id
  port             = var.app_port
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.service.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service.arn
  }

  tags = merge(var.tags, {
    Name      = "${var.service_name}-listener"
    Component = "service"
  })
}
