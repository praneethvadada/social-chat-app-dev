package com.example.social_chat_app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Handles Answer/Decline button actions from call notifications
 */
public class CallActionReceiver extends BroadcastReceiver {
    private static final String TAG = "[CallActionReceiver]";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        String channelName = intent.getStringExtra("channelName");
        String callerId = intent.getStringExtra("callerId");
        boolean isVideo = intent.getBooleanExtra("isVideo", false); // Default to audio if missing

        System.out.println(TAG + " onReceive: action=" + action + ", callerId=" + callerId + ", isVideo=" + isVideo);

        if ("ANSWER_CALL".equals(action)) {
            System.out.println(TAG + " 📞 ANSWER_CALL pressed");
            handleAnswerCall(context, channelName, callerId, isVideo);
        } else if ("DECLINE_CALL".equals(action)) {
            System.out.println(TAG + " 📵 DECLINE_CALL pressed");
            handleDeclineCall(context, channelName, callerId);
        }

        // Stop the service
        stopCallNotificationService(context);
    }

    private void handleAnswerCall(Context context, String channelName, String callerId, boolean isVideo) {
        try {
            System.out.println(TAG + " 📞 Bringing app to foreground and answering call");
            
            // Launch MainActivity with AGGRESSIVE flags to bring to foreground
            Intent mainIntent = new Intent(context, MainActivity.class);
            mainIntent.setFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK | 
                Intent.FLAG_ACTIVITY_SINGLE_TOP | 
                Intent.FLAG_ACTIVITY_REORDER_TO_FRONT |  // Bring existing task to front
                Intent.FLAG_ACTIVITY_CLEAR_TOP           // Clear any activities above it
            );
            mainIntent.putExtra("callIncoming", true);
            mainIntent.putExtra("channelName", channelName);
            mainIntent.putExtra("callerId", callerId);
            mainIntent.putExtra("acceptCall", true); // Signal to automatically accept
            mainIntent.putExtra("isVideo", isVideo); // Pass video state
            context.startActivity(mainIntent);
            System.out.println(TAG + " ✅ startActivity called to bring app to foreground");
            
        } catch (Exception e) {
            System.out.println(TAG + " ❌ Error handling answer call: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void handleDeclineCall(Context context, String channelName, String callerId) {
        try {
            System.out.println(TAG + " 📵 DECLINE_CALL pressed - Starting MainActivity to handle event");
            
            // We MUST start the activity because the app might be killed, 
            // and we need the Flutter Engine (and Auth Token) to send the Reject signal.
            Intent mainIntent = new Intent(context, MainActivity.class);
            mainIntent.setFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK | 
                Intent.FLAG_ACTIVITY_SINGLE_TOP | 
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            );
            mainIntent.putExtra("declineCall", true);
            mainIntent.putExtra("channelName", channelName);
            mainIntent.putExtra("callerId", callerId);
            context.startActivity(mainIntent);
            
            System.out.println(TAG + " ✅ startActivity called for Decline");
        } catch (Exception e) {
            System.out.println(TAG + " ❌ Error handling decline call: " + e.getMessage());
            e.printStackTrace();
        }
    }

    private void stopCallNotificationService(Context context) {
        try {
            // Directly STOP the service to kill notification and ringtone immediately
            Intent stopIntent = new Intent(context, CallNotificationService.class);
            context.stopService(stopIntent);
            System.out.println(TAG + " ✅ Service stopped directly via stopService()");
        } catch (Exception e) {
            System.out.println(TAG + " ❌ Error stopping service: " + e.getMessage());
        }
    }
}
