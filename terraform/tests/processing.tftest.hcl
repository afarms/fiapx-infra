mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "000000000000" }
  }
}

override_resource {
  target = aws_sqs_queue.processing
  values = {
    arn = "arn:aws:sqs:us-east-1:000000000000:fiapx-processing-work"
    id  = "https://sqs.us-east-1.amazonaws.com/000000000000/fiapx-processing-work"
  }
}

override_resource {
  target = aws_sqs_queue.processing_dlq
  values = {
    arn = "arn:aws:sqs:us-east-1:000000000000:fiapx-processing-work-dlq"
    id  = "https://sqs.us-east-1.amazonaws.com/000000000000/fiapx-processing-work-dlq"
  }
}

variables {
  media_bucket_name = "fiapx-media-unit-test"
}

run "processing_and_producer_access" {
  command = apply

  assert {
    condition = (
      !aws_sqs_queue.processing.fifo_queue && !aws_sqs_queue.processing_dlq.fifo_queue &&
      aws_sqs_queue.processing.sqs_managed_sse_enabled && aws_sqs_queue.processing_dlq.sqs_managed_sse_enabled &&
      aws_sqs_queue.processing.message_retention_seconds == 345600 &&
      aws_sqs_queue.processing_dlq.message_retention_seconds == 1209600 &&
      aws_sqs_queue.processing.visibility_timeout_seconds == 120 &&
      aws_sqs_queue.processing.receive_wait_time_seconds == 20
    )
    error_message = "Use encrypted Standard queues, 4/14-day retention, 120-second visibility and long polling."
  }
  assert {
    condition = (
      jsondecode(aws_sqs_queue_redrive_policy.processing.redrive_policy).deadLetterTargetArn == aws_sqs_queue.processing_dlq.arn &&
      jsondecode(aws_sqs_queue_redrive_policy.processing.redrive_policy).maxReceiveCount == 5 &&
      jsondecode(aws_sqs_queue_redrive_allow_policy.processing_dlq.redrive_allow_policy).redrivePermission == "byQueue" &&
      jsondecode(aws_sqs_queue_redrive_allow_policy.processing_dlq.redrive_allow_policy).sourceQueueArns == [aws_sqs_queue.processing.arn]
    )
    error_message = "Only the work queue may use this DLQ, after five receives."
  }
  assert {
    condition = alltrue([for key, queue in { work = aws_sqs_queue.processing, dlq = aws_sqs_queue.processing_dlq } :
      jsondecode(aws_sqs_queue_policy.tls[key].policy).Statement == [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = queue.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }]
    ])
    error_message = "Both queue policies must deny HTTP without granting public access."
  }
  assert {
    condition = jsondecode(aws_iam_role.video_local.assume_role_policy).Statement == [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:aws:iam::000000000000:user/rafael-admin" }
    }]
    error_message = "Only the explicitly authorized IAM user in this account may assume the local role."
  }
  assert {
    condition = jsondecode(aws_iam_role_policy.video_local.policy).Statement == [
      {
        Sid      = "OriginalObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::fiapx-media-unit-test/originals/*"
      },
      {
        Sid       = "ListOriginals"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::fiapx-media-unit-test"
        Condition = { StringLike = { "s3:prefix" = "originals/*" } }
      },
      {
        Sid      = "PublishProcessing"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.processing.arn
      }
    ]
    error_message = "Producer access must exclude results, state, IAM, DLQ and consumption actions."
  }
}
