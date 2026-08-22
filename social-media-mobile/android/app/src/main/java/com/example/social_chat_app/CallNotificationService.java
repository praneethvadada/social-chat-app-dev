package com.example.social_chat_app;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.media.AudioAttributes;
import android.media.AudioManager;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.content.pm.ServiceInfo;
import android.app.ForegroundServiceStartNotAllowedException;

import androidx.core.app.NotificationCompat;

/**
 * Foreground Service for WhatsApp-style incoming call notifications
 * Keeps call active even if app is backgrounded with persistent ringtone
 */
public class CallNotificationService extends Service {
    private static final String CHANNEL_ID = "call_channel_critical"; // Changed to force update
    private static final String BACKGROUND_CHANNEL_ID = "background_call_channel";
    private static final int NOTIFICATION_ID = 9999;
    private PowerManager.WakeLock wakeLock;
    // private Ringtone ringtone; // Removed in favor of MediaPlayer
    private static final int BACKGROUND_NOTIFICATION_ID = 10001;
    private static final String TAG = "[CallNotificationService]";

    // ... (fields remain same)

    // ... (onStartCommand, startForegroundNotification, showBackgroundCallNotification methods remain same until createCallChannelIfNeeded)
    // Note: I will only replace the methods I need to change or the whole class if easier.
    // Since I need to change CHANNEL_ID at top AND methods at bottom, I'll use multiple chunks or careful selection.
    // The instructions say "replacing a single contiguous block".
    // I can't change CHANNEL_ID at top and methods at bottom in one tool call if they are far apart.
    // Wait, the tool allows "ReplacementChunks" for multi_replace_file_content!
    // But I am using "replace_file_content" which is single block.
    // I should use "multi_replace_file_content" if possible? 
    // Agent instructions say: "3. To edit multiple, non-adjacent lines... make a single call to the multi_replace_file_content tool."
    // Yes! I will use multi_replace_file_content.

    // I will construct the multi_replace_file_content in the tool call directly.
    // This text block is just thinking. I don't need to put code here.

