# Lambda Monorepo - Architecture & Pipeline Summary

## Overview

This monorepo contains **two separate Lambda functions** (Lambda1 and Lambda2) with **independent CodePipeline deployments**. Each Lambda has its own build pipeline that triggers on code changes to its respective directory.

## Final Project Structure

```
lambda_monorepo/
├── CODEPIPELINE_SETUP.md          # Comprehensive guide (START HERE)
├── ARCHITECTURE_SUMMARY.md         # This file
├── iam-roles-template.yaml         # Shared IAM roles for pipelines
├── codepipeline-lambda1-template.yaml   # Lambda1 pipeline infrastructure
├── codepipeline-lambda2-template.yaml   # Lambda2 pipeline infrastructure
├── buildspec-lambda1.yml           # Lambda1 build configuration
├── buildspec-lambda2.yml           # Lambda2 build configuration
├── setup-pipeline.sh               # Automated deployment script
├── Makefile                        # Management commands
├── template.yaml                   # Root SAM template
├── samconfig.toml                  # SAM configuration
├── lambda1/
│   ├── app.py                      # Lambda1 handler code
│   └── requirements.txt            # Lambda1 dependencies
├── lambda2/
│   ├── app.py                      # Lambda2 handler code
│   └── requirements.txt            # Lambda2 dependencies
└── layers/
    └── shared/
        ├── requirements.txt        # Shared layer dependencies
        └── python/
            ├── logger.py           # Shared logging utility
            └── utils.py            # Shared utilities
```

## How It Works

### 1. **Separate Pipelines**

Each Lambda has a **dedicated CodePipeline**:

- **Lambda1 Pipeline**: `lambda-monorepo-pipeline-lambda1`
  - Triggers on changes to: `lambda1/` or `layers/shared/`
  - Build project: `lambda-monorepo-lambda1-build`
  - Artifacts bucket: `lambda-monorepo-lambda1-artifacts-{ACCOUNT_ID}`
  
- **Lambda2 Pipeline**: `lambda-monorepo-pipeline-lambda2`
  - Triggers on changes to: `lambda2/` or `layers/shared/`
  - Build project: `lambda-monorepo-lambda2-build`
  - Artifacts bucket: `lambda-monorepo-lambda2-artifacts-{ACCOUNT_ID}`

### 2. **Build Process (SAM)**

Each buildspec file (`buildspec-lambda1.yml`, `buildspec-lambda2.yml`):

1. **Install Phase**: Installs Lambda dependencies
   ```bash
   cd lambda1 && pip install -r requirements.txt -t .
   ```
   This installs packages directly into the Lambda directory, preparing them for deployment.

2. **Pre-build Phase**: Validates SAM template
   ```bash
   sam validate --template template.yaml
   ```

3. **Build Phase**: 
   - **SAM Build**: `sam build --use-container --build-dir ./build`
     - `--use-container`: Runs build in Docker to match Lambda runtime environment (Python 3.12)
     - Optimizes code: removes test files, compiles dependencies for Lambda
     - Creates optimized `build/` directory
   
   - **SAM Package**: `sam package --s3-bucket {bucket} --output-template-file packaged.yaml`
     - Zips code and uploads to S3
     - Replaces code paths in CloudFormation template with S3 URLs
     - Generates `packaged.yaml` (S3-ready template)

4. **Post-build Phase**: Uploads packaged template and code to S3

### 3. **Deployment Process (CloudFormation)**

Each pipeline has 7 stages:

1. **Source**: Pulls code from CodeCommit
2. **Build**: Runs buildspec, creates packaged SAM template
3. **DeployToDev**: Creates/updates dev Lambda stack
4. **ApprovalForStaging**: Manual approval (prevents auto-deployment)
5. **DeployToStaging**: Creates/updates staging Lambda stack
6. **ApprovalForProduction**: Manual approval
7. **DeployToProduction**: Creates/updates production Lambda stack

**CloudFormation Strategy**: Uses **ChangeSet pattern**
- Creates ChangeSet (preview of changes)
- Executes ChangeSet (applies changes)
- Safe: Can review changes before executing

Stack names:
- Lambda1: `lambda-monorepo-lambda1-stack-{dev|staging|prod}`
- Lambda2: `lambda-monorepo-lambda2-stack-{dev|staging|prod}`

### 4. **IAM Permissions**

Three IAM roles (defined in `iam-roles-template.yaml`):

1. **CodePipelineServiceRole**: Orchestrates pipeline stages
   - S3: Read/write artifacts
   - CodeBuild: Start builds
   - CloudFormation: Deploy stacks

