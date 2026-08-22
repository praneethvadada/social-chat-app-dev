# Security Implementation Guide

## Overview

This document describes all security measures implemented in the Social Media Backend.

## 1. Authentication & Authorization

### JWT Token Security

**Implementation:**
- Access tokens: 24-hour expiration
- Refresh tokens: 7-day expiration
- 256-bit HMAC-SHA secret key
- Token validation at API Gateway

**Security Features:**
- Tokens stored in Redis with TTL
- Secure token generation using `io.jsonwebtoken`
- Subject claim contains user ID
- Email included in claims for additional verification

**Code Location:**
- `auth-service/src/main/java/com/socialmedia/auth/security/JwtTokenProvider.java`
- `api-gateway/src/main/java/com/socialmedia/gateway/filter/JwtAuthenticationFilter.java`

### Password Security

**Implementation:**
- BCrypt hashing with strength 12
- Minimum 6 characters required
- Passwords never logged or transmitted unencrypted

**Code Location:**
- `auth-service/src/main/java/com/socialmedia/auth/config/SecurityConfig.java`

### Account Protection

**Brute Force Prevention:**
- Maximum 5 failed login attempts
- Account locked for 15 minutes
- Failed attempts counter per user
- Automatic unlock after timeout

**Code Location:**
- `auth-service/src/main/java/com/socialmedia/auth/service/AuthService.java`

## 2. Network Security

### Nginx Reverse Proxy

**Features:**
- First line of defense
- Hides internal service architecture
- SSL/TLS termination
- Request filtering

**Configuration:**
```nginx
# Rate limiting
limit_req_zone $binary_remote_addr zone=general:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=auth:10m rate=5r/s;

# Connection limits
limit_conn_zone $binary_remote_addr zone=addr:10m;
limit_conn addr 10;
```

**Code Location:**
- `nginx/nginx.conf`

### Rate Limiting

**Multiple Layers:**

1. **Nginx Layer:**
   - General: 10 requests/second
   - Auth: 5 requests/second
   - Burst capacity: 10-20 requests

2. **API Gateway Layer:**
   - Redis-backed rate limiting
   - User-based rate limiting
   - IP-based fallback

**Code Location:**
- `nginx/nginx.conf`
- `api-gateway/src/main/java/com/socialmedia/gateway/config/RateLimitConfig.java`
- `api-gateway/src/main/java/com/socialmedia/gateway/config/GatewayConfig.java`

## 3. Application Security

### Input Validation

**Bean Validation:**
```java
@NotBlank(message = "Email is required")
@Email(message = "Email should be valid")
private String email;

@Size(min = 6, message = "Password must be at least 6 characters")
private String password;
```

**Implementation:**
- All DTOs validated
- Custom validation messages
- Size, format, and constraint checks

**Code Locations:**
- `auth-service/src/main/java/com/socialmedia/auth/dto/*.java`
- `social-service/src/main/java/com/socialmedia/social/dto/*.java`

### SQL Injection Prevention

**Measures:**
- JPA/Hibernate for all database access
- Parameterized queries only
- No raw SQL concatenation
- `@Query` with parameters

**Example:**
```java
@Query("SELECT p FROM Post p WHERE p.userId IN :userIds AND p.isPublic = true")
Page<Post> findFeedPosts(@Param("userIds") List<Long> userIds, Pageable pageable);
```

### XSS Protection

**Headers:**
```nginx
X-XSS-Protection: 1; mode=block
Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline';
X-Content-Type-Options: nosniff
```

**Code Location:**
- `api-gateway/src/main/java/com/socialmedia/gateway/filter/SecurityHeadersFilter.java`
- `nginx/nginx.conf`

### CORS Configuration

**Settings:**
```properties
allowed-origins=http://localhost:3000,http://localhost:4200
allowed-methods=GET,POST,PUT,DELETE,OPTIONS
allowed-headers=*
allow-credentials=true
max-age=3600
```

**Code Location:**
- `api-gateway/src/main/resources/application.properties`

### CSRF Protection

**Status:** Disabled for stateless REST API
- JWT tokens provide CSRF protection
- All requests must include JWT in Authorization header
- STOMP WebSocket endpoints use token authentication

## 4. Communication Security

### TLS/SSL

**Configuration:**
```nginx
listen 443 ssl http2;
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers HIGH:!aNULL:!MD5;
ssl_prefer_server_ciphers on;
```

**Setup Instructions:**
```bash
# Generate self-signed certificate (development)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout nginx/ssl/key.pem -out nginx/ssl/cert.pem

# Production: Use Let's Encrypt
certbot certonly --standalone -d your-domain.com
```

### Secure Headers

**Headers Applied:**
- `Strict-Transport-Security`: Force HTTPS
- `X-Frame-Options: DENY`: Prevent clickjacking
- `X-Content-Type-Options: nosniff`: Prevent MIME sniffing
- `Content-Security-Policy`: Restrict resource loading
- `Referrer-Policy`: Control referrer information
- `Permissions-Policy`: Restrict browser features

