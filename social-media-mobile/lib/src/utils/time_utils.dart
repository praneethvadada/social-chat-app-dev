import 'package:flutter/material.dart';

/// A widget that displays dynamic "time ago" text that updates automatically
class TimeAgoWidget extends StatefulWidget {
  final DateTime timestamp;
  final TextStyle? style;

  const TimeAgoWidget({
    super.key,
    required this.timestamp,
    this.style,
  });

  @override
  State<TimeAgoWidget> createState() => _TimeAgoWidgetState();
}

class _TimeAgoWidgetState extends State<TimeAgoWidget> {
  late String _timeAgoText;
  late Duration _updateInterval;

  @override
  void initState() {
    super.initState();
    _updateTimeAgo();
    _scheduleNextUpdate();
  }

  void _updateTimeAgo() {
    // Safe timezone handling: normalize both timestamps to UTC before comparing
    // This handles cases where timestamp might be local or UTC
    final now = DateTime.now().toUtc();
    final ts = widget.timestamp.isUtc ? widget.timestamp : widget.timestamp.toUtc();
    final diff = now.difference(ts);
    
    print('[TimeAgoWidget] 🕐 timestamp=${widget.timestamp}, isUtc=${widget.timestamp.isUtc}, diff=${diff.inSeconds}s');
    
    // Determine update interval based on time elapsed
    if (diff.inSeconds < 60) {
      _timeAgoText = formatTimeAgo(diff);
      _updateInterval = const Duration(seconds: 5); // Update every 5 seconds for recent posts
    } else if (diff.inMinutes < 60) {
      _timeAgoText = formatTimeAgo(diff);
      _updateInterval = const Duration(minutes: 1); // Update every minute
    } else if (diff.inHours < 24) {
      _timeAgoText = formatTimeAgo(diff);
      _updateInterval = const Duration(hours: 1); // Update every hour
    } else {
      _timeAgoText = formatTimeAgo(diff);
      _updateInterval = const Duration(days: 1); // Update daily for older posts
    }
  }

  void _scheduleNextUpdate() {
    Future.delayed(_updateInterval, () {
      if (mounted) {
        setState(() {
          _updateTimeAgo();
        });
        _scheduleNextUpdate();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Text(_timeAgoText, style: widget.style);
  }
}

/// Format time difference as human-readable string (relative time)
/// Examples: "just now", "1 min", "10 mins", "1 hr", "2 hrs", "1 day", "2 days"
String formatTimeAgo(Duration diff) {
  // 0-60 seconds: "just now"
  if (diff.inSeconds < 60) return 'just now';
  
  // Minutes (1-59)
  if (diff.inMinutes < 60) {
    final mins = diff.inMinutes;
    return '$mins min${mins > 1 ? 's' : ''}';
  }
  
  // Hours (1-23)
  if (diff.inHours < 24) {
    final hrs = diff.inHours;
    return '$hrs hr${hrs > 1 ? 's' : ''}';
  }
  
  // Days
  final days = diff.inDays;
  return '$days day${days > 1 ? 's' : ''}';
}

/// Get time ago string from DateTime (safe timezone handling)
String getTimeAgo(DateTime timestamp) {
  // Normalize both to UTC before comparing
  final now = DateTime.now().toUtc();
  final ts = timestamp.isUtc ? timestamp : timestamp.toUtc();
  final diff = now.difference(ts);
  return formatTimeAgo(diff);
}