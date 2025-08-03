import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String id;
  final String email;
  final String displayName;
  final bool isOnline;
  final Timestamp? lastSeen;

  UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isOnline,
    this.lastSeen,
  });

  factory UserModel.fromMap(String id, Map<String, dynamic> map) {
    return UserModel(
      id: id,
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? '',
      isOnline: map['isOnline'] ?? false,
      lastSeen: map['lastSeen'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'isOnline': isOnline,
      'lastSeen': lastSeen,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    bool? isOnline,
    Timestamp? lastSeen,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
} 