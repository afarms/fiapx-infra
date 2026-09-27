TERRAFORM := terraform
.DEFAULT_GOAL := verify
.PHONY: verify fmt lock infra-plan infra-apply

# Local validation without AWS credentials or remote backend initialization.
verify:
	$(TERRAFORM) -chdir=terraform fmt -check -recursive
	$(TERRAFORM) -chdir=terraform init -backend=false -input=false
	$(TERRAFORM) -chdir=terraform validate
	$(TERRAFORM) -chdir=terraform test
	bash -n scripts/init-backend.sh scripts/infra-delivery.sh
	bash scripts/test-delivery-guards.sh

fmt:
	$(TERRAFORM) -chdir=terraform fmt -recursive

lock:
	$(TERRAFORM) -chdir=terraform providers lock -platform=windows_amd64 -platform=linux_amd64

infra-plan:
	bash scripts/infra-delivery.sh plan

infra-apply:
	bash scripts/infra-delivery.sh apply
