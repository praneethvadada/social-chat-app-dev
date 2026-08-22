# AWS Deployment Guide - Complete Schema with OTP

## Overview
This guide provides step-by-step instructions for deploying the complete Social Chat application schema to AWS RDS with OTP verification support.

---

## Prerequisites

1. **AWS Account** - With EC2 and RDS access
2. **MySQL Client** - Installed locally
3. **DBeaver or MySQL Workbench** - For GUI execution
4. **AWS RDS Instance** - MySQL 8.0+ created

---

## Step 1: Create AWS RDS MySQL Instance

### Via AWS Console:

1. **Go to RDS Dashboard**
   - https://console.aws.amazon.com/rds/

2. **Click "Create Database"**
   - Engine: MySQL
   - Version: MySQL 8.0.28 or higher
   - DB Instance Class: db.t3.micro (Free tier eligible)
   - Allocated Storage: 20 GB
   - Storage Type: General Purpose (SSD)

3. **Configure Instance:**
   - DB Instance Identifier: `social-media-db`
   - Master Username: `admin`
   - Master Password: `YourSecurePassword123!`

4. **Network & Security:**
   - VPC: Default VPC
   - Public Accessibility: YES (for development only)
   - Security Group: Create new or select existing
   - Allow inbound: Port 3306 (MySQL)

5. **Additional Configuration:**
   - Initial Database Name: `auth_db`
   - Enable Automated Backups: YES
   - Backup Retention Period: 7 days
   - Enable Multi-AZ: NO (for development)

6. **Click "Create Database"** and wait 5-10 minutes

### Get RDS Endpoint:

```
RDS Dashboard → Databases → social-media-db
Copy the Endpoint (e.g., social-media-db.c9akciq32.us-east-1.rds.amazonaws.com)
```

---

## Step 2: Deploy Schema via DBeaver

### Option A: Using DBeaver GUI (Recommended)

1. **Download DBeaver** - https://dbeaver.io/download/

2. **Create New Connection:**
   - New Database Connection → MySQL
   - Server Host: `<RDS_ENDPOINT>`
   - Port: 3306
   - Username: `admin`
   - Password: `YourSecurePassword123!`
   - Test Connection → Finish

3. **Execute Schema Script:**
   - Open SQL Editor
   - File → Open File → Select `COMPLETE_SCHEMA_AWS_PRODUCTION.sql`
   - Select All (Ctrl+A)
   - Execute (Ctrl+Enter)
   - Wait for completion (should see "Migration Complete!")

4. **Verify Deployment:**
   ```sql
   USE auth_db;
   SHOW TABLES;
   SELECT * FROM schema_version;
   DESCRIBE otp_verifications;
   ```

### Option B: Using MySQL Command Line

```bash
# Connect to RDS
mysql -h social-media-db.c9akciq32.us-east-1.rds.amazonaws.com \
      -u admin -p \
      -e "CREATE DATABASE IF NOT EXISTS auth_db;"

# Execute full schema
mysql -h social-media-db.c9akciq32.us-east-1.rds.amazonaws.com \
      -u admin -p auth_db < COMPLETE_SCHEMA_AWS_PRODUCTION.sql

# Verify
mysql -h social-media-db.c9akciq32.us-east-1.rds.amazonaws.com \
      -u admin -p auth_db -e "SHOW TABLES; SELECT * FROM schema_version;"
```

### Option C: Using MySQL Workbench

1. **Create Connection:**
   - Database → New Connection
   - Connection Name: AWS Production
   - Hostname: `<RDS_ENDPOINT>`
   - Port: 3306
   - Username: `admin`
   - Password: (click "Store in Vault")
   - Test Connection → OK

2. **Execute Script:**
   - File → Open SQL Script → COMPLETE_SCHEMA_AWS_PRODUCTION.sql
   - Execute (⚡ button or Ctrl+Shift+Enter)

3. **Verify:**
   - Schemas panel → auth_db → Tables (should see 20 tables)

---

## Step 3: Configure Backend for AWS

### Update `auth-service/src/main/resources/application.properties`:

