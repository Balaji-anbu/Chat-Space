import 'package:cloud_firestore/cloud_firestore.dart';

import 'message_model.dart';
import 'user_model.dart';

class ChatModel {
  final String id;
  final List<String> participants;
  final UserModel otherUser;
  final String lastMessage;
  final Timestamp? lastMessageTime;
  final int unreadCount;
  final MessageStatus? lastMessageStatus;
  final String? lastMessageSenderId;

  ChatModel({
    required this.id,
    required this.participants,
    required this.otherUser,
    required this.lastMessage,
    this.lastMessageTime,
    required this.unreadCount,
    this.lastMessageStatus,
    this.lastMessageSenderId,
  });

  factory ChatModel.fromMap(
    String id,
    Map<String, dynamic> map,
    UserModel otherUser,
  ) {
    return ChatModel(
      id: id,
      participants: List<String>.from(map['participants'] ?? []),
      otherUser: otherUser,
      lastMessage: map['lastMessage'] ?? '',
      lastMessageTime: map['lastMessageTime'],
      unreadCount: map['unreadCount'] ?? 0,
      lastMessageStatus: map['lastMessageStatus'] != null
          ? MessageStatus.values.firstWhere(
              (status) =>
                  status.toString() ==
                  'MessageStatus.${map['lastMessageStatus']}',
              orElse: () => MessageStatus.sent,
            )
          : null,
      lastMessageSenderId: map['lastMessageSenderId'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'participants': participants,
      'lastMessage': lastMessage,
      'lastMessageTime': lastMessageTime,
      'unreadCount': unreadCount,
      'lastMessageStatus': lastMessageStatus?.toString().split('.').last,
      'lastMessageSenderId': lastMessageSenderId,
    };
  }

  ChatModel copyWith({
    String? id,
    List<String>? participants,
    UserModel? otherUser,
    String? lastMessage,
    Timestamp? lastMessageTime,
    int? unreadCount,
    MessageStatus? lastMessageStatus,
    String? lastMessageSenderId,
  }) {
    return ChatModel(
      id: id ?? this.id,
      participants: participants ?? this.participants,
      otherUser: otherUser ?? this.otherUser,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessageStatus: lastMessageStatus ?? this.lastMessageStatus,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
    );
  }
}
