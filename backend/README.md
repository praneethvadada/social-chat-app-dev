# Social Media Backend - Microservices Architecture

A complete, production-ready social media backend built with Spring Boot microservices architecture, featuring real-time chat, comprehensive security, and scalable deployment.

## 🏗️ Architecture Overview

```
                                    ┌─────────────────┐
                                    │  Nginx Reverse  │
                                    │      Proxy      │
                                    │  (Port 80/443)  │
                                    └────────┬────────┘
                                             │
                                    ┌────────▼────────┐
                                    │   API Gateway   │
                                    │   (Port 8080)   │
                                    │  Rate Limiting  │
                                    │  JWT Validation │
                                    └────────┬────────┘
                                             │
                        ┌────────────────────┼────────────────────┐
                        │                    │                    │
                ┌───────▼────────┐  ┌───────▼────────┐  ┌───────▼────────┐
                │  Auth Service  │  │ Social Service │  │ Eureka Server  │
                │  (Port 8081)   │  │  (Port 8082)   │  │  (Port 8761)   │
                │  - JWT Auth    │  │  - Posts       │  │  - Discovery   │
                │  - User Mgmt   │  │  - Comments    │  │  - Registry    │
                └───────┬────────┘  │  - Likes       │  └────────────────┘
                        │           │  - Followers   │
                        │           │  - Real-time   │
                        │           │    Chat (WS)   │
                        │           └───────┬────────┘
                        │                   │
        ┌───────────────┼───────────────────┼───────────────┐
        │               │                   │               │
   ┌────▼─────┐   ┌────▼─────┐      ┌─────▼──────┐  ┌────▼─────┐
   │  MySQL   │   │  MySQL   │      │   Redis    │  │  Redis   │
   │ Auth DB  │   │Social DB │      │  Sessions  │  │  Cache   │
   │(Port 3307)│  │(Port 3308)│      │(Port 6379) │  │Rate Limit│
   └──────────┘   └──────────┘      └────────────┘  └──────────┘
```

## ✨ Features

### 🔐 Authentication & Security
- **JWT Token Authentication** with refresh tokens
- **Account lockout** after failed login attempts
- **BCrypt password hashing** (strength: 12)
- **Redis-based session management**
- **Rate limiting** at gateway and nginx levels
- **CORS protection** with configurable origins
- **Security headers** (CSP, XSS, HSTS, X-Frame-Options)
- **SQL injection prevention** via JPA/Hibernate
- **Input validation** with Bean Validation

### 📱 Social Media Features
- **Posts**: Create, read, update, delete with media support
- **Comments**: Nested comments with replies
- **Likes**: Like posts and comments
- **Followers**: Follow/unfollow users, followers/following lists
- **Real-time Chat**: WebSocket-based messaging
- **Feed**: Personalized feed from followed users
- **Explore**: Discover public posts
- **Shares**: Share posts with counters

### 🔥 Real-time Communication
- **WebSocket** integration via STOMP
- **Real-time notifications** for new messages
- **Online presence** tracking
- **Message read receipts**
- **Unread message counters**

### 🛡️ Infrastructure Security
- **Nginx Reverse Proxy** as firewall
- **TLS/SSL** support (HTTPS)
- **Rate limiting zones** (general, auth)
- **Connection limits** per IP
- **DDoS protection** via nginx
- **Service isolation** in Docker network

## 📋 Prerequisites

- **Java 17** or higher
- **Maven 3.8+**
- **MySQL 8.0+** (required)
- **Redis 7+** (required)
- **Docker & Docker Compose** (optional - only if you want to use Docker)

## 🚀 Quick Start

You have **two options** to run the application:

### Option 1: Local Setup (Without Docker) ⭐ **Recommended for Development**

#### 1. Install Prerequisites

Make sure you have **MySQL** and **Redis** installed and running locally.

**Windows:**
```powershell
# Install MySQL and Redis using chocolatey
choco install mysql redis-64

# Or download installers from official websites
```

**Linux:**
```bash
sudo apt install mysql-server redis-server
```

**macOS:**
```bash
brew install mysql redis
```

#### 2. Setup Databases

```bash
# Login to MySQL
mysql -u root -p

# Create databases
CREATE DATABASE auth_db;
CREATE DATABASE social_db;
EXIT;
```

#### 3. Start Services

**Windows:**
```powershell
# Make sure MySQL and Redis are running
net start MySQL80
redis-server

# Build and start all services
.\start-local.ps1
```

**Linux/Mac:**
```bash
# Make sure MySQL and Redis are running
sudo systemctl start mysql redis

# Build and start all services
chmod +x start-local.sh
./start-local.sh
```

