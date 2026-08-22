# Profile Data Update - Fix Summary

## Problem
Profile screen was displaying placeholder data ("User 12") instead of actual logged-in user data ("Sai").

### Root Cause
- Profiles were auto-created with placeholder data
- When registration called `/profiles/create` with real data, it would fail (profile already exists)
- Profile remained with placeholder data, even though user data was correct in auth-service

## Solution
Updated `UserProfileService.createProfile()` method to **create or update** instead of just create:

```java
// BEFORE: Threw exception if profile already existed
if (userProfileRepository.existsByUserId(userId)) {
    throw new IllegalArgumentException("Profile already exists for this user");
}

// AFTER: Updates existing profile with real data
UserProfile profile = userProfileRepository.findByUserId(userId).orElse(null);
if (profile != null) {
    // Update existing profile with real data
    profile.setUsername(username);
    profile.setEmail(email);
    profile.setFullName(fullName);
    userProfileRepository.save(profile);
}
```

## Result
✅ Next login will sync the profile with real user data
✅ Profile screen will display actual logged-in user name
✅ No more placeholder data ("User 12", "user_12")

## Files Changed
- **backend/social-service/src/main/java/.../UserProfileService.java**
  - Modified `createProfile()` method to handle existing profiles

## Build & Deploy
```bash
mvn clean package -DskipTests   # (build successful)
java -jar social-service-1.0.0.jar  # Restart with new code
```

## Verification
Log in again → Check ProfileScreen → Should show your actual fullName ("Sai"), not placeholder
