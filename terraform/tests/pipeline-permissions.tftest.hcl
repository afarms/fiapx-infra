mock_provider "aws" {}

variables {
  media_bucket_name = "fiapx-media-unit-test"
}

run "pipeline_permission_boundaries" {
  command = plan
  variables {
    media_bucket_name = "fiapx-media-unit-test"
  }
  assert {
    condition = alltrue(flatten([
      for file_name in ["network-pipeline-policy.json", "registry-pipeline-policy.json"] : [
        for statement in jsondecode(file("${path.module}/../docs/operations/${file_name}")).Statement :
        statement.Effect == "Allow" &&
        statement.Condition.StringEquals["aws:RequestedRegion"] == "us-east-1" &&
        alltrue([for action in statement.Action :
          !strcontains(action, "*") &&
          !startswith(action, "iam:") &&
          !contains(["ec2:RunInstances", "ec2:AuthorizeSecurityGroupIngress", "ec2:AuthorizeSecurityGroupEgress", "ec2:DeleteVpc", "ec2:DeleteSubnet", "ec2:DeleteNatGateway", "ec2:ReleaseAddress", "ecr:DeleteRepository", "ecr:BatchDeleteImage", "ecr:PutImage", "ecr:GetAuthorizationToken"], action)
        ])
      ]
    ]))
    error_message = "Policies must remain regional, use explicit actions and exclude IAM, compute, ingress grants, image access and destruction."
  }
  assert {
    condition = alltrue([
      for statement in jsondecode(file("${path.module}/../docs/operations/network-pipeline-policy.json")).Statement :
      statement.Sid == "ReadNetwork" ? (
        statement.Resource == "*" && alltrue([for action in statement.Action : startswith(action, "ec2:Describe")])
        ) : (
        alltrue([for arn in statement.Resource : startswith(arn, "arn:aws:ec2:us-east-1:ACCOUNT_ID:")]) &&
        (try(statement.Condition.StringEquals["ec2:ResourceTag/Project"] == "fiapx" && statement.Condition.StringEquals["ec2:ResourceTag/ManagedBy"] == "terraform", false) ||
        try(statement.Condition.StringEquals["aws:RequestTag/Project"] == "fiapx" && statement.Condition.StringEquals["aws:RequestTag/ManagedBy"] == "terraform", false))
      )
    ])
    error_message = "Only EC2 reads can use Resource=*; every write requires account/region ARNs and project ownership or creation tags."
  }
  assert {
    condition = alltrue([
      for statement in jsondecode(file("${path.module}/../docs/operations/registry-pipeline-policy.json")).Statement :
      toset(statement.Resource) == toset([
        "arn:aws:ecr:us-east-1:ACCOUNT_ID:repository/fiapx-identity-service",
        "arn:aws:ecr:us-east-1:ACCOUNT_ID:repository/fiapx-video-service",
        "arn:aws:ecr:us-east-1:ACCOUNT_ID:repository/fiapx-processing-service"
      ])
    ])
    error_message = "ECR permissions must never reach other repositories or a wildcard resource."
  }
  assert {
    condition = alltrue([
      for statement in jsondecode(file("${path.module}/../docs/operations/network-pipeline-policy.json")).Statement :
      statement.Sid != "BootstrapDefaultGroupTags" || (
        statement.Action == ["ec2:CreateTags"] &&
        statement.Resource == ["arn:aws:ec2:us-east-1:ACCOUNT_ID:security-group/*"] &&
        statement.Condition.StringEquals["aws:RequestTag/Name"] == "fiapx-default-no-access" &&
        statement.Condition.Null["ec2:ResourceTag/Project"] == "true" &&
        statement.Condition.Null["ec2:ResourceTag/ManagedBy"] == "true" &&
        statement.Condition.Null["ec2:ResourceTag/Name"] == "true" &&
        toset(statement.Condition["ForAllValues:StringEquals"]["aws:TagKeys"]) == toset(["Project", "ManagedBy", "Name"])
      )
    ])
    error_message = "The bootstrap exception must only tag an unidentified group with the three fixed tags, never grant rule changes itself."
  }
  assert {
    condition = alltrue([
      for statement in jsondecode(file("${path.module}/../docs/operations/network-pipeline-policy.json")).Statement :
      statement.Sid != "MaintainOwnedTags" ||
      toset(statement.Condition["ForAllValues:StringNotEquals"]["aws:TagKeys"]) == toset(["Project", "ManagedBy"])
    ])
    error_message = "Ordinary tagging must not change or remove the ownership boundary tags."
  }
  assert {
    condition = alltrue([
      for name in ["network-pipeline-policy.json", "registry-pipeline-policy.json"] :
      length(jsonencode(jsondecode(file("${path.module}/../docs/operations/${name}")))) <= 6144
    ])
    error_message = "Each document must fit the IAM customer-managed policy size limit."
  }
}
