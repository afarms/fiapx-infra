mock_provider "aws" {}

variables {
  media_bucket_name = "fiapx-media-unit-test"
}

run "private_media" {
  command = plan
  assert {
    condition = (
      aws_s3_bucket_public_access_block.media.block_public_acls &&
      aws_s3_bucket_public_access_block.media.block_public_policy &&
      aws_s3_bucket_public_access_block.media.ignore_public_acls &&
      aws_s3_bucket_public_access_block.media.restrict_public_buckets
    )
    error_message = "Every public-access protection must be enabled."
  }
  assert {
    condition     = !aws_s3_bucket.media.force_destroy
    error_message = "Deleting a bucket must not delete its objects automatically."
  }
  assert {
    condition     = one(aws_s3_bucket_ownership_controls.media.rule).object_ownership == "BucketOwnerEnforced"
    error_message = "ACL-based access must be disabled."
  }
  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.media.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "Media requires SSE-S3 encryption."
  }
  assert {
    condition     = one(aws_s3_bucket_versioning.media.versioning_configuration).status == "Suspended"
    error_message = "Media versioning must remain disabled."
  }
  assert {
    condition     = jsondecode(aws_s3_bucket_policy.media.policy).Statement[0].Condition.Bool["aws:SecureTransport"] == "false" && jsondecode(aws_s3_bucket_policy.media.policy).Statement[0].Effect == "Deny"
    error_message = "HTTP access must be denied."
  }
}

run "reject_state_bucket" {
  command = plan
  variables {
    media_bucket_name = "fiap-fase-05"
  }
  expect_failures = [var.media_bucket_name]
}
