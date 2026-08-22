import 'package:flutter/services.dart';
import 'package:social_chat_app/src/state/call_state_manager.dart';
import 'package:social_chat_app/src/services/call_signaling_service.dart';
import 'package:social_chat_app/src/services/api_service.dart';

/// Communicates with native Android CallNotificationService
/// Uses MethodChannel to start/stop foreground call notifications
class CallNotificationPlatform {
  static const platform = MethodChannel('com.example.social_chat_app/call');
  static bool _initialized = false;

  // Cache the incoming call info so we can use it in accept/decline handlers
  static String _cachedChannelName = '';
  static int _cachedCallerId = 0;
  static bool _cachedIsVideo = false;

  /// Initialize method channel handlers for receiving calls from native code
  /// Should be called once during app startup
  static void initializeMethodHandlers() {
    if (_initialized) return;
    _initialized = true;

    platform.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'acceptCall':
            print('[CallNotificationPlatform] 📞 acceptCall received from native');
            final callerId = call.arguments['callerId'] as String?;
            final channelName = call.arguments['channelName'] as String?;
            final isVideo = call.arguments['isVideo'] as bool? ?? false;
            
            if (callerId != null && channelName != null) {
              await _handleAcceptCall(callerId, channelName, isVideo);
            }
            break;

          case 'declineCall':
            print('[CallNotificationPlatform] 📵 declineCall received from native');
            final callerId = call.arguments['callerId'] as String?;
            final channelName = call.arguments['channelName'] as String?;
            if (callerId != null && channelName != null) {
              await _handleDeclineCall(callerId, channelName);
            }
            break;

          default:
            print('[CallNotificationPlatform] ⚠️ Unknown method: ${call.method}');
            return null;
        }
      } catch (e) {
        print('[CallNotificationPlatform] ❌ Error handling method call: $e');
      }
      return null;
    });
  }

  /// Handle accept call from notification button
  /// This triggers the actual call start on the receiver's side
  /// Handle acceptCall from notification button
  /// This triggers the actual call start on the receiver's side
  static Future<void> _handleAcceptCall(String callerId, String channelName, bool isVideo) async {
    try {
      print('[CallNotificationPlatform] 📞 Handling accept call for callerId=$callerId isVideo=$isVideo');
      // Get current user ID
      final myUserId = await ApiService.getUserId();
      if (myUserId == null) {
        print('[CallNotificationPlatform] ❌ Could not get user ID');
        return;
      }
      
      // ✅ IMPORTANT: Update local call state to "inCall" BEFORE sending acceptance
      // This makes the UI transition from incoming call screen to active call screen
      print('[CallNotificationPlatform] 📞 Transitioning call state to inCall');
      final callStateManager = CallStateManager();
      
      // Build the payload for the call, using PASSED arguments (so it works on cold start too)
      final payload = {
        'fromUserId': int.tryParse(callerId) ?? 0,
        'toUserId': myUserId,
        'channelName': channelName,
        'isVideo': isVideo,
      };
      
      // Set state to inCall - this initializes Agora and shows active call UI
      // Force the state transition even if idle (since we accepted from notification)
      // CallStateManager usually blocks if not ringing/outgoing, so we might need to handle that.
      // But typically notification accept implies we are bypassing "ringing" or we set it transiently.
      // Actually, CallStateManager setInCall requires valid state.
      // Let's force it by transiently setting incomingRinging if needed, or update CallStateManager logic.
      // For now, let's assume CallStateManager checks are fine effectively, or we transiently set ringing.
      
      // Workaround: If idle, set ringing first to allow transition.
      if (callStateManager.currentState == CallState.idle) {
         print('[CallNotificationPlatform] ⚠️ State is IDLE (cold start?), setting transient incomingRinging');
         callStateManager.setIncomingCall(payload);
      }

      callStateManager.setInCall(payload);
      print('[CallNotificationPlatform] ✅ Call transitioned to inCall state');
      
      // Send accept message through websocket to notify remote peer
      print('[CallNotificationPlatform] 📤 Sending CALL_ACCEPT signal to remote peer');
      CallSignalingService().sendCallAccept(
        fromUserId: myUserId,
        toUserId: int.tryParse(callerId) ?? 0,
        channelName: channelName,
        isVideo: isVideo,
      );
      print('[CallNotificationPlatform] ✅ Accept signal sent - call should now be active on both sides');
    } catch (e) {
      print('[CallNotificationPlatform] ❌ Error accepting call: $e');
    }
  }

  /// Handle decline call from notification button
  static Future<void> _handleDeclineCall(String callerId, String channelName) async {
    try {
      print('[CallNotificationPlatform] 📵 Handling decline call for callerId=$callerId');
      // Get current user ID
      final myUserId = await ApiService.getUserId();
      if (myUserId == null) {
        print('[CallNotificationPlatform] ❌ Could not get user ID');
        return;
      }
      
      // Send reject message through websocket AND REST (await ensures it completes)
      // We await this so the network request is fired before we minimize
      print('[CallNotificationPlatform] ⏳ Sending rejection signal...');
      await CallSignalingService().sendCallReject(
        fromUserId: myUserId,
        toUserId: int.tryParse(callerId) ?? 0,
        channelName: channelName,
      );
      print('[CallNotificationPlatform] ✅ Rejection signal sent (or fire-and-forget started)');

      // Reset call state after rejection
      await CallStateManager().handleCallRejected(int.tryParse(callerId) ?? 0, 'Declined from notification');
      print('[CallNotificationPlatform] ✅ Decline sent');
      
      // Stop the notification (Native usually does this, but good to ensure)
      await stopCallNotification();
      
      // Finally, minimize the app since the user interacted with a notification action
      // and we forced the app to foreground to handle it.
      await minimizeApp();
      
    } catch (e) {
      print('[CallNotificationPlatform] ❌ Error declining call: $e');
    }
  }

  /// Start foreground service with ongoing call notification
  /// Shows WhatsApp-style incoming call popup with Answer/Decline buttons
  static Future<void> startCallNotification({
    required int callerId,
    required String callerName,
    required String channelName,
    required bool isVideo,
  }) async {
    try {
      print('[CallNotificationPlatform] 📞 Starting call notification for: $callerName');
      
      // Cache the call info for use in accept/decline handlers
      _cachedChannelName = channelName;
      _cachedCallerId = callerId;
      _cachedIsVideo = isVideo;
      
      await platform.invokeMethod('startCallNotification', {
        'callerId': callerId.toString(),
        'callerName': callerName,
        'channelName': channelName,
        'isVideo': isVideo,
        'playRingtone': false,
      });
      print('[CallNotificationPlatform] ✅ Call notification started');
    } catch (e) {
      print('[CallNotificationPlatform] ❌ Error starting call notification: $e');
    }
  }

  /// Stop foreground service and remove call notification
  /// Called when call ends, is rejected, or is answered
  static Future<void> stopCallNotification() async {
    try {
      print('[CallNotificationPlatform] 📵 Stopping call notification');
      await platform.invokeMethod('stopCallNotification');
      print('[CallNotificationPlatform] ✅ Call notification stopped');
    } catch (e) {
      print('[CallNotificationPlatform] ❌ Error stopping call notification: $e');
    }
  }

  /// Show persistent "background call running" notification
  /// Keeps user informed that call is active even if app is backgrounded
  static Future<void> showBackgroundCallNotification({
    required String callerName,
    required String channelName,
  }) async {
    try {
      print('[CallNotificationPlatform] 📱 Showing background call notification');
      await platform.invokeMethod('showBackgroundCallNotification', {
        'callerName': callerName,
        'channelName': channelName,
      });
      print('[CallNotificationPlatform] ✅ Background call notification shown');
    } catch (e) {
      print('[CallNotificationPlatform] ❌ Error showing background call notification: $e');
    }
  }

  /// Remove background call notification
  static Future<void> hideBackgroundCallNotification() async {
    try {
      print('[CallNotificationPlatform] 📵 Hiding background call notification');
      await platform.invokeMethod('hideBackgroundCallNotification');
      print('[CallNotificationPlatform] ✅ Background call notification hidden');
    } catch (e) {
      print('[CallNotificationPlatform] ❌ Error hiding background call notification: $e');
    }
  }

  /// Minimize the app programmatically (move to back)
  static Future<void> minimizeApp() async {
    try {
      print('[CallNotificationPlatform] 📉 Minimizing app...');
      await platform.invokeMethod('minimizeApp');
      print('[CallNotificationPlatform] ✅ App minimized');
    } catch (e) {
      print('[CallNotificationPlatform] ❌ Error minimizing app: $e');
    }
  }

  /// Notify Native that Flutter is ready to receive messages
  static Future<void> signalFlutterReady() async {
    try {
      print('[CallNotificationPlatform] 🚀 Signaling Flutter is ready...');
      await platform.invokeMethod('flutterReady');
      print('[CallNotificationPlatform] ✅ Signal sent');
    } catch (e) {
      print('[CallNotificationPlatform] ⚠️ Error signaling flutter ready: $e');
    }
  }
}