This will start:
- **API Gateway** on port 8080
- **Eureka Server** on port 8761
- **Auth Service** on port 8081
- **Social Service** on port 8082

#### 4. Test the Setup

```bash
# Windows
.\test-local.ps1

# Linux/Mac
./test-local.sh
```

#### 5. Stop Services

```bash
# Windows
.\stop-local.ps1

# Linux/Mac
./stop-local.sh
```

**📖 For detailed local setup instructions, see:** [`docs/LOCAL-SETUP.md`](docs/LOCAL-SETUP.md)

---

### Option 2: Docker Setup (Optional)

If you prefer using Docker:

#### 1. Build All Services

```bash
mvn clean package -DskipTests
```

#### 2. Start with Docker Compose

```bash
docker-compose up -d
```

This will start:
- **Nginx** on port 80 (HTTP) and 443 (HTTPS)
- **API Gateway** on port 8080
- **Eureka Server** on port 8761
- **Auth Service** on port 8081
- **Social Service** on port 8082
- **MySQL Auth DB** on port 3307
- **MySQL Social DB** on port 3308
- **Redis** on port 6379

#### 3. Verify Services

Check Eureka Dashboard:
```
http://localhost:8761
```
Username: `admin`, Password: `admin123`

Health checks:
```bash
curl http://localhost/health
curl http://localhost:8080/actuator/health
```

## 📚 API Documentation

### Base URL
```
Production: https://your-domain.com/api
Local (with Docker/Nginx): http://localhost/api
Local (without Docker): http://localhost:8080/api
Direct Gateway: http://localhost:8080/api
```

**Note:** When running locally without Docker, use `http://localhost:8080/api` as your base URL.

### Authentication Endpoints

#### Register User
```http
POST /api/auth/register
Content-Type: application/json

{
  "username": "johndoe",
  "email": "john@example.com",
  "password": "securePass123",
  "fullName": "John Doe"
}

Response: 200 OK
{
  "accessToken": "eyJhbGc...",
  "refreshToken": "eyJhbGc...",
  "tokenType": "Bearer",
  "userId": 1,
  "username": "johndoe",
  "email": "john@example.com"
}
```

#### Login
```http
POST /api/auth/login
Content-Type: application/json

{
  "email": "john@example.com",
  "password": "securePass123"
}

Response: 200 OK
{
  "accessToken": "eyJhbGc...",
  "refreshToken": "eyJhbGc...",
  "tokenType": "Bearer",
  "userId": 1,
  "username": "johndoe",
  "email": "john@example.com"
}
```

#### Refresh Token
```http
POST /api/auth/refresh?refreshToken=eyJhbGc...

Response: 200 OK
{
  "accessToken": "eyJhbGc...",
  "refreshToken": "eyJhbGc...",
  ...
}
```

#### Logout
```http
POST /api/auth/logout
Authorization: Bearer eyJhbGc...

Response: 200 OK
```

### Social Endpoints (Requires Authentication)

All social endpoints require `Authorization: Bearer <token>` header.

#### Posts

**Create Post**
```http
POST /api/social/posts
Authorization: Bearer <token>
Content-Type: application/json

{
  "content": "Hello, world!",
  "mediaUrls": ["https://example.com/image.jpg"],
  "isPublic": true
}
```

**Get User Feed**
```http
GET /api/social/posts/feed?page=0&size=20
Authorization: Bearer <token>
```

**Get Explore Posts**
```http
GET /api/social/posts/explore?page=0&size=20
Authorization: Bearer <token>
```

**Get User Posts**
```http
GET /api/social/posts/user/{userId}?page=0&size=20
Authorization: Bearer <token>
```

**Update Post**
```http
PUT /api/social/posts/{postId}
Authorization: Bearer <token>
Content-Type: application/json

{
  "content": "Updated content",
  "mediaUrls": [],
  "isPublic": true
}
```

**Delete Post**
```http
DELETE /api/social/posts/{postId}
Authorization: Bearer <token>
```

**Share Post**
```http
POST /api/social/posts/{postId}/share
Authorization: Bearer <token>
```

#### Comments

**Create Comment**
```http
POST /api/social/comments
Authorization: Bearer <token>
Content-Type: application/json

{
  "postId": 1,
  "content": "Great post!",
  "parentCommentId": null
}
```

**Get Post Comments**
```http
GET /api/social/comments/post/{postId}?page=0&size=20
Authorization: Bearer <token>
```

**Get Comment Replies**
```http
GET /api/social/comments/{commentId}/replies?page=0&size=20
Authorization: Bearer <token>
```