    private String callerId = "Unknown";
    private String channelName = "";
    private boolean isVideo = false;
    private boolean shouldPlayRingtone = true;

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null) {
            String action = intent.getAction();
            System.out.println(TAG + " onStartCommand: action=" + action);

            if ("START_CALL".equals(action)) {
                // Extract call details from intent
                callerId = intent.getStringExtra("callerId");
                String callerName = intent.getStringExtra("callerName");
                channelName = intent.getStringExtra("channelName");
                isVideo = intent.getBooleanExtra("isVideo", false);
                shouldPlayRingtone = intent.getBooleanExtra("playRingtone", true);

                System.out.println(TAG + " START_CALL: callerId=" + callerId + ", name=" + callerName + ", video=" + isVideo);

                // Start foreground with ongoing notification and ringtone
                startForegroundNotification(callerName);

            } else if ("STOP_CALL".equals(action)) {
                System.out.println(TAG + " STOP_CALL received - stopping service");
                removeBackgroundCallNotification();  // 🔴 BUG FIX #2: Remove background notification when call ends
                stopRingtone();
                stopForeground(true);
                stopSelf();
            } else if ("SHOW_BACKGROUND_NOTIFICATION".equals(action)) {
                // 🔴 BUG FIX #2: Show background "Call Running" notification
                String callerName = intent.getStringExtra("callerName");
                channelName = intent.getStringExtra("channelName");
                System.out.println(TAG + " SHOW_BACKGROUND_NOTIFICATION: " + callerName);
                showBackgroundCallNotification(callerName);
            } else if ("HIDE_BACKGROUND_NOTIFICATION".equals(action)) {
                // 🔴 BUG FIX #2: Hide background notification
                System.out.println(TAG + " HIDE_BACKGROUND_NOTIFICATION");
                removeBackgroundCallNotification();
            }
        }

        // Keep service running even if process is killed
        return START_STICKY;
    }

    private void startForegroundNotification(String callerName) {
        System.out.println(TAG + " startForegroundNotification: callerName=" + callerName);

        // Acquire wake lock to wake screen
        try {
            PowerManager powerManager = (PowerManager) getSystemService(Context.POWER_SERVICE);
            if (wakeLock == null && powerManager != null) {
                wakeLock = powerManager.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK |
                    PowerManager.ACQUIRE_CAUSES_WAKEUP |
                    PowerManager.ON_AFTER_RELEASE,
                    "CallNotification:WakeLock"
                );
                wakeLock.acquire(60000); // 60 seconds
                System.out.println(TAG + " ✅ Wake lock acquired - screen will wake up");
            }
        } catch (Exception e) {
            System.out.println(TAG + " ⚠️ Wake lock error: " + e.getMessage());
        }

        // Create call notification channel if needed
        createCallChannelIfNeeded();

        // Play ringtone explicitly for reliable audio feedback
        if (shouldPlayRingtone) {
            playRingtone();
        }

        // Create full-screen intent
        Intent fullScreenIntent = new Intent(this, MainActivity.class);
        fullScreenIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        fullScreenIntent.putExtra("callIncoming", true);
        fullScreenIntent.putExtra("callerId", callerId);
        fullScreenIntent.putExtra("callerName", callerName);
        fullScreenIntent.putExtra("channelName", channelName);
        fullScreenIntent.putExtra("isVideo", isVideo);
        
        PendingIntent fullScreenPendingIntent = PendingIntent.getActivity(
            this,
            0,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        // Create Answer Intent - DIRECTLY OPEN ACTIVITY
        Intent answerIntent = new Intent(this, MainActivity.class);
        answerIntent.setAction("ANSWER_CALL_ACTION");
        answerIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        answerIntent.putExtra("callerId", callerId);
        answerIntent.putExtra("channelName", channelName);
        answerIntent.putExtra("isVideo", isVideo);
        answerIntent.putExtra("acceptCall", true); // Signal MainActivity to accept
        
        PendingIntent answerPendingIntent = PendingIntent.getActivity(
            this, 
            1, 
            answerIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        // Create Decline Intent - DIRECTLY OPEN ACTIVITY (Avoid Notification Trampoline)
        Intent declineIntent = new Intent(this, MainActivity.class);
        declineIntent.setAction("DECLINE_CALL_ACTION");
        declineIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        declineIntent.putExtra("callerId", callerId);
        declineIntent.putExtra("channelName", channelName);
        declineIntent.putExtra("isVideo", isVideo);
        declineIntent.putExtra("declineCall", true); // Signal MainActivity to decline
        
        PendingIntent declinePendingIntent = PendingIntent.getActivity(
            this, 
            2, 
            declineIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        // Build notification
        NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(isVideo ? "Incoming Video Call" : "Incoming Audio Call")
            .setContentText((callerName != null && !callerName.isEmpty()) ? callerName : "Tap to answer")
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(false)
            // Add Action Buttons
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Decline", declinePendingIntent)
            .addAction(android.R.drawable.ic_menu_call, "Answer", answerPendingIntent);

        // Start foreground service
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Use MEDIA_PLAYBACK type as we are playing a ringtone
                startForeground(NOTIFICATION_ID, builder.build(), 
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
            } else {
                startForeground(NOTIFICATION_ID, builder.build());
            }
            System.out.println(TAG + " ✅ Foreground service started with full-screen intent");
        } catch (ForegroundServiceStartNotAllowedException ex) {
            System.out.println(TAG + " ⚠️ Foreground start blocked: " + ex.getMessage());
            // Fall back to posting notification and stop service to avoid crash
            NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (notificationManager != null) {
                notificationManager.notify(NOTIFICATION_ID, builder.build());
            }
            stopSelf();
        }
    }

    /// 🔴 BUG FIX #2: Show background "Call Running" notification
    public void showBackgroundCallNotification(String callerName) {
        System.out.println(TAG + " 📱 showBackgroundCallNotification called for: " + callerName);
        
        // Create notification channel for Android 8+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    BACKGROUND_CHANNEL_ID,
                    "Active Calls",
                    NotificationManager.IMPORTANCE_HIGH
            );
            channel.setDescription("Active call in progress");
            channel.enableVibration(false); // Don't vibrate for background notification
            channel.setShowBadge(true);
            
            NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (notificationManager != null) {
                notificationManager.createNotificationChannel(channel);
                System.out.println(TAG + " ✅ Background notification channel created");
            }
        }

        // Create intent to open app and return to call screen when tapped
        Intent callIntent = new Intent(this, MainActivity.class);
        callIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        callIntent.putExtra("callIncoming", true);
        callIntent.putExtra("channelName", channelName);
        callIntent.putExtra("callerId", callerId);
        PendingIntent callPendingIntent = PendingIntent.getActivity(
                this,
                100,
                callIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        // Build background "Call in Progress" notification
        NotificationCompat.Builder bgBuilder = new NotificationCompat.Builder(this, BACKGROUND_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Call in Progress")
                .setContentText("Tap to return to call")
                .setContentIntent(callPendingIntent)
                .setAutoCancel(false)
                .setOngoing(true)  // Persistent, can't swipe away
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_CALL);

        try {
            NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (notificationManager != null) {
                notificationManager.notify(BACKGROUND_NOTIFICATION_ID, bgBuilder.build());
                System.out.println(TAG + " ✅ Background call notification posted");
            }
        } catch (Exception e) {
            System.out.println(TAG + " ❌ Error posting background notification: " + e.getMessage());
        }
    }

    /// 🔴 BUG FIX #2: Remove background "Call Running" notification
    public void removeBackgroundCallNotification() {
        System.out.println(TAG + " 📵 removeBackgroundCallNotification called");
        try {
            NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
            if (notificationManager != null) {
                notificationManager.cancel(BACKGROUND_NOTIFICATION_ID);
                System.out.println(TAG + " ✅ Background notification removed");
            }
        } catch (Exception e) {
            System.out.println(TAG + " ❌ Error removing background notification: " + e.getMessage());
        }
    }

    private PendingIntent createFullScreenIntent() {
        Intent mainIntent = new Intent(this, MainActivity.class);
        mainIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TASK);
        mainIntent.putExtra("callIncoming", true);
        mainIntent.putExtra("channelName", channelName);
        mainIntent.putExtra("callerId", callerId);
        return PendingIntent.getActivity(
                this,
                0,
                mainIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    @Override
    public void onDestroy() {
        System.out.println(TAG + " onDestroy called - stopping foreground");
        stopRingtone();
        // Release wake lock
        if (wakeLock != null && wakeLock.isHeld()) {
            wakeLock.release();
            System.out.println(TAG + " ✅ Wake lock released");
        }
        stopForeground(true);
        super.onDestroy();
    }

    private void createCallChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return;
        NotificationManager notificationManager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
        if (notificationManager == null) return;

        NotificationChannel channel = notificationManager.getNotificationChannel(CHANNEL_ID);
        if (channel != null) return; // already created

        channel = new NotificationChannel(
            CHANNEL_ID,
            "Call Notifications",
            NotificationManager.IMPORTANCE_HIGH
        );
        channel.setDescription("Incoming call notifications");
        channel.setSound(null, null); // Disable system notification sound to avoid double/wrong sound
        channel.setLockscreenVisibility(Notification.VISIBILITY_PUBLIC);
        channel.setBypassDnd(true);
        notificationManager.createNotificationChannel(channel);
    }

    private android.media.MediaPlayer mediaPlayer;

    // ... (keep existing methods until playRingtone)

    private void playRingtone() {
        if (mediaPlayer != null && mediaPlayer.isPlaying()) {
            System.out.println(TAG + " ℹ️ MediaPlayer already playing");
            return;
        }
        
        try {
            Uri ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE);
            if (ringtoneUri == null) {
                System.out.println(TAG + " ⚠️ Default RINGTONE uri is null, trying NOTIFICATION");
                ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION);
            }
            if (ringtoneUri == null) {
                System.out.println(TAG + " ⚠️ Default NOTIFICATION uri is null, trying ALARM");
                ringtoneUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM);
            }
            
            if (ringtoneUri == null) {
                System.out.println(TAG + " ❌ All ringtone URIs are null, cannot play sound");
                return;
            }

            System.out.println(TAG + " 🎵 Preparing to play ringtone from URI: " + ringtoneUri.toString());
            
            mediaPlayer = new android.media.MediaPlayer();
            mediaPlayer.setDataSource(this, ringtoneUri);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                AudioAttributes attributes = new AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build();
                mediaPlayer.setAudioAttributes(attributes);
            } else {
                mediaPlayer.setAudioStreamType(AudioManager.STREAM_RING);
            }
            
            mediaPlayer.setLooping(true);
            mediaPlayer.prepare(); // Synchronous prepare (OK for local file)
            mediaPlayer.start();
            
            System.out.println(TAG + " ✅ MediaPlayer started successfully (Looping=true)");
        } catch (Exception e) {
            System.out.println(TAG + " ❌ Error starting MediaPlayer: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void stopRingtone() {
        try {
            if (mediaPlayer != null) {
                if (mediaPlayer.isPlaying()) {
                    mediaPlayer.stop();
                }
                mediaPlayer.release();
                mediaPlayer = null;
                System.out.println(TAG + " ✅ MediaPlayer stopped and released");
            }
        } catch (Exception e) {
            System.out.println(TAG + " ❌ Error stopping MediaPlayer: " + e.getMessage());
        }
    }
}
