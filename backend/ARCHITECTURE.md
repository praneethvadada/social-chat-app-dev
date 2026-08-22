# Backend Architecture & Service Communication

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT (Browser/App)                     │
│                                                                   │
│  Request: http://localhost:8080/api/auth/login                  │
│           http://localhost:8080/api/social/posts                │
└───────────────────────────┬───────────────────────────────────┘
                            │ HTTP Request
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                     API GATEWAY (Port 8080)                      │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │ Spring Cloud Gateway                                        │ │
│  │  - Route Management                                         │ │
│  │  - Request Forwarding                                       │ │
│  │  - CORS Handling                                            │ │
│  │  - Retry Logic (3 attempts)                                 │ │
│  └────────────────────────────────────────────────────────────┘ │
└──────────────┬─────────────────────────────┬──────────────────┘
               │                              │
     /api/auth/**                    /api/social/**
     (StripPrefix=2)                 (StripPrefix=2)
               │                              │
               ▼                              ▼
┌──────────────────────────┐    ┌──────────────────────────────┐
│  AUTH SERVICE (8081)     │    │  SOCIAL SERVICE (8082)       │
│  ┌────────────────────┐  │    │  ┌────────────────────────┐  │
│  │ Controllers        │  │    │  │ JWT Filter             │  │
│  │  - /register       │  │    │  │ (validates token)      │  │
│  │  - /login          │  │    │  └────────────────────────┘  │
│  │  - /logout         │  │    │  ┌────────────────────────┐  │
│  │  - /refresh        │  │    │  │ Controllers            │  │
│  └────────────────────┘  │    │  │  - /posts              │  │
│  ┌────────────────────┐  │    │  │  - /comments           │  │
│  │ JWT Generation     │  │    │  │  - /likes              │  │
│  │ (creates tokens)   │  │    │  │  - /saves              │  │
│  └────────────────────┘  │    │  │  - /shares             │  │
└──────────┬───────────────┘    │  │  - /messages           │  │
           │                    │  │  - /files              │  │
           ▼                    │  └────────────────────────┘  │
┌──────────────────────────┐    └──────────┬───────────────────┘
│  MySQL: auth_db          │               │
│   - users table          │               ▼
└──────────────────────────┘    ┌──────────────────────────────┐
                                │  MySQL: social_db            │
┌──────────────────────────┐    │   - posts                    │
│  Redis (Port 6379)       │◄───┤   - comments                 │
│   - Sessions             │    │   - likes                    │
│   - Rate Limiting        │    │   - saves                    │
│   - Caching              │    │   - shares                   │
└──────────────────────────┘    │   - messages                 │
                                └──────────────────────────────┘
```

## 🔄 Request Flow Explanation

### Scenario 1: User Registration/Login (Auth Service)

```
1. Client → Gateway
   POST http://localhost:8080/api/auth/register
   Body: { username, email, password, fullName }

2. Gateway → Auth Service
   - Strips "/api/auth" prefix
   - Forwards to: http://localhost:8081/register
   - Adds header: X-Gateway-Source: api-gateway

3. Auth Service Processing
   - Validates input data
   - Hashes password with BCrypt
   - Saves user to auth_db
   - Generates JWT token with user ID
   - Returns: { accessToken, refreshToken, user details }

4. Auth Service → Gateway → Client
   Response: { accessToken: "eyJhbGc...", ... }
```

### Scenario 2: Creating a Post (Social Service with Auth)

```
1. Client → Gateway
   POST http://localhost:8080/api/social/posts
   Headers: Authorization: Bearer eyJhbGc...
   Body: { content, imageUrls, isPublic }

2. Gateway → Social Service
   - Strips "/api/social" prefix
   - Forwards to: http://localhost:8082/posts
   - Preserves Authorization header
   - Adds header: X-Gateway-Source: api-gateway

3. Social Service Processing
   a) JWT Authentication Filter (JwtAuthenticationFilter)
      - Extracts token from Authorization header
      - Validates token using JwtTokenProvider
      - Extracts userId from token
      - Sets userId in request attribute
      - Passes to Spring Security context

   b) Security Filter Chain (SecurityConfig)
      - Checks if request is authenticated
      - All /posts/** endpoints require authentication
      - /health, /swagger-ui/** are public

   c) Controller Layer (PostController)
      - @RequestAttribute("userId") gets authenticated user
      - Receives post data
      - Calls PostService

   d) Service Layer (PostService)
      - Creates Post entity with userId
      - Saves to social_db
      - Returns saved post

4. Social Service → Gateway → Client
   Response: { id, userId, content, imageUrls, ... }
```

## 🔐 Authentication & Authorization Flow

### How Services Communicate

**IMPORTANT:** Social Service does NOT directly call Auth Service!

```
┌────────────────────────────────────────────────────────────────┐
│  Authentication Flow                                            │
└────────────────────────────────────────────────────────────────┘

1. USER LOGS IN (Auth Service)
   ┌─────────────┐
   │ Auth Service│ ← Generates JWT token
   │   (8081)    │ ← Token contains: userId, expiration
   └─────────────┘ ← Signed with shared secret key

2. USER MAKES REQUEST (Social Service)
   ┌──────────────────────────────────────────────────┐
   │ Social Service receives JWT token                 │
   │                                                   │
   │ ✓ Validates token LOCALLY (no Auth Service call) │
   │ ✓ Uses SAME secret key (jwt.secret)              │
   │ ✓ Extracts userId from token                     │
   │ ✓ No database lookup needed                      │
   └──────────────────────────────────────────────────┘
```

### Key Points:

1. **Shared Secret Key**
   - Both services use: `jwt.secret=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437`
   - Auth Service: Signs tokens with this key
   - Social Service: Verifies tokens with this key

2. **No Service-to-Service Communication**
   - Social Service NEVER calls Auth Service
   - Token validation is LOCAL (cryptographic verification)
   - No network latency or dependency issues

3. **Stateless Authentication**
   - JWT contains all needed information (userId)
   - No session storage needed
   - Scales horizontally easily

## 📊 Detailed Component Breakdown

### 1. API Gateway (Port 8080)

**Purpose:** Single entry point for all client requests

**Configuration:**
```properties
# application.properties
spring.cloud.gateway.routes[0].id=auth-service
spring.cloud.gateway.routes[0].uri=http://localhost:8081
spring.cloud.gateway.routes[0].predicates[0]=Path=/api/auth/**
spring.cloud.gateway.routes[0].filters[0]=StripPrefix=2

spring.cloud.gateway.routes[1].id=social-service
spring.cloud.gateway.routes[1].uri=http://localhost:8082
spring.cloud.gateway.routes[1].predicates[0]=Path=/api/social/**
spring.cloud.gateway.routes[1].filters[0]=StripPrefix=2
```

**Functions:**
- ✅ Routes requests to appropriate microservices
- ✅ Strips path prefixes (`/api/auth`, `/api/social`)
- ✅ Handles CORS globally
- ✅ Implements retry logic (3 attempts)
- ✅ Adds custom headers (`X-Gateway-Source`)

**Example Routing:**
```
Client Request:  http://localhost:8080/api/auth/login
Gateway Routes:  → http://localhost:8081/login

Client Request:  http://localhost:8080/api/social/posts
Gateway Routes:  → http://localhost:8082/posts
```

### 2. Auth Service (Port 8081)

**Purpose:** User authentication and JWT token management

**Components:**
```
AuthController
  ├── /register → AuthService.register()
  ├── /login    → AuthService.login()
  ├── /logout   → AuthService.logout()
  └── /refresh  → AuthService.refresh()

AuthService
  ├── Hash passwords (BCrypt)
  ├── Validate credentials
  ├── Generate JWT tokens (JwtTokenProvider)
  └── Store users in auth_db

JwtTokenProvider
  ├── createAccessToken(userId) → 24 hours
  ├── createRefreshToken(userId) → 7 days
  └── Signs with jwt.secret
```

**Database:** `auth_db`
```sql
users
  ├── id (Primary Key)
  ├── username (Unique)
  ├── email (Unique)
  ├── password (BCrypt hashed)
  ├── full_name
  ├── created_at
  └── updated_at
```

**No Authentication Required:**
- All endpoints are PUBLIC (registration/login)

### 3. Social Service (Port 8082)

**Purpose:** Social media features (posts, comments, likes, messages)

**Security Flow:**
```
Request → JwtAuthenticationFilter → SecurityFilterChain → Controller
          (validates token)         (checks permissions)   (processes)
```

**Components:**

#### A. JwtAuthenticationFilter
```java
// For EVERY request:
1. Extract JWT from Authorization header
2. Validate token signature using jwt.secret
3. Extract userId from token payload
4. Set userId in request attribute
5. Create Spring Security authentication
6. Continue to controller
```

#### B. JwtTokenProvider
```java
// Token validation (NO external service calls):
1. Parse token with secret key
2. Check signature validity
3. Check expiration date
4. Extract userId from "subject" claim
5. Return userId to filter
```

#### C. SecurityConfig
```java
// Define security rules:
✅ Public:  /health, /swagger-ui/**, /ws/**
🔒 Protected: ALL other endpoints require authentication
```

#### D. Controllers
```java
// Example: PostController
@PostMapping("/posts")
public Post createPost(
    @RequestAttribute("userId") Long userId,  // Set by JWT filter
    @RequestBody PostRequest request
) {
    return postService.createPost(userId, request);
}
```

**Database:** `social_db`
```sql
posts     → id, user_id, content, image_urls, is_public, created_at
comments  → id, post_id, user_id, content, parent_comment_id
likes     → id, user_id, target_id, target_type (POST/COMMENT)
saves     → id, user_id, post_id
shares    → id, user_id, post_id, shared_note
messages  → id, sender_id, receiver_id, content, is_read
```

## 🔍 Common Questions Answered

### Q1: Does Social Service call Auth Service to validate tokens?
**Answer:** NO! 

- Token validation is LOCAL (cryptographic)
- Uses shared `jwt.secret` key
- No network calls between services
- Fast and scalable

### Q2: How does Social Service know the user ID?
**Answer:** From JWT token payload!

```
JWT Token Structure:
{
  "header": {
    "alg": "HS256",
    "typ": "JWT"
  },
  "payload": {
    "sub": "123",        ← User ID here
    "exp": 1733024400,   ← Expiration timestamp
    "iat": 1732938000    ← Issued at timestamp
  },
  "signature": "..."     ← Verified with jwt.secret
}
```

### Q3: What if I change my password in Auth Service?
**Answer:** Old tokens remain valid until expiration!

- JWT is stateless (no revocation by default)
- Options to handle this:
  1. Wait for token expiration (24 hours)
  2. Implement token blacklist in Redis
  3. Add "password version" in token claims

### Q4: Can Social Service work if Auth Service is down?
**Answer:** YES! (for existing users with valid tokens)

- Social Service validates tokens independently
- New logins/registrations won't work
- Existing authenticated users continue normally

### Q5: How does API Gateway know which service to route to?
**Answer:** By URL path matching!

```
/api/auth/**   → Auth Service (8081)
/api/social/** → Social Service (8082)
```

## 🔒 Security Implementation

### 1. Token Generation (Auth Service)
```java
// JwtTokenProvider.java
public String createAccessToken(Long userId) {
    Date now = new Date();
    Date expiryDate = new Date(now.getTime() + 86400000); // 24 hours
    
    return Jwts.builder()
        .subject(String.valueOf(userId))
        .issuedAt(now)
        .expiration(expiryDate)
        .signWith(getSigningKey())  // Uses jwt.secret
        .compact();
}
```

### 2. Token Validation (Social Service)
```java
// JwtTokenProvider.java
public boolean validateToken(String token) {
    try {
        Jwts.parser()
            .verifyWith(getSigningKey())  // Same jwt.secret
            .build()
            .parseSignedClaims(token);
        return true;
    } catch (ExpiredJwtException ex) {
        return false;  // Token expired
    }
}
```

### 3. User Extraction (Social Service)
```java
// JwtTokenProvider.java
public Long getUserIdFromToken(String token) {
    Claims claims = Jwts.parser()
        .verifyWith(getSigningKey())
        .build()
        .parseSignedClaims(token)
        .getPayload();
    
    return Long.parseLong(claims.getSubject());  // Extract userId
}
```

## 📝 Complete Request Example

### Step-by-Step: Creating a Post

**Step 1: User Registration**
```bash
curl -X POST http://localhost:8080/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "john_doe",
    "email": "john@example.com",
    "password": "password123",
    "fullName": "John Doe"
  }'

# Response:
{
  "accessToken": "eyJhbGciOiJIUzI1NiJ9...",
  "refreshToken": "eyJhbGciOiJIUzI1NiJ9...",
  "tokenType": "Bearer",
  "user": {
    "id": 1,
    "username": "john_doe",
    "email": "john@example.com"
  }
}
```

**Step 2: Create Post (with token)**
```bash
curl -X POST http://localhost:8080/api/social/posts \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9..." \
  -H "Content-Type: application/json" \
  -d '{
    "content": "Hello World!",
    "imageUrls": [],
    "isPublic": true
  }'

# Internal Flow:
# 1. Gateway receives request
# 2. Gateway forwards to http://localhost:8082/posts (strips /api/social)
# 3. Social Service JwtAuthenticationFilter intercepts
# 4. Filter validates token, extracts userId=1
# 5. Filter sets request.setAttribute("userId", 1)
# 6. PostController receives userId=1 from @RequestAttribute
# 7. PostService creates post with userId=1
# 8. Post saved to social_db
# 9. Response returned through Gateway to client

# Response:
{
  "id": 1,
  "userId": 1,
  "content": "Hello World!",
  "imageUrls": [],
  "isPublic": true,
  "createdAt": "2025-11-29T10:00:00",
  "updatedAt": "2025-11-29T10:00:00",
  "likesCount": 0,
  "commentsCount": 0
}
```

## 🎯 Key Takeaways

1. **Gateway = Traffic Router**
   - Single entry point for clients
   - Routes based on URL paths
   - No authentication logic

2. **Auth Service = Token Creator**
   - Generates JWT tokens
   - Stores user credentials
   - No communication with Social Service

3. **Social Service = Token Validator**
   - Validates tokens LOCALLY
   - Extracts userId from token
   - No communication with Auth Service

4. **Shared Secret = Trust Mechanism**
   - Both services know jwt.secret
   - Token signed by Auth, verified by Social
   - Cryptographic trust, no network calls

5. **Stateless = Scalable**
   - No session state between services
   - Each service is independent
   - Can scale horizontally easily

## 🚀 Benefits of This Architecture

✅ **Loose Coupling:** Services don't depend on each other at runtime
✅ **High Performance:** No inter-service calls for authentication
✅ **Scalability:** Each service scales independently
✅ **Fault Tolerance:** Social Service works even if Auth is down
✅ **Security:** JWT cryptographic signatures ensure trust
✅ **Simplicity:** Clear separation of concerns

