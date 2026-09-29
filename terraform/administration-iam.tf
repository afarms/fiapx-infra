resource "aws_iam_role" "administration" {
  name = "fiapx-administration"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_instance_profile" "administration" {
  name = "fiapx-administration"
  role = aws_iam_role.administration.name
}

resource "aws_iam_role_policy_attachment" "administration_ssm" {
  role       = aws_iam_role.administration.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "administration" {
  name = "fiapx-administration-runtime"
  role = aws_iam_role.administration.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = aws_eks_cluster.application.arn
      },
      {
        Effect    = "Allow"
        Action    = ["logs:DescribeLogGroups"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } }
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.administration.arn}:*"
      }
    ]
  })
}

resource "aws_eks_access_entry" "administration_host" {
  cluster_name  = aws_eks_cluster.application.name
  principal_arn = aws_iam_role.administration.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "administration_host" {
  cluster_name  = aws_eks_cluster.application.name
  principal_arn = aws_eks_access_entry.administration_host.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
}
