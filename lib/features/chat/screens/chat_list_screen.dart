import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_model.dart';
import '../../../core/models/message_model.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/timestamp_utils.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () => _navigateToNewChat(),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _handleLogout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Consumer<ChatService>(
          builder: (context, chatService, child) {
            return StreamBuilder<List<ChatModel>>(
              stream: chatService.getChatsStream(),
              builder: (context, snapshot) {
                // Don't show loading indicator, just show content or empty state
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading chats',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {});
                          },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final chats = snapshot.data ?? [];

                if (chats.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No chats yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start a conversation with someone',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _navigateToNewChat(),
                          icon: const Icon(Icons.add),
                          label: const Text('New Chat'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: chats.length,
                  itemBuilder: (context, index) {
                    final chat = chats[index];
                    return _buildChatTile(chat, index);
                  },
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToNewChat(),
        child: const Icon(Icons.chat),
      ),
    );
  }

  Widget _buildChatTile(ChatModel chat, int index) {
    return Hero(
      tag: 'chat_${chat.id}',
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: InkWell(
          onTap: () => _navigateToChat(chat),
          onHover: (isHovered) {
            // Preload chat data when hovering
            if (isHovered) {
              Provider.of<ChatService>(
                context,
                listen: false,
              ).preloadChatData(chat.id);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                  child: Text(
                    chat.otherUser.displayName.isNotEmpty
                        ? chat.otherUser.displayName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              chat.otherUser.displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (chat.unreadCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                chat.unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    chat.lastMessage.isNotEmpty
                                        ? chat.lastMessage
                                        : 'No messages yet',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: chat.unreadCount > 0
                                          ? AppTheme.darkOnSurfaceColor
                                          : Colors.grey[400],
                                      fontWeight: chat.unreadCount > 0
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                // Show tick status if last message is from current user
                                if (chat.lastMessageSenderId ==
                                        FirebaseAuth
                                            .instance
                                            .currentUser
                                            ?.uid &&
                                    chat.lastMessageStatus != null)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Icon(
                                      _getStatusIcon(chat.lastMessageStatus),
                                      size: 12,
                                      color: _getStatusColor(
                                        chat.lastMessageStatus,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (chat.lastMessageTime != null)
                            Text(
                              _formatTimestamp(chat.lastMessageTime!),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Consumer<ChatService>(
                        builder: (context, chatService, child) {
                          // Get real-time user data from cache
                          final realTimeUser =
                              chatService.getUserFromCache(chat.otherUser.id) ??
                              chat.otherUser;

                          return Row(
                            children: [
                              if (realTimeUser.isOnline)
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              const SizedBox(width: 4),
                              Text(
                                realTimeUser.isOnline
                                    ? 'Online'
                                    : realTimeUser.lastSeen != null
                                    ? 'Last seen ${TimestampUtils.formatLastSeen(realTimeUser.lastSeen!.toDate())}'
                                    : 'Offline',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: realTimeUser.isOnline
                                      ? Colors.green
                                      : Colors.grey[400],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';

    DateTime dateTime;
    if (timestamp is DateTime) {
      dateTime = timestamp;
    } else {
      dateTime = timestamp.toDate();
    }

    return TimestampUtils.formatChatListTime(dateTime);
  }

  IconData _getStatusIcon(MessageStatus? status) {
    if (status == null) return Icons.done;
    switch (status) {
      case MessageStatus.sent:
        return Icons.done; // Single tick for sent
      case MessageStatus.delivered:
        return Icons.done_all; // Double tick for delivered
      case MessageStatus.read:
        return Icons.done_all; // Double tick for read
    }
  }

  Color _getStatusColor(MessageStatus? status) {
    if (status == null) return Colors.grey[400]!;
    switch (status) {
      case MessageStatus.sent:
        return Colors.grey[400]!; // Grey single tick for sent
      case MessageStatus.delivered:
        return Colors.grey[400]!; // Grey double tick for delivered
      case MessageStatus.read:
        return Colors.blue; // Blue double tick for read (WhatsApp style)
    }
  }

  void _navigateToChat(ChatModel chat) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ChatScreen(chat: chat),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _navigateToNewChat() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const NewChatScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeInOutCubic;

          var tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await Provider.of<AuthService>(context, listen: false).signOut();
    }
  }
}
