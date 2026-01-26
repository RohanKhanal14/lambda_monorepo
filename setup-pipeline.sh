#!/bin/bash

##############################################################################
# Lambda Monorepo CodePipeline Deployment Setup Script
# 
# This script automates the setup of AWS CodePipeline for Lambda deployment
# Prerequisites: AWS CLI configured, appropriate IAM permissions
##############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="${AWS_REGION:-us-east-1}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
USE_CODECOMMIT="${USE_CODECOMMIT:-true}"
CODECOMMIT_REPO="${CODECOMMIT_REPO:-lambda-monorepo}"

##############################################################################
# Helper Functions
##############################################################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

##############################################################################
# Main Setup Flow
##############################################################################

main() {
    print_header "Lambda Monorepo CodePipeline Setup"
    
    # Check AWS CLI
    print_info "Checking AWS CLI configuration..."
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI not found. Please install AWS CLI."
        exit 1
    fi
    print_success "AWS CLI found"
    
    # Get AWS Account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_success "AWS Account ID: $ACCOUNT_ID"
    
    # Step 1: Deploy IAM Roles
    print_header "Step 1: Deploying IAM Roles Stack"
    deploy_iam_roles
    
    # Step 2: Create Artifact Bucket
    print_header "Step 2: Setting up Artifact Bucket"
    create_artifact_bucket
    
    # Step 3: Initialize CodeCommit or GitHub
    print_header "Step 3: Setting up Source Repository"
    if [ "$USE_CODECOMMIT" = "true" ]; then
        setup_codecommit
    else
        setup_github
    fi
    
    # Step 4: Deploy CodePipeline
    print_header "Step 4: Deploying CodePipeline"
    deploy_codepipeline
    
    # Step 5: Display summary
    print_header "Setup Complete!"
    display_summary
}

##############################################################################
# Function: Deploy IAM Roles
##############################################################################

deploy_iam_roles() {
    print_info "Creating IAM roles for CodePipeline, CodeBuild, and CloudFormation..."
    
    aws cloudformation deploy \
        --template-file iam-roles-template.yaml \
        --stack-name lambda-monorepo-iam-roles \
        --region "$AWS_REGION" \
        --no-fail-on-empty-changeset \
        --capabilities CAPABILITY_NAMED_IAM
    
    print_success "IAM roles deployed successfully"
}

##############################################################################
# Function: Create Artifact Bucket
##############################################################################

create_artifact_bucket() {
    # Create separate buckets for Lambda1 and Lambda2
    for LAMBDA in lambda1 lambda2; do
        BUCKET_NAME="lambda-monorepo-${LAMBDA}-artifacts-${ACCOUNT_ID}"
        
        # Check if bucket exists
        if aws s3 ls "s3://${BUCKET_NAME}" 2>/dev/null; then
            print_warning "Artifact bucket already exists: $BUCKET_NAME"
        else
            print_info "Creating artifact bucket: $BUCKET_NAME"
            aws s3 mb "s3://${BUCKET_NAME}" --region "$AWS_REGION"
            
            # Enable versioning
            aws s3api put-bucket-versioning \
                --bucket "$BUCKET_NAME" \
                --versioning-configuration Status=Enabled \
                --region "$AWS_REGION"
            
            print_success "Artifact bucket created and versioning enabled: $BUCKET_NAME"
        fi
    done
}

##############################################################################
# Function: Setup CodeCommit
##############################################################################

setup_codecommit() {
    print_info "Setting up CodeCommit repository: $CODECOMMIT_REPO"
    
    # Check if repository exists
    if aws codecommit get-repository --repository-name "$CODECOMMIT_REPO" \
        --region "$AWS_REGION" 2>/dev/null; then
        print_warning "CodeCommit repository already exists: $CODECOMMIT_REPO"
    else
        print_info "Creating CodeCommit repository..."
        aws codecommit create-repository \
            --repository-name "$CODECOMMIT_REPO" \
            --description "Lambda Monorepo for SAM Deployment" \
            --region "$AWS_REGION"
        print_success "CodeCommit repository created"
        
        # Get clone URL
        CLONE_URL=$(aws codecommit get-repository \
            --repository-name "$CODECOMMIT_REPO" \
            --region "$AWS_REGION" \
            --query 'repositoryMetadata.cloneUrlHttp' \
            --output text)
        
        print_info "Clone URL: $CLONE_URL"
    fi
    
    SOURCE_PROVIDER="CodeCommit"
}

