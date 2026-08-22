package com.example.social_chat_app;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;
import androidx.core.content.ContextCompat;
import androidx.core.app.NotificationCompat;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

import android.content.Context;
import android.os.PowerManager;
import java.util.Locale;
import java.util.Map;

public class CallFirebaseMessagingService extends FirebaseMessagingService {
    private static final String TAG = "[CallFCMService]";

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        super.onMessageReceived(remoteMessage);
        
        // ⚡ Acquire WakeLock immediately to keep CPU running
        PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
        PowerManager.WakeLock wakeLock = null;
        if (powerManager != null) {
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "CallFCMService:WakeLock"
            );
            wakeLock.acquire(10000); // Hold for 10 seconds max
            System.out.println(TAG + " ⚡ WakeLock acquired for FCM processing");
        }

        try {
            Map<String, String> payload = remoteMessage.getData();
            if (payload == null || payload.isEmpty()) {
                System.out.println(TAG + " ⚠️ Received FCM message with no data");
                return;
            }
    
            String type = payload.get("type");
            if (type == null) {
                System.out.println(TAG + " ⚠️ Missing type field in data payload");
                return;
            }
    
            String typeUpper = type.toUpperCase();
            System.out.println(TAG + " ✅ Received call-related FCM data: " + typeUpper);
    
            switch (typeUpper) {
                case "CALL_INVITE":
                    startCallNotification(payload);
                    break;
                case "CALL_END":
                case "CALL_REJECT":
                    stopCallNotification();
                    break;
                default:
                    // Non-call notifications are handled by Flutter FirebaseMessagingService
                    // to avoid duplicate notifications from parallel native + Flutter handlers.
                    System.out.println(TAG + " ℹ️ Non-call message ignored by native call service (type=" + type + ")");
            }
        } finally {
            if (wakeLock != null && wakeLock.isHeld()) {
                wakeLock.release();
                System.out.println(TAG + " ⚡ WakeLock released");
            }
        }
    }

    private void showStandardNotification(RemoteMessage remoteMessage) {
        try {
            Map<String, String> payload = remoteMessage.getData();
            String type = payload.getOrDefault("type", "default");
            String channelId = resolveChannelId(type);
            createChannelIfNeeded(channelId);

            String title = remoteMessage.getNotification() != null
                    ? remoteMessage.getNotification().getTitle()
                    : payload.getOrDefault("title", "Notification");
            String body = remoteMessage.getNotification() != null
                    ? remoteMessage.getNotification().getBody()
                    : payload.getOrDefault("body", payload.getOrDefault("message", "You have a new notification"));

            Intent openIntent = new Intent(this, MainActivity.class);
            openIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            openIntent.putExtra("notificationType", type);
            openIntent.putExtra("senderId", payload.getOrDefault("senderId", "0"));
            openIntent.putExtra("postId", payload.getOrDefault("postId", "0"));

            PendingIntent openPendingIntent = PendingIntent.getActivity(
                    this,
                    (int) (System.currentTimeMillis() % 100000),
                    openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
            );

            NotificationCompat.Builder builder = new NotificationCompat.Builder(this, channelId)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle(title != null ? title : "Notification")
                    .setContentText(body != null ? body : "")
                    .setAutoCancel(true)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setContentIntent(openPendingIntent);

            NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (notificationManager != null) {
                int notificationId = (int) (System.currentTimeMillis() % 1000000);
                notificationManager.notify(notificationId, builder.build());
                System.out.println(TAG + " ✅ Standard notification shown (id=" + notificationId + ", channel=" + channelId + ")");
            }
        } catch (Exception e) {
            System.out.println(TAG + " ❌ Failed to show standard notification: " + e.getMessage());
        }
    }

    private String resolveChannelId(String type) {
        String normalized = type == null ? "" : type.toLowerCase(Locale.ROOT);
        if (normalized.contains("message") || normalized.contains("chat")) {
            return "chat_channel";
        }
        if (normalized.contains("like") || normalized.contains("comment") || normalized.contains("follow") || normalized.contains("mention") || normalized.contains("reply")) {
            return "interaction_channel";
        }
        return "default_channel";
    }

    private void createChannelIfNeeded(String channelId) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;

        NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (notificationManager == null) return;
        if (notificationManager.getNotificationChannel(channelId) != null) return;

        String channelName;
        switch (channelId) {
            case "chat_channel":
                channelName = "Chat Messages";
                break;
            case "interaction_channel":
                channelName = "Interactions";
                break;
            default:
                channelName = "Default Notifications";
        }

        NotificationChannel channel = new NotificationChannel(
                channelId,
                channelName,
                NotificationManager.IMPORTANCE_HIGH
        );
        notificationManager.createNotificationChannel(channel);
    }

    private void startCallNotification(Map<String, String> payload) {
        Intent intent = new Intent(this, CallNotificationService.class);
        intent.setAction("START_CALL");
        intent.putExtra("callerId", payload.get("callerId"));
        intent.putExtra("callerName", payload.get("callerName"));
        intent.putExtra("channelName", payload.get("channelName"));
        intent.putExtra("isVideo", Boolean.parseBoolean(payload.getOrDefault("isVideo", "false")));
        intent.putExtra("playRingtone", true);
        ContextCompat.startForegroundService(this, intent);
        System.out.println(TAG + " ✅ START_CALL requested via foreground service");
    }

    private void stopCallNotification() {
        Intent stopIntent = new Intent(this, CallNotificationService.class);
        stopIntent.setAction("STOP_CALL");
        ContextCompat.startForegroundService(this, stopIntent);
        System.out.println(TAG + " ✅ STOP_CALL requested");
    }
}
