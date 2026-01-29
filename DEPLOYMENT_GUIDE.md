# Lambda Monorepo - DevOps Deployment Guide

**Version:** 1.0  
**Last Updated:** January 2026  
**Audience:** DevOps Engineers  
**Purpose:** Complete step-by-step deployment instructions for AWS Lambda monorepo

---

## Table of Contents

1. [Pre-Deployment Prerequisites](#pre-deployment-prerequisites)
2. [Step 1: AWS Account Setup](#step-1-aws-account-setup)
3. [Step 2: Create S3 Artifact Bucket](#step-2-create-s3-artifact-bucket)
4. [Step 3: Configure IAM Roles & Policies](#step-3-configure-iam-roles--policies)
5. [Step 4: Setup Repository & Secrets](#step-4-setup-repository--secrets)
6. [Step 5: Configure GitHub Webhook](#step-5-configure-github-webhook)
7. [Step 6: Create CodePipeline Infrastructure](#step-6-create-codepipeline-infrastructure)
8. [Step 7: Configure SAM & Local Setup](#step-7-configure-sam--local-setup)
9. [Step 8: Deploy Lambda Layer](#step-8-deploy-lambda-layer)
10. [Step 9: Deploy Lambda Functions](#step-9-deploy-lambda-functions)
11. [Step 10: Verify Deployment](#step-10-verify-deployment)
12. [Step 11: Configure Monitoring & Alarms](#step-11-configure-monitoring--alarms)
13. [Troubleshooting & Rollback](#troubleshooting--rollback)

---

## Pre-Deployment Prerequisites

### Required Software & Tools

- [ ] AWS CLI v2 (installed and configured)
- [ ] AWS SAM CLI (latest version)
- [ ] Python 3.9+
- [ ] Docker Desktop (for local testing)
- [ ] Git
- [ ] Text editor (VS Code recommended)

### Required Permissions

Before beginning, ensure you have:
- [ ] AWS Account access with admin or appropriate permissions
- [ ] GitHub repository admin access
- [ ] AWS CloudFormation permissions
- [ ] IAM role creation permissions
- [ ] S3 bucket creation permissions

### Required Information

Gather the following information before starting:

```
AWS Account ID: ________________
AWS Region: ________________ (default: us-east-1)
GitHub Repository URL: ________________
GitHub Branch: ________________ (default: main)
Artifact S3 Bucket Name: ________________
Webhook Endpoint URL: ________________
```

**Screenshot Placeholder - Pre-Deployment Checklist**
```
[INSERT SCREENSHOT: Terminal showing AWS CLI version and SAM version]
```

---

## Step 1: AWS Account Setup

### 1.1 Configure AWS CLI Credentials

```bash
# Configure AWS credentials
aws configure

# When prompted, enter:
# AWS Access Key ID: [your-access-key]
# AWS Secret Access Key: [your-secret-key]
# Default region name: us-east-1
# Default output format: json
```

### 1.2 Verify AWS Configuration

```bash
# Test AWS CLI access
aws sts get-caller-identity
```

**Expected Output:**
```json
{
    "UserId": "AIDAI...",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/your-user"
}
```

### 1.3 Set Environment Variables

```bash
# Set region (optional if already configured)
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Verify
echo "Account ID: $AWS_ACCOUNT_ID"
echo "Region: $AWS_REGION"
```

**Screenshot Placeholder - AWS Account Setup**
```
[INSERT SCREENSHOT: Terminal output showing AWS credentials verification]
```

---

## Step 2: Create S3 Artifact Bucket

### 2.1 Create S3 Bucket

```bash
# Generate unique bucket name with timestamp
BUCKET_NAME="lambda-monorepo-artifacts-$(date +%s)"

# Create bucket
aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION

# Verify bucket creation
aws s3 ls | grep $BUCKET_NAME
```

### 2.2 Enable Versioning on Bucket

```bash
# Enable versioning for artifact tracking
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Verify versioning
aws s3api get-bucket-versioning --bucket $BUCKET_NAME
```

### 2.3 Enable Block Public Access

```bash
# Block all public access for security
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Verify
aws s3api get-public-access-block --bucket $BUCKET_NAME
```

### 2.4 Save Bucket Name

```bash
# Save for later use
echo "S3_BUCKET=$BUCKET_NAME" >> ~/.bashrc
source ~/.bashrc

# Verify
echo $S3_BUCKET
```

**Expected Output:**
```
S3_BUCKET=lambda-monorepo-artifacts-1673456789
```

**Screenshot Placeholder - S3 Bucket Creation**
```
[INSERT SCREENSHOT: AWS Console showing S3 bucket created with versioning enabled]
```

---

## Step 3: Configure IAM Roles & Policies

### 3.1 Create CodeBuild Service Role

```bash
# Create trust policy document
cat > /tmp/codebuild-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create IAM role
aws iam create-role \
  --role-name lambda-monorepo-codebuild-role \
  --assume-role-policy-document file:///tmp/codebuild-trust-policy.json

# Get role ARN
CODEBUILD_ROLE_ARN=$(aws iam get-role \
  --role-name lambda-monorepo-codebuild-role \
  --query 'Role.Arn' \
  --output text)

echo "CodeBuild Role ARN: $CODEBUILD_ROLE_ARN"
```

### 3.2 Attach CodeBuild Policies

```bash
# Create inline policy for CodeBuild
cat > /tmp/codebuild-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/codebuild/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::lambda-monorepo-artifacts*",
        "arn:aws:s3:::lambda-monorepo-artifacts*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Attach inline policy
aws iam put-role-policy \
  --role-name lambda-monorepo-codebuild-role \
  --policy-name CodeBuildPolicy \
  --policy-document file:///tmp/codebuild-policy.json
```

### 3.3 Create CodePipeline Service Role

```bash
# Create trust policy for CodePipeline
cat > /tmp/codepipeline-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codepipeline.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name lambda-monorepo-codepipeline-role \
  --assume-role-policy-document file:///tmp/codepipeline-trust-policy.json

# Get role ARN
CODEPIPELINE_ROLE_ARN=$(aws iam get-role \
  --role-name lambda-monorepo-codepipeline-role \
  --query 'Role.Arn' \
  --output text)

echo "CodePipeline Role ARN: $CODEPIPELINE_ROLE_ARN"
```

### 3.4 Attach CodePipeline Policies

```bash
# Create CodePipeline policy
cat > /tmp/codepipeline-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::lambda-monorepo-artifacts*",
        "arn:aws:s3:::lambda-monorepo-artifacts*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:BatchGetReports",
        "codebuild:CreateReport",
        "codebuild:CreateReportGroup",
        "codebuild:UpdateReport"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "codebuild:BatchGetBuilds",
        "codebuild:BatchGetReports"
      ],
      "Resource": "arn:aws:codebuild:*:*:project/lambda*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Attach policy
aws iam put-role-policy \
  --role-name lambda-monorepo-codepipeline-role \
  --policy-name CodePipelinePolicy \
  --policy-document file:///tmp/codepipeline-policy.json
```

### 3.5 Create Lambda Execution Role

```bash
# Create trust policy for Lambda
cat > /tmp/lambda-trust-policy.json << 'EOF'
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
EOF

# Create role
aws iam create-role \
  --role-name lambda-monorepo-execution-role \
  --assume-role-policy-document file:///tmp/lambda-trust-policy.json

# Attach basic Lambda execution policy
aws iam attach-role-policy \
  --role-name lambda-monorepo-execution-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Enable X-Ray write access (optional)
aws iam attach-role-policy \
  --role-name lambda-monorepo-execution-role \
  --policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess

# Get role ARN
LAMBDA_ROLE_ARN=$(aws iam get-role \
  --role-name lambda-monorepo-execution-role \
  --query 'Role.Arn' \
  --output text)

echo "Lambda Execution Role ARN: $LAMBDA_ROLE_ARN"
```

**Screenshot Placeholder - IAM Roles Creation**
```
[INSERT SCREENSHOT: AWS IAM Console showing created roles (CodeBuild, CodePipeline, Lambda)]
```

---

## Step 4: Setup Repository & Secrets

### 4.1 Clone Repository

```bash
# Clone the repository (replace with your repo URL)
git clone https://github.com/your-org/lambda-monorepo.git
cd lambda-monorepo

# Verify structure
ls -la
```

**Expected Output:**
```
ARCHITECTURE.md
DEPLOYMENT_GUIDE.md
README.md
deploy.sh
packaged.yaml
samconfig.toml
lambda1/
lambda2/
layers/
webhook/
```

### 4.2 Update samconfig.toml

```bash
# Open samconfig.toml and update with your values
cat > samconfig.toml << 'EOF'
version = 0.1

[default]
[default.deploy]
[default.deploy.parameters]
stack_name = "lambda-monorepo"
s3_bucket = "lambda-monorepo-artifacts-XXXXX"
s3_prefix = "lambda-deployments"
region = "us-east-1"
confirm_changeset = true
capabilities = "CAPABILITY_IAM"
parameter_overrides = []
EOF

# Replace XXXXX with your bucket name
sed -i "s/XXXXX/$(echo $S3_BUCKET | cut -d'-' -f4-)/g" samconfig.toml

# Verify
cat samconfig.toml
```

### 4.3 Create .env File (Local Development)

```bash
# Create .env file for local testing
cat > .env << 'EOF'
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=123456789012
LAMBDA_ROLE_ARN=arn:aws:iam::123456789012:role/lambda-monorepo-execution-role
S3_BUCKET=lambda-monorepo-artifacts-XXXXX
LOG_LEVEL=INFO
EOF

# Replace values with your actual values
# Update XXXXX with your bucket name
# Update 123456789012 with your account ID
```

**Screenshot Placeholder - Repository Setup**
```
[INSERT SCREENSHOT: Terminal showing samconfig.toml configuration]
```

---

## Step 5: Configure GitHub Webhook

### 5.1 Generate GitHub Personal Access Token

1. Go to GitHub Settings → Developer settings → Personal access tokens
2. Click "Generate new token"
3. Select scopes: `repo`, `workflow`, `admin:repo_hook`
4. Generate and copy the token

**Screenshot Placeholder - GitHub Token Creation**
```
[INSERT SCREENSHOT: GitHub Settings showing Personal Access Token creation]
```

### 5.2 Create Webhook Endpoint (AWS)

```bash
# Create webhook service using AWS Lambda + API Gateway
# For now, create a basic webhook function

mkdir -p webhook-deployment
cd webhook-deployment

cat > lambda_function.py << 'EOF'
import json
import boto3
import hmac
import hashlib
import os

codepipeline = boto3.client('codepipeline')

def verify_github_signature(event, secret):
    """Verify GitHub webhook signature"""
    signature = event.get('headers', {}).get('X-Hub-Signature', '')
    body = event.get('body', '')
    
    expected_signature = 'sha1=' + hmac.new(
        secret.encode(),
        body.encode(),
        hashlib.sha1
    ).hexdigest()
    
    return hmac.compare_digest(signature, expected_signature)

def lambda_handler(event, context):
    print(f"Received webhook event: {json.dumps(event)}")
    
    try:
        # Parse GitHub event
        body = json.loads(event.get('body', '{}'))
        changed_files = body.get('push', {}).get('changes', [])
        
        # Determine which pipeline to trigger
        if any('lambda1' in f.get('path', '') for f in changed_files):
            trigger_pipeline('lambda1-pipeline')
        
        if any('lambda2' in f.get('path', '') for f in changed_files):
            trigger_pipeline('lambda2-pipeline')
        
        if any('layers/shared' in f.get('path', '') for f in changed_files):
            trigger_pipeline('lambda1-pipeline')
            trigger_pipeline('lambda2-pipeline')
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Webhook processed successfully'})
        }
    
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def trigger_pipeline(pipeline_name):
    """Trigger CodePipeline execution"""
    try:
        response = codepipeline.start_pipeline_execution(
            name=pipeline_name
        )
        print(f"Triggered {pipeline_name}: {response['pipelineExecutionId']}")
    except Exception as e:
        print(f"Error triggering pipeline: {str(e)}")
EOF

cd ..
```

### 5.3 Deploy Webhook Lambda

```bash
# Create IAM role for webhook Lambda
cat > /tmp/webhook-trust-policy.json << 'EOF'
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
EOF

aws iam create-role \
  --role-name lambda-monorepo-webhook-role \
  --assume-role-policy-document file:///tmp/webhook-trust-policy.json

# Attach policies
aws iam attach-role-policy \
  --role-name lambda-monorepo-webhook-role \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# Add CodePipeline start permission
cat > /tmp/webhook-codepipeline-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "codepipeline:StartPipelineExecution"
      ],
      "Resource": "arn:aws:codepipeline:*:*:*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name lambda-monorepo-webhook-role \
  --policy-name CodePipelineAccess \
  --policy-document file:///tmp/webhook-codepipeline-policy.json
```

### 5.4 Create API Gateway Webhook Endpoint

```bash
# Create REST API
API_ID=$(aws apigateway create-rest-api \
  --name "lambda-monorepo-webhook" \
  --description "Webhook for Lambda monorepo" \
  --query 'id' \
  --output text)

echo "API Gateway ID: $API_ID"

# Get root resource
ROOT_ID=$(aws apigateway get-resources \
  --rest-api-id $API_ID \
  --query 'items[0].id' \
  --output text)

# Create POST method
aws apigateway put-method \
  --rest-api-id $API_ID \
  --resource-id $ROOT_ID \
  --http-method POST \
  --authorization-type NONE

# Get webhook lambda ARN
WEBHOOK_LAMBDA_ARN=$(aws lambda get-function \
  --function-name lambda-monorepo-webhook \
  --query 'Configuration.FunctionArn' \
  --output text 2>/dev/null || echo "arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:function:lambda-monorepo-webhook")

# Save webhook URL for later
WEBHOOK_URL="https://$API_ID.execute-api.$AWS_REGION.amazonaws.com/prod"
echo "Webhook URL: $WEBHOOK_URL"
```

**Screenshot Placeholder - GitHub Webhook Setup**
```
[INSERT SCREENSHOT: GitHub Settings showing Webhook URL configured]
[INSERT SCREENSHOT: API Gateway showing webhook endpoint]
```

---

## Step 6: Create CodePipeline Infrastructure

### 6.1 Create CodeBuild Projects

```bash
# Create Lambda1 CodeBuild project
aws codebuild create-project \
  --name lambda1-build \
  --service-role $CODEBUILD_ROLE_ARN \
  --artifacts type=CODEPIPELINE \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:5.0,computeType=BUILD_GENERAL1_SMALL \
  --source type=CODEPIPELINE,buildspec=lambda1/buildspec.yml

# Create Lambda2 CodeBuild project
aws codebuild create-project \
  --name lambda2-build \
  --service-role $CODEBUILD_ROLE_ARN \
  --artifacts type=CODEPIPELINE \
  --environment type=LINUX_CONTAINER,image=aws/codebuild/standard:5.0,computeType=BUILD_GENERAL1_SMALL \
  --source type=CODEPIPELINE,buildspec=lambda2/buildspec.yml

# Verify projects created
aws codebuild list-projects --query 'projects' --output text | grep lambda
```

### 6.2 Create CodePipeline for Lambda1

```bash
# Create pipeline configuration JSON
cat > /tmp/lambda1-pipeline.json << 'EOF'
{
  "pipeline": {
    "name": "lambda1-pipeline",
    "roleArn": "CODEPIPELINE_ROLE_ARN",
    "artifactStore": {
      "type": "S3",
      "location": "S3_BUCKET"
    },
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "SourceAction",
            "actionTypeId": {
              "category": "Source",
              "owner": "GitHub",
              "provider": "GitHub",
              "version": "1"
            },
            "configuration": {
              "Owner": "YOUR_GITHUB_ORG",
              "Repo": "lambda-monorepo",
              "Branch": "main",
              "OAuthToken": "GITHUB_TOKEN"
            },
            "outputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ]
          }
        ]
      },
      {
        "name": "Build",
        "actions": [
          {
            "name": "BuildAction",
            "actionTypeId": {
              "category": "Build",
              "owner": "AWS",
              "provider": "CodeBuild",
              "version": "1"
            },
            "configuration": {
              "ProjectName": "lambda1-build"
            },
            "inputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ],
            "outputArtifacts": [
              {
                "name": "BuildOutput"
              }
            ]
          }
        ]
      },
      {
        "name": "Deploy",
        "actions": [
          {
            "name": "DeployAction",
            "actionTypeId": {
              "category": "Deploy",
              "owner": "AWS",
              "provider": "CloudFormation",
              "version": "1"
            },
            "configuration": {
              "ActionMode": "CREATE_UPDATE",
              "StackName": "lambda1-stack",
              "TemplatePath": "BuildOutput::packaged.yaml",
              "Capabilities": "CAPABILITY_IAM,CAPABILITY_AUTO_EXPAND",
              "RoleArn": "CODEPIPELINE_ROLE_ARN"
            },
            "inputArtifacts": [
              {
                "name": "BuildOutput"
              }
            ]
          }
        ]
      }
    ]
  }
}
EOF

# Replace placeholders
sed -i "s|CODEPIPELINE_ROLE_ARN|$CODEPIPELINE_ROLE_ARN|g" /tmp/lambda1-pipeline.json
sed -i "s|S3_BUCKET|$S3_BUCKET|g" /tmp/lambda1-pipeline.json
sed -i "s|YOUR_GITHUB_ORG|your-org|g" /tmp/lambda1-pipeline.json
sed -i "s|GITHUB_TOKEN|$GITHUB_TOKEN|g" /tmp/lambda1-pipeline.json

# Create pipeline
aws codepipeline create-pipeline --cli-input-json file:///tmp/lambda1-pipeline.json
```

### 6.3 Create CodePipeline for Lambda2

```bash
# Create pipeline configuration JSON for Lambda2
cat > /tmp/lambda2-pipeline.json << 'EOF'
{
  "pipeline": {
    "name": "lambda2-pipeline",
    "roleArn": "CODEPIPELINE_ROLE_ARN",
    "artifactStore": {
      "type": "S3",
      "location": "S3_BUCKET"
    },
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "SourceAction",
            "actionTypeId": {
              "category": "Source",
              "owner": "GitHub",
              "provider": "GitHub",
              "version": "1"
            },
            "configuration": {
              "Owner": "YOUR_GITHUB_ORG",
              "Repo": "lambda-monorepo",
              "Branch": "main",
              "OAuthToken": "GITHUB_TOKEN"
            },
            "outputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ]
          }
        ]
      },
      {
        "name": "Build",
        "actions": [
          {
            "name": "BuildAction",
            "actionTypeId": {
              "category": "Build",
              "owner": "AWS",
              "provider": "CodeBuild",
              "version": "1"
            },
            "configuration": {
              "ProjectName": "lambda2-build"
            },
            "inputArtifacts": [
              {
                "name": "SourceOutput"
              }
            ],
            "outputArtifacts": [
              {
                "name": "BuildOutput"
              }
            ]
          }
        ]
      },
      {
        "name": "Deploy",
        "actions": [
          {
            "name": "DeployAction",
            "actionTypeId": {
              "category": "Deploy",
              "owner": "AWS",
              "provider": "CloudFormation",
              "version": "1"
            },
            "configuration": {
              "ActionMode": "CREATE_UPDATE",
              "StackName": "lambda2-stack",
              "TemplatePath": "BuildOutput::packaged.yaml",
              "Capabilities": "CAPABILITY_IAM,CAPABILITY_AUTO_EXPAND",
              "RoleArn": "CODEPIPELINE_ROLE_ARN"
            },
            "inputArtifacts": [
              {
                "name": "BuildOutput"
              }
            ]
          }
        ]
      }
    ]
  }
}
EOF

# Replace placeholders
sed -i "s|CODEPIPELINE_ROLE_ARN|$CODEPIPELINE_ROLE_ARN|g" /tmp/lambda2-pipeline.json
sed -i "s|S3_BUCKET|$S3_BUCKET|g" /tmp/lambda2-pipeline.json
sed -i "s|YOUR_GITHUB_ORG|your-org|g" /tmp/lambda2-pipeline.json
sed -i "s|GITHUB_TOKEN|$GITHUB_TOKEN|g" /tmp/lambda2-pipeline.json

# Create pipeline
aws codepipeline create-pipeline --cli-input-json file:///tmp/lambda2-pipeline.json
```

### 6.4 Verify Pipelines Created

```bash
# List all pipelines
aws codepipeline list-pipelines --query 'pipelines[*].name' --output text

# Get pipeline status
aws codepipeline get-pipeline-state --name lambda1-pipeline
aws codepipeline get-pipeline-state --name lambda2-pipeline
```

**Screenshot Placeholder - CodePipeline Creation**
```
[INSERT SCREENSHOT: AWS CodePipeline console showing lambda1-pipeline and lambda2-pipeline]
[INSERT SCREENSHOT: CodeBuild projects created]
```

---

## Step 7: Configure SAM & Local Setup

### 7.1 Install Python Dependencies

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Upgrade pip
pip install --upgrade pip

# Install shared layer dependencies
pip install -r layers/shared/requirements.txt

# Install Lambda1 dependencies
pip install -r lambda1/requirements.txt

# Install Lambda2 dependencies
pip install -r lambda2/requirements.txt

# Install development & testing tools
pip install pytest pytest-cov boto3 moto
```

### 7.2 Validate SAM Templates

```bash
# Validate each SAM template
sam validate --template lambda1/template.yaml --region $AWS_REGION
sam validate --template lambda2/template.yaml --region $AWS_REGION

# Check for syntax errors
python -m py_compile lambda1/app.py
python -m py_compile lambda2/app.py
python -m py_compile layers/shared/python/logger.py
python -m py_compile layers/shared/python/utils.py
```

### 7.3 Build SAM Application Locally

```bash
# Build application
sam build --use-container

# Verify build output
ls -la .aws-sam/build/
```

**Screenshot Placeholder - SAM Configuration**
```
[INSERT SCREENSHOT: Terminal showing SAM template validation]
[INSERT SCREENSHOT: SAM build output]
```

---

## Step 8: Deploy Lambda Layer

### 8.1 Package Lambda Layer

```bash
# Create layer package structure
mkdir -p layer-build/python
cp -r layers/shared/python/* layer-build/python/

# Install layer dependencies
pip install -r layers/shared/requirements.txt -t layer-build/python/

# Create zip file
cd layer-build
zip -r ../lambda-layer.zip .
cd ..

# Verify zip file
unzip -l lambda-layer.zip | head -20
```

### 8.2 Publish Lambda Layer

```bash
# Publish layer to AWS
LAYER_VERSION=$(aws lambda publish-layer-version \
  --layer-name shared-layer \
  --zip-file fileb://lambda-layer.zip \
  --compatible-runtimes python3.9 \
  --compatible-architectures x86_64 \
  --query 'Version' \
  --output text)

echo "Layer Version: $LAYER_VERSION"

# Get layer ARN
LAYER_ARN=$(aws lambda get-layer-version \
  --layer-name shared-layer \
  --version-number $LAYER_VERSION \
  --query 'LayerVersionArn' \
  --output text)

echo "Layer ARN: $LAYER_ARN"
```

### 8.3 Update SAM Templates with Layer ARN

```bash
# Update lambda1 template
sed -i "s|LAYER_ARN|$LAYER_ARN|g" lambda1/template.yaml

# Update lambda2 template
sed -i "s|LAYER_ARN|$LAYER_ARN|g" lambda2/template.yaml

# Verify updates
grep -n "Layers:" lambda1/template.yaml lambda2/template.yaml
```

### 8.4 Verify Layer Deployment

```bash
# List layer versions
aws lambda list-layer-versions --layer-name shared-layer

# Get layer details
aws lambda get-layer-version \
  --layer-name shared-layer \
  --version-number $LAYER_VERSION \
  --query 'Content'
```

**Screenshot Placeholder - Lambda Layer Deployment**
```
[INSERT SCREENSHOT: AWS Lambda console showing shared-layer versions]
[INSERT SCREENSHOT: Terminal showing layer ARN and version]
```

---

## Step 9: Deploy Lambda Functions

### 9.1 Build Lambdas Locally

```bash
# Build Lambda1
cd lambda1
sam build --use-container

# Build Lambda2
cd ../lambda2
sam build --use-container

# Return to root
cd ..
```

### 9.2 Package Lambda Functions

```bash
# Package Lambda1
sam package \
  --template-file lambda1/.aws-sam/build/template.yaml \
  --s3-bucket $S3_BUCKET \
  --s3-prefix lambda1 \
  --output-template-file lambda1-packaged.yaml \
  --region $AWS_REGION

# Package Lambda2
sam package \
  --template-file lambda2/.aws-sam/build/template.yaml \
  --s3-bucket $S3_BUCKET \
  --s3-prefix lambda2 \
  --output-template-file lambda2-packaged.yaml \
  --region $AWS_REGION

# Verify packaged templates
ls -la *-packaged.yaml
```

### 9.3 Deploy Lambda1

```bash
# Deploy Lambda1 stack
sam deploy \
  --template-file lambda1-packaged.yaml \
  --stack-name lambda1-stack \
  --capabilities CAPABILITY_IAM \
  --region $AWS_REGION \
  --no-confirm-changeset

# Get Lambda1 function ARN
LAMBDA1_ARN=$(aws cloudformation describe-stacks \
  --stack-name lambda1-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`Lambda1FunctionArn`].OutputValue' \
  --output text)

echo "Lambda1 ARN: $LAMBDA1_ARN"
```

### 9.4 Deploy Lambda2

```bash
# Deploy Lambda2 stack
sam deploy \
  --template-file lambda2-packaged.yaml \
  --stack-name lambda2-stack \
  --capabilities CAPABILITY_IAM \
  --region $AWS_REGION \
  --no-confirm-changeset

# Get Lambda2 function ARN
LAMBDA2_ARN=$(aws cloudformation describe-stacks \
  --stack-name lambda2-stack \
  --query 'Stacks[0].Outputs[?OutputKey==`Lambda2FunctionArn`].OutputValue' \
  --output text)

echo "Lambda2 ARN: $LAMBDA2_ARN"
```

### 9.5 Verify Deployments

```bash
# List Lambda functions
aws lambda list-functions \
  --query 'Functions[?FunctionName==`lambda1` || FunctionName==`lambda2`].[FunctionName,FunctionArn,Runtime]' \
  --output table

# Check CloudFormation stacks
aws cloudformation describe-stacks \
  --query 'Stacks[?contains(StackName, `lambda`)].{Name:StackName,Status:StackStatus,CreatedTime:CreationTime}' \
  --output table
```

**Screenshot Placeholder - Lambda Deployment**
```
[INSERT SCREENSHOT: AWS Lambda console showing lambda1 and lambda2 functions]
[INSERT SCREENSHOT: SAM deployment output]
[INSERT SCREENSHOT: CloudFormation stacks created]
```

---

## Step 10: Verify Deployment

### 10.1 Test Lambda1 Function

```bash
# Invoke Lambda1 with test payload
aws lambda invoke \
  --function-name lambda1 \
  --payload '{"test": true, "message": "Hello Lambda1"}' \
  --log-type Tail \
  response.json

# View response
cat response.json

# View logs
aws logs tail /aws/lambda/lambda1 --follow --max-items 10
```

### 10.2 Test Lambda2 Function

```bash
# Invoke Lambda2 with test payload
aws lambda invoke \
  --function-name lambda2 \
  --payload '{"test": true, "message": "Hello Lambda2"}' \
  --log-type Tail \
  response.json

# View response
cat response.json

# View logs
aws logs tail /aws/lambda/lambda2 --follow --max-items 10
```

### 10.3 Verify Layer Access

```bash
# Check if layer is attached to Lambda1
aws lambda get-function-configuration \
  --function-name lambda1 \
  --query 'Layers' \
  --output json

# Check if layer is attached to Lambda2
aws lambda get-function-configuration \
  --function-name lambda2 \
  --query 'Layers' \
  --output json

# Expected output should show shared-layer attachment
```

### 10.4 Test Shared Layer Utilities

```bash
# Create test to verify layer is accessible
cat > test_layer_access.py << 'EOF'
import json
import boto3

lambda_client = boto3.client('lambda')

test_payload = {
    "test": "layer_import",
    "action": "import_logger"
}

response = lambda_client.invoke(
    FunctionName='lambda1',
    InvocationType='RequestResponse',
    Payload=json.dumps(test_payload)
)

result = json.loads(response['Payload'].read())
print(f"Response: {json.dumps(result, indent=2)}")

assert response['StatusCode'] == 200, "Lambda invocation failed"
assert 'logger' in str(result), "Logger not found in response"
print("✓ Layer import test passed")
EOF

python test_layer_access.py
```

### 10.5 Run Integration Tests

```bash
# Run pytest on integration tests
pytest tests/integration/ -v

# Expected output
# tests/integration/test_lambda1.py::test_lambda1_invocation PASSED
# tests/integration/test_lambda2.py::test_lambda2_invocation PASSED
```

**Screenshot Placeholder - Deployment Verification**
```
[INSERT SCREENSHOT: Terminal showing Lambda1 invocation successful]
[INSERT SCREENSHOT: Terminal showing Lambda2 invocation successful]
[INSERT SCREENSHOT: CloudWatch logs showing function execution]
```

---

## Step 11: Configure Monitoring & Alarms

### 11.1 Enable Detailed CloudWatch Monitoring

```bash
# Enable detailed monitoring for Lambda1
aws lambda update-function-configuration \
  --function-name lambda1 \
  --environment Variables={LOG_LEVEL=INFO,MONITORING=true}

# Enable detailed monitoring for Lambda2
aws lambda update-function-configuration \
  --function-name lambda2 \
  --environment Variables={LOG_LEVEL=INFO,MONITORING=true}

# Enable X-Ray tracing (optional)
aws lambda update-function-configuration \
  --function-name lambda1 \
  --tracing-config Mode=Active

aws lambda update-function-configuration \
  --function-name lambda2 \
  --tracing-config Mode=Active
```

### 11.2 Create CloudWatch Alarms for Lambda1

```bash
# Alarm for Lambda1 errors
aws cloudwatch put-metric-alarm \
  --alarm-name lambda1-errors \
  --alarm-description "Alert when Lambda1 has errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=lambda1 \
  --evaluation-periods 1

# Alarm for Lambda1 throttling
aws cloudwatch put-metric-alarm \
  --alarm-name lambda1-throttles \
  --alarm-description "Alert when Lambda1 is throttled" \
  --metric-name Throttles \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 60 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=FunctionName,Value=lambda1 \
  --evaluation-periods 1

# Alarm for Lambda1 duration
aws cloudwatch put-metric-alarm \
  --alarm-name lambda1-duration \
  --alarm-description "Alert when Lambda1 execution time is high" \
  --metric-name Duration \
  --namespace AWS/Lambda \
  --statistic Average \
  --period 300 \
  --threshold 5000 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=lambda1 \
  --evaluation-periods 2
```

### 11.3 Create CloudWatch Alarms for Lambda2

```bash
# Alarm for Lambda2 errors
aws cloudwatch put-metric-alarm \
  --alarm-name lambda2-errors \
  --alarm-description "Alert when Lambda2 has errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=lambda2 \
  --evaluation-periods 1

# Alarm for Lambda2 throttling
aws cloudwatch put-metric-alarm \
  --alarm-name lambda2-throttles \
  --alarm-description "Alert when Lambda2 is throttled" \
  --metric-name Throttles \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 60 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=FunctionName,Value=lambda2 \
  --evaluation-periods 1
```

### 11.4 Create CodePipeline Alarms

```bash
# Alarm for pipeline failures
aws cloudwatch put-metric-alarm \
  --alarm-name lambda1-pipeline-failures \
  --alarm-description "Alert when Lambda1 pipeline fails" \
  --metric-name PipelineExecutionFailure \
  --namespace AWS/CodePipeline \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=PipelineName,Value=lambda1-pipeline \
  --evaluation-periods 1

aws cloudwatch put-metric-alarm \
  --alarm-name lambda2-pipeline-failures \
  --alarm-description "Alert when Lambda2 pipeline fails" \
  --metric-name PipelineExecutionFailure \
  --namespace AWS/CodePipeline \
  --statistic Sum \
  --period 300 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=PipelineName,Value=lambda2-pipeline \
  --evaluation-periods 1
```

### 11.5 Create Log Groups with Retention

```bash
# Set log retention for Lambda1 (30 days)
aws logs put-retention-policy \
  --log-group-name /aws/lambda/lambda1 \
  --retention-in-days 30

# Set log retention for Lambda2 (30 days)
aws logs put-retention-policy \
  --log-group-name /aws/lambda/lambda2 \
  --retention-in-days 30

# Verify retention policies
aws logs describe-log-groups \
  --log-group-name-prefix /aws/lambda/lambda \
  --query 'logGroups[*].[logGroupName,retentionInDays]' \
  --output table
```

**Screenshot Placeholder - Monitoring Setup**
```
[INSERT SCREENSHOT: CloudWatch dashboard showing Lambda1 and Lambda2 metrics]
[INSERT SCREENSHOT: CloudWatch alarms created]
[INSERT SCREENSHOT: CloudWatch log groups configured]
```

---

## Troubleshooting & Rollback

### Issue: Pipeline Fails with "Module Not Found"

**Problem:** CodeBuild fails with `ModuleNotFoundError: No module named 'shared'`

**Solution:**
```bash
# Update buildspec.yml to include layer in Python path
cat > lambda1/buildspec.yml << 'EOF'
version: 0.2

phases:
  install:
    runtime-versions:
      python: 3.9
    commands:
      - pip install --upgrade pip
      - pip install aws-sam-cli aws-cli
  
  pre_build:
    commands:
      - export PYTHONPATH=/opt/python:$PYTHONPATH
      - pip install -r requirements.txt
  
  build:
    commands:
      - sam build --use-container
      - sam package --s3-bucket $ARTIFACT_BUCKET --output-template-file packaged.yaml
  
  post_build:
    commands:
      - echo "Build complete"

artifacts:
  files:
    - packaged.yaml
EOF
```

### Issue: Webhook Not Triggering Pipeline

**Problem:** Code pushed but pipeline doesn't start

**Solution:**
```bash
# Test webhook manually
WEBHOOK_URL="https://YOUR_API_ID.execute-api.us-east-1.amazonaws.com/prod"

curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: push" \
  -d '{
    "ref": "refs/heads/main",
    "repository": {
      "name": "lambda-monorepo"
    },
    "head_commit": {
      "modified": ["lambda1/app.py"]
    }
  }' \
  -v

# Check webhook Lambda logs
aws logs tail /aws/lambda/lambda-monorepo-webhook --follow
```

### Issue: CloudFormation Stack Update Fails

**Problem:** Stack fails to update with "No updates are to be performed"

**Solution:**
```bash
# Check stack events
aws cloudformation describe-stack-events \
  --stack-name lambda1-stack \
  --query 'StackEvents[0:5]' \
  --output table

# Manually update stack
aws cloudformation update-stack \
  --stack-name lambda1-stack \
  --template-body file://lambda1-packaged.yaml \
  --capabilities CAPABILITY_IAM \
  --region $AWS_REGION
```

### Issue: Lambda Layer Version Mismatch

**Problem:** Lambda references old layer version

**Solution:**
```bash
# Check current layer version
aws lambda get-function-configuration \
  --function-name lambda1 \
  --query 'Layers' \
  --output json

# Publish new layer version
aws lambda publish-layer-version \
  --layer-name shared-layer \
  --zip-file fileb://lambda-layer.zip

# Update Lambda to use new layer
LATEST_VERSION=$(aws lambda list-layer-versions \
  --layer-name shared-layer \
  --query 'LayerVersions[0].Version' \
  --output text)

LAYER_ARN="arn:aws:lambda:$AWS_REGION:$AWS_ACCOUNT_ID:layer:shared-layer:$LATEST_VERSION"

aws lambda update-function-configuration \
  --function-name lambda1 \
  --layers $LAYER_ARN
```

### Issue: Permission Denied on S3

**Problem:** CodeBuild cannot upload artifacts

**Solution:**
```bash
# Check IAM role permissions
aws iam get-role-policy \
  --role-name lambda-monorepo-codebuild-role \
  --policy-name CodeBuildPolicy

# Add S3 permissions if missing
cat > /tmp/s3-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::lambda-monorepo-artifacts*",
        "arn:aws:s3:::lambda-monorepo-artifacts*/*"
      ]
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name lambda-monorepo-codebuild-role \
  --policy-name S3Access \
  --policy-document file:///tmp/s3-policy.json
```

### Rollback to Previous Lambda Version

```bash
# List previous versions
aws lambda list-versions-by-function --function-name lambda1

# Get previous function version
PREVIOUS_VERSION=$(aws lambda list-versions-by-function \
  --function-name lambda1 \
  --query 'Versions[-2].Version' \
  --output text)

# Create/update alias to point to previous version
aws lambda update-alias \
  --function-name lambda1 \
  --name LIVE \
  --function-version $PREVIOUS_VERSION

# Verify rollback
aws lambda get-alias \
  --function-name lambda1 \
  --name LIVE
```

### Rollback CloudFormation Stack

```bash
# Continue update rollback (if stack is stuck)
aws cloudformation continue-update-rollback \
  --stack-name lambda1-stack

# Or cancel update
aws cloudformation cancel-update-stack \
  --stack-name lambda1-stack

# Delete stack (if needed for fresh deployment)
aws cloudformation delete-stack --stack-name lambda1-stack

# Wait for deletion
aws cloudformation wait stack-delete-complete --stack-name lambda1-stack
```

**Screenshot Placeholder - Troubleshooting**
```
[INSERT SCREENSHOT: CloudFormation events showing error details]
[INSERT SCREENSHOT: CodeBuild logs showing failure reason]
[INSERT SCREENSHOT: IAM policy document confirming permissions]
```

---

## Deployment Checklist

Before considering the deployment complete, verify all items:

- [ ] AWS CLI configured and tested
- [ ] S3 bucket created with versioning enabled
- [ ] IAM roles created (CodeBuild, CodePipeline, Lambda, Webhook)
- [ ] IAM policies attached with correct permissions
- [ ] GitHub Personal Access Token created
- [ ] GitHub Webhook endpoint configured
- [ ] CodeBuild projects created (lambda1-build, lambda2-build)
- [ ] CodePipeline pipelines created (lambda1-pipeline, lambda2-pipeline)
- [ ] SAM templates validated
- [ ] Shared layer published and version noted
- [ ] Lambda1 function deployed successfully
- [ ] Lambda2 function deployed successfully
- [ ] Lambda functions tested with test payloads
- [ ] Layer correctly attached to both functions
- [ ] CloudWatch alarms configured
- [ ] Log group retention policies set
- [ ] X-Ray tracing enabled (optional)
- [ ] Pipeline execution tested with code push
- [ ] All CloudFormation stacks in CREATE_COMPLETE or UPDATE_COMPLETE state

---

## Post-Deployment Steps

### 1. Document Deployment

```bash
# Save deployment details
cat > deployment-info.txt << 'EOF'
Lambda Monorepo Deployment Information
======================================
Deployment Date: $(date)
AWS Region: $AWS_REGION
AWS Account: $AWS_ACCOUNT_ID
S3 Bucket: $S3_BUCKET

Lambda Functions:
- Function: lambda1, ARN: $LAMBDA1_ARN
- Function: lambda2, ARN: $LAMBDA2_ARN

Shared Layer:
- Layer Name: shared-layer
- Layer Version: $LAYER_VERSION
- Layer ARN: $LAYER_ARN

CodePipelines:
- lambda1-pipeline
- lambda2-pipeline

CodeBuild Projects:
- lambda1-build
- lambda2-build

IAM Roles:
- lambda-monorepo-codebuild-role
- lambda-monorepo-codepipeline-role
- lambda-monorepo-execution-role

WebhookEndpoint:
- URL: $WEBHOOK_URL
EOF

cat deployment-info.txt
```

### 2. Setup Continuous Monitoring

- Set up email notifications for CloudWatch alarms
- Configure SNS topics for alerts
- Enable AWS Health Dashboard monitoring
- Set up CloudTrail for audit logging

### 3. Schedule Maintenance

```bash
# Create calendar reminders for:
# - Monthly patch updates
# - Quarterly security reviews
# - Dependency updates
# - Performance optimization reviews
```

### 4. Team Training

- Document deployment process for team
- Conduct deployment walkthrough with team
- Create runbooks for common operations
- Share monitoring dashboard access

---

## Appendix: Useful Commands

### Lambda Operations

```bash
# List all Lambda functions
aws lambda list-functions --query 'Functions[*].[FunctionName,Runtime]' --output table

# Get function configuration
aws lambda get-function-configuration --function-name lambda1

# Update environment variables
aws lambda update-function-configuration \
  --function-name lambda1 \
  --environment Variables={KEY=value}

# Get function logs
aws logs tail /aws/lambda/lambda1 --follow

# Test invoke with live logs
aws lambda invoke \
  --function-name lambda1 \
  --payload '{"test": true}' \
  --log-type Tail \
  response.json
```

### CloudFormation Operations

```bash
# List all stacks
aws cloudformation list-stacks

# Get stack details
aws cloudformation describe-stacks --stack-name lambda1-stack

# Get stack resources
aws cloudformation list-stack-resources --stack-name lambda1-stack

# Monitor stack events
aws cloudformation describe-stack-events --stack-name lambda1-stack

# Delete stack
aws cloudformation delete-stack --stack-name lambda1-stack
```

### CodePipeline Operations

```bash
# Get pipeline status
aws codepipeline get-pipeline-state --name lambda1-pipeline

# Start pipeline execution manually
aws codepipeline start-pipeline-execution --name lambda1-pipeline

# Get execution details
aws codepipeline get-pipeline-execution \
  --pipeline-name lambda1-pipeline \
  --pipeline-execution-id <execution-id>
```

### Layer Operations

```bash
# List layer versions
aws lambda list-layer-versions --layer-name shared-layer

# Get layer details
aws lambda get-layer-version --layer-name shared-layer --version-number 1

# Delete layer version
aws lambda delete-layer-version --layer-name shared-layer --version-number 1
```

---

## Support & Additional Resources

For more information, refer to:
- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed architecture documentation
- [README.md](README.md) - Quick start guide
- [AWS Lambda Documentation](https://docs.aws.amazon.com/lambda/)
- [AWS SAM Documentation](https://docs.aws.amazon.com/serverless-application-model/)
- [AWS CodePipeline Documentation](https://docs.aws.amazon.com/codepipeline/)

---

**Document Version:** 1.0  
**Last Updated:** January 2026  
**Status:** Production Ready
