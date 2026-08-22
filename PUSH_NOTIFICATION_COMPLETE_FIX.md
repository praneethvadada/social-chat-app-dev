# Push Notification Setup - Complete Steps

## ROOT CAUSE IDENTIFIED

The FCM token is **NOT being saved to the database** because:
1. The Flutter app hasn't done a **clean rebuild** after code changes
2. The endpoint was updated from `/users/fcm-token` → `/users/{userId}/fcm-token`
3. Hot reload doesn't always pick up all Dart changes

---

## FIX: Complete Clean Rebuild

### Step 1: Stop Everything
```bash
# Stop Flutter app (if running)
# Press Ctrl+C in Flutter terminal

# Stop backend (if running)
# Press Ctrl+C in backend terminal
```

### Step 2: Clean Flutter
```bash
cd "C:\Users\VAMSI KRISHNA\Desktop\PROJECTS\INTERNSHIP\Mobile App Development\social-media-mobile"
flutter clean
flutter pub get
```

### Step 3: Rebuild and Run
```bash
flutter run
```

**WAIT FOR FULL BUILD (not hot reload)** - you'll see:
```
Running Gradle task 'assembleDebug'...
...
✅ Built build/app/outputs/flutter-app-debug.apk
```

### Step 4: Verify Logs
Once app starts, look for these exact logs:
```
[FCM] 🔑 Getting FCM token...
[FCM] 🔑 FCM Token: exxx...xxxx
[API] 🔄 Saving FCM token to backend for user 3...
[API] ✅ FCM token saved successfully
```

### Step 5: Verify in Database
```bash
mysql -u root -p

USE auth_db;
SELECT user_id, username, fcm_token FROM users WHERE user_id IN (2, 3);
```

Expected result:
```
| user_id | username | fcm_token        |
|---------|----------|------------------|
| 2       | sai      | exxx...xxxx      |
| 3       | vamsi    | fyyy...yyyy      |
```

**If fcm_token is NULL → repeat steps 1-3**

---

## Once FCM Token is Saved

### Step 6: Test Follow Notification
1. Login as User 2 (sai)
2. Search for User 3 (vamsi)
3. Click "Follow" button
4. **Check backend logs for:**
   ```
   [FCM] 👤 Follow notification sent to user 3
   ```
   (NOT "No FCM token for user 3")
5. **Check User 3's device for push notification**

---

## If Still Not Working

### Check 1: Firebase Admin SDK Initialized?
Look at backend startup logs:
```
✅ Firebase Admin SDK initialized successfully
```

If NOT:
```
⚠️ FIREBASE_KEY_PATH environment variable not set
```

**Fix:** Set environment variable:
```bash
# Windows CMD
SET FIREBASE_KEY_PATH=C:\path\to\serviceAccountKey.json

# Then restart backend
.\start-all-services.bat
```

### Check 2: Firebase Service Account Key Exists?
```bash
# Find the key file
dir C:\path\to\serviceAccountKey.json
```

If NOT found:
1. Go to Firebase Console
2. Project → Settings → Service Accounts
3. Click "Generate New Private Key"
4. Download and save as `serviceAccountKey.json`

### Check 3: All Services Running?
```bash
# Check if auth-service is accessible
curl http://localhost:8081/health

# Check if social-service is accessible
curl http://localhost:8082/health

# Check if API gateway is accessible
curl http://localhost:8080/health
```

Expected: All return `200 OK`

---

## Complete Notification Flow When Working

```
User 2 clicks Follow on User 3:
  ✅ POST /followers/3
     ↓
  ✅ Notification saved to DB
  ✅ Sent via WebSocket (in-app)
     ↓
  ✅ FCMService.onUserFollowed(3, 2) triggered
     ↓
  ✅ GET /users/2/username → "sai" (200 OK)
  ✅ GET /users/3/fcm-token → "exxx...xxxx" (200 OK with token)
     ↓
  ✅ Firebase Admin SDK sends push notification
     ↓
  ✅ Device receives push (even if app closed)
  ✅ Notification appears on device
  ✅ User sees: "👤 sai started following you"
```

---

## Commands Quick Reference

```bash
# Full clean rebuild
cd "C:\Users\VAMSI KRISHNA\Desktop\PROJECTS\INTERNSHIP\Mobile App Development\social-media-mobile"
flutter clean && flutter pub get && flutter run

# Check Flutter logs
flutter logs | findstr "FCM"

# Check database
mysql -u root -p -e "USE auth_db; SELECT user_id, fcm_token FROM users WHERE fcm_token IS NOT NULL;"

# Check backend services
curl http://localhost:8080/health
curl http://localhost:8081/health
curl http://localhost:8082/health

# Restart backend
cd backend
.\start-all-services.bat
```

---

## Next Steps

1. **Do the complete clean rebuild** (most important!)
2. **Verify FCM token is in database**
3. **Test follow notification flow**
4. **If still not working, check Firebase Admin SDK initialization**

Document what you see at each step and share the logs.