2. **CodeBuildServiceRole**: Executes build commands
   - CloudWatch Logs: Write build logs
   - S3: Upload packaged code
   - ECR: Pull Docker images for SAM builds

3. **CloudFormationServiceRole**: Deploys Lambda stacks
   - Lambda: Create/update functions
   - IAM: Attach execution roles
   - API Gateway: Create APIs (if templates define them)

All roles use **least-privilege principle**: Only permissions required for their specific task.

### 5. **Shared Layer**

Located in `layers/shared/`:
- Contains utilities used by both Lambda1 and Lambda2
- Changes to shared layer trigger **BOTH** pipelines
- Packaged as Lambda Layer (optimized, reusable code)

## Deployment Flow

```
Developer pushes code to CodeCommit
        ↓
EventBridge detects change (in lambda1/ or lambda2/)
        ↓
CodePipeline triggers (Lambda1 or Lambda2 pipeline)
        ↓
CodeBuild runs buildspec:
  - Installs dependencies
  - Validates SAM template
  - Runs "sam build" (Docker)
  - Runs "sam package" (uploads to S3)
        ↓
CloudFormation creates ChangeSet (preview)
        ↓
CloudFormation executes ChangeSet (applies)
        ↓
Lambda function updated in dev environment
        ↓
Manual approval required (staging & production)
        ↓
Automatic deployment to staging, then production
```

## Key Technologies & Concepts

### SAM (Serverless Application Model)
- **sam build**: Optimizes code for Lambda runtime, removes test files
- **sam package**: Uploads code to S3, generates CloudFormation template with S3 URLs
- **--use-container**: Builds in Docker to ensure dependencies compile for Lambda's Linux environment
- **Output template**: `packaged.yaml` is S3-ready (all code references point to S3)

### CloudFormation
- **ChangeSet**: Preview changes before applying (safer than direct updates)
- **Stack names**: Unique per Lambda and per environment
- **Managed by CodePipeline**: Automatic creation and updates

### CodePipeline
- **Separate pipelines**: Lambda1 and Lambda2 deployments are independent
- **Auto-triggering**: EventBridge watches CodeCommit for changes
- **Multi-stage**: Source → Build → Dev → Staging Approval → Staging → Prod Approval → Production

### CodeCommit
- Central source repository (alternative to GitHub)
- EventBridge triggers pipelines on push events

## Management Commands

### Setup
```bash
make setup                  # Deploy everything (pipelines, IAM, CodeCommit)
make setup-codecommit       # Setup with CodeCommit explicitly
```

### Monitor Pipelines
```bash
make status                 # View both pipelines
make status-lambda1         # View Lambda1 pipeline
make status-lambda2         # View Lambda2 pipeline
```

### View Logs
```bash
make logs-lambda1           # Stream Lambda1 build logs
make logs-lambda2           # Stream Lambda2 build logs
```

### Cleanup
```bash
make cleanup                # Remove pipelines (keeps Lambda stacks)
make cleanup-all            # Remove everything (careful!)
```

## Triggering

**Lambda1 pipeline triggers when:**
- Code changes in `lambda1/` directory
- Code changes in `layers/shared/` directory

**Lambda2 pipeline triggers when:**
- Code changes in `lambda2/` directory
- Code changes in `layers/shared/` directory

**Both trigger independently**: Changing Lambda1 does NOT trigger Lambda2 pipeline (unless shared layer changed).

## Detailed Documentation

For in-depth explanations of:
- How buildspec files work
- IAM role permissions breakdown
- Pipeline configuration details
- SAM optimization strategies
- Troubleshooting common issues

**See [CODEPIPELINE_SETUP.md](CODEPIPELINE_SETUP.md)** - The comprehensive guide.

## Quick Start

1. **Deploy infrastructure:**
   ```bash
   make setup
   ```

2. **Push code to CodeCommit:**
   ```bash
   git push origin main
   ```

3. **Monitor pipelines:**
   ```bash
   make status
   ```

4. **View logs:**
   ```bash
   make logs-lambda1
   ```

## Next Steps

1. Configure CodeCommit repository URL and push code
2. Configure approval notifications (SNS for Slack/Email)
3. Set up Lambda Layer versioning strategy
4. Configure CloudWatch alarms for failed deployments
5. Setup auto-rollback on deployment failures (optional)

---

**Questions?** See [CODEPIPELINE_SETUP.md](CODEPIPELINE_SETUP.md) for detailed explanations of how each component works.
