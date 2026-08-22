#!/bin/bash

# AWS S3 Bucket Setup Script for Social Media App
# This script creates and configures an S3 bucket for media storage

set -e

echo "========================================="
echo "AWS S3 Bucket Setup"
echo "========================================="
echo ""

# Configuration
read -p "Enter S3 bucket name [social-media-app-bucket]: " BUCKET_NAME
BUCKET_NAME=${BUCKET_NAME:-social-media-app-bucket}

read -p "Enter AWS region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

echo ""
echo "Creating S3 bucket: $BUCKET_NAME in region: $AWS_REGION"
echo ""

# Create S3 bucket
if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $AWS_REGION
else
    aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $AWS_REGION \
        --create-bucket-configuration LocationConstraint=$AWS_REGION
fi

echo "✓ Bucket created successfully"

# Block public access (we'll use ACLs on individual objects)
echo "Configuring public access settings..."
aws s3api put-public-access-block \
    --bucket $BUCKET_NAME \
    --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

echo "✓ Public access configured"

# Enable versioning (optional but recommended)
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled

echo "✓ Versioning enabled"

# Add CORS configuration for web access
echo "Configuring CORS..."
cat > /tmp/cors-config.json << 'EOF'
{
    "CORSRules": [
        {
            "AllowedOrigins": ["*"],
            "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
            "AllowedHeaders": ["*"],
            "ExposeHeaders": ["ETag"],
            "MaxAgeSeconds": 3000
        }
    ]
}
EOF

aws s3api put-bucket-cors \
    --bucket $BUCKET_NAME \
    --cors-configuration file:///tmp/cors-config.json

rm /tmp/cors-config.json

echo "✓ CORS configured"

# Add lifecycle policy to delete old files (optional)
read -p "Do you want to add a lifecycle policy to delete files older than 365 days? (yes/no): " ADD_LIFECYCLE
if [ "$ADD_LIFECYCLE" = "yes" ]; then
    echo "Configuring lifecycle policy..."
    cat > /tmp/lifecycle-policy.json << 'EOF'
{
    "Rules": [
        {
            "Id": "DeleteOldFiles",
            "Status": "Enabled",
            "Expiration": {
                "Days": 365
            }
        }
    ]
}
EOF

    aws s3api put-bucket-lifecycle-configuration \
        --bucket $BUCKET_NAME \
        --lifecycle-configuration file:///tmp/lifecycle-policy.json

    rm /tmp/lifecycle-policy.json
    echo "✓ Lifecycle policy configured"
fi

echo ""
echo "========================================="
echo "S3 Bucket Setup Complete!"
echo "========================================="
echo ""
echo "Bucket Name: $BUCKET_NAME"
echo "Region: $AWS_REGION"
echo "Bucket URL: https://$BUCKET_NAME.s3.$AWS_REGION.amazonaws.com/"
echo ""
echo "Update your social-service environment variables:"
echo "AWS_S3_BUCKET=$BUCKET_NAME"
echo "AWS_REGION=$AWS_REGION"
echo ""
echo "Make sure your EC2 instance has an IAM role with S3 permissions!"
echo "Required permissions: s3:PutObject, s3:GetObject, s3:DeleteObject"
echo ""
