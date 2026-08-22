# Step-by-Step EC2 Deployment Guide

Complete guide to deploy your Spring Boot backend on AWS EC2 instances.

---

## Prerequisites Checklist

Before starting, ensure you have:
- [ ] AWS Account created
- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] Java 17 installed locally
- [ ] Maven installed locally
- [ ] SSH client (built into Windows 10+)

---

## Phase 1: Create AWS Infrastructure (15-20 minutes)

### Step 1: Verify AWS Configuration

```bash
aws configure list
aws sts get-caller-identity
```

You should see your AWS account details.

### Step 2: Create EC2 Key Pair

This key will be used to SSH into your EC2 instances.

```bash
cd backend

# Create key pair
aws ec2 create-key-pair --key-name social-media-key --query 'KeyMaterial' --output text > social-media-key.pem

# Set proper permissions (Git Bash or WSL)
chmod 400 social-media-key.pem
```

**Windows PowerShell alternative:**
```powershell
aws ec2 create-key-pair --key-name social-media-key --query 'KeyMaterial' --output text | Out-File -Encoding ascii social-media-key.pem
icacls social-media-key.pem /inheritance:r
icacls social-media-key.pem /grant:r "%username%:R"
```

### Step 3: Deploy Infrastructure with CloudFormation

```bash
aws cloudformation create-stack ^
  --stack-name social-media-backend ^
  --template-body file://aws-infrastructure.yml ^
  --parameters ParameterKey=DBPassword,ParameterValue=YourStrongPassword123! ^
  --region us-east-1
```

**Wait for completion:**
```bash
aws cloudformation wait stack-create-complete --stack-name social-media-backend --region us-east-1
```

This creates:
- VPC with subnets
- RDS MySQL database
- ElastiCache Redis
- S3 bucket
- Security groups

### Step 4: Get Infrastructure Outputs

```bash
aws cloudformation describe-stacks --stack-name social-media-backend --query 'Stacks[0].Outputs' --output table
```

**Save these values:**
- `DBEndpoint` - RDS endpoint
- `RedisEndpoint` - Redis endpoint
- `S3BucketName` - S3 bucket name
- `VPCId` - VPC ID
- `PublicSubnet1Id` - Subnet for EC2 instances
- `ApplicationSecurityGroupId` - Security group for EC2

---

## Phase 2: Build Applications (5 minutes)

### Step 5: Build JAR Files

```bash
cd backend
mvn clean package -DskipTests
```

**Verify JAR files:**
```bash
dir api-gateway\target\api-gateway-1.0.0.jar
dir auth-service\target\auth-service-1.0.0.jar
dir social-service\target\social-service-1.0.0.jar
```

---

## Phase 3: Launch EC2 Instances (10 minutes)

### Step 6: Get Latest Amazon Linux 2023 AMI

```bash
aws ec2 describe-images ^
  --owners amazon ^
  --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" ^
  --query "sort_by(Images, &CreationDate)[-1].ImageId" ^
  --output text
```

Save this AMI ID (e.g., `ami-0c55b159cbfafe1f0`)

### Step 7: Get Security Group and Subnet IDs

From Step 4 outputs, you need:
- Application Security Group ID (e.g., `sg-xxxxx`)
- Public Subnet 1 ID (e.g., `subnet-xxxxx`)

### Step 8: Launch EC2 Instance for Auth Service

```bash
aws ec2 run-instances ^
  --image-id ami-XXXXXXXXX ^
  --instance-type t3.small ^
  --key-name social-media-key ^
  --security-group-ids sg-XXXXXXXXX ^
  --subnet-id subnet-XXXXXXXXX ^
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=auth-service},{Key=Service,Value=auth}]" ^
  --user-data file://ec2-user-data-java.sh ^
  --associate-public-ip-address
```

### Step 9: Launch EC2 Instance for Social Service

```bash
aws ec2 run-instances ^
  --image-id ami-XXXXXXXXX ^
  --instance-type t3.small ^
  --key-name social-media-key ^
  --security-group-ids sg-XXXXXXXXX ^
  --subnet-id subnet-XXXXXXXXX ^
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=social-service},{Key=Service,Value=social}]" ^
  --associate-public-ip-address
```

### Step 10: Launch EC2 Instance for API Gateway

```bash
aws ec2 run-instances ^
  --image-id ami-XXXXXXXXX ^
  --instance-type t3.small ^
  --key-name social-media-key ^
  --security-group-ids sg-XXXXXXXXX ^
  --subnet-id subnet-XXXXXXXXX ^
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=api-gateway},{Key=Service,Value=gateway}]" ^
  --associate-public-ip-address
```

### Step 11: Get Instance IPs

```bash
# Get all instances
aws ec2 describe-instances ^
  --filters "Name=tag:Name,Values=auth-service,social-service,api-gateway" "Name=instance-state-name,Values=running" ^
  --query "Reservations[*].Instances[*].[Tags[?Key=='Name'].Value|[0],PublicIpAddress,PrivateIpAddress]" ^
  --output table
```

