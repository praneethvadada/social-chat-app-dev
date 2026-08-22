import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../state/call_state_manager.dart';
import '../navigation/root_navigator_key.dart';
import '../screens/call_screen.dart';
import '../screens/calls/calling_loader_screen.dart';
import '../screens/calls/incoming_call_screen.dart';
import 'api_service.dart';

/// Manages call screen navigation by listening to CallStateManager
/// Shows call screens using Navigator.push - NO OVERLAY APPROACH
class CallOverlayManager {
  static final CallOverlayManager _instance = CallOverlayManager._internal();
  factory CallOverlayManager() => _instance;

  int? _cachedUserId;

  CallOverlayManager._internal() {
    // Pre-cache userId
    _initUserId();
    // Listen to CallStateManager and show/hide call screens accordingly
    CallStateManager().addListener(_onCallStateChanged);
  }

  Future<void> _initUserId() async {
    _cachedUserId = await ApiService.getUserId();
    print('[CallOverlayManager] 📌 Cached userId=$_cachedUserId');
  }

  /// Determine remote user ID from payload
  /// For sender: toUserId is remote
  /// For receiver: fromUserId is remote
  int _getRemoteUserId(Map<String, dynamic>? payload) {
    if (payload == null) return 0;

    final fromUserId = payload['fromUserId'] as int? ?? 0;
    final toUserId = payload['toUserId'] as int? ?? 0;
    final myId = _cachedUserId;

    // If I'm the fromUser, then toUser is remote
    // If I'm the toUser, then fromUser is remote
    if (myId != null) {
      if (fromUserId == myId) {
        print(
            '[CallOverlayManager] 🔍 I am fromUser($myId), remote is toUser($toUserId)');
        return toUserId;
      } else if (toUserId == myId) {
        print(
            '[CallOverlayManager] 🔍 I am toUser($myId), remote is fromUser($fromUserId)');
        return fromUserId;
      }
    }

    // Fallback: try toUserId first, then fromUserId
    print(
        '[CallOverlayManager] 🔍 Fallback: using toUserId=$toUserId or fromUserId=$fromUserId');
    return toUserId != 0 ? toUserId : fromUserId;
  }

  bool _isCallScreenVisible = false;
  CallState? _currentScreenState; // Track which state's screen is showing
  bool _isReplacingScreen =
      false; // Flag to prevent original push's .then() from firing during replacement
  bool _popScheduled = false; // Prevent duplicate pop scheduling

