# AWS Deployment Guide

## Prerequisites

- AWS Account with appropriate permissions
- AWS CLI configured: `aws configure`
- SAM CLI installed: `pip install aws-sam-cli`
- Docker installed (for local testing)

## Step 1: Build the Application

```bash
cd /home/genese/Desktop/lambda_monorepo
sam build
```

Expected output:
```
Build Succeeded
Built Artifacts  : .aws-sam/build
Built Template   : .aws-sam/build/template.yaml
```

## Step 2: Deploy to AWS (First Time)

```bash
sam deploy --guided
```

You'll be prompted for:

```
Stack Name [lambda-monorepo-stack]: <your-stack-name>
AWS Region [us-east-1]: <your-region>
Parameter Environment [dev]: dev
Confirm changes before deployment [y/N]: y
Allow SAM CLI IAM role creation [Y/n]: Y
Save parameters to samconfig.toml [Y/n]: Y
```

## Step 3: Deploy to AWS (Subsequent Times)

```bash
sam deploy
```

Uses saved settings from `samconfig.toml`

## Step 4: Get Deployment Outputs

After successful deployment, view the outputs:

```bash
aws cloudformation describe-stacks \
  --stack-name <your-stack-name> \
  --query 'Stacks[0].Outputs' \
  --output table
```

Or check AWS CloudFormation console for:
- Lambda1FunctionArn
- Lambda2FunctionArn
- ApiEndpoint
- Lambda1InvokeUrl
- Lambda2InvokeUrl

## Step 5: Test Deployed Functions

### Using AWS Console
1. Go to Lambda Console
2. Select your function
3. Click "Test" tab
4. Create a test event
5. Click "Test"

### Using AWS CLI

```bash
# Test Lambda 1
aws lambda invoke \
  --function-name <your-stack-name>-lambda1 \
  --payload '{}' \
  response.json
cat response.json

# Test Lambda 2
aws lambda invoke \
  --function-name <your-stack-name>-lambda2 \
  --payload '{}' \
  response.json
cat response.json
```

### Using API Gateway

```bash
# Get the endpoint from CloudFormation outputs
API_ENDPOINT="https://<api-id>.execute-api.<region>.amazonaws.com/dev"

# Test Lambda 1
curl $API_ENDPOINT/lambda1

# Test Lambda 2
curl $API_ENDPOINT/lambda2
```

## Updating Your Functions

After making changes to Lambda code:

```bash
sam build
sam deploy
```

## Deleting the Stack

To remove all deployed resources:

```bash
aws cloudformation delete-stack --stack-name <your-stack-name>

# Monitor deletion
aws cloudformation wait stack-delete-complete \
  --stack-name <your-stack-name>
```

## Environment Variables

Deploy to different environments:

```bash
# Deploy to staging
sam deploy --parameter-overrides Environment=staging

# Deploy to production
sam deploy --parameter-overrides Environment=prod
```

## Monitoring and Logs

### CloudWatch Logs

```bash
# View Lambda 1 logs
aws logs tail /aws/lambda/<your-stack-name>-lambda1 --follow

# View Lambda 2 logs
aws logs tail /aws/lambda/<your-stack-name>-lambda2 --follow
```

### CloudWatch Metrics

Monitor in AWS Console:
1. Go to CloudWatch → Insights
2. Select your Lambda log group
3. Run queries to analyze logs and metrics

## Troubleshooting

### "Access Denied" Error
- Ensure your AWS credentials have the necessary permissions
- Required: Lambda, API Gateway, CloudFormation, IAM roles

### Function Timeout
- Increase timeout in `template.yaml` → `Timeout` field
- Rebuild and redeploy

### Layer Import Errors
- Ensure layer is correctly defined in template
- Check that shared code is in `layers/shared/python/`

### API Gateway Not Found
- Check CloudFormation outputs for correct endpoint
- Verify API Gateway is enabled in template

## Best Practices

1. **Always test locally first**: `sam local start-api`
2. **Use environment parameters**: dev, staging, prod
3. **Monitor logs regularly**: CloudWatch Logs
4. **Keep requirements.txt updated**: Add dependencies there
5. **Use meaningful stack names**: Include project and environment
6. **Set up alarms**: Monitor errors and durations
7. **Enable API Gateway logging**: Track all requests
8. **Backup configurations**: Keep samconfig.toml in version control

## Resources

- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [Lambda Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html)
- [API Gateway Documentation](https://docs.aws.amazon.com/apigateway/)
- [CloudFormation Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/)
