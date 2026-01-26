# Lambda Monorepo - Documentation Index

## 🚀 Getting Started (Pick One)

### For GitHub Setup (RECOMMENDED) ⭐
👉 **[GITHUB_SETUP.md](GITHUB_SETUP.md)**
- Setup with GitHub (best practice)
- CodeStar Connections (secure, no tokens)
- Step-by-step authorization
- 10 minutes to deploy

### For Quick Deployment (5 min read)
👉 **[QUICK_START.md](QUICK_START.md)**
- 3-step deployment guide
- Key management commands
- Common tasks

### For Understanding the System (15 min read)
👉 **[ARCHITECTURE_SUMMARY.md](ARCHITECTURE_SUMMARY.md)**
- High-level overview
- How pipelines work
- SAM optimization explained
- Deployment flow diagram

### For Complete Technical Reference (45 min read)
👉 **[CODEPIPELINE_SETUP.md](CODEPIPELINE_SETUP.md)**
- Comprehensive guide
- Code explanations
- How each component works
- Troubleshooting guide

---

## 📁 Project Files

### Documentation
| File | Purpose |
|------|---------|
| `GITHUB_SETUP.md` | **RECOMMENDED** - GitHub integration with CodeStar |
| `QUICK_START.md` | 3-step deployment guide |
| `ARCHITECTURE_SUMMARY.md` | How everything works together |
| `CODEPIPELINE_SETUP.md` | Comprehensive technical guide |
| `README.md` | Project overview |
| `DEPLOYMENT_GUIDE.md` | Local testing & deployment |
| `SAM_SETUP_SUMMARY.md` | SAM configuration details |

### Infrastructure
| File | Purpose |
|------|---------|
| `iam-roles-template.yaml` | Shared IAM roles (CodePipeline, CodeBuild, CloudFormation) |
| `codepipeline-lambda1-template.yaml` | Lambda1 pipeline (7 stages) |
| `codepipeline-lambda2-template.yaml` | Lambda2 pipeline (7 stages) |
| `buildspec-lambda1.yml` | Lambda1 build instructions |
| `buildspec-lambda2.yml` | Lambda2 build instructions |

### Automation & Configuration
| File | Purpose |
|------|---------|
| `setup-pipeline.sh` | Deploy entire infrastructure |
| `Makefile` | Management commands |
| `template.yaml` | Root SAM template |
| `samconfig.toml` | SAM build config |

### Lambda Functions
| Directory | Purpose |
|-----------|---------|
| `lambda1/` | Lambda1 handler & dependencies |
| `lambda2/` | Lambda2 handler & dependencies |
| `layers/shared/` | Shared utilities (logger, utils) |

---

## 🎯 Key Concepts

### Independent Pipelines
- **Lambda1 Pipeline**: Triggered by changes to `lambda1/` or `layers/shared/`
- **Lambda2 Pipeline**: Triggered by changes to `lambda2/` or `layers/shared/`
- Each has its own CodeBuild project, S3 bucket, and CloudFormation stack

### SAM Build Process
1. **Install**: Dependencies from `lambda1/requirements.txt` or `lambda2/requirements.txt`
2. **Validate**: CloudFormation template syntax
3. **Build**: `sam build --use-container` (optimizes for Lambda runtime)
4. **Package**: `sam package` (uploads to S3, generates deployment template)
5. **Deploy**: CloudFormation ChangeSet (preview then execute)

### Deployment Stages
Each pipeline has 7 stages:
```
Source (CodeCommit)
  ↓
Build (CodeBuild + SAM)
  ↓
DeployToDev (CloudFormation)
  ↓
ApprovalForStaging (manual)
  ↓
DeployToStaging (CloudFormation)
  ↓
ApprovalForProduction (manual)
  ↓
DeployToProduction (CloudFormation)
```

---

## 💡 Common Commands

```bash
# Deploy infrastructure
make setup

# Monitor pipelines
make status                    # Both pipelines
make status-lambda1            # Lambda1 only
make status-lambda2            # Lambda2 only

# View build logs (real-time)
make logs-lambda1
make logs-lambda2

# Push code (auto-triggers pipeline)
git push origin main

# List all resources
make list-stacks

# Cleanup
make cleanup                   # Remove pipelines
make cleanup-all               # Remove everything
```

---

## 🔧 What Each File Does

