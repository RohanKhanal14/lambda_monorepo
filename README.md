# Lambda Monorepo

A monorepo containing AWS Lambda functions and shared layers.

## Structure

- **lambda1/** - First Lambda function
- **lambda2/** - Second Lambda function
- **webhook/** - Webhook service
- **layers/shared/** - Shared Python layer with utilities and logging

## Deployment

Run the deployment script:
```bash
./deploy.sh
```

Configuration is managed in `samconfig.toml`.

## Requirements

Each function and the shared layer have their own `requirements.txt` files. Install dependencies:
```bash
pip install -r layers/shared/requirements.txt
pip install -r lambda1/requirements.txt
pip install -r lambda2/requirements.txt
```

## CI/CD Pipeline

This monorepo uses GitHub webhooks and independent build pipelines for automated deployment:

### How It Works

1. **GitHub Webhook Integration**
   - Webhook is configured to monitor pushes to the repository
   - Triggers are set up for specific branch names and file paths
   - When code is pushed, the webhook notifies the build system

2. **Independent Pipelines**
   - Each Lambda function has its own separate build pipeline
   - Pipelines are triggered based on file path changes
   - Each pipeline runs independently with its own `buildspec.yml`

3. **Smart Triggering**
   - **lambda1/** - Pipeline triggers when files change in `lambda1/`
   - **lambda2/** - Pipeline triggers when files change in `lambda2/`
   - **layers/shared/** - Changes here trigger **both** Lambda pipelines (since they share this layer)

4. **Build & Deployment**
   - Each pipeline runs its corresponding `buildspec.yml` file
   - Dependencies are installed from `requirements.txt`
   - Lambda function is built and deployed via SAM template
   - Shared layer is rebuilt and deployed when needed
