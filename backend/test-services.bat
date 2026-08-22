@echo off
REM Test Deployed Services

set IP=98.90.116.96

echo ========================================
echo Testing Services on %IP%
echo ========================================
echo.

echo [1/4] Testing Social Service Health...
curl -s http://%IP%:8082/actuator/health
if %ERRORLEVEL% EQU 0 (
    echo   ✓ Social Service is responding
) else (
    echo   ✗ Social Service is NOT responding
)
echo.

echo [2/4] Testing API Gateway...
curl -s http://%IP%:8080/api/social/posts/explore
if %ERRORLEVEL% EQU 0 (
    echo   ✓ API Gateway is responding
) else (
    echo   ✗ API Gateway is NOT responding
)
echo.

echo [3/4] Testing WebSocket Endpoint...
curl -s http://%IP%:8082/ws
if %ERRORLEVEL% EQU 0 (
    echo   ✓ WebSocket endpoint is accessible
) else (
    echo   ✗ WebSocket endpoint is NOT accessible
)
echo.

echo [4/4] Testing Ports...
echo Checking if ports are open...
powershell -Command "Test-NetConnection -ComputerName %IP% -Port 8080 | Select-Object -ExpandProperty TcpTestSucceeded"
powershell -Command "Test-NetConnection -ComputerName %IP% -Port 8082 | Select-Object -ExpandProperty TcpTestSucceeded"
echo.

echo ========================================
echo Test Complete
echo ========================================
echo.
echo URLs:
echo   API:       http://%IP%:8080/api
echo   WebSocket: http://%IP%:8082/ws
echo   Swagger:   http://%IP%:8080/swagger-ui.html
echo.

pause
