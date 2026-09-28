resource "aws_sqs_queue" "processing" {
  name                       = "fiapx-processing-work"
  fifo_queue                 = false
  sqs_managed_sse_enabled    = true
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 120
  receive_wait_time_seconds  = 20
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_sqs_queue" "processing_dlq" {
  name                      = "fiapx-processing-work-dlq"
  fifo_queue                = false
  sqs_managed_sse_enabled   = true
  message_retention_seconds = 1209600
  receive_wait_time_seconds = 20
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_sqs_queue_redrive_policy" "processing" {
  queue_url = aws_sqs_queue.processing.id
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq.arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "processing_dlq" {
  queue_url = aws_sqs_queue.processing_dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.processing.arn]
  })
}

resource "aws_sqs_queue_policy" "tls" {
  for_each = {
    work = aws_sqs_queue.processing
    dlq  = aws_sqs_queue.processing_dlq
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

output "processing_queue_url" {
  value     = aws_sqs_queue.processing.url
  sensitive = true
}

output "processing_queue_arn" {
  value     = aws_sqs_queue.processing.arn
  sensitive = true
}

output "processing_dlq_url" {
  value     = aws_sqs_queue.processing_dlq.url
  sensitive = true
}
