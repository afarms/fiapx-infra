output "application_network" {
  description = "Network identifiers grouped by availability zone for future EKS/RDS deployment."
  value = {
    vpc_id = aws_vpc.application.id
    subnets = { for index, az in local.network_zones : az => {
      public_id  = aws_subnet.public[index].id
      private_id = aws_subnet.private[index].id
    } }
  }
}

output "container_registries" {
  description = "Private image registry URLs; publication credentials are not included."
  value       = { for name, repository in aws_ecr_repository.service : name => repository.repository_url }
  sensitive   = true
}

output "media_bucket_name" {
  description = "Private media bucket name."
  value       = aws_s3_bucket.media.id
}

output "eks_runtime" {
  description = "Private cluster connection metadata and node SG for later SSM/RDS configuration; contains no credentials."
  value = {
    cluster_name                     = aws_eks_cluster.application.name
    endpoint                         = aws_eks_cluster.application.endpoint
    certificate_authority            = aws_eks_cluster.application.certificate_authority[0].data
    cluster_security_group_id        = aws_eks_cluster.application.vpc_config[0].cluster_security_group_id
    administration_security_group_id = aws_security_group.eks_api.id
    node_group_name                  = aws_eks_node_group.application.node_group_name
  }
  sensitive = true
}

output "processing_dlq_url" {
  description = "Processing work dead-letter queue URL."
  value       = aws_sqs_queue.processing_dlq.url
  sensitive   = true
}

output "processing_local_role_arn" {
  description = "Temporary local worker role ARN; not an EKS workload role."
  value       = aws_iam_role.processing_local.arn
  sensitive   = true
}

output "processing_queue_arn" {
  description = "Processing work queue ARN."
  value       = aws_sqs_queue.processing.arn
  sensitive   = true
}

output "processing_queue_url" {
  description = "Processing work queue URL."
  value       = aws_sqs_queue.processing.url
  sensitive   = true
}

output "video_events_dlq_url" {
  description = "Video result dead-letter queue URL."
  value       = aws_sqs_queue.video_events_dlq.url
  sensitive   = true
}

output "video_events_queue_arn" {
  description = "Video result queue ARN."
  value       = aws_sqs_queue.video_events.arn
  sensitive   = true
}

output "video_events_queue_url" {
  description = "Video result queue URL."
  value       = aws_sqs_queue.video_events.url
  sensitive   = true
}

output "video_local_role_arn" {
  description = "Temporary local video service role ARN; not an EKS workload role."
  value       = aws_iam_role.video_local.arn
  sensitive   = true
}