```properties
# ============================================
# AWS RDS Configuration
# ============================================

# Database Connection
spring.datasource.url=jdbc:mysql://social-media-db.c9akciq32.us-east-1.rds.amazonaws.com:3306/auth_db
spring.datasource.username=admin
spring.datasource.password=YourSecurePassword123!
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# Connection Pool Settings (Important for RDS)
spring.datasource.hikari.maximum-pool-size=10
spring.datasource.hikari.minimum-idle=5
spring.datasource.hikari.connection-timeout=20000
spring.datasource.hikari.idle-timeout=300000
spring.datasource.hikari.max-lifetime=1200000

# JPA/Hibernate Configuration
spring.jpa.database-platform=org.hibernate.dialect.MySQL8Dialect
spring.jpa.hibernate.ddl-auto=validate
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.format_sql=true

# ============================================
# Email Configuration for OTP
# ============================================

# Gmail SMTP (Recommended - Free)
spring.mail.host=smtp.gmail.com
spring.mail.port=587
spring.mail.username=your-email@gmail.com
spring.mail.password=your-app-password
spring.mail.properties.mail.smtp.auth=true
spring.mail.properties.mail.smtp.starttls.enable=true
spring.mail.properties.mail.smtp.starttls.required=true

# Enable Email Sending
app.mail.enabled=true
app.frontend.url=https://your-frontend-domain.com

# ============================================
# Server Configuration
# ============================================

server.port=8081
spring.application.name=auth-service
```

### For Social Service (`social-service/src/main/resources/application.properties`):

```properties
spring.datasource.url=jdbc:mysql://social-media-db.c9akciq32.us-east-1.rds.amazonaws.com:3306/auth_db
spring.datasource.username=admin
spring.datasource.password=YourSecurePassword123!
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

# Connection Pool
spring.datasource.hikari.maximum-pool-size=10
spring.datasource.hikari.minimum-idle=5

# JPA
spring.jpa.database-platform=org.hibernate.dialect.MySQL8Dialect
spring.jpa.hibernate.ddl-auto=validate

server.port=8082
spring.application.name=social-service
```

### For API Gateway (`api-gateway/src/main/resources/application.properties`):

```properties
server.port=8080
spring.application.name=api-gateway

# Auth Service
app.auth-service.url=http://localhost:8081
app.social-service.url=http://localhost:8082
```

---

## Step 4: Build and Deploy Backend

### Build All Services:

```bash
cd backend

# Clean and build
mvn clean install -DskipTests

# Build Docker images (Optional)
mvn clean install docker:build -DskipTests
```

### Deploy to EC2:

```bash
# SSH to EC2 instance
ssh -i your-key.pem ec2-user@your-instance-ip

# Copy built JARs
scp -i your-key.pem target/auth-service-1.0.jar ec2-user@instance:/app/
scp -i your-key.pem target/social-service-1.0.jar ec2-user@instance:/app/
scp -i your-key.pem target/api-gateway-1.0.jar ec2-user@instance:/app/

# Start services
java -jar /app/auth-service-1.0.jar &
java -jar /app/social-service-1.0.jar &
java -jar /app/api-gateway-1.0.jar &
```

### Or Deploy to Elastic Beanstalk:

```bash
# Install EB CLI
pip install awsebcli --upgrade --user

# Initialize application
eb init -p java-11 social-media-app --region us-east-1

# Create environment
eb create prod-environment

# Deploy
eb deploy

# View logs
eb logs
```

---

## Step 5: Verification

### Test Database Connection:

```bash
# From your local machine
mysql -h social-media-db.c9akciq32.us-east-1.rds.amazonaws.com \
      -u admin -p auth_db \
      -e "SELECT version, applied_at FROM schema_version;"

# Expected output:
# version | applied_at
# 2.0.2   | 2026-01-06 ...
```

### Test OTP Table:

```sql
-- Check OTP table structure
DESCRIBE otp_verifications;

-- Check stored procedures
SHOW PROCEDURE STATUS WHERE db = 'auth_db';

-- Test insert
INSERT INTO otp_verifications (email, otp, expires_at)
VALUES ('test@example.com', '1234', DATE_ADD(NOW(), INTERVAL 10 MINUTE));

-- Verify OTP
CALL sp_check_otp_status('test@example.com');
```

### Test API Endpoints:

```bash
# Send OTP
curl -X POST http://localhost:8080/auth/send-otp \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com"}'

# Verify OTP
curl -X POST http://localhost:8080/auth/verify-otp \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com","otp":"1234"}'

# Resend OTP
curl -X POST http://localhost:8080/auth/resend-otp \
     -H "Content-Type: application/json" \
     -d '{"email":"test@example.com"}'
```

---

