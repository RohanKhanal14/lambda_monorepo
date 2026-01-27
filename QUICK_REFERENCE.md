# Quick Reference Guide

## Key Files Created

| File | Purpose |
|------|---------|
| `template.yaml` | Main SAM template with Lambdas, layers, pipelines, and roles |
| `lambda1/buildspec.yml` | CodeBuild build instructions for lambda1 |
| `lambda2/buildspec.yml` | CodeBuild build instructions for lambda2 |
| `webhook/app.py` | GitHub webhook handler that triggers pipelines |
| `DEPLOYMENT.md` | Full step-by-step deployment guide |
| `IAM_POLICIES.md` | IAM policies and security reference |

## Trigger Logic (in webhook/app.py)

```python
# Trigger lambda1-pipeline if:
- lambda1/* files changed, OR
- layers/shared/* files changed

# Trigger lambda2-pipeline if:
- lambda2/* files changed, OR
- layers/shared/* files changed

# Example:
Push with changes to: lambda1/app.py
→ Triggers: lambda1-pipeline only

Push with changes to: layers/shared/python/logger.py
→ Triggers: lambda1-pipeline AND lambda2-pipeline

Push with changes to: lambda1/app.py, lambda2/app.py
→ Triggers: lambda1-pipeline AND lambda2-pipeline
```

## Quick Start Commands

### Deploy Infrastructure
```bash
sam build --template template.yaml
sam deploy --guided
```

### Deploy Webhook Lambda
```bash
cd webhook
pip install -r requirements.txt -t package/
zip -r deployment.zip app.py package/
aws lambda create-function \
  --function-name webhook \
  --runtime python3.11 \
  --role arn:aws:iam::ACCOUNT_ID:role/webhook-execution-role \
  --handler app.lambda_handler \
  --zip-file fileb://deployment.zip
```

### Enable Webhook URL
```bash
aws lambda create-function-url-config \
  --function-name webhook \
  --auth-type NONE
```

### Monitor Deployments
```bash
# Watch CodeBuild logs
aws logs tail /aws/codebuild/lambda1-build --follow

# Watch Lambda logs
aws logs tail /aws/lambda/lambda1 --follow

# Check pipeline status
aws codepipeline get-pipeline-state --name lambda1-pipeline
```

## Architecture Flow

1. **GitHub Push** → Webhook endpoint receives event
2. **Webhook Lambda** → Parses changed files, determines which pipelines to trigger
3. **CodePipeline** (lambda1 and/or lambda2) → Gets source from GitHub
4. **CodeBuild** → Runs SAM build/package commands
5. **CloudFormation** → Creates/updates Lambda stack with packaged template

## Environment Variables

### Webhook Lambda
- `GITHUB_WEBHOOK_SECRET`: GitHub webhook secret (set in Lambda console or CLI)

### CodeBuild
- `S3_BUCKET`: Artifact bucket (auto-set by template)
- `LAMBDA_NAME`: Lambda name (auto-set by buildspec)
- `AWS_REGION`: AWS region

## Pipeline Stages

Both lambda1-pipeline and lambda2-pipeline have:

1. **Source Stage** (GitHub via CodeStar Connection)
   - Detects new commits
   - Uploads source to artifact bucket

2. **Build Stage** (CodeBuild)
   - Runs `sam build`
   - Runs `sam package`
   - Produces packaged.yaml artifact

3. **Deploy Stage** (CloudFormation)
   - Creates ChangeSet
   - Executes ChangeSet (deploys new Lambda version)

## Testing the Setup

### Test 1: Webhook receives event
```bash
curl -X POST $WEBHOOK_URL \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen":"test"}'
# Should return 200 {"message": "pong"}
```

### Test 2: Trigger lambda1 pipeline
```bash
echo "# test comment" >> lambda1/app.py
git add lambda1/app.py
git commit -m "test lambda1"
git push origin main

# Check CodePipeline console: lambda1-pipeline should execute
# Check CloudWatch logs: /aws/codebuild/lambda1-build
```

### Test 3: Trigger both pipelines
```bash
echo "# test" >> layers/shared/python/logger.py
git add layers/shared/python/logger.py
git commit -m "test shared layer"
git push origin main

# Check CodePipeline console: both pipelines should execute
```

## Troubleshooting Checklist

- [ ] GitHub webhook delivery shows 200 status
- [ ] Webhook Lambda logs show "Successfully triggered pipeline"
- [ ] CodeBuild logs show "sam build" and "sam package" successful
- [ ] CloudFormation stack shows "CREATE_COMPLETE" or "UPDATE_COMPLETE"
- [ ] Lambda function exists in AWS Lambda console
- [ ] Lambda has correct layers attached
- [ ] Environment variables set in Lambda

## Common Issues & Fixes

| Issue | Fix |
|-------|-----|
| Webhook not triggering | Check GITHUB_WEBHOOK_SECRET, IAM permissions, S3 bucket exists |
| SAM package fails | Ensure S3 bucket name is correct, dependencies in requirements.txt |
| Lambda not updating | Check CloudFormation stack events, check template.yaml syntax |
| Shared layer not loading | Verify layer is in SAM template, Lambda includes layer in Globals |

## Security Notes

- [ ] GITHUB_WEBHOOK_SECRET is strong (20+ random characters)
- [ ] Webhook URL has Function URL auth disabled (NONE) for GitHub events
- [ ] CodePipeline role restricted to specific pipeline ARNs
- [ ] CloudFormation role restricted to Lambda/S3/CloudBuild/Logs services
- [ ] All S3 buckets have public access blocked
- [ ] Consider using Secrets Manager for GITHUB_WEBHOOK_SECRET

## Next Steps After Deployment

1. Add manual approval gates to pipeline
2. Set up CloudWatch alarms for failures
3. Add SNS notifications for pipeline completion
4. Implement staging/production environments
5. Add integration tests in CodeBuild
6. Set up canary deployments
7. Enable X-Ray tracing for Lambda functions
8. Create CloudWatch dashboards
