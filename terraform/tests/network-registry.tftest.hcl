mock_provider "aws" {}

variables {
  media_bucket_name = "fiapx-media-unit-test"
}

run "isolated_network_and_registries" {
  command = apply
  assert {
    condition = (
      aws_vpc.application.enable_dns_support && aws_vpc.application.enable_dns_hostnames &&
      length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2 &&
      toset([for subnet in aws_subnet.public : subnet.cidr_block]) == toset(["10.50.0.0/24", "10.50.1.0/24"]) &&
      toset([for subnet in aws_subnet.private : subnet.cidr_block]) == toset(["10.50.10.0/24", "10.50.11.0/24"])
    )
    error_message = "The network needs DNS and four non-overlapping /24 subnets in the dedicated VPC."
  }
  assert {
    condition = alltrue([for index, subnet in aws_subnet.private : (
      !subnet.map_public_ip_on_launch && subnet.vpc_id == aws_vpc.application.id &&
      subnet.availability_zone == aws_subnet.public[index].availability_zone &&
      aws_route_table_association.private[index].subnet_id == subnet.id &&
      aws_route_table_association.private[index].route_table_id == aws_route_table.private.id
    )])
    error_message = "Private subnets must use the private route table, have no public IP assignment and match public AZs."
  }
  assert {
    condition = (
      aws_route.private_default.nat_gateway_id == aws_nat_gateway.application.id &&
      aws_route.private_default.route_table_id == aws_route_table.private.id &&
      aws_route.private_default.destination_cidr_block == "0.0.0.0/0" &&
      aws_nat_gateway.application.subnet_id == aws_subnet.public["0"].id &&
      aws_nat_gateway.application.allocation_id == aws_eip.nat.id &&
      aws_route.public_default.gateway_id == aws_internet_gateway.application.id &&
      aws_route.public_default.route_table_id == aws_route_table.public.id &&
      alltrue([for index, subnet in aws_subnet.public :
        aws_route_table_association.public[index].subnet_id == subnet.id &&
        aws_route_table_association.public[index].route_table_id == aws_route_table.public.id
      ])
    )
    error_message = "Private egress must traverse the NAT in a public subnet routed to the internet gateway."
  }
  assert {
    condition     = length(aws_default_security_group.application.ingress) == 0 && length(aws_default_security_group.application.egress) == 0
    error_message = "The default security group must grant no access."
  }
  assert {
    condition = (
      toset(keys(aws_ecr_repository.service)) == toset(["fiapx-identity-service", "fiapx-video-service", "fiapx-processing-service"]) &&
      alltrue([for repository in aws_ecr_repository.service :
        repository.image_tag_mutability == "IMMUTABLE" && !repository.force_delete &&
        one(repository.encryption_configuration).encryption_type == "AES256" &&
        one(repository.image_scanning_configuration).scan_on_push
      ])
    )
    error_message = "Only the three existing services receive encrypted, scanned, immutable repositories protected against forced deletion."
  }
}

run "reject_duplicate_zones" {
  command = plan
  variables {
    network_availability_zones = ["us-east-1a", "us-east-1a"]
  }
  expect_failures = [var.network_availability_zones]
}

run "reject_other_region" {
  command = plan
  variables {
    network_availability_zones = ["us-east-1a", "us-west-2b"]
  }
  expect_failures = [var.network_availability_zones]
}
