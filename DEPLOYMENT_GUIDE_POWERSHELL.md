# Backend Services Deployment Guide (PowerShell)

This guide provides step-by-step instructions for deploying the social-chat-app backend services to AWS EC2 using PowerShell.

## Prerequisites

- **Java 17** installed locally (for building)
- **Maven** installed locally
- **PowerShell** terminal
- **SSH access** to EC2 instance
- **PEM key file**: `social-media-key.pem`
- **EC2 Instance IP**: `98.92.24.110`
- **EC2 User**: `ec2-user` (Amazon Linux 2023)

## Project Structure

```
backend/
├── auth-service/          # Port 8081
│   ├── src/
│   ├── pom.xml
│   └── build.bat
└── social-service/        # Port 8082
    ├── src/
    ├── pom.xml
    └── build.bat
```

## 1. Build Services Locally

### Option A: Using build.bat (Recommended)

The build.bat scripts already have Java 17 configured.

**Build Auth Service:**
```powershell
cd "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\auth-service"
.\build.bat
```

**Build Social Service:**
```powershell
cd "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\social-service"
.\build.bat
```

### Option B: Using Maven with Java 17 Path

If you need to set Java 17 explicitly:

```powershell
# Set Java 17 path (adjust path to your Java installation)
$env:JAVA_HOME = "C:\Program Files\Java\jdk-17.0.12"
$env:PATH = "C:\Program Files\Java\jdk-17.0.12\bin;" + $env:PATH

# Verify Java version
java -version

# Build auth-service
cd "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\auth-service"
mvn clean package -DskipTests

# Build social-service
cd "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\social-service"
mvn clean package -DskipTests
```

**Output JARs:**
- Auth Service: `backend\auth-service\target\auth-service-1.0.0.jar`
- Social Service: `backend\social-service\target\social-service-1.0.0.jar`

## 2. Upload JARs to EC2

### Upload Auth Service

```powershell
scp -i "C:\Users\gidut\Downloads\social-media-key.pem" `
    "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\auth-service\target\auth-service-1.0.0.jar" `
    ec2-user@98.92.24.110:~
```

### Upload Social Service

```powershell
scp -i "C:\Users\gidut\Downloads\social-media-key.pem" `
    "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\social-service\target\social-service-1.0.0.jar" `
    ec2-user@98.92.24.110:~
```

## 3. Deploy to EC2

### Connect to EC2

```powershell
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110
```

### Deploy Auth Service (Manual Process)

The auth-service runs as a manual Java process.

```bash
# Kill existing auth-service process
pkill -f "auth-service-1.0.0.jar"

# Start auth-service in background
nohup java -jar auth-service-1.0.0.jar --spring.profiles.active=prod > auth-service.log 2>&1 &

# Verify it's running
ps aux | grep auth-service

# Check logs
tail -f auth-service.log

# Test health endpoint
curl http://localhost:8081/actuator/health
```

### Deploy Social Service (Systemd Managed)

The social-service is managed by systemd.

```bash
# Stop the service
sudo systemctl stop social-service

# Copy new JAR to systemd location
sudo cp ~/social-service-1.0.0.jar /opt/social-service/social-service.jar

# Start the service
sudo systemctl start social-service

# Check service status
sudo systemctl status social-service

# View logs
sudo journalctl -u social-service -n 50 --no-pager

# Follow logs in real-time
sudo journalctl -u social-service -f

# Test health endpoint
curl http://localhost:8082/actuator/health
```

## 4. Quick Deployment (Single Command)

### Deploy Auth Service

From your **local PowerShell**:

```powershell
# Build and deploy auth-service
cd "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\auth-service"
.\build.bat
scp -i "C:\Users\gidut\Downloads\social-media-key.pem" "target\auth-service-1.0.0.jar" ec2-user@98.92.24.110:~
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110 "pkill -f 'auth-service-1.0.0.jar'; nohup java -jar auth-service-1.0.0.jar --spring.profiles.active=prod > auth-service.log 2>&1 &"
```

### Deploy Social Service

From your **local PowerShell**:

```powershell
# Build and deploy social-service
cd "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\social-service"
.\build.bat
scp -i "C:\Users\gidut\Downloads\social-media-key.pem" "target\social-service-1.0.0.jar" ec2-user@98.92.24.110:/home/ec2-user/social-service.jar
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110 "sudo systemctl stop social-service && sudo cp /home/ec2-user/social-service.jar /opt/social-service/social-service.jar && sudo systemctl start social-service"
```

## 5. Verify Deployment

### Check Service Health

From **EC2 instance** or **local PowerShell**:

```powershell
# Via SSH from local
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110 "curl -s http://localhost:8082/actuator/health && echo '' && ps aux | grep 'java -jar' | grep -v grep"
```

Expected output:
```json
{"status":"UP"}
```

### Check Running Processes

```bash
# On EC2 instance
ps aux | grep java

# Should show:
# - auth-service-1.0.0.jar (manual process)
# - social-service running via systemd
```

### View Logs

**Auth Service:**
```bash
tail -f ~/auth-service.log
```

**Social Service:**
```bash
sudo journalctl -u social-service -f
```

