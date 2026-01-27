# Lambda Monorepo - CodePipeline Deployment

A production-ready AWS Lambda monorepo with automated CodePipeline deployments triggered by GitHub pushes, using AWS SAM and best practices.

## 📋 Quick Start

```bash
# 1. Make deployment script executable
chmod +x deploy.sh

# 2. Run automated deployment
./deploy.sh

# 3. Add GitHub webhook (see output from deploy.sh)
```

For detailed instructions, see [DEPLOYMENT.md](DEPLOYMENT.md).

## 🏗️ Architecture

- **Lambda Functions**: lambda1 and lambda2 with shared layer
- **CodePipeline**: Separate pipelines per Lambda with Source → Build → Deploy stages
- **CodeBuild**: SAM build and package for each Lambda
- **Webhook**: GitHub webhook handler that intelligently triggers pipelines
- **S3**: Artifact storage for pipeline builds

## 📁 Project Structure

```
├── template.yaml              # Main SAM template (all AWS resources)
├── deploy.sh                  # Automated deployment script
├── DEPLOYMENT.md              # Step-by-step deployment guide
├── QUICK_REFERENCE.md         # Command reference and troubleshooting
├── IAM_POLICIES.md           # IAM permissions reference
├── IMPLEMENTATION_SUMMARY.md  # What was built and why
│
├── lambda1/                   # First Lambda function
│   ├── app.py               # Lambda handler
│   ├── requirements.txt      # Python dependencies
│   └── buildspec.yml         # CodeBuild instructions
│
├── lambda2/                   # Second Lambda function
│   ├── app.py               # Lambda handler
│   ├── requirements.txt      # Python dependencies
│   └── buildspec.yml         # CodeBuild instructions
│
├── layers/
│   └── shared/              # Shared Lambda layer
│       ├── python/
│       │   ├── logger.py
│       │   └── utils.py
│       └── requirements.txt
│
└── webhook/                   # GitHub webhook handler
    ├── app.py               # Webhook Lambda
    └── requirements.txt
```

## 🚀 How It Works

### Trigger Logic

Your webhook intelligently determines which pipelines to trigger based on changed files:

```
Push to: lambda1/app.py
  → Triggers: lambda1-pipeline ONLY

Push to: lambda2/app.py
  → Triggers: lambda2-pipeline ONLY

Push to: layers/shared/python/logger.py
  → Triggers: BOTH pipelines (shared dependency)

Push to: lambda1/app.py + lambda2/app.py
  → Triggers: BOTH pipelines
```

### Deployment Flow

```
1. Developer pushes to GitHub
   ↓
2. GitHub sends webhook to webhook Lambda
   ↓
3. Webhook Lambda verifies signature & parses changed files
   ↓
4. Webhook Lambda calls StartPipelineExecution for relevant pipelines
   ↓
5. CodePipeline executes for each affected Lambda:
   - Source stage: Pulls code from GitHub
   - Build stage: Runs SAM build && sam package
   - Deploy stage: CloudFormation creates/updates Lambda stack
```

## 📚 Documentation

| File | Purpose |
|------|---------|
| **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** | What was built, architecture overview, best practices |
| **[DEPLOYMENT.md](DEPLOYMENT.md)** | Step-by-step deployment guide and troubleshooting |
| **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** | Quick commands, testing procedures, common issues |
| **[IAM_POLICIES.md](IAM_POLICIES.md)** | IAM permissions required for each component |

**Start here**: [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)

## 🔧 Deployment Methods

### Method 1: Automated (Recommended)
```bash
chmod +x deploy.sh
./deploy.sh
```

### Method 2: SAM CLI
```bash
sam build --template template.yaml
sam deploy --guided
```

### Method 3: AWS CLI
```bash
aws cloudformation deploy \
  --template-file template.yaml \
  --stack-name lambda-monorepo-stack \
  --capabilities CAPABILITY_NAMED_IAM
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed instructions on each method.

## ⚙️ Configuration

Before deploying, update:

1. **template.yaml**:
   - Replace `RohanKhanal14/lambda_monorepo` with your GitHub repo
   - Replace `YOUR_CONNECTION_ID` with actual CodeStar Connection ARN

2. **GitHub Webhook Secret**:
   - Generate a strong random string
   - Set in webhook Lambda environment variable

## 🧪 Testing

After deployment, test the trigger logic:

```bash
# Test 1: Trigger lambda1-pipeline only
echo "# test" >> lambda1/app.py
git add lambda1/app.py
git commit -m "test lambda1"
git push

# Test 2: Trigger both pipelines
echo "# test" >> layers/shared/python/logger.py
git add layers/shared/python/logger.py
git commit -m "test shared layer"
git push
```

See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for monitoring commands.

## 📊 Monitoring

```bash
# View pipeline status
aws codepipeline get-pipeline-state --name lambda1-pipeline

# View build logs
aws logs tail /aws/codebuild/lambda1-build --follow

# View Lambda logs
aws logs tail /aws/lambda/lambda1 --follow

# View webhook logs
aws logs tail /aws/lambda/webhook --follow
```

## 💡 Key Features

✅ **Smart Triggering**: Only affected services deploy (faster feedback)
✅ **Shared Layer Support**: Changes to shared code trigger all services
✅ **Best Practices**: Uses SAM + CloudFormation production pattern
✅ **Minimal Cost**: ~$2-3/month for this setup
✅ **Fully Documented**: 4 comprehensive guides included
✅ **Production Ready**: IAM least privilege, CloudFormation ChangeSet, logging
✅ **Easy Testing**: Deploy script handles initial setup

## 🔒 Security

- GitHub webhook signature verification
- IAM least privilege for all roles
- S3 public access blocked
- CloudWatch logging for all components
- Secure secrets handling recommendations

See [IAM_POLICIES.md](IAM_POLICIES.md) for security best practices.

## 📈 Next Steps

After deployment:

1. Add manual approval gates to pipelines
2. Set up SNS notifications for failures
3. Add integration tests to CodeBuild stage
4. Implement canary deployments
5. Set up CloudWatch alarms and dashboards
6. Enable X-Ray tracing for Lambda functions

## ❓ Troubleshooting

1. **Webhook not triggering?**
   - Check GITHUB_WEBHOOK_SECRET is set
   - Verify webhook delivery in GitHub settings
   - Check IAM permissions

2. **CodeBuild failing?**
   - View logs: `aws logs tail /aws/codebuild/lambda1-build --follow`
   - Ensure S3 bucket exists
   - Verify buildspec.yml syntax

3. **Lambda not updating?**
   - Check CloudFormation stack events
   - Verify template.yaml syntax
   - Ensure packaged template available in S3

See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for more troubleshooting tips.

## 📞 Support

- Check the troubleshooting section in [DEPLOYMENT.md](DEPLOYMENT.md)
- Review [QUICK_REFERENCE.md](QUICK_REFERENCE.md) checklist
- Check CloudWatch logs for error details
- Review GitHub webhook deliveries for issues

## 📄 License

[Add your license here]

## 🤝 Contributing

[Add contribution guidelines here]

---

**Ready to deploy?** Start with [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) or run `./deploy.sh`!
