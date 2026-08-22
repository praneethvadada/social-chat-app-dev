import 'package:flutter/material.dart';
import '../models/message.dart';
import 'package:social_chat_app/src/theme/colors.dart';

/// MessageStatusIndicator - Shows message read status as ticks
/// 
/// ✓  = SENT (single gray tick - message sent to server)
/// ✓✓ = READ (double gray ticks - message read by recipient)
/// ⏱  = SENDING (clock icon - message being sent)
/// 🔼 = UPLOADING (spinner - media uploading)
/// 
/// Note: No blue ticks. Read receipts show as double gray ticks only.
class MessageStatusIndicator extends StatelessWidget {
  final Message message;
  final Color? color;

  const MessageStatusIndicator({
    Key? key,
    required this.message,
    this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final finalColor = color ?? AppColors.mutedSolid!;

    // Return appropriate icon based on message status
    switch (message.status) {
      case MessageStatus.sending:
        // ⏱ Clock icon for "sending"
        return Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text(
            '⏱',
            style: TextStyle(fontSize: 10, color: finalColor),
          ),
        );

      case MessageStatus.sent:
        // ✓ Single gray tick for "sent"
        return Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text(
            '✓',
            style: TextStyle(fontSize: 11, color: finalColor, fontWeight: FontWeight.bold),
          ),
        );

      case MessageStatus.read:
        // ✓✓ Double gray ticks for "read" (NO blue color)
        return Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Text(
            '✓✓',
            style: TextStyle(
              fontSize: 11,
              color: finalColor, // Gray ticks for read (not blue)
              fontWeight: FontWeight.bold,
            ),
          ),
        );

      case MessageStatus.uploading:
        // 🔼 Spinner for uploading
        return Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(finalColor),
            ),
          ),
        );

      case MessageStatus.failed:
        // ❌ Message was not sent - must stay visually distinct from a tick
        return const Padding(
          padding: EdgeInsets.only(left: 4.0),
          child: Icon(Icons.error_outline, size: 12, color: AppColors.danger),
        );
    }
  }
}

/// MessageStatusText - Returns text description of message status
String getMessageStatusText(MessageStatus status) {
  switch (status) {
    case MessageStatus.sending:
      return 'Sending...';
    case MessageStatus.sent:
      return 'Sent';
    case MessageStatus.read:
      return 'Read';
    case MessageStatus.uploading:
      return 'Uploading...';
    case MessageStatus.failed:
      return 'Not sent - tap to retry';
  }
}

/// MessageStatusIcon - Returns a more descriptive icon
Widget getMessageStatusIcon(MessageStatus status, {Color? color}) {
  final finalColor = color ?? AppColors.mutedSolid;

  switch (status) {
    case MessageStatus.sending:
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1,
          valueColor: AlwaysStoppedAnimation<Color>(finalColor ?? AppColors.mutedSolid),
        ),
      );

    case MessageStatus.sent:
      return Icon(Icons.check, size: 14, color: finalColor);

    case MessageStatus.read:
      // Double gray ticks for read (not blue)
      return Icon(Icons.done_all, size: 14, color: finalColor);

    case MessageStatus.uploading:
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(finalColor ?? AppColors.mutedSolid),
        ),
      );

    case MessageStatus.failed:
      return const Icon(Icons.error_outline, size: 14, color: AppColors.danger);
  }
}
