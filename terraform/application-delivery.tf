locals {
  delivery = toset(["fiapx-identity-service", "fiapx-video-service", "fiapx-processing-service"])
  # GitHub immutable OIDC subjects include owner and repository IDs.
  delivery_repository_ids = {
    fiapx-identity-service   = "1390898475"
    fiapx-video-service      = "1382545566"
    fiapx-processing-service = "1392529435"
  }
}

resource "aws_iam_role" "application" {
  for_each = toset(["fiapx-video-service", "fiapx-processing-service"])
  name     = "${each.key}-pod"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Principal = { Service = "pods.eks.amazonaws.com" }
      Action = ["sts:AssumeRole", "sts:TagSession"]
      Condition = { StringEquals = {
        "aws:RequestTag/kubernetes-namespace"       = "fiapx"
        "aws:RequestTag/kubernetes-service-account" = each.key
        "aws:RequestTag/eks-cluster-arn"            = aws_eks_cluster.application.arn
      } }
    }]
  })
}

resource "aws_eks_pod_identity_association" "application" {
  for_each        = aws_iam_role.application
  cluster_name    = aws_eks_cluster.application.name
  namespace       = "fiapx"
  service_account = each.key
  role_arn        = each.value.arn
}

resource "aws_iam_role_policy" "video_pod" {
  role = aws_iam_role.application["fiapx-video-service"].id
  name = "fiapx-video-runtime"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = concat(jsondecode(aws_iam_role_policy.video_local.policy).Statement, jsondecode(aws_iam_role_policy.video_results_local.policy).Statement)
  })
}

resource "aws_iam_role_policy" "processing_pod" {
  role   = aws_iam_role.application["fiapx-processing-service"].id
  name   = "fiapx-processing-runtime"
  policy = aws_iam_role_policy.processing_local.policy
}

resource "aws_iam_role" "service_delivery" {
  for_each = local.delivery
  name     = "${each.key}-github-actions"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Condition = { StringEquals = {
        "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        "token.actions.githubusercontent.com:sub" = "repo:afarms@37558207/${each.key}@${local.delivery_repository_ids[each.key]}:ref:refs/heads/main"
      } }
    }]
  })
}

resource "aws_iam_role_policy" "service_delivery" {
  for_each = local.delivery
  name     = "publish-and-deploy"
  role     = aws_iam_role.service_delivery[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } } },
      { Effect = "Allow", Action = ["ecr:DescribeImages", "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage"], Resource = aws_ecr_repository.service[each.key].arn },
      { Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = aws_eks_cluster.application.arn },
      { Effect = "Allow", Action = ["ssm:StartSession"], Resource = aws_ssm_document.eks_tunnel.arn },
      { Effect = "Allow", Action = ["ssm:StartSession"], Resource = aws_instance.administration.arn, Condition = { BoolIfExists = { "ssm:SessionDocumentAccessCheck" = "true" } } },
      { Effect = "Allow", Action = ["ssm:TerminateSession"], Resource = "arn:aws:ssm:us-east-1:${data.aws_caller_identity.current.account_id}:session/*", Condition = { StringLike = { "ssm:resourceTag/aws:ssmmessages:session-id" = "$${aws:userid}*" } } },
      { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = aws_secretsmanager_secret.runtime.arn }
    ]
  })
}

output "application_delivery" {
  value = { for name, role in aws_iam_role.service_delivery : name => {
    role_arn             = role.arn, instance_id = aws_instance.administration.id
    db_host              = aws_db_instance.application.address, media_bucket_name = var.media_bucket_name
    processing_queue_url = aws_sqs_queue.processing.url, videos_events_queue_url = aws_sqs_queue.video_events.url
  } }
}

# Network transport only: kubectl executes on the GitHub-hosted runner.
resource "aws_ssm_document" "eks_tunnel" {
  name          = "fiapx-eks-tunnel"
  document_type = "Session"
  content = jsonencode({
    schemaVersion = "1.0"
    description   = "Port forwarding exclusively to the private FIAP X EKS API"
    sessionType   = "Port"
    properties = {
      type       = "LocalPortForwarding"
      host       = trimprefix(aws_eks_cluster.application.endpoint, "https://")
      portNumber = "443", localPortNumber = "18443"
    }
  })
}

resource "aws_eks_access_entry" "delivery" {
  for_each      = aws_iam_role.service_delivery
  cluster_name  = aws_eks_cluster.application.name
  principal_arn = each.value.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "delivery" {
  for_each      = aws_eks_access_entry.delivery
  cluster_name  = aws_eks_cluster.application.name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
  access_scope {
    type       = "namespace"
    namespaces = ["fiapx"]
  }
}
