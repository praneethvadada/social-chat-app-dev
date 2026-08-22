# Social Media Backend Architecture Summary

## Overview
This document provides a comprehensive analysis of the social media backend architecture, covering both the complete backend system and the database schema design.

## 1. Complete Backend Architecture

### Microservices Architecture
The backend is built using a **microservices architecture** with three main services:

#### API Gateway Service (Port 8080)
- **Technology:** Spring Cloud Gateway, Redis Reactive, JWT
- **Responsibilities:**
  - Request routing and load balancing
  - JWT token validation and authentication
  - Rate limiting (user-based and IP-based)
  - CORS configuration for frontend integration
  - WebSocket routing for real-time features
- **Routes:**
  - `/api/auth/**` → auth-service:8081
  - `/api/social/**` → social-service:8082
  - `/ws/**` → social-service:8082 (WebSocket)
  - `/api/calls/**` → social-service:8082

#### Authentication Service (Port 8081)
- **Technology:** Spring Boot, Spring Security, JPA, MySQL, Redis, JWT, Email
- **Core Features:**
  - User registration with email OTP verification
  - JWT-based authentication with refresh tokens
  - Password reset functionality
  - Account management (deletion, availability checks)
  - User profile management
  - Role-based access control (USER, ADMIN, MODERATOR)
- **Security Features:**
  - BCrypt password hashing
  - Account lockout after failed attempts
  - Email verification for signup
  - Secure password reset tokens

#### Social Service (Port 8082)
- **Technology:** Spring Boot, JPA, MySQL, Redis, WebSocket, AWS S3, Agora RTC
- **Core Features:**
  - **Content Management:** Posts, comments, likes, shares, saves
  - **Social Graph:** Followers, follow requests, blocking, close friends
  - **Real-time Messaging:** WebSocket-based chat with media support
  - **File Management:** AWS S3 integration for media uploads
  - **Video Calling:** Agora RTC integration for WebRTC calls
  - **Notifications:** Activity notifications system
  - **Privacy Controls:** Account visibility, post visibility (Public/Close Friends)

### Technology Stack
- **Framework:** Spring Boot 3.2.0, Java 17
- **Microservices:** Spring Cloud 2023.0.0
- **Security:** Spring Security, JWT (JJWT 0.12.3)
- **Database:** MySQL 8.0 with JPA/Hibernate
- **Caching:** Redis for sessions and real-time data
- **Communication:** REST APIs, WebSocket (STOMP), OpenFeign
- **File Storage:** AWS S3
- **Video Calling:** Agora RTC
- **Email:** SMTP (Gmail)
- **Documentation:** OpenAPI/Swagger
- **Build:** Maven with multi-module structure

### Communication Patterns
- **Synchronous:** REST APIs with OpenFeign for service-to-service calls
- **Asynchronous:** WebSocket for real-time messaging, Redis pub/sub for events
- **Shared Database:** Both services access the same MySQL database with clear separation

### Deployment Architecture
- **Development:** Local services with shared database
- **Production (AWS):**
  - API Gateway on EC2
  - Auth Service on EC2
  - Social Service on EC2
  - MySQL on RDS
  - Redis on ElastiCache
  - Files on S3
  - Load balancer for high availability

## 2. Database Schema Architecture

### Database Design
- **Database:** `auth_db` (MySQL 8.0, InnoDB, UTF8MB4)
- **Tables:** 21 total
- **Timezone:** UTC (enforced application-wide)
- **Pattern:** Shared database with service-specific table ownership

### Core Tables by Category

#### Authentication Tables (5 tables)
- `users` - Main user entity with auth and profile data
- `user_roles` - Role assignments (USER, ADMIN, MODERATOR)
- `otp_verifications` - Email verification for signup
- `password_reset_token` - Password reset functionality
- `user_profile_extensions` - Extended profile information

#### Content & Social Tables (8 tables)
- `posts` - User posts with visibility controls
- `post_images` - Media attachments for posts
- `comments` - Post comments with threading
- `likes` - Post/comment likes
- `shares` - Content sharing
- `saves` - Content bookmarking
- `followers` - Follow relationships
- `follow_requests` - Follow request system

#### Advanced Social Features (4 tables)
- `blocked_users` - User blocking functionality
- `close_friends` - Close friends relationships
- `messages` - Direct messaging with media
- `chat_deletions` - WhatsApp-like conversation deletion

#### System Tables (4 tables)
- `notifications` - Activity notifications
- `call_logs` - Video call history
- `schema_version` - Database versioning
- Various junction and system tables

### Key Design Patterns

#### Denormalized Counters
- `likes_count`, `comments_count`, `shares_count`, `saves_count` on posts
- Updated via database triggers for performance
- Prevents expensive COUNT(*) queries

#### Soft Deletes
- `chat_deletions` table for independent message deletion
- `deleted_for_initiator/receiver` flags in call logs
- Maintains data integrity while respecting privacy

#### Composite Keys & Unique Constraints
- Prevents duplicate relationships (follows, blocks, friendships)
- Ensures data integrity at database level

#### Audit Fields
- `created_at`, `updated_at` on all entities
- Automatic timestamps with UTC timezone

### Performance Optimizations

#### Strategic Indexing
- **User lookups:** username, email, online status, verification status
- **Social graph:** follower/following relationships with timestamps
- **Content queries:** user posts, visibility filters, creation time
- **Messaging:** conversation queries, unread message tracking
- **Composite indexes** for complex multi-column queries

#### Query Optimization
- **Pagination support** with LIMIT/OFFSET
- **Selective field fetching** to reduce data transfer
- **Proper foreign key indexing** for join performance
- **Redis caching** for frequently accessed data

### Data Integrity & Security

#### Foreign Key Constraints
- **CASCADE DELETE** for dependent relationships
- **SET NULL** for optional references
- **RESTRICT** for critical data protection

#### Validation Constraints
- **ENUM values** for controlled vocabularies
- **Unique constraints** on critical fields
- **Check constraints** for logical validations

#### Privacy & Security
- **Independent conversation deletion** (WhatsApp-like)
- **Account privacy settings** (private/public accounts)
- **Post visibility controls** (Public/Close Friends)
- **Read receipt preferences**

## Architecture Benefits

### Scalability
- **Horizontal scaling** of individual services
- **Shared database** with read replicas
- **Redis clustering** for caching
- **Load balancer** distribution

### Maintainability
- **Service separation** by business domain
- **Clear API contracts** with OpenAPI documentation
- **Database versioning** and migration tracking
- **Modular architecture** for independent deployment

### Reliability
- **Circuit breakers** and retry logic
- **Health checks** and monitoring
- **Graceful degradation** capabilities
- **Automated backups** and recovery

### Security
- **JWT-based authentication** with refresh tokens
- **Rate limiting** and DDoS protection
- **Input validation** and SQL injection prevention
- **CORS configuration** and secure headers

## Development & Deployment

### Local Development
- Docker Compose for service orchestration
- Hot reload for rapid development
- Shared database for integration testing
- Local Redis and S3 simulation

### Production Deployment
- AWS infrastructure with Terraform/CloudFormation
- CI/CD pipelines with automated testing
- Blue-green deployments for zero downtime
- Monitoring with CloudWatch and application metrics

This architecture provides a solid foundation for a modern, scalable social media platform with comprehensive features, strong security, and excellent performance characteristics.