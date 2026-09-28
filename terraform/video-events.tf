resource "aws_sqs_queue" "video_events" {
  name                       = "fiapx-videos-events"
  fifo_queue                 = false
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 120
  receive_wait_time_seconds  = 20
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_sqs_queue" "video_events_dlq" {
  name                      = "fiapx-videos-events-dlq"
  fifo_queue                = false
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
  receive_wait_time_seconds = 20
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_sqs_queue_redrive_policy" "video_events" {
  queue_url = aws_sqs_queue.video_events.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.video_events_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "video_events_dlq" {
  queue_url = aws_sqs_queue.video_events_dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.video_events.arn]
  })
}

resource "aws_sqs_queue_policy" "video_events_tls" {
  for_each = {
    work = aws_sqs_queue.video_events
    dlq  = aws_sqs_queue.video_events_dlq
  }
  queue_url = each.value.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sqs:*"
      Resource  = each.value.arn
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}

output "video_events_queue_url" {
  value     = aws_sqs_queue.video_events.url
  sensitive = true
}

output "video_events_queue_arn" {
  value     = aws_sqs_queue.video_events.arn
  sensitive = true
}

output "video_events_dlq_url" {
  value     = aws_sqs_queue.video_events_dlq.url
  sensitive = true
}