**Save these IPs:**
- Auth Service: Public IP = `X.X.X.X`, Private IP = `10.0.X.X`
- Social Service: Public IP = `Y.Y.Y.Y`, Private IP = `10.0.Y.Y`
- API Gateway: Public IP = `Z.Z.Z.Z`, Private IP = `10.0.Z.Z`

---

## Phase 4: Configure Security Groups (5 minutes)

### Step 12: Allow SSH Access (Temporary)

```bash
# Get your current IP
curl -s https://checkip.amazonaws.com

# Allow SSH from your IP only
aws ec2 authorize-security-group-ingress ^
  --group-id sg-XXXXXXXXX ^
  --protocol tcp ^
  --port 22 ^
  --cidr YOUR_IP/32
```

### Step 13: Configure Service-to-Service Communication

```bash
# Get Application Security Group ID
set APP_SG=sg-XXXXXXXXX

# Allow API Gateway to access Auth Service (port 8081)
aws ec2 authorize-security-group-ingress ^
  --group-id %APP_SG% ^
  --protocol tcp ^
  --port 8081 ^
  --source-group %APP_SG%

# Allow API Gateway to access Social Service (port 8082)
aws ec2 authorize-security-group-ingress ^
  --group-id %APP_SG% ^
  --protocol tcp ^
  --port 8082 ^
  --source-group %APP_SG%

# Allow public access to API Gateway (port 8080)
aws ec2 authorize-security-group-ingress ^
  --group-id %APP_SG% ^
  --protocol tcp ^
  --port 8080 ^
  --cidr 0.0.0.0/0
```

---

## Phase 5: Deploy Auth Service (15 minutes)

### Step 14: Connect to Auth Service Instance

```bash
ssh -i social-media-key.pem ec2-user@AUTH_SERVICE_PUBLIC_IP
```

### Step 15: Install Java on Auth Service

```bash
# Update system
sudo yum update -y

# Install Java 17
sudo yum install java-17-amazon-corretto-devel -y

# Verify
java -version
```

### Step 16: Upload JAR File

**On your local machine (new terminal):**
```bash
cd backend
scp -i social-media-key.pem auth-service/target/auth-service-1.0.0.jar ec2-user@AUTH_SERVICE_PUBLIC_IP:/home/ec2-user/
```

### Step 17: Create Environment File

**On EC2 instance:**
```bash
cat > /home/ec2-user/auth-service.env << 'EOF'
SPRING_DATASOURCE_URL=jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db
SPRING_DATASOURCE_USERNAME=admin
SPRING_DATASOURCE_PASSWORD=YourStrongPassword123!
SPRING_DATA_REDIS_HOST=YOUR_REDIS_ENDPOINT
SPRING_DATA_REDIS_PORT=6379
JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437
SERVER_PORT=8081
SPRING_PROFILES_ACTIVE=prod
EOF
```

**Replace placeholders with actual values from Step 4.**

### Step 18: Create SystemD Service

```bash
sudo tee /etc/systemd/system/auth-service.service > /dev/null << 'EOF'
[Unit]
Description=Auth Service
After=syslog.target network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user
EnvironmentFile=/home/ec2-user/auth-service.env
ExecStart=/usr/bin/java -jar /home/ec2-user/auth-service-1.0.0.jar
SuccessExitStatus=143
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

### Step 19: Start Auth Service

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable service to start on boot
sudo systemctl enable auth-service

# Start service
sudo systemctl start auth-service

# Check status
sudo systemctl status auth-service

# View logs
sudo journalctl -u auth-service -f
```

**Press Ctrl+C to exit logs when service is running.**

---

## Phase 6: Deploy Social Service (15 minutes)

### Step 20: Connect to Social Service Instance

**New terminal:**
```bash
ssh -i social-media-key.pem ec2-user@SOCIAL_SERVICE_PUBLIC_IP
```

### Step 21: Install Java

```bash
sudo yum update -y
sudo yum install java-17-amazon-corretto-devel -y
java -version
```

### Step 22: Upload JAR File

**Local machine:**
```bash
scp -i social-media-key.pem social-service/target/social-service-1.0.0.jar ec2-user@SOCIAL_SERVICE_PUBLIC_IP:/home/ec2-user/
```

### Step 23: Create Environment File

**On EC2:**
```bash
cat > /home/ec2-user/social-service.env << 'EOF'
SPRING_DATASOURCE_URL=jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db
SPRING_DATASOURCE_USERNAME=admin
SPRING_DATASOURCE_PASSWORD=YourStrongPassword123!
SPRING_DATA_REDIS_HOST=YOUR_REDIS_ENDPOINT
SPRING_DATA_REDIS_PORT=6379
JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437
SERVER_PORT=8082
SPRING_PROFILES_ACTIVE=prod
FILE_UPLOAD_DIR=/home/ec2-user/uploads/images
AWS_S3_ENABLED=false
EOF
```

### Step 24: Create Upload Directory

```bash
mkdir -p /home/ec2-user/uploads/images
```

### Step 25: Create SystemD Service

