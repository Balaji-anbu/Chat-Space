import 'package:chatapp/core/models/message_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Reply Functionality Tests', () {
    test('MessageModel should support reply functionality', () {
      final message = MessageModel(
        id: 'test-message-1',
        senderId: 'user1',
        receiverId: 'user2',
        text: 'Hello world',
        status: MessageStatus.sent,
        replyTo: 'original-message-id',
      );

      expect(message.replyTo, equals('original-message-id'));
      expect(message.replyToMessage, isNull);
    });

    test('MessageModel.fromMap should parse replyTo field', () {
      final data = {
        'senderId': 'user1',
        'receiverId': 'user2',
        'text': 'Reply message',
        'timestamp': Timestamp.now(),
        'status': 'sent',
        'replyTo': 'original-message-id',
      };

      final message = MessageModel.fromMap('test-message-2', data);
      expect(message.replyTo, equals('original-message-id'));
    });

    test('MessageModel.toMap should include replyTo field', () {
      final message = MessageModel(
        id: 'test-message-3',
        senderId: 'user1',
        receiverId: 'user2',
        text: 'Reply message',
        status: MessageStatus.sent,
        replyTo: 'original-message-id',
      );

      final map = message.toMap();
      expect(map['replyTo'], equals('original-message-id'));
    });

    test('MessageModel.copyWith should preserve replyTo field', () {
      final originalMessage = MessageModel(
        id: 'test-message-4',
        senderId: 'user1',
        receiverId: 'user2',
        text: 'Original message',
        status: MessageStatus.sent,
        replyTo: 'original-message-id',
      );

      final updatedMessage = originalMessage.copyWith(text: 'Updated message');

      expect(updatedMessage.replyTo, equals('original-message-id'));
      expect(updatedMessage.text, equals('Updated message'));
    });
  });
}
