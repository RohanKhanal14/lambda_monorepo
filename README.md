# Lambda Monorepo - SAM Deployment Guide

This is a monorepo containing two AWS Lambda functions with shared utilities, deployable using AWS SAM (Serverless Application Model).

## Project Structure

```
lambda_monorepo/
├── template.yaml           # SAM template for deployment
├── samconfig.toml          # SAM configuration for local testing
├── events.json             # Test events for local invocation
├── lambda1/
│   ├── app.py             # Lambda 1 function handler
│   └── requirements.txt    # Lambda 1 dependencies
├── lambda2/
│   ├── app.py             # Lambda 2 function handler
│   └── requirements.txt    # Lambda 2 dependencies
└── shared/
    ├── logger.py          # Shared logger utility
    └── utils.py           # Other shared utilities
```

## Prerequisites

- AWS SAM CLI installed: `pip install aws-sam-cli`
- Docker installed (required for local testing)
- AWS CLI configured with credentials
- Python 3.11 or higher

## Installation

```bash
# Install SAM CLI
pip install aws-sam-cli

# Install Docker (if not already installed)
# Follow https://docs.docker.com/get-docker/
```

## Local Testing

### 1. Build the SAM Application

```bash
sam build
```

This command builds the application and prepares it for local testing.

### 2. Start Local API Gateway

```bash
sam local start-api
```

This starts a local API Gateway on `http://127.0.0.1:3000` with both Lambda endpoints available.

**Available endpoints:**
- Lambda1: `http://127.0.0.1:3000/lambda1`
- Lambda2: `http://127.0.0.1:3000/lambda2`

### 3. Test the Functions (in a new terminal)

```bash
# Test Lambda 1
curl http://127.0.0.1:3000/lambda1

# Test Lambda 2
curl http://127.0.0.1:3000/lambda2
```

### 4. Invoke Functions Directly

Alternatively, invoke Lambda functions directly without API Gateway:

```bash
# Invoke Lambda 1
sam local invoke Lambda1Function -e events.json

# Invoke Lambda 2
sam local invoke Lambda2Function -e events.json
```

## Deployment to AWS

### 1. Build the Application

```bash
sam build
```

### 2. Deploy to AWS (First time)

```bash
sam deploy --guided
```

This will prompt you to enter:
- Stack name (e.g., `lambda-monorepo-stack`)
- AWS region (e.g., `us-east-1`)
- Confirm changes before deployment
- Allow SAM CLI to create IAM roles

### 3. Subsequent Deployments

```bash
sam deploy
```

Uses the settings from `samconfig.toml` for subsequent deployments.

### 4. View Deployment Outputs

After successful deployment, CloudFormation outputs will show:
- Lambda function ARNs
- API Gateway endpoint URL
- Individual Lambda invocation URLs

## Environment Variables

The template supports environment variables through the `Environment` parameter:

```bash
sam deploy --parameter-overrides Environment=prod
```

Allowed values: `dev`, `staging`, `prod`

## Cleanup

To delete the deployed resources:

```bash
aws cloudformation delete-stack --stack-name lambda-monorepo-stack
```

Or use the AWS Console to delete the CloudFormation stack.

## Troubleshooting

### Docker Connection Error
```
ERROR: Can't connect to Docker daemon
```
- Ensure Docker is running: `docker ps`
- On Linux, you may need to run with `sudo` or add your user to the docker group

### Python Import Errors
```
ImportError: No module named 'common.logger'
```
- Ensure all dependencies in `requirements.txt` are installed
- Run `sam build` to rebuild

### Port Already in Use
```
ERROR: Port 3000 is already in use
```
- Kill the process: `lsof -ti:3000 | xargs kill -9`
- Or specify a different port: `sam local start-api --port 3001`

## Advanced Usage

### Enable Debugging

```bash
sam local start-api --debug
```

### Watch Mode (Auto-rebuild)

```bash
sam local start-api --warm-containers EAGER
```

### Container Network

To connect containers to external services:

```bash
sam local start-api --docker-network sam-network
```

## References

- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [SAM CLI Reference](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/serverless-sam-reference.html)
- [Lambda Layers](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html)
