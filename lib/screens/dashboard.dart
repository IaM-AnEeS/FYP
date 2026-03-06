import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0; // 0 = Home, 1 = AI Chat, 2 = Voice Settings, 3 = Settings

  // Get current Firebase user
  final User? user = FirebaseAuth.instance.currentUser;
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastWords = '';

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
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
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

              // --- Top Buttons Row ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: _buildOptionCard(
                      context,
                      icon: Icons.navigation_outlined,
                      title: "Navigate",
                      subtitle: "Realtime directions",
                      onTap: () {
                        Navigator.pushNamed(context, '/navigation');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildOptionCard(
                      context,
                      icon: Icons.center_focus_strong,
                      title: "Object Detection",
                      subtitle: "Identify objects nearby",
                      onTap: () {
                        Navigator.pushNamed(context, '/detection');
                      },
                    ),
                  ),
                ],
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
              Center(
                child: GestureDetector(
                  onTap: _toggleListening,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: _isListening ? theme.colorScheme.error : theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: _isListening
                          ? [
                              BoxShadow(
                                color: theme.colorScheme.error.withAlpha((0.35 * 0xFF).round()),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ]
                          : [],
                    ),
                    child: Icon(
                      _isListening ? Icons.mic_none : Icons.mic,
                      color: theme.colorScheme.onPrimary,
                      size: 36,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Text(
                  _isListening ? 'Listening...' : "Tap or say 'Hey Vision' to start",
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withAlpha((0.7 * 0xFF).round()),
                  ),
                ),
              ),
              if (_lastWords.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Center(
                    child: Text(
                      'Heard: "$_lastWords"',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ),
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

  // Toggle speech recognition on/off
  Future<void> _toggleListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) => debugPrint('Speech status: $val'),
        onError: (val) => debugPrint('Speech error: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(onResult: (val) {
          setState(() {
            _lastWords = val.recognizedWords;
          });
          if (val.finalResult) {
            // Show recognized final text
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_lastWords)),
            );
          }
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition unavailable')),
        );
      }
    } else {
      await _speech.stop();
      setState(() => _isListening = false);
    }
  }

  // ---------------- CARD BUILDER ----------------
  Widget _buildOptionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 120,
        margin: const EdgeInsets.symmetric(horizontal: 5),
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
