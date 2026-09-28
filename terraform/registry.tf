locals {
  container_services = toset(["fiapx-identity-service", "fiapx-video-service", "fiapx-processing-service"])
}

resource "aws_ecr_repository" "service" {
  for_each             = local.container_services
  name                 = each.value
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false
  encryption_configuration {
    encryption_type = "AES256"
  }
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = { Name = each.value }
}
