# Social Media Backend - Simplified Architecture

## Overview
This is a simplified microservices architecture with just two services:
- **Auth Service** (Port 8081) - Handles user authentication and JWT tokens
- **API Gateway** (Port 8080) - Routes requests to backend services

**Note:** Eureka Server and Social Service have been removed from this setup.

## Architecture

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│  API Gateway    │ :8080
│                 │
│ Routes:         │
│ /api/auth/**    │ ──────┐
└─────────────────┘        │
                           ▼
                    ┌──────────────┐
                    │ Auth Service │ :8081
                    │              │
                    │ - Register   │
                    │ - Login      │
                    │ - JWT Tokens │
                    └──────┬───────┘
                           │
                           ▼
                    ┌─────────────┐
                    │    MySQL    │
                    │   Database  │
                    └─────────────┘
```

## Services

### API Gateway (Port 8080)
- Entry point for all client requests
- Routes traffic directly to Auth Service (no service discovery)
- Handles CORS configuration
- JWT validation for protected routes

**Configuration:**
- Direct routing: `http://localhost:8081`
- No Eureka dependency

### Auth Service (Port 8081)
- User registration and authentication
- JWT token generation and validation
- Password encryption
- Redis for token caching

**Configuration:**
- Database: MySQL on port 3306
- Redis: localhost:6379
- No Eureka registration

## Prerequisites

1. **Java Development Kit (JDK) 17+**
2. **Maven 3.6+**
3. **MySQL** running on port 3306
   - Database: `auth_db`
   - Username: `root`
   - Password: `8144268322`
4. **Redis** running on port 6379

## Quick Start

### 1. Setup MySQL Database

```sql
CREATE DATABASE IF NOT EXISTS auth_db;
```

### 2. Start Redis

```bash
# Windows
redis-server

# Or use Docker
docker run -d -p 6379:6379 redis:latest
```

### 3. Start Services

Run the startup script from the project root:

```powershell
cd "c:\Users\gidut\OneDrive\html files\Projects\Freelance\Social media backend"
.\start-services-simple.ps1
```

The script will:
1. Check and kill any existing processes on ports 8080 and 8081
2. Start Auth Service (wait 15 seconds)
3. Start API Gateway (wait 10 seconds)
4. Display service status

### 4. Verify Services

- Auth Service: http://localhost:8081/actuator/health
- API Gateway: http://localhost:8080/actuator/health

## API Endpoints

### User Registration

```bash
POST http://localhost:8080/api/auth/register
Content-Type: application/json

{
  "username": "testuser",
  "email": "test@example.com",
  "password": "password123"
}
```

### User Login

```bash
POST http://localhost:8080/api/auth/login
Content-Type: application/json

{
  "username": "testuser",
  "password": "password123"
}
```

Response:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "type": "Bearer",
  "expiresIn": 86400000
}
```

## Manual Service Start

If you prefer to start services manually:

### Start Auth Service
```powershell
cd "c:\Users\gidut\OneDrive\html files\Projects\Freelance\Social media backend\auth-service"
mvn spring-boot:run
```

### Start API Gateway
```powershell
cd "c:\Users\gidut\OneDrive\html files\Projects\Freelance\Social media backend\api-gateway"
mvn spring-boot:run
```

## Changes from Original Architecture

### Removed Components:
1. **Eureka Server** - No longer needed for service discovery
2. **Social Service** - Removed from this simplified setup

### Configuration Changes:
1. **API Gateway**
   - Removed `spring-cloud-starter-netflix-eureka-client` dependency
   - Changed routing from `lb://auth-service` to `http://localhost:8081`
   - Removed Eureka configuration
   - Removed `@EnableDiscoveryClient` annotation

2. **Auth Service**
   - Removed `spring-cloud-starter-netflix-eureka-client` dependency
   - Removed Eureka configuration
   - Removed `@EnableDiscoveryClient` annotation

## Troubleshooting

### Port Already in Use
```powershell
# Kill process on port 8080
netstat -ano | findstr :8080
taskkill /PID <process_id> /F

# Kill process on port 8081
netstat -ano | findstr :8081
taskkill /PID <process_id> /F
```

### Database Connection Issues
- Verify MySQL is running: `mysql -u root -p`
- Check database exists: `SHOW DATABASES;`
- Verify password in `auth-service/src/main/resources/application.properties`

### Redis Connection Issues
- Check if Redis is running: `redis-cli ping` (should return PONG)
- Default port: 6379

## Project Structure

```
social-media-backend/
├── api-gateway/
│   ├── src/main/java/com/socialmedia/gateway/
│   │   └── ApiGatewayApplication.java
│   └── src/main/resources/
│       └── application.properties
├── auth-service/
│   ├── src/main/java/com/socialmedia/auth/
│   │   ├── AuthServiceApplication.java
│   │   ├── controller/
│   │   ├── service/
│   │   ├── repository/
│   │   └── model/
│   └── src/main/resources/
│       └── application.properties
└── start-services-simple.ps1
```

## Development Notes

- Auth Service starts first to ensure it's ready before Gateway routes to it
- No service discovery means services communicate via direct HTTP URLs
- Simpler architecture with fewer moving parts
- Easier to debug and maintain

## Next Steps

To add more services:
1. Create new Spring Boot service
2. Add route configuration in API Gateway's `application.properties`
3. Update the startup script to include the new service
