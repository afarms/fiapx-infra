locals {
  eks_name    = "fiapx"
  eks_version = "1.35"
  eks_addons = {
    pod_identity = "v1.3.10-eksbuild.3"
    vpc_cni      = "v1.22.4-eksbuild.3"
    coredns      = "v1.13.2-eksbuild.31"
    kube_proxy   = "v1.35.3-eksbuild.29"
  }
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.eks_name}/cluster"
  retention_in_days = 7
}

# No public rules. A future SSM administration SG will be an explicit source.
# EKS also creates its own cluster SG, attached to its managed nodes automatically.
resource "aws_security_group" "eks_api" {
  name        = "fiapx-eks-private-api"
  description = "Additional private administration access to EKS"
  vpc_id      = aws_vpc.application.id
  tags        = { Name = "fiapx-eks-private-api" }
}

resource "aws_eks_cluster" "application" {
  name                          = local.eks_name
  version                       = local.eks_version
  role_arn                      = aws_iam_role.eks_cluster.arn
  bootstrap_self_managed_addons = false
  deletion_protection           = true
  enabled_cluster_log_types     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = [for subnet in aws_subnet.private : subnet.id]
    security_group_ids      = [aws_security_group.eks_api.id]
    endpoint_private_access = true
    endpoint_public_access  = false
  }

  kubernetes_network_config {
    ip_family         = "ipv4"
    service_ipv4_cidr = "172.20.0.0/16"
  }

  upgrade_policy {
    support_type = "STANDARD"
  }

  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster, aws_cloudwatch_log_group.eks]
}

# DaemonSet add-ons are installed before compute; CoreDNS waits for compute below.
resource "aws_eks_addon" "pod_identity" {
  cluster_name                = aws_eks_cluster.application.name
  addon_name                  = "eks-pod-identity-agent"
  addon_version               = local.eks_addons.pod_identity
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.application.name
  addon_name                  = "vpc-cni"
  addon_version               = local.eks_addons.vpc_cni
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  pod_identity_association {
    role_arn        = aws_iam_role.eks_cni.arn
    service_account = "aws-node"
  }
  depends_on = [aws_eks_addon.pod_identity, aws_iam_role_policy_attachment.eks_cni]
}

resource "aws_launch_template" "eks_nodes" {
  name                   = "fiapx-eks-spot-nodes"
  update_default_version = true

  # AMI and instance types belong to the managed node group, not this template.
  # Omitting custom SGs lets EKS attach its cluster SG to the nodes.
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      volume_size           = 50
      encrypted             = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  dynamic "tag_specifications" {
    for_each = toset(["instance", "volume"])
    content {
      resource_type = tag_specifications.value
      tags          = { Name = "fiapx-eks-spot", Project = "fiapx", ManagedBy = "terraform" }
    }
  }
}

resource "aws_eks_node_group" "application" {
  cluster_name    = aws_eks_cluster.application.name
  node_group_name = "fiapx-spot"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = [for subnet in aws_subnet.private : subnet.id]
  capacity_type   = "SPOT"
  instance_types  = ["m6i.large", "m6a.large", "m5.large"]
  ami_type        = "AL2023_x86_64_STANDARD"
  version         = local.eks_version
  release_version = "1.35.8-20260923"

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = tostring(aws_launch_template.eks_nodes.latest_version)
  }

  scaling_config {
    min_size     = 2
    desired_size = 2
    max_size     = 2
  }

  update_config {
    max_unavailable = 1
  }

  node_repair_config {
    enabled = true
  }

  timeouts {
    create = "45m"
    update = "45m"
    delete = "45m"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_nodes,
    aws_eks_addon.vpc_cni,
    aws_route.private_default,
    aws_route_table_association.private
  ]
}

resource "aws_eks_addon" "runtime" {
  for_each = {
    coredns      = local.eks_addons.coredns
    "kube-proxy" = local.eks_addons.kube_proxy
  }
  cluster_name                = aws_eks_cluster.application.name
  addon_name                  = each.key
  addon_version               = each.value
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_node_group.application]
}

# Resource metrics for the applications' autoscaling/v2 HPAs.
resource "aws_eks_addon" "metrics_server" {
  cluster_name                = aws_eks_cluster.application.name
  addon_name                  = "metrics-server"
  addon_version               = "v0.9.0-eksbuild.11"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_node_group.application]
}
