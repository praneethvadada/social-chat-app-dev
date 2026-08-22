@echo off 
set "JAVA_HOME=C:\Program Files\Java\jdk-17"
set "PATH=%JAVA_HOME%\bin;%PATH%"
"C:\Program Files\Java\jdk-17\bin\java" -version 
mvn clean package -DskipTests
