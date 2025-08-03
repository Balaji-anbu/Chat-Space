import 'package:intl/intl.dart';

class TimestampUtils {
  static String formatMessageTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    // Format for 12-hour time
    final timeFormat = DateFormat('h:mm a'); // e.g., "2:30 PM"

    if (messageDate == today) {
      // Today - show only time
      return timeFormat.format(dateTime);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // Yesterday - show "Yesterday" and time
      return 'Yesterday ${timeFormat.format(dateTime)}';
    } else if (now.difference(dateTime).inDays < 7) {
      // Within a week - show day name and time
      final dayFormat = DateFormat('E'); // e.g., "Mon"
      return '${dayFormat.format(dateTime)} ${timeFormat.format(dateTime)}';
    } else {
      // Older - show date and time
      final dateFormat = DateFormat('MMM d'); // e.g., "Dec 15"
      return '${dateFormat.format(dateTime)} ${timeFormat.format(dateTime)}';
    }
  }

  static String formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      if (difference.inHours == 1) {
        return '1 hour ago';
      } else {
        return '${difference.inHours} hours ago';
      }
    } else if (difference.inDays < 7) {
      if (difference.inDays == 1) {
        return 'Yesterday';
      } else {
        return '${difference.inDays} days ago';
      }
    } else {
      // For older dates, show the actual date
      final dateFormat = DateFormat('MMM d, y'); // e.g., "Dec 15, 2023"
      return dateFormat.format(lastSeen);
    }
  }

  static String formatChatListTime(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    // Format for 12-hour time
    final timeFormat = DateFormat('h:mm a'); // e.g., "2:30 PM"

    if (messageDate == today) {
      // Today - show only time
      return timeFormat.format(dateTime);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      // Yesterday - show "Yesterday"
      return 'Yesterday';
    } else if (now.difference(dateTime).inDays < 7) {
      // Within a week - show day name
      final dayFormat = DateFormat('E'); // e.g., "Mon"
      return dayFormat.format(dateTime);
    } else {
      // Older - show date
      final dateFormat = DateFormat('MMM d'); // e.g., "Dec 15"
      return dateFormat.format(dateTime);
    }
  }
}
