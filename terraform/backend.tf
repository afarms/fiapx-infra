terraform {
  required_version = "= 1.14.7"

  backend "s3" {
    bucket              = "fiap-fase-05"
    key                 = "fiapx-infra/tfstate/terraform.tfstate"
    region              = "us-east-1"
    encrypt             = true
    use_lockfile        = true
    allowed_account_ids = ["388799375729"]
  }
}
