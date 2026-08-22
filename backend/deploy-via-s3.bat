@echo off
echo ========================================
echo Deploying Auth Service via S3
echo ========================================

set JAR_FILE=auth-service\target\auth-service-1.0.0.jar
set S3_BUCKET=social-media-gidut-54513
set EC2_HOST=98.92.24.110
set TIMESTAMP=%DATE:~-4%%DATE:~4,2%%DATE:~7,2%_%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%
set TIMESTAMP=%TIMESTAMP: =0%

echo.
echo Step 1: Uploading JAR to S3...
aws s3 cp "%JAR_FILE%" "s3://%S3_BUCKET%/deployments/auth-service-%TIMESTAMP%.jar" --region us-east-1
if errorlevel 1 (
    echo ERROR: Failed to upload to S3. Configuring AWS credentials...
    aws configure set aws_access_key_id AKIAXMEVHBKQETI7IVX3
    aws configure set aws_secret_access_key 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
    aws configure set region us-east-1
    aws configure set output json
    
    echo Retrying upload...
    aws s3 cp "%JAR_FILE%" "s3://%S3_BUCKET%/deployments/auth-service-%TIMESTAMP%.jar" --region us-east-1
    if errorlevel 1 (
        echo ERROR: Upload failed. Please check AWS credentials.
        pause
        exit /b 1
    )
)

echo.
echo Step 2: Creating deployment script...
echo #!/bin/bash > deploy-temp.sh
echo set -e >> deploy-temp.sh
echo echo "Downloading JAR from S3..." >> deploy-temp.sh
echo aws s3 cp "s3://%S3_BUCKET%/deployments/auth-service-%TIMESTAMP%.jar" /tmp/auth-service-1.0.0.jar --region us-east-1 >> deploy-temp.sh
echo echo "Stopping auth-service..." >> deploy-temp.sh
echo sudo systemctl stop auth-service >> deploy-temp.sh
echo echo "Backing up old JAR..." >> deploy-temp.sh
echo sudo cp /opt/auth-service/auth-service.jar /opt/auth-service/auth-service.jar.backup 2^>^/dev/null ^|^| true >> deploy-temp.sh
echo echo "Installing new JAR..." >> deploy-temp.sh
echo sudo mv /tmp/auth-service-1.0.0.jar /opt/auth-service/auth-service.jar >> deploy-temp.sh
echo sudo chown ec2-user:ec2-user /opt/auth-service/auth-service.jar >> deploy-temp.sh
echo echo "Starting auth-service..." >> deploy-temp.sh
echo sudo systemctl start auth-service >> deploy-temp.sh
echo echo "Waiting for service to start..." >> deploy-temp.sh
echo sleep 10 >> deploy-temp.sh
echo echo "Checking service status..." >> deploy-temp.sh
echo sudo systemctl status auth-service --no-pager ^| head -20 >> deploy-temp.sh
echo echo "Testing OTP endpoint..." >> deploy-temp.sh
echo curl -X POST http://localhost:8081/otp/send -H "Content-Type: application/json" -d '{"email":"test@example.com"}' >> deploy-temp.sh

echo.
echo Step 3: Uploading deployment script to S3...
aws s3 cp deploy-temp.sh "s3://%S3_BUCKET%/deployments/deploy-auth.sh" --region us-east-1

echo.
echo ========================================
echo Files uploaded to S3!
echo ========================================
echo.
echo Now run these commands on EC2 (via AWS Console Session Manager):
echo.
echo aws s3 cp s3://%S3_BUCKET%/deployments/deploy-auth.sh /tmp/deploy-auth.sh --region us-east-1
echo chmod +x /tmp/deploy-auth.sh
echo /tmp/deploy-auth.sh
echo.
echo ========================================

del deploy-temp.sh 2>nul

echo.
echo Attempting to connect via Session Manager...
echo (This may fail if Session Manager plugin is not installed)
echo.

aws ssm start-session --target i-0139d8ec8d73b924f --region us-east-1

pause
