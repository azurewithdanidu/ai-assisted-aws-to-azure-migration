#!/bin/bash

# Image Upload Service Deployment Script
# This script deploys the CloudFormation stack and updates Lambda functions

set -e

# Configuration
STACK_NAME="image-upload"
ENVIRONMENT="dev"
REGION="ap-southeast-2"
PROFILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        --environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --stack-name NAME      CloudFormation stack name (default: image-upload-service)"
            echo "  --environment ENV      Environment (dev/staging/prod) (default: dev)"
            echo "  --region REGION        AWS region (default: ap-southeast-2)"
            echo "  --profile PROFILE      AWS CLI profile to use (optional)"
            echo "  --help                 Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

print_status "Starting deployment for stack: $STACK_NAME in $ENVIRONMENT environment"

# Set up profile flag for AWS CLI commands
PROFILE_FLAG=""
if [ -n "$PROFILE" ]; then
    PROFILE_FLAG="--profile $PROFILE"
    print_status "Using AWS profile: $PROFILE"
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity $PROFILE_FLAG &> /dev/null; then
    print_error "AWS credentials are not configured. Please configure them first."
    exit 1
fi

# Create build directory
print_status "Creating build directory..."
mkdir -p build
rm -rf build/*

# Package Lambda functions
print_status "Packaging Lambda functions..."

# Package upload function
print_status "  - Packaging upload function..."
cd lambda/upload
zip -q ../../build/upload.zip upload_handler.py
cd ../..

# Package list function
print_status "  - Packaging list function..."
cd lambda/list
zip -q ../../build/list.zip list_handler.py
cd ../..

# Package view function
print_status "  - Packaging view function..."
cd lambda/view
zip -q ../../build/view.zip view_handler.py
cd ../..

# Package delete function
print_status "  - Packaging delete function..."
cd lambda/delete
zip -q ../../build/delete.zip delete_handler.py
cd ../..

# Check if stack exists
print_status "Checking if stack exists..."
if aws cloudformation describe-stacks --stack-name $STACK_NAME --region $REGION $PROFILE_FLAG &> /dev/null; then
    STACK_EXISTS=true
    print_status "Stack exists. Will update it."
else
    STACK_EXISTS=false
    print_status "Stack does not exist. Will create it."
fi

# Deploy CloudFormation stack
if [ "$STACK_EXISTS" = true ]; then
    print_status "Updating CloudFormation stack..."
    aws cloudformation update-stack \
        --stack-name $STACK_NAME \
        --template-body file://template.yaml \
        --parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION \
        $PROFILE_FLAG

    print_status "Waiting for stack update to complete..."
    aws cloudformation wait stack-update-complete \
        --stack-name $STACK_NAME \
        --region $REGION \
        $PROFILE_FLAG

    print_status "Stack update completed successfully!"
else
    print_status "Creating CloudFormation stack..."
    aws cloudformation create-stack \
        --stack-name $STACK_NAME \
        --template-body file://template.yaml \
        --parameters ParameterKey=Environment,ParameterValue=$ENVIRONMENT \
        --capabilities CAPABILITY_NAMED_IAM \
        --region $REGION \
        $PROFILE_FLAG

    print_status "Waiting for stack creation to complete..."
    aws cloudformation wait stack-create-complete \
        --stack-name $STACK_NAME \
        --region $REGION \
        $PROFILE_FLAG

    print_status "Stack creation completed successfully!"
fi

# Get Lambda function names from stack outputs
print_status "Getting Lambda function names from stack..."
UPLOAD_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    $PROFILE_FLAG \
    --query "Stacks[0].Outputs[?OutputKey=='UploadFunctionName'].OutputValue" \
    --output text)

LIST_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    $PROFILE_FLAG \
    --query "Stacks[0].Outputs[?OutputKey=='ListFilesFunctionName'].OutputValue" \
    --output text)

VIEW_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    $PROFILE_FLAG \
    --query "Stacks[0].Outputs[?OutputKey=='GetViewUrlFunctionName'].OutputValue" \
    --output text)

DELETE_FUNCTION=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    $PROFILE_FLAG \
    --query "Stacks[0].Outputs[?OutputKey=='DeleteFileFunctionName'].OutputValue" \
    --output text)

# Update Lambda function code
print_status "Updating Lambda function code..."

print_status "  - Updating upload function..."
aws lambda update-function-code \
    --function-name $UPLOAD_FUNCTION \
    --zip-file fileb://build/upload.zip \
    --region $REGION \
    $PROFILE_FLAG \
    --no-cli-pager > /dev/null

print_status "  - Updating list function..."
aws lambda update-function-code \
    --function-name $LIST_FUNCTION \
    --zip-file fileb://build/list.zip \
    --region $REGION \
    $PROFILE_FLAG \
    --no-cli-pager > /dev/null

print_status "  - Updating view function..."
aws lambda update-function-code \
    --function-name $VIEW_FUNCTION \
    --zip-file fileb://build/view.zip \
    --region $REGION \
    $PROFILE_FLAG \
    --no-cli-pager > /dev/null

print_status "  - Updating delete function..."
aws lambda update-function-code \
    --function-name $DELETE_FUNCTION \
    --zip-file fileb://build/delete.zip \
    --region $REGION \
    $PROFILE_FLAG \
    --no-cli-pager > /dev/null

# Get API URL
API_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    $PROFILE_FLAG \
    --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
    --output text)

# Get Website Bucket and URL
WEBSITE_BUCKET=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    $PROFILE_FLAG \
    --query "Stacks[0].Outputs[?OutputKey=='WebsiteBucketName'].OutputValue" \
    --output text)

WEBSITE_URL=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    $PROFILE_FLAG \
    --query "Stacks[0].Outputs[?OutputKey=='WebsiteUrl'].OutputValue" \
    --output text)

# Get API User credentials
API_USER_NAME=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    $PROFILE_FLAG \
    --query "Stacks[0].Outputs[?OutputKey=='ApiUserName'].OutputValue" \
    --output text)

API_ACCESS_KEY_ID=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    $PROFILE_FLAG \
    --query "Stacks[0].Outputs[?OutputKey=='ApiUserAccessKeyId'].OutputValue" \
    --output text)

API_SECRET_KEY=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    $PROFILE_FLAG \
    --query "Stacks[0].Outputs[?OutputKey=='ApiUserSecretAccessKey'].OutputValue" \
    --output text)

# Deploy frontend to S3 (if app.html exists)
if [ -f "examples/app.html" ]; then
    print_status "Deploying frontend to S3..."

    # Update API URL in the HTML file
    print_status "  - Updating configuration in HTML..."
    sed -e "s|https://YOUR-API-ID.execute-api.YOUR-REGION.amazonaws.com/dev|$API_URL|g" \
        -e "s|YOUR_REGION|$REGION|g" \
        examples/app.html > build/app.html

    # Upload to S3
    print_status "  - Uploading HTML to S3..."
    aws s3 cp build/app.html s3://$WEBSITE_BUCKET/app.html \
        --content-type "text/html" \
        --region $REGION \
        $PROFILE_FLAG \
        --no-cli-pager > /dev/null

    print_status "Frontend deployed successfully!"
else
    print_warning "No frontend file found (examples/app.html), skipping frontend deployment"
fi

print_status "Deployment completed successfully!"
echo ""
print_status "=== Stack Outputs ==="
print_status "API URL: $API_URL"
print_status "Upload Function: $UPLOAD_FUNCTION"
print_status "List Function: $LIST_FUNCTION"
print_status "View Function: $VIEW_FUNCTION"
print_status "Delete Function: $DELETE_FUNCTION"
echo ""
print_status "=== API Endpoints (IAM Auth Required) ==="
print_status "  POST   $API_URL/upload"
print_status "  GET    $API_URL/files?prefix=<optional>"
print_status "  GET    $API_URL/files/<fileId>/view-url"
print_status "  DELETE $API_URL/files/<fileId>"
echo ""
print_status "=== Frontend ==="
print_status "Website URL: $WEBSITE_URL"
print_status "Website Bucket: $WEBSITE_BUCKET"
echo ""
print_status "=== API User Credentials ==="
print_status "IAM User: $API_USER_NAME"
print_warning "Access Key ID: $API_ACCESS_KEY_ID"
print_warning "Secret Access Key: $API_SECRET_KEY"
print_warning ""
print_warning "IMPORTANT: Save these credentials! The Secret Access Key cannot be retrieved again."
print_warning "Use these credentials to login to the website at: $WEBSITE_URL"
echo ""
print_status "=== Authentication ==="
print_status "This app uses AWS IAM authentication (AWS Signature V4)"
print_status "Requests must be signed with valid AWS credentials"
echo ""
print_status "To test with AWS CLI:"
print_status "  aws apigatewayv2 invoke-api --api-id <api-id> --stage $ENVIRONMENT --path /files $PROFILE_FLAG"
