# GitHub Integration Setup Guide

## Overview

This guide explains how to set up your Lambda monorepo with GitHub as the source control using **AWS CodeStar Connections**. This is the recommended approach as it's more secure than storing GitHub tokens.

## Why CodeStar Connections?

✓ **More Secure**: No need to store GitHub tokens in AWS Parameter Store or environment variables  
✓ **Better UX**: One-time GitHub authorization, managed in AWS Console  
✓ **Production Ready**: AWS best practice for GitHub integration  
✓ **Automatic Token Refresh**: CodeStar handles token management automatically  

## Prerequisites

- AWS account with appropriate permissions
- GitHub account with repository access
- Repository must be public or GitHub account must have access
- AWS CLI configured locally

## Quick Start (3 Steps)

### Step 1: Deploy with GitHub
```bash
export GITHUB_REPO=your-username/your-repo
make setup-github GITHUB_REPO=$GITHUB_REPO
```

### Step 2: Authorize Connection
When the script runs, it will:
1. Create a CodeStar connection
2. Ask you to authorize it in AWS Console
3. Provide a link to the connection authorization page

**In AWS Console**:
- Go to **Developer Tools → Connections**
- Find `github-lambda-monorepo` connection
- Click **Update pending connection**
- Follow GitHub authorization flow
- Return to terminal and press ENTER

### Step 3: Push Code
```bash
git push origin main
```

Pipelines will auto-trigger on code changes!

## Detailed Setup Instructions

### 1. Prepare Your GitHub Repository

**Option A: New Repository**
```bash
# Create new repo on GitHub
git clone https://github.com/your-username/your-repo.git
cd your-repo

# Copy lambda_monorepo contents
cp -r /path/to/lambda_monorepo/* .

# Push to GitHub
git add .
git commit -m "Initial commit: Lambda monorepo setup"
git push origin main
```

**Option B: Existing Repository**
```bash
# Just ensure your repo has the lambda_monorepo structure
git push origin main  # Ensure latest code is pushed
```

### 2. Deploy Infrastructure

```bash
# Set your GitHub repo (format: owner/repo)
export GITHUB_REPO=myusername/my-lambda-repo

# Run setup script
make setup-github GITHUB_REPO=$GITHUB_REPO
```

**What the script does:**
1. ✓ Validates GitHub repo format
2. ✓ Checks AWS CLI configuration
3. ✓ Deploys IAM roles
4. ✓ Creates S3 artifact buckets
5. ✓ Creates CodeStar connection to GitHub
6. ✓ Deploys both pipelines

### 3. Authorize CodeStar Connection

When you see this message:
```
IMPORTANT: You must authorize this connection in AWS Console!
Steps to authorize:
  1. Go to AWS Console → Developer Tools → Connections
  2. Find connection: github-lambda-monorepo
  3. Click 'Update pending connection'
  4. Follow GitHub authorization flow

Press ENTER after authorizing the connection in AWS Console...
```

**In Browser**:
1. Go to AWS Console
2. Search for "Connections" or go to **Developer Tools → Connections**
3. Find `github-lambda-monorepo` (status: Pending authorization)
4. Click **Update pending connection**
5. Click **Connect to GitHub**
6. Authorize AWS to access your GitHub account
7. Select repositories or "All repositories"
8. Click **Connect**
9. Return to terminal and press ENTER

### 4. Verify Setup

```bash
# View Lambda1 pipeline
make status-lambda1

# View Lambda2 pipeline
make status-lambda2

# View both pipelines
make status
```

## Configuration

### Custom Connection Name (Optional)
By default, the connection is named `github-lambda-monorepo`. To use a different name:

```bash
export CODESTAR_CONNECTION_NAME=my-custom-connection
make setup-github GITHUB_REPO=$GITHUB_REPO
```

### Custom GitHub Branch (Optional)
By default, the pipeline watches the `main` branch. To use a different branch:

```bash
export GITHUB_BRANCH=develop
make setup-github GITHUB_REPO=$GITHUB_REPO
```

### Custom AWS Region (Optional)
```bash
export AWS_REGION=us-west-2
make setup-github GITHUB_REPO=$GITHUB_REPO
```

## How It Works

### Pipeline Trigger Flow

```
GitHub Repository
  ├─ lambda1/
  ├─ lambda2/
  ├─ layers/shared/
  └─ ...
      ↓
GitHub Push to 'main' branch
      ↓
CodeStar Connection detects change
      ↓
CodePipeline triggered (Lambda1 or Lambda2 or both)
      ↓
CodeBuild runs buildspec (SAM build + package)
      ↓
CloudFormation deploys via ChangeSet
      ↓
Lambda deployed to dev → staging → production
```

### Pipeline Triggering

**Lambda1 Pipeline Triggers**:
- Changes to `lambda1/` directory
- Changes to `layers/shared/` directory

**Lambda2 Pipeline Triggers**:
- Changes to `lambda2/` directory
- Changes to `layers/shared/` directory

## Monitoring & Management

### View Pipeline Status
```bash
# Both pipelines
make status

# Individual pipelines
make status-lambda1
make status-lambda2
```

### View Build Logs
```bash
# Lambda1 build logs (real-time)
make logs-lambda1

# Lambda2 build logs (real-time)
make logs-lambda2
```

### View Detailed Pipeline State
```bash
make pipeline-status-lambda1
make pipeline-status-lambda2
```

### List All Resources
```bash
make list-stacks
```

## Common Tasks

### Deploy a Fix to Production

```bash
# Make changes to lambda1/app.py
vim lambda1/app.py

# Commit and push
git add lambda1/app.py
git commit -m "Fix Lambda1 bug"
git push origin main

# Monitor pipeline
make status-lambda1
```