  void _onCallStateChanged() {
    final callState = CallStateManager().currentState;
    final payload = CallStateManager().activeCallPayload;
    final isMinimized = CallStateManager().isMinimized;

    print('[CallOverlayManager] ============ STATE CHANGE ============');
    print('[CallOverlayManager] 🎬 NEW State: $callState');
    print('[CallOverlayManager] 🎬 minimized: $isMinimized');
    print('[CallOverlayManager] 🎬 screenVisible: $_isCallScreenVisible');
    print('[CallOverlayManager] 🎬 currentScreen: $_currentScreenState');
    print('[CallOverlayManager] 🎬 payload: $payload');
    print('[CallOverlayManager] 🎬 myId: $_cachedUserId');
    print('[CallOverlayManager] ============================================');

    // SAFETY CHECK: Detect invalid state sequences
    // IncomingCallScreen should NEVER be shown if previous state was outgoingCalling
    if (callState == CallState.incomingRinging &&
        _currentScreenState == CallState.outgoingCalling) {
      print(
          '[CallOverlayManager] ❌❌❌ CRITICAL ERROR: Transition from outgoingCalling to incomingRinging');
      print(
          '[CallOverlayManager] ❌❌❌ This should NEVER happen - blocking screen show');
      return;
    }

    // RULE 1: If call ended or idle → close any open screen
    if (callState == CallState.idle || callState == CallState.ended) {
      if (_isCallScreenVisible && !_popScheduled) {
        print('[CallOverlayManager] ❌ Scheduling screen close for next frame');
        _popScheduled = true;

        // CRITICAL FIX: Defer the pop to the next frame to avoid Navigator state conflicts
        // This prevents the black screen crash caused by pop happening during rebuild
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _popScheduled = false;

          if (rootNavigatorKey.currentContext != null && _isCallScreenVisible) {
            final navigator = Navigator.of(rootNavigatorKey.currentContext!);

            // Only pop if there's a route to pop
            if (navigator.canPop()) {
              navigator.pop();
              print(
                  '[CallOverlayManager] ✅ Screen popped successfully (deferred)');
            } else {
              print(
                  '[CallOverlayManager] ⚠️ Cannot pop - Navigator history is empty');
            }
          }

          _isCallScreenVisible = false;
          _currentScreenState = null;
        });
      }
      return;
    }

    // RULE 2: If minimized → don't show screen
    if (isMinimized) {
      print('[CallOverlayManager] 📱 Minimized - no screen');
      _currentScreenState = callState; // Track state even when minimized
      return;
    }

    // RULE 3: If state changed and screen is visible → replace screen
    if (_isCallScreenVisible &&
        _currentScreenState != callState &&
        rootNavigatorKey.currentContext != null) {
      print('[CallOverlayManager] 🔄 ========== REPLACING SCREEN ==========');
      print('[CallOverlayManager] 🔄 OLD SCREEN STATE: $_currentScreenState');
      print('[CallOverlayManager] 🔄 NEW SCREEN STATE: $callState');
      print('[CallOverlayManager] 🔄 Payload: $payload');

      // CRITICAL: Determine what screen will be shown
      String screenName = 'Unknown';
      switch (callState) {
        case CallState.outgoingCalling:
          screenName = 'CallingLoaderScreen';
          break;
        case CallState.incomingRinging:
          screenName = 'IncomingCallScreen';
          break;
        case CallState.connecting:
        case CallState.inCall:
        case CallState.reconnecting:
        case CallState.failed:
          // connecting/reconnecting/failed are sub-states rendered *within*
          // CallScreen, not separate routes.
          screenName = 'CallScreen';
          break;
        default:
          screenName = 'None';
      }
      print('[CallOverlayManager] 🔄 WILL SHOW: $screenName');
      print(
          '[CallOverlayManager] 🔄 ==========================================');

      // Update tracked state BEFORE deferring to prevent duplicate calls
      _currentScreenState = callState;

      // CRITICAL: Defer navigation to next frame to avoid conflicts during rebuild
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (rootNavigatorKey.currentContext == null) return;

        final context = rootNavigatorKey.currentContext!;
        Widget newScreen;

        switch (callState) {
          case CallState.outgoingCalling:
            newScreen = CallingLoaderScreen(payload: payload ?? {});
            break;
          case CallState.incomingRinging:
            newScreen = IncomingCallScreen(payload: payload ?? {});
            break;
          case CallState.connecting:
          case CallState.inCall:
          case CallState.reconnecting:
          case CallState.failed:
            final remoteUserId = _getRemoteUserId(payload);
            final channelName = payload?['channelName'] as String? ?? '';
            final isVideo = payload?['isVideo'] as bool? ?? false;
            newScreen = CallScreen(
              otherUserId: remoteUserId,
              channelName: channelName,
              isVideo: isVideo,
            );
            break;
          default:
            return;
        }

        // Set flag to prevent original push's .then() from firing
        _isReplacingScreen = true;

        // Use pushReplacement to atomically replace the old screen
        Navigator.of(context)
            .pushReplacement(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => newScreen,
          ),
        )
            .then((_) {
          // This .then() fires when the NEW route is eventually popped
          print('[CallOverlayManager] 📤 Replaced screen popped');
          _isReplacingScreen = false;
          _isCallScreenVisible = false;
          _currentScreenState = null;

          final callManager = CallStateManager();
          final currentState = callManager.currentState;
          final isMinimized = callManager.isMinimized;

          if (isMinimized) {
            print(
                '[CallOverlayManager] 📱 Screen was minimized - keeping call active');
          } else if (currentState != CallState.idle &&
              currentState != CallState.ended) {
            print(
                '[CallOverlayManager] 🔴 Screen dismissed without minimize - ending call');
            callManager.reset();
          }
        }).catchError((error) {
          // Handle pop errors gracefully
          print('[CallOverlayManager] ⚠️ Error after pushReplacement: $error');
          _isReplacingScreen = false;
          _isCallScreenVisible = false;
          _currentScreenState = null;
        });
      });

      // Keep _isCallScreenVisible = true (don't reset here)
      return;
    }

    // RULE 4: If no screen visible → show screen for current state
    if (!_isCallScreenVisible && rootNavigatorKey.currentContext != null) {
      print('[CallOverlayManager] ✅ Showing screen for state: $callState');
      _showCallScreen(callState, payload);
    }
  }

  void _showCallScreen(CallState callState, Map<String, dynamic>? payload) {
    if (payload == null || rootNavigatorKey.currentContext == null) return;

    print('[CallOverlayManager] 📱 Showing call screen for state: $callState');

    // Set flags BEFORE deferring to prevent duplicate calls
    _isCallScreenVisible = true;
    _currentScreenState = callState;

    // CRITICAL: Defer navigation to next frame to avoid conflicts during rebuild
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (rootNavigatorKey.currentContext == null) {
        _isCallScreenVisible = false;
        _currentScreenState = null;
        return;
      }

      final context = rootNavigatorKey.currentContext!;
      Widget callScreen;

      switch (callState) {
        case CallState.outgoingCalling:
          callScreen = CallingLoaderScreen(payload: payload);
          break;
        case CallState.incomingRinging:
          callScreen = IncomingCallScreen(payload: payload);
          break;
        case CallState.connecting:
        case CallState.inCall:
        case CallState.reconnecting:
        case CallState.failed:
          final remoteUserId = _getRemoteUserId(payload);
          final channelName = payload['channelName'] as String? ?? '';
          final isVideo = payload['isVideo'] as bool? ?? false;
          final fromNotification = payload['fromNotification'] as bool? ?? false;
          callScreen = CallScreen(
            otherUserId: remoteUserId,
            channelName: channelName,
            isVideo: isVideo,
            fromNotification: fromNotification,
          );
          break;
        default:
          _isCallScreenVisible = false;
          _currentScreenState = null;
          return;
      }

      Navigator.of(context)
          .push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => callScreen,
        ),
      )
          .then((_) {
        // When screen is popped, check if it's due to replacement
        if (_isReplacingScreen) {
          print(
              '[CallOverlayManager] 📤 Old screen popped during replacement - ignoring');
          return; // Don't reset, just return
        }

        // When screen is popped manually, update flag
        print('[CallOverlayManager] 📤 Call screen popped');
        _isCallScreenVisible = false;
        _currentScreenState = null;

        // Only reset if user dismissed screen manually (not via minimize button)
        final callManager = CallStateManager();
        final currentState = callManager.currentState;
        final isMinimized = callManager.isMinimized;

        if (isMinimized) {
          print(
              '[CallOverlayManager] 📱 Screen was minimized - keeping call active');
        } else if (currentState != CallState.idle &&
            currentState != CallState.ended) {
          print(
              '[CallOverlayManager] 🔴 Screen dismissed without minimize - ending call');
          callManager.reset();
        }
      }).catchError((error) {
        // Handle pop errors gracefully
        print('[CallOverlayManager] ⚠️ Error after push: $error');
        _isCallScreenVisible = false;
        _currentScreenState = null;
      });
    });
  }

  void dispose() {
    CallStateManager().removeListener(_onCallStateChanged);
  }
}