**Delete Comment**
```http
DELETE /api/social/comments/{commentId}
Authorization: Bearer <token>
```

#### Likes

**Like Entity (Post or Comment)**
```http
POST /api/social/likes/{entityType}/{entityId}
Authorization: Bearer <token>

# entityType: POST or COMMENT
# Example: POST /api/social/likes/POST/123
```

**Unlike Entity**
```http
DELETE /api/social/likes/{entityType}/{entityId}
Authorization: Bearer <token>
```

**Get Like Info**
```http
GET /api/social/likes/{entityType}/{entityId}
Authorization: Bearer <token>

Response:
{
  "count": 42,
  "isLiked": true
}
```

#### Followers

**Follow User**
```http
POST /api/social/followers/{userId}
Authorization: Bearer <token>
```

**Unfollow User**
```http
DELETE /api/social/followers/{userId}
Authorization: Bearer <token>
```

**Get Followers**
```http
GET /api/social/followers/user/{userId}
Authorization: Bearer <token>
```

**Get Following**
```http
GET /api/social/followers/user/{userId}/following
Authorization: Bearer <token>
```

**Get User Stats**
```http
GET /api/social/followers/user/{userId}/stats
Authorization: Bearer <token>

Response:
{
  "followersCount": 150,
  "followingCount": 200,
  "isFollowing": true
}
```

#### Messages (Real-time Chat)

**Send Message (HTTP)**
```http
POST /api/social/messages
Authorization: Bearer <token>
Content-Type: application/json

{
  "receiverId": 2,
  "content": "Hello!",
  "mediaUrl": null
}
```

**Get Conversation**
```http
GET /api/social/messages/conversation/{otherUserId}?page=0&size=50
Authorization: Bearer <token>
```

**Mark Message as Read**
```http
PUT /api/social/messages/{messageId}/read
Authorization: Bearer <token>
```

**Get Unread Count**
```http
GET /api/social/messages/unread-count
Authorization: Bearer <token>

Response:
{
  "unreadCount": 5
}
```

#### WebSocket Chat

**Connect to WebSocket**
```javascript
const socket = new SockJS('http://localhost/api/social/ws');
const stompClient = Stomp.over(socket);

stompClient.connect({
  'Authorization': 'Bearer ' + token
}, function(frame) {
  // Subscribe to receive messages
  stompClient.subscribe('/user/queue/messages', function(message) {
    console.log('New message:', JSON.parse(message.body));
  });
  
  // Send a message
  stompClient.send('/app/chat.send', {}, JSON.stringify({
    receiverId: 2,
    content: 'Hello via WebSocket!'
  }));
});
```

## 🔒 Security Features Implemented

### 1. Authentication Security
- JWT tokens with expiration (24 hours for access, 7 days for refresh)
- Secure token storage in Redis
- Account lockout after 5 failed attempts (15 minutes)
- BCrypt password hashing

### 2. Network Security
- Nginx reverse proxy as first line of defense
- Rate limiting at multiple layers
- Connection limits per IP
- HTTPS/TLS encryption
- Security headers (HSTS, CSP, X-Frame-Options, etc.)

### 3. Application Security
- Input validation on all endpoints
- SQL injection prevention via JPA
- XSS protection via security headers
- CORS configuration
- JWT validation at API Gateway
- Service-to-service authentication

### 4. Infrastructure Security
- Isolated Docker network
- Health checks for all services
- Resource limits
- Service restart policies
- Separate databases per service

## ⚙️ Configuration

### Environment Variables

Create `.env` file for production:

```env
# Database
MYSQL_ROOT_PASSWORD=your_secure_password
AUTH_DB_NAME=auth_db
SOCIAL_DB_NAME=social_db

# JWT
JWT_SECRET=your_256_bit_secret_key
JWT_EXPIRATION=86400000
JWT_REFRESH_EXPIRATION=604800000

# Redis
REDIS_HOST=redis
REDIS_PORT=6379

# Eureka
EUREKA_USERNAME=admin
EUREKA_PASSWORD=your_eureka_password
```

### Rate Limiting Configuration

Adjust in `nginx/nginx.conf`:
```nginx
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/s;
```

### CORS Configuration

Adjust in `api-gateway/src/main/resources/application.properties`:
```properties
spring.cloud.gateway.globalcors.cors-configurations.[/**].allowed-origins=http://localhost:3000
```

## 🧪 Testing

### Run Unit Tests
```bash
mvn test
```

### Test with curl

**Register:**
```bash
curl -X POST http://localhost/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"test","email":"test@test.com","password":"pass123","fullName":"Test User"}'
```

