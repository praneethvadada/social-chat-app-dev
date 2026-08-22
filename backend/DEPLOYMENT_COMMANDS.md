# Quick Deployment Commands - Social Service with S3

## Prerequisites Setup

### 1. Create S3 Bucket
```bash
# Make script executable
chmod +x setup-s3-bucket.sh

# Run setup
./setup-s3-bucket.sh
# Enter bucket name: social-media-app-bucket
# Enter region: us-east-1
```

### 2. Configure EC2 IAM Role
```bash
# Create IAM policy (save as s3-policy.json)
cat > s3-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl",
                "s3:GetObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::social-media-app-bucket",
                "arn:aws:s3:::social-media-app-bucket/*"
            ]
        }
    ]
}
EOF

# Create IAM policy
aws iam create-policy \
    --policy-name SocialMediaS3Access \
    --policy-document file://s3-policy.json

# Create IAM role for EC2
aws iam create-role \
    --role-name SocialMediaEC2Role \
    --assume-role-policy-document file://trust-policy.json

# Attach policy to role
aws iam attach-role-policy \
    --role-name SocialMediaEC2Role \
    --policy-arn arn:aws:iam::YOUR_ACCOUNT_ID:policy/SocialMediaS3Access

# Attach role to EC2 instance
aws ec2 associate-iam-instance-profile \
    --instance-id i-YOUR_INSTANCE_ID \
    --iam-instance-profile Name=SocialMediaEC2Role
```

## Build Project

### Using Java 17 (Windows)
```cmd
set "JAVA_HOME=C:\Program Files\Java\jdk-17"
set "PATH=%JAVA_HOME%\bin;%PATH%"
cd backend
mvn clean package -pl social-service -am -DskipTests
```

### Using Java 17 (Linux/Mac)
```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH=$JAVA_HOME/bin:$PATH
cd backend
mvn clean package -pl social-service -am -DskipTests
```

## Deploy to AWS

### Option 1: Windows Automated Deployment
```cmd
cd backend
deploy-social-service.bat
```

Then enter when prompted:
- EC2 IP: `54.XXX.XXX.XXX`
- Key file: `C:\path\to\your-key.pem`
- RDS endpoint: `your-db.xxxxxx.us-east-1.rds.amazonaws.com`
- RDS password: `yourpassword`
- Redis endpoint: `your-redis.xxxxxx.cache.amazonaws.com`
- S3 bucket: `social-media-app-bucket`

### Option 2: Manual Deployment
```bash
# 1. Upload JAR
scp -i your-key.pem \
    social-service/target/social-service-1.0.0.jar \
    ubuntu@EC2_IP:/home/ubuntu/

# 2. Create environment file on EC2
ssh -i your-key.pem ubuntu@EC2_IP
cat > /home/ubuntu/social-service.env << 'EOF'
SPRING_PROFILES_ACTIVE=prod
PORT=8082
SPRING_DATASOURCE_URL=jdbc:mysql://RDS_ENDPOINT:3306/auth_db?createDatabaseIfNotExist=true&useSSL=true
SPRING_DATASOURCE_USERNAME=admin
SPRING_DATASOURCE_PASSWORD=YOUR_PASSWORD
SPRING_DATA_REDIS_HOST=REDIS_ENDPOINT
SPRING_DATA_REDIS_PORT=6379
JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437
JWT_EXPIRATION=86400000
AWS_S3_BUCKET=social-media-app-bucket
AWS_REGION=us-east-1
AGORA_APP_ID=b7a780435e494cdf8c4d6e4bc59be7ab
AGORA_APP_CERT=7c3359b7e6214ec6a5bcca098d47ee77
EOF

# 3. Upload and configure service file
exit
scp -i your-key.pem \
    social-service.service \
    ubuntu@EC2_IP:/tmp/

# 4. Setup service
ssh -i your-key.pem ubuntu@EC2_IP
sudo mv /tmp/social-service.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/social-service.service
sudo systemctl daemon-reload
sudo systemctl enable social-service
sudo systemctl start social-service
sudo systemctl status social-service
```

## Update API Gateway

```bash
# SSH to API Gateway EC2
ssh -i your-key.pem ubuntu@API_GATEWAY_IP

# Edit environment file
sudo nano /home/ubuntu/api-gateway.env

# Add this line (use private IP if in same VPC):
SOCIAL_SERVICE_URL=http://SOCIAL_EC2_PRIVATE_IP:8082

# Restart API Gateway
sudo systemctl restart api-gateway
sudo systemctl status api-gateway
```

