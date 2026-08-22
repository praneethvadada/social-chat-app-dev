@echo off
REM Configure security group rules for EC2 deployment

echo ========================================
echo  Configure Security Group Rules
echo ========================================
echo.

REM Get security group ID
for /f %%i in ('aws cloudformation describe-stacks --stack-name social-media-backend --query "Stacks[0].Outputs[?OutputKey=='ApplicationSecurityGroupId'].OutputValue" --output text') do set SG_ID=%%i

echo Security Group: %SG_ID%
echo.

echo Adding security group rules...
echo.

REM Get your current IP
for /f %%i in ('curl -s https://checkip.amazonaws.com') do set MY_IP=%%i
echo Your IP: %MY_IP%

echo 1. Allowing SSH from your IP...
aws ec2 authorize-security-group-ingress --group-id %SG_ID% --protocol tcp --port 22 --cidr %MY_IP%/32 2>nul
if %errorlevel% equ 0 (echo    ✓ SSH access added) else (echo    - Already exists)

echo 2. Allowing HTTP to API Gateway...
aws ec2 authorize-security-group-ingress --group-id %SG_ID% --protocol tcp --port 8080 --cidr 0.0.0.0/0 2>nul
if %errorlevel% equ 0 (echo    ✓ HTTP access added) else (echo    - Already exists)

echo 3. Allowing Auth Service internal access...
aws ec2 authorize-security-group-ingress --group-id %SG_ID% --protocol tcp --port 8081 --source-group %SG_ID% 2>nul
if %errorlevel% equ 0 (echo    ✓ Auth Service access added) else (echo    - Already exists)

echo 4. Allowing Social Service internal access...
aws ec2 authorize-security-group-ingress --group-id %SG_ID% --protocol tcp --port 8082 --source-group %SG_ID% 2>nul
if %errorlevel% equ 0 (echo    ✓ Social Service access added) else (echo    - Already exists)

echo.
echo ========================================
echo Security group configuration complete!
echo ========================================
echo.
pause
