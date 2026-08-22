import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Utility class for parsing timestamps from backend that are in UTC
class TimestampParser {
  /// Parse timestamp from backend as UTC
  /// Backend sends LocalDateTime without timezone indicator, which is in UTC
  static DateTime parseUtc(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return DateTime.now().toUtc();
    }

    try {
      // If timestamp already has 'Z' or timezone info, parse normally
      if (timestamp.endsWith('Z') || 
          timestamp.contains('+') || 
          (timestamp.contains('T') && timestamp.split('T').last.contains('-'))) {
        return DateTime.parse(timestamp).toUtc();
      }
      
      // Otherwise, add 'Z' to indicate it's UTC time
      return DateTime.parse(timestamp + 'Z');
    } catch (e) {
      debugPrint('Error parsing timestamp: $timestamp, error: $e');
      return DateTime.now().toUtc();
    }
  }

  /// Parse timestamp that might be dynamic (from JSON)
  static DateTime parseDynamic(dynamic timestamp) {
    if (timestamp == null) {
      return DateTime.now().toUtc();
    }
    
    if (timestamp is DateTime) {
      return timestamp.toUtc();
    }
    
    return parseUtc(timestamp.toString());
  }

  /// Format timestamp as relative time (e.g., "just now", "5 min ago", "2 hrs ago")
  /// Supports: 0-60 sec, minutes, hours, days
  static String formatRelativeTime(DateTime timestamp) {
    // Important: Convert both to UTC to ensure correct difference calculation
    final now = DateTime.now().toUtc();
    final tsUtc = timestamp.toUtc();
    final difference = now.difference(tsUtc);
    
    // Less than 60 seconds
    if (difference.inSeconds < 60) {
      return 'just now';
    }
    
    // Minutes (1 - 59)
    if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '$mins min${mins > 1 ? 's' : ''}';
    }
    
    // Hours (1 - 23)
    if (difference.inHours < 24) {
      final hrs = difference.inHours;
      return '$hrs hr${hrs > 1 ? 's' : ''}';
    }
    
    // Days
    final days = difference.inDays;
    return '$days day${days > 1 ? 's' : ''}';
  }

  /// Format timestamp as relative time ago (e.g., "just now", "5 min ago", "2 hrs ago")
  static String formatRelativeTimeAgo(DateTime timestamp) {
    final relative = formatRelativeTime(timestamp);
    if (relative == 'just now') {
      return 'just now';
    }
    return '$relative ago';
  }

  /// Format for display in chat - shows local time converted from UTC
  static String formatForChat(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) {
      return 'just now';
    }
    
    try {
      final dateTime = parseUtc(timestamp);
      // formatRelativeTime now handles UTC properly, so pass the UTC timestamp directly
      return formatRelativeTime(dateTime);
    } catch (e) {
      debugPrint('Error formatting timestamp for chat: $e');
      return 'just now';
    }
  }

  /// Format timestamp in WhatsApp style:
  /// - "Just Now" (up to 59 seconds)
  /// - "X min ago" (up to 59 minutes)
  /// - "Today, 10:30 AM" (today after 1 hour)
  /// - "Yesterday, 9:45 PM" (yesterday)
  /// - "Monday, 3:20 PM" (within last week)
  /// - "15 January, 2:10 PM" (older)
  static String formatWhatsAppStyle(DateTime timestamp) {
    // Convert UTC to local Indian time (IST)
    final local = timestamp.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final timestampDate = DateTime(local.year, local.month, local.day);
    
    // Time format: "10:30 AM"
    final timeFormatter = DateFormat('h:mm a');
    final timeStr = timeFormatter.format(local);
    
    final difference = now.difference(local);
    
    // Less than 60 seconds: "Just Now"
    if (difference.inSeconds < 60) {
      return 'Just Now';
    }
    
    // Less than 60 minutes: "X min ago"
    if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      return '$mins min ago';
    }
    
    // Same day: "Today, 10:30 AM"
    if (timestampDate == today) {
      return 'Today, $timeStr';
    }
    
    // Yesterday: "Yesterday, 9:45 PM"
    if (timestampDate == yesterday) {
      return 'Yesterday, $timeStr';
    }
    
    // Within last 6 days: "Monday, 3:20 PM"
    if (difference.inDays < 6) {
      final dayFormatter = DateFormat('EEEE');
      final dayStr = dayFormatter.format(local);
      return '$dayStr, $timeStr';
    }
    
    // Older: "15 January, 2:10 PM"
    final dateFormatter = DateFormat('d MMMM');
    final dateStr = dateFormatter.format(local);
    return '$dateStr, $timeStr';
  }
}