**Code Location:**
- `api-gateway/src/main/java/com/socialmedia/gateway/filter/SecurityHeadersFilter.java`
- `nginx/nginx.conf`

## 5. Infrastructure Security

### Docker Network Isolation

**Implementation:**
```yaml
networks:
  social-network:
    driver: bridge
```

- All services in isolated network
- External access only through Nginx
- Inter-service communication secured
- No direct database access from outside

### Database Security

**Measures:**
- Separate databases per service
- Strong root passwords
- No default credentials
- Port mapping limited to host
- Regular backups

**Configuration:**
```yaml
mysql-auth:
  environment:
    MYSQL_ROOT_PASSWORD: root123  # Change in production!
  ports:
    - "3307:3306"  # Not exposed to internet
```

### Redis Security

**Measures:**
- Password protection (add in production)
- Isolated network
- Session TTL enforced
- Automatic cleanup

### Health Checks

**Purpose:**
- Verify service availability
- Automatic restart on failure
- Dependency management

**Example:**
```yaml
healthcheck:
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
  interval: 10s
  timeout: 5s
  retries: 5
```

## 6. Monitoring & Logging

### Security Logging

**What's Logged:**
- Failed login attempts
- Account lockouts
- Token generation/validation
- Rate limit violations
- Unauthorized access attempts

**Code Location:**
- All services log security events
- Nginx access logs
- Application logs in Docker

### Access Logs

**Nginx Format:**
```nginx
log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for"';
```

## 7. Best Practices Implemented

### ✅ OWASP Top 10 Coverage

1. **Broken Access Control**
   - JWT validation on all protected endpoints
   - User ownership verification before updates/deletes

2. **Cryptographic Failures**
   - BCrypt for passwords
   - TLS/SSL for transport
   - Secure JWT signing

3. **Injection**
   - Parameterized queries (JPA)
   - Input validation

4. **Insecure Design**
   - Microservices architecture
   - Service isolation
   - Defense in depth

5. **Security Misconfiguration**
   - Secure defaults
   - Error handling
   - Security headers

6. **Vulnerable Components**
   - Updated dependencies
   - Spring Boot 3.2.0
   - Latest security patches

7. **Authentication Failures**
   - Strong password policy
   - Account lockout
   - Secure session management

8. **Software Integrity Failures**
   - Docker image verification
   - Maven dependency verification

9. **Logging Failures**
   - Comprehensive logging
   - Security event tracking

10. **SSRF**
    - Input validation
    - URL whitelist for external calls

## 8. Production Hardening Checklist

### Before Production Deployment:

- [ ] Change all default passwords
- [ ] Generate strong JWT secret (256-bit)
- [ ] Set up real SSL certificates
- [ ] Configure firewall rules
- [ ] Enable Redis password
- [ ] Set up database backups
- [ ] Configure log rotation
- [ ] Set up monitoring/alerting
- [ ] Review and restrict CORS origins
- [ ] Set environment variables securely
- [ ] Enable database SSL connections
- [ ] Configure fail2ban or similar
- [ ] Set up intrusion detection
- [ ] Enable audit logging
- [ ] Test disaster recovery
- [ ] Perform security audit/penetration test

## 9. Security Maintenance

### Regular Tasks:

**Weekly:**
- Review security logs
- Check for failed login patterns
- Monitor rate limit violations

**Monthly:**
- Update dependencies
- Review access logs
- Check for vulnerabilities (OWASP Dependency-Check)

**Quarterly:**
- Rotate JWT secrets
- Security audit
- Update SSL certificates
- Review and update security policies

## 10. Incident Response

### Security Breach Protocol:

1. **Detect**: Monitor logs for suspicious activity
2. **Contain**: Revoke affected tokens, lock accounts
3. **Investigate**: Analyze logs, identify attack vector
4. **Remediate**: Patch vulnerability, update credentials
5. **Document**: Record incident, lessons learned
6. **Notify**: Inform affected users if required

### Quick Response Commands:

```bash
# Revoke all sessions (flush Redis)
docker exec -it redis redis-cli FLUSHALL

# Lock specific user account
# Update database: SET account_non_locked = false WHERE user_id = X

# Check recent failed logins
docker-compose logs auth-service | grep "failed"

# Block IP at nginx level
# Add to nginx.conf: deny <IP_ADDRESS>;
# Reload: docker exec nginx-proxy nginx -s reload
```

## 11. Security Testing

### Automated Testing:

```bash
# OWASP Dependency Check
mvn org.owasp:dependency-check-maven:check

# Security headers test
curl -I https://your-domain.com | grep -E "X-|Content-Security|Strict-Transport"

# Rate limiting test
for i in {1..20}; do curl http://localhost/api/auth/login; done
```

### Manual Testing:

1. **SQL Injection**: Try malicious input in all fields
2. **XSS**: Test script injection in user content
3. **Authentication Bypass**: Test endpoints without tokens
4. **Authorization**: Try accessing other users' data
5. **Rate Limiting**: Rapid-fire requests
6. **Session Management**: Test token expiration

## Contact

For security issues, please email: security@example.com

**Do not** create public issues for security vulnerabilities.
