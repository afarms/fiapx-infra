resource "aws_iam_role" "processing_local" {
  name                 = "fiapx-processing-local"
  description          = "Temporary local credentials for video processing"
  max_session_duration = 3600
  assume_role_policy   = aws_iam_role.video_local.assume_role_policy
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_iam_role_policy" "processing_local" {
  name = "fiapx-processing-worker"
  role = aws_iam_role.processing_local.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadOriginals"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.media_bucket_name}/originals/*"
      },
      {
        Sid      = "ResultObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${var.media_bucket_name}/results/*"
      },
      {
        Sid       = "ListResults"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::${var.media_bucket_name}"
        Condition = { StringLike = { "s3:prefix" = "results/*" } }
      },
      {
        Sid      = "ConsumeProcessing"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:ChangeMessageVisibility", "sqs:DeleteMessage"]
        Resource = aws_sqs_queue.processing.arn
      },
      {
        Sid      = "PublishResults"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.video_events.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "video_results_local" {
  name = "fiapx-video-results-consumer"
  role = aws_iam_role.video_local.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ConsumeResults"
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:ChangeMessageVisibility", "sqs:DeleteMessage"]
        Resource = aws_sqs_queue.video_events.arn
      },
      {
        Sid      = "ReadResults"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.media_bucket_name}/results/*"
      }
    ]
  })
}

output "processing_local_role_arn" {
  value     = aws_iam_role.processing_local.arn
  sensitive = true
}
