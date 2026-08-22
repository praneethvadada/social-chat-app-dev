# Local Development Setup (Without Docker)

This guide will help you run all services locally without Docker.

## Prerequisites

- **Java 17** or higher
- **Maven 3.8+**
- **MySQL 8.0+** installed locally
- **Redis** installed locally

## 1. Install Required Software

### Windows

**MySQL:**
```powershell
# Download and install from: https://dev.mysql.com/downloads/installer/
# Or use chocolatey:
choco install mysql
```

**Redis:**
```powershell
# Download from: https://github.com/microsoftarchive/redis/releases
# Or use chocolatey:
choco install redis-64
```

### Linux (Ubuntu/Debian)

```bash
# MySQL
sudo apt update
sudo apt install mysql-server

# Redis
sudo apt install redis-server
```

### macOS

```bash
# Using Homebrew
brew install mysql
brew install redis
```

## 2. Database Setup

### Start MySQL

```bash
# Windows
net start MySQL80

# Linux
sudo systemctl start mysql

# macOS
brew services start mysql
```

### Create Databases

```bash
# Login to MySQL
mysql -u root -p

# Create databases
CREATE DATABASE auth_db;
CREATE DATABASE social_db;

# Create user (optional but recommended)
CREATE USER 'socialapp'@'localhost' IDENTIFIED BY 'socialapp123';
GRANT ALL PRIVILEGES ON auth_db.* TO 'socialapp'@'localhost';
GRANT ALL PRIVILEGES ON social_db.* TO 'socialapp'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

## 3. Redis Setup

### Start Redis

```bash
# Windows
redis-server

# Linux
sudo systemctl start redis

# macOS
brew services start redis
```

### Verify Redis is Running

```bash
redis-cli ping
# Should return: PONG
```

## 4. Configure Services for Local Development

All services are already configured to work locally by default. The `application.properties` files use `localhost` connections.

### Verify Configuration

**Auth Service** (`auth-service/src/main/resources/application.properties`):
```properties
spring.datasource.url=jdbc:mysql://localhost:3306/auth_db?createDatabaseIfNotExist=true&useSSL=false&serverTimezone=UTC
spring.datasource.username=root
spring.datasource.password=root123  # Change to your MySQL password
spring.data.redis.host=localhost
```

**Social Service** (`social-service/src/main/resources/application.properties`):
```properties
spring.datasource.url=jdbc:mysql://localhost:3306/social_db?createDatabaseIfNotExist=true&useSSL=false&serverTimezone=UTC
spring.datasource.username=root
spring.datasource.password=root123  # Change to your MySQL password
spring.data.redis.host=localhost
```

## 5. Build All Services

```bash
# From the root directory
mvn clean install -DskipTests
```

Or use the build scripts:
```bash
# Linux/Mac
./build.sh

# Windows
.\build.ps1
```

## 6. Start Services (In Order)

Open **4 separate terminal windows** and run:

### Terminal 1: Eureka Server

```bash
cd eureka-server
mvn spring-boot:run
```

Wait until you see: `Started EurekaServerApplication`

Verify at: http://localhost:8761

### Terminal 2: Auth Service

```bash
cd auth-service
mvn spring-boot:run
```

Wait until you see: `Started AuthServiceApplication`

### Terminal 3: Social Service

```bash
cd social-service
mvn spring-boot:run
```

Wait until you see: `Started SocialServiceApplication`

### Terminal 4: API Gateway

```bash
cd api-gateway
mvn spring-boot:run
```

Wait until you see: `Started ApiGatewayApplication`

## 7. Verify Services Are Running

### Check Eureka Dashboard
```
http://localhost:8761
```
You should see all 3 services registered:
- AUTH-SERVICE
- SOCIAL-SERVICE  
- API-GATEWAY

### Health Checks
```bash
# Auth Service
curl http://localhost:8081/actuator/health

# Social Service
curl http://localhost:8082/actuator/health

# API Gateway
curl http://localhost:8080/actuator/health
```

## 8. Test the API

### Register a User

```bash
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123",
    "fullName": "Test User"
  }'
```

### Login

```bash
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

Save the `accessToken` from the response.

### Create a Post

```bash
TOKEN="your-access-token-here"

curl -X POST http://localhost:8080/api/social/posts \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{
    "content": "My first post!",
    "isPublic": true
  }'
```

### Get Feed

```bash
curl -X GET http://localhost:8080/api/social/posts/feed \
  -H "Authorization: Bearer $TOKEN"
```

## 9. Access URLs

| Service | URL | Description |
|---------|-----|-------------|
| API Gateway | http://localhost:8080 | Main entry point for all API calls |
| Eureka Server | http://localhost:8761 | Service registry dashboard (admin/admin123) |
| Auth Service | http://localhost:8081 | Direct access (not recommended) |
| Social Service | http://localhost:8082 | Direct access (not recommended) |
| MySQL Auth DB | localhost:3306 | Database for authentication |
| MySQL Social DB | localhost:3306 | Database for social features |
| Redis | localhost:6379 | Cache and rate limiting |

