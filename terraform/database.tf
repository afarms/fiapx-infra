resource "aws_security_group" "database" {
  name        = "fiapx-postgres"
  description = "Private PostgreSQL from EKS and SSM administration only"
  vpc_id      = aws_vpc.application.id
  tags        = { Name = "fiapx-postgres" }
}

resource "aws_vpc_security_group_ingress_rule" "database" {
  for_each = {
    administration = aws_security_group.administration.id
    workloads      = aws_eks_cluster.application.vpc_config[0].cluster_security_group_id
  }
  security_group_id            = aws_security_group.database.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from ${each.key}"
}

resource "aws_vpc_security_group_egress_rule" "administration_database" {
  security_group_id            = aws_security_group.administration.id
  referenced_security_group_id = aws_security_group.database.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Private PostgreSQL administration"
}

resource "aws_db_subnet_group" "application" {
  name       = "fiapx-postgres"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]
}

resource "aws_db_parameter_group" "application" {
  name   = "fiapx-postgres17"
  family = "postgres17"
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
  parameter {
    name  = "password_encryption"
    value = "scram-sha-256"
  }
}

# The bootstrap creates the value once. Terraform owns only its metadata.
data "aws_secretsmanager_secret" "runtime_bootstrap" {
  name = "fiapx/runtime"
}

import {
  to = aws_secretsmanager_secret.runtime
  id = data.aws_secretsmanager_secret.runtime_bootstrap.arn
}

resource "aws_secretsmanager_secret" "runtime" {
  name                    = "fiapx/runtime"
  description             = "FIAP X database and application credentials"
  recovery_window_in_days = 7
  lifecycle {
    prevent_destroy = true
  }
}

# Ephemeral values and write-only arguments do not enter state or saved plans.
ephemeral "aws_secretsmanager_secret_version" "runtime" {
  secret_id = data.aws_secretsmanager_secret.runtime_bootstrap.arn
}

resource "aws_db_instance" "application" {
  identifier                   = "fiapx-postgres"
  engine                       = "postgres"
  engine_version               = "17.11"
  instance_class               = "db.t4g.small"
  allocated_storage            = 20
  storage_type                 = "gp3"
  storage_encrypted            = true
  multi_az                     = false
  publicly_accessible          = false
  db_subnet_group_name         = aws_db_subnet_group.application.name
  vpc_security_group_ids       = [aws_security_group.database.id]
  parameter_group_name         = aws_db_parameter_group.application.name
  username                     = "fiapx_admin"
  password_wo                  = jsondecode(ephemeral.aws_secretsmanager_secret_version.runtime.secret_string).database.master.password
  password_wo_version          = 1
  backup_retention_period      = 7
  backup_window                = "04:00-05:00"
  maintenance_window           = "sun:05:00-sun:06:00"
  auto_minor_version_upgrade   = false
  deletion_protection          = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "fiapx-postgres-final"
  copy_tags_to_snapshot        = true
  apply_immediately            = false
  performance_insights_enabled = false
  lifecycle {
    prevent_destroy = true
  }
}

output "database" {
  description = "Private connection metadata, without credentials."
  value = {
    identifier = aws_db_instance.application.identifier
    host       = aws_db_instance.application.address
    port       = aws_db_instance.application.port
    secret_arn = aws_secretsmanager_secret.runtime.arn
  }
}
