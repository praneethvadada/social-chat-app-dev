@echo off
REM Get public and private IPs of all instances

echo ========================================
echo  Instance IP Addresses
echo ========================================
echo.

aws ec2 describe-instances --filters "Name=tag:Name,Values=auth-service,social-service,api-gateway" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[Tags[?Key=='Name'].Value|[0],InstanceId,PublicIpAddress,PrivateIpAddress,State.Name]" --output table

echo.
echo ========================================
echo Save these IPs for deployment!
echo ========================================
echo.
echo To SSH into instances:
echo   ssh -i social-media-key.pem ec2-user@PUBLIC_IP
echo.
pause
