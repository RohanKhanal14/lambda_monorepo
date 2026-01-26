.PHONY: help setup setup-github setup-codecommit list-stacks status status-lambda1 status-lambda2 logs logs-lambda1 logs-lambda2 pipeline-status pipeline-status-lambda1 pipeline-status-lambda2 cleanup cleanup-all

AWS_REGION ?= us-east-1
AWS_ACCOUNT_ID = $(shell aws sts get-caller-identity --query Account --output text)

help:
	@echo "Lambda Monorepo CodePipeline Management"
	@echo "======================================="
	@echo ""
	@echo "Setup targets:"
	@echo "  make setup-github        - Setup with GitHub (recommended)"
	@echo "  make setup-codecommit    - Setup with AWS CodeCommit (legacy)"
	@echo ""
	@echo "GitHub setup:"
	@echo "  GITHUB_REPO=owner/repo make setup-github"
	@echo "  Example: GITHUB_REPO=myuser/my-repo make setup-github"
	@echo ""
	@echo "Monitoring targets (both pipelines):"
	@echo "  make status             - View both Lambda1 and Lambda2 pipeline status"
	@echo "  make list-stacks        - List all CloudFormation stacks"
	@echo ""
	@echo "Lambda1-specific targets:"
	@echo "  make status-lambda1     - View Lambda1 pipeline status"
	@echo "  make logs-lambda1       - View Lambda1 CodeBuild logs (real-time)"
	@echo "  make pipeline-status-lambda1  - View detailed Lambda1 pipeline state"
	@echo ""
	@echo "Lambda2-specific targets:"
	@echo "  make status-lambda2     - View Lambda2 pipeline status"
	@echo "  make logs-lambda2       - View Lambda2 CodeBuild logs (real-time)"
	@echo "  make pipeline-status-lambda2  - View detailed Lambda2 pipeline state"
	@echo ""
	@echo "Management targets:"
	@echo "  make cleanup            - Remove pipelines (keeps Lambda stacks)"
	@echo "  make cleanup-all        - Remove everything including Lambda stacks"
	@echo ""
	@echo "Local testing:"
	@echo "  make build              - Build SAM locally"
	@echo "  make local-api          - Start local API Gateway"
	@echo ""
	@echo "Examples:"
	@echo "  make setup-github GITHUB_REPO=myuser/my-repo"
	@echo "  make status-lambda1"
	@echo "  make logs-lambda2"
	@echo "  make cleanup"

# ============================================================================
# Setup Targets
# ============================================================================

setup-github:
	@if [ -z "$(GITHUB_REPO)" ]; then \
		echo "Error: GITHUB_REPO required"; \
		echo "Usage: GITHUB_REPO=owner/repo make setup-github"; \
		echo "Example: GITHUB_REPO=myuser/my-repo make setup-github"; \
		exit 1; \
	fi
	@echo "Setting up with GitHub: $(GITHUB_REPO)..."
	@export AWS_REGION=$(AWS_REGION) GITHUB_REPO=$(GITHUB_REPO) GITHUB_BRANCH=$(GITHUB_BRANCH) && chmod +x setup-pipeline-github.sh && ./setup-pipeline-github.sh

setup-codecommit:
	@echo "Setting up with AWS CodeCommit..."
	@export AWS_REGION=$(AWS_REGION) USE_CODECOMMIT=true && chmod +x setup-pipeline.sh && ./setup-pipeline.sh

setup:
	@echo "Setup with GitHub (recommended)"
	@$(MAKE) setup-github

# ============================================================================
# Monitoring Targets
# ============================================================================

status:
	@echo "Lambda1 Pipeline Status:"
	@aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda1 --region $(AWS_REGION) --query 'stageStates[*].[stageName,latestExecution.status]' --output table
	@echo ""
	@echo "Lambda2 Pipeline Status:"
	@aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda2 --region $(AWS_REGION) --query 'stageStates[*].[stageName,latestExecution.status]' --output table

status-lambda1:
	@echo "Lambda1 Pipeline Status:"
	@aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda1 --region $(AWS_REGION) --query 'stageStates[*].[stageName,latestExecution.status]' --output table

status-lambda2:
	@echo "Lambda2 Pipeline Status:"
	@aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda2 --region $(AWS_REGION) --query 'stageStates[*].[stageName,latestExecution.status]' --output table

pipeline-status-lambda1:
	@aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda1 --region $(AWS_REGION)

pipeline-status-lambda2:
	@aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda2 --region $(AWS_REGION)

list-stacks:
	@echo "CloudFormation Stacks:"
	@aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --region $(AWS_REGION) --query 'StackSummaries[?contains(StackName, `lambda-monorepo`)].{Name:StackName,Status:StackStatus,Updated:LastUpdatedTime}' --output table

