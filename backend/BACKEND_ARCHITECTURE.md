# Social Media Backend Architecture

## Overview
The social media backend is a microservices-based architecture built with Spring Boot 3.2.0, implementing a comprehensive social media platform with real-time messaging, video calls, and content sharing features.

## Architecture Components

### 1. API Gateway Service
**Technology Stack:** Spring Cloud Gateway, Redis (Reactive), JWT
**Port:** 8080
**Responsibilities:**
- Request routing to auth-service and social-service
- JWT token validation and user authentication
- Rate limiting based on user ID or IP
- CORS configuration for frontend integration
- WebSocket routing for real-time features

**Key Features:**
- Routes `/api/auth/**` to auth-service (port 8081)
- Routes `/api/social/**` to social-service (port 8082)
- Routes `/ws/**` to social-service for WebSocket connections
- Routes `/api/calls/**` to social-service for video calls
- Implements retry logic (3 attempts) for failed requests

### 2. Authentication Service (auth-service)
**Technology Stack:** Spring Boot, Spring Security, JPA, MySQL, Redis, JWT, Email
**Port:** 8081
**Responsibilities:**
- User registration and login
- JWT token generation and refresh
- Password reset functionality
- Email OTP verification for signup
- Account management (deletion, availability checks)
- User profile management

**Key Features:**
- BCrypt password hashing
- Refresh token mechanism
- Account lockout after failed attempts
- Email verification with 4-digit OTP (10-minute expiry)
- Integration with social-service via OpenFeign

### 3. Social Service (social-service)
**Technology Stack:** Spring Boot, JPA, MySQL, Redis, WebSocket, AWS S3, Agora RTC
**Port:** 8082
**Responsibilities:**
- Social media features (posts, comments, likes, follows)
- Real-time messaging with WebSocket
- File upload and storage (AWS S3)
- Video calling with Agora integration
- Notification system
- User presence tracking
- Content moderation (blocking, reporting)

**Key Features:**
- Real-time chat with message status tracking
- Post visibility controls (Public, Close Friends)
- Follow request system for private accounts
- Media upload with S3 integration
- WebRTC video calling
- Push notifications
- Scheduled tasks for cleanup operations

## Data Flow Architecture

### Authentication Flow
```
Frontend → API Gateway → Auth Service
    ↓
JWT Token Generation
    ↓
Token Validation on Subsequent Requests
```

### Social Features Flow
```
Frontend → API Gateway → Social Service → Database
    ↓
Real-time Updates via WebSocket
    ↓
Push Notifications
```

### File Upload Flow
```
Frontend → API Gateway → Social Service → AWS S3
    ↓
URL Generation → Database Storage
```

## Technology Stack Details

### Core Framework
- **Spring Boot 3.2.0** - Main application framework
- **Java 17** - Programming language
- **Spring Cloud 2023.0.0** - Microservices support

### Security & Authentication
- **Spring Security** - Authentication and authorization
- **JWT (JJWT 0.12.3)** - Token-based authentication
- **BCrypt** - Password hashing

### Data Layer
- **Spring Data JPA** - ORM framework
- **MySQL 8.0** - Primary database
- **Redis** - Caching and session storage
- **AWS S3** - File storage

### Communication
- **Spring Cloud OpenFeign** - Service-to-service communication
- **Spring WebSocket** - Real-time messaging
- **STOMP** - WebSocket protocol
- **SockJS** - WebSocket fallback

### External Integrations
- **AWS S3** - File storage and CDN
- **Agora RTC** - Video calling infrastructure
- **SMTP (Gmail)** - Email notifications

### Development Tools
- **Lombok** - Code generation
- **SpringDoc OpenAPI** - API documentation
- **Maven** - Build tool
- **Spring Boot Actuator** - Monitoring

## Service Communication Patterns

### Synchronous Communication
- REST APIs between services (via OpenFeign)
- Database shared between auth-service and social-service

### Asynchronous Communication
- WebSocket for real-time messaging
- Redis pub/sub for cross-service events
- Email notifications (asynchronous)

## Deployment Architecture

### Development Environment
- All services run locally
- Shared MySQL database
- Local Redis instance
- Local file storage

### Production Environment (AWS)
- API Gateway on EC2
- Auth Service on EC2
- Social Service on EC2
- MySQL on RDS
- Redis on ElastiCache
- Files on S3
- Load balancer for high availability

## Security Architecture

### Authentication
- JWT tokens with expiration
- Refresh token rotation
- Password complexity requirements
- Account lockout protection

### Authorization
- Role-based access control (USER, ADMIN, MODERATOR)
- API Gateway filters requests
- WebSocket security interceptors

### Data Protection
- HTTPS/TLS encryption
- SQL injection prevention (JPA)
- XSS protection (input validation)
- CORS configuration

## Scalability Considerations

### Horizontal Scaling
- Stateless services (auth-service, social-service)
- Shared database with read replicas
- Redis clustering for caching
- Load balancer for API Gateway

### Performance Optimization
- Database indexing on frequently queried fields
- Redis caching for user sessions and frequently accessed data
- Pagination for large datasets
- Asynchronous processing for heavy operations

### Monitoring & Observability
- Spring Boot Actuator endpoints
- Application logging with different levels
- Health checks for all services
- Metrics collection for performance monitoring

## Database Architecture

### Shared Database Design
Both auth-service and social-service share the same MySQL database (`auth_db`) with clearly separated concerns:

- **Auth Service Tables:** users, user_roles, password_reset_token, otp_verifications, user_profile_extensions
- **Social Service Tables:** posts, post_images, likes, comments, shares, saves, followers, follow_requests, blocked_users, close_friends, messages, chat_deletions, notifications, call_logs

### Key Design Patterns
- **Soft Deletes:** For messages and call logs (per-user deletion tracking)
- **Denormalized Counters:** likes_count, comments_count, shares_count, saves_count on posts
- **Composite Keys:** For relationships (followers, blocked_users, close_friends)
- **Audit Fields:** created_at, updated_at on all entities
- **Optimistic Locking:** For concurrent operations

This architecture provides a robust, scalable foundation for a modern social media platform with real-time features and comprehensive user management.