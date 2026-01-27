# Pre-Deployment Checklist

Use this checklist before deploying to AWS.

## ✅ Files Created (Verification)

- [ ] [template.yaml](template.yaml) - Main SAM template exists
- [ ] [lambda1/buildspec.yml](lambda1/buildspec.yml) - Lambda1 build spec exists
- [ ] [lambda2/buildspec.yml](lambda2/buildspec.yml) - Lambda2 build spec exists
- [ ] [webhook/app.py](webhook/app.py) - Webhook Lambda exists
- [ ] [webhook/requirements.txt](webhook/requirements.txt) - Webhook dependencies
- [ ] [deploy.sh](deploy.sh) - Deployment script (should be executable)
- [ ] [README.md](README.md) - Project overview
- [ ] [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) - Implementation details
- [ ] [DEPLOYMENT.md](DEPLOYMENT.md) - Step-by-step guide
- [ ] [QUICK_REFERENCE.md](QUICK_REFERENCE.md) - Quick commands

## 🔧 Configuration Updates Required

### 1. template.yaml

- [ ] Line ~87: Replace `RohanKhanal14/lambda_monorepo` with your GitHub repo
  ```yaml
  FullRepositoryId: 'YOUR_USERNAME/YOUR_REPO_NAME'
  ```

- [ ] Line ~94: Replace `YOUR_CONNECTION_ID` with your CodeStar Connection ARN
  ```yaml
  ConnectionArn: 'arn:aws:codestar-connections:REGION:ACCOUNT_ID:connection/YOUR_CONNECTION_ID'
  ```

- [ ] Repeat for lambda2 pipeline (similar lines)

### 2. GitHub Webhook Secret

- [ ] Generate a strong random secret (20+ characters)
  ```bash
  openssl rand -hex 20
  # Save this value
  ```

## 📋 AWS Prerequisites

- [ ] AWS Account with appropriate permissions
- [ ] AWS CLI installed and configured
- [ ] SAM CLI installed
- [ ] GitHub account with repository
- [ ] GitHub Personal Access Token or CodeStar Connection setup

## 🚀 Deployment Steps

### Step 1: Verify Configuration
- [ ] All replacements in template.yaml completed
- [ ] GitHub webhook secret saved
- [ ] deploy.sh is executable: `ls -l deploy.sh | grep x`

### Step 2: Deploy Infrastructure
```bash
chmod +x deploy.sh
./deploy.sh
```
- [ ] SAM build completes successfully
- [ ] CloudFormation stack deploys successfully
- [ ] All AWS resources created

### Step 3: Configure Webhook
- [ ] Copy webhook URL from deploy.sh output
- [ ] Go to GitHub Settings → Webhooks → Add webhook
- [ ] Enter webhook URL
- [ ] Enter webhook secret
- [ ] Select "Push events" only
- [ ] Click "Add webhook"

### Step 4: Test Triggering
- [ ] Make change to `lambda1/` directory
- [ ] Push to repository
- [ ] Check: lambda1-pipeline should execute
- [ ] View logs: `aws logs tail /aws/lambda/webhook --follow`

- [ ] Make change to `layers/shared/` directory
- [ ] Push to repository
- [ ] Check: BOTH pipelines should execute

## 🔍 Post-Deployment Verification

### Check Infrastructure
```bash
# List all stacks
aws cloudformation list-stacks

# Describe the deployed stack
aws cloudformation describe-stacks --stack-name lambda-monorepo-stack

# List Lambda functions
aws lambda list-functions --query 'Functions[?starts_with(FunctionName, `lambda`) || FunctionName==`webhook`]'

# List CodePipelines
aws codepipeline list-pipelines
```

- [ ] Stack status is CREATE_COMPLETE or UPDATE_COMPLETE
- [ ] lambda1 function exists
- [ ] lambda2 function exists
- [ ] webhook function exists
- [ ] lambda1-pipeline exists
- [ ] lambda2-pipeline exists
- [ ] S3 artifact bucket exists

### Check Webhook
```bash
# Get webhook function URL
aws lambda get-function-url-config --function-name webhook
```

- [ ] Function URL is accessible (HTTPS)
- [ ] GitHub webhook shows successful deliveries

### Check Permissions
```bash
# Get webhook execution role
aws iam get-role --role-name webhook-execution-role

# List inline policies
aws iam list-role-policies --role-name webhook-execution-role

# Get policy details
aws iam get-role-policy --role-name webhook-execution-role --policy-name codepipeline-trigger
```

- [ ] webhook-execution-role exists
- [ ] codepipeline-trigger policy attached
- [ ] Policy includes lambda1-pipeline and lambda2-pipeline ARNs

