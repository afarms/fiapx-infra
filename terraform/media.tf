terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.14.1"
    }
  }
}

variable "media_bucket_name" {
  description = "Globally unique media bucket name, supplied by GitHub configuration."
  type        = string
  validation {
    condition     = can(regex("^fiapx-media-[a-z0-9][a-z0-9-]{0,48}[a-z0-9]$", var.media_bucket_name))
    error_message = "Use fiapx-media- followed by 2 to 50 lowercase letters, digits or hyphens; end with a letter or digit."
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Project = "fiapx", ManagedBy = "terraform" }
  }
}

resource "aws_s3_bucket" "media" {
  bucket        = var.media_bucket_name
  force_destroy = false
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration {
    status = "Suspended"
  }
}

resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = ["arn:aws:s3:::${var.media_bucket_name}", "arn:aws:s3:::${var.media_bucket_name}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.media]
}

output "media_bucket_name" {
  value = aws_s3_bucket.media.id
}
