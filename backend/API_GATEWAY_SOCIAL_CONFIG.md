# API Gateway Configuration for Social Service

## Update Required

After deploying social-service, you need to update the API Gateway to route requests to it.

### Option 1: Update Environment Variables

Add to `/home/ubuntu/api-gateway.env`:
```bash
SOCIAL_SERVICE_URL=http://SOCIAL_SERVICE_EC2_IP:8082
```

Then restart API Gateway:
```bash
sudo systemctl restart api-gateway
```

### Option 2: If Using Same EC2 Instance

If social-service runs on the same EC2 as API Gateway:
```bash
SOCIAL_SERVICE_URL=http://localhost:8082
```

### Option 3: If Using Separate EC2 Instances

Update with the private IP of social-service EC2:
```bash
SOCIAL_SERVICE_URL=http://172.31.X.X:8082  # Use private IP within VPC
```

## Verification

Test routing through API Gateway:
```bash
# Health check through gateway
curl http://API_GATEWAY_IP:4000/social/actuator/health

# File upload through gateway
curl -X POST http://API_GATEWAY_IP:4000/social/files/upload \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -F "file=@test.jpg"
```

## Routes Configured

The API Gateway routes all `/social/**` requests to social-service:
- `/social/files/**` → File upload/download/delete
- `/social/posts/**` → Posts management
- `/social/profiles/**` → User profiles
- `/social/followers/**` → Follower system
- `/social/chat/**` → Chat functionality

## Notes

- All requests to social-service go through API Gateway
- Authentication is handled by API Gateway before forwarding to social-service
- The `userId` is extracted from JWT and added to request attributes
- Social-service receives authenticated requests with userId in attributes
