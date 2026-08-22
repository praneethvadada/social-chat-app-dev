# AWS Deployment Guide (Non-Docker)

This guide covers deploying your Spring Boot microservices to AWS without using Docker.

## Architecture Overview

Your application consists of:
- **API Gateway** (Port 8080) - Routes requests to backend services
- **Auth Service** (Port 8081) - Authentication and user management
- **Social Service** (Port 8082) - Social features and chat

## Deployment Options

### Option 1: AWS Elastic Beanstalk (Recommended)

Elastic Beanstalk is the easiest way to deploy Spring Boot applications without Docker.

#### Prerequisites
1. Install AWS CLI: `https://aws.amazon.com/cli/`
2. Install EB CLI: `pip install awsebcli`
3. Configure AWS credentials: `aws configure`

#### Steps for Each Service

##### 1. Build JAR Files

```bash
cd backend
mvn clean package -DskipTests
```

This creates:
- `api-gateway/target/api-gateway-1.0.0.jar`
- `auth-service/target/auth-service-1.0.0.jar`
- `social-service/target/social-service-1.0.0.jar`

##### 2. Create Elastic Beanstalk Applications

For each service, create a separate EB application:

**Auth Service:**
```bash
cd backend/auth-service
eb init -p corretto-17 auth-service-app --region us-east-1
eb create auth-service-env
```

**Social Service:**
```bash
cd backend/social-service
eb init -p corretto-17 social-service-app --region us-east-1
eb create social-service-env
```

**API Gateway:**
```bash
cd backend/api-gateway
eb init -p corretto-17 api-gateway-app --region us-east-1
eb create api-gateway-env
```

##### 3. Configure Environment Variables

Set environment variables for each service via AWS Console or CLI:

**Auth Service Environment Variables:**
```bash
eb setenv \
  SPRING_DATASOURCE_URL=jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db \
  SPRING_DATASOURCE_USERNAME=admin \
  SPRING_DATASOURCE_PASSWORD=your-password \
  JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 \
  SPRING_DATA_REDIS_HOST=YOUR_REDIS_ENDPOINT \
  SERVER_PORT=5000
```

**Social Service Environment Variables:**
```bash
eb setenv \
  SPRING_DATASOURCE_URL=jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db \
  SPRING_DATASOURCE_USERNAME=admin \
  SPRING_DATASOURCE_PASSWORD=your-password \
  JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 \
  SPRING_DATA_REDIS_HOST=YOUR_REDIS_ENDPOINT \
  SERVER_PORT=5000
```

**API Gateway Environment Variables:**
```bash
eb setenv \
  AUTH_SERVICE_URL=http://auth-service-env.YOUR-REGION.elasticbeanstalk.com \
  SOCIAL_SERVICE_URL=http://social-service-env.YOUR-REGION.elasticbeanstalk.com \
  JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 \
  SERVER_PORT=5000
```

Note: Elastic Beanstalk expects apps to run on port 5000 by default.

##### 4. Deploy Applications

```bash
cd backend/auth-service
eb deploy

cd backend/social-service
eb deploy

cd backend/api-gateway
eb deploy
```

---

### Option 2: EC2 Instances with SystemD

Deploy each service on separate EC2 instances.

#### 1. Launch EC2 Instances

Launch 3 t2.small or t2.medium instances with Amazon Linux 2023:
- auth-service-instance
- social-service-instance
- api-gateway-instance

#### 2. Install Java on Each Instance

```bash
sudo yum update -y
sudo yum install java-17-amazon-corretto-devel -y
java -version
```

#### 3. Upload JAR Files

Use SCP or AWS Systems Manager to upload JAR files:

```bash
scp -i your-key.pem backend/auth-service/target/auth-service-1.0.0.jar ec2-user@AUTH_IP:/home/ec2-user/
scp -i your-key.pem backend/social-service/target/social-service-1.0.0.jar ec2-user@SOCIAL_IP:/home/ec2-user/
scp -i your-key.pem backend/api-gateway/target/api-gateway-1.0.0.jar ec2-user@GATEWAY_IP:/home/ec2-user/
```

#### 4. Create SystemD Service Files

**On Auth Service Instance** - Create `/etc/systemd/system/auth-service.service`:

