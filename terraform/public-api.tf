locals {
  public_apis = {
    identity = { port = 30081, paths = ["/auth/register", "/auth/login", "/users/me", "/users/me/credentials"] }
    video    = { port = 30082, paths = ["/videos", "/videos/*"] }
  }
  public_api_rules = {
    identity_api   = { service = "identity", priority = 10, paths = local.public_apis.identity.paths }
    identity_admin = { service = "identity", priority = 11, paths = ["/admin/users", "/admin/users/*"] }
    identity_docs  = { service = "identity", priority = 12, paths = ["/swagger-ui.html", "/swagger-ui/*", "/v3/api-docs", "/v3/api-docs/*"] }
    video_api      = { service = "video", priority = 20, paths = local.public_apis.video.paths }
    video_docs     = { service = "video", priority = 21, paths = ["/swagger-ui.html", "/swagger-ui/*", "/v3/api-docs", "/v3/api-docs/*"] }
  }
}

resource "aws_security_group" "public_api" {
  name        = "fiapx-private-alb"
  description = "Private ALB reached only through CloudFront VPC origin"
  vpc_id      = aws_vpc.application.id
  tags        = { Name = "fiapx-private-alb" }
}

resource "aws_vpc_security_group_egress_rule" "public_api_nodes" {
  for_each                     = local.public_apis
  security_group_id            = aws_security_group.public_api.id
  referenced_security_group_id = aws_eks_cluster.application.vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
}

resource "aws_vpc_security_group_ingress_rule" "public_api_nodes" {
  for_each                     = local.public_apis
  security_group_id            = aws_eks_cluster.application.vpc_config[0].cluster_security_group_id
  referenced_security_group_id = aws_security_group.public_api.id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = "Private ALB to application NodePort"
}

resource "aws_lb" "public_api" {
  name                       = "fiapx-private-api"
  internal                   = true
  load_balancer_type         = "application"
  subnets                    = [for subnet in aws_subnet.private : subnet.id]
  security_groups            = [aws_security_group.public_api.id]
  idle_timeout               = 120
  drop_invalid_header_fields = true
}

resource "aws_lb_target_group" "public_api" {
  for_each             = local.public_apis
  name                 = "fiapx-${each.key}-api"
  port                 = each.value.port
  protocol             = "HTTP"
  target_type          = "instance"
  vpc_id               = aws_vpc.application.id
  deregistration_delay = 120
  health_check {
    path                = "/actuator/health/readiness"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# ASG registers replacement Spot nodes; Kubernetes routes NodePort to Ready Pods.
# No controller and no static instance/IP registration list.
resource "aws_autoscaling_attachment" "public_api" {
  for_each               = local.public_apis
  autoscaling_group_name = aws_eks_node_group.application.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = aws_lb_target_group.public_api[each.key].arn
}

resource "aws_lb_listener" "public_api" {
  load_balancer_arn = aws_lb.public_api.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not found"
      status_code  = "404"
    }
  }
}

resource "aws_lb_listener_rule" "public_api" {
  for_each     = local.public_api_rules
  listener_arn = aws_lb_listener.public_api.arn
  priority     = each.value.priority
  condition {
    http_header {
      http_header_name = "X-Fiapx-Service"
      values           = [each.value.service]
    }
  }
  condition {
    path_pattern { values = each.value.paths }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.public_api[each.value.service].arn
  }
}

resource "aws_cloudfront_vpc_origin" "public_api" {
  vpc_origin_endpoint_config {
    name                   = "fiapx-private-api"
    arn                    = aws_lb.public_api.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
  depends_on = [aws_lb_listener.public_api, aws_internet_gateway.application]
}

# Created and owned by CloudFront, not by Terraform. Allow only that SG.
data "aws_security_group" "cloudfront_origin" {
  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG*"]
  }
  filter {
    name   = "vpc-id"
    values = [aws_vpc.application.id]
  }
  depends_on = [aws_cloudfront_vpc_origin.public_api]
}

resource "aws_vpc_security_group_ingress_rule" "cloudfront_origin" {
  security_group_id            = aws_security_group.public_api.id
  referenced_security_group_id = data.aws_security_group.cloudfront_origin.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_cloudfront_function" "api_request" {
  name    = "fiapx-api-request"
  runtime = "cloudfront-js-2.0"
  comment = "Public API prefix and trusted forwarding headers"
  publish = true
  code    = file("${path.module}/cloudfront/api-request.js")
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "api" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "public_api" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "FIAP X public APIs; private ALB origin"
  http_version    = "http2and3"
  price_class     = "PriceClass_All"
  dynamic "origin" {
    for_each = local.public_apis
    content {
      domain_name         = aws_lb.public_api.dns_name
      origin_id           = origin.key
      connection_attempts = 1
      connection_timeout  = 10
      custom_header {
        name  = "X-Fiapx-Service"
        value = origin.key
      }
      vpc_origin_config {
        vpc_origin_id            = aws_cloudfront_vpc_origin.public_api.id
        origin_read_timeout      = 60
        origin_keepalive_timeout = 5
      }
    }
  }
  default_cache_behavior {
    target_origin_id         = "identity"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.api.id
    compress                 = false
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.api_request.arn
    }
  }
  ordered_cache_behavior {
    path_pattern             = "/api/video/*"
    target_origin_id         = "video"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.api.id
    compress                 = false
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.api_request.arn
    }
  }
  dynamic "custom_error_response" {
    for_each = toset([400, 403, 404, 405, 414, 416, 500, 501, 502, 503, 504])
    content {
      error_code            = custom_error_response.value
      error_caching_min_ttl = 0
    }
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
  depends_on = [aws_vpc_security_group_ingress_rule.cloudfront_origin]
}

output "public_api" {
  value = {
    base_url         = "https://${aws_cloudfront_distribution.public_api.domain_name}"
    identity_url     = "https://${aws_cloudfront_distribution.public_api.domain_name}/api/identity"
    video_url        = "https://${aws_cloudfront_distribution.public_api.domain_name}/api/video"
    identity_swagger = "https://${aws_cloudfront_distribution.public_api.domain_name}/api/identity/swagger-ui.html"
    video_swagger    = "https://${aws_cloudfront_distribution.public_api.domain_name}/api/video/swagger-ui.html"
  }
}
