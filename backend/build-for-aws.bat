@echo off
REM Build all services for AWS deployment

REM Force Java 17 (project requires Java 17)
set "JAVA_HOME=C:\Program Files\Java\jdk-17"
set "PATH=%JAVA_HOME%\bin;%PATH%"

echo Building all services...
cd /d "%~dp0"
call mvn clean package -DskipTests

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful!
    echo.
    echo JAR files created:
    echo   - api-gateway/target/api-gateway-1.0.0.jar
    echo   - auth-service/target/auth-service-1.0.0.jar
    echo   - social-service/target/social-service-1.0.0.jar
    echo.
    echo Next steps:
    echo 1. Review AWS_DEPLOYMENT_GUIDE.md
    echo 2. Choose deployment method (Elastic Beanstalk or EC2^)
    echo 3. Set up AWS infrastructure (RDS, Redis^)
    echo 4. Deploy using chosen method
) else (
    echo.
    echo Build failed. Please fix errors and try again.
    exit /b 1
)