```ini
[Unit]
Description=Auth Service
After=syslog.target network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/java -jar /home/ec2-user/auth-service-1.0.0.jar
SuccessExitStatus=143
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=10

Environment="SPRING_DATASOURCE_URL=jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db"
Environment="SPRING_DATASOURCE_USERNAME=admin"
Environment="SPRING_DATASOURCE_PASSWORD=your-password"
Environment="JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437"
Environment="SPRING_DATA_REDIS_HOST=YOUR_REDIS_ENDPOINT"
Environment="SERVER_PORT=8081"

[Install]
WantedBy=multi-user.target
```

**On Social Service Instance** - Create `/etc/systemd/system/social-service.service`:

```ini
[Unit]
Description=Social Service
After=syslog.target network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/java -jar /home/ec2-user/social-service-1.0.0.jar
SuccessExitStatus=143
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=10

Environment="SPRING_DATASOURCE_URL=jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db"
Environment="SPRING_DATASOURCE_USERNAME=admin"
Environment="SPRING_DATASOURCE_PASSWORD=your-password"
Environment="JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437"
Environment="SPRING_DATA_REDIS_HOST=YOUR_REDIS_ENDPOINT"
Environment="SERVER_PORT=8082"

[Install]
WantedBy=multi-user.target
```

**On API Gateway Instance** - Create `/etc/systemd/system/api-gateway.service`:

```ini
[Unit]
Description=API Gateway
After=syslog.target network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/usr/bin/java -jar /home/ec2-user/api-gateway-1.0.0.jar
SuccessExitStatus=143
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=10

Environment="AUTH_SERVICE_URL=http://INTERNAL_AUTH_IP:8081"
Environment="SOCIAL_SERVICE_URL=http://INTERNAL_SOCIAL_IP:8082"
Environment="JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437"
Environment="SERVER_PORT=8080"

[Install]
WantedBy=multi-user.target
```

#### 5. Start Services

On each instance:

```bash
sudo systemctl daemon-reload
sudo systemctl enable auth-service  # or social-service or api-gateway
sudo systemctl start auth-service
sudo systemctl status auth-service

# View logs
sudo journalctl -u auth-service -f
```

#### 6. Configure Security Groups

- Auth Service: Allow port 8081 from API Gateway security group
- Social Service: Allow port 8082 from API Gateway security group  
- API Gateway: Allow port 8080 from 0.0.0.0/0 (internet) or ALB

---

## AWS Infrastructure Setup

### 1. RDS MySQL Database

Create an RDS MySQL instance:

```bash
aws rds create-db-instance \
    --db-instance-identifier social-media-db \
    --db-instance-class db.t3.micro \
    --engine mysql \
    --engine-version 8.0 \
    --master-username admin \
    --master-user-password YourStrongPassword123! \
    --allocated-storage 20 \
    --vpc-security-group-ids sg-xxxxxxxx \
    --db-subnet-group-name your-subnet-group \
    --backup-retention-period 7 \
    --publicly-accessible false
```

After creation, note the endpoint and update your application properties.

### 2. ElastiCache Redis

Create a Redis cluster:

```bash
aws elasticache create-cache-cluster \
    --cache-cluster-id social-media-redis \
    --cache-node-type cache.t3.micro \
    --engine redis \
    --num-cache-nodes 1 \
    --cache-subnet-group-name your-subnet-group \
    --security-group-ids sg-xxxxxxxx
```

### 3. Application Load Balancer (Optional but Recommended)

Create an ALB to route traffic to your API Gateway:

1. Go to EC2 Console → Load Balancers
2. Create Application Load Balancer
3. Add listener on port 80/443
4. Create target group pointing to API Gateway instance(s) on port 8080
5. Configure health check: `/actuator/health`

---

## Configuration Files for Production

### Update Gateway Routes

Create a production configuration file or use environment variables:

**backend/api-gateway/src/main/resources/application-prod.properties:**

