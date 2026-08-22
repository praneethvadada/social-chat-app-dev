/// POST TIMESTAMP WIDGET - Simple, reliable timestamp display for posts
/// Uses post_timestamp_utils for consistent IST formatting
/// No complex state updates - just renders the formatted time

import 'package:flutter/material.dart';
import 'post_timestamp_utils.dart';

/// Simple widget to display post timestamp
/// Uses IST timezone and formats according to post_timestamp_utils
class PostTimestampWidget extends StatelessWidget {
  final DateTime timestamp;
  final TextStyle? style;

  const PostTimestampWidget({
    super.key,
    required this.timestamp,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final formattedTime = formatPostTimestamp(timestamp);
    
    return Text(
      formattedTime,
      style: style,
      overflow: TextOverflow.ellipsis,
    );
  }
}
