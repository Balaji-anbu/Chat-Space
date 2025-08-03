import 'package:chatapp/core/utils/timestamp_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TimestampUtils Tests', () {
    test('formatMessageTime - today messages', () {
      final now = DateTime.now();
      final todayMessage = DateTime(
        now.year,
        now.month,
        now.day,
        14,
        30,
      ); // 2:30 PM

      final result = TimestampUtils.formatMessageTime(todayMessage);

      // Should show only time in 12-hour format
      expect(result, contains('2:30 PM'));
    });

    test('formatMessageTime - yesterday messages', () {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final yesterdayMessage = DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
        14,
        30,
      );

      final result = TimestampUtils.formatMessageTime(yesterdayMessage);

      // Should show "Yesterday" and time
      expect(result, contains('Yesterday'));
      expect(result, contains('2:30 PM'));
    });

    test('formatLastSeen - just now', () {
      final justNow = DateTime.now().subtract(const Duration(minutes: 30));

      final result = TimestampUtils.formatLastSeen(justNow);

      expect(result, '30 minutes ago');
    });

    test('formatLastSeen - 1 hour ago', () {
      final oneHourAgo = DateTime.now().subtract(const Duration(hours: 1));

      final result = TimestampUtils.formatLastSeen(oneHourAgo);

      expect(result, '1 hour ago');
    });

    test('formatLastSeen - multiple hours ago', () {
      final threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3));

      final result = TimestampUtils.formatLastSeen(threeHoursAgo);

      expect(result, '3 hours ago');
    });

    test('formatChatListTime - today messages', () {
      final now = DateTime.now();
      final todayMessage = DateTime(now.year, now.month, now.day, 14, 30);

      final result = TimestampUtils.formatChatListTime(todayMessage);

      // Should show only time in 12-hour format
      expect(result, contains('2:30 PM'));
    });

    test('formatChatListTime - yesterday messages', () {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final yesterdayMessage = DateTime(
        yesterday.year,
        yesterday.month,
        yesterday.day,
        14,
        30,
      );

      final result = TimestampUtils.formatChatListTime(yesterdayMessage);

      // Should show only "Yesterday"
      expect(result, 'Yesterday');
    });
  });
}
