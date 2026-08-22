# RDS Connection Timeout Fix

## Error
```
ERROR 2003 (HY000): Can't connect to MySQL server on 'social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306' (10060)
```

## Cause
**Your RDS security group doesn't allow connections from your local IP address.**

## Solution: Update RDS Security Group

### Option 1: AWS Console (Recommended)

1. **Go to AWS RDS Console**
   - https://console.aws.amazon.com/rds/

2. **Find Your Database**
   - Click on `social-media-db`

3. **Go to Security Group**
   - Under "Connectivity & security" tab
   - Click on the **VPC security group** link (e.g., `sg-xxxxxxxxx`)

4. **Edit Inbound Rules**
   - Click "Edit inbound rules"
   - Click "Add rule"
   - Set:
     - **Type**: MySQL/Aurora
     - **Protocol**: TCP
     - **Port**: 3306
     - **Source**: My IP (automatically detects your IP)
     - **Description**: My local development machine
   - Click "Save rules"

5. **Wait 30 seconds** and try again

### Option 2: AWS CLI

```bash
# Get your current IP
curl https://checkip.amazonaws.com

# Add your IP to security group (replace with your values)
aws ec2 authorize-security-group-ingress \
    --group-id sg-YOUR_SECURITY_GROUP_ID \
    --protocol tcp \
    --port 3306 \
    --cidr YOUR_IP_ADDRESS/32
```

## Alternative: Connect from EC2 (Always Works)

Since EC2 is in the same VPC, it can always connect to RDS:

### Method 1: SSH Tunnel
```bash
# Create SSH tunnel from local to RDS via EC2
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" \
    -L 3307:social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306 \
    ec2-user@98.92.24.110 -N

# In another terminal, connect to localhost:3307
mysql -h 127.0.0.1 -P 3307 -u admin -p

# Or apply schema
mysql -h 127.0.0.1 -P 3307 -u admin -pSecurePass123! < complete_schema_v2.sql
```

### Method 2: Upload Schema and Run on EC2

```bash
# 1. Upload schema file to EC2
scp -i "C:\Users\gidut\Downloads\social-media-key.pem" \
    complete_schema_v2.sql \
    ec2-user@98.92.24.110:/tmp/

# 2. SSH to EC2 and run
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110

# 3. Apply schema from EC2
mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com \
      -u admin -pSecurePass123! < /tmp/complete_schema_v2.sql

# 4. Verify
mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com \
      -u admin -pSecurePass123! \
      -e "USE auth_db; SELECT * FROM schema_version; SHOW TABLES;"
```

### Method 3: MySQL Workbench with SSH Tunnel

1. Open **MySQL Workbench**
2. Create new connection:
   - **Connection Method**: Standard TCP/IP over SSH
   - **SSH Hostname**: 98.92.24.110
   - **SSH Username**: ec2-user
   - **SSH Key File**: C:\Users\gidut\Downloads\social-media-key.pem
   - **MySQL Hostname**: social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com
   - **MySQL Port**: 3306
   - **Username**: admin
   - **Password**: SecurePass123!
3. Test connection
4. Run your SQL scripts

## Quick Commands

### Test RDS Connection
```bash
# From local (will timeout if security group not configured)
mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com \
      -u admin -pSecurePass123! \
      -e "SELECT 1;"

# From EC2 (should always work)
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" \
    ec2-user@98.92.24.110 \
    "mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com \
           -u admin -pSecurePass123! \
           -e 'SELECT 1;'"
```

### Apply New Schema from EC2
```bash
# Step 1: Upload schema
scp -i "C:\Users\gidut\Downloads\social-media-key.pem" \
    "c:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend\complete_schema_v2.sql" \
    ec2-user@98.92.24.110:/tmp/schema.sql

# Step 2: Apply schema
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" \
    ec2-user@98.92.24.110 \
    "mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -pSecurePass123! < /tmp/schema.sql"

# Step 3: Verify
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" \
    ec2-user@98.92.24.110 \
    "mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -pSecurePass123! -e 'USE auth_db; SELECT version FROM schema_version;'"
```

### Check Current Database
```bash
ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" \
    ec2-user@98.92.24.110 \
    "mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -pSecurePass123! -e 'SHOW DATABASES;'"
```

## Important Note About Database Name

Your current backend is configured to use `social_app` database:

```properties
# backend/social-service.env
SPRING_DATASOURCE_URL=...3306/social_app?createDatabaseIfNotExist=true...
```

But the new schema creates `auth_db`. You have two options:

### Option A: Keep Using social_app (Recommended)
Edit `complete_schema_v2.sql` lines 11-15:

```sql
-- Change from:
DROP DATABASE IF EXISTS auth_db;
CREATE DATABASE auth_db 

-- To:
DROP DATABASE IF EXISTS social_app;
CREATE DATABASE social_app 

-- And change:
USE auth_db;

-- To:
USE social_app;
```

Then no backend config changes needed.

### Option B: Use auth_db
Keep schema as-is, update backend configs:

```bash
# Edit social-service.env
SPRING_DATASOURCE_URL=jdbc:mysql://social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306/auth_db?createDatabaseIfNotExist=true&useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC

# Edit auth-service.env (if exists)
SPRING_DATASOURCE_URL=jdbc:mysql://social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com:3306/auth_db?createDatabaseIfNotExist=true&useSSL=false&allowPublicKeyRetrieval=true&serverTimezone=UTC
```

Then redeploy services.

## Summary

**Immediate Solution**: Apply schema from EC2 since it can connect to RDS:

```bash
cd "c:\Users\gidut\OneDrive\html files\Projects\social-chat-app\backend"

scp -i "C:\Users\gidut\Downloads\social-media-key.pem" complete_schema_v2.sql ec2-user@98.92.24.110:/tmp/

ssh -i "C:\Users\gidut\Downloads\social-media-key.pem" ec2-user@98.92.24.110 "mysql -h social-media-db.ca30yaou8j00.us-east-1.rds.amazonaws.com -u admin -pSecurePass123! < /tmp/complete_schema_v2.sql && echo 'Schema applied successfully!'"
```

**Long-term Solution**: Update RDS security group to allow your local IP for development.