## 🧪 Testing Checklist

### Test 1: Lambda1 Pipeline Trigger
```bash
echo "# test" >> lambda1/app.py
git add lambda1/app.py
git commit -m "test lambda1 trigger"
git push origin main
```

- [ ] Webhook Lambda receives event
- [ ] Webhook Lambda logs show "lambda1-pipeline" in triggered pipelines
- [ ] CodePipeline console shows lambda1-pipeline executing
- [ ] Build stage succeeds (SAM build & package)
- [ ] Deploy stage succeeds (CloudFormation update)

### Test 2: Lambda2 Pipeline Trigger
```bash
echo "# test" >> lambda2/app.py
git add lambda2/app.py
git commit -m "test lambda2 trigger"
git push origin main
```

- [ ] Webhook Lambda receives event
- [ ] Webhook Lambda logs show "lambda2-pipeline" in triggered pipelines
- [ ] CodePipeline console shows lambda2-pipeline executing
- [ ] Build stage succeeds
- [ ] Deploy stage succeeds

### Test 3: Shared Layer Trigger Both
```bash
echo "# test" >> layers/shared/python/logger.py
git add layers/shared/python/logger.py
git commit -m "test shared layer trigger"
git push origin main
```

- [ ] Webhook Lambda receives event
- [ ] Webhook Lambda logs show BOTH pipelines: lambda1-pipeline AND lambda2-pipeline
- [ ] CodePipeline console shows BOTH pipelines executing
- [ ] Both build stages succeed
- [ ] Both deploy stages succeed

### Test 4: Multiple Changes
```bash
echo "# test" >> lambda1/app.py
echo "# test" >> lambda2/app.py
git add lambda1/app.py lambda2/app.py
git commit -m "test both lambdas"
git push origin main
```

- [ ] Webhook Lambda receives event
- [ ] Webhook Lambda logs show BOTH pipelines triggered
- [ ] Both pipelines execute in CodePipeline console

## 🔐 Security Verification

- [ ] GITHUB_WEBHOOK_SECRET set in webhook Lambda environment
- [ ] webhook-execution-role has only required permissions
- [ ] S3 artifact bucket has public access blocked
- [ ] S3 versioning enabled on artifact bucket
- [ ] CloudFormation role uses least privilege
- [ ] No hardcoded credentials in any file
- [ ] GitHub webhook secret configured on GitHub side

## 📊 Monitoring Setup

- [ ] CloudWatch log group `/aws/lambda/webhook` created
- [ ] CloudWatch log group `/aws/lambda/lambda1` created
- [ ] CloudWatch log group `/aws/lambda/lambda2` created
- [ ] CloudWatch log group `/aws/codebuild/lambda1-build` created
- [ ] CloudWatch log group `/aws/codebuild/lambda2-build` created

### View Logs
```bash
# Webhook logs
aws logs tail /aws/lambda/webhook --follow

# Build logs
aws logs tail /aws/codebuild/lambda1-build --follow

# Lambda logs
aws logs tail /aws/lambda/lambda1 --follow
```

## 💰 Cost Review

- [ ] CodePipeline charges: $1/month per pipeline = $2/month
- [ ] CodeBuild charges: Minimal (first 100 build minutes free)
- [ ] S3 charges: Minimal (artifact storage)
- [ ] Lambda charges: Webhook free tier, lambdas depend on usage
- [ ] **Estimated total: $2-3/month**

## ✨ Final Verification

- [ ] All infrastructure deployed
- [ ] All tests passed
- [ ] All monitoring configured
- [ ] All security best practices applied
- [ ] Documentation reviewed and understood
- [ ] Team members notified of new pipeline
- [ ] Runbook updated if applicable

## 🎯 Success Criteria Met

- [ ] Webhook Lambda triggers correct pipelines
- [ ] lambda1 changes → lambda1-pipeline only
- [ ] lambda2 changes → lambda2-pipeline only
- [ ] shared layer changes → BOTH pipelines
- [ ] CodePipeline deploys Lambda functions
- [ ] Shared layer included in deployments
- [ ] All logs accessible in CloudWatch
- [ ] Cost is under $5/month

## 📝 Notes

- [ ] Webhook secret stored securely (consider AWS Secrets Manager)
- [ ] Team members have access to CloudWatch logs
- [ ] Escalation procedures defined for pipeline failures
- [ ] Rollback plan documented if needed
- [ ] Change log updated with deployment info

---

**Before Deployment**: Print this checklist and verify each item
**After Deployment**: Keep this checklist as deployment record

Last Updated: [Add date]
Deployed By: [Add name]
AWS Account: [Add account ID]
AWS Region: [Add region]
