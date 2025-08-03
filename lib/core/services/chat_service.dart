import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_model.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../utils/emoji_utils.dart';

class ChatService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  final List<ChatModel> _chats = [];
  final List<MessageModel> _messages = [];
  final bool _isLoading = false;

  // Cache for user data to avoid repeated queries
  final Map<String, UserModel> _userCache = {};
  final Map<String, List<MessageModel>> _messageCache = {};

  // Track which chats are being loaded to prevent duplicate requests
  final Set<String> _loadingChats = {};

  // Lazy loading state management
  final Map<String, DocumentSnapshot?> _lastDocuments = {};
  final Map<String, bool> _hasMoreMessages = {};
  final Map<String, bool> _isLoadingMore = {};

  // Typing indicator management
  final Map<String, Timer> _typingTimers = {};
  final Map<String, bool> _isTyping = {};
  bool _isDisposed = false;

  // Real-time user status listeners
  final Map<String, StreamSubscription> _userStatusListeners = {};

  List<ChatModel> get chats => _chats;
  List<MessageModel> get messages => _messages;
  bool get isLoading => _isLoading;

  // Get user from cache
  UserModel? getUserFromCache(String userId) => _userCache[userId];

  // Get typing status for a specific chat
  bool isTyping(String chatId) => _isTyping[chatId] ?? false;

  // Check if there are more messages to load for a chat
  bool hasMoreMessages(String chatId) => _hasMoreMessages[chatId] ?? false;

  // Check if currently loading more messages for a chat
  bool isLoadingMore(String chatId) => _isLoadingMore[chatId] ?? false;

  // Reset pagination state for a chat (call when entering a new chat)
  void resetPaginationState(String chatId) {
    _lastDocuments[chatId] = null;
    _hasMoreMessages.remove(chatId);
    _isLoadingMore[chatId] = false;
  }

  // Listen to user status changes in real-time
  void _listenToUserStatus(String userId) {
    if (_userStatusListeners.containsKey(userId)) return;

    final subscription = _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.exists) {
            final data = snapshot.data()!;
            final updatedUser = UserModel(
              id: snapshot.id,
              email: data['email'] ?? '',
              displayName: data['displayName'] ?? '',
              isOnline: data['isOnline'] ?? false,
              lastSeen: data['lastSeen'],
            );

            // Update cache
            _userCache[userId] = updatedUser;

            // Notify listeners to update UI
            if (!_isDisposed) {
              notifyListeners();
            }
          }
        });

    _userStatusListeners[userId] = subscription;
  }

  // Stop listening to user status
  void _stopListeningToUserStatus(String userId) {
    _userStatusListeners[userId]?.cancel();
    _userStatusListeners.remove(userId);
  }

  // Clear all user status listeners
  void _clearUserStatusListeners() {
    for (var subscription in _userStatusListeners.values) {
      subscription.cancel();
    }
    _userStatusListeners.clear();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _clearUserStatusListeners();
    super.dispose();
  }

  // Start typing indicator
  Future<void> startTyping(String chatId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    // Cancel existing timer if any
    _typingTimers[chatId]?.cancel();

    // Set typing status to true
    _isTyping[chatId] = true;

    // Only notify listeners if not disposed
    if (!_isDisposed) {
      try {
        notifyListeners();
      } catch (e) {
        // Ignore errors during disposal
      }
    }

    // Update typing status in Firebase
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('typing')
        .doc(currentUserId)
        .set({'isTyping': true, 'timestamp': FieldValue.serverTimestamp()});

    // Set timer to stop typing after 3 seconds of inactivity
    _typingTimers[chatId] = Timer(const Duration(seconds: 1), () {
      stopTyping(chatId);
    });
  }

  // Stop typing indicator
  Future<void> stopTyping(String chatId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    // Cancel timer
    _typingTimers[chatId]?.cancel();

    // Set typing status to false
    _isTyping[chatId] = false;

    // Only notify listeners if not disposed
    if (!_isDisposed) {
      try {
        notifyListeners();
      } catch (e) {
        // Ignore errors during disposal
      }
    }

    // Remove typing status from Firebase
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('typing')
        .doc(currentUserId)
        .delete();
  }

  // Stop typing indicator without notifying listeners (for disposal)
  Future<void> stopTypingSilently(String chatId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    // Cancel timer
    _typingTimers[chatId]?.cancel();

    // Set typing status to false without notifying
    _isTyping[chatId] = false;

    // Remove typing status from Firebase
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('typing')
        .doc(currentUserId)
        .delete();
  }

  // Get typing status stream for a specific chat
  Stream<Map<String, bool>> getTypingStatusStream(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('typing')
        .snapshots()
        .map((snapshot) {
          final typingUsers = <String, bool>{};
          final currentUserId = _auth.currentUser?.uid;

          for (var doc in snapshot.docs) {
            // Don't include current user in the typing list
            if (doc.id != currentUserId) {
              final data = doc.data();
              final isTyping = data['isTyping'] ?? false;
              final timestamp = data['timestamp'] as Timestamp?;

              // Check if typing status is recent (within last 5 seconds)
              if (timestamp != null) {
                final timeDiff = DateTime.now().difference(timestamp.toDate());
                if (timeDiff.inSeconds <= 5) {
                  typingUsers[doc.id] = isTyping;
                }
              }
            }
          }

          return typingUsers;
        });
  }

  // Get all chats for current user with optimized queries
  Stream<List<ChatModel>> getChatsStream() {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return Stream.value([]);

    return _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .asyncMap((snapshot) async {
          List<ChatModel> chats = [];
          Set<String> userIdsToFetch = {};

          // First pass: collect all user IDs we need to fetch
          for (var doc in snapshot.docs) {
            final chatData = doc.data();
            final participants = List<String>.from(
              chatData['participants'] ?? [],
            );

            final otherUserId = participants.firstWhere(
              (id) => id != currentUserId,
              orElse: () => '',
            );

            if (otherUserId.isNotEmpty &&
                !_userCache.containsKey(otherUserId)) {
              userIdsToFetch.add(otherUserId);
            }
          }

          // Batch fetch all user data in one query if needed
          if (userIdsToFetch.isNotEmpty) {
            final userDocs = await _firestore
                .collection('users')
                .where(FieldPath.documentId, whereIn: userIdsToFetch.toList())
                .get();

            for (var doc in userDocs.docs) {
              final userData = doc.data();
              _userCache[doc.id] = UserModel(
                id: doc.id,
                email: userData['email'] ?? '',
                displayName: userData['displayName'] ?? '',
                isOnline: userData['isOnline'] ?? false,
                lastSeen: userData['lastSeen'],
              );
            }
          }

          // Second pass: build chat models using cached user data
          for (var doc in snapshot.docs) {
            final chatData = doc.data();
            final participants = List<String>.from(
              chatData['participants'] ?? [],
            );

            final otherUserId = participants.firstWhere(
              (id) => id != currentUserId,
              orElse: () => '',
            );

            if (otherUserId.isNotEmpty && _userCache.containsKey(otherUserId)) {
              final otherUser = _userCache[otherUserId]!;

              // Start listening to user status changes for real-time updates
              _listenToUserStatus(otherUserId);

              chats.add(
                ChatModel(
                  id: doc.id,
                  participants: participants,
                  otherUser: otherUser,
                  lastMessage: chatData['lastMessage'] ?? '',
                  lastMessageTime: chatData['lastMessageTime'],
                  unreadCount: chatData['unreadCount']?[currentUserId] ?? 0,
                  lastMessageStatus: chatData['lastMessageStatus'] != null
                      ? MessageStatus.values.firstWhere(
                          (status) =>
                              status.toString().split('.').last ==
                              chatData['lastMessageStatus'],
                          orElse: () => MessageStatus.sent,
                        )
                      : null,
                  lastMessageSenderId: chatData['lastMessageSenderId'],
                ),
              );
            }
          }

          // Sort by last message time
          chats.sort((a, b) {
            if (a.lastMessageTime == null && b.lastMessageTime == null) {
              return 0;
            }
            if (a.lastMessageTime == null) {
              return 1;
            }
            if (b.lastMessageTime == null) {
              return -1;
            }
            return b.lastMessageTime!.compareTo(a.lastMessageTime!);
          });

          return chats;
        });
  }

  // Get messages for a specific chat with real-time updates and lazy loading
  Stream<List<MessageModel>> getMessagesStream(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(50) // Increased limit for better initial experience
        .snapshots()
        .map((snapshot) {
          // Only update lazy loading state if it hasn't been set by pagination
          // This prevents the stream from resetting pagination state
          if (snapshot.docs.isNotEmpty && _lastDocuments[chatId] == null) {
            _lastDocuments[chatId] = snapshot.docs.last;
            _hasMoreMessages[chatId] = snapshot.docs.length == 50;
            print(
              'ChatService: Initial pagination state set for $chatId - hasMore=${_hasMoreMessages[chatId]}',
            );
          } else if (snapshot.docs.isEmpty && _lastDocuments[chatId] == null) {
            _hasMoreMessages[chatId] = false;
            print('ChatService: No messages found for $chatId');
          }

          final messages = snapshot.docs.map((doc) {
            final data = doc.data();
            final statusString = data['status'] ?? 'sent';
            final parsedStatus = MessageStatus.values.firstWhere(
              (status) => status.toString().split('.').last == statusString,
              orElse: () => MessageStatus.sent,
            );

            return MessageModel(
              id: doc.id,
              senderId: data['senderId'] ?? '',
              receiverId: data['receiverId'] ?? '',
              text: data['text'] ?? '',
              timestamp: data['timestamp'],
              status: parsedStatus,
              isEdited: data['isEdited'] ?? false,
              reactions: Map<String, String>.from(data['reactions'] ?? {}),
              isEmojiOnly:
                  data['isEmojiOnly'] ??
                  EmojiUtils.isEmojiOnly(data['text'] ?? ''),
              replyTo: data['replyTo'],
            );
          }).toList();

          return messages;
        });
  }

  // Get more messages for lazy loading
  Future<List<MessageModel>> getMoreMessages(String chatId) async {
    if (_isLoadingMore[chatId] == true ||
        !(_hasMoreMessages[chatId] ?? false)) {
      print(
        'ChatService: Skipping getMoreMessages for $chatId - isLoadingMore=${_isLoadingMore[chatId]}, hasMore=${_hasMoreMessages[chatId]}',
      );
      return [];
    }

    print('ChatService: Loading more messages for $chatId');

    _isLoadingMore[chatId] = true;
    notifyListeners();

    try {
      Query query = _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(50);

      final lastDocument = _lastDocuments[chatId];
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snapshot = await query.get();

      // Update lazy loading state
      if (snapshot.docs.isNotEmpty) {
        _lastDocuments[chatId] = snapshot.docs.last;
        _hasMoreMessages[chatId] = snapshot.docs.length == 50;
        print(
          'ChatService: Updated pagination state for $chatId - hasMore=${_hasMoreMessages[chatId]}, docsCount=${snapshot.docs.length}',
        );
      } else {
        _hasMoreMessages[chatId] = false;
        print('ChatService: No more messages for $chatId');
      }

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        return MessageModel(
          id: doc.id,
          senderId: data?['senderId'] ?? '',
          receiverId: data?['receiverId'] ?? '',
          text: data?['text'] ?? '',
          timestamp: data?['timestamp'],
          status: MessageStatus.values.firstWhere(
            (status) =>
                status.toString().split('.').last ==
                (data?['status'] ?? 'sent'),
            orElse: () => MessageStatus.sent,
          ),
          isEdited: data?['isEdited'] ?? false,
          reactions: Map<String, String>.from(data?['reactions'] ?? {}),
          isEmojiOnly:
              data?['isEmojiOnly'] ??
              EmojiUtils.isEmojiOnly(data?['text'] ?? ''),
          replyTo: data?['replyTo'],
        );
      }).toList();
    } finally {
      _isLoadingMore[chatId] = false;
      notifyListeners();
    }
  }

  // Send a message with optimistic updates
  Future<void> sendMessage(
    String chatId,
    String receiverId,
    String text, {
    String? replyTo,
  }) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null || text.trim().isEmpty) return;

    final messageId = _uuid.v4();
    final message = {
      'senderId': currentUserId,
      'receiverId': receiverId,
      'text': text.trim(),
      'timestamp': FieldValue.serverTimestamp(),
      'status': MessageStatus.sent.toString().split('.').last,
      'isEmojiOnly': EmojiUtils.isEmojiOnly(text.trim()),
      if (replyTo != null) 'replyTo': replyTo,
    };

    // Optimistic update - add message to cache immediately
    final optimisticMessage = MessageModel(
      id: messageId,
      senderId: currentUserId,
      receiverId: receiverId,
      text: text.trim(),
      timestamp: Timestamp.now(),
      status: MessageStatus.sent,
      isEmojiOnly: EmojiUtils.isEmojiOnly(text.trim()),
      replyTo: replyTo,
    );

    // Add to cache and notify listeners immediately
    if (_messageCache.containsKey(chatId)) {
      _messageCache[chatId]!.insert(0, optimisticMessage);
      notifyListeners();
    }

    try {
      // Optimized: Add message and update chat metadata simultaneously
      await Future.wait([
        _firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .doc(messageId)
            .set(message),
        _firestore.collection('chats').doc(chatId).update({
          'lastMessage': text.trim(),
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessageStatus': 'sent',
          'lastMessageSenderId': currentUserId,
          'unreadCount.$receiverId': FieldValue.increment(1),
        }),
      ]);
    } catch (e) {
      // Remove optimistic message on error
      if (_messageCache.containsKey(chatId)) {
        _messageCache[chatId]!.removeWhere((msg) => msg.id == messageId);
        notifyListeners();
      }
      rethrow;
    }
  }

  // Create or get existing chat between two users
  Future<String> createOrGetChat(String otherUserId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) throw Exception('User not authenticated');

    // Check if chat already exists
    final existingChats = await _firestore
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .get();

    for (var doc in existingChats.docs) {
      final participants = List<String>.from(doc.data()['participants'] ?? []);
      if (participants.contains(otherUserId)) {
        return doc.id;
      }
    }

    // Create new chat
    final chatId = _uuid.v4();
    await _firestore.collection('chats').doc(chatId).set({
      'participants': [currentUserId, otherUserId],
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessage': '',
      'lastMessageTime': null,
      'unreadCount': {},
    });

    return chatId;
  }

  // Mark messages as delivered when recipient opens chat
  Future<void> markMessagesAsDelivered(String chatId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    // Optimized: Update all sent messages to delivered in one batch operation
    final sentMessages = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'sent')
        .get();

    if (sentMessages.docs.isNotEmpty) {
      final batch = _firestore.batch();

      // Update all messages in batch for better performance
      for (var doc in sentMessages.docs) {
        batch.update(doc.reference, {'status': 'delivered'});
      }

      // Execute batch and update chat metadata simultaneously for faster updates
      await Future.wait([
        batch.commit(),
        _updateChatLastMessageStatus(chatId, MessageStatus.delivered),
      ]);

      // Force immediate UI update
      notifyListeners();

      // Additional notification after a short delay to ensure UI catches up
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_isDisposed) {
          notifyListeners();
        }
      });
    }
  }

  // Helper method to update chat last message status
  Future<void> _updateChatLastMessageStatus(
    String chatId,
    MessageStatus status,
  ) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    final chatDoc = await _firestore.collection('chats').doc(chatId).get();
    final chatData = chatDoc.data();
    if (chatData != null &&
        chatData['lastMessageSenderId'] != currentUserId &&
        chatData['lastMessageStatus'] != status.toString().split('.').last) {
      await _firestore.collection('chats').doc(chatId).update({
        'lastMessageStatus': status.toString().split('.').last,
      });
    }
  }

  // Mark messages as read (only for messages that are visible/seen by user)
  Future<void> markMessagesAsRead(String chatId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    // Optimized: Update only delivered messages to read status
    final deliveredMessages = await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('receiverId', isEqualTo: currentUserId)
        .where('status', isEqualTo: 'delivered')
        .get();

    if (deliveredMessages.docs.isNotEmpty) {
      final batch = _firestore.batch();

      // Update delivered messages to read status in batch
      for (var doc in deliveredMessages.docs) {
        batch.update(doc.reference, {'status': 'read'});
      }

      // Execute batch and update chat metadata simultaneously for faster updates
      await Future.wait([
        batch.commit(),
        _firestore.collection('chats').doc(chatId).update({
          'unreadCount.$currentUserId': 0,
        }),
        _updateChatLastMessageStatus(chatId, MessageStatus.read),
      ]);

      // Force immediate UI update
      notifyListeners();

      // Additional notification after a short delay to ensure UI catches up
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_isDisposed) {
          notifyListeners();
        }
      });
    } else {
      // Still update unread count even if no messages to mark as read
      await _firestore.collection('chats').doc(chatId).update({
        'unreadCount.$currentUserId': 0,
      });
    }
  }

  // Get all users except current user with caching
  Stream<List<UserModel>> getAllUsersStream() {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .where(FieldPath.documentId, isNotEqualTo: currentUserId)
        .snapshots()
        .map((snapshot) {
          final users = snapshot.docs.map((doc) {
            final data = doc.data();
            final user = UserModel(
              id: doc.id,
              email: data['email'] ?? '',
              displayName: data['displayName'] ?? '',
              isOnline: data['isOnline'] ?? false,
              lastSeen: data['lastSeen'],
            );

            // Cache the user
            _userCache[doc.id] = user;

            // Start listening to user status changes for real-time updates
            _listenToUserStatus(doc.id);

            return user;
          }).toList();

          return users;
        });
  }

  // Preload chat data in background
  Future<void> preloadChatData(String chatId) async {
    if (_messageCache.containsKey(chatId) || _loadingChats.contains(chatId)) {
      return;
    }

    _loadingChats.add(chatId);

    try {
      final snapshot = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get();

      final messages = snapshot.docs.map((doc) {
        final data = doc.data();
        return MessageModel(
          id: doc.id,
          senderId: data['senderId'] ?? '',
          receiverId: data['receiverId'] ?? '',
          text: data['text'] ?? '',
          timestamp: data['timestamp'],
          status: MessageStatus.values.firstWhere(
            (status) =>
                status.toString().split('.').last == (data['status'] ?? 'sent'),
            orElse: () => MessageStatus.sent,
          ),
          isEdited: data['isEdited'] ?? false,
          reactions: Map<String, String>.from(data['reactions'] ?? {}),
          isEmojiOnly:
              data['isEmojiOnly'] ?? EmojiUtils.isEmojiOnly(data['text'] ?? ''),
        );
      }).toList();

      _messageCache[chatId] = messages;

      // Update lazy loading state
      if (snapshot.docs.isNotEmpty) {
        _lastDocuments[chatId] = snapshot.docs.last;
        _hasMoreMessages[chatId] = snapshot.docs.length == 20;
      } else {
        _hasMoreMessages[chatId] = false;
      }
    } finally {
      _loadingChats.remove(chatId);
    }
  }

  // Update message status when sender receives read receipt
  Future<void> updateMessageStatus(
    String chatId,
    String messageId,
    MessageStatus status,
  ) async {
    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'status': status.toString().split('.').last});

    // Notify listeners for real-time updates
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  // Real-time status update for new messages
  Future<void> updateNewMessageStatus(String chatId, String messageId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      // Get the specific message
      final messageDoc = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .get();

      if (!messageDoc.exists) return;

      final messageData = messageDoc.data();
      if (messageData == null) return;

      // Check if this message is for the current user and needs status update
      if (messageData['receiverId'] == currentUserId &&
          messageData['senderId'] != currentUserId &&
          messageData['status'] == 'sent') {
        // Only mark as delivered when message is received by the receiver
        await _firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .doc(messageId)
            .update({'status': 'delivered'});

        // Update chat metadata
        await _updateChatLastMessageStatus(chatId, MessageStatus.delivered);

        // Notify listeners
        if (!_isDisposed) {
          notifyListeners();
        }
      }
    } catch (e) {
      // Handle error silently to avoid disrupting the chat experience
    }
  }

  // Edit a message
  Future<void> editMessage(
    String chatId,
    String messageId,
    String newText,
  ) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null || newText.trim().isEmpty) return;

    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
            'text': newText.trim(),
            'isEdited': true,
            'editedAt': FieldValue.serverTimestamp(),
            'isEmojiOnly': EmojiUtils.isEmojiOnly(newText.trim()),
          });

      // Update chat metadata if this is the last message
      final chatDoc = await _firestore.collection('chats').doc(chatId).get();
      final chatData = chatDoc.data();
      if (chatData != null &&
          chatData['lastMessageSenderId'] == currentUserId &&
          chatData['lastMessage'] == chatData['lastMessage']) {
        await _firestore.collection('chats').doc(chatId).update({
          'lastMessage': newText.trim(),
        });
      }

      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  // Delete a message
  Future<void> deleteMessage(String chatId, String messageId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      // Get the message to check if it's the last message
      final messageDoc = await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .get();

      if (!messageDoc.exists) return;

      final messageData = messageDoc.data();
      final isLastMessage =
          messageData?['senderId'] == currentUserId &&
          messageData?['text'] == messageData?['text'];

      // Delete the message
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .delete();

      // Update chat metadata if this was the last message
      if (isLastMessage) {
        final messages = await _firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();

        if (messages.docs.isNotEmpty) {
          final lastMessage = messages.docs.first.data();
          await _firestore.collection('chats').doc(chatId).update({
            'lastMessage': lastMessage['text'] ?? '',
            'lastMessageTime': lastMessage['timestamp'],
            'lastMessageStatus': lastMessage['status'] ?? 'sent',
            'lastMessageSenderId': lastMessage['senderId'] ?? '',
          });
        } else {
          // No messages left, clear chat metadata
          await _firestore.collection('chats').doc(chatId).update({
            'lastMessage': '',
            'lastMessageTime': null,
            'lastMessageStatus': null,
            'lastMessageSenderId': null,
          });
        }
      }

      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  // Clear cache when user logs out
  void clearCache() {
    _userCache.clear();
    _messageCache.clear();
    _chats.clear();
    _messages.clear();
    _loadingChats.clear();
    _lastDocuments.clear();
    _hasMoreMessages.clear();
    _isLoadingMore.clear();
    _isDisposed = true;
  }

  // Add or update reaction to a message
  Future<void> addReaction(
    String chatId,
    String messageId,
    String reaction,
  ) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({'reactions.$currentUserId': reaction});

      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  // Remove reaction from a message
  Future<void> removeReaction(String chatId, String messageId) async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({'reactions.$currentUserId': FieldValue.delete()});

      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }
}
