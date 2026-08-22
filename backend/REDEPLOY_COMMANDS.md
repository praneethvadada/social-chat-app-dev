# Complete Redeployment Commands for 98.90.116.96

## Prerequisites
```bash
cd "c:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend"
set KEY=C:\Users\gidut\Downloads\social-media-key.pem
set IP=98.90.116.96
```

## Step 1: Build All Services
```bash
mvn clean package -DskipTests
```

## Step 2: Deploy Social Service

### Upload JAR
```bash
scp -i %KEY% -o StrictHostKeyChecking=no social-service\target\social-service-1.0.0.jar ec2-user@%IP%:~/social-service.jar
```

### Create and Upload Environment File
```bash
echo SPRING_DATASOURCE_URL=jdbc:mysql://social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306/auth_db?createDatabaseIfNotExist=true^&useSSL=false^&allowPublicKeyRetrieval=true^&serverTimezone=UTC > social-env.txt
echo SPRING_DATASOURCE_USERNAME=admin >> social-env.txt
echo SPRING_DATASOURCE_PASSWORD=SecurePass123! >> social-env.txt
echo SPRING_DATA_REDIS_HOST=social-media-redis.0k0afe.0001.use1.cache.amazonaws.com >> social-env.txt
echo SPRING_DATA_REDIS_PORT=6379 >> social-env.txt
echo JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 >> social-env.txt
echo JWT_EXPIRATION=86400000 >> social-env.txt
echo PORT=8082 >> social-env.txt
echo SPRING_PROFILES_ACTIVE=prod >> social-env.txt
echo AWS_S3_BUCKET=social-media-gidut-54513 >> social-env.txt
echo AWS_REGION=us-east-1 >> social-env.txt
echo AGORA_APP_ID=b7a780435e494cdf8c4d6e4bc59be7ab >> social-env.txt
echo AGORA_APP_CERT=7c3359b7e6214ec6a5bcca098d47ee77 >> social-env.txt

scp -i %KEY% -o StrictHostKeyChecking=no social-env.txt ec2-user@%IP%:~/
del social-env.txt
```

### Upload Service File
```bash
scp -i %KEY% -o StrictHostKeyChecking=no social-service.service ec2-user@%IP%:~/
```

### Setup and Start Social Service
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo yum update -y && sudo yum install -y java-17-amazon-corretto-headless && sudo mkdir -p /opt/social-service && sudo mv ~/social-service.jar /opt/social-service/ && sudo mv ~/social-env.txt /opt/social-service/env.txt && sudo mv ~/social-service.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable social-service && sudo systemctl restart social-service"
```

### Check Social Service Status
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo systemctl status social-service --no-pager && echo '--- Logs ---' && sudo journalctl -u social-service -n 50 --no-pager"
```

## Step 3: Deploy API Gateway

### Upload JAR
```bash
scp -i %KEY% -o StrictHostKeyChecking=no api-gateway\target\api-gateway-1.0.0.jar ec2-user@%IP%:~/api-gateway.jar
```

### Create and Upload Environment File
```bash
echo AUTH_SERVICE_URL=http://172.31.74.81:8081 > gateway-env.txt
echo SOCIAL_SERVICE_URL=http://172.31.74.81:8082 >> gateway-env.txt
echo JWT_SECRET=5367566B59703373367639792F423F4528482B4D6251655468576D5A71347437 >> gateway-env.txt
echo PORT=8080 >> gateway-env.txt
echo SPRING_PROFILES_ACTIVE=prod >> gateway-env.txt

scp -i %KEY% -o StrictHostKeyChecking=no gateway-env.txt ec2-user@%IP%:~/
del gateway-env.txt
```

### Upload Service File
```bash
scp -i %KEY% -o StrictHostKeyChecking=no api-gateway.service ec2-user@%IP%:~/
```

### Setup and Start API Gateway
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo mkdir -p /opt/api-gateway && sudo mv ~/api-gateway.jar /opt/api-gateway/ && sudo mv ~/gateway-env.txt /opt/api-gateway/env.txt && sudo mv ~/api-gateway.service /etc/systemd/system/ && sudo systemctl daemon-reload && sudo systemctl enable api-gateway && sudo systemctl restart api-gateway"
```

### Check API Gateway Status
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo systemctl status api-gateway --no-pager && echo '--- Logs ---' && sudo journalctl -u api-gateway -n 50 --no-pager"
```

## Step 4: Verify Deployment

### Test Social Service
```bash
curl http://98.90.116.96:8082/actuator/health
```

### Test API Gateway
```bash
curl http://98.90.116.96:8080/api/social/posts/explore
```

### Test WebSocket
```bash
curl http://98.90.116.96:8082/ws
```

## Step 5: Monitor Logs (Optional)

### Social Service Logs
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo journalctl -u social-service -f"
```

### API Gateway Logs
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo journalctl -u api-gateway -f"
```

### Both Services Status
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo systemctl status social-service api-gateway --no-pager"
```

## Quick Restart Commands

### Restart Social Service
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo systemctl restart social-service"
```

### Restart API Gateway
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo systemctl restart api-gateway"
```

### Restart Both
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo systemctl restart social-service api-gateway"
```

## Troubleshooting

### Check if ports are listening
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo netstat -tlnp | grep -E '8080|8082|8081'"
```

### Check Java processes
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "ps aux | grep java"
```

### View full service logs
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo journalctl -u social-service --no-pager | tail -100"
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo journalctl -u api-gateway --no-pager | tail -100"
```

### Stop services
```bash
ssh -i %KEY% -o StrictHostKeyChecking=no ec2-user@%IP% "sudo systemctl stop social-service api-gateway"
```

## Security Group Check
Make sure EC2 security group allows:
- Port 8080 (API Gateway) - from 0.0.0.0/0
- Port 8082 (Social Service WebSocket) - from 0.0.0.0/0
- Port 22 (SSH) - from your IP
