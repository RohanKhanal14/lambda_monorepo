#!/bin/bash

##############################################################################
# Lambda Monorepo CodePipeline Deployment Setup Script (GitHub + CodeStar)
# 
# This script automates the setup of AWS CodePipeline for Lambda deployment
# with GitHub as the source control using CodeStar Connections
# 
# Prerequisites: 
#   - AWS CLI configured with appropriate IAM permissions
#   - GitHub account with repository access
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
GITHUB_REPO="${GITHUB_REPO:-}"          # Format: owner/repo
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
CODESTAR_CONNECTION_NAME="${CODESTAR_CONNECTION_NAME:-github-lambda-monorepo}"

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
# Function: Validate GitHub Repo Format
##############################################################################

validate_github_repo() {
    if [ -z "$GITHUB_REPO" ]; then
        print_error "GitHub repository required (format: owner/repo)"
        print_info "Set GITHUB_REPO environment variable"
        echo "  Example: export GITHUB_REPO=myusername/my-lambda-repo"
        exit 1
    fi
    
    if [[ ! "$GITHUB_REPO" =~ ^[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$ ]]; then
        print_error "Invalid GitHub repo format: $GITHUB_REPO"
        print_info "Expected format: owner/repo"
        exit 1
    fi
    
    print_success "GitHub repository format valid: $GITHUB_REPO"
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
# Function: Create Artifact Buckets
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
# Function: Create/Get CodeStar Connection
##############################################################################

setup_codestar_connection() {
    print_info "Setting up CodeStar connection to GitHub..."
    print_info "Connection name: $CODESTAR_CONNECTION_NAME"
    
    # Check if connection already exists
    EXISTING_CONNECTION=$(aws codestar-connections list-connections \
        --region "$AWS_REGION" \
        --query "Connections[?ConnectionName=='$CODESTAR_CONNECTION_NAME'].ConnectionArn" \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$EXISTING_CONNECTION" ]; then
        print_success "CodeStar connection already exists: $CODESTAR_CONNECTION_NAME"
        CODESTAR_CONNECTION_ARN="$EXISTING_CONNECTION"
    else
        print_info "Creating new CodeStar connection..."
        CONNECTION_RESPONSE=$(aws codestar-connections create-connection \
            --provider-type GitHub \
            --connection-name "$CODESTAR_CONNECTION_NAME" \
            --region "$AWS_REGION" \
            --output json)
        
        CODESTAR_CONNECTION_ARN=$(echo "$CONNECTION_RESPONSE" | jq -r '.ConnectionArn')
        
        print_success "CodeStar connection created: $CODESTAR_CONNECTION_ARN"
        print_warning "⚠️  IMPORTANT: You must authorize this connection in AWS Console!"
        print_info "Steps to authorize:"
        echo "  1. Go to AWS Console → Developer Tools → Connections"
        echo "  2. Find connection: $CODESTAR_CONNECTION_NAME"
        echo "  3. Click 'Update pending connection'"
        echo "  4. Follow GitHub authorization flow"
        echo ""
        read -p "Press ENTER after authorizing the connection in AWS Console..."
    fi
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
        --no-fail-on-empty-changeset \
        --parameter-overrides \
            GitHubRepo="$GITHUB_REPO" \
            GitHubBranch="$GITHUB_BRANCH" \
            CodeStarConnectionArn="$CODESTAR_CONNECTION_ARN"
    
    print_success "Lambda1 CodePipeline deployed successfully"
    
    # Deploy Lambda2 Pipeline
    print_info "Deploying Lambda2 CodePipeline..."
    aws cloudformation deploy \
        --template-file codepipeline-lambda2-template.yaml \
        --stack-name lambda-monorepo-pipeline-lambda2 \
        --region "$AWS_REGION" \
        --no-fail-on-empty-changeset \
        --parameter-overrides \
            GitHubRepo="$GITHUB_REPO" \
            GitHubBranch="$GITHUB_BRANCH" \
            CodeStarConnectionArn="$CODESTAR_CONNECTION_ARN"
    
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
    echo "Repository:"
    echo "  • GitHub: https://github.com/$GITHUB_REPO"
    echo "  • Branch: $GITHUB_BRANCH"
    echo ""
    echo "Next steps:"
    echo "  1. Push code to GitHub: git push origin $GITHUB_BRANCH"
    echo "  2. Each pipeline will trigger on changes to its Lambda directory"
    echo "  3. Lambda1 triggers: lambda1/ or layers/shared/ changes"
    echo "  4. Lambda2 triggers: lambda2/ or layers/shared/ changes"
    echo ""
    echo "Pipeline stages (both Lambda1 and Lambda2):"
    echo "  • Source: Pulls code from GitHub"
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
# Function: Cleanup Function
##############################################################################

cleanup() {
    print_warning "Setup interrupted. To rollback, run:"
    echo "  aws cloudformation delete-stack --stack-name lambda-monorepo-pipeline-lambda1 --region $AWS_REGION"
    echo "  aws cloudformation delete-stack --stack-name lambda-monorepo-pipeline-lambda2 --region $AWS_REGION"
    echo "  aws cloudformation delete-stack --stack-name lambda-monorepo-iam-roles --region $AWS_REGION"
}

##############################################################################
# Main Setup Flow
##############################################################################

main() {
    print_header "Lambda Monorepo CodePipeline Setup (GitHub + CodeStar)"
    
    # Validate inputs
    print_info "Validating configuration..."
    validate_github_repo
    
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
    
    # Step 2: Create Artifact Buckets
    print_header "Step 2: Setting up Artifact Buckets"
    create_artifact_bucket
    
    # Step 3: Setup CodeStar Connection
    print_header "Step 3: Setting up CodeStar Connection to GitHub"
    setup_codestar_connection
    
    # Step 4: Deploy CodePipeline
    print_header "Step 4: Deploying CodePipelines"
    deploy_codepipeline
    
    # Step 5: Display summary
    print_header "Setup Complete!"
    display_summary
}

# Run main function
trap cleanup EXIT
main