```bash
sudo tee /etc/systemd/system/social-service.service > /dev/null << 'EOF'
[Unit]
Description=Social Service
After=syslog.target network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user
EnvironmentFile=/home/ec2-user/social-service.env
ExecStart=/usr/bin/java -jar /home/ec2-user/social-service-1.0.0.jar
SuccessExitStatus=143
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

### Step 26: Start Social Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable social-service
sudo systemctl start social-service
sudo systemctl status social-service
sudo journalctl -u social-service -f
```

---

## Phase 7: Deploy API Gateway (15 minutes)

### Step 27: Connect to API Gateway Instance

**New terminal:**
```bash
ssh -i social-media-key.pem ec2-user@API_GATEWAY_PUBLIC_IP
```

### Step 28: Install Java

```bash
sudo yum update -y
sudo yum install java-17-amazon-corretto-devel -y
java -version
```

### Step 29: Upload JAR File

**Local machine:**
```bash
scp -i social-media-key.pem api-gateway/target/api-gateway-1.0.0.jar ec2-user@API_GATEWAY_PUBLIC_IP:/home/ec2-user/
```

### Step 30: Create Environment File

**Use private IPs from Step 11:**
```bash
cat > /home/ec2-user/api-gateway.env << 'EOF'
AUTH_SERVICE_URL=http://AUTH_PRIVATE_IP:8081
SOCIAL_SERVICE_URL=http://SOCIAL_PRIVATE_IP:8082
JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437
SERVER_PORT=8080
SPRING_PROFILES_ACTIVE=prod
CORS_ALLOWED_ORIGINS=*
CORS_ALLOW_CREDENTIALS=false
EOF
```

### Step 31: Create SystemD Service

```bash
sudo tee /etc/systemd/system/api-gateway.service > /dev/null << 'EOF'
[Unit]
Description=API Gateway
After=syslog.target network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user
EnvironmentFile=/home/ec2-user/api-gateway.env
ExecStart=/usr/bin/java -jar /home/ec2-user/api-gateway-1.0.0.jar
SuccessExitStatus=143
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

### Step 32: Start API Gateway

```bash
sudo systemctl daemon-reload
sudo systemctl enable api-gateway
sudo systemctl start api-gateway
sudo systemctl status api-gateway
sudo journalctl -u api-gateway -f
```

---

## Phase 8: Test Deployment (10 minutes)

### Step 33: Test Health Endpoint

**From local machine:**
```bash
curl http://API_GATEWAY_PUBLIC_IP:8080/actuator/health
```

Expected response:
```json
{"status":"UP"}
```

### Step 34: Test User Registration

```bash
curl -X POST http://API_GATEWAY_PUBLIC_IP:8080/api/auth/register ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"testuser\",\"email\":\"test@example.com\",\"password\":\"password123\"}"
```

### Step 35: Test Login

```bash
curl -X POST http://API_GATEWAY_PUBLIC_IP:8080/api/auth/login ^
  -H "Content-Type: application/json" ^
  -d "{\"email\":\"test@example.com\",\"password\":\"password123\"}"
```

You should receive a JWT token.

---

## Troubleshooting

### Service Won't Start

```bash
# Check logs
sudo journalctl -u auth-service -n 100

# Check if port is in use
sudo netstat -tulpn | grep 8081

# Restart service
sudo systemctl restart auth-service
```

### Database Connection Failed

```bash
# Test from EC2
mysql -h YOUR_RDS_ENDPOINT -u admin -p

# Check security group allows MySQL (3306) from EC2 instances
```

### Gateway Can't Reach Services

```bash
# Test connectivity from gateway instance
curl http://AUTH_PRIVATE_IP:8081/actuator/health
curl http://SOCIAL_PRIVATE_IP:8082/actuator/health

# Check security groups allow traffic between instances
```

---

## Useful Commands

**Check service status:**
```bash
sudo systemctl status auth-service
sudo systemctl status social-service
sudo systemctl status api-gateway
```

**View logs:**
```bash
sudo journalctl -u auth-service -f
sudo journalctl -u social-service -f
sudo journalctl -u api-gateway -f
```

**Restart service:**
```bash
sudo systemctl restart auth-service
```

**Stop service:**
```bash
sudo systemctl stop auth-service
```

**Update JAR file:**
```bash
# Stop service
sudo systemctl stop auth-service

# Upload new JAR from local machine
scp -i social-media-key.pem auth-service/target/auth-service-1.0.0.jar ec2-user@IP:/home/ec2-user/

# Start service
sudo systemctl start auth-service
```

---

## Next Steps

1. ✅ **Set up Application Load Balancer** for high availability
2. ✅ **Configure HTTPS** with SSL certificate
3. ✅ **Set up CloudWatch** for monitoring
4. ✅ **Enable auto-scaling** for production
5. ✅ **Convert file storage to S3** (important!)

---

## Cost Estimate

- **3 × t3.small EC2**: ~$45/month
- **RDS MySQL (db.t3.micro)**: ~$15/month
- **ElastiCache Redis**: ~$12/month
- **Data transfer**: ~$5/month
- **S3 storage**: ~$1-5/month

**Total: ~$78-82/month**

Add $20/month for Application Load Balancer if needed.
