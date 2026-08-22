@echo off
echo Stopping all services...
taskkill /F /IM java.exe 2>nul
timeout /t 3 /nobreak

echo Building and starting Auth Service...
cd auth-service
start "Auth Service" cmd /k "mvn clean spring-boot:run"
timeout /t 10 /nobreak

echo Building and starting Social Service...
cd ..\social-service
start "Social Service" cmd /k "mvn clean spring-boot:run"
timeout /t 10 /nobreak

echo Building and starting API Gateway...
cd ..\api-gateway
start "API Gateway" cmd /k "mvn clean spring-boot:run"
timeout /t 5 /nobreak

echo All services started!
echo Press any key to exit...
pause
