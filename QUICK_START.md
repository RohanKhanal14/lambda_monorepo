# Quick Start Guide

## 📖 Read First

1. **[ARCHITECTURE_SUMMARY.md](ARCHITECTURE_SUMMARY.md)** - Overview of how pipelines work (5 min read)
2. **[CODEPIPELINE_SETUP.md](CODEPIPELINE_SETUP.md)** - Detailed explanations of each component (comprehensive reference)

## 🚀 Deploy in 3 Steps

### Step 1: Deploy Infrastructure
```bash
make setup
```
This command:
- Creates IAM roles with minimal permissions
- Creates S3 buckets for Lambda1 and Lambda2 artifacts
- Sets up CodeCommit repository
- Deploys separate CodePipeline for Lambda1
- Deploys separate CodePipeline for Lambda2

### Step 2: Push Code to CodeCommit
```bash
git push origin main
```

### Step 3: Monitor Pipelines
```bash
# View both pipelines
make status

# View Lambda1 pipeline
make status-lambda1

# View Lambda2 pipeline
make status-lambda2

# Stream build logs
make logs-lambda1
make logs-lambda2
```

## 📊 Monitor & Manage

### Check Pipeline Status
```bash
# Both pipelines
make status

# Individual pipelines
make status-lambda1
make status-lambda2

# Detailed state
make pipeline-status-lambda1
make pipeline-status-lambda2
```

### View Build Logs
```bash
# Lambda1 build logs (real-time streaming)
make logs-lambda1

# Lambda2 build logs (real-time streaming)
make logs-lambda2
```

### List All Resources
```bash
# All CloudFormation stacks
make list-stacks
```

## 🧹 Cleanup

### Remove Pipelines (Keep Lambda Stacks)
```bash
make cleanup
```
This removes:
- CodePipeline infrastructure
- CodeBuild projects
- S3 artifact buckets

Lambda functions in dev/staging/prod remain deployed.

### Remove Everything (Nuclear Option)
```bash
make cleanup-all
```
⚠️ **Warning**: Deletes everything including Lambda stacks in all environments!

## 🎯 Key Points

### Independent Pipelines
- **Lambda1 pipeline** triggers on changes to `lambda1/` or `layers/shared/`
- **Lambda2 pipeline** triggers on changes to `lambda2/` or `layers/shared/`
- Changing Lambda1 does NOT trigger Lambda2 (unless shared layer changed)

### Deployment Flow per Pipeline
```
Code Push → Build (SAM) → Dev Deploy → Staging Approval → 
Staging Deploy → Prod Approval → Prod Deploy
```

### Build Process (SAM)
1. **Install**: Dependencies for the Lambda (lambda1/ or lambda2/)
2. **Build**: `sam build --use-container` (optimizes code for Lambda runtime)
3. **Package**: `sam package` (uploads to S3, generates template with S3 URLs)
4. **Deploy**: CloudFormation deploys Lambda to dev/staging/prod

### Shared Layer
Changes to `layers/shared/` trigger **BOTH** pipelines:
- Contains utilities used by Lambda1 and Lambda2
- Deployed as Lambda Layer (reusable, optimized)

## 📝 Useful AWS CLI Commands

### View Lambda1 Pipeline
```bash
aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda1 --region us-east-1
```

### View Lambda2 Pipeline
```bash
aws codepipeline get-pipeline-state --name lambda-monorepo-pipeline-lambda2 --region us-east-1
```

### List Lambda1 Stack History
```bash
aws cloudformation describe-stacks \
  --stack-name lambda-monorepo-lambda1-stack-dev \
  --region us-east-1
```

### View Build Logs
```bash
# Lambda1 logs
aws logs tail /aws/codebuild/lambda-monorepo-lambda1-build --region us-east-1 --follow

# Lambda2 logs
aws logs tail /aws/codebuild/lambda-monorepo-lambda2-build --region us-east-1 --follow
```

## 🔍 Troubleshooting

### Pipeline Stuck?
Check build logs:
```bash
make logs-lambda1   # or make logs-lambda2
```

### Lambda not updating?
1. Verify code was pushed: `git log` on CodeCommit
2. Check pipeline status: `make status-lambda1`
3. View build logs: `make logs-lambda1`
4. Common issues:
   - Dependency installation failures → Check `lambda1/requirements.txt`
   - SAM validation errors → Run `sam validate --template template.yaml` locally
   - Deployment failures → Check CloudFormation stack events

### Need to redeploy?
Just push code again:
```bash
git push origin main
```
Pipeline auto-triggers on code changes.

## 📂 File Reference

| File | Purpose |
|------|---------|
| `ARCHITECTURE_SUMMARY.md` | High-level overview (START HERE) |
| `CODEPIPELINE_SETUP.md` | Comprehensive technical guide |
| `buildspec-lambda1.yml` | Build instructions for Lambda1 |
| `buildspec-lambda2.yml` | Build instructions for Lambda2 |
| `codepipeline-lambda1-template.yaml` | Lambda1 pipeline infrastructure |
| `codepipeline-lambda2-template.yaml` | Lambda2 pipeline infrastructure |
| `iam-roles-template.yaml` | Shared IAM roles |
| `setup-pipeline.sh` | Automated deployment script |
| `Makefile` | Management commands |
| `template.yaml` | Root SAM template |
| `samconfig.toml` | SAM build configuration |

## ⚡ Common Tasks

### Deploy a fix to Lambda1 production
```bash
# Make changes to lambda1/app.py
git add lambda1/app.py
git commit -m "Fix Lambda1 bug"
git push origin main

# Pipeline auto-triggers, goes through dev → staging → prod approvals
# Monitor with:
make status-lambda1
```

### Update shared utilities
```bash
# Make changes to layers/shared/python/utils.py
git add layers/shared/
git commit -m "Update shared utilities"
git push origin main

# BOTH Lambda1 and Lambda2 pipelines trigger
make status          # View both
```

### Add new dependency
```bash
# Edit lambda1/requirements.txt or lambda2/requirements.txt
# Push code
git add lambda1/requirements.txt
git commit -m "Add new dependency"
git push origin main

# Pipeline auto-installs dependency and deploys
make logs-lambda1    # Watch installation
```

## 📞 Questions?

See **[CODEPIPELINE_SETUP.md](CODEPIPELINE_SETUP.md)** for:
- How SAM build process works
- How CloudFormation ChangeSet deployment works
- Detailed IAM permission breakdown
- Troubleshooting guide
- SAM optimization strategies
- Architecture diagrams

---

**That's it!** You now have two independent, production-ready Lambda deployment pipelines.
