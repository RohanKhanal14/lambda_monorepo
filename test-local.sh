#!/bin/bash

# SAM Local Testing Script
# This script tests both Lambda functions locally

set -e

echo "======================================"
echo "Lambda Monorepo - Local Testing"
echo "======================================"
echo ""

# Build
echo "📦 Building SAM application..."
sam build

echo ""
echo "✅ Build completed successfully"
echo ""
echo "======================================"
echo "Testing Functions Locally"
echo "======================================"
echo ""

# Test Lambda 1
echo "🔵 Testing Lambda 1 Function..."
sam local invoke Lambda1Function -e events.json
echo ""

# Test Lambda 2
echo "🟢 Testing Lambda 2 Function..."
sam local invoke Lambda2Function -e events.json
echo ""

echo "======================================"
echo "Local Testing Complete!"
echo "======================================"
echo ""
echo "To start the API Gateway locally, run:"
echo "  sam local start-api"
echo ""
echo "Then test with:"
echo "  curl http://127.0.0.1:3000/lambda1"
echo "  curl http://127.0.0.1:3000/lambda2"
echo ""