```properties
spring.application.name=api-gateway
server.port=5000

# Gateway Routes - Use environment variables
spring.cloud.gateway.routes[0].id=auth-service
spring.cloud.gateway.routes[0].uri=${AUTH_SERVICE_URL:http://localhost:8081}
spring.cloud.gateway.routes[0].predicates[0]=Path=/api/auth/**
spring.cloud.gateway.routes[0].filters[0]=StripPrefix=2

spring.cloud.gateway.routes[1].id=social-service
spring.cloud.gateway.routes[1].uri=${SOCIAL_SERVICE_URL:http://localhost:8082}
spring.cloud.gateway.routes[1].predicates[0]=Path=/api/social/**
spring.cloud.gateway.routes[1].filters[0]=StripPrefix=2

# CORS Configuration
spring.cloud.gateway.globalcors.cors-configurations.[/**].allowed-origins=https://yourdomain.com
spring.cloud.gateway.globalcors.cors-configurations.[/**].allowed-methods=GET,POST,PUT,DELETE,OPTIONS
spring.cloud.gateway.globalcors.cors-configurations.[/**].allowed-headers=*
spring.cloud.gateway.globalcors.cors-configurations.[/**].allow-credentials=true

# JWT
jwt.secret=${JWT_SECRET}
jwt.expiration=86400000

# Logging
logging.level.org.springframework.cloud.gateway=INFO
logging.level.reactor.netty=WARN
```

---

## Deployment Checklist

- [ ] Build all services: `mvn clean package`
- [ ] Create RDS MySQL database
- [ ] Create ElastiCache Redis cluster
- [ ] Create S3 bucket for file uploads (for social-service images)
- [ ] Deploy auth-service
- [ ] Deploy social-service
- [ ] Deploy api-gateway
- [ ] Configure environment variables
- [ ] Update security groups
- [ ] Set up Application Load Balancer
- [ ] Configure Route 53 DNS (optional)
- [ ] Set up SSL certificate with ACM
- [ ] Test all endpoints
- [ ] Configure CloudWatch logs
- [ ] Set up auto-scaling (optional)

---

## Monitoring and Logs

### CloudWatch Logs

For Elastic Beanstalk, logs are automatically sent to CloudWatch.

For EC2 instances, install CloudWatch agent:

```bash
sudo yum install amazon-cloudwatch-agent -y
```

Configure it to send application logs to CloudWatch.

### Application Health

Access Spring Boot Actuator endpoints:
- http://your-api-gateway/actuator/health
- http://your-api-gateway/actuator/info
- http://your-api-gateway/actuator/metrics

---

## Cost Optimization Tips

1. **Use t3.small instances** instead of larger ones initially
2. **Enable RDS automated backups** but limit retention to 7 days
3. **Use ElastiCache t3.micro** for Redis
4. **Set up auto-scaling** to scale down during low traffic
5. **Use Reserved Instances** for predictable workloads (save up to 72%)
6. **Enable AWS Cost Explorer** to monitor spending

---

## Troubleshooting

### Service won't start
```bash
# Check logs
sudo journalctl -u auth-service -n 100

# Check if port is in use
sudo netstat -tulpn | grep 8081

# Test database connection
mysql -h YOUR_RDS_ENDPOINT -u admin -p
```

### Gateway can't reach backend services
- Check security groups allow traffic between services
- Verify environment variables are set correctly
- Check service URLs in gateway configuration

### Database connection issues
- Ensure RDS security group allows traffic from EC2 instances
- Verify database endpoint and credentials
- Check if database was created: `SHOW DATABASES;`

---

## Next Steps

1. **CI/CD Pipeline**: Set up GitHub Actions or AWS CodePipeline for automated deployments
2. **Monitoring**: Configure CloudWatch alarms for high CPU, memory usage
3. **Backup Strategy**: Set up automated database backups and snapshots
4. **Disaster Recovery**: Set up multi-AZ deployment for high availability
5. **Security**: Enable AWS WAF, use AWS Secrets Manager for credentials

---

## Estimated Monthly Costs (us-east-1)

- **EC2 (3 × t3.small)**: ~$45/month
- **RDS MySQL (db.t3.micro)**: ~$15/month
- **ElastiCache (cache.t3.micro)**: ~$12/month
- **Application Load Balancer**: ~$20/month
- **Data Transfer**: ~$5-10/month
- **S3 Storage**: ~$1-5/month

**Total**: ~$98-107/month

For Elastic Beanstalk approach, costs are similar (EB itself is free, you pay for underlying resources).

---

## Support

For issues or questions:
- AWS Documentation: https://docs.aws.amazon.com/
- Spring Boot on AWS: https://spring.io/guides/gs/spring-boot-on-aws-ec2/
- AWS Support: https://console.aws.amazon.com/support/