## Verification Commands

### Check Service Status
```bash
# On EC2
ssh -i your-key.pem ubuntu@EC2_IP
sudo systemctl status social-service
sudo journalctl -u social-service -n 50

# Health check
curl http://localhost:8082/actuator/health
```

### Test S3 Upload
```bash
# Get JWT token first
TOKEN=$(curl -X POST http://API_GATEWAY_IP:4000/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"test@example.com","password":"password"}' \
    | jq -r '.token')

# Upload test file
curl -X POST http://API_GATEWAY_IP:4000/social/files/upload \
    -H "Authorization: Bearer $TOKEN" \
    -F "file=@test-image.jpg"

# Should return: {"fileUrl": "https://social-media-app-bucket.s3.us-east-1.amazonaws.com/..."}
```

### Check S3 Bucket
```bash
# List files in bucket
aws s3 ls s3://social-media-app-bucket/

# Check specific file
aws s3 ls s3://social-media-app-bucket/YOUR_FILE.jpg
```

### View Logs
```bash
# Real-time logs
ssh -i your-key.pem ubuntu@EC2_IP
sudo journalctl -u social-service -f

# Recent errors
sudo journalctl -u social-service --no-pager | grep ERROR

# Last 100 lines
sudo journalctl -u social-service -n 100
```

## Troubleshooting

### Service Won't Start
```bash
# Check Java installation
java -version

# Check port availability
sudo netstat -tlnp | grep 8082

# Check environment file
cat /home/ubuntu/social-service.env

# Check permissions
ls -la /home/ubuntu/social-service-1.0.0.jar
```

### S3 Upload Fails
```bash
# Check IAM role
aws sts get-caller-identity

# Test S3 access from EC2
aws s3 ls s3://social-media-app-bucket/

# Check bucket permissions
aws s3api get-bucket-acl --bucket social-media-app-bucket
```

### Database Connection Issues
```bash
# Test connection from EC2
telnet RDS_ENDPOINT 3306

# Check security groups
# - EC2 security group must allow outbound to RDS
# - RDS security group must allow inbound from EC2
```

### Redis Connection Issues
```bash
# Test Redis connection
telnet REDIS_ENDPOINT 6379

# Check security groups
# - EC2 must have outbound to Redis
# - Redis must allow inbound from EC2
```

## Quick Reference

### Service Commands
```bash
sudo systemctl start social-service    # Start service
sudo systemctl stop social-service     # Stop service
sudo systemctl restart social-service  # Restart service
sudo systemctl status social-service   # Check status
```

### Log Commands
```bash
sudo journalctl -u social-service -f              # Follow logs
sudo journalctl -u social-service -n 50           # Last 50 lines
sudo journalctl -u social-service --since "1h ago" # Last hour
```

### Health Checks
```bash
curl http://localhost:8082/actuator/health        # Health
curl http://localhost:8082/actuator/info          # Info
curl http://localhost:8082/swagger-ui.html        # Swagger UI
```

## Performance Monitoring

### CloudWatch Metrics
```bash
# S3 metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/S3 \
    --metric-name NumberOfObjects \
    --dimensions Name=BucketName,Value=social-media-app-bucket \
    --start-time 2025-12-23T00:00:00Z \
    --end-time 2025-12-24T00:00:00Z \
    --period 3600 \
    --statistics Average

# Application metrics available at:
curl http://localhost:8082/actuator/metrics
```

## Cost Monitoring

```bash
# Check S3 storage usage
aws s3 ls s3://social-media-app-bucket --recursive --summarize

# Estimate costs
# Storage: $0.023 per GB/month
# PUT requests: $0.005 per 1,000 requests
# GET requests: $0.0004 per 1,000 requests
```

## Next Steps Checklist

- [ ] S3 bucket created and configured
- [ ] IAM role attached to EC2
- [ ] Social-service deployed and running
- [ ] API Gateway updated and restarted
- [ ] File upload tested successfully
- [ ] Files accessible via S3 URLs
- [ ] CloudWatch alarms configured
- [ ] Backup strategy implemented
- [ ] CDN (CloudFront) configured
- [ ] Mobile app updated to use S3 URLs
