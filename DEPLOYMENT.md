# Lambda Monorepo Deployment Guide

## Overview

This guide walks through deploying the Lambda monorepo with CodePipeline and CodeBuild for automated builds and deployments.

### Architecture

```
GitHub Push Event
        ↓
   Webhook Lambda (GitHub Webhook)
        ↓
  Parse Changed Files
        ↓
  Determine Pipelines to Trigger
        ↓
  Start CodePipeline Executions
        ├→ Lambda1-Pipeline
        │   ├→ Source: GitHub
        │   ├→ Build: CodeBuild (sam build && sam package)
        │   └→ Deploy: CloudFormation
        │
        └→ Lambda2-Pipeline
            ├→ Source: GitHub
            ├→ Build: CodeBuild (sam build && sam package)
            └→ Deploy: CloudFormation
```

## Prerequisites

1. **AWS Account** with appropriate permissions
2. **Git Repository** on GitHub with webhook capability
3. **AWS CLI** installed and configured
4. **SAM CLI** installed locally (for testing)
5. **Python 3.11** or higher

## Step 1: Set Up GitHub Connection

### Option A: Using AWS CodeStar Connections (Recommended)

```bash
# Create a connection to GitHub
aws codestar-connections create-connection \
  --provider-type GitHub \
  --connection-name lambda-monorepo-connection \
  --region us-east-1

# The command returns a connectionArn. Store this.
# Example: arn:aws:codestar-connections:us-east-1:123456789:connection/abc123
```

After creating the connection, you must authorize it by visiting the AWS Console → CodeStar → Connections and authorizing GitHub access.

### Option B: GitHub Personal Access Token

If using CodePipeline with GitHub provider (v1):
1. Generate GitHub PAT with `repo` and `admin:repo_hook` permissions
2. Store in AWS Secrets Manager

## Step 2: Deploy Infrastructure with SAM

### 2a. Update template.yaml

Replace the placeholder connection ARN:

```bash
# Edit template.yaml and replace:
# YOUR_CONNECTION_ID with your actual connection ARN from Step 1
# RohanKhanal14/lambda_monorepo with your GitHub user/repo
```

### 2b. Deploy the CloudFormation Stack

```bash
# Build the SAM template
sam build --template template.yaml

# Deploy to AWS
sam deploy \
  --template-file .aws-sam/build/template.yaml \
  --stack-name lambda-monorepo-stack \
  --s3-bucket lambda-monorepo-artifacts-ACCOUNT_ID \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1 \
  --no-confirm-changeset

# OR use AWS CLI directly
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name lambda-monorepo-stack \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_IAM \
  --region us-east-1 \
  --parameter-overrides \
    EnvironmentName=prod
```

### 2c. Verify Deployment

```bash
# Check stack status
aws cloudformation describe-stacks \
  --stack-name lambda-monorepo-stack \
  --query 'Stacks[0].StackStatus' \
  --region us-east-1

# Get output values
aws cloudformation describe-stacks \
  --stack-name lambda-monorepo-stack \
  --query 'Stacks[0].Outputs' \
  --region us-east-1
```

## Step 3: Deploy Webhook Lambda

The webhook Lambda is NOT included in the main SAM template (to avoid circular dependencies). Deploy it separately:

### 3a. Create Webhook Execution Role

```bash
# Create the role
aws iam create-role \
  --role-name webhook-execution-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' \
  --region us-east-1

# Attach basic Lambda execution policy
aws iam attach-role-policy \
  --role-name webhook-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  --region us-east-1

# Add inline policy for CodePipeline
aws iam put-role-policy \
  --role-name webhook-execution-role \
  --policy-name codepipeline-trigger \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": "codepipeline:StartPipelineExecution",
      "Resource": [
        "arn:aws:codepipeline:us-east-1:ACCOUNT_ID:lambda1-pipeline",
        "arn:aws:codepipeline:us-east-1:ACCOUNT_ID:lambda2-pipeline"
      ]
    }]
  }' \
  --region us-east-1
```

### 3b. Deploy Webhook Lambda Function

```bash
# Package webhook
cd webhook
pip install -r requirements.txt -t package/
zip -r deployment.zip app.py package/
cd ..

# Create Lambda function
WEBHOOK_ROLE_ARN=$(aws iam get-role --role-name webhook-execution-role --query 'Role.Arn' --output text)

aws lambda create-function \
  --function-name webhook \
  --runtime python3.11 \
  --role $WEBHOOK_ROLE_ARN \
  --handler app.lambda_handler \
  --zip-file fileb://webhook/deployment.zip \
  --timeout 60 \
  --environment Variables={GITHUB_WEBHOOK_SECRET=your-github-webhook-secret} \
  --region us-east-1

# OR update if already exists
aws lambda update-function-code \
  --function-name webhook \
  --zip-file fileb://webhook/deployment.zip \
  --region us-east-1

# Update environment variables
aws lambda update-function-configuration \
  --function-name webhook \
  --environment Variables={GITHUB_WEBHOOK_SECRET=your-github-webhook-secret} \
  --region us-east-1
```

### 3c. Create Lambda Function URL

