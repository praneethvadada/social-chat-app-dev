# AWS Infrastructure Setup Script
# This script creates all necessary AWS resources using CloudFormation

Write-Host "🚀 Setting up AWS Infrastructure for Social Media Backend" -ForegroundColor Cyan
Write-Host ""

# Check if AWS CLI is installed
$awsVersion = aws --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ AWS CLI is not installed. Please install it first:" -ForegroundColor Red
    Write-Host "   https://aws.amazon.com/cli/" -ForegroundColor Yellow
    exit 1
}

Write-Host "✓ AWS CLI detected: $awsVersion" -ForegroundColor Green
Write-Host ""

# Get parameters
$StackName = Read-Host "Enter stack name (e.g., social-media-backend)"
if ([string]::IsNullOrWhiteSpace($StackName)) {
    $StackName = "social-media-backend"
}

$DBPassword = Read-Host "Enter database password (min 8 characters)" -AsSecureString
$DBPasswordPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($DBPassword)
)

if ($DBPasswordPlain.Length -lt 8) {
    Write-Host "❌ Password must be at least 8 characters long" -ForegroundColor Red
    exit 1
}

$Region = Read-Host "Enter AWS region (default: us-east-1)"
if ([string]::IsNullOrWhiteSpace($Region)) {
    $Region = "us-east-1"
}

Write-Host ""
Write-Host "Creating CloudFormation stack..." -ForegroundColor Cyan
Write-Host "  Stack Name: $StackName" -ForegroundColor Yellow
Write-Host "  Region: $Region" -ForegroundColor Yellow
Write-Host ""

# Create stack
aws cloudformation create-stack `
    --stack-name $StackName `
    --template-body file://aws-infrastructure.yml `
    --parameters ParameterKey=DBPassword,ParameterValue=$DBPasswordPlain `
    --region $Region

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Stack creation initiated!" -ForegroundColor Green
    Write-Host ""
    Write-Host "⏳ Waiting for stack creation to complete (this may take 10-15 minutes)..." -ForegroundColor Cyan
    
    aws cloudformation wait stack-create-complete --stack-name $StackName --region $Region
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "✅ Infrastructure created successfully!" -ForegroundColor Green
        Write-Host ""
        
        # Get outputs
        Write-Host "📋 Infrastructure Details:" -ForegroundColor Cyan
        $outputs = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs' --output table
        Write-Host $outputs
        
        # Save environment variables
        $envFile = "aws-environment-variables.txt"
        Write-Host ""
        Write-Host "💾 Saving environment variables to $envFile..." -ForegroundColor Cyan
        
        $dbEndpoint = (aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[?OutputKey==`DBEndpoint`].OutputValue' --output text)
        $redisEndpoint = (aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[?OutputKey==`RedisEndpoint`].OutputValue' --output text)
        $s3Bucket = (aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' --output text)
        
        @"
# AWS Environment Variables for $StackName
# Generated: $(Get-Date)

# Database Configuration
SPRING_DATASOURCE_URL=jdbc:mysql://${dbEndpoint}:3306/auth_db
SPRING_DATASOURCE_USERNAME=admin
SPRING_DATASOURCE_PASSWORD=$DBPasswordPlain

# Redis Configuration
SPRING_DATA_REDIS_HOST=$redisEndpoint
SPRING_DATA_REDIS_PORT=6379

# S3 Configuration
AWS_S3_BUCKET=$s3Bucket
AWS_REGION=$Region
AWS_S3_ENABLED=true

# JWT Secret (change in production!)
JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437

# Application URLs (update after deploying services)
AUTH_SERVICE_URL=http://your-auth-service-url
SOCIAL_SERVICE_URL=http://your-social-service-url

# Server Port (Elastic Beanstalk uses 5000)
SERVER_PORT=5000

# Spring Profile
SPRING_PROFILES_ACTIVE=prod
"@ | Out-File -FilePath $envFile -Encoding UTF8
        
        Write-Host "✓ Environment variables saved to $envFile" -ForegroundColor Green
        Write-Host ""
        Write-Host "📝 Next Steps:" -ForegroundColor Cyan
        Write-Host "  1. Review $envFile" -ForegroundColor Yellow
        Write-Host "  2. Build your applications: .\build-for-aws.bat" -ForegroundColor Yellow
        Write-Host "  3. Deploy to Elastic Beanstalk or EC2 (see AWS_DEPLOYMENT_GUIDE.md)" -ForegroundColor Yellow
        Write-Host "  4. Configure environment variables in your deployment" -ForegroundColor Yellow
        Write-Host ""
    } else {
        Write-Host "❌ Stack creation failed. Check AWS Console for details." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "❌ Failed to initiate stack creation" -ForegroundColor Red
    exit 1
}