## 6. Service Management Commands

### Auth Service (Manual Process)

```bash
# Start
nohup java -jar auth-service-1.0.0.jar --spring.profiles.active=prod > auth-service.log 2>&1 &

# Stop
pkill -f "auth-service-1.0.0.jar"

# Restart
pkill -f "auth-service-1.0.0.jar" && sleep 2 && nohup java -jar auth-service-1.0.0.jar --spring.profiles.active=prod > auth-service.log 2>&1 &

# View logs
tail -f auth-service.log

# Check process
ps aux | grep auth-service
```

### Social Service (Systemd)

```bash
# Start
sudo systemctl start social-service

# Stop
sudo systemctl stop social-service

# Restart
sudo systemctl restart social-service

# Status
sudo systemctl status social-service

# Enable auto-start on boot
sudo systemctl enable social-service

# View logs
sudo journalctl -u social-service -n 100

# Follow logs
sudo journalctl -u social-service -f
```

## 7. Troubleshooting

### Service Won't Start

**Check Java version on EC2:**
```bash
java -version
# Should be Java 17
```

**Check JAR file permissions:**
```bash
ls -lh *.jar
chmod +x *.jar  # If needed
```

**Check port availability:**
```bash
# Check if ports are in use
netstat -tlnp | grep -E '8081|8082'

# Kill process on specific port if needed
sudo kill $(sudo lsof -t -i:8081)
sudo kill $(sudo lsof -t -i:8082)
```

### Build Failures

**Verify Java 17 is being used:**
```powershell
java -version
mvn -version
```

**Clean Maven cache:**
```powershell
mvn clean
rm -rf target/
mvn package -DskipTests
```

### Connection Issues

**Test EC2 connectivity:**
```powershell
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110 "echo 'Connection successful'"
```

**Verify security group allows:**
- Port 22 (SSH)
- Ports 8081, 8082 (if external access needed)

### Health Endpoint Returns 403

Auth-service health endpoint may return 403 if it requires authentication. This is normal. The service is still running if you see the 403 response.

For social-service, the health endpoint should return `{"status":"UP"}`.

## 8. Environment Variables

Both services use environment variables from:

**Auth Service:**
- Home directory: `~/auth-service.env` (if exists)
- Passed via Spring profile: `--spring.profiles.active=prod`

**Social Service:**
- Systemd environment file: `/opt/social-service/env.txt`
- Configured in: `/etc/systemd/system/social-service.service`

### View Social Service Environment

```bash
cat /opt/social-service/env.txt
```

## 9. Systemd Service File

**Location:** `/etc/systemd/system/social-service.service`

```ini
[Unit]
Description=Social Service
After=network.target

[Service]
User=ec2-user
WorkingDirectory=/opt/social-service
ExecStart=/usr/bin/java -jar /opt/social-service/social-service.jar --spring.profiles.active=prod
EnvironmentFile=/opt/social-service/env.txt
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Reload Systemd After Changes

```bash
sudo systemctl daemon-reload
sudo systemctl restart social-service
```

## 10. Port Configuration

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| auth-service | 8081 | HTTP | Authentication endpoints |
| social-service | 8082 | HTTP | Social features, WebSocket |

### Verify Ports

```bash
# Check which process is using each port
sudo netstat -tlnp | grep 8081
sudo netstat -tlnp | grep 8082
```

## 11. Complete Deployment Checklist

- [ ] Build auth-service with Java 17
- [ ] Build social-service with Java 17
- [ ] Upload auth-service JAR to EC2
- [ ] Upload social-service JAR to EC2
- [ ] Stop existing auth-service process
- [ ] Start new auth-service process
- [ ] Stop social-service systemd service
- [ ] Copy new social-service JAR to /opt/social-service/
- [ ] Start social-service systemd service
- [ ] Verify auth-service health (port 8081)
- [ ] Verify social-service health (port 8082)
- [ ] Test application functionality

## 12. Quick Reference Commands

### Local PowerShell

```powershell
# Build both services
cd "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\auth-service"
.\build.bat
cd "..\social-service"
.\build.bat

# Upload both services
scp -i "C:\Users\gidut\Downloads\social-media-key.pem" "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\auth-service\target\auth-service-1.0.0.jar" ec2-user@98.92.24.110:~
scp -i "C:\Users\gidut\Downloads\social-media-key.pem" "C:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\social-service\target\social-service-1.0.0.jar" ec2-user@98.92.24.110:~

# Deploy both services
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110
```

### On EC2

```bash
# Deploy auth-service
pkill -f "auth-service-1.0.0.jar"
nohup java -jar auth-service-1.0.0.jar --spring.profiles.active=prod > auth-service.log 2>&1 &

# Deploy social-service
sudo systemctl stop social-service
sudo cp social-service-1.0.0.jar /opt/social-service/social-service.jar
sudo systemctl start social-service

# Verify
curl http://localhost:8082/actuator/health
ps aux | grep java
```

---

## Support

For issues or questions, check the logs:
- Auth Service: `~/auth-service.log`
- Social Service: `sudo journalctl -u social-service -n 100`