```bash
# Enable Function URL for webhook
aws lambda create-function-url-config \
  --function-name webhook \
  --auth-type NONE \
  --region us-east-1

# Get the Function URL
WEBHOOK_URL=$(aws lambda get-function-url-config \
  --function-name webhook \
  --query 'FunctionUrl' \
  --output text \
  --region us-east-1)

echo "Webhook URL: $WEBHOOK_URL"
```

## Step 4: Configure GitHub Webhook

### 4a. Get Webhook URL

```bash
# Use the WEBHOOK_URL from previous step
echo $WEBHOOK_URL
# Example: https://abc123.lambda-url.us-east-1.on.aws/
```

### 4b. Add Webhook to GitHub Repository

1. Go to your GitHub repository
2. Navigate to **Settings** → **Webhooks**
3. Click **Add webhook**
4. Fill in:
   - **Payload URL**: Paste the webhook URL from above
   - **Content type**: `application/json`
   - **Secret**: Use your `GITHUB_WEBHOOK_SECRET` value
   - **Events**: Select "Push events" only
   - **Active**: Check the box
5. Click **Add webhook**

### 4c. Test the Webhook

```bash
# View webhook deliveries in GitHub UI
# Settings → Webhooks → Recent Deliveries

# Or test manually:
curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen":"test"}'
```

## Step 5: Verify Pipeline Triggers

### 5a. Test Trigger Logic

Make a commit and push to test:

```bash
# Test 1: Modify lambda1 only
echo "test" >> lambda1/app.py
git add lambda1/app.py
git commit -m "Test lambda1 trigger"
git push origin main

# Check: Only lambda1-pipeline should execute
```

```bash
# Test 2: Modify shared layer
echo "# test" >> layers/shared/python/logger.py
git add layers/shared/python/logger.py
git commit -m "Test shared layer trigger"
git push origin main

# Check: Both lambda1-pipeline AND lambda2-pipeline should execute
```

### 5b: Monitor Pipeline Execution

```bash
# List pipeline executions
aws codepipeline list-pipeline-executions \
  --pipeline-name lambda1-pipeline \
  --region us-east-1

# Get detailed pipeline status
aws codepipeline get-pipeline-state \
  --name lambda1-pipeline \
  --region us-east-1

# View CodeBuild logs
aws logs tail /aws/codebuild/lambda1-build --follow --region us-east-1

# View Lambda logs
aws logs tail /aws/lambda/lambda1 --follow --region us-east-1
```

## Step 6: Troubleshooting

### Issue: Webhook not triggering pipelines

1. Check webhook delivery in GitHub settings
2. Verify signature verification in webhook logs:
   ```bash
   aws logs tail /aws/lambda/webhook --follow --region us-east-1
   ```
3. Confirm GITHUB_WEBHOOK_SECRET is set correctly
4. Check IAM permissions for webhook Lambda

### Issue: CodeBuild failing

1. Check buildspec.yml syntax
2. View CodeBuild logs:
   ```bash
   aws logs tail /aws/codebuild/lambda1-build --follow --region us-east-1
   ```
3. Ensure S3 bucket exists for artifacts
4. Verify CodeBuild IAM role has S3 permissions

### Issue: CloudFormation deployment failing

1. Check CloudFormation events:
   ```bash
   aws cloudformation describe-stack-events \
     --stack-name lambda1-stack \
     --region us-east-1
   ```
2. Review CloudFormation role permissions
3. Check template.yaml syntax
4. Ensure Lambda code is accessible in S3

### Issue: SAM package failing

1. Verify dependencies in requirements.txt
2. Check S3 bucket for artifacts exists
3. Ensure buildspec.yml paths are correct
4. Test locally: `sam build --use-container`

## File Structure After Deployment

```
lambda_monorepo/
├── template.yaml                 # Main SAM template (all infrastructure)
├── lambda1/
│   ├── app.py
│   ├── requirements.txt
│   └── buildspec.yml             # Build commands for lambda1
├── lambda2/
│   ├── app.py
│   ├── requirements.txt
│   └── buildspec.yml             # Build commands for lambda2
├── layers/
│   └── shared/
│       ├── python/
│       │   ├── logger.py
│       │   └── utils.py
│       └── requirements.txt
├── webhook/
│   ├── app.py                    # Webhook Lambda (deployed separately)
│   └── requirements.txt
├── IAM_POLICIES.md               # Policy reference
└── DEPLOYMENT.md                 # This file
```

## Cost Considerations

- **CodePipeline**: $1 per active pipeline per month
- **CodeBuild**: $0.005 per build minute (minimal for this setup)
- **S3**: Negligible for artifacts (~$0.023/GB stored)
- **Lambda (webhook)**: Free tier covers ~1M invocations/month
- **Lambda (lambda1, lambda2)**: Depends on usage

Estimated monthly cost: **$2-3** (mostly pipeline charges)

## Next Steps

1. Add more stages (e.g., Test, Staging, Production)
2. Implement notifications (SNS, CloudWatch alarms)
3. Add approval gates before deployment
4. Set up monitoring dashboards
5. Implement canary deployments

## References

- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [CodePipeline Documentation](https://docs.aws.amazon.com/codepipeline/)
- [CodeBuild Documentation](https://docs.aws.amazon.com/codebuild/)
- [GitHub Webhooks](https://docs.github.com/en/developers/webhooks-and-events/webhooks)
