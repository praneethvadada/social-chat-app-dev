# Social Service S3 Deployment Guide

## Overview
This guide explains how to deploy the social-service with AWS S3 integration for media storage.

## Changes Made

### 1. Code Updates
- **S3StorageService**: New service class that handles file uploads/downloads to S3
- **S3Config**: Configuration for AWS S3 client with default credentials provider
- **FileController**: Updated to use S3StorageService instead of local file storage
- **Dependencies**: Added AWS S3 SDK v2.20.26

### 2. Configuration Updates
Files now use S3 bucket configuration instead of local file paths:
```properties
aws.s3.bucket-name=social-media-app-bucket
aws.s3.region=us-east-1
```

## Prerequisites

### 1. Create S3 Bucket
Run the setup script:
```bash
chmod +x setup-s3-bucket.sh
./setup-s3-bucket.sh
```

Or create manually via AWS Console:
- Go to S3 Console
- Create bucket with name: `social-media-app-bucket`
- Region: `us-east-1` (or your preferred region)
- Configure CORS for web access
- Set public access settings to allow public reads on uploaded files

### 2. EC2 IAM Role Configuration
Your EC2 instance must have an IAM role with S3 permissions:

```json
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
```

To attach IAM role to EC2:
1. Go to EC2 Console
2. Select your instance
3. Actions → Security → Modify IAM role
4. Create/Select role with above S3 permissions
5. Save

### 3. Build the Project
```bash
# Use Java 17 for building
export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"  # Linux
# Or on Windows: set "JAVA_HOME=C:\Program Files\Java\jdk-17"

cd backend
mvn clean package -pl social-service -am -DskipTests
```

## Deployment Options

### Option 1: Automated Deployment (Windows)
```cmd
cd backend
deploy-social-service.bat
```

Follow the prompts to enter:
- EC2 instance IP
- Path to .pem key file
- RDS endpoint
- RDS password
- Redis endpoint
- S3 bucket name

### Option 2: Manual Deployment

#### Step 1: Prepare Environment File
Create `social-service.env` on EC2:
```bash
SPRING_PROFILES_ACTIVE=prod
PORT=8082

# Database
SPRING_DATASOURCE_URL=jdbc:mysql://your-rds.amazonaws.com:3306/auth_db?createDatabaseIfNotExist=true&useSSL=true
SPRING_DATASOURCE_USERNAME=admin
SPRING_DATASOURCE_PASSWORD=your-password

# Redis
SPRING_DATA_REDIS_HOST=your-redis.cache.amazonaws.com
SPRING_DATA_REDIS_PORT=6379

# JWT
JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437
JWT_EXPIRATION=86400000

# S3
AWS_S3_BUCKET=social-media-app-bucket
AWS_REGION=us-east-1

# Agora
AGORA_APP_ID=b7a780435e494cdf8c4d6e4bc59be7ab
AGORA_APP_CERT=7c3359b7e6214ec6a5bcca098d47ee77
```

#### Step 2: Upload Files to EC2
```bash
# Upload JAR
scp -i your-key.pem social-service/target/social-service-1.0.0.jar ubuntu@EC2_IP:/home/ubuntu/

# Upload service file
scp -i your-key.pem social-service.service ubuntu@EC2_IP:/tmp/
```

#### Step 3: Configure Service on EC2
```bash
ssh -i your-key.pem ubuntu@EC2_IP

# Install Java 17 if needed
sudo apt-get update
sudo apt-get install -y openjdk-17-jre-headless

# Move and configure service
sudo mv /tmp/social-service.service /etc/systemd/system/
sudo chmod 644 /etc/systemd/system/social-service.service

# Start service
sudo systemctl daemon-reload
sudo systemctl enable social-service
sudo systemctl start social-service

# Check status
sudo systemctl status social-service
```

## Verification

### 1. Check Service Health
```bash
curl http://YOUR_EC2_IP:8082/actuator/health
```

Expected response:
```json
{"status":"UP"}
```

### 2. Test File Upload
```bash
curl -X POST http://YOUR_EC2_IP:8082/files/upload \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -F "file=@test-image.jpg"
```

Expected response:
```json
{
  "fileUrl": "https://social-media-app-bucket.s3.us-east-1.amazonaws.com/uuid.jpg"
}
```

### 3. Verify File in S3
- Go to AWS S3 Console
- Open your bucket
- You should see the uploaded file with a UUID-based filename

### 4. Check Logs
```bash
# View logs
sudo journalctl -u social-service -f

# Check for errors
sudo journalctl -u social-service --no-pager | grep ERROR
```

## API Endpoints

### Upload File
```
POST /files/upload
Headers: Authorization: Bearer <token>
Body: multipart/form-data with "file" field
Response: { "fileUrl": "https://..." }
```

### Delete File
```
DELETE /files?fileUrl=<url>
Headers: Authorization: Bearer <token>
Response: 204 No Content
```

### Check File Exists
```
GET /files/check?fileUrl=<url>
Response: { "exists": true/false }
```

## Troubleshooting

### Issue: Service fails to start
```bash
# Check logs
sudo journalctl -u social-service -n 50

# Common issues:
# - Database connection failed → Check RDS endpoint and credentials
# - Redis connection failed → Check Redis endpoint
# - Port already in use → Check if another service is using port 8082
```

### Issue: S3 upload fails with "Access Denied"
- Verify EC2 instance has IAM role with S3 permissions
- Check bucket policy and CORS configuration
- Verify bucket name in environment variables

### Issue: Files upload but return 403 when accessed
- Check S3 bucket public access settings
- Verify ACL is set to public-read in S3StorageService
- Check bucket CORS configuration

## Security Considerations

1. **IAM Roles**: Use EC2 IAM roles instead of hardcoded AWS credentials
2. **Bucket Access**: Configure bucket policies to restrict access as needed
3. **File Validation**: Implement file type and size validation before upload
4. **JWT Authentication**: All file operations require valid JWT token
5. **HTTPS**: Use HTTPS in production for secure file transfers

## Monitoring

### CloudWatch Metrics
Monitor S3 usage:
- Number of requests
- Data transferred
- 4xx/5xx errors

### Application Metrics
```bash
# Check service metrics
curl http://YOUR_EC2_IP:8082/actuator/metrics

# Check specific metric
curl http://YOUR_EC2_IP:8082/actuator/metrics/jvm.memory.used
```

## Cost Optimization

1. **Lifecycle Policies**: Set up lifecycle rules to delete old files
2. **Storage Class**: Use S3 Standard-IA for infrequently accessed files
3. **CloudFront**: Add CDN for better performance and lower costs
4. **Request Optimization**: Batch operations where possible

## Next Steps

1. **Add CloudFront**: Set up CDN for better media delivery
2. **Image Processing**: Add Lambda for automatic image resizing/optimization
3. **Video Support**: Integrate with MediaConvert for video processing
4. **Backup**: Set up S3 versioning and cross-region replication
5. **Monitoring**: Set up CloudWatch alarms for S3 errors

## Support

For issues or questions:
- Check logs: `sudo journalctl -u social-service -f`
- Review S3 bucket permissions in AWS Console
- Verify IAM role has required S3 permissions
- Check security group allows port 8082
