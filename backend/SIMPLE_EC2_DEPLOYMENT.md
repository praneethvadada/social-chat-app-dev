# Simplified EC2 Deployment Guide - Step by Step

This guide will deploy your backend to AWS EC2 using simple, direct commands.

---

## ✅ Current Status

- ✅ AWS CLI configured
- ✅ SSH key created (social-media-key.pem)
- ✅ API Gateway JAR built
- ✅ Auth Service JAR built
- ⏳ Social Service - needs Java version fix (we'll do this later)

**We'll deploy API Gateway and Auth Service first!**

---

## Phase 1: Create Database (RDS MySQL) - 5 minutes

### Step 1: Create RDS MySQL Instance

```bash
aws rds create-db-instance --db-instance-identifier social-media-db --db-instance-class db.t3.micro --engine mysql --engine-version 8.0.35 --master-username admin --master-user-password SecurePass123! --allocated-storage 20 --publicly-accessible --backup-retention-period 0 --no-multi-az --region us-east-1
```

**Wait for database to be ready (5-10 minutes):**

```bash
aws rds wait db-instance-available --db-instance-identifier social-media-db --region us-east-1
```

**Get database endpoint:**

```bash
aws rds describe-db-instances --db-instance-identifier social-media-db --query "DBInstances[0].Endpoint.Address" --output text
```

**Save this endpoint!** Example: `social-media-db.xxxxx.us-east-1.rds.amazonaws.com`

---

## Phase 2: Create Redis (ElastiCache) - 5 minutes

### Step 2: Create ElastiCache Redis

```bash
aws elasticache create-cache-cluster --cache-cluster-id social-media-redis --cache-node-type cache.t3.micro --engine redis --num-cache-nodes 1 --region us-east-1
```

**Wait for Redis to be ready:**

```bash
aws elasticache wait cache-cluster-available --cache-cluster-id social-media-redis --region us-east-1
```

**Get Redis endpoint:**

```bash
aws elasticache describe-cache-clusters --cache-cluster-id social-media-redis --show-cache-node-info --query "CacheClusters[0].CacheNodes[0].Endpoint.Address" --output text
```

**Save this endpoint!** Example: `social-media-redis.xxxxx.0001.use1.cache.amazonaws.com`

---

## Phase 3: Launch EC2 Instances - 10 minutes

### Step 3: Get Latest Amazon Linux AMI

```bash
aws ec2 describe-images --owners amazon --filters "Name=name,Values=al2023-ami-2023*-x86_64" "Name=state,Values=available" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text
```

**Save the AMI ID!** Example: `ami-0c55b159cbfafe1f0`

### Step 4: Create Security Group

```bash
aws ec2 create-security-group --group-name social-media-sg --description "Security group for social media app" --region us-east-1
```

**Get security group ID:**

```bash
aws ec2 describe-security-groups --group-names social-media-sg --query "SecurityGroups[0].GroupId" --output text
```

**Save the SG ID!** Example: `sg-0123456789abcdef`

### Step 5: Add Security Group Rules

Replace `YOUR_SG_ID` with your security group ID:

```bash
# Allow SSH from your IP
aws ec2 authorize-security-group-ingress --group-id YOUR_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

# Allow API Gateway (8080) from internet
aws ec2 authorize-security-group-ingress --group-id YOUR_SG_ID --protocol tcp --port 8080 --cidr 0.0.0.0/0

# Allow Auth Service (8081) within security group
aws ec2 authorize-security-group-ingress --group-id YOUR_SG_ID --protocol tcp --port 8081 --source-group YOUR_SG_ID

# Allow MySQL (3306) from security group
aws ec2 authorize-security-group-ingress --group-id YOUR_SG_ID --protocol tcp --port 3306 --source-group YOUR_SG_ID

# Allow Redis (6379) from security group  
aws ec2 authorize-security-group-ingress --group-id YOUR_SG_ID --protocol tcp --port 6379 --source-group YOUR_SG_ID
```

### Step 6: Launch Auth Service Instance

Replace `YOUR_AMI_ID` and `YOUR_SG_ID`:

```bash
aws ec2 run-instances --image-id YOUR_AMI_ID --instance-type t3.small --key-name social-media-key --security-group-ids YOUR_SG_ID --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=auth-service}]" --region us-east-1
```

### Step 7: Launch API Gateway Instance

```bash
aws ec2 run-instances --image-id YOUR_AMI_ID --instance-type t3.small --key-name social-media-key --security-group-ids YOUR_SG_ID --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=api-gateway}]" --region us-east-1
```

### Step 8: Get Instance IPs

**Wait 2 minutes for instances to start, then:**

```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=auth-service,api-gateway" "Name=instance-state-name,Values=running" --query "Reservations[*].Instances[*].[Tags[?Key=='Name'].Value|[0],PublicIpAddress,PrivateIpAddress]" --output table
```

**Save these IPs:**
- Auth Service: Public IP = `X.X.X.X`, Private IP = `10.0.X.X`
- API Gateway: Public IP = `Y.Y.Y.Y`, Private IP = `10.0.Y.Y`

---

## Phase 4: Deploy Auth Service - 15 minutes

### Step 9: Connect to Auth Service Instance

Replace `AUTH_PUBLIC_IP` with your auth service public IP:

```bash
ssh -i social-media-key.pem ec2-user@AUTH_PUBLIC_IP
```

**If you get a permissions error on Windows:**
- Right-click `social-media-key.pem` → Properties → Security
- Remove all users except yourself
- Give yourself Read permissions only

### Step 10: Install Java on Auth Service

**On the EC2 instance:**

```bash
sudo yum update -y
sudo yum install java-17-amazon-corretto-devel -y
java -version
```

### Step 11: Upload Auth Service JAR

**Open a NEW terminal on your local machine:**

```bash
cd "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend"
scp -i social-media-key.pem auth-service/target/auth-service-1.0.0.jar ec2-user@AUTH_PUBLIC_IP:/home/ec2-user/
```

### Step 12: Create Environment Configuration

**Back on the EC2 instance, create environment file:**

Replace `YOUR_RDS_ENDPOINT` and `YOUR_REDIS_ENDPOINT` with values from Steps 1 and 2:

```bash
cat > /home/ec2-user/auth-service.env << 'EOF'
SPRING_DATASOURCE_URL=jdbc:mysql://YOUR_RDS_ENDPOINT:3306/auth_db?createDatabaseIfNotExist=true
SPRING_DATASOURCE_USERNAME=admin
SPRING_DATASOURCE_PASSWORD=SecurePass123!
SPRING_DATA_REDIS_HOST=YOUR_REDIS_ENDPOINT
SPRING_DATA_REDIS_PORT=6379
JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437
SERVER_PORT=8081
SPRING_PROFILES_ACTIVE=prod
EOF
```

### Step 13: Create SystemD Service

```bash
sudo tee /etc/systemd/system/auth-service.service > /dev/null << 'EOF'
[Unit]
Description=Auth Service
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user
EnvironmentFile=/home/ec2-user/auth-service.env
ExecStart=/usr/bin/java -jar /home/ec2-user/auth-service-1.0.0.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

### Step 14: Start Auth Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable auth-service
sudo systemctl start auth-service

# Check status
sudo systemctl status auth-service

# View logs
sudo journalctl -u auth-service -f
```

**Wait until you see:** `Started AuthServiceApplication` in the logs.
**Press Ctrl+C** to exit logs.

---

## Phase 5: Deploy API Gateway - 15 minutes

### Step 15: Connect to API Gateway Instance

**New terminal:**

```bash
ssh -i social-media-key.pem ec2-user@API_GATEWAY_PUBLIC_IP
```

### Step 16: Install Java

```bash
sudo yum update -y
sudo yum install java-17-amazon-corretto-devel -y
java -version
```

### Step 17: Upload API Gateway JAR

**Local terminal:**

```bash
scp -i social-media-key.pem api-gateway/target/api-gateway-1.0.0.jar ec2-user@API_GATEWAY_PUBLIC_IP:/home/ec2-user/
```

### Step 18: Create Environment Configuration

**On EC2, use the PRIVATE IP of auth service from Step 8:**

```bash
cat > /home/ec2-user/api-gateway.env << 'EOF'
AUTH_SERVICE_URL=http://AUTH_PRIVATE_IP:8081
JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437
SERVER_PORT=8080
SPRING_PROFILES_ACTIVE=prod
CORS_ALLOWED_ORIGINS=*
EOF
```

### Step 19: Create SystemD Service

```bash
sudo tee /etc/systemd/system/api-gateway.service > /dev/null << 'EOF'
[Unit]
Description=API Gateway
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/home/ec2-user
EnvironmentFile=/home/ec2-user/api-gateway.env
ExecStart=/usr/bin/java -jar /home/ec2-user/api-gateway-1.0.0.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

### Step 20: Start API Gateway

```bash
sudo systemctl daemon-reload
sudo systemctl enable api-gateway
sudo systemctl start api-gateway
sudo systemctl status api-gateway
sudo journalctl -u api-gateway -f
```

---

## Phase 6: Test Your Deployment! - 5 minutes

### Step 21: Test Health Endpoint

**From your local machine:**

```bash
curl http://API_GATEWAY_PUBLIC_IP:8080/actuator/health
```

**Expected:** `{"status":"UP"}`

### Step 22: Test User Registration

```bash
curl -X POST http://API_GATEWAY_PUBLIC_IP:8080/api/auth/register -H "Content-Type: application/json" -d "{\"username\":\"testuser\",\"email\":\"test@example.com\",\"password\":\"password123\"}"
```

### Step 23: Test Login

```bash
curl -X POST http://API_GATEWAY_PUBLIC_IP:8080/api/auth/login -H "Content-Type: application/json" -d "{\"email\":\"test@example.com\",\"password\":\"password123\"}"
```

**You should get a JWT token!** 🎉

---

## Summary of What You Deployed

✅ **RDS MySQL Database** - Stores user data
✅ **ElastiCache Redis** - Caching and sessions
✅ **Auth Service EC2** - Handles authentication  
✅ **API Gateway EC2** - Routes requests

**Your API is now live at:** `http://API_GATEWAY_PUBLIC_IP:8080`

---

## Useful Commands

**Check service status:**
```bash
ssh -i social-media-key.pem ec2-user@IP_ADDRESS
sudo systemctl status auth-service
sudo journalctl -u auth-service -n 50
```

**Restart service:**
```bash
sudo systemctl restart auth-service
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

## Cost Breakdown

- **2 × t3.small EC2**: ~$30/month
- **RDS MySQL (db.t3.micro)**: ~$15/month
- **Redis (cache.t3.micro)**: ~$12/month
- **Data transfer**: ~$3-5/month

**Total: ~$60-62/month**

---

## Clean Up (When Done Testing)

To avoid charges:

```bash
# Stop EC2 instances
aws ec2 stop-instances --instance-ids INSTANCE_ID_1 INSTANCE_ID_2

# Delete RDS
aws rds delete-db-instance --db-instance-identifier social-media-db --skip-final-snapshot

# Delete Redis
aws elasticache delete-cache-cluster --cache-cluster-id social-media-redis

# Terminate EC2 instances (permanent)
aws ec2 terminate-instances --instance-ids INSTANCE_ID_1 INSTANCE_ID_2
```

---

## Next Steps

Once this is working:
1. Fix Social Service Java 25 compatibility issue
2. Deploy Social Service
3. Set up Application Load Balancer
4. Configure HTTPS with SSL certificate
5. Set up CloudWatch monitoring
6. Convert file uploads to S3

**🎉 Congratulations! Your backend is deployed on AWS!**