**Login:**
```bash
curl -X POST http://localhost/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"pass123"}'
```

**Create Post:**
```bash
curl -X POST http://localhost/api/social/posts \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-token>" \
  -d '{"content":"My first post","isPublic":true}'
```

## 📊 Monitoring

### Eureka Dashboard
```
http://localhost:8761
```

### Health Endpoints
- Gateway: `http://localhost:8080/actuator/health`
- Auth Service: `http://localhost:8081/actuator/health`
- Social Service: `http://localhost:8082/actuator/health`

### Logs
```bash
# View all logs
docker-compose logs -f

# View specific service
docker-compose logs -f api-gateway
docker-compose logs -f auth-service
docker-compose logs -f social-service
```

## 🐛 Troubleshooting

### Services not starting
```bash
# Check service status
docker-compose ps

# Restart services
docker-compose restart

# Rebuild and restart
docker-compose up -d --build
```

### Database connection issues
```bash
# Check MySQL logs
docker-compose logs mysql-auth
docker-compose logs mysql-social

# Connect to MySQL
docker exec -it mysql-auth mysql -uroot -proot123
```

### Redis connection issues
```bash
# Check Redis
docker exec -it redis redis-cli ping

# Should return: PONG
```

### Port conflicts
```bash
# Stop existing services
docker-compose down

# Change ports in docker-compose.yml if needed
```

## 🚀 Production Deployment

### 1. SSL Certificates

Generate certificates:
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/key.pem -out nginx/ssl/cert.pem
```

Or use Let's Encrypt:
```bash
certbot certonly --standalone -d your-domain.com
```

### 2. Environment Variables

Set production values in docker-compose.yml or use `.env` file.

### 3. Database Backups

```bash
# Backup Auth DB
docker exec mysql-auth mysqldump -uroot -proot123 auth_db > auth_db_backup.sql

# Backup Social DB
docker exec mysql-social mysqldump -uroot -proot123 social_db > social_db_backup.sql
```

### 4. Scale Services

```bash
# Scale social service
docker-compose up -d --scale social-service=3
```

## 📝 Development

### Local Development (without Docker)

The application is configured to run locally by default. All services use `localhost` for database and Redis connections.

**Quick Start:**
```bash
# Windows
.\start-local.ps1

# Linux/Mac
./start-local.sh
```

**Manual Start (for debugging):**
```bash
# Terminal 1 - Eureka (wait 30s)
cd eureka-server && mvn spring-boot:run

# Terminal 2 - Auth Service (wait 20s)
cd auth-service && mvn spring-boot:run

# Terminal 3 - Social Service (wait 20s)
cd social-service && mvn spring-boot:run

# Terminal 4 - API Gateway
cd api-gateway && mvn spring-boot:run
```

### Configuration for Local Development

The default `application.properties` in each service is already configured for local development:

- **MySQL:** `localhost:3306`
- **Redis:** `localhost:6379`
- **Eureka:** `localhost:8761`

**To change MySQL credentials**, update in each service's `application.properties`:
```properties
spring.datasource.username=root
spring.datasource.password=YOUR_PASSWORD
```

### Hot Reload

Add Spring DevTools dependency for automatic restart on code changes:
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-devtools</artifactId>
    <scope>runtime</scope>
    <optional>true</optional>
</dependency>
```

## 📖 Technology Stack

- **Spring Boot 3.2.0** - Application framework
- **Spring Cloud 2023.0.0** - Microservices infrastructure
- **Spring Cloud Gateway** - API Gateway with reactive support
- **Netflix Eureka** - Service discovery and registry
- **Spring Security** - Authentication and authorization
- **JWT (jjwt 0.12.3)** - Token-based authentication
- **MySQL 8.0** - Relational database
- **Redis 7** - Caching and session management
- **WebSocket (STOMP)** - Real-time communication
- **Docker & Docker Compose** - Containerization
- **Nginx** - Reverse proxy and load balancer

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit changes (`git commit -m 'Add AmazingFeature'`)
4. Push to branch (`git push origin feature/AmazingFeature`)
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License.

## 👨‍💻 Support

For issues and questions:
- Create an issue on GitHub
- Email: support@example.com

## 🎯 Roadmap

- [ ] Add notification service
- [ ] Implement media upload service (S3/MinIO)
- [ ] Add search functionality (Elasticsearch)
- [ ] Implement story feature
- [ ] Add video streaming support
- [ ] OAuth2 social login (Google, Facebook)
- [ ] Admin dashboard
- [ ] Analytics service
- [ ] Email verification
- [ ] Two-factor authentication

---

**Built with ❤️ using Spring Boot Microservices**