##############################################################################
# Function: Setup GitHub
##############################################################################

setup_github() {
    if [ -z "$GITHUB_REPO" ] || [ -z "$GITHUB_TOKEN" ]; then
        print_error "GitHub repository and token required"
        print_info "Set GITHUB_REPO and GITHUB_TOKEN environment variables"
        exit 1
    fi
    
    print_success "GitHub repository configured: $GITHUB_REPO"
    SOURCE_PROVIDER="GitHub"
}

##############################################################################
# Function: Deploy CodePipeline
##############################################################################

deploy_codepipeline() {
    print_info "Deploying CodePipeline infrastructure for Lambda1 and Lambda2..."
    
    # Deploy Lambda1 Pipeline
    print_info "Deploying Lambda1 CodePipeline..."
    aws cloudformation deploy \
        --template-file codepipeline-lambda1-template.yaml \
        --stack-name lambda-monorepo-pipeline-lambda1 \
        --region "$AWS_REGION" \
        --no-fail-on-empty-changeset
    
    print_success "Lambda1 CodePipeline deployed successfully"
    
    # Deploy Lambda2 Pipeline
    print_info "Deploying Lambda2 CodePipeline..."
    aws cloudformation deploy \
        --template-file codepipeline-lambda2-template.yaml \
        --stack-name lambda-monorepo-pipeline-lambda2 \
        --region "$AWS_REGION" \
        --no-fail-on-empty-changeset
    
    print_success "Lambda2 CodePipeline deployed successfully"
}

##############################################################################
# Function: Display Summary
##############################################################################

display_summary() {
    CONSOLE_URL_LAMBDA1="https://console.aws.amazon.com/codepipeline/home?region=${AWS_REGION}#/view/lambda-monorepo-pipeline-lambda1"
    CONSOLE_URL_LAMBDA2="https://console.aws.amazon.com/codepipeline/home?region=${AWS_REGION}#/view/lambda-monorepo-pipeline-lambda2"
    
    echo ""
    print_success "Pipeline deployment completed!"
    echo ""
    echo "Separate pipelines deployed:"
    echo "  • Lambda1 Pipeline: $CONSOLE_URL_LAMBDA1"
    echo "  • Lambda2 Pipeline: $CONSOLE_URL_LAMBDA2"
    echo ""
    echo "Next steps:"
    echo "  1. Push code to CodeCommit repository: $CODECOMMIT_REPO"
    echo "  2. Each pipeline will trigger on changes to its Lambda directory (lambda1/ or lambda2/)"
    echo "  3. Shared layer changes (layers/shared/) will trigger both pipelines"
    echo ""
    echo "Pipeline stages (same for both Lambda1 and Lambda2):"
    echo "  • Source: Pulls code from CodeCommit"
    echo "  • Build: Builds and packages SAM application"
    echo "  • DeployToDev: Deploys to dev environment"
    echo "  • ApprovalForStaging: Manual approval required"
    echo "  • DeployToStaging: Deploys to staging environment"
    echo "  • ApprovalForProduction: Manual approval required"
    echo "  • DeployToProduction: Deploys to production environment"
    echo ""
    echo "Useful commands:"
    echo "  # View Lambda1 pipeline status"
    echo "  aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda1 --region $AWS_REGION"
    echo ""
    echo "  # View Lambda2 pipeline status"
    echo "  aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda2 --region $AWS_REGION"
    echo ""
    echo "  # View Lambda1 build logs"
    echo "  aws logs tail /aws/codebuild/lambda-monorepo-lambda1-build --region $AWS_REGION --follow"
    echo ""
    echo "  # View Lambda2 build logs"
    echo "  aws logs tail /aws/codebuild/lambda-monorepo-lambda2-build --region $AWS_REGION --follow"
    echo ""
}

##############################################################################
# Cleanup Function
##############################################################################

cleanup() {
    print_warning "Setup interrupted. To rollback, run:"
    echo "  aws cloudformation delete-stack --stack-name lambda-monorepo-pipeline-lambda1 --region $AWS_REGION"
    echo "  aws cloudformation delete-stack --stack-name lambda-monorepo-pipeline-lambda2 --region $AWS_REGION"
    echo "  aws cloudformation delete-stack --stack-name lambda-monorepo-iam-roles --region $AWS_REGION"
}

# Run main function
trap cleanup EXIT
main
