import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/services/app_lifecycle_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/chat_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/auth_screen.dart';
import 'features/chat/screens/chat_list_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp();

  // Enable Firestore offline persistence with optimized settings
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    sslEnabled: true,
  );

  runApp(ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ChatService()),
        ChangeNotifierProvider(create: (_) => AppLifecycleService()),
      ],
      child: Builder(
        builder: (context) {
          // Connect services
          final authService = Provider.of<AuthService>(context, listen: false);
          final chatService = Provider.of<ChatService>(context, listen: false);
          authService.setChatService(chatService);

          return MaterialApp(
            title: 'Chat App',
            theme: AppTheme.darkTheme,
            themeMode: ThemeMode.dark,
            debugShowCheckedModeBanner: false,
            home: const BrokenAppScreen(),
          );
        },
      ),
    );
  }
}

class BrokenAppScreen extends StatefulWidget {
  const BrokenAppScreen({super.key});

  @override
  State<BrokenAppScreen> createState() => _BrokenAppScreenState();
}

class _BrokenAppScreenState extends State<BrokenAppScreen>
    with TickerProviderStateMixin {
  int tapCount = 0;
  bool showPinDialog = false;
  final TextEditingController _pinController = TextEditingController();
  bool isPinCorrect = false;

  // Animation controllers for different states
  late AnimationController _brokenIconController;
  late AnimationController _messageAnimationController;
  late AnimationController _pulseController;
  late Animation<double> _brokenIconAnimation;
  late Animation<double> _messageAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animation controllers
    _brokenIconController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _messageAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Broken icon animation (pulse effect)
    _brokenIconAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _brokenIconController, curve: Curves.easeInOut),
    );

    // Message animation (bounce and fade)
    _messageAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _messageAnimationController,
        curve: Curves.elasticOut,
      ),
    );

    // Slide animation for message icon
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _messageAnimationController,
            curve: Curves.easeOutBack,
          ),
        );

    // Pulse animation for notification badge
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start animations
    _brokenIconController.repeat(reverse: true);
    _messageAnimationController.forward();
    // Pulse animation will be controlled based on unread messages
  }

  @override
  void dispose() {
    _brokenIconController.dispose();
    _messageAnimationController.dispose();
    _pulseController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _onStayTunedTap() {
    setState(() {
      tapCount++;
      if (tapCount >= 3) {
        showPinDialog = true;
      }
    });
  }

  void _checkPin() {
    if (_pinController.text == "2230") {
      setState(() {
        isPinCorrect = true;
        showPinDialog = false;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect PIN!'),
          backgroundColor: Colors.red,
        ),
      );
      _pinController.clear();
    }
  }

  void _controlPulseAnimation(bool hasUnreadMessages) {
    if (hasUnreadMessages) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isPinCorrect) {
      return const AuthWrapper();
    }

    // Show pin dialog when tap count reaches 10
    if (showPinDialog) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) =>
              PinDialog(controller: _pinController, onCheck: _checkPin),
        );
        setState(() {
          showPinDialog = false;
        });
      });
    }

    return Scaffold(
      backgroundColor: Colors.grey[900],
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Dynamic icon based on unread messages
              Consumer<ChatService>(
                builder: (context, chatService, child) {
                  return StreamBuilder<List<dynamic>>(
                    stream: chatService.getChatsStream(),
                    builder: (context, snapshot) {
                      final chats = snapshot.data ?? [];
                      final hasUnreadMessages = chats.any(
                        (chat) => chat.unreadCount > 0,
                      );

                      // Control pulse animation based on unread messages
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _controlPulseAnimation(hasUnreadMessages);
                      });

                      if (hasUnreadMessages) {
                        // Show message notification animation
                        return SlideTransition(
                          position: _slideAnimation,
                          child: ScaleTransition(
                            scale: _messageAnimation,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/message.png',
                                  width: 150,
                                  height: 150,
                                  fit: BoxFit.contain,
                                ),
                                Positioned(
                                  top: 15,
                                  right: 15,
                                  child: ScaleTransition(
                                    scale: _pulseAnimation,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          chats
                                              .fold<int>(
                                                0,
                                                (sum, chat) =>
                                                    sum +
                                                    (chat.unreadCount as int),
                                              )
                                              .toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      } else {
                        // Show no message image
                        return ScaleTransition(
                          scale: _brokenIconAnimation,
                          child: Image.asset(
                            'assets/Nomessage.png',
                            width: 150,
                            height: 150,
                            fit: BoxFit.contain,
                          ),
                        );
                      }
                    },
                  );
                },
              ),
              const SizedBox(height: 40),

              // Main text
              Text(
                'Our app is broken',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Hidden tap area - the text itself is clickable
              GestureDetector(
                onTap: _onStayTunedTap,
                child: Text(
                  'We\'ll get you soon, Stay tuned',
                  style: TextStyle(fontSize: 20, color: Colors.grey[300]),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Pin Dialog
class PinDialog extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onCheck;

  const PinDialog({super.key, required this.controller, required this.onCheck});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[850],
      title: Text('Enter OTP', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        obscureText: true,
        keyboardType: TextInputType.number,
        style: TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Enter 4-digit OTP',
          hintStyle: TextStyle(color: Colors.grey[400]),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.blue[400]!),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: Colors.grey[400])),
        ),
        ElevatedButton(
          onPressed: () {
            onCheck();
            Navigator.of(context).pop();
          },
          child: Text('Submit OTP'),
        ),
      ],
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize app lifecycle service in next frame to avoid build phase issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appLifecycleService = Provider.of<AppLifecycleService>(
        context,
        listen: false,
      );
      appLifecycleService.initialize();

      // Listen to auth state changes
      final authService = Provider.of<AuthService>(context, listen: false);
      authService.addListener(() {
        appLifecycleService.onUserAuthStateChanged(authService.currentUser);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final appLifecycleService = Provider.of<AppLifecycleService>(
      context,
      listen: false,
    );
    appLifecycleService.onAppLifecycleChanged(state);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        if (authService.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (authService.currentUser != null) {
          return const ChatListScreen();
        }

        return const AuthScreen();
      },
    );
  }
}