logs-lambda1:
	@echo "Lambda1 CodeBuild Logs (streaming):"
	@aws logs tail /aws/codebuild/lambda-monorepo-lambda1-build --region $(AWS_REGION) --follow

logs-lambda2:
	@echo "Lambda2 CodeBuild Logs (streaming):"
	@aws logs tail /aws/codebuild/lambda-monorepo-lambda2-build --region $(AWS_REGION) --follow

logs:
	@echo "Lambda1 CodeBuild Logs (streaming):"
	@aws logs tail /aws/codebuild/lambda-monorepo-lambda1-build --region $(AWS_REGION) --follow

# ============================================================================
# Management Targets
# ============================================================================

# (removed manual start-pipeline as pipelines auto-trigger on code changes)

# ============================================================================
# Local Development Targets
# ============================================================================

build:
	@echo "Building SAM application locally..."
	@sam build

local-api:
	@echo "Starting local API Gateway..."
	@sam local start-api

# ============================================================================
# Cleanup Targets
# ============================================================================

cleanup:
	@echo "Removing CodePipeline infrastructure..."
	@echo "This will remove both Lambda1 and Lambda2 pipelines but keep Lambda stacks."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		aws cloudformation delete-stack --stack-name lambda-monorepo-pipeline-lambda1 --region $(AWS_REGION); \
		aws cloudformation delete-stack --stack-name lambda-monorepo-pipeline-lambda2 --region $(AWS_REGION); \
		echo "Pipeline stacks deleted."; \
		echo "Cleaning up S3 artifacts..."; \
		aws s3 rm s3://lambda-monorepo-lambda1-artifacts-$(AWS_ACCOUNT_ID) --recursive 2>/dev/null || true; \
		aws s3 rb s3://lambda-monorepo-lambda1-artifacts-$(AWS_ACCOUNT_ID) 2>/dev/null || true; \
		aws s3 rm s3://lambda-monorepo-lambda2-artifacts-$(AWS_ACCOUNT_ID) --recursive 2>/dev/null || true; \
		aws s3 rb s3://lambda-monorepo-lambda2-artifacts-$(AWS_ACCOUNT_ID) 2>/dev/null || true; \
		echo "Cleanup complete."; \
	else \
		echo "Cleanup cancelled."; \
	fi

cleanup-all:
	@echo "WARNING: This will delete ALL resources including Lambda stacks!"
	@read -p "Are you absolutely sure? Type 'yes' to continue: " -r; \
	if [ "$$REPLY" = "yes" ]; then \
		echo "Deleting Lambda1 stacks..."; \
		aws cloudformation delete-stack --stack-name lambda-monorepo-lambda1-stack-prod --region $(AWS_REGION) 2>/dev/null || true; \
		aws cloudformation delete-stack --stack-name lambda-monorepo-lambda1-stack-staging --region $(AWS_REGION) 2>/dev/null || true; \
		aws cloudformation delete-stack --stack-name lambda-monorepo-lambda1-stack-dev --region $(AWS_REGION) 2>/dev/null || true; \
		echo "Deleting Lambda2 stacks..."; \
		aws cloudformation delete-stack --stack-name lambda-monorepo-lambda2-stack-prod --region $(AWS_REGION) 2>/dev/null || true; \
		aws cloudformation delete-stack --stack-name lambda-monorepo-lambda2-stack-staging --region $(AWS_REGION) 2>/dev/null || true; \
		aws cloudformation delete-stack --stack-name lambda-monorepo-lambda2-stack-dev --region $(AWS_REGION) 2>/dev/null || true; \
		echo "Deleting pipelines..."; \
		aws cloudformation delete-stack --stack-name lambda-monorepo-pipeline-lambda1 --region $(AWS_REGION) 2>/dev/null || true; \
		aws cloudformation delete-stack --stack-name lambda-monorepo-pipeline-lambda2 --region $(AWS_REGION) 2>/dev/null || true; \
		echo "Deleting IAM roles..."; \
		aws cloudformation delete-stack --stack-name lambda-monorepo-iam-roles --region $(AWS_REGION) 2>/dev/null || true; \
		echo "Cleaning up S3..."; \
		aws s3 rm s3://lambda-monorepo-lambda1-artifacts-$(AWS_ACCOUNT_ID) --recursive 2>/dev/null || true; \
		aws s3 rb s3://lambda-monorepo-lambda1-artifacts-$(AWS_ACCOUNT_ID) 2>/dev/null || true; \
		aws s3 rm s3://lambda-monorepo-lambda2-artifacts-$(AWS_ACCOUNT_ID) --recursive 2>/dev/null || true; \
		aws s3 rb s3://lambda-monorepo-lambda2-artifacts-$(AWS_ACCOUNT_ID) 2>/dev/null || true; \
		echo "Full cleanup initiated. This may take several minutes..."; \
		echo "Use 'make list-stacks' to monitor deletion progress."; \
	else \
		echo "Cleanup cancelled."; \
	fi
