@echo off
REM View Service Logs

set KEY=C:\Users\gidut\Downloads\social-media-key.pem
set IP=98.90.116.96

echo Select service to view logs:
echo 1. Social Service
echo 2. API Gateway
echo 3. Both (last 50 lines each)
echo 4. Social Service (live tail)
echo 5. API Gateway (live tail)
echo.
set /p choice="Enter choice (1-5): "

if "%choice%"=="1" (
    echo.
    echo === Social Service Logs (last 100 lines) ===
    ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo journalctl -u social-service -n 100 --no-pager"
) else if "%choice%"=="2" (
    echo.
    echo === API Gateway Logs (last 100 lines) ===
    ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo journalctl -u api-gateway -n 100 --no-pager"
) else if "%choice%"=="3" (
    echo.
    echo === Social Service Logs (last 50 lines) ===
    ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo journalctl -u social-service -n 50 --no-pager"
    echo.
    echo === API Gateway Logs (last 50 lines) ===
    ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo journalctl -u api-gateway -n 50 --no-pager"
) else if "%choice%"=="4" (
    echo.
    echo === Social Service Logs (live - Press Ctrl+C to exit) ===
    ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo journalctl -u social-service -f"
) else if "%choice%"=="5" (
    echo.
    echo === API Gateway Logs (live - Press Ctrl+C to exit) ===
    ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo journalctl -u api-gateway -f"
) else (
    echo Invalid choice!
)

echo.
pause
