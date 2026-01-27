#!/bin/bash
# Deployment script for Lambda Monorepo
# This script automates the initial deployment setup

set -e

REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
STACK_NAME="lambda-monorepo-stack"
WEBHOOK_ROLE="webhook-execution-role"

echo "==============================================="
echo "Lambda Monorepo Deployment Script"
echo "==============================================="
echo "Region: $REGION"
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 1: Build SAM template
echo "Step 1: Building SAM template..."
sam build --template template.yaml --region $REGION

# Step 2: Deploy infrastructure
echo "Step 2: Deploying infrastructure stack..."
sam deploy \
  --template-file .aws-sam/build/template.yaml \
  --stack-name $STACK_NAME \
  --s3-bucket lambda-monorepo-artifacts-$ACCOUNT_ID \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $REGION \
  --no-confirm-changeset

echo "Infrastructure deployment complete!"

# Step 3: Get stack outputs
echo "Step 3: Retrieving stack outputs..."
ARTIFACT_BUCKET=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`ArtifactBucketName`].OutputValue' \
  --output text \
  --region $REGION)

LAMBDA1_PIPELINE=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`Lambda1PipelineName`].OutputValue' \
  --output text \
  --region $REGION)

LAMBDA2_PIPELINE=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --query 'Stacks[0].Outputs[?OutputKey==`Lambda2PipelineName`].OutputValue' \
  --output text \
  --region $REGION)

echo "Artifact Bucket: $ARTIFACT_BUCKET"
echo "Lambda1 Pipeline: $LAMBDA1_PIPELINE"
echo "Lambda2 Pipeline: $LAMBDA2_PIPELINE"

# Step 4: Create webhook execution role
echo ""
echo "Step 4: Creating webhook execution role..."
aws iam create-role \
  --role-name $WEBHOOK_ROLE \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "lambda.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }' \
  --region $REGION 2>/dev/null || echo "Role already exists"

# Attach basic Lambda execution policy
aws iam attach-role-policy \
  --role-name $WEBHOOK_ROLE \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
  --region $REGION 2>/dev/null || true

# Add inline policy for CodePipeline
aws iam put-role-policy \
  --role-name $WEBHOOK_ROLE \
  --policy-name codepipeline-trigger \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": \"codepipeline:StartPipelineExecution\",
      \"Resource\": [
        \"arn:aws:codepipeline:$REGION:$ACCOUNT_ID:lambda1-pipeline\",
        \"arn:aws:codepipeline:$REGION:$ACCOUNT_ID:lambda2-pipeline\"
      ]
    }]
  }" \
  --region $REGION

echo "Webhook role created/updated"

# Step 5: Deploy webhook Lambda
echo ""
echo "Step 5: Deploying webhook Lambda..."
cd webhook
pip install -r requirements.txt -t package/ -q
zip -r deployment.zip app.py package/ -q
cd ..

WEBHOOK_ROLE_ARN=$(aws iam get-role --role-name $WEBHOOK_ROLE --query 'Role.Arn' --output text --region $REGION)

aws lambda create-function \
  --function-name webhook \
  --runtime python3.11 \
  --role $WEBHOOK_ROLE_ARN \
  --handler app.lambda_handler \
  --zip-file fileb://webhook/deployment.zip \
  --timeout 60 \
  --environment Variables={GITHUB_WEBHOOK_SECRET=change-me-to-your-secret} \
  --region $REGION 2>/dev/null || \
aws lambda update-function-code \
  --function-name webhook \
  --zip-file fileb://webhook/deployment.zip \
  --region $REGION

echo "Webhook Lambda created/updated"

# Step 6: Enable function URL
echo ""
echo "Step 6: Creating Function URL..."
WEBHOOK_URL=$(aws lambda create-function-url-config \
  --function-name webhook \
  --auth-type NONE \
  --region $REGION 2>/dev/null | jq -r '.FunctionUrl' || \
aws lambda get-function-url-config \
  --function-name webhook \
  --query 'FunctionUrl' \
  --output text \
  --region $REGION)

echo "Webhook URL: $WEBHOOK_URL"

# Summary
echo ""
echo "==============================================="
echo "Deployment Complete!"
echo "==============================================="
echo ""
echo "Next steps:"
echo "1. Update webhook Lambda environment variable:"
echo "   aws lambda update-function-configuration \\"
echo "     --function-name webhook \\"
echo "     --environment Variables={GITHUB_WEBHOOK_SECRET=your-secret} \\"
echo "     --region $REGION"
echo ""
echo "2. Add webhook to GitHub:"
echo "   URL: $WEBHOOK_URL"
echo "   Event: Push events only"
echo "   Secret: (same as GITHUB_WEBHOOK_SECRET)"
echo ""
echo "3. Verify webhook in GitHub Settings → Webhooks"
echo ""
echo "4. Test by pushing changes to your repository"
echo ""
