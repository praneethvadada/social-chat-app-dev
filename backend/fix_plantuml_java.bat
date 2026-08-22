@echo off
REM PlantUML Java Configuration Fix
REM This script helps configure PlantUML to use JDK 17

echo Setting JAVA_HOME to JDK 17...
set JAVA_HOME=C:\Program Files\Java\jdk-17
set PATH=%JAVA_HOME%\bin;%PATH%

echo JAVA_HOME is now: %JAVA_HOME%
echo Java version:
java -version

echo.
echo PlantUML should now work with JDK 17.
echo If you're still having issues, try restarting VS Code.
pause