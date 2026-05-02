import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../Services/auth_service.dart';
import '../Services/session_service.dart';
import '../Services/voice_assistant_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0; // 0 = Home, 1 = AI Chat, 2 = Voice Settings, 3 = Settings

  // Get current Firebase user
  final User? user = FirebaseAuth.instance.currentUser;
  final VoiceAssistantService _voiceAssistant = VoiceAssistantService.instance;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _accountStatusSubscription;

  @override
  void initState() {
    super.initState();
    _watchAccountStatus();
  }

  @override
  void dispose() {
    _accountStatusSubscription?.cancel();
    super.dispose();
  }

  void _watchAccountStatus() {
    final currentUser = user;
    if (currentUser == null) return;

    _accountStatusSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .snapshots()
        .listen((snapshot) async {
      final status =
          (snapshot.data()?['accountStatus']?.toString() ?? 'active').toLowerCase();

      if (status != 'suspended') return;

      await SessionService.endSession();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(AuthService.suspendedAccountMessage),
        ),
      );

      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    });
  }

  void _onNavTap(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
        // Home - stay on dashboard
        break;
      case 1:
        Navigator.pushNamed(context, '/chat');
        break;
      case 2:
        Navigator.pushNamed(context, '/voice-settings');
        break;
      case 3:
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userName =
        user?.displayName ?? user?.email?.split('@').first ?? "User";
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            theme.appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: GestureDetector(
            onTap: () {
              Navigator.pushNamed(context, '/profile');
            },
            child: CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.surface.withAlpha((0.12 * 0xFF).round()),
              child: Icon(Icons.person, color: theme.colorScheme.onSurface),
            ),
          ),
        ),
        title: Text(
          "Vision Companion",
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      // ---------------- BODY ----------------
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting with Firebase user name
              Text(
                "Hello $userName, how can I assist you today?",
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 25),

              // --- Top Action Card ---
              _buildOptionCard(
                context,
                icon: Icons.center_focus_strong,
                title: "Object Detection",
                subtitle: "AI-powered guidance",
                cardHeight: 165,
                onTap: () {
                  Navigator.pushNamed(context, '/navigation');
                },
              ),
              const SizedBox(height: 20),

              // --- Text Reader Section ---
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pushNamed(context, '/text-reader');
                  },
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.text_fields,
                          color: theme.colorScheme.onSurface,
                          size: 40,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "Text Reader",
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          "Read signs & documents",
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withAlpha((0.7 * 0xFF).round()),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // --- Mic Button Section ---
              _buildVoiceAssistantSection(theme),
            ],
          ),
        ),
      ),

      // ---------------- BOTTOM NAV BAR ----------------
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: theme.colorScheme.surface,
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: theme.colorScheme.onSurface.withAlpha((0.7 * 0xFF).round()),
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onNavTap,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.smart_toy_outlined),
            label: "AI Chat",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic_none),
            label: "Voice Settings",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: "Settings",
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceAssistantSection(ThemeData theme) {
    return ValueListenableBuilder<bool>(
      valueListenable: _voiceAssistant.isListening,
      builder: (context, listening, _) {
        return Column(
          children: [
            Center(
              child: GestureDetector(
                onTap: () => _voiceAssistant.captureCommandNow(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: listening
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    boxShadow: listening
                        ? [
                            BoxShadow(
                              color:
                                  theme.colorScheme.error.withAlpha((0.35 * 0xFF).round()),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ]
                        : [],
                  ),
                  child: Icon(
                    listening ? Icons.mic_none : Icons.mic,
                    color: theme.colorScheme.onPrimary,
                    size: 36,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<String>(
              valueListenable: _voiceAssistant.assistantStateText,
              builder: (context, status, __) {
                return Center(
                  child: Text(
                    listening
                        ? status
                      : 'Tap anywhere or use mic to start voice command',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          theme.colorScheme.onSurface.withAlpha((0.7 * 0xFF).round()),
                    ),
                  ),
                );
              },
            ),
            ValueListenableBuilder<String>(
              valueListenable: _voiceAssistant.lastHeardText,
              builder: (context, heard, __) {
                if (heard.trim().isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Center(
                    child: Text(
                      'Heard: "$heard"',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // ---------------- CARD BUILDER ----------------
  Widget _buildOptionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    double cardHeight = 120,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        height: cardHeight,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: theme.colorScheme.onSurface, size: 36),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
