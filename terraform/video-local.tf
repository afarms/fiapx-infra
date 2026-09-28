data "aws_caller_identity" "current" {}

resource "aws_iam_role" "video_local" {
  name                 = "fiapx-video-local"
  description          = "Temporary local credentials for the video upload producer"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/rafael-admin" }
    }]
  })
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "video_local" {
  name = "fiapx-video-producer"
  role = aws_iam_role.video_local.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "OriginalObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${var.media_bucket_name}/originals/*"
      },
      {
        Sid       = "ListOriginals"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::${var.media_bucket_name}"
        Condition = { StringLike = { "s3:prefix" = "originals/*" } }
      },
      {
        Sid      = "PublishProcessing"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.processing.arn
      }
    ]
  })
}
