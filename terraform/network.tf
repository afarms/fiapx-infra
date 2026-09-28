locals {
  network_zones = { for index, az in var.network_availability_zones : tostring(index) => az }
}

resource "aws_vpc" "application" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "fiapx-application" }
}

resource "aws_default_security_group" "application" {
  vpc_id = aws_vpc.application.id
  tags   = { Name = "fiapx-default-no-access" }
  # No ingress or egress: future workloads must use dedicated security groups.
}

resource "aws_internet_gateway" "application" {
  vpc_id = aws_vpc.application.id
  tags   = { Name = "fiapx-internet" }
}

resource "aws_subnet" "public" {
  for_each                = local.network_zones
  vpc_id                  = aws_vpc.application.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(aws_vpc.application.cidr_block, 8, tonumber(each.key))
  map_public_ip_on_launch = false
  tags = {
    Name                     = "fiapx-public-${each.value}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  for_each                = local.network_zones
  vpc_id                  = aws_vpc.application.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(aws_vpc.application.cidr_block, 8, 10 + tonumber(each.key))
  map_public_ip_on_launch = false
  tags = {
    Name                              = "fiapx-private-${each.value}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "fiapx-nat" }
}

resource "aws_nat_gateway" "application" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["0"].id
  tags          = { Name = "fiapx-nat" }
  depends_on    = [aws_internet_gateway.application]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.application.id
  tags   = { Name = "fiapx-public" }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.application.id
}

resource "aws_route_table_association" "public" {
  for_each       = local.network_zones
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.application.id
  tags   = { Name = "fiapx-private" }
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.application.id
}

resource "aws_route_table_association" "private" {
  for_each       = local.network_zones
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private.id
}
