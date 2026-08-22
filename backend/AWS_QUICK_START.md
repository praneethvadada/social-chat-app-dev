# AWS Deployment Quick Start

This guide provides the fastest path to deploy your backend to AWS.

## Prerequisites Checklist

- [ ] AWS Account created
- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] Java 17 installed
- [ ] Maven installed
- [ ] EB CLI installed (for Elastic Beanstalk option)

## Quick Deployment Steps

### Step 1: Choose Your Deployment Method

**Option A: Elastic Beanstalk (Easiest)**
- Managed platform
- Auto-scaling included
- Integrated with CloudWatch
- Best for: Quick deployment, less DevOps experience

**Option B: EC2 Instances (More Control)**
- Full control over instances
- Custom configurations
- Best for: Custom requirements, experienced DevOps

### Step 2: Set Up Infrastructure (10-15 minutes)

Run the automated setup script:

```powershell
cd backend
.\setup-aws-infrastructure.ps1
```

This creates:
- VPC with public/private subnets
- RDS MySQL database
- ElastiCache Redis cluster
- S3 bucket for file uploads
- Security groups

**Or manually create with CloudFormation:**

```bash
aws cloudformation create-stack \
  --stack-name social-media-backend \
  --template-body file://aws-infrastructure.yml \
  --parameters ParameterKey=DBPassword,ParameterValue=YourPassword123! \
  --region us-east-1
```

### Step 3: Build Applications

```bash
cd backend
# Windows
.\build-for-aws.bat

# Linux/Mac
./build-for-aws.sh
```

JAR files created in:
- `api-gateway/target/api-gateway-1.0.0.jar`
- `auth-service/target/auth-service-1.0.0.jar`
- `social-service/target/social-service-1.0.0.jar`

### Step 4A: Deploy to Elastic Beanstalk

#### Initialize EB for each service:

**Auth Service:**
```bash
cd backend/auth-service
eb init -p corretto-17 auth-service-app --region us-east-1
eb create auth-service-env --instance-type t3.small
```

**Social Service:**
```bash
cd backend/social-service
eb init -p corretto-17 social-service-app --region us-east-1
eb create social-service-env --instance-type t3.small
```

**API Gateway:**
```bash
cd backend/api-gateway
eb init -p corretto-17 api-gateway-app --region us-east-1
eb create api-gateway-env --instance-type t3.small
```

#### Set environment variables:

Get your RDS and Redis endpoints from CloudFormation outputs:

```bash
aws cloudformation describe-stacks --stack-name social-media-backend --query 'Stacks[0].Outputs'
```

**For Auth Service:**
```bash
cd backend/auth-service
eb setenv \
  SPRING_DATASOURCE_URL=jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db \
  SPRING_DATASOURCE_USERNAME=admin \
  SPRING_DATASOURCE_PASSWORD=YourPassword123! \
  SPRING_DATA_REDIS_HOST=YOUR_REDIS_ENDPOINT \
  JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 \
  SERVER_PORT=5000 \
  SPRING_PROFILES_ACTIVE=prod
```

**For Social Service:**
```bash
cd backend/social-service
eb setenv \
  SPRING_DATASOURCE_URL=jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db \
  SPRING_DATASOURCE_USERNAME=admin \
  SPRING_DATASOURCE_PASSWORD=YourPassword123! \
  SPRING_DATA_REDIS_HOST=YOUR_REDIS_ENDPOINT \
  JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 \
  AWS_S3_BUCKET=YOUR_S3_BUCKET \
  AWS_S3_ENABLED=true \
  SERVER_PORT=5000 \
  SPRING_PROFILES_ACTIVE=prod
```

**For API Gateway:**

First, get the URLs of deployed services:
```bash
eb status  # Run in each service directory to get URLs
```

Then set variables:
```bash
cd backend/api-gateway
eb setenv \
  AUTH_SERVICE_URL=http://auth-service-env.YOUR-REGION.elasticbeanstalk.com \
  SOCIAL_SERVICE_URL=http://social-service-env.YOUR-REGION.elasticbeanstalk.com \
  JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 \
  SERVER_PORT=5000 \
  SPRING_PROFILES_ACTIVE=prod
```

#### Deploy all services:

```bash
# Deploy auth service
cd backend/auth-service
eb deploy

# Deploy social service
cd backend/social-service
eb deploy

# Deploy API gateway
cd backend/api-gateway
eb deploy
```

