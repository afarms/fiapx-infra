resource "aws_security_group" "administration" {
  name        = "fiapx-administration"
  description = "Private SSM administration, no inbound connections"
  vpc_id      = aws_vpc.application.id
  tags        = { Name = "fiapx-administration" }
}

# SSM, AWS APIs and bootstrap downloads use TLS through the existing NAT.
resource "aws_vpc_security_group_egress_rule" "administration_https" {
  security_group_id = aws_security_group.administration.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "SSM, AWS APIs and HTTPS bootstrap downloads"
}

resource "aws_vpc_security_group_ingress_rule" "eks_administration" {
  security_group_id            = aws_security_group.eks_api.id
  referenced_security_group_id = aws_security_group.administration.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Kubernetes API from the private SSM host"
}

resource "aws_cloudwatch_log_group" "administration" {
  name              = "/fiapx/administration/sessions"
  retention_in_days = 7
}

resource "aws_ssm_document" "administration_shell" {
  name            = "fiapx-administration-shell"
  document_type   = "Session"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "FIAP X administrative shell with CloudWatch session logging"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = ""
      s3KeyPrefix                 = ""
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = aws_cloudwatch_log_group.administration.name
      cloudWatchEncryptionEnabled = false
      cloudWatchStreamingEnabled  = true
      kmsKeyId                    = ""
      runAsEnabled                = false
      runAsDefaultUser            = ""
      idleSessionTimeout          = "20"
      maxSessionDuration          = "60"
      shellProfile                = { windows = "", linux = "cd /home/ssm-user" }
    }
  })
}

# aws_instance tags the instance/volume, but not the Spot request itself.
# Tag it at launch so cancellation can be authorized by ownership on replacement.
resource "aws_launch_template" "administration" {
  name = "fiapx-administration"
  tags = { Name = "fiapx-administration" }
  tag_specifications {
    resource_type = "spot-instances-request"
    tags          = { Name = "fiapx-administration", Project = "fiapx", ManagedBy = "terraform" }
  }
}

resource "aws_instance" "administration" {
  # AL2023 2023.12.20260918.0, verified AWS-owned x86_64 AMI in us-east-1.
  ami                         = "ami-0fef201115eefe936"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private["0"].id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.administration.id]
  iam_instance_profile        = aws_iam_instance_profile.administration.name
  user_data                   = file("${path.module}/bootstrap/administration.sh")
  user_data_replace_on_change = true
  tags                        = { Name = "fiapx-administration" }
  volume_tags                 = { Name = "fiapx-administration", Project = "fiapx", ManagedBy = "terraform" }

  launch_template {
    id      = aws_launch_template.administration.id
    version = tostring(aws_launch_template.administration.latest_version)
  }

  instance_market_options {
    market_type = "spot"
    spot_options {
      spot_instance_type             = "persistent"
      instance_interruption_behavior = "stop"
    }
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 12
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  credit_specification {
    cpu_credits = "standard"
  }

  depends_on = [
    aws_iam_role_policy_attachment.administration_ssm,
    aws_iam_role_policy.administration,
    aws_route.private_default,
    aws_route_table_association.private,
    aws_vpc_security_group_egress_rule.administration_https
  ]
}