## Step 6: Security Configuration

### AWS Security Group Settings:

**Inbound Rules:**
- MySQL (3306): Source = Your IP (for local testing)
- MySQL (3306): Source = Security Group (for EC2 access)
- SSH (22): Source = Your IP
- HTTP (80): Source = 0.0.0.0/0
- HTTPS (443): Source = 0.0.0.0/0

### Create IAM User for Application:

```bash
# Via AWS Console or CLI
aws iam create-user --user-name app-user
aws iam create-access-key --user-name app-user

# Create RDS database user
CREATE USER 'app_user'@'%.amazonaws.com' IDENTIFIED BY 'SecurePassword456!';
GRANT SELECT, INSERT, UPDATE, DELETE ON auth_db.* TO 'app_user'@'%.amazonaws.com';
FLUSH PRIVILEGES;
```

### Enable RDS Encryption:

```bash
# For new instances (automatic)
# For existing instances:
# - AWS Console → RDS → Modify Instance
# - Enable "Encrypt using AWS KMS"
# - Apply changes immediately
```

---

## Step 7: Monitoring & Maintenance

### CloudWatch Monitoring:

```bash
# Enable Enhanced Monitoring
aws rds modify-db-instance \
    --db-instance-identifier social-media-db \
    --enable-cloudwatch-logs-exports error general slowquery \
    --apply-immediately
```

### Automated Backups:

```bash
# Already configured via AWS Console
# View snapshots: RDS → Snapshots
# Restore from snapshot: Select snapshot → Restore to new instance
```

### Cleanup Expired OTPs:

```bash
# Schedule this stored procedure to run daily
CALL sp_cleanup_expired_otps();
```

### View OTP Status:

```sql
-- Check all pending OTPs
SELECT email, otp, expires_at, 
       TIMESTAMPDIFF(MINUTE, NOW(), expires_at) as minutes_remaining
FROM otp_verifications
WHERE is_used = FALSE AND expires_at > NOW();

-- Check OTP usage
SELECT email, is_used, attempts, created_at
FROM otp_verifications
ORDER BY created_at DESC
LIMIT 10;
```

---

## Cost Estimates (AWS Pricing - US East 1)

| Service | Size | Monthly Cost |
|---------|------|--------------|
| RDS MySQL | db.t3.micro (Free tier) | ~$0 (1 year) |
| RDS MySQL | db.t3.small (Production) | ~$30 |
| EC2 t3.micro | (Free tier) | ~$0 (1 year) |
| EC2 t3.small | (Production) | ~$20 |
| Data Transfer | 100 GB/month | ~$10 |
| **Total (Development)** | | **~$0-10** |
| **Total (Production)** | | **~$60** |

---

## Troubleshooting

### Connection Refused Error:

```bash
# Check security group
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Test connection
telnet social-media-db.xxx.us-east-1.rds.amazonaws.com 3306

# Solution: Add your IP to security group inbound rule
```

### OTP Table Not Created:

```sql
-- Check if table exists
SHOW TABLES LIKE 'otp_verifications';

-- If not, run migration manually
source /path/to/WORKBENCH_OTP_MIGRATION.sql;
```

### Email Not Sending:

1. Verify Gmail App Password (not regular password)
2. Check mail.enabled=true
3. Review logs: `tail -f /var/log/auth-service.log`
4. Test connection: `telnet smtp.gmail.com 587`

### Slow Queries:

```sql
-- Check query performance
SELECT * FROM mysql.slow_log ORDER BY query_time DESC LIMIT 10;

-- Enable query optimization
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;
```

---

## Summary

✅ **Complete Setup Includes:**
- AWS RDS MySQL 8.0 with automated backups
- 20 tables with OTP verification support
- 3 stored procedures for OTP management
- 8 triggers for counter updates
- Configured Spring Boot services
- Email OTP functionality
- Security groups and IAM setup
- Monitoring and logging
- Cost-optimized configuration

✅ **Ready for Production:**
- Schema validated (2.0.2)
- OTP tables and procedures created
- Backend configured for AWS
- Email service configured
- Security hardened
- Monitoring enabled
- Backups automated

---

**For Support:**
- AWS RDS Documentation: https://docs.aws.amazon.com/rds/
- MySQL 8.0 Reference: https://dev.mysql.com/doc/refman/8.0/
- Spring Boot Properties: https://docs.spring.io/spring-boot/docs/current/reference/

