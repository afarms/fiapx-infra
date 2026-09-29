TERRAFORM := terraform
.DEFAULT_GOAL := verify
.PHONY: verify fmt lock init plan apply check-drift check-pr

# Local validation without AWS credentials or remote backend initialization.
verify:
	$(TERRAFORM) -chdir=terraform fmt -check -recursive
	$(TERRAFORM) -chdir=terraform init -backend=false -input=false
	$(TERRAFORM) -chdir=terraform validate
	bash -n scripts/init-backend.sh
	bash -n terraform/bootstrap/administration.sh
	bash scripts/test-pr-revision.sh

check-pr:
	bash scripts/check-pr-revision.sh

fmt:
	$(TERRAFORM) -chdir=terraform fmt -recursive

lock:
	$(TERRAFORM) -chdir=terraform providers lock -platform=windows_amd64 -platform=linux_amd64

init:
	bash scripts/init-backend.sh

plan:
	bash -c 'mkdir -p .local'
	$(TERRAFORM) -chdir=terraform plan -input=false -lock-timeout=60s -no-color -out=../.local/terraform.tfplan

# A saved plan is the approval; Terraform does not prompt again.
apply:
	$(TERRAFORM) -chdir=terraform apply -input=false -lock-timeout=60s -no-color ../.local/terraform.tfplan

check-drift:
	$(TERRAFORM) -chdir=terraform plan -input=false -lock-timeout=60s -detailed-exitcode -no-color
