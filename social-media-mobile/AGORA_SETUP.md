# Agora Integration Guide

This document explains the minimal steps to get Agora working with this Flutter app.

1. Create an Agora account and a project to obtain an App ID.
2. Implement a backend endpoint that creates temporary tokens (recommended) for channels. The Flutter client expects a GET to:

   `GET {ApiConfig.agoraTokenEndpoint}?channel=<channel>&uid=<uid>`

   and a JSON response like:

   ```json
   { "appId": "<APP_ID>", "token": "<TOKEN>" }
   ```

3. Update `lib/src/config/api_config.dart` if your backend host or port differs.
4. Add platform permissions:
   - Android: `RECORD_AUDIO`, `CAMERA` in `AndroidManifest.xml`.
   - iOS: `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` in `Info.plist`.
5. Run:

```bash
cd "social-media-mobile"
flutter pub get
flutter run
```

6. Trigger a call by navigating to `CallScreen`:

```dart
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => CallScreen(channelName: 'channel123', otherUserId: 42, isVideo: true),
));
```

7. Backend responsibilities:
- Issue short-lived Agora tokens server-side (do not embed long-lived secrets in the app).
- Provide `ApiConfig.callLogEndpoint` to accept call logs for analytics/records.

Notes:
- The app uses `agora_rtc_engine` and `permission_handler` packages added to `pubspec.yaml`.
- `lib/src/services/agora_service.dart` wraps engine init/join/leave.
- `lib/src/services/call_api.dart` shows how the client requests tokens and posts logs.
- Customize UI and permission flows as needed for production.
