import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../Services/voice_assistant_service.dart';
import '../theme/theme_manager.dart';
import '../theme/color_scheme_manager.dart';

enum _SettingsVoiceCommandType {
  customerSupport,
  goHome,
  saveSettings,
  lightTheme,
  darkTheme,
  colorBlue,
  colorGreen,
  colorBlack,
  colorPurple,
  colorRed,
  colorOrange,
  unknown,
}

class SettingsScreen extends StatefulWidget {
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  final VoiceAssistantService _voiceAssistant = VoiceAssistantService.instance;
  final stt.SpeechToText _localSpeech = stt.SpeechToText();

  static const Duration _commandListenFor = Duration(seconds: 6);
  static const Duration _commandPauseFor = Duration(seconds: 2);

  static const List<String> _customerSupportCommands = <String>[
    'go to customer support',
    'open customer support',
    'customer support',
    'support chat',
    'open support',
  ];

  static const List<String> _goHomeCommands = <String>[
    'go home',
    'go to home',
    'home screen',
    'dashboard',
    'go to dashboard',
    'open home',
  ];

  static const List<String> _saveSettingsCommands = <String>[
    'save settings',
    'save the settings',
    'save setting',
  ];

  bool darkMode = true;
  bool _isListeningForCommand = false;
  bool _isHandlingCommand = false;
  bool _localSpeechReady = false;

    String _commandStatus =
      'Tap anywhere and say a settings command like change to blue color or go to customer support.';
  String _lastHeardCommand = '';

