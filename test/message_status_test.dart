import 'package:chatapp/core/models/message_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Message Status Updates', () {
    test('should update message status from sent to delivered to read', () async {
      // This test verifies that the message status update logic works correctly
      // In a real scenario, this would be tested with Firebase emulators

      final message = MessageModel(
        id: 'test_message_1',
        senderId: 'user1',
        receiverId: 'user2',
        text: 'Test message',
        timestamp: Timestamp.now(),
        status: MessageStatus.sent,
      );

      // Verify initial status
      expect(message.status, MessageStatus.sent);

      // Simulate status update to delivered
      final deliveredMessage = message.copyWith(
        status: MessageStatus.delivered,
      );
      expect(deliveredMessage.status, MessageStatus.delivered);

      // Simulate status update to read
      final readMessage = deliveredMessage.copyWith(status: MessageStatus.read);
      expect(readMessage.status, MessageStatus.read);
    });

    test('should handle message status enum correctly', () {
      // Test enum values
      expect(MessageStatus.sent.toString(), 'MessageStatus.sent');
      expect(MessageStatus.delivered.toString(), 'MessageStatus.delivered');
      expect(MessageStatus.read.toString(), 'MessageStatus.read');

      // Test enum parsing
      expect(
        MessageStatus.values.firstWhere(
          (status) => status.toString().split('.').last == 'sent',
        ),
        MessageStatus.sent,
      );

      expect(
        MessageStatus.values.firstWhere(
          (status) => status.toString().split('.').last == 'delivered',
        ),
        MessageStatus.delivered,
      );

      expect(
        MessageStatus.values.firstWhere(
          (status) => status.toString().split('.').last == 'read',
        ),
        MessageStatus.read,
      );
    });
  });
}
