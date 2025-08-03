import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/models/chat_model.dart';
import '../../../core/models/message_model.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/emoji_utils.dart';
import '../../../core/utils/timestamp_utils.dart';
import '../widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  final ChatModel chat;

  const ChatScreen({super.key, required this.chat});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _messageFocusNode = FocusNode();

  late AnimationController _sendButtonController;
  late Animation<double> _sendButtonScale;
  late AnimationController _editModeController;
  late Animation<double> _editModeAnimation;

  // Reaction animation controllers
  final Map<String, AnimationController> _reactionControllers = {};
  final Map<String, Animation<double>> _reactionAnimations = {};

  bool _hasMarkedAsRead = false;
  bool _isEditMode = false;
  bool _isReplyMode = false;
  MessageModel? _editingMessage;
  MessageModel? _replyingToMessage;
  Timer? _refreshTimer;

  // Typing indicator variables
  Map<String, bool> _typingUsers = {};
  StreamSubscription<Map<String, bool>>? _typingSubscription;
  ChatService? _chatService;
  Timer? _typingDebounceTimer;
  bool _showTypingIndicator = false;

  // Lazy loading variables
  List<MessageModel> _allMessages = [];
  bool _isLoadingMore = false;
  int _loadingDotsCount = 0;
  Timer? _loadingAnimationTimer;
  late AnimationController _loadingPulseController;
  late Animation<double> _loadingPulseAnimation;
  double _lastScrollPosition = 0;
  bool _isScrollingUp = false;

  // Track previous reactions for notifications
  final Map<String, Map<String, String>> _previousReactions = {};

  // Real-time message status monitoring
  StreamSubscription<List<MessageModel>>? _messageStatusSubscription;
  final List<MessageModel> _lastProcessedMessages = [];

  // Track which messages have been marked as read
  final Set<String> _readMessages = {};

  // Track if there are unread messages when user is scrolled up
  bool _hasUnreadMessages = false;

  @override
  void initState() {
    super.initState();
    _sendButtonController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _sendButtonScale = Tween<double>(begin: 1.0, end: 0.8).animate(
      CurvedAnimation(parent: _sendButtonController, curve: Curves.easeInOut),
    );

    _editModeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _editModeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _editModeController, curve: Curves.easeInOut),
    );

    // Initialize loading pulse animation
    _loadingPulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _loadingPulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _loadingPulseController, curve: Curves.easeInOut),
    );

    // Preload chat data and mark messages as read when entering chat
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatService = Provider.of<ChatService>(context, listen: false);

      // Reset pagination state for this chat
      chatService.resetPaginationState(widget.chat.id);

      // Preload chat data in background
      chatService.preloadChatData(widget.chat.id);

      // Mark messages as delivered immediately when entering chat
      if (!_hasMarkedAsRead) {
        _hasMarkedAsRead = true;
        chatService.markMessagesAsDelivered(widget.chat.id).catchError((error) {
          // Error handling for marking messages as delivered
        });
      }

      // Set up real-time message status monitoring
      _setupMessageStatusMonitoring();
    });

    // Listen to chat service changes to force UI updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatService = Provider.of<ChatService>(context, listen: false);
      chatService.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
    });

    // Set up periodic refresh to ensure UI stays in sync and mark visible messages as read
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        setState(() {});

        // Periodically mark visible messages as read
        _markMessagesAsReadWhenVisible();
      }
    });

    // Listen to typing status
    _setupTypingListener();

    // Set up scroll listener for lazy loading
    _setupScrollListener();

    // Set up reaction monitoring for animations only
    _setupReactionMonitoring();
  }

  @override
  void dispose() {
    // Stop typing indicator when leaving the chat (silently to avoid widget tree issues)
    _chatService?.stopTypingSilently(widget.chat.id);

    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    _sendButtonController.dispose();
    _editModeController.dispose();
    _loadingPulseController.dispose();
    _refreshTimer?.cancel();
    _typingSubscription?.cancel();
    _typingDebounceTimer?.cancel();
    _messageStatusSubscription?.cancel();
    _loadingAnimationTimer?.cancel();

    // Dispose reaction animations
    for (final controller in _reactionControllers.values) {
      controller.dispose();
    }
    _reactionControllers.clear();
    _reactionAnimations.clear();

    // Clear lazy loading state
    _allMessages.clear();
    _isLoadingMore = false;
    _loadingDotsCount = 0;
    _lastScrollPosition = 0;
    _isScrollingUp = false;
    _lastProcessedMessages.clear();
    _readMessages.clear();

    super.dispose();
  }

  void _setupTypingListener() {
    _chatService = Provider.of<ChatService>(context, listen: false);
    _typingSubscription = _chatService!
        .getTypingStatusStream(widget.chat.id)
        .listen((typingUsers) {
          if (mounted) {
            // Cancel previous timer
            _typingDebounceTimer?.cancel();

            // Check if anyone is actually typing
            final hasTypingUsers = typingUsers.values.any(
              (isTyping) => isTyping,
            );

            if (hasTypingUsers) {
              // Show typing indicator immediately if someone is typing
              setState(() {
                _typingUsers = typingUsers;
                _showTypingIndicator = true;
              });
            } else {
              // Delay hiding the typing indicator to prevent flickering
              _typingDebounceTimer = Timer(
                const Duration(milliseconds: 1000),
                () {
                  if (mounted) {
                    setState(() {
                      _typingUsers = typingUsers;
                      _showTypingIndicator = false;
                    });
                  }
                },
              );
            }
          }
        });
  }

  void _setupScrollListener() {
    _scrollController.addListener(() {
      final currentPosition = _scrollController.position.pixels;
      final maxScrollExtent = _scrollController.position.maxScrollExtent;

      // In reverse ListView:
      // - currentPosition = 0 means we're at the bottom (newest messages)
      // - currentPosition = maxScrollExtent means we're at the top (oldest messages)

      // Detect if user is scrolling towards older messages (towards maxScrollExtent)
      if (currentPosition > _lastScrollPosition) {
        _isScrollingUp = true; // Scrolling towards older messages
      } else {
        _isScrollingUp = false;
      }
      _lastScrollPosition = currentPosition;

      // Only trigger loading if we have a valid scroll extent
      if (maxScrollExtent > 0) {
        // Load more messages when user scrolls to the top (oldest messages)
        // Check if we're near the top of the scroll (oldest messages)
        if (currentPosition >= maxScrollExtent - 200) {
          // Load immediately when user scrolls to the top (oldest messages)
          _loadMoreMessages();
        }

        // Also trigger loading when user is near the top (within 300 pixels from top)
        if (currentPosition >= maxScrollExtent - 300 &&
            currentPosition < maxScrollExtent - 200) {
          // Pre-load more messages when approaching the top
          _loadMoreMessages();
        }

        // Additional trigger: if user is scrolling towards older messages and near the top
        if (_isScrollingUp && currentPosition >= maxScrollExtent - 400) {
          _loadMoreMessages();
        }

        // Smooth scroll behavior: maintain scroll position when new messages are loaded
        if (_isLoadingMore && _isScrollingUp) {
          // Keep the scroll position stable during loading
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              // Maintain the current scroll position during loading
              final currentExtent = _scrollController.position.maxScrollExtent;
              if (currentExtent > maxScrollExtent) {
                // Adjust scroll position to account for new messages
                final newPosition =
                    currentPosition + (currentExtent - maxScrollExtent);
                if (newPosition >= 0) {
                  _scrollController.jumpTo(newPosition);
                }
              }
            }
          });
        }
      }

      // Debug: Print scroll position for understanding
      if (maxScrollExtent > 0 &&
          _isScrollingUp &&
          currentPosition >= maxScrollExtent - 500) {
        print(
          'Scroll Debug: currentPosition=$currentPosition, maxScrollExtent=$maxScrollExtent, distanceFromTop=${maxScrollExtent - currentPosition}',
        );
      }

      // Mark messages as read when user scrolls and messages are visible
      _markMessagesAsReadWhenVisible();

      // Hide unread indicator when user scrolls to bottom
      if (currentPosition <= 100 && _hasUnreadMessages) {
        setState(() {
          _hasUnreadMessages = false;
        });
      }
    });
  }

  void _scrollToBottom({bool animate = true}) {
    if (_scrollController.hasClients) {
      if (animate) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 3500),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(0);
      }

      // Mark messages as read when scrolling to bottom (user has seen the messages)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _markMessagesAsReadWhenVisible();
      });
    }
  }

  void _setupReactionMonitoring() {
    // Monitor reactions for animations only (data updates handled by StreamBuilder)
    _refreshTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        _checkForReactionAnimations();
      }
    });
  }

  void _setupMessageStatusMonitoring() {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null) return;

    // Listen to messages stream and monitor for new messages that need status updates
    _messageStatusSubscription = chatService.getMessagesStream(widget.chat.id).listen((
      messages,
    ) {
      if (!mounted) return;

      // Check for new messages that need status updates
      for (final message in messages) {
        // Only process messages sent by the other user that need status updates
        if (message.senderId != currentUserId &&
            message.receiverId == currentUserId &&
            message.status == MessageStatus.sent) {
          // Check if we've already processed this message
          final messageKey = '${message.id}_${message.status}';
          if (!_lastProcessedMessages.any(
            (m) => '${m.id}_${m.status}' == messageKey,
          )) {
            // Use the more efficient method for real-time status updates
            chatService.updateNewMessageStatus(widget.chat.id, message.id);

            // Track this message as processed
            _lastProcessedMessages.add(message);

            // Keep only the last 50 processed messages to prevent memory leaks
            if (_lastProcessedMessages.length > 50) {
              _lastProcessedMessages.removeAt(0);
            }
          }
        }
      }
    });
  }

  // Mark messages as read when they come into view
  void _markMessagesAsReadWhenVisible() {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == null || !_scrollController.hasClients) return;

    // Get visible messages that need to be marked as read
    final messagesToMarkAsRead = <String>[];

    for (final message in _allMessages) {
      // Only mark messages from others as read
      if (message.senderId != currentUserId &&
          message.receiverId == currentUserId &&
          message.status == MessageStatus.delivered &&
          !_readMessages.contains(message.id)) {
        messagesToMarkAsRead.add(message.id);
        _readMessages.add(message.id);
      }
    }

    // Mark messages as read if any found
    if (messagesToMarkAsRead.isNotEmpty) {
      chatService.markMessagesAsRead(widget.chat.id);
    }
  }

  void _checkForReactionAnimations() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    for (final message in _allMessages) {
      final messageId = message.id;
      final currentReactions = message.reactions;
      final previousReactions = _previousReactions[messageId] ?? {};

      // Check for new reactions for animation purposes
      for (final entry in currentReactions.entries) {
        final userId = entry.key;
        final emoji = entry.value;

        // Skip if it's your own reaction
        if (userId == currentUserId) continue;

        // Check if this is a new reaction
        if (previousReactions[userId] != emoji) {
          _animateNewReaction(message, emoji);
        }
      }

      // Check for removed reactions
      for (final entry in previousReactions.entries) {
        final userId = entry.key;
        final emoji = entry.value;

        // Skip if it's your own reaction
        if (userId == currentUserId) continue;

        // Check if this reaction was removed
        if (!currentReactions.containsKey(userId) ||
            currentReactions[userId] != emoji) {
          _animateReactionRemoval(message, emoji);
        }
      }

      // Update previous reactions
      _previousReactions[messageId] = Map.from(currentReactions);
    }
  }

  void _animateNewReaction(MessageModel message, String emoji) {
    final reactionKey = '${message.id}_$emoji';

    // Create animation controller if it doesn't exist
    if (!_reactionControllers.containsKey(reactionKey)) {
      _reactionControllers[reactionKey] = AnimationController(
        duration: const Duration(milliseconds: 400),
        vsync: this,
      );
      _reactionAnimations[reactionKey] = Tween<double>(begin: 0.0, end: 1.0)
          .animate(
            CurvedAnimation(
              parent: _reactionControllers[reactionKey]!,
              curve: Curves.elasticOut,
            ),
          );
    }

    // Animate the new reaction with a bounce effect
    _reactionControllers[reactionKey]!.forward().then((_) {
      // Add a small bounce effect
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_reactionControllers.containsKey(reactionKey)) {
          _reactionControllers[reactionKey]!.reverse().then((_) {
            _reactionControllers[reactionKey]!.forward();
          });
        }
      });
    });
  }

  void _animateReactionRemoval(MessageModel message, String emoji) {
    final reactionKey = '${message.id}_$emoji';

    if (_reactionControllers.containsKey(reactionKey)) {
      // Animate the removal with a fade out effect
      _reactionControllers[reactionKey]!.reverse().then((_) {
        // Clean up the controller after animation
        if (_reactionControllers.containsKey(reactionKey)) {
          _reactionControllers[reactionKey]!.dispose();
          _reactionControllers.remove(reactionKey);
          _reactionAnimations.remove(reactionKey);
        }
      });
    }
  }

  void _animateReactionCountChange(MessageModel message, String emoji) {
    final reactionKey = '${message.id}_$emoji';

    if (_reactionControllers.containsKey(reactionKey)) {
      // Add a subtle pulse animation for count changes
      _reactionControllers[reactionKey]!.forward().then((_) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_reactionControllers.containsKey(reactionKey)) {
            _reactionControllers[reactionKey]!.reverse().then((_) {
              _reactionControllers[reactionKey]!.forward();
            });
          }
        });
      });
    }
  }

  void _startLoadingAnimation() {
    _loadingAnimationTimer?.cancel();
    _loadingAnimationTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) {
      if (mounted) {
        setState(() {
          _loadingDotsCount = (_loadingDotsCount + 1) % 4;
        });
      }
    });
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore ||
        !(_chatService?.hasMoreMessages(widget.chat.id) ?? false)) {
      print(
        'Skipping load more: isLoadingMore=$_isLoadingMore, hasMore=${_chatService?.hasMoreMessages(widget.chat.id)}',
      );
      return;
    }

    print('Loading more messages for chat ${widget.chat.id}');
    setState(() {
      _isLoadingMore = true;
    });

    // Start loading animation immediately
    _startLoadingAnimation();
    _loadingPulseController.repeat(reverse: true);

    try {
      final moreMessages = await _chatService!.getMoreMessages(widget.chat.id);
      if (moreMessages.isNotEmpty) {
        setState(() {
          // Add messages to the end of the list (which appears at the top in reverse ListView)
          _allMessages.addAll(moreMessages);
        });
      }
    } catch (e) {
      // Handle error silently or show a snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading more messages: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingMore = false;
      });
      // Stop loading animation
      _loadingAnimationTimer?.cancel();
      _loadingDotsCount = 0;
      _loadingPulseController.stop();
    }
  }

  void _enterEditMode(MessageModel message) {
    setState(() {
      _isEditMode = true;
      _editingMessage = message;
      _messageController.text = message.text;
    });
    _editModeController.forward();
    _messageController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _messageController.text.length,
    );
  }

  void _exitEditMode() {
    setState(() {
      _isEditMode = false;
      _editingMessage = null;
      _messageController.clear();
    });
    _editModeController.reverse();

    // Stop typing indicator when exiting edit mode
    _chatService?.stopTyping(widget.chat.id);

    // Keep keyboard open when exiting edit mode - don't unfocus
    // This allows users to continue typing without interruption
  }

  void _enterReplyMode(MessageModel message) {
    setState(() {
      _isReplyMode = true;
      _replyingToMessage = message;
      _messageController.clear();
    });
    _messageFocusNode.requestFocus();
  }

  void _exitReplyMode() {
    setState(() {
      _isReplyMode = false;
      _replyingToMessage = null;
      _messageController.clear();
    });
    _chatService?.stopTyping(widget.chat.id);
    // Keep keyboard open when exiting reply mode - don't unfocus
    // This allows users to continue typing without interruption
  }

  Future<void> _updateMessage() async {
    if (_editingMessage == null || _messageController.text.trim().isEmpty) {
      _exitEditMode();
      return;
    }

    final newText = _messageController.text.trim();
    if (newText == _editingMessage!.text) {
      _exitEditMode();
      return;
    }

    // Exit edit mode immediately for instant feedback
    _exitEditMode();

    // Update message in background
    _updateMessageInBackground(newText);
  }

  Future<void> _updateMessageInBackground(String newText) async {
    try {
      // Stop typing indicator when updating message (non-blocking)
      _chatService?.stopTyping(widget.chat.id);

      await _chatService?.editMessage(
        widget.chat.id,
        _editingMessage!.id,
        newText,
      );
    } catch (e) {
      // Show error but don't block the UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating message: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Future<void> _deleteMessage(MessageModel message) async {
    try {
      await Provider.of<ChatService>(
        context,
        listen: false,
      ).deleteMessage(widget.chat.id, message.id);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting message: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  void _showMessageOptions(
    MessageModel message,
    bool isMe,
    GlobalKey messageKey,
  ) {
    // Get the position of the specific message bubble
    final RenderBox? renderBox =
        messageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    // Calculate position for the dropdown with better handling for small messages
    double left, top;
    final screenWidth = MediaQuery.of(context).size.width;
    final menuWidth = 180.0;
    final menuHeight = 120.0; // Approximate height for 2-3 items

    if (isMe) {
      // Our messages are on the right, show dropdown to the left
      // For small messages, position the menu to the left of the message
      if (size.width < 100) {
        // Small message: position menu to the left with some margin
        left = offset.dx - menuWidth - 10;
      } else {
        // Larger message: position relative to message width
        left = offset.dx + size.width * 0.2;
      }
      top = offset.dy - menuHeight - 10; // Position above with margin
    } else {
      // Other's messages are on the left, show dropdown to the right
      // For small messages, position the menu to the right of the message
      if (size.width < 100) {
        // Small message: position menu to the right with some margin
        left = offset.dx + size.width + 10;
      } else {
        // Larger message: position relative to message width
        left = offset.dx + size.width * 0.8;
      }
      top = offset.dy - menuHeight - 10; // Position above with margin
    }

    // Ensure the menu doesn't go off screen
    if (left < 16) left = 16;
    if (left + menuWidth > screenWidth - 16) {
      left = screenWidth - menuWidth - 16;
    }

    // Use Overlay instead of showMenu to avoid interfering with keyboard
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Invisible overlay to catch taps outside the menu
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                overlayEntry.remove();
              },
              child: Container(color: Colors.transparent),
            ),
          ),
          // The actual message options menu
          Positioned(
            left: left,
            top: top,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 180,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[850]
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMessageOptionItem(
                      'reply',
                      Icons.reply,
                      'Reply',
                      Colors.blue,
                      message,
                      isMe,
                      messageKey,
                      overlayEntry,
                    ),
                    if (!isMe)
                      _buildMessageOptionItem(
                        'react',
                        Icons.emoji_emotions,
                        'React',
                        Colors.orange,
                        message,
                        isMe,
                        messageKey,
                        overlayEntry,
                      ),
                    if (isMe) ...[
                      _buildMessageOptionItem(
                        'edit',
                        Icons.edit,
                        'Edit Message',
                        Colors.blue,
                        message,
                        isMe,
                        messageKey,
                        overlayEntry,
                      ),
                      _buildMessageOptionItem(
                        'delete',
                        Icons.delete,
                        'Delete Message',
                        Colors.red,
                        message,
                        isMe,
                        messageKey,
                        overlayEntry,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(overlayEntry);
  }

  Widget _buildMessageOptionItem(
    String value,
    IconData icon,
    String text,
    Color color,
    MessageModel message,
    bool isMe,
    GlobalKey messageKey,
    OverlayEntry overlayEntry,
  ) {
    return GestureDetector(
      onTap: () {
        overlayEntry.remove(); // Remove the overlay

        // Handle the action
        if (value == 'reply') {
          _enterReplyMode(message);
        } else if (value == 'react') {
          _showReactionPicker(message, isMe, messageKey);
        } else if (value == 'edit') {
          _enterEditMode(message);
        } else if (value == 'delete') {
          _deleteMessage(message);
        }

        // Ensure keyboard stays open after menu interaction
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _messageFocusNode.requestFocus();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionPicker(
    MessageModel message,
    bool isMe,
    GlobalKey messageKey,
  ) {
    // Only allow reactions to messages from others (not your own messages)
    if (isMe) return;

    // Get the position of the specific message bubble
    final RenderBox? renderBox =
        messageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    // Calculate position for the reaction picker with better handling for small messages
    double left, top;
    final screenWidth = MediaQuery.of(context).size.width;
    final pickerWidth = 280.0;
    final pickerHeight = 120.0; // Approximate height for 2 rows of emojis

    // Show reaction picker above the message
    if (size.width < 100) {
      // Small message: center the picker on screen
      left = (screenWidth - pickerWidth) / 2;
    } else {
      // Larger message: center the picker on the message
      left = offset.dx + size.width * 0.5 - pickerWidth * 0.5;
    }
    top = offset.dy - pickerHeight - 10; // Position above with margin

    // Ensure the picker doesn't go off screen
    if (left < 16) left = 16;
    if (left + pickerWidth > screenWidth - 16) {
      left = screenWidth - pickerWidth - 16;
    }

    // Use Overlay instead of showDialog to avoid interfering with keyboard
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Invisible overlay to catch taps outside the reaction picker
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                overlayEntry.remove();
              },
              child: Container(color: Colors.transparent),
            ),
          ),
          // The actual reaction picker
          Positioned(
            left: left,
            top: top,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[850]
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // First row of emojis
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildReactionItemOverlay(
                            '❤️',
                            message,
                            overlayEntry,
                          ),
                          _buildReactionItemOverlay(
                            '👍',
                            message,
                            overlayEntry,
                          ),
                          _buildReactionItemOverlay(
                            '👎',
                            message,
                            overlayEntry,
                          ),
                          _buildReactionItemOverlay(
                            '😂',
                            message,
                            overlayEntry,
                          ),
                          _buildReactionItemOverlay(
                            '😮',
                            message,
                            overlayEntry,
                          ),
                          _buildReactionItemOverlay(
                            '😢',
                            message,
                            overlayEntry,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Second row of emojis
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildReactionItemOverlay(
                            '😍',
                            message,
                            overlayEntry,
                          ),
                          _buildReactionItemOverlay(
                            '😭',
                            message,
                            overlayEntry,
                          ),
                          _buildReactionItemOverlay(
                            '😡',
                            message,
                            overlayEntry,
                          ),
                          _buildReactionItemOverlay(
                            '🤔',
                            message,
                            overlayEntry,
                          ),
                          _buildReactionItemOverlay(
                            '👏',
                            message,
                            overlayEntry,
                          ),
                          _buildReactionItemOverlay(
                            '🙏',
                            message,
                            overlayEntry,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    overlay.insert(overlayEntry);
  }

  Widget _buildReactionItemOverlay(
    String emoji,
    MessageModel message,
    OverlayEntry overlayEntry,
  ) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final hasReacted = message.reactions[currentUserId] == emoji;

    return GestureDetector(
      onTap: () {
        overlayEntry.remove(); // Remove the overlay
        _addReaction(message, emoji);
        // Ensure keyboard stays open after reaction
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _messageFocusNode.requestFocus();
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: hasReacted
              ? AppTheme.primaryColor.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }

  Widget _buildReactionItem(String emoji, MessageModel message) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final hasReacted = message.reactions[currentUserId] == emoji;

    return GestureDetector(
      onTap: () {
        Navigator.of(context).pop(); // Close the dialog
        _addReaction(message, emoji);
        // Ensure keyboard stays open after reaction
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _messageFocusNode.requestFocus();
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: hasReacted
              ? AppTheme.primaryColor.withOpacity(0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
    );
  }

  Future<void> _addReaction(MessageModel message, String reaction) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    // Create animation for this reaction
    final reactionKey = '${message.id}_$reaction';
    if (!_reactionControllers.containsKey(reactionKey)) {
      _reactionControllers[reactionKey] = AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      );
      _reactionAnimations[reactionKey] = Tween<double>(begin: 0.0, end: 1.0)
          .animate(
            CurvedAnimation(
              parent: _reactionControllers[reactionKey]!,
              curve: Curves.elasticOut,
            ),
          );
    }

    try {
      // Check if user already reacted with this emoji
      if (message.reactions[currentUserId] == reaction) {
        // Remove reaction if same emoji
        await Provider.of<ChatService>(
          context,
          listen: false,
        ).removeReaction(widget.chat.id, message.id);

        // Animate removal
        await _reactionControllers[reactionKey]!.reverse();
      } else {
        // Add or update reaction
        await Provider.of<ChatService>(
          context,
          listen: false,
        ).addReaction(widget.chat.id, message.id, reaction);

        // Animate addition
        _reactionControllers[reactionKey]!.forward();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding reaction: $e'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  Widget _buildReactionsDisplay(MessageModel message) {
    // Group reactions by emoji
    final Map<String, List<String>> groupedReactions = {};
    message.reactions.forEach((userId, emoji) {
      if (!groupedReactions.containsKey(emoji)) {
        groupedReactions[emoji] = [];
      }
      groupedReactions[emoji]!.add(userId);
    });

    if (groupedReactions.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: groupedReactions.entries.map((entry) {
          final emoji = entry.key;
          final count = entry.value.length;
          final currentUserId = FirebaseAuth.instance.currentUser?.uid;
          final hasReacted = message.reactions[currentUserId] == emoji;
          final reactionKey = '${message.id}_$emoji';

          // Initialize animation if not exists
          if (!_reactionControllers.containsKey(reactionKey)) {
            _reactionControllers[reactionKey] = AnimationController(
              duration: const Duration(milliseconds: 300),
              vsync: this,
            );
            _reactionAnimations[reactionKey] =
                Tween<double>(begin: 0.0, end: 1.0).animate(
                  CurvedAnimation(
                    parent: _reactionControllers[reactionKey]!,
                    curve: Curves.elasticOut,
                  ),
                );

            // Start animation if reaction exists
            if (count > 0) {
              _reactionControllers[reactionKey]!.forward();
            }
          }

          return AnimatedBuilder(
            animation: _reactionAnimations[reactionKey]!,
            builder: (context, child) {
              return Transform.scale(
                scale: _reactionAnimations[reactionKey]!.value,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: hasReacted
                        ? AppTheme.primaryColor.withOpacity(0.2)
                        : Colors.grey[700]?.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: hasReacted
                        ? Border.all(
                            color: AppTheme.primaryColor.withOpacity(0.4),
                            width: 1.5,
                          )
                        : Border.all(
                            color:
                                Colors.grey[600]?.withOpacity(0.3) ??
                                Colors.transparent,
                            width: 1,
                          ),
                    boxShadow: hasReacted
                        ? [
                            BoxShadow(
                              color: AppTheme.primaryColor.withOpacity(0.2),
                              blurRadius: 6,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                  child: GestureDetector(
                    onTap: message.senderId == currentUserId
                        ? null // No action for your own messages
                        : () {
                            _addReaction(message, emoji);
                            // Ensure keyboard stays open after reaction
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _messageFocusNode.requestFocus();
                              }
                            });
                          },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(emoji, style: const TextStyle(fontSize: 14)),
                        if (count > 1) ...[
                          const SizedBox(width: 3),
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 9,
                              color: hasReacted
                                  ? AppTheme.primaryColor
                                  : Colors.grey[400],
                              fontWeight: FontWeight.w600,
                            ),
                            child: Text(count.toString()),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Keep keyboard open when tapping outside - don't dismiss it
        // This allows users to continue typing without interruption
      },
      child: WillPopScope(
        onWillPop: () async {
          // Keep keyboard open when back button is pressed, only navigate back
          // Don't dismiss keyboard unless user explicitly closes it
          return true; // Allow normal back navigation
        },
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                Hero(
                  tag: 'chat_${widget.chat.id}',
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                    child: Text(
                      widget.chat.otherUser.displayName.isNotEmpty
                          ? widget.chat.otherUser.displayName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.chat.otherUser.displayName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Consumer<ChatService>(
                        builder: (context, chatService, child) {
                          // Get real-time user data from cache
                          final otherUser =
                              chatService.getUserFromCache(
                                widget.chat.otherUser.id,
                              ) ??
                              widget.chat.otherUser;

                          return Row(
                            children: [
                              if (otherUser.isOnline)
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              const SizedBox(width: 4),
                              Text(
                                otherUser.isOnline
                                    ? 'Online'
                                    : otherUser.lastSeen != null
                                    ? 'Last seen ${TimestampUtils.formatLastSeen(otherUser.lastSeen!.toDate())}'
                                    : 'Offline',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: otherUser.isOnline
                                      ? Colors.green
                                      : Colors.grey[500],
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
            actions: [],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: StreamBuilder<List<MessageModel>>(
                      stream: Provider.of<ChatService>(
                        context,
                        listen: false,
                      ).getMessagesStream(widget.chat.id),
                      builder: (context, snapshot) {
                        // Don't show loading indicator, just show empty state or messages
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
                                  'Error loading messages',
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

                        final initialMessages = snapshot.data ?? [];
                        final currentUserId =
                            FirebaseAuth.instance.currentUser?.uid;

                        // Update all messages when initial messages change or new messages arrive
                        if (initialMessages.isNotEmpty) {
                          final previousMessageCount = _allMessages.length;

                          // Only replace messages if we haven't loaded additional messages through pagination
                          // or if this is the initial load
                          if (_allMessages.isEmpty) {
                            _allMessages = List.from(initialMessages);
                          } else {
                            // Check if we have loaded more messages through pagination
                            final hasLoadedMoreMessages =
                                _allMessages.length > initialMessages.length;

                            if (!hasLoadedMoreMessages) {
                              // Only update if we haven't loaded additional messages
                              // This preserves paginated messages
                              _allMessages = List.from(initialMessages);
                            } else {
                              // If we have paginated messages, only update the first batch
                              // and preserve the additional messages
                              final firstBatchMessages = initialMessages
                                  .take(50)
                                  .toList();
                              final additionalMessages = _allMessages
                                  .skip(50)
                                  .toList();
                              _allMessages = [
                                ...firstBatchMessages,
                                ...additionalMessages,
                              ];
                            }
                          }

                          // Auto-scroll to bottom if new messages arrive and user is at bottom
                          if (initialMessages.length > previousMessageCount &&
                              _scrollController.hasClients &&
                              _scrollController.position.pixels <= 100) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _scrollToBottom();
                            });
                          } else if (initialMessages.length >
                              previousMessageCount) {
                            // If new messages arrive but user is not at bottom, show unread indicator
                            if (_scrollController.hasClients &&
                                _scrollController.position.pixels > 100) {
                              setState(() {
                                _hasUnreadMessages = true;
                              });
                            }
                            // Still mark as read since they might be visible in the current view
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _markMessagesAsReadWhenVisible();
                            });
                          }

                          // Mark messages as read when new messages are loaded
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            _markMessagesAsReadWhenVisible();
                          });
                        }

                        if (_allMessages.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'No messages yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Start the conversation!',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.all(16),
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          itemCount:
                              _allMessages.length +
                              (_isLoadingMore ? 1 : 0) +
                              (_showTypingIndicator && _typingUsers.isNotEmpty
                                  ? 1
                                  : 0),
                          itemBuilder: (context, index) {
                            // Show loading indicator at the top when loading more
                            if (_isLoadingMore &&
                                index == _allMessages.length) {
                              return Container(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: AnimatedBuilder(
                                    animation: _loadingPulseAnimation,
                                    builder: (context, child) {
                                      return Transform.scale(
                                        scale: _loadingPulseAnimation.value,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Animated loading indicator with dots
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Loading',
                                                  style: TextStyle(
                                                    color: Colors.grey[500],
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                // Animated dots
                                                Row(
                                                  children: List.generate(3, (
                                                    index,
                                                  ) {
                                                    return AnimatedOpacity(
                                                      opacity:
                                                          index <
                                                              _loadingDotsCount
                                                          ? 1.0
                                                          : 0.3,
                                                      duration: const Duration(
                                                        milliseconds: 200,
                                                      ),
                                                      child: Container(
                                                        margin:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 1,
                                                            ),
                                                        child: Text(
                                                          '.',
                                                          style: TextStyle(
                                                            color: AppTheme
                                                                .primaryColor,
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            // Progress indicator
                                            SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(AppTheme.primaryColor),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              );
                            }

                            // Show typing indicator at the bottom (since list is reversed)
                            if (_showTypingIndicator &&
                                _typingUsers.isNotEmpty &&
                                index == 0) {
                              return _typingUsers.entries.map((entry) {
                                final userId = entry.key;
                                final isTyping = entry.value;

                                if (isTyping) {
                                  // Get the user name for the typing indicator
                                  String userName = 'Someone';
                                  if (userId == widget.chat.otherUser.id) {
                                    userName =
                                        widget.chat.otherUser.displayName;
                                  }

                                  return TypingIndicator(
                                    key: ValueKey('typing_$userId'),
                                    userName: userName,
                                    isVisible: true,
                                  );
                                }
                                return const SizedBox.shrink();
                              }).first;
                            }

                            // Adjust index for messages since typing indicator takes one slot
                            final adjustedIndex =
                                _showTypingIndicator && _typingUsers.isNotEmpty
                                ? index - 1
                                : index;
                            final message = _allMessages[adjustedIndex];
                            final isMe = message.senderId == currentUserId;
                            final messageKey = GlobalKey();

                            return _buildMessageBubble(
                              message,
                              isMe,
                              adjustedIndex,
                              messageKey,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  _buildMessageInput(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(
    MessageModel message,
    bool isMe,
    int index,
    GlobalKey messageKey,
  ) {
    final isEmojiOnly = message.isEmojiOnly;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isMe && !isEmojiOnly) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
              child: Text(
                widget.chat.otherUser.displayName.isNotEmpty
                    ? widget.chat.otherUser.displayName[0].toUpperCase()
                    : '?',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: _buildSlideToReplyMessage(
              message,
              isMe,
              messageKey,
              isEmojiOnly,
            ),
          ),
          if (isMe && !isEmojiOnly) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildEmojiMessage(
    MessageModel message,
    bool isMe,
    GlobalKey messageKey,
  ) {
    return Container(
      key: messageKey,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.text,
            style: TextStyle(
              fontSize: EmojiUtils.getEmojiFontSize(message.text),
              height: 1.2, // Better line height for emojis
            ),
            textAlign: TextAlign.center,
          ),
          // Show reactions for emoji-only messages
          if (message.reactions.isNotEmpty) _buildReactionsDisplay(message),
        ],
      ),
    );
  }

  Widget _buildRegularMessage(
    MessageModel message,
    bool isMe,
    GlobalKey messageKey,
  ) {
    return Container(
      key: messageKey,
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isMe ? AppTheme.primaryColor : Colors.grey[800],
        borderRadius: BorderRadius.circular(20).copyWith(
          bottomLeft: isMe
              ? const Radius.circular(20)
              : const Radius.circular(4),
          bottomRight: isMe
              ? const Radius.circular(4)
              : const Radius.circular(20),
        ),
      ),
      child: IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reply preview if this message is a reply
            if (message.replyTo != null) _buildReplyPreview(message, isMe),
            Text(
              message.text,
              style: TextStyle(
                color: isMe ? Colors.white : AppTheme.darkOnSurfaceColor,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message.timestamp != null
                          ? TimestampUtils.formatMessageTime(
                              message.timestamp!.toDate(),
                            )
                          : '',
                      style: TextStyle(
                        fontSize: 12,
                        color: isMe
                            ? Colors.white.withOpacity(0.7)
                            : Colors.grey[400],
                      ),
                    ),
                    if (message.isEdited) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit,
                        size: 12,
                        color: isMe
                            ? Colors.white.withOpacity(0.6)
                            : Colors.grey[500],
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'edited',
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: isMe
                              ? Colors.white.withOpacity(0.6)
                              : Colors.grey[500],
                        ),
                      ),
                    ],
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        _getStatusIcon(message.status),
                        size: 14,
                        color: _getStatusColor(message.status, isMe),
                      ),
                    ],
                  ],
                ),
                if (message.reactions.isNotEmpty)
                  _buildReactionsDisplay(message),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sent:
        return Icons.done; // Single tick for sent
      case MessageStatus.delivered:
        return Icons.done_all; // Double tick for delivered
      case MessageStatus.read:
        return Icons.done_all; // Double tick for read
    }
  }

  Color _getStatusColor(MessageStatus status, bool isMe) {
    if (!isMe)
      return Colors.transparent; // Don't show ticks for received messages

    switch (status) {
      case MessageStatus.sent:
        return Colors.grey; // Grey single tick for sent
      case MessageStatus.delivered:
        return Colors.grey; // Grey double tick for delivered
      case MessageStatus.read:
        return Colors.blue; // Blue double tick for read (WhatsApp style)
    }
  }

  Widget _buildSlideToReplyMessage(
    MessageModel message,
    bool isMe,
    GlobalKey messageKey,
    bool isEmojiOnly,
  ) {
    return Dismissible(
      key: ValueKey(message.id),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {
        DismissDirection.startToEnd: 0.1, // 50% threshold
      },
      confirmDismiss: (direction) async {
        // Enter reply mode when swiped
        _enterReplyMode(message);
        return false; // Don't dismiss the message
      },
      background: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            const SizedBox(width: 20),
            Icon(Icons.reply, color: Colors.blue, size: 24),
            const SizedBox(width: 12),
            Text(
              'Reply',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      child: GestureDetector(
        onLongPress: () {
          // Show reaction picker for others' messages, options menu for own messages
          if (isMe) {
            _showMessageOptions(message, isMe, messageKey);
          } else {
            _showReactionPicker(message, isMe, messageKey);
          }
        },
        onLongPressStart: (_) {
          // Add haptic feedback
          HapticFeedback.mediumImpact();
        },
        child: isEmojiOnly
            ? _buildEmojiMessage(message, isMe, messageKey)
            : _buildRegularMessage(message, isMe, messageKey),
      ),
    );
  }

  Widget _buildReplyPreview(MessageModel message, bool isMe) {
    // Find the replied message
    final repliedMessage = _allMessages.firstWhere(
      (msg) => msg.id == message.replyTo,
      orElse: () => MessageModel(
        id: '',
        senderId: '',
        receiverId: '',
        text: 'Message not found',
        status: MessageStatus.sent,
      ),
    );

    final isRepliedMessageFromMe =
        repliedMessage.senderId == FirebaseAuth.instance.currentUser?.uid;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withOpacity(0.2)
            : Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: isMe ? Colors.white : Colors.grey, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.reply,
                size: 12,
                color: isMe ? Colors.white.withOpacity(0.7) : Colors.grey[400],
              ),
              const SizedBox(width: 4),
              Text(
                isRepliedMessageFromMe
                    ? 'You'
                    : widget.chat.otherUser.displayName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isMe
                      ? Colors.white.withOpacity(0.8)
                      : Colors.grey[300],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            repliedMessage.text,
            style: TextStyle(
              fontSize: 12,
              color: isMe ? Colors.white.withOpacity(0.7) : Colors.grey[400],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return AnimatedBuilder(
      animation: _editModeAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              if (_isEditMode)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 16, color: AppTheme.primaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Editing message',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _exitEditMode,
                        child: Icon(
                          Icons.close,
                          size: 18,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isReplyMode && _replyingToMessage != null)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.reply, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Replying to ${_replyingToMessage!.senderId == FirebaseAuth.instance.currentUser?.uid ? 'yourself' : widget.chat.otherUser.displayName}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _replyingToMessage!.text,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.withOpacity(0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _exitReplyMode,
                        child: Icon(Icons.close, size: 18, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        // Only focus the text field when specifically tapped
                        _messageFocusNode.requestFocus();
                      },
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                        decoration: InputDecoration(
                          hintText: _isEditMode
                              ? 'Edit message...'
                              : _isReplyMode
                              ? 'Reply to message...'
                              : 'Type a message...',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onChanged: (value) {
                          // Start typing indicator when user starts typing
                          if (value.isNotEmpty) {
                            _chatService?.startTyping(widget.chat.id);
                          } else {
                            // Stop typing indicator when text field is empty
                            _chatService?.stopTyping(widget.chat.id);
                          }
                        },
                        onSubmitted: (value) {
                          // Send message when user presses enter
                          if (value.trim().isNotEmpty) {
                            _sendMessage();
                          }
                        },
                        onTapOutside: (event) {
                          // Keep keyboard open when tapping outside
                          // Don't unfocus the text field to maintain keyboard visibility
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _messageController,
                    builder: (context, child) {
                      final hasText = _messageController.text.trim().isNotEmpty;
                      return ScaleTransition(
                        scale: _sendButtonScale,
                        child: GestureDetector(
                          onTapDown: (_) => _sendButtonController.forward(),
                          onTapUp: (_) => _sendButtonController.reverse(),
                          onTapCancel: () => _sendButtonController.reverse(),
                          child: GestureDetector(
                            onTap: hasText
                                ? (_isEditMode ? _updateMessage : _sendMessage)
                                : null,
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: hasText
                                    ? AppTheme.primaryColor
                                    : Colors.grey[300],
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _isEditMode ? Icons.check : Icons.send,
                                color: hasText
                                    ? Colors.white
                                    : Colors.grey[600],
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              // Floating action button to scroll to bottom when there are unread messages
              if (_hasUnreadMessages &&
                  _scrollController.hasClients &&
                  _scrollController.position.pixels > 100)
                Positioned(
                  right: 16,
                  bottom: 100, // Position above the message input
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: AppTheme.primaryColor,
                    onPressed: () {
                      _scrollToBottom();
                      setState(() {
                        _hasUnreadMessages = false;
                      });
                    },
                    child: const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // Clear the text field immediately for instant feedback
    _messageController.clear();

    // Always scroll to bottom when sending a message
    _scrollToBottom();

    // Send message in background without blocking UI
    _sendMessageInBackground(text);
  }

  Future<void> _sendMessageInBackground(String text) async {
    try {
      // Stop typing indicator when sending message (non-blocking)
      _chatService?.stopTyping(widget.chat.id);

      // Send message without waiting for UI updates
      await _chatService?.sendMessage(
        widget.chat.id,
        widget.chat.otherUser.id,
        text,
        replyTo: _replyingToMessage?.id,
      );

      // Exit reply mode after sending
      if (_isReplyMode) {
        _exitReplyMode();
      }
    } catch (e) {
      // Show error but don't block the UI
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }
}
