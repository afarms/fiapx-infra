terraform {
  backend "s3" {
    bucket       = "fiap-fase-05"
    key          = "fiapx-infra/tfstate/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
