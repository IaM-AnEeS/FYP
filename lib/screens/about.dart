import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color accentColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            theme.appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "About AURA",
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: FadeTransition(
        opacity: _fadeIn,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // App Logo
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withOpacity(0.08),
                ),
                child: Icon(
                  Icons.remove_red_eye_rounded,
                  size: 70,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Blindly - AI Assisted Blind Navigation",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Empowering Vision. Guiding Life.",
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),

              // About Description
              _sectionCard(
                title: "About the App",
                icon: FontAwesomeIcons.circleInfo,
                content:
                    "AURA is an intelligent navigation companion designed for visually impaired users. "
                    "It provides real-time object detection, voice guidance, and environment awareness to help users navigate safely and independently.",
              ),

              _sectionCard(
                title: "Core Features",
                icon: FontAwesomeIcons.star,
                content:
                    "• Real-time obstacle detection using AI camera vision.\n"
                    "• Voice feedback for navigation and object recognition.\n"
                    "• Text reader for reading signs and printed documents.\n"
                    "• Customizable voice settings and speech tone.\n"
                    "• Emergency contact alert feature.",
              ),

              _sectionCard(
                title: "Our Mission",
                icon: FontAwesomeIcons.bullseye,
                content:
                    "To build inclusive technology that enhances independence, "
                    "safety, and confidence for the visually impaired community.",
              ),

              _sectionCard(
                title: "Developer",
                icon: FontAwesomeIcons.userTie,
                content:
                    "Developed by Anees Ahmad — a passionate AI & Flutter developer focused on assistive and impactful technologies.",
              ),

              _sectionCard(
                title: "Contact & Support",
                icon: FontAwesomeIcons.envelope,
                content:
                    "📧 Email: support@auraassist.ai\n🌐 Website: www.auraassist.ai\n☎️ Helpline: +92-300-XXXXXXX",
              ),

              const SizedBox(height: 20),
              _socialLinks(),

              const SizedBox(height: 30),
              Text(
                "Version 1.0.0",
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Reusable Card Widget
  Widget _sectionCard({
    required String title,
    required IconData icon,
    required String content,
  }) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withOpacity(0.88),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _socialLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _socialButton(FontAwesomeIcons.facebookF),
        _socialButton(FontAwesomeIcons.twitter),
        _socialButton(FontAwesomeIcons.instagram),
        _socialButton(FontAwesomeIcons.linkedinIn),
      ],
    );
  }

  Widget _socialButton(IconData icon) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: GestureDetector(
        onTap: () {},
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.primary.withOpacity(0.28),
            ),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 18),
        ),
      ),
    );
  }
}
