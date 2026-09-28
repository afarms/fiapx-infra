mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "000000000000" }
  }
}

override_resource {
  target = aws_sqs_queue.processing
  values = { arn = "arn:aws:sqs:us-east-1:000000000000:fiapx-processing-work" }
}

override_resource {
  target = aws_sqs_queue.video_events
  values = {
    arn = "arn:aws:sqs:us-east-1:000000000000:fiapx-videos-events"
    id  = "https://sqs.us-east-1.amazonaws.com/000000000000/fiapx-videos-events"
  }
}

override_resource {
  target = aws_sqs_queue.video_events_dlq
  values = {
    arn = "arn:aws:sqs:us-east-1:000000000000:fiapx-videos-events-dlq"
    id  = "https://sqs.us-east-1.amazonaws.com/000000000000/fiapx-videos-events-dlq"
  }
}

variables {
  media_bucket_name = "fiapx-media-unit-test"
}

run "result_delivery_and_least_privilege" {
  command = apply

  assert {
    condition = (
      aws_sqs_queue.video_events.name == "fiapx-videos-events" &&
      aws_sqs_queue.video_events_dlq.name == "fiapx-videos-events-dlq" &&
      !aws_sqs_queue.video_events.fifo_queue && !aws_sqs_queue.video_events_dlq.fifo_queue &&
      aws_sqs_queue.video_events.sqs_managed_sse_enabled && aws_sqs_queue.video_events_dlq.sqs_managed_sse_enabled &&
      aws_sqs_queue.video_events.message_retention_seconds == 345600 &&
      aws_sqs_queue.video_events_dlq.message_retention_seconds == 1209600 &&
      aws_sqs_queue.video_events.visibility_timeout_seconds == 120 &&
      aws_sqs_queue.video_events.receive_wait_time_seconds == 20
    )
    error_message = "Results require encrypted Standard queues, 4/14-day retention and bounded visibility with long polling."
  }
  assert {
    condition = (
      jsondecode(aws_sqs_queue_redrive_policy.video_events.redrive_policy).deadLetterTargetArn == aws_sqs_queue.video_events_dlq.arn &&
      jsondecode(aws_sqs_queue_redrive_policy.video_events.redrive_policy).maxReceiveCount == 5 &&
      jsondecode(aws_sqs_queue_redrive_allow_policy.video_events_dlq.redrive_allow_policy).redrivePermission == "byQueue" &&
      jsondecode(aws_sqs_queue_redrive_allow_policy.video_events_dlq.redrive_allow_policy).sourceQueueArns == [aws_sqs_queue.video_events.arn]
    )
    error_message = "Result DLQ must be exclusive to the result queue with five transport receives."
  }
  assert {
    condition = alltrue([for key, queue in { work = aws_sqs_queue.video_events, dlq = aws_sqs_queue.video_events_dlq } :
      jsondecode(aws_sqs_queue_policy.video_events_tls[key].policy).Statement == [{
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sqs:*"
        Resource  = queue.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }]
    ])
    error_message = "Result queues must reject insecure transport and never grant public access."
  }
  assert {
    condition = jsondecode(aws_iam_role.processing_local.assume_role_policy).Statement == [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:aws:iam::000000000000:user/rafael-admin" }
    }]
    error_message = "Worker credentials must use the existing authorized local principal."
  }
  assert {
    condition = jsondecode(aws_iam_role_policy.processing_local.policy).Statement == [
      {
        Sid      = "ReadOriginals", Effect = "Allow", Action = ["s3:GetObject"],
        Resource = "arn:aws:s3:::fiapx-media-unit-test/originals/*"
      },
      {
        Sid      = "ResultObjects", Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
        Resource = "arn:aws:s3:::fiapx-media-unit-test/results/*"
      },
      {
        Sid       = "ListResults", Effect = "Allow", Action = "s3:ListBucket",
        Resource  = "arn:aws:s3:::fiapx-media-unit-test",
        Condition = { StringLike = { "s3:prefix" = "results/*" } }
      },
      {
        Sid      = "ConsumeProcessing", Effect = "Allow",
        Action   = ["sqs:ReceiveMessage", "sqs:ChangeMessageVisibility", "sqs:DeleteMessage"],
        Resource = aws_sqs_queue.processing.arn
      },
      {
        Sid      = "PublishResults", Effect = "Allow", Action = "sqs:SendMessage",
        Resource = aws_sqs_queue.video_events.arn
      }
    ]
    error_message = "Worker must not mutate originals, consume results/DLQs, publish work or access state/IAM."
  }
  assert {
    condition = jsondecode(aws_iam_role_policy.video_results_local.policy).Statement == [
      {
        Sid      = "ConsumeResults", Effect = "Allow",
        Action   = ["sqs:ReceiveMessage", "sqs:ChangeMessageVisibility", "sqs:DeleteMessage"],
        Resource = aws_sqs_queue.video_events.arn
      },
      {
        Sid      = "ReadResults", Effect = "Allow", Action = ["s3:GetObject"],
        Resource = "arn:aws:s3:::fiapx-media-unit-test/results/*"
      },
      {
        Sid      = "DeleteExpiredResults", Effect = "Allow", Action = ["s3:DeleteObject"],
        Resource = "arn:aws:s3:::fiapx-media-unit-test/results/*"
      }
    ]
    error_message = "Video may read/delete result keys only; no PutObject, version deletion, bucket listing, work/DLQ consumption or infrastructure access."
  }
}
