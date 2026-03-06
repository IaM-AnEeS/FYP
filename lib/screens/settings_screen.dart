import 'package:flutter/material.dart';
import '../theme/theme_manager.dart';
import '../theme/color_scheme_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  bool darkMode = true;
  double voiceVolume = 0.6;
  double feedbackSpeed = 0.5;
  String language = 'English';
  String defaultMode = 'Navigation';
  bool vibrationFeedback = true;
  bool obstacleAlerts = true;
  bool voiceTips = true;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // initialize the local toggle to reflect the current app theme
    darkMode = ThemeManager.themeMode.value == ThemeMode.dark;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary,
        elevation: 0,
        title: Text(
          "Settings",
          style: TextStyle(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: theme.colorScheme.onPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildSectionTitle("APPEARANCE"),
                // Theme selector: System / Light / Dark
                Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      title: const Text('Use system theme'),
                      value: ThemeMode.system,
                      groupValue: ThemeManager.themeMode.value,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {});
                        ThemeManager.setThemeMode(v);
                      },
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text('Light'),
                      value: ThemeMode.light,
                      groupValue: ThemeManager.themeMode.value,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {});
                        ThemeManager.setThemeMode(v);
                      },
                    ),
                    RadioListTile<ThemeMode>(
                      title: const Text('Dark'),
                      value: ThemeMode.dark,
                      groupValue: ThemeManager.themeMode.value,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() {});
                        ThemeManager.setThemeMode(v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                buildSectionTitle("COLOR SCHEME"),
                buildColorPickerTile(),
                const SizedBox(height: 20),
                buildSectionTitle("ACCESSIBILITY"),
                buildSliderTile(
                  icon: Icons.volume_up,
                  title: "Voice Volume",
                  value: voiceVolume,
                  onChanged: (val) => setState(() => voiceVolume = val),
                ),
                buildSliderTile(
                  icon: Icons.speed,
                  title: "Feedback Speed",
                  value: feedbackSpeed,
                  onChanged: (val) => setState(() => feedbackSpeed = val),
                ),
                buildSwitchTile(
                  icon: Icons.vibration,
                  title: "Vibration Feedback",
                  value: vibrationFeedback,
                  onChanged: (val) => setState(() => vibrationFeedback = val),
                ),
                buildSwitchTile(
                  icon: Icons.warning_amber_rounded,
                  title: "Obstacle Alerts",
                  value: obstacleAlerts,
                  onChanged: (val) => setState(() => obstacleAlerts = val),
                ),
                buildSwitchTile(
                  icon: Icons.record_voice_over,
                  title: "Voice Tips",
                  value: voiceTips,
                  onChanged: (val) => setState(() => voiceTips = val),
                ),
                const SizedBox(height: 20),
                buildSectionTitle("LANGUAGE"),
                buildSettingTile(
                  icon: Icons.language,
                  title: "Language",
                  subtitle: language,
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: theme.colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(20),
                        ),
                      ),
                      builder: (_) => buildLanguageSheet(),
                    );
                  },
                ),
                const SizedBox(height: 20),
                buildSectionTitle("GENERAL"),
                buildSettingTile(
                  icon: Icons.explore,
                  title: "Default Mode",
                  subtitle: defaultMode,
                  onTap: () {
                    setState(() {
                      defaultMode = defaultMode == 'Navigation'
                          ? 'Object Detection'
                          : 'Navigation';
                    });
                  },
                ),
                buildSettingTile(
                  icon: Icons.contact_emergency,
                  title: "Emergency Contact",
                  subtitle: "Set Up",
                  iconColor: theme.colorScheme.error,
                  onTap: () {},
                ),
                buildSettingTile(
                  icon: Icons.info_outline,
                  title: "About AURA",
                  subtitle: "Version 1.0.0",
                  onTap: () {},
                ),
                const SizedBox(height: 30),
                Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      height: 55,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withOpacity(0.25),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          "Save Settings",
                          style: TextStyle(
                            fontSize: 16,
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(3),
    );
  }

  // Build Bottom Navigation Bar
  BottomNavigationBar _buildBottomNav(int selectedIndex) {
    final theme = Theme.of(context);
    return BottomNavigationBar(
      backgroundColor: theme.colorScheme.surface,
      selectedItemColor: theme.colorScheme.primary,
      unselectedItemColor: theme.colorScheme.onSurface.withOpacity(0.7),
      type: BottomNavigationBarType.fixed,
      currentIndex: selectedIndex,
      onTap: (index) {
        switch (index) {
          case 0:
            Navigator.pushNamed(context, '/dashboard');
            break;
          case 1:
            Navigator.pushNamed(context, '/chat');
            break;
          case 2:
            Navigator.pushNamed(context, '/voice-settings');
            break;
          case 3:
            // Already on Settings
            break;
        }
      },
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
          activeIcon: Icon(Icons.settings),
          label: "Settings",
        ),
      ],
    );
  }

  // Section Title
  Widget buildSectionTitle(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.onSurface.withOpacity(0.7),
          fontWeight: FontWeight.w600,
          fontSize: 14,
          letterSpacing: 1,
        ),
      ),
    );
  }

  // Slider Tile
  Widget buildSliderTile({
    required IconData icon,
    required String title,
    required double value,
    required Function(double) onChanged,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: theme.iconTheme.color),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: theme.colorScheme.primary,
              thumbColor: theme.colorScheme.primary,
            ),
            child: Slider(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  // Switch Tile
  Widget buildSwitchTile({
    required IconData icon,
    required String title,
    required bool value,
    required Function(bool) onChanged,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.iconTheme.color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: theme.colorScheme.primary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  // Simple Setting Tile
  Widget buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? theme.iconTheme.color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: theme.colorScheme.onSurface.withOpacity(0.3),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  // Bottom Sheet for Language
  Widget buildLanguageSheet() {
    final languages = ['English', 'Urdu', 'Arabic', 'Spanish', 'German'];
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 15),
        Container(
          height: 4,
          width: 40,
          color: theme.colorScheme.onSurface.withOpacity(0.12),
        ),
        const SizedBox(height: 20),
        Text(
          "Choose Language",
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 10),
        ...languages.map(
          (lang) => ListTile(
            title: Text(
              lang,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withOpacity(0.8),
                fontSize: 16,
              ),
            ),
            trailing: lang == language
                ? Icon(Icons.check, color: theme.colorScheme.primary)
                : null,
            onTap: () {
              setState(() => language = lang);
              Navigator.pop(context);
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // Color Picker Tile
  Widget buildColorPickerTile() {
    final theme = Theme.of(context);
    final presetColors = [
      const Color(0xFF003D73), // Brand deep blue (from attachment)
      Colors.black,
      Colors.blue,
      Colors.green,
      Colors.purple,
      Colors.red,
      Colors.orange,
      Colors.teal,
    ];

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.palette, color: theme.iconTheme.color),
              const SizedBox(width: 12),
              Text(
                "Primary Color",
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              ...presetColors.map((color) {
                return GestureDetector(
                  onTap: () async {
                    await ColorSchemeManager.setPrimaryColor(color);
                    if (mounted) setState(() {});
                  },
                  child: ValueListenableBuilder<Color>(
                    valueListenable: ColorSchemeManager.primaryColor,
                    builder: (context, currentColor, _) {
                      final isSelected = currentColor.value == color.value;
                      return Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : Colors.transparent,
                            width: 3,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withOpacity(0.4),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : [],
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                color: color.computeLuminance() > 0.5
                                    ? Colors.black
                                    : Colors.white,
                                size: 24,
                              )
                            : null,
                      );
                    },
                  ),
                );
              }),
              GestureDetector(
                onTap: () async {
                  await ColorSchemeManager.resetToDefault();
                  if (mounted) setState(() {});
                },
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.onSurface.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.refresh,
                    color: theme.colorScheme.onSurface,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