### Update Shared Utilities

```bash
# Make changes to shared layer
vim layers/shared/python/utils.py

# Commit and push
git add layers/shared/
git commit -m "Update shared utilities"
git push origin main

# BOTH pipelines will trigger
make status  # View both
```

### Add New Dependency

```bash
# Edit requirements file
vim lambda1/requirements.txt

# Commit and push
git add lambda1/requirements.txt
git commit -m "Add new dependency"
git push origin main

# Pipeline auto-installs and deploys
make logs-lambda1
```

## Troubleshooting

### Connection Not Authorized
**Problem**: Pipeline fails with authorization error
**Solution**:
1. Go to AWS Console → Developer Tools → Connections
2. Find the connection (should show "PENDING" status)
3. Click "Update pending connection"
4. Complete GitHub authorization
5. Wait a few seconds, then retry push

### Pipeline Not Triggering
**Problem**: Code pushed but pipeline didn't start
**Solution**:
1. Verify CodeStar connection is authorized (status: "AVAILABLE")
2. Check that you pushed to the correct branch (default: main)
3. Verify changes are to `lambda1/`, `lambda2/`, or `layers/shared/`
4. Check pipeline logs: `make status-lambda1`

### Build Failures
**Problem**: Build stage fails
**Solution**:
1. Check build logs: `make logs-lambda1`
2. Common issues:
   - Missing dependencies in `requirements.txt`
   - SAM template validation errors (run `sam validate` locally)
   - Buildspec issues (check `buildspec-lambda1.yml`)
3. Fix locally, commit, and push

### CloudFormation Deployment Fails
**Problem**: Deploy stage fails
**Solution**:
1. Check CloudFormation stack events
   ```bash
   aws cloudformation describe-stack-events \
     --stack-name lambda-monorepo-lambda1-stack-dev
   ```
2. Common issues:
   - Lambda execution role permissions
   - Invalid template parameters
   - Timeout (Lambda too large)
3. Fix template, commit, and push

## Advanced Configuration

### Restricting Repository Access

After connecting CodeStar to GitHub:
1. In GitHub settings, you can revoke access to specific repositories
2. In AWS console, the connection shows "AVAILABLE" and can be updated

### Using Different Branches

Each pipeline watches the `main` branch by default. To create separate environments:

**Option 1: Use GitHub branch protection**
- main → production-ready
- develop → staging
- feature/* → dev

**Option 2: Deploy from different branches**
```bash
# Deploy from main (prod environment)
git push origin main

# Create develop branch for staging
git checkout -b develop
git push origin develop

# Would need separate pipeline for develop branch
```

### Multiple Repositories

If you want separate pipelines for different repos:
```bash
# Setup 1
export GITHUB_REPO=owner/repo1
make setup-github

# Setup 2
export GITHUB_REPO=owner/repo2
make setup-github
```

Each will create separate CodePipeline resources.

## Security Best Practices

✓ **Use CodeStar Connections**: Never store GitHub tokens in AWS parameters  
✓ **Limit GitHub Permissions**: Authorize only necessary repositories  
✓ **Use Branch Protection**: Require PR reviews before merging to main  
✓ **Enable GitHub 2FA**: Protect your GitHub account  
✓ **Rotate CodeStar Credentials**: Periodically re-authorize connection  
✓ **Monitor Pipeline Executions**: Review who deployed what and when  

## Integration with GitHub Actions

You can use GitHub Actions alongside CodePipeline:

**Example: Run tests on PR**
```yaml
# .github/workflows/test.yml
name: Test
on: [pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run tests
        run: |
          cd lambda1
          python -m pytest
```

This runs tests before code is merged, and CodePipeline deploys after merge to main.

## Cleanup

### Remove Everything
```bash
make cleanup-all
```

This removes:
- CodePipeline resources
- CodeBuild projects
- S3 artifact buckets
- CloudFormation stacks
- Lambda functions (all environments)
- IAM roles

**Note**: CodeStar connection is not deleted (managed separately in Connections console)

### Remove Just Pipelines
```bash
make cleanup
```

This removes pipelines but keeps:
- Lambda stacks (dev/staging/prod)
- IAM roles
- CodeStar connection

## FAQ

**Q: Do I need to re-authorize the connection after each deployment?**
A: No, the connection persists and can be reused across multiple pipeline updates.

**Q: Can I use the same CodeStar connection for multiple pipelines?**
A: Yes, each pipeline can reference the same connection ARN.

**Q: What happens if my GitHub token expires?**
A: CodeStar handles token refresh automatically. If needed, you can re-authorize in the Connections console.

**Q: Can I use SSH keys instead of CodeStar?**
A: CodeStar is the recommended approach. SSH would require additional configuration.

**Q: How do I switch from CodeCommit to GitHub?**
A: Run `make setup-github GITHUB_REPO=owner/repo` - it will update the pipelines.

## Need Help?

**See Also**:
- [QUICK_START.md](QUICK_START.md) - General deployment guide
- [ARCHITECTURE_SUMMARY.md](ARCHITECTURE_SUMMARY.md) - System architecture
- [CODEPIPELINE_SETUP.md](CODEPIPELINE_SETUP.md) - Complete technical reference

**AWS Documentation**:
- [CodeStar Connections](https://docs.aws.amazon.com/dtconsole/latest/userguide/connections.html)
- [CodePipeline GitHub Integration](https://docs.aws.amazon.com/codepipeline/latest/userguide/integrations-action-type.html#integrations-source-github)
- [CodeStar Connections Troubleshooting](https://docs.aws.amazon.com/dtconsole/latest/userguide/troubleshooting-connections.html)
