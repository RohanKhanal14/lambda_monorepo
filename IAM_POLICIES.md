# IAM Policies for Lambda Monorepo with CodePipeline

This document outlines the IAM policies required for the Lambda monorepo deployment pipeline.

## 1. Webhook Lambda Execution Role Policy

The webhook Lambda needs permissions to start CodePipeline executions.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowStartPipelineExecution",
      "Effect": "Allow",
      "Action": [
        "codepipeline:StartPipelineExecution"
      ],
      "Resource": [
        "arn:aws:codepipeline:REGION:ACCOUNT_ID:lambda1-pipeline",
        "arn:aws:codepipeline:REGION:ACCOUNT_ID:lambda2-pipeline"
      ]
    },
    {
      "Sid": "AllowCloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:REGION:ACCOUNT_ID:log-group:/aws/lambda/webhook-*"
    }
  ]
}
```

**Trust Policy** (for webhook Lambda execution role):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

## 2. CodePipeline Role Policy

Defined in template.yaml. Includes:
- S3 access for artifacts
- CodeBuild integration
- CloudFormation stack management
- IAM PassRole for CloudFormation

## 3. CloudFormation Execution Role Policy

Uses `AdministratorAccess` policy (in template.yaml for simplicity). In production:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "lambda:*",
        "logs:*",
        "s3:*",
        "cloudformation:*",
        "iam:*",
        "codebuild:*"
      ],
      "Resource": "*"
    }
  ]
}
```

## 4. CodeBuild Role Policy

Defined in template.yaml. Includes:
- CloudWatch Logs creation/writing
- S3 artifact access
- Access to pull source from CodePipeline

## Environment Variables for Webhook Lambda

Set these when creating the webhook Lambda:

```
GITHUB_WEBHOOK_SECRET=your-github-webhook-secret-here
```

## AWS CLI Commands to Deploy

```bash
# 1. Deploy the SAM template
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name lambda-monorepo-stack \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# 2. Get webhook Lambda ARN
aws lambda list-functions --query "Functions[?FunctionName=='webhook'].Arn"

# 3. Update webhook Lambda environment variables
aws lambda update-function-configuration \
  --function-name webhook \
  --environment Variables={GITHUB_WEBHOOK_SECRET=your-secret} \
  --region us-east-1

# 4. Attach inline policy to webhook Lambda execution role
aws iam put-role-policy \
  --role-name webhook-execution-role \
  --policy-name codepipeline-trigger \
  --policy-document file://webhook-policy.json
```

## Minimum Required Permissions Summary

| Component | Required Permissions |
|-----------|----------------------|
| **Webhook Lambda** | `codepipeline:StartPipelineExecution`, CloudWatch Logs |
| **CodePipeline** | S3, CodeBuild, CloudFormation, IAM PassRole |
| **CloudFormation** | Lambda, Logs, S3, CodeBuild, IAM |
| **CodeBuild** | CloudWatch Logs, S3 |

## Security Best Practices

1. **Least Privilege**: The template already follows this for most roles
2. **Resource ARNs**: Restrict to specific pipelines (lambda1-pipeline, lambda2-pipeline)
3. **KMS Encryption**: Add for S3 artifact bucket and encryption at rest
4. **VPC**: Deploy Lambda in VPC for better isolation
5. **Secrets Manager**: Store `GITHUB_WEBHOOK_SECRET` in Secrets Manager instead of env vars