### Step 4B: Deploy to EC2 Instances

See the full [AWS_DEPLOYMENT_GUIDE.md](./AWS_DEPLOYMENT_GUIDE.md) for detailed EC2 setup.

## Testing Your Deployment

### 1. Check Application Health

```bash
# Get API Gateway URL
eb status

# Test health endpoint
curl http://your-api-gateway-url/actuator/health
```

### 2. Test API Endpoints

```bash
# Register a user
curl -X POST http://your-api-gateway-url/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "password123"
  }'

# Login
curl -X POST http://your-api-gateway-url/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'
```

### 3. Check Logs

```bash
# Elastic Beanstalk
eb logs

# View in real-time
eb logs --stream
```

## Common Issues & Solutions

### Issue: Service won't start

**Solution:**
```bash
# Check logs
eb logs

# Common issues:
# - Database connection failed → Check RDS endpoint and security group
# - Redis connection failed → Check ElastiCache endpoint and security group
# - Port 5000 not configured → Set SERVER_PORT=5000 environment variable
```

### Issue: Gateway can't reach backend services

**Solution:**
```bash
# Ensure services are in same VPC
# Check security groups allow traffic between services
# Verify environment variables AUTH_SERVICE_URL and SOCIAL_SERVICE_URL
```

### Issue: Database connection timeout

**Solution:**
```bash
# Check RDS security group allows traffic from application security group
# Verify database endpoint is correct
# Ensure database is in running state
```

## Monitoring

### View Application Logs
```bash
eb logs --stream
```

### CloudWatch Metrics
Visit AWS Console → CloudWatch → Metrics → ApplicationELB

Monitor:
- Request count
- Target response time
- HTTP 4xx/5xx errors
- Healthy/unhealthy hosts

### Set Up Alarms
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name high-cpu-usage \
  --alarm-description "Alert when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold
```

## Scaling

### Manual Scaling
```bash
eb scale 3  # Scale to 3 instances
```

### Auto-Scaling Configuration
Edit `.ebextensions/autoscaling.config` in each service:

```yaml
option_settings:
  aws:autoscaling:asg:
    MinSize: 1
    MaxSize: 4
  aws:autoscaling:trigger:
    MeasureName: CPUUtilization
    Unit: Percent
    UpperThreshold: 70
    LowerThreshold: 20
```

## Cost Management

### Current Stack Cost Estimate
- EC2 instances (3 × t3.small): ~$45/month
- RDS MySQL (db.t3.micro): ~$15/month
- ElastiCache (cache.t3.micro): ~$12/month
- Load Balancer: ~$20/month
- S3 & Data Transfer: ~$5-10/month
**Total: ~$97-102/month**

### Cost Reduction Tips
1. Use Reserved Instances (save 30-70%)
2. Stop non-production environments outside business hours
3. Use AWS Cost Explorer
4. Set up billing alerts

## Update & Rollback

### Deploy New Version
```bash
# Build new version
mvn clean package

# Deploy
eb deploy
```

### Rollback to Previous Version
```bash
# List versions
eb appversion lifecycle

# Rollback
eb deploy --version your-previous-version
```

## Security Checklist

- [ ] Change default JWT_SECRET
- [ ] Use AWS Secrets Manager for sensitive data
- [ ] Enable HTTPS with ACM certificate
- [ ] Restrict RDS/Redis to private subnets only
- [ ] Enable CloudTrail for audit logging
- [ ] Set up AWS WAF for API protection
- [ ] Use IAM roles instead of access keys
- [ ] Enable MFA for AWS account
- [ ] Regular security updates: `eb upgrade`

## Getting Help

- Full guide: [AWS_DEPLOYMENT_GUIDE.md](./AWS_DEPLOYMENT_GUIDE.md)
- AWS Documentation: https://docs.aws.amazon.com/
- EB CLI Reference: https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/eb-cli3.html
- Spring Boot on AWS: https://spring.io/guides/gs/spring-boot-on-aws-ec2/

## Cleanup

To delete all resources and stop billing:

```bash
# Delete EB environments
eb terminate auth-service-env
eb terminate social-service-env
eb terminate api-gateway-env

# Delete CloudFormation stack
aws cloudformation delete-stack --stack-name social-media-backend
```

**⚠️ Warning:** This will permanently delete all data!
