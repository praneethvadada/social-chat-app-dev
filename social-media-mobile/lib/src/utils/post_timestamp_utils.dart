/// POST TIMESTAMP UTILITY - Dedicated for post timestamps with Indian timezone support
/// This ensures consistent timestamp formatting across all post displays
/// Independent from chat/call/notification timestamps to avoid conflicts

import 'package:intl/intl.dart';

/// Get formatted timestamp for posts with Indian timezone (IST)
/// Returns format based on time difference:
/// - Below 1 min: "Just Now"
/// - Below 1 hr: "X min ago"
/// - Below 24 hrs: "X hr ago"
/// - Yesterday: "Yesterday, h:mm am/pm"
/// - Other dates: "MMM d, h:mm am/pm"
String formatPostTimestamp(DateTime timestamp) {
  // Convert to IST (UTC+5:30)
  final istTimestamp = _convertToIST(timestamp);
  final now = _convertToIST(DateTime.now().toUtc());

  final diff = now.difference(istTimestamp);

  // Below 1 minute
  if (diff.inSeconds < 60) {
    return 'Just Now';
  }

  // Below 1 hour
  if (diff.inMinutes < 60) {
    final mins = diff.inMinutes;
    return '$mins min${mins > 1 ? 's' : ''} ago';
  }

  // Below 24 hours
  if (diff.inHours < 24) {
    final hrs = diff.inHours;
    return '$hrs hr${hrs > 1 ? 's' : ''} ago';
  }

  // Yesterday
  if (diff.inDays == 1 && _isYesterday(istTimestamp, now)) {
    final time = _formatTime(istTimestamp);
    return 'Yesterday, $time';
  }

  // Other dates - show "MMM d, h:mm am/pm"
  return _formatDateTime(istTimestamp);
}

/// Convert DateTime to IST (Indian Standard Time - UTC+5:30)
DateTime _convertToIST(DateTime utcTime) {
  // IST is UTC+5:30
  const istOffset = Duration(hours: 5, minutes: 30);
  return utcTime.add(istOffset);
}

/// Check if a date is yesterday
bool _isYesterday(DateTime date, DateTime now) {
  final yesterday = now.subtract(const Duration(days: 1));
  return date.year == yesterday.year &&
      date.month == yesterday.month &&
      date.day == yesterday.day;
}

/// Format time as "h:mm am/pm" (e.g., "2:35 pm")
String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour;
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = hour >= 12 ? 'pm' : 'am';
  final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
  return '$displayHour:$minute $period';
}

/// Format date time as "MMM d, h:mm am/pm" (e.g., "Jan 6, 10:10 am")
String _formatDateTime(DateTime dateTime) {
  final formatter = DateFormat('MMM d, h:mm a');
  return formatter.format(dateTime);
}

/// Get readable date for post (used in detail views if needed)
/// Format: "Wednesday, January 6, 2026 at 2:35 PM"
String formatPostDetailDate(DateTime timestamp) {
  final istTimestamp = _convertToIST(timestamp);
  final formatter = DateFormat('EEEE, MMMM d, yyyy \'at\' h:mm a');
  return formatter.format(istTimestamp);
}

/// Simple relative time for quick display
/// Returns: "just now", "2m", "3h", "5d", "Jan 6"
String formatPostQuickTime(DateTime timestamp) {
  final istTimestamp = _convertToIST(timestamp);
  final now = _convertToIST(DateTime.now().toUtc());

  final diff = now.difference(istTimestamp);

  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';

  return DateFormat('MMM d').format(istTimestamp);
}
