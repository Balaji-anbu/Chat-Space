import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class TypingIndicator extends StatefulWidget {
  final String userName;
  final bool isVisible;

  const TypingIndicator({
    super.key,
    required this.userName,
    this.isVisible = true,
  });

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _fadeController;
  late AnimationController _phaseController;
  late AnimationController _slideController;
  late List<Animation<double>> _dotAnimations;
  late Animation<double> _fadeAnimation;
  late Animation<double> _phaseAnimation;
  late Animation<Offset> _slideAnimation;

  // Two simple phases
  final List<String> _typingMessages = ['is typing', 'is still typing...🤔'];

  int _currentPhaseIndex = 0;

  // Single color for dot animations
  final Color _dotColor = Colors.blue[400]!;

  @override
  void initState() {
    super.initState();

    // Main animation controller for dots
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    // Fade in animation controller
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Phase controller - no repeat, just forward
    _phaseController = AnimationController(
      duration: const Duration(milliseconds: 5000), // 5 seconds for "is typing"
      vsync: this,
    );

    // Slide animation controller
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    // Fade animation
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    // Phase animation
    _phaseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _phaseController, curve: Curves.easeInOut),
    );

    // Slide animation - slides up from bottom
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1), // Start from bottom
      end: Offset.zero, // End at normal position
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    // Create three dot animations with different delays and curves
    _dotAnimations = List.generate(3, (index) {
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(
            index * 0.15, // Stagger the animations
            (index + 1) * 0.15,
            curve: Curves.elasticOut,
          ),
        ),
      );
    });

    // Start the animations
    _fadeController.forward();
    _animationController.repeat();

    // Start phase controller with a delay
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        _phaseController.forward(); // Forward only, no repeat
      }
    });

    // Start slide animation if visible
    if (widget.isVisible) {
      _slideController.forward();
    }

    // Listen to phase animation to change phases
    _phaseController.addListener(() {
      if (_phaseController.value >= 1.0 && _currentPhaseIndex == 0) {
        // Switch to "is still typing" after 5 seconds
        setState(() {
          _currentPhaseIndex = 1;
        });
      }
    });
  }

  @override
  void didUpdateWidget(TypingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle visibility changes
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        _slideController.forward();
        _fadeController.forward();
      } else {
        _slideController.reverse();
        _fadeController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fadeController.dispose();
    _phaseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                // Avatar with subtle animation
                AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 1.0 + (0.05 * _animationController.value),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: AppTheme.primaryColor.withOpacity(
                          0.15,
                        ),
                        child: Text(
                          widget.userName.isNotEmpty
                              ? widget.userName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 10),
                // Typing bubble
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Typing text
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${widget.userName} ${_typingMessages[_currentPhaseIndex].replaceAll('🤔', '')}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            if (_currentPhaseIndex == 1)
                              const Text(
                                '🤔',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        // Enhanced animated dots with changing colors
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (index) {
                            return AnimatedBuilder(
                              animation: _dotAnimations[index],
                              builder: (context, child) {
                                // Use current color index for dots
                                Color dotColor = _dotColor;

                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  child: Transform.translate(
                                    offset: Offset(
                                      0,
                                      -6 * _dotAnimations[index].value,
                                    ),
                                    child: Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: dotColor.withOpacity(1.0),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: dotColor.withOpacity(0.6),
                                            blurRadius: 6,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
