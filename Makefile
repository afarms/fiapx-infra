TERRAFORM := terraform
.DEFAULT_GOAL := verify
.PHONY: verify backend-check

# Local validation without AWS credentials or remote backend initialization.
verify:
	$(TERRAFORM) -chdir=terraform fmt -check -recursive
	$(TERRAFORM) -chdir=terraform init -backend=false -input=false
	$(TERRAFORM) -chdir=terraform validate

# Requires AWS credentials. May initialize an empty state and uses the S3 lock.
# Intended for the empty configuration before application resources are added.
backend-check:
	bash scripts/init-backend.sh
	$(TERRAFORM) -chdir=terraform validate
	$(TERRAFORM) -chdir=terraform plan -input=false -lock=true -lock-timeout=60s -detailed-exitcode -no-color
