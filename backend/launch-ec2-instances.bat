@echo off
REM Quick EC2 instance launcher for Windows

echo ========================================
echo  EC2 Instance Launcher
echo ========================================
echo.

REM Get AMI ID
echo Getting latest Amazon Linux 2023 AMI...
for /f %%i in ('aws ec2 describe-images --owners amazon --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text') do set AMI_ID=%%i
echo AMI ID: %AMI_ID%
echo.

REM Get stack outputs
echo Getting infrastructure details...
for /f %%i in ('aws cloudformation describe-stacks --stack-name social-media-backend --query "Stacks[0].Outputs[?OutputKey=='ApplicationSecurityGroupId'].OutputValue" --output text') do set SG_ID=%%i
for /f %%i in ('aws cloudformation describe-stacks --stack-name social-media-backend --query "Stacks[0].Outputs[?OutputKey=='PublicSubnet1Id'].OutputValue" --output text') do set SUBNET_ID=%%i

echo Security Group: %SG_ID%
echo Subnet: %SUBNET_ID%
echo.

echo Choose service to launch:
echo 1. Auth Service
echo 2. Social Service
echo 3. API Gateway
echo 4. All Services
echo.
set /p choice="Enter choice (1-4): "

if "%choice%"=="1" goto auth
if "%choice%"=="2" goto social
if "%choice%"=="3" goto gateway
if "%choice%"=="4" goto all
goto end

:auth
echo Launching Auth Service...
aws ec2 run-instances --image-id %AMI_ID% --instance-type t3.small --key-name social-media-key --security-group-ids %SG_ID% --subnet-id %SUBNET_ID% --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=auth-service},{Key=Service,Value=auth}]" --user-data file://ec2-user-data-java.sh --associate-public-ip-address
goto end

:social
echo Launching Social Service...
aws ec2 run-instances --image-id %AMI_ID% --instance-type t3.small --key-name social-media-key --security-group-ids %SG_ID% --subnet-id %SUBNET_ID% --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=social-service},{Key=Service,Value=social}]" --user-data file://ec2-user-data-java.sh --associate-public-ip-address
goto end

:gateway
echo Launching API Gateway...
aws ec2 run-instances --image-id %AMI_ID% --instance-type t3.small --key-name social-media-key --security-group-ids %SG_ID% --subnet-id %SUBNET_ID% --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=api-gateway},{Key=Service,Value=gateway}]" --user-data file://ec2-user-data-java.sh --associate-public-ip-address
goto end

:all
echo Launching all services...
echo.
echo Auth Service:
aws ec2 run-instances --image-id %AMI_ID% --instance-type t3.small --key-name social-media-key --security-group-ids %SG_ID% --subnet-id %SUBNET_ID% --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=auth-service},{Key=Service,Value=auth}]" --user-data file://ec2-user-data-java.sh --associate-public-ip-address
timeout /t 2 /nobreak >nul
echo.
echo Social Service:
aws ec2 run-instances --image-id %AMI_ID% --instance-type t3.small --key-name social-media-key --security-group-ids %SG_ID% --subnet-id %SUBNET_ID% --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=social-service},{Key=Service,Value=social}]" --user-data file://ec2-user-data-java.sh --associate-public-ip-address
timeout /t 2 /nobreak >nul
echo.
echo API Gateway:
aws ec2 run-instances --image-id %AMI_ID% --instance-type t3.small --key-name social-media-key --security-group-ids %SG_ID% --subnet-id %SUBNET_ID% --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=api-gateway},{Key=Service,Value=gateway}]" --user-data file://ec2-user-data-java.sh --associate-public-ip-address

:end
echo.
echo ========================================
echo Wait 2-3 minutes for instances to launch, then run:
echo   get-instance-ips.bat
echo ========================================
pause
