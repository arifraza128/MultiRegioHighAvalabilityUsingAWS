.PHONY: help init fmt validate lint security-scan plan apply destroy verify-teardown

TFVARS ?= environments/dev/terraform.tfvars

help:
	@echo "Multi-Region HA on AWS - Operational Makefile"
	@echo "  make init             - Initialize Terraform in bootstrap/ and root"
	@echo "  make fmt              - Format all Terraform files recursively"
	@echo "  make validate         - Validate bootstrap and root Terraform configs"
	@echo "  make lint             - Run tflint recursively"
	@echo "  make security-scan    - Run checkov security scanner"
	@echo "  make plan             - Generate Terraform execution plan using $(TFVARS)"
	@echo "  make apply            - Apply Terraform plan (requires manual confirmation)"
	@echo "  make destroy          - Destroy all active resources after test session"
	@echo "  make verify-teardown  - Verify zero billable resources remain in us-east-1 and ap-south-1"

init:
	terraform -chdir=bootstrap init -backend=false
	terraform init -backend=false

fmt:
	terraform fmt -recursive

validate:
	terraform -chdir=bootstrap validate
	terraform validate

lint:
	tflint --recursive

security-scan:
	checkov -d . --framework terraform,dockerfile

plan:
	terraform plan -var-file=$(TFVARS)

apply:
	terraform apply -var-file=$(TFVARS)

destroy:
	terraform destroy -var-file=$(TFVARS)

verify-teardown:
	bash scripts/verify-clean-teardown.sh