## 10. Recommended API Testing Tools

### Using curl (Command Line)
See examples above and in `docs/API-TESTING.md`

### Using Postman
1. Import the API collection
2. Set base URL to: `http://localhost:8080/api`
3. Set token variable after login

### Using VS Code REST Client
Install "REST Client" extension and use `.http` files

## 11. Stopping Services

Press `Ctrl+C` in each terminal window to stop the services.

Or if running in background:
```bash
# Find Java processes
jps

# Kill specific process
kill <PID>
```

## 12. Development Tips

### Hot Reload with Spring DevTools

Add to each service's `pom.xml`:
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-devtools</artifactId>
    <scope>runtime</scope>
    <optional>true</optional>
</dependency>
```

Then services will auto-restart on code changes.

### View Logs

Logs are displayed in the terminal. Adjust log levels in `application.properties`:
```properties
logging.level.com.socialmedia=DEBUG
logging.level.org.springframework.security=INFO
```

### Database Access

```bash
# MySQL
mysql -u root -p auth_db
mysql -u root -p social_db

# View tables
SHOW TABLES;
SELECT * FROM users;
SELECT * FROM posts;
```

### Redis Access

```bash
redis-cli

# View all keys
KEYS *

# Get value
GET refresh_token:1

# View all sessions
KEYS refresh_token:*
```

## 13. Troubleshooting

### Port Already in Use

```bash
# Windows - Find and kill process
netstat -ano | findstr :8080
taskkill /PID <PID> /F

# Linux/Mac - Find and kill process
lsof -i :8080
kill -9 <PID>
```

### MySQL Connection Error

1. Verify MySQL is running
2. Check credentials in `application.properties`
3. Ensure databases exist
4. Check firewall settings

```bash
# Test MySQL connection
mysql -u root -p -e "SHOW DATABASES;"
```

### Redis Connection Error

```bash
# Test Redis
redis-cli ping

# Should return: PONG

# If not running, start it:
redis-server
```

### Service Not Registering with Eureka

1. Ensure Eureka Server started first
2. Check network connectivity
3. Verify Eureka URL in service's `application.properties`
4. Wait 30 seconds for registration

### Build Errors

```bash
# Clean and rebuild
mvn clean install -DskipTests

# Update dependencies
mvn dependency:purge-local-repository
mvn clean install
```

## 14. Environment-Specific Configuration

### Development Profile

Create `application-dev.properties` in each service:

```properties
# Development specific settings
spring.jpa.show-sql=true
logging.level.root=DEBUG
```

Run with:
```bash
mvn spring-boot:run -Dspring-boot.run.profiles=dev
```

### Change MySQL Password

Update in all service's `application.properties`:
```properties
spring.datasource.password=YOUR_PASSWORD
```

### Change Redis Configuration

```properties
spring.data.redis.host=localhost
spring.data.redis.port=6379
spring.data.redis.password=  # If you set one
```

## 15. Quick Start Script

### Linux/Mac (`start-local.sh`)

```bash
#!/bin/bash

# Start MySQL
sudo systemctl start mysql

# Start Redis
sudo systemctl start redis

# Start Eureka
cd eureka-server
mvn spring-boot:run &
EUREKA_PID=$!
echo "Eureka PID: $EUREKA_PID"
sleep 30

# Start Auth Service
cd ../auth-service
mvn spring-boot:run &
AUTH_PID=$!
echo "Auth Service PID: $AUTH_PID"
sleep 20

# Start Social Service
cd ../social-service
mvn spring-boot:run &
SOCIAL_PID=$!
echo "Social Service PID: $SOCIAL_PID"
sleep 20

# Start API Gateway
cd ../api-gateway
mvn spring-boot:run &
GATEWAY_PID=$!
echo "API Gateway PID: $GATEWAY_PID"

echo "All services started!"
echo "Eureka: http://localhost:8761"
echo "API Gateway: http://localhost:8080"
```

### Windows (`start-local.ps1`)

```powershell
# Start MySQL
net start MySQL80

# Start Redis
Start-Process redis-server

# Start services in separate windows
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd eureka-server; mvn spring-boot:run"
Start-Sleep -Seconds 30

Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd auth-service; mvn spring-boot:run"
Start-Sleep -Seconds 20

Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd social-service; mvn spring-boot:run"
Start-Sleep -Seconds 20

Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd api-gateway; mvn spring-boot:run"

Write-Host "All services started in separate windows!"
```

## 16. Production Considerations

For production deployment without Docker, consider:

1. **Systemd Services** (Linux) - Create service files for auto-start
2. **Windows Services** - Use NSSM or similar tools
3. **Process Managers** - PM2, supervisord
4. **Reverse Proxy** - Install and configure Nginx locally
5. **Monitoring** - Set up application monitoring
6. **Log Management** - Configure log rotation

## Need Help?

- Check logs in the terminal output
- Verify MySQL and Redis are running
- Ensure no port conflicts
- Check firewall settings
- Review `application.properties` configurations

For detailed API documentation, see: `docs/API-TESTING.md`
For security details, see: `docs/SECURITY.md`