  Timer? _commandTimeoutTimer;

  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    SettingsScreen.isActive.value = true;
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
    SettingsScreen.isActive.value = false;
    _commandTimeoutTimer?.cancel();
    _commandTimeoutTimer = null;
    unawaited(_localSpeech.stop());
    _controller.dispose();
    super.dispose();
  }

  String _normalizeCommandText(String rawText) {
    return rawText
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _containsAnyPhrase(String normalized, List<String> phrases) {
    for (final phrase in phrases) {
      if (normalized.contains(phrase)) {
        return true;
      }
    }
    return false;
  }

  bool _isColorCommand(String normalized, String color) {
    final hasColorWord =
        normalized.contains('color') || normalized.contains('colour');
    final hasChangeCue =
        normalized.contains('change') ||
            normalized.contains('chnage') ||
            normalized.contains('set') ||
            normalized.contains('make');

    if (!normalized.contains(color)) return false;
    return hasColorWord || hasChangeCue;
  }

  _SettingsVoiceCommandType _parseSettingsVoiceCommand(String rawText) {
    final normalized = _normalizeCommandText(rawText);

    if (normalized.isEmpty) {
      return _SettingsVoiceCommandType.unknown;
    }

    if (_containsAnyPhrase(normalized, _customerSupportCommands)) {
      return _SettingsVoiceCommandType.customerSupport;
    }

    if (_containsAnyPhrase(normalized, _goHomeCommands)) {
      return _SettingsVoiceCommandType.goHome;
    }

    if (_containsAnyPhrase(normalized, _saveSettingsCommands)) {
      return _SettingsVoiceCommandType.saveSettings;
    }

    if (normalized.contains('light theme') ||
        normalized.contains('change to light theme')) {
      return _SettingsVoiceCommandType.lightTheme;
    }

    if (normalized.contains('dark theme') ||
        normalized.contains('change to dark theme')) {
      return _SettingsVoiceCommandType.darkTheme;
    }

    if (_isColorCommand(normalized, 'blue')) {
      return _SettingsVoiceCommandType.colorBlue;
    }

    if (_isColorCommand(normalized, 'green')) {
      return _SettingsVoiceCommandType.colorGreen;
    }

    if (_isColorCommand(normalized, 'black')) {
      return _SettingsVoiceCommandType.colorBlack;
    }

    if (_isColorCommand(normalized, 'purple')) {
      return _SettingsVoiceCommandType.colorPurple;
    }

    if (_isColorCommand(normalized, 'red')) {
      return _SettingsVoiceCommandType.colorRed;
    }

    if (_isColorCommand(normalized, 'orange')) {
      return _SettingsVoiceCommandType.colorOrange;
    }

    return _SettingsVoiceCommandType.unknown;
  }

  Future<void> _saveSettings({bool speakFeedback = false}) async {
    if (!mounted) return;

    setState(() {
      _commandStatus = 'Settings saved.';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved.')),
    );

    if (speakFeedback) {
      await _voiceAssistant.speak(
        'Settings saved.',
        resumeWakeListening: false,
        forceWhenDisabled: true,
      );
    }
  }

  Future<void> _applyColorChange({
    required Color color,
    required String colorName,
  }) async {
    await ColorSchemeManager.setPrimaryColor(color);
    if (!mounted) return;

    setState(() {
      _commandStatus = 'Changed to $colorName color.';
    });

    await _voiceAssistant.speak(
      'Changed to $colorName color.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );
  }

  Future<void> _startLocalSettingsCommandMode() async {
    if (_isListeningForCommand || _isHandlingCommand) return;

    if (!Platform.isAndroid) {
      if (!mounted) return;
      setState(() {
        _commandStatus =
            'Local voice command on Settings is available on Android only.';
      });
      return;
    }

    final granted = await _voiceAssistant.requestMicrophonePermission();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _commandStatus =
            'Microphone permission is required for Settings voice command.';
      });
      await _voiceAssistant.speak(
        'Microphone permission is required for settings voice commands.',
        resumeWakeListening: false,
        forceWhenDisabled: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isListeningForCommand = true;
      _isHandlingCommand = false;
      _lastHeardCommand = '';
      _commandStatus = 'Tell me your settings command.';
    });

    await _voiceAssistant.speak(
      'Tell me your settings command.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    if (!mounted || !_isListeningForCommand) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _listenForLocalSettingsCommand();
  }

  Future<void> _listenForLocalSettingsCommand() async {
    if (!_isListeningForCommand || !mounted) return;

    if (!_localSpeechReady) {
      _localSpeechReady = await _localSpeech.initialize(
        onStatus: _onLocalSpeechStatus,
        onError: _onLocalSpeechError,
        debugLogging: false,
      );
    }

    if (!_localSpeechReady) {
      if (!mounted) return;
      setState(() {
        _isListeningForCommand = false;
        _commandStatus =
            'Voice recognition is unavailable on this device right now.';
      });
      return;
    }

    _commandTimeoutTimer?.cancel();
    _commandTimeoutTimer = Timer(
      _commandListenFor + const Duration(seconds: 1),
      () {
        unawaited(_finishLocalSettingsListening(noCommandHeard: true));
      },
    );

    try {
      await _localSpeech.listen(
        onResult: _onLocalSpeechResult,
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        listenFor: _commandListenFor,
        pauseFor: _commandPauseFor,
        localeId: 'en_US',
      );

      if (!mounted) return;
      setState(() {
        _commandStatus =
            'Listening... say color, theme, customer support, go home, or save settings.';
      });
    } catch (_) {
      await _finishLocalSettingsListening(
        noCommandHeard: false,
        customStatus: 'Could not start listening. Tap and try again.',
      );
    }
  }

  void _onLocalSpeechResult(dynamic result) {
    final heardText = result.recognizedWords.trim();
    if (heardText.isEmpty || !mounted || !_isListeningForCommand) {
      return;
    }

    setState(() {
      _lastHeardCommand = heardText;
    });

    final command = _parseSettingsVoiceCommand(heardText);

    if (command != _SettingsVoiceCommandType.unknown && !_isHandlingCommand) {
      _isHandlingCommand = true;
      unawaited(_handleParsedSettingsCommand(command));
      return;
    }

    if (result.finalResult && !_isHandlingCommand) {
      unawaited(
        _finishLocalSettingsListening(
          noCommandHeard: false,
          customStatus:
              'Command not recognized. Try color/theme/go home/customer support/save settings.',
        ),
      );
    }
  }

  void _onLocalSpeechStatus(String status) {
    if (!_isListeningForCommand || _isHandlingCommand) return;
    if (status == 'done' || status == 'notListening') {
      unawaited(_finishLocalSettingsListening(noCommandHeard: true));
    }
  }

  void _onLocalSpeechError(dynamic error) {
    if (!_isListeningForCommand || _isHandlingCommand) return;
    unawaited(
      _finishLocalSettingsListening(
        noCommandHeard: false,
        customStatus: 'Could not understand command. Tap and try again.',
      ),
    );
  }

  Future<void> _handleParsedSettingsCommand(
    _SettingsVoiceCommandType command,
  ) async {
    await _finishLocalSettingsListening(
      noCommandHeard: false,
      customStatus: 'Applying settings command...',
    );

    try {
      switch (command) {
        case _SettingsVoiceCommandType.customerSupport:
          await _voiceAssistant.speak(
            'Opening customer support.',
            resumeWakeListening: false,
            forceWhenDisabled: true,
          );
          if (!mounted) return;
          Navigator.pushNamed(context, '/customer-support');
          break;
        case _SettingsVoiceCommandType.goHome:
          await _voiceAssistant.speak(
            'Going to home screen.',
            resumeWakeListening: false,
            forceWhenDisabled: true,
          );
          if (!mounted) return;
          Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (_) => false);
          break;
        case _SettingsVoiceCommandType.saveSettings:
          await _saveSettings(speakFeedback: true);
          break;
        case _SettingsVoiceCommandType.lightTheme:
          await ThemeManager.setThemeMode(ThemeMode.light);
          if (mounted) {
            setState(() {
              darkMode = false;
              _commandStatus = 'Changed to light theme.';
            });
          }
          await _voiceAssistant.speak(
            'Changed to light theme.',
            resumeWakeListening: false,
            forceWhenDisabled: true,
          );
          break;
        case _SettingsVoiceCommandType.darkTheme:
          await ThemeManager.setThemeMode(ThemeMode.dark);
          if (mounted) {
            setState(() {
              darkMode = true;
              _commandStatus = 'Changed to dark theme.';
            });
          }
          await _voiceAssistant.speak(
            'Changed to dark theme.',
            resumeWakeListening: false,
            forceWhenDisabled: true,
          );
          break;
        case _SettingsVoiceCommandType.colorBlue:
          await _applyColorChange(color: Colors.blue, colorName: 'blue');
          break;
        case _SettingsVoiceCommandType.colorGreen:
          await _applyColorChange(color: Colors.green, colorName: 'green');
          break;
        case _SettingsVoiceCommandType.colorBlack:
          await _applyColorChange(color: Colors.black, colorName: 'black');
          break;
        case _SettingsVoiceCommandType.colorPurple:
          await _applyColorChange(color: Colors.purple, colorName: 'purple');
          break;
        case _SettingsVoiceCommandType.colorRed:
          await _applyColorChange(color: Colors.red, colorName: 'red');
          break;
        case _SettingsVoiceCommandType.colorOrange:
          await _applyColorChange(color: Colors.orange, colorName: 'orange');
          break;
        case _SettingsVoiceCommandType.unknown:
          break;
      }
    } finally {
      _isHandlingCommand = false;
    }
  }

  Future<void> _finishLocalSettingsListening({
    required bool noCommandHeard,
    String? customStatus,
  }) async {
    _commandTimeoutTimer?.cancel();
    _commandTimeoutTimer = null;

    if (_localSpeech.isListening) {
      try {
        await _localSpeech.stop();
      } catch (_) {
        // Keep screen stable if speech stop fails.
      }
    }

    if (!mounted) return;
    setState(() {
      _isListeningForCommand = false;

      if (customStatus != null) {
        _commandStatus = customStatus;
      } else if (noCommandHeard) {
        _commandStatus =
            'I did not catch a command. Tap anywhere and try again.';
      }
    });
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
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _startLocalSettingsCommandMode,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tap anywhere and say a command for color, theme, customer support, home, or save settings.',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isListeningForCommand
                          ? theme.colorScheme.primary.withOpacity(0.12)
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isListeningForCommand
                            ? theme.colorScheme.primary.withOpacity(0.3)
                            : theme.dividerColor.withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _commandStatus,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.9),
                          ),
                        ),
                        if (_lastHeardCommand.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Heard: $_lastHeardCommand',
                            style: TextStyle(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.7),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
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
                buildSectionTitle("GENERAL"),
                buildSettingTile(
                  icon: Icons.contact_emergency,
                  title: "Emergency Contact",
                  subtitle: "Set Up",
                  iconColor: theme.colorScheme.error,
                  onTap: () {},
                ),
                buildSettingTile(
                  icon: Icons.support_agent,
                  title: "Customer Support",
                  subtitle: "Chat",
                  onTap: () => Navigator.pushNamed(context, '/customer-support'),
                ),
                const SizedBox(height: 30),
                Center(
                  child: GestureDetector(
                    onTap: () {
                      unawaited(_saveSettings());
                    },
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

