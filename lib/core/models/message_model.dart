import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/emoji_utils.dart';

enum MessageStatus { sent, delivered, read }

class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String text;
  final Timestamp? timestamp;
  final MessageStatus status;
  final bool isEdited;
  final Map<String, String> reactions; // userId -> reaction emoji
  final bool isEmojiOnly; // Track if message contains only emojis
  final String? replyTo; // ID of the message being replied to
  final MessageModel? replyToMessage; // The actual message being replied to

  MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.text,
    this.timestamp,
    required this.status,
    this.isEdited = false,
    this.reactions = const {},
    bool? isEmojiOnly,
    this.replyTo,
    this.replyToMessage,
  }) : isEmojiOnly = isEmojiOnly ?? EmojiUtils.isEmojiOnly(text);

  factory MessageModel.fromMap(String id, Map<String, dynamic> map) {
    return MessageModel(
      id: id,
      senderId: map['senderId'] ?? '',
      receiverId: map['receiverId'] ?? '',
      text: map['text'] ?? '',
      timestamp: map['timestamp'],
      status: MessageStatus.values.firstWhere(
        (status) =>
            status.toString().split('.').last == (map['status'] ?? 'sent'),
        orElse: () => MessageStatus.sent,
      ),
      isEdited: map['isEdited'] ?? false,
      reactions: Map<String, String>.from(map['reactions'] ?? {}),
      isEmojiOnly:
          map['isEmojiOnly'] ?? EmojiUtils.isEmojiOnly(map['text'] ?? ''),
      replyTo: map['replyTo'],
      replyToMessage: null, // Will be populated separately if needed
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'text': text,
      'timestamp': timestamp,
      'status': status.toString().split('.').last,
      'isEdited': isEdited,
      'reactions': reactions,
      'isEmojiOnly': isEmojiOnly,
      'replyTo': replyTo,
    };
  }

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? text,
    Timestamp? timestamp,
    MessageStatus? status,
    bool? isEdited,
    Map<String, String>? reactions,
    bool? isEmojiOnly,
    String? replyTo,
    MessageModel? replyToMessage,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      isEdited: isEdited ?? this.isEdited,
      reactions: reactions ?? this.reactions,
      isEmojiOnly: isEmojiOnly ?? this.isEmojiOnly,
      replyTo: replyTo ?? this.replyTo,
      replyToMessage: replyToMessage ?? this.replyToMessage,
    );
  }
}
