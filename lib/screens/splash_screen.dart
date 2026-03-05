import 'dart:async';
import 'package:blindly/screens/on_boarding1.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Widget? nextScreen;

  const SplashScreen({super.key, this.nextScreen});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<int> _dotsAnimation;
  int _currentDot = 0;
  Timer? _splashTimer;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();

    // Animation controller for the dots
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );

    // Animate dots (changes every 500ms)
    _dotsAnimation =
        IntTween(begin: 0, end: 3).animate(
          CurvedAnimation(parent: _controller, curve: Curves.linear),
        )..addListener(() {
          setState(() {
            _currentDot = _dotsAnimation.value % 3;
          });
        });

    _controller.repeat(period: const Duration(milliseconds: 500));

    // Navigate after 3 seconds. Keep a reference so we can cancel it on dispose
    _splashTimer = Timer(const Duration(seconds: 3), () {
      if (_isDisposed) return;
      if (!mounted) return;
      try {
        _controller.stop();
      } catch (_) {}
      // If a nextScreen was provided, navigate there, otherwise go to onboarding
      final destination = widget.nextScreen ?? const Onboarding1();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => destination),
      );
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _splashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // Helper to build dots
  Widget _buildDots() {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _currentDot == index
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.3),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          // Centered Logo (use correct asset path)
          Center(
            child: Image.asset(
              'assets/images/logo.png',
              width: 190,
              height: 190,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Show a fallback UI if the asset isn't available
                return Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.visibility,
                    size: 80,
                    color: theme.colorScheme.onPrimary,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          const Spacer(),
          // Animated Dots at Bottom
          Padding(
            padding: const EdgeInsets.only(bottom: 40.0),
            child: _buildDots(),
          ),
        ],
      ),
    );
  }
}
