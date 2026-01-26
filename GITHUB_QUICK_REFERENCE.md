# GitHub Setup - Quick Reference Card

## 🚀 Deploy in 3 Minutes

```bash
# 1. Set your GitHub repository
export GITHUB_REPO=your-username/your-repo

# 2. Deploy infrastructure
make setup-github GITHUB_REPO=$GITHUB_REPO

# 3. Authorize in AWS Console (opens browser)
# - Go to Developer Tools → Connections
# - Find "github-lambda-monorepo"
# - Click "Update pending connection"
# - Authorize with GitHub

# 4. Push code
git push origin main

# 5. Watch pipelines
make status
```

## 📊 Why CodeStar Connections?

| Feature | CodeStar | GitHub OAuth Token |
|---------|----------|-------------------|
| Security | ✅ AWS-managed | ⚠️ Token in store |
| Tokens | ✅ Auto-refresh | ⚠️ Manual refresh |
| Setup | ✅ One-time auth | ⚠️ Manual token |
| Best Practice | ✅ AWS recommended | ❌ Legacy |
| Effort | ✅ 5 minutes | ⚠️ Generate token |

## 🔑 Key Commands

```bash
# Deploy
make setup-github GITHUB_REPO=owner/repo

# Monitor both pipelines
make status

# Monitor individual pipelines
make status-lambda1
make status-lambda2

# View build logs (streaming)
make logs-lambda1
make logs-lambda2

# List resources
make list-stacks

# Cleanup
make cleanup                 # Remove pipelines only
make cleanup-all             # Remove everything
```

## 🎯 Pipeline Triggers

| Change Location | Lambda1 | Lambda2 | Both |
|-----------------|---------|---------|------|
| `lambda1/` | ✅ | ❌ | ❌ |
| `lambda2/` | ❌ | ✅ | ❌ |
| `layers/shared/` | ✅ | ✅ | ✅ |

## 📚 What Gets Deployed

```
CodeStar Connection (GitHub)
    ↓
Lambda1 Pipeline
    ├─ Source: GitHub (via CodeStar)
    ├─ Build: CodeBuild (SAM build + package)
    └─ Deploy: CloudFormation (dev → staging → prod)

Lambda2 Pipeline
    ├─ Source: GitHub (via CodeStar)
    ├─ Build: CodeBuild (SAM build + package)
    └─ Deploy: CloudFormation (dev → staging → prod)
```

## 🔒 Security Features

- ✅ No GitHub tokens stored in AWS
- ✅ No personal access tokens in environment
- ✅ AWS manages authentication
- ✅ One-time GitHub authorization
- ✅ Can revoke access anytime
- ✅ Limited scope (repository access only)

## ⚙️ Configuration Options

```bash
# Custom GitHub branch
export GITHUB_BRANCH=develop
make setup-github GITHUB_REPO=$GITHUB_REPO

# Custom connection name
export CODESTAR_CONNECTION_NAME=my-connection
make setup-github GITHUB_REPO=$GITHUB_REPO

# Custom AWS region
export AWS_REGION=us-west-2
make setup-github GITHUB_REPO=$GITHUB_REPO
```

## 🆘 Quick Troubleshooting

**Pipeline not triggering?**
→ Verify CodeStar connection is "AVAILABLE" in AWS Console

**Build failing?**
→ Run `make logs-lambda1` to see error details

**Deployment stuck?**
→ Check CloudFormation stack events in AWS Console

## 📖 Documentation

- `GITHUB_SETUP.md` - Complete guide (450+ lines)
- `QUICK_START.md` - General deployment guide
- `ARCHITECTURE_SUMMARY.md` - System architecture
- `CODEPIPELINE_SETUP.md` - Technical reference

## ✨ What Happens After Push

```
git push origin main
    ↓ (CodeStar detects change)
CodePipeline triggered
    ↓
CodeBuild runs:
  1. Install dependencies
  2. SAM build (--use-container)
  3. SAM package (S3 upload)
    ↓
CloudFormation deploys:
  1. Creates ChangeSet
  2. Reviews changes
  3. Executes ChangeSet
    ↓
Lambda functions updated
  (dev immediately, staging/prod with approval)
```

## 🎓 Learning Path

1. **This card** (2 min) - Overview
2. **GITHUB_SETUP.md** (10 min) - Setup instructions
3. **ARCHITECTURE_SUMMARY.md** (10 min) - How it works
4. **CODEPIPELINE_SETUP.md** (optional, 30 min) - Deep dive

## 🚀 Ready? Start Here

```bash
export GITHUB_REPO=your-username/your-repo
make setup-github GITHUB_REPO=$GITHUB_REPO
```

Then read [GITHUB_SETUP.md](GITHUB_SETUP.md) for detailed instructions!
