# AWS CodePipeline for Lambda Monorepo - Complete Guide

This is the comprehensive guide for your CodePipeline setup with separate pipelines for Lambda1 and Lambda2, including code explanations and SAM optimization.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [How It Works - Code Explanations](#how-it-works-code-explanations)
4. [Quick Start](#quick-start)
5. [Detailed Setup](#detailed-setup)
6. [Pipeline Configuration](#pipeline-configuration)
7. [SAM Optimization](#sam-optimization)
8. [Troubleshooting](#troubleshooting)
9. [Cleanup](#cleanup)

---

## Overview

### Purpose

Your Lambda monorepo contains two separate Lambda functions (Lambda1 and Lambda2) with shared utilities. To optimize deployment and allow triggering based on code changes per Lambda, separate CodePipeline instances are created:

- **Pipeline1**: Triggered when `lambda1/` changes
- **Pipeline2**: Triggered when `lambda2/` changes
- **Shared Layer**: Updated with both pipelines

### What Gets Deployed

```
Lambda1 Stack (dev/staging/prod)
├─ Lambda1Function
├─ SharedUtilitiesLayer
└─ API Gateway (/lambda1)

Lambda2 Stack (dev/staging/prod)
├─ Lambda2Function
├─ SharedUtilitiesLayer
└─ API Gateway (/lambda2)
```

---

## Architecture

### Pipeline Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Lambda1 CodePipeline                      │
├─────────────────────────────────────────────────────────────┤
│ Source (triggered on lambda1/ changes)                       │
│    ↓                                                          │
│ Build (buildspec-lambda1.yml - SAM build lambda1)          │
│    ↓                                                          │
│ Deploy Dev (automatic) → Deploy Staging → Deploy Prod       │
│             (with manual approvals)                          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                    Lambda2 CodePipeline                      │
├─────────────────────────────────────────────────────────────┤
│ Source (triggered on lambda2/ changes)                       │
│    ↓                                                          │
│ Build (buildspec-lambda2.yml - SAM build lambda2)          │
│    ↓                                                          │
│ Deploy Dev (automatic) → Deploy Staging → Deploy Prod       │
│             (with manual approvals)                          │
└─────────────────────────────────────────────────────────────┘
```

### AWS Resources

```
CodeCommit Repository
├─ lambda1/
│  └─ changes trigger Pipeline1
├─ lambda2/
│  └─ changes trigger Pipeline2
└─ layers/shared/ (changes trigger BOTH)

S3 Artifact Buckets (Separate per Lambda)
├─ lambda-monorepo-lambda1-artifacts-{ACCOUNT_ID}
└─ lambda-monorepo-lambda2-artifacts-{ACCOUNT_ID}

CodePipeline Instances
├─ lambda-monorepo-pipeline-lambda1
│  └─ 7-stage pipeline (Source → Build → Deploy Dev/Staging/Prod)
└─ lambda-monorepo-pipeline-lambda2
   └─ 7-stage pipeline (Source → Build → Deploy Dev/Staging/Prod)

CloudFormation Stacks (per Lambda + per Environment)
├─ lambda-monorepo-lambda1-stack-dev
├─ lambda-monorepo-lambda1-stack-staging
├─ lambda-monorepo-lambda1-stack-prod
├─ lambda-monorepo-lambda2-stack-dev
├─ lambda-monorepo-lambda2-stack-staging
└─ lambda-monorepo-lambda2-stack-prod
```

---

## How It Works - Code Explanations

### 1. buildspec-lambda1.yml

The buildspec file is a YAML file that tells CodeBuild exactly what to do during the build process.

```yaml
version: 0.2  # CodeBuild specification version

phases:
  install:
    runtime-versions:
      python: 3.12  # Use Python 3.12
    commands:
      # Install AWS SAM CLI - this is what packages your Lambda
      - pip install --upgrade pip
      - pip install aws-sam-cli
      
      # Install CloudFormation linter - validates template syntax
      - pip install cfn-lint
      
      # Build Lambda1 dependencies - SAM expects dependencies
      # to be in the same directory as the handler code
      - cd lambda1 && pip install -r requirements.txt -t . && cd ..
      
      # Build shared layer dependencies - packaged separately
      - cd layers/shared && pip install -r requirements.txt -t python/ && cd ../..

  pre_build:
    commands:
      # Validate CloudFormation template - catches syntax errors early
      - cfn-lint template.yaml
      
      # Placeholder for running tests
      - echo "Running unit tests..."

  build:
    commands:
      # SAM BUILD: Converts your Lambda + dependencies into deployment format
      # Input: lambda1/ with all code
      # Output: .aws-sam/build/lambda1/ (optimized, removes test files, etc)
      - sam build --use-container --build-dir ./build
      
      # SAM PACKAGE: Creates S3-ready deployment package
      # 1. Zips the optimized lambda1 code
      # 2. Zips the shared layer
      # 3. Uploads both ZIPs to S3
      # 4. Generates packaged.yaml with S3 URLs
      # CloudFormation then downloads from these S3 URLs during deployment
      - sam package
        --template-file build/template.yaml
        --s3-bucket $ARTIFACT_BUCKET
        --s3-prefix lambda1/$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
        --output-template-file packaged.yaml
        --region $AWS_REGION

  post_build:
    commands:
      - echo "Lambda1 build completed successfully"

artifacts:
  files:
    - packaged.yaml  # The main output - packaged CloudFormation template
  name: Lambda1BuildArtifact

cache:
  paths:
    - '/root/.cache/pip/**/*'  # Cache pip packages for faster subsequent builds

env:
  variables:
    AWS_REGION: us-east-1
    ARTIFACT_BUCKET: lambda-monorepo-lambda1-artifacts
```

**How It Works Step-by-Step:**

1. **Install Phase**: 
   - Sets up SAM CLI and Python tools
   - Downloads and installs all dependencies from requirements.txt
   - Places dependencies in the same directory as Lambda code

2. **Pre-Build Phase**: 
   - Validates CloudFormation template for syntax errors
   - Runs unit tests (if any)

3. **Build Phase** (The Magic):
   - `sam build` compresses your Lambda code optimally (removes unnecessary files)
   - `sam package` uploads the code to S3 and creates a deployment-ready CloudFormation template
   - The packaged.yaml file now has S3 URLs instead of local paths

4. **Artifacts**:
   - Only packaged.yaml is passed to the next stage
   - CodePipeline will give this to CloudFormation for deployment

---

### 2. iam-roles-template.yaml

This file creates three IAM roles with minimal required permissions (principle of least privilege).

**CodePipelineServiceRole** (Orchestrates the pipeline)
```
Permissions:
├─ S3: GetObject, PutObject (artifacts bucket)
├─ CodeBuild: StartBuild, BatchGetBuilds
├─ CloudFormation: Create/Update stacks, Execute ChangeSet
└─ IAM: PassRole to CloudFormation
```

**CodeBuildServiceRole** (Runs the build)
```
Permissions:
├─ CloudWatch Logs: CreateLogGroup, PutLogEvents (for build logs)
├─ S3: GetObject, PutObject (artifacts bucket)
└─ ECR: GetAuthorizationToken (for Docker image)
```

**CloudFormationServiceRole** (Deploys resources)
```
Permissions:
├─ Lambda: CreateFunction, UpdateFunction, DeleteFunction
├─ API Gateway: CreateRestApi, CreateDeployment
├─ IAM: CreateRole, AttachRolePolicy (for Lambda execution role)
├─ CloudWatch: CreateLogGroup (for Lambda logs)
└─ S3: GetObject (to download Lambda code from S3)
```

**Why Separate Roles?**
- Each service only has permissions it needs
- If one service is compromised, others aren't affected
- Makes auditing and security simpler

---

### 3. codepipeline-lambda1-template.yaml

This template creates the actual pipeline with 7 stages.

**How the Pipeline Works:**

**Stage 1: Source**
```
Monitors CodeCommit repository
When lambda1/ directory changes:
  → Pulls entire source code
  → Stores in S3 as SourceOutput artifact
  → Triggers Build stage
```

**Stage 2: Build**
```
CodeBuild executes buildspec-lambda1.yml
Takes SourceOutput from S3
Runs build, test, package steps
Produces packaged.yaml
Stores as BuildOutput artifact
```

**Stage 3: Deploy to Dev (Automatic)**
```
CloudFormation takes packaged.yaml
Creates changeset (shows what will change)
Auto-executes changeset
Result: lambda-monorepo-lambda1-stack-dev deployed
```

**Stage 4: Approval Gate (Manual)**
```
Pipeline STOPS here
Requires human approval in AWS Console
Allow time for testing in dev environment
```

**Stages 5-7: Staging and Prod**
```
Same as Dev:
  → Create ChangeSet → Execute
  → Manual Approval between Staging and Prod
```

**Why ChangeSet?**
Instead of directly updating the stack (risky), CloudFormation:
1. Creates a ChangeSet (preview of changes)
2. Human reviews what will change
3. Human approves
4. Executes the ChangeSet

If something goes wrong before execution, the ChangeSet can be discarded.

---

### 4. setup-pipeline.sh

This bash script automates the entire pipeline deployment.

**What It Does:**

```bash
1. VALIDATION
   ├─ Checks AWS CLI installed and configured
   ├─ Gets your AWS Account ID
   └─ Verifies IAM permissions

2. DEPLOY IAM ROLES
   ├─ Uploads iam-roles-template.yaml to CloudFormation
   ├─ CloudFormation creates the 3 IAM roles
   └─ Waits for completion

3. CREATE S3 BUCKETS
   ├─ Creates lambda-monorepo-lambda1-artifacts-{ACCOUNT_ID}
   ├─ Creates lambda-monorepo-lambda2-artifacts-{ACCOUNT_ID}
   ├─ Enables versioning (keeps old artifacts)
   └─ Sets 30-day retention policy (automatic cleanup)

4. INITIALIZE CODECOMMIT
   ├─ Creates CodeCommit repository (if not exists)
   ├─ Sets up EventBridge rule
   └─ Rule watches for pushes to main branch

5. DEPLOY PIPELINES
   ├─ Uploads codepipeline-lambda1-template.yaml to CloudFormation
   ├─ Uploads codepipeline-lambda2-template.yaml to CloudFormation
   └─ Both pipelines ready and watching for changes

6. DISPLAY SUMMARY
   ├─ Shows all created resources
   └─ Provides console URLs for monitoring
```

**Why Automation?**
- Manual deployment would take 15+ minutes
- Easy to make mistakes manually
- Script ensures consistent setup
- Can be re-run to recreate if needed

---

## Quick Start

### Prerequisites

Make sure you have these installed and configured:

```bash
# AWS CLI
aws --version
aws sts get-caller-identity  # Should show your account ID

# SAM CLI
sam --version

# Git
git --version
```

### One-Command Setup (2-3 minutes)

```bash
cd /home/genese/Desktop/lambda_monorepo

# Make script executable
chmod +x setup-pipeline.sh

# Run the automated setup
./setup-pipeline.sh
```

**What This Creates:**
- ✅ 3 IAM roles
- ✅ 2 S3 buckets (lambda1 and lambda2 artifacts)
- ✅ CodeCommit repository
- ✅ Lambda1 CodePipeline (7 stages)
- ✅ Lambda2 CodePipeline (7 stages)

### After Setup - Trigger Your First Deployment

```bash
# Set up git (first time only)
git config user.email "your@email.com"
git config user.name "Your Name"

# Make a change and push
git add .
git commit -m "Initial CodePipeline setup"
git push origin main

# Both pipelines will automatically start!
```

### Monitor the Pipelines

```bash
# Check Lambda1 Pipeline status
aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda1 \
  --query 'stageStates[*].[stageName,latestExecution.status]' \
  --output table

# Check Lambda2 Pipeline status
aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda2 \
  --query 'stageStates[*].[stageName,latestExecution.status]' \
  --output table

# View build logs in real-time
aws logs tail /aws/codebuild/lambda-monorepo-lambda1-build --follow
aws logs tail /aws/codebuild/lambda-monorepo-lambda2-build --follow
```

---

## Detailed Setup

### Manual Setup (If Preferred)

#### Step 1: Deploy IAM Roles

```bash
aws cloudformation deploy \
  --template-file iam-roles-template.yaml \
  --stack-name lambda-monorepo-iam-roles \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM
```

#### Step 2: Create S3 Artifact Buckets

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Lambda1 Artifacts Bucket
aws s3 mb s3://lambda-monorepo-lambda1-artifacts-${ACCOUNT_ID} --region us-east-1
aws s3api put-bucket-versioning \
  --bucket lambda-monorepo-lambda1-artifacts-${ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

# Lambda2 Artifacts Bucket
aws s3 mb s3://lambda-monorepo-lambda2-artifacts-${ACCOUNT_ID} --region us-east-1
aws s3api put-bucket-versioning \
  --bucket lambda-monorepo-lambda2-artifacts-${ACCOUNT_ID} \
  --versioning-configuration Status=Enabled
```

#### Step 3: Deploy Lambda1 Pipeline

```bash
aws cloudformation deploy \
  --template-file codepipeline-lambda1-template.yaml \
  --stack-name lambda-monorepo-pipeline-lambda1 \
  --region us-east-1
```

#### Step 4: Deploy Lambda2 Pipeline

```bash
aws cloudformation deploy \
  --template-file codepipeline-lambda2-template.yaml \
  --stack-name lambda-monorepo-pipeline-lambda2 \
  --region us-east-1
```

---

## Pipeline Configuration

### How Triggering Works

**Lambda1 Pipeline triggers when:**
- Any file in `lambda1/` directory changes
- Any file in `layers/shared/` directory changes
- Push is to the `main` branch
- CodeCommit event fires → EventBridge rule detects it → Triggers pipeline

**Lambda2 Pipeline triggers when:**
- Any file in `lambda2/` directory changes
- Any file in `layers/shared/` directory changes
- Push is to the `main` branch

### Customizing Trigger Paths

To trigger only on specific files, edit the EventBridge rule in the pipeline template:

```yaml
# In codepipeline-lambda1-template.yaml, update the EventBridge rule:
EventPattern:
  source:
    - aws.codecommit
  detail:
    referenceType:
      - branch
    referenceName:
      - main
    # Add path filtering (optional):
    # - Filter to only trigger on lambda1/ changes
```

### Adding More Environments

To add a QA environment between Staging and Prod:

1. Edit `codepipeline-lambda1-template.yaml`
2. In the `Stages` section, add after `DeployToStaging`:

```yaml
- Name: ApprovalForQA
  Actions:
    - Name: ManualApproval
      ActionTypeId:
        Category: Approval
        Owner: AWS
        Provider: Manual
        Version: '1'

- Name: DeployToQA
  Actions:
    - Name: CreateChangeSet
      ActionTypeId:
        Category: Deploy
        Owner: AWS
        Provider: CloudFormation
        Version: '1'
      Configuration:
        ActionMode: CHANGE_SET_REPLACE
        StackName: lambda-monorepo-lambda1-stack-qa
        ChangeSetName: lambda-monorepo-changeset-qa
        TemplatePath: BuildOutput::packaged_output/packaged.yaml
        Capabilities: CAPABILITY_NAMED_IAM,CAPABILITY_AUTO_EXPAND
        ParameterOverrides: |
          {
            "Environment": "qa"
          }
        RoleArn: !Sub 'arn:aws:iam::${AWS::AccountId}:role/lambda-monorepo-cloudformation-role'
      InputArtifacts:
        - Name: BuildOutput
      RunOrder: 1

    - Name: ExecuteChangeSet
      ActionTypeId:
        Category: Deploy
        Owner: AWS
        Provider: CloudFormation
        Version: '1'
      Configuration:
        ActionMode: CHANGE_SET_EXECUTE
        StackName: lambda-monorepo-lambda1-stack-qa
        ChangeSetName: lambda-monorepo-changeset-qa
      RunOrder: 2
```

3. Update your template.yaml to accept `qa` as an allowed value for Environment parameter

---

## SAM Optimization

### What SAM Does

**SAM Build:**
```
Input Directory: lambda1/
├─ app.py
├─ requirements.txt
└─ installed_dependencies/ (large directory)

Output Directory: build/lambda1/
├─ app.py (same)
├─ dependencies/ (optimized, cleaned up)
└─ (test files and unused packages removed)
```

**SAM Package:**
```
1. Takes optimized code from build/
2. Creates ZIP file (lambda1-code.zip)
3. Uploads ZIP to S3
4. Creates packaged.yaml template with S3 URLs:
   - CodeUri: s3://bucket/lambda1-code.zip
   - Layer ContentUri: s3://bucket/shared-layer.zip

CloudFormation then downloads from S3 during deployment
```

### Why `--use-container`?

```
Without --use-container:
  └─ Build happens on your machine (CodeBuild instance)
  └─ Dependencies might compile differently for Linux

With --use-container:
  └─ Docker creates an isolated Linux environment
  └─ Matches actual Lambda runtime exactly
  └─ Dependencies compile for Lambda runtime
  └─ "Works on my machine" problem avoided
```

### Optimization Tips

**1. Minimize Dependencies**
```
Good:
  requests==2.28.1

Bad:
  pandas==1.5.0  # 100+ MB
  numpy==1.23.0  # 50+ MB
  scipy==1.9.0   # 100+ MB
```

**2. Use Lambda Layers for Shared Code**
```
Your setup already does this:
  layers/shared/python/
  ├─ logger.py
  ├─ utils.py
  └─ requirements.txt

Both Lambda1 and Lambda2 reference this layer
Shared code isn't duplicated in both Lambda packages
```

**3. Monitor Code Size**
```bash
# Check deployed function size
aws lambda get-function --function-name lambda-monorepo-lambda1-dev-Lambda1Function \
  --query 'Configuration.CodeSize'

# Should be under 250 MB (Lambda limit)
# Ideally under 50 MB for acceptable cold start
```

**4. Remove Test Files Before Packaging**
```
requirements.txt:
  # Good - only production dependencies
  requests
  boto3

requirements-dev.txt:
  # Development only
  pytest
  black
  flake8
```

buildspec will only use requirements.txt by default.

---

## Troubleshooting

### Build Fails

**View the build logs:**
```bash
aws logs tail /aws/codebuild/lambda-monorepo-lambda1-build --follow
```

**Common Issues:**

1. **Missing dependency in requirements.txt**
   ```
   Error: ModuleNotFoundError: No module named 'requests'
   
   Fix: Add to lambda1/requirements.txt or layers/shared/requirements.txt
   ```

2. **Syntax error in Python code**
   ```
   Error: SyntaxError: invalid syntax
   
   Fix: Review app.py, fix the error
   ```

3. **SAM CLI version mismatch**
   ```
   Error: SAM CLI version not compatible
   
   Fix: Update buildspec to latest SAM version
   pip install --upgrade aws-sam-cli
   ```

### Deployment Fails

**View CloudFormation events:**
```bash
aws cloudformation describe-stack-events \
  --stack-name lambda-monorepo-lambda1-stack-dev \
  --query 'StackEvents | sort_by(@, &Timestamp) | reverse(@)' \
  --output table
```

**Common Issues:**

1. **IAM Role missing permissions**
   ```
   Error: User is not authorized to perform: lambda:CreateFunction
   
   Fix: Check CloudFormationServiceRole in iam-roles-template.yaml
   ```

2. **Lambda handler path wrong**
   ```
   Error: Handler lambda_handler could not be found
   
   Fix: Verify Handler: app.lambda_handler in template.yaml
   ```

3. **Layer not found**
   ```
   Error: Layer version {arn} does not exist
   
   Fix: Ensure layers/shared/requirements.txt is valid
   ```

### Pipeline Stuck

**Check pipeline status:**
```bash
aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda1
```

**Waiting for approval?**
```
# Get the approval job details
aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda1 \
  --query 'stageStates[?stageName==`ApprovalForStaging`]'

# To approve in Console: https://console.aws.amazon.com/codepipeline/
```

**Stuck on Build?**
```bash
# Check CodeBuild logs
aws logs tail /aws/codebuild/lambda-monorepo-lambda1-build --follow

# If still stuck, manually retry
aws codepipeline start-pipeline-execution \
  --pipeline-name lambda-monorepo-pipeline-lambda1
```

---

## Monitoring

### Real-time Pipeline Status

```bash
# Lambda1 Pipeline
aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda1 \
  --query 'stageStates[*].[stageName,latestExecution.status]' \
  --output table

# Lambda2 Pipeline
aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda2 \
  --query 'stageStates[*].[stageName,latestExecution.status]' \
  --output table
```

### Build Logs

```bash
# Real-time
aws logs tail /aws/codebuild/lambda-monorepo-lambda1-build --follow

# Last 50 lines
aws logs tail /aws/codebuild/lambda-monorepo-lambda1-build --max-items 50
```

### Deployment Status

```bash
# Lambda1 Dev Stack
aws cloudformation describe-stacks \
  --stack-name lambda-monorepo-lambda1-stack-dev

# Lambda2 Prod Stack
aws cloudformation describe-stacks \
  --stack-name lambda-monorepo-lambda2-stack-prod
```

---

## Cleanup

### Remove Everything

```bash
# Delete all Lambda stacks
for env in dev staging prod; do
  aws cloudformation delete-stack --stack-name lambda-monorepo-lambda1-stack-$env
  aws cloudformation delete-stack --stack-name lambda-monorepo-lambda2-stack-$env
done

# Delete pipelines
aws cloudformation delete-stack --stack-name lambda-monorepo-pipeline-lambda1
aws cloudformation delete-stack --stack-name lambda-monorepo-pipeline-lambda2

# Delete IAM roles
aws cloudformation delete-stack --stack-name lambda-monorepo-iam-roles

# Delete S3 buckets
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 rm s3://lambda-monorepo-lambda1-artifacts-${ACCOUNT_ID} --recursive
aws s3 rb s3://lambda-monorepo-lambda1-artifacts-${ACCOUNT_ID}
aws s3 rm s3://lambda-monorepo-lambda2-artifacts-${ACCOUNT_ID} --recursive
aws s3 rb s3://lambda-monorepo-lambda2-artifacts-${ACCOUNT_ID}
```

---

## Key Concepts

### CloudFormation Change Sets - Why?

```
WITHOUT ChangeSet (risky):
  Deploy Code → Immediately Update Stack → Might fail mid-deployment
  If fails: Stack left in bad state

WITH ChangeSet (safe):
  Deploy Code → Create ChangeSet (preview) → Review → Approve → Apply
  If something wrong: Discard ChangeSet, no changes applied
```

### SAM vs CloudFormation

```
SAM (Serverless Application Model):
  └─ Simpler syntax
  └─ Shorthand for Lambda/API Gateway patterns
  └─ sam build & sam package automate packaging

CloudFormation:
  └─ What SAM compiles to
  └─ More verbose but more powerful
  └─ Actually deploys your resources
```

### EventBridge Auto-Trigger

```
Without EventBridge:
  1. Developer pushes code
  2. Developer remembers to start pipeline (easy to forget!)
  3. Deployment starts

WITH EventBridge (automatic):
  1. Developer pushes code
  2. CodeCommit fires event
  3. EventBridge rule detects event
  4. EventBridge auto-triggers CodePipeline
  5. Deployment starts immediately (zero manual steps)
```

---

## File Structure

```
lambda_monorepo/
├── buildspec-lambda1.yml        # Lambda1 build config
├── buildspec-lambda2.yml        # Lambda2 build config
├── iam-roles-template.yaml      # IAM roles
├── codepipeline-lambda1-template.yaml   # Lambda1 pipeline
├── codepipeline-lambda2-template.yaml   # Lambda2 pipeline
├── setup-pipeline.sh            # Automated setup
├── Makefile                     # Convenience commands
├── template.yaml                # Main SAM template
├── lambda1/
│   ├── app.py
│   └── requirements.txt
├── lambda2/
│   ├── app.py
│   └── requirements.txt
└── layers/shared/
    ├── python/
    │   ├── logger.py
    │   └── utils.py
    └── requirements.txt
```

---

## Summary

Your CodePipeline setup provides:

✅ **Separate pipelines** - Lambda1 and Lambda2 deploy independently
✅ **Auto-triggering** - Pipelines start automatically on code push
✅ **Multi-environment** - Dev → Staging → Prod with approvals
✅ **SAM optimization** - Uses SAM for proper build and package
✅ **Least privilege** - IAM roles with minimal permissions
✅ **Change sets** - Safe deployment with review capability
✅ **Artifact management** - Versioned S3 buckets per Lambda
✅ **Comprehensive logging** - CloudWatch logs for debugging

**Get Started:**

```bash
./setup-pipeline.sh
git add .
git commit -m "Deploy Lambda pipelines"
git push origin main
```

Monitor: `aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda1`
