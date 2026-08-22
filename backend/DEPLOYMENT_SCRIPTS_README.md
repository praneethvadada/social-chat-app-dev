# Backend Deployment Scripts

Quick reference for deploying and managing services on EC2 instance **98.90.116.96**

## 📦 Deployment Scripts

### **Full Redeployment**
Rebuilds all services and deploys to EC2
```bash
redeploy-all.bat
```
- ✅ Builds JAR files
- ✅ Uploads to EC2
- ✅ Configures environment
- ✅ Starts services
- ✅ Verifies deployment

**Use this when:** Code changes need to be deployed

---

### **Quick Restart**
Restarts services without rebuilding
```bash
restart-services-only.bat
```
- ✅ Restart Social Service
- ✅ Restart API Gateway
- ✅ Check status

**Use this when:** Services need to be restarted (config changes, troubleshooting)

---

## 📊 Monitoring Scripts

### **View Logs**
```bash
view-logs.bat
```
Interactive menu to view:
1. Social Service logs
2. API Gateway logs
3. Both services (last 50 lines)
4. Social Service (live tail)
5. API Gateway (live tail)

**Use this when:** Debugging issues, monitoring service behavior

---

### **Test Services**
```bash
test-services.bat
```
- ✅ Test Social Service health
- ✅ Test API Gateway
- ✅ Test WebSocket endpoint
- ✅ Test port connectivity

**Use this when:** Verifying deployment, troubleshooting connectivity

---

## 🔧 Manual Deployment (Advanced)

If you need more control, see [REDEPLOY_COMMANDS.md](REDEPLOY_COMMANDS.md) for individual SCP/SSH commands.

### Individual Service Deployment
```bash
# Social Service only
deploy-social-service-final.bat

# API Gateway only
deploy-api-gateway.bat
```

---

## 📡 Service Endpoints

After deployment, services are available at:

| Service | URL | Description |
|---------|-----|-------------|
| **API Gateway** | `http://98.90.116.96:8080/api` | Main API endpoint |
| **Social Service** | `http://98.90.116.96:8082` | Direct access |
| **WebSocket** | `http://98.90.116.96:8082/ws` | Real-time chat/calls |
| **Swagger UI** | `http://98.90.116.96:8080/swagger-ui.html` | API documentation |
| **Health Check** | `http://98.90.116.96:8082/actuator/health` | Service health |

---

## 🚀 Quick Start

1. **First-time deployment:**
   ```bash
   redeploy-all.bat
   ```

2. **After code changes:**
   ```bash
   redeploy-all.bat
   ```

3. **Just restart services:**
   ```bash
   restart-services-only.bat
   ```

4. **Check if working:**
   ```bash
   test-services.bat
   ```

5. **View errors:**
   ```bash
   view-logs.bat
   ```

---

## 🔍 Troubleshooting

### Service won't start?
```bash
view-logs.bat
# Choose option 1 or 2 to see error messages
```

### Connection timeout?
1. Check security group allows ports 8080, 8082
2. Run: `test-services.bat`

### Need to check database connection?
```bash
view-logs.bat
# Look for "HikariPool" or "datasource" messages
```

### Services running but not responding?
```bash
restart-services-only.bat
```

---

## 📝 Manual SSH Access

```bash
ssh -i C:\Users\gidut\Downloads\social-media-key.pem ec2-user@98.90.116.96

# Once logged in:
sudo systemctl status social-service
sudo systemctl status api-gateway
sudo journalctl -u social-service -f
```

---

## 🔐 Environment Variables

Services use these configurations:
- **Database:** social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com
- **Redis:** social-media-redis.0k0afe.0001.use1.cache.amazonaws.com
- **S3 Bucket:** social-media-gidut-54513
- **Region:** us-east-1

All configured automatically by deployment scripts.
