import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../state/group_call_state_manager.dart';
import '../navigation/root_navigator_key.dart';
import '../screens/calls/incoming_group_call_screen.dart';
import '../screens/calls/group_call_screen.dart';

/// Mirrors CallOverlayManager's role for 1:1 calls, but for the much
/// simpler group-call state machine (idle / incomingRinging / inCall) — no
/// replace-screen edge cases needed since group calls skip the
/// "outgoingCalling" step entirely (the caller joins the grid immediately).
class GroupCallOverlayManager {
  static final GroupCallOverlayManager _instance = GroupCallOverlayManager._internal();
  factory GroupCallOverlayManager() => _instance;

  GroupCallOverlayManager._internal() {
    GroupCallStateManager().addListener(_onStateChanged);
  }

  bool _screenVisible = false;
  GroupCallState? _shownFor;

  void _onStateChanged() {
    final gm = GroupCallStateManager();
    final state = gm.currentState;

    if (state == GroupCallState.idle) {
      if (_screenVisible) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null && Navigator.of(ctx).canPop() && _screenVisible) {
            Navigator.of(ctx).pop();
          }
          _screenVisible = false;
          _shownFor = null;
        });
      }
      return;
    }

    if (gm.isMinimized) {
      _shownFor = state;
      return;
    }

    if (_screenVisible && _shownFor != state) {
      // incomingRinging -> inCall (accepted): swap screens.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null) return;
        _shownFor = state;
        Navigator.of(ctx).pushReplacement(
          MaterialPageRoute(fullscreenDialog: true, builder: (_) => _screenFor(state)),
        ).then((_) => _onPopped());
      });
      return;
    }

    if (!_screenVisible) {
      _screenVisible = true;
      _shownFor = state;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        final ctx = rootNavigatorKey.currentContext;
        if (ctx == null) {
          _screenVisible = false;
          return;
        }
        Navigator.of(ctx).push(
          MaterialPageRoute(fullscreenDialog: true, builder: (_) => _screenFor(state)),
        ).then((_) => _onPopped());
      });
    }
  }

  void _onPopped() {
    _screenVisible = false;
    _shownFor = null;
    final gm = GroupCallStateManager();
    if (!gm.isMinimized && gm.currentState != GroupCallState.idle) {
      gm.reset();
    }
  }

  Widget _screenFor(GroupCallState state) {
    switch (state) {
      case GroupCallState.incomingRinging:
        return const IncomingGroupCallScreen();
      case GroupCallState.inCall:
        return const GroupCallScreen();
      case GroupCallState.idle:
        return const SizedBox.shrink();
    }
  }

  void dispose() {
    GroupCallStateManager().removeListener(_onStateChanged);
  }
}