### buildspec-lambda1.yml & buildspec-lambda2.yml
**Purpose**: Build instructions for CodeBuild

**Key Commands**:
- Install phase: `cd lambda1 && pip install -r requirements.txt -t .`
- Build phase: `sam build --use-container`
- Package phase: `sam package --s3-bucket {bucket}`

**Why `--use-container`**: 
- Builds in Docker to match Lambda's Linux runtime
- Ensures dependencies compile correctly for Lambda

### codepipeline-lambda1-template.yaml & codepipeline-lambda2-template.yaml
**Purpose**: Define pipeline infrastructure in CloudFormation

**Components**:
- S3 bucket for artifacts
- CodeBuild project with buildspec
- CodePipeline with 7 stages
- CloudFormation stack for Lambda deployment
- IAM permissions (references iam-roles-template.yaml)

**Stack Names**:
- Dev: `lambda-monorepo-lambda1-stack-dev` (or `lambda2`)
- Staging: `lambda-monorepo-lambda1-stack-staging`
- Prod: `lambda-monorepo-lambda1-stack-prod`

### iam-roles-template.yaml
**Purpose**: Create three shared IAM roles

**Roles**:
1. **CodePipelineServiceRole**: Orchestrates pipeline stages
2. **CodeBuildServiceRole**: Runs build commands
3. **CloudFormationServiceRole**: Deploys Lambda stacks

**Permissions**: Each role has only the minimum required permissions (least privilege)

### setup-pipeline.sh
**Purpose**: Automated deployment script

**Actions**:
1. Checks AWS CLI configuration
2. Deploys IAM roles
3. Creates S3 artifact buckets (separate for Lambda1 and Lambda2)
4. Sets up CodeCommit repository
5. Deploys both pipeline CloudFormation templates

**Usage**: `make setup` (runs this script)

### Makefile
**Purpose**: Management commands

**Commands**:
- `setup` - Deploy everything
- `status` - View pipeline status
- `logs-lambda1`/`logs-lambda2` - Stream build logs
- `cleanup` - Remove pipelines
- `list-stacks` - List CloudFormation stacks

---

## 🎓 Learning Path

1. **5 min**: Read [QUICK_START.md](QUICK_START.md) for overview
2. **10 min**: Read [ARCHITECTURE_SUMMARY.md](ARCHITECTURE_SUMMARY.md) to understand how it works
3. **5 min**: Run `make setup` to deploy
4. **30 min**: Read [CODEPIPELINE_SETUP.md](CODEPIPELINE_SETUP.md) for deep technical details
5. **5 min**: Run `make status` to see pipelines in action

---

## 🚨 Troubleshooting

**Pipeline not triggering?**
- Check CodeCommit repository is correctly configured
- Verify EventBridge rule is active
- See CODEPIPELINE_SETUP.md → Troubleshooting section

**Build failures?**
- Check build logs: `make logs-lambda1`
- Common issues: dependency installation, SAM validation
- See CODEPIPELINE_SETUP.md → Troubleshooting section

**Deployment not working?**
- Check CloudFormation stack events
- Verify IAM permissions
- See CODEPIPELINE_SETUP.md → Troubleshooting section

---

## 📞 Quick Help

- **How do I deploy?** → See [QUICK_START.md](QUICK_START.md)
- **How does it work?** → See [ARCHITECTURE_SUMMARY.md](ARCHITECTURE_SUMMARY.md)
- **What's in each file?** → See [CODEPIPELINE_SETUP.md](CODEPIPELINE_SETUP.md)
- **How do I debug?** → See [CODEPIPELINE_SETUP.md](CODEPIPELINE_SETUP.md) → Troubleshooting

---

## ✨ Key Features

✓ **Separate Pipelines**: Lambda1 and Lambda2 deploy independently  
✓ **Auto-Triggered**: Pipelines trigger on code push to CodeCommit  
✓ **SAM Optimized**: Uses `--use-container` for Lambda runtime compatibility  
✓ **Multi-Environment**: dev → staging → production with approvals  
✓ **Safe Deployments**: CloudFormation ChangeSet (preview before executing)  
✓ **Minimal Permissions**: IAM roles follow least-privilege principle  
✓ **Comprehensive Docs**: 3 guides + troubleshooting + examples  

---

**Start with [GITHUB_SETUP.md](GITHUB_SETUP.md)** 🚀
