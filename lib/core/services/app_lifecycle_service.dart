import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

class AppLifecycleService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Timer? _onlineStatusTimer;
  bool _isAppActive = true;
  bool _isInitialized = false;
  bool _isOnline = false;
  bool _isConnected = true;

  bool get isAppActive => _isAppActive;
  bool get isOnline => _isOnline;
  bool get isConnected => _isConnected;

  void initialize() {
    if (_isInitialized) return;
    _isInitialized = true;

    // Set up periodic online status updates
    _onlineStatusTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateOnlineStatus();
    });

    // Set initial online status in next frame to avoid build phase issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setUserOnline();
    });
  }

  @override
  void dispose() {
    _onlineStatusTimer?.cancel();
    _onlineStatusTimer = null;
    _isAppActive = false;
    _isInitialized = false;
    _setUserOffline();
    super.dispose();
  }

  // Handle app lifecycle changes
  void onAppLifecycleChanged(AppLifecycleState state) {
    bool wasActive = _isAppActive;

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _isAppActive = false;
        if (wasActive) {
          _setUserOffline();
        }
        break;
      case AppLifecycleState.resumed:
        _isAppActive = true;
        if (!wasActive) {
          _setUserOnline();
        }
        break;
      default:
        break;
    }

    // Use post-frame callback to avoid build phase issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  // Update online status based on current state
  Future<void> _updateOnlineStatus() async {
    final user = _auth.currentUser;
    if (user != null && _isAppActive) {
      await _setUserOnline();
    }
  }

  // Set user as online
  Future<void> _setUserOnline() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        // Check if user document exists, create if it doesn't
        final userDoc = _firestore.collection('users').doc(user.uid);
        final docSnapshot = await userDoc.get();

        if (docSnapshot.exists) {
          await userDoc.update({
            'isOnline': true,
            'lastSeen': FieldValue.serverTimestamp(),
          });
        } else {
          // Create user document if it doesn't exist
          await userDoc.set({
            'uid': user.uid,
            'email': user.email,
            'displayName': user.displayName,
            'isOnline': true,
            'lastSeen': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        _isOnline = true;
        _isConnected = true;

        // Use post-frame callback to avoid build phase issues
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      } catch (e) {
        debugPrint('Error setting user online: $e');
        _isOnline = false;
        _isConnected = false;

        // Use post-frame callback to avoid build phase issues
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });

        // Retry after a delay if it's a network issue
        if (e.toString().contains('network') ||
            e.toString().contains('timeout')) {
          Timer(const Duration(seconds: 5), () {
            if (_isAppActive) {
              _setUserOnline();
            }
          });
        }
      }
    }
  }

  // Set user as offline
  Future<void> _setUserOffline() async {
    final user = _auth.currentUser;
    if (user != null) {
      try {
        final userDoc = _firestore.collection('users').doc(user.uid);
        final docSnapshot = await userDoc.get();

        if (docSnapshot.exists) {
          await userDoc.update({
            'isOnline': false,
            'lastSeen': FieldValue.serverTimestamp(),
          });
        }

        _isOnline = false;
        _isConnected = true;

        // Use post-frame callback to avoid build phase issues
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      } catch (e) {
        debugPrint('Error setting user offline: $e');
        _isOnline = false;
        _isConnected = false;

        // Use post-frame callback to avoid build phase issues
        WidgetsBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
      }
    }
  }

  // Force refresh online status
  Future<void> refreshOnlineStatus() async {
    if (_isAppActive) {
      await _setUserOnline();
    } else {
      await _setUserOffline();
    }
  }

  // Handle user authentication state changes
  void onUserAuthStateChanged(User? user) {
    if (user != null && _isAppActive) {
      // User signed in and app is active
      _setUserOnline();
    } else if (user == null) {
      // User signed out
      _isOnline = false;
      _isConnected = false;

      // Use post-frame callback to avoid build phase issues
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifyListeners();
      });
    }
  }
}
