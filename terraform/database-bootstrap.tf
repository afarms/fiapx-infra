resource "aws_iam_role_policy" "administration_database" {
  name = "fiapx-database-bootstrap"
  role = aws_iam_role.administration.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.runtime.arn
      },
      {
        Effect   = "Allow"
        Action   = ["rds:DescribeDBInstances"]
        Resource = aws_db_instance.application.arn
      }
    ]
  })
}

# Public code only. Secret values are fetched in memory by the instance role.
# A versioned document avoids replacing the Spot host when SQL setup changes.
resource "aws_ssm_document" "database_bootstrap" {
  name            = "fiapx-database-bootstrap"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Create and verify FIAP X logical databases without rotating credentials"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "bootstrap"
      inputs = {
        timeoutSeconds = "900"
        runCommand = concat([
          "#!/bin/bash",
          "set -euo pipefail",
          "umask 077",
          "dnf install -y python3 python3-pip >/dev/null",
          "install -d -m 700 /opt/fiapx-database",
          "python3 -m venv /opt/fiapx-database/venv"
          ], [for filename in ["requirements.txt", "bootstrap.py"] :
          "printf '%s' '${filebase64("${path.module}/../scripts/database/${filename}")}' | base64 --decode > /opt/fiapx-database/${filename}"
          ], [
          "/opt/fiapx-database/venv/bin/pip install --disable-pip-version-check --quiet -r /opt/fiapx-database/requirements.txt",
          "curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 https://truststore.pki.rds.amazonaws.com/us-east-1/us-east-1-bundle.pem -o /opt/fiapx-database/rds-ca.pem",
          "/opt/fiapx-database/venv/bin/python /opt/fiapx-database/bootstrap.py"
        ])
      }
    }]
  })
}

output "database_bootstrap" {
  value = {
    document = aws_ssm_document.database_bootstrap.name
    version  = aws_ssm_document.database_bootstrap.latest_version
    instance = aws_instance.administration.id
  }
}
