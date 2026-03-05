import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple app-wide theme manager using a ValueNotifier so screens can
/// toggle between light and dark theme without introducing a heavy
/// dependency like Provider or Riverpod.
class ThemeManager {
  static const String _storageKey = 'app_theme_mode';

  // Default to system so the app adapts to the device. If you prefer
  // a strict default of dark on first-run, change the fallback in
  // initialize() to ThemeMode.dark. Current behavior: system-adaptive.
  static final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  /// Initialize theme from SharedPreferences. If no saved user preference
  /// exists, keep `ThemeMode.system` so the app adapts to the device theme.
  static Future<void> initialize(Brightness systemBrightness) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_storageKey);

      if (saved != null) {
        switch (saved) {
          case 'light':
            themeMode.value = ThemeMode.light;
            break;
          case 'dark':
            themeMode.value = ThemeMode.dark;
            break;
          case 'system':
          default:
            themeMode.value = ThemeMode.system;
            break;
        }
      } else {
          // No saved preference: default to dark on first run while still
          // allowing the user to pick 'Use system theme' from settings later.
          themeMode.value = ThemeMode.dark;
      }
      print('[ThemeManager] Initialized with mode: ${themeMode.value}');
    } catch (e) {
      print('[ThemeManager] Error initializing theme: $e');
      themeMode.value = ThemeMode.system;
    }
  }

  /// Persist the user's theme preference and update the ValueNotifier.
  static Future<void> setThemeMode(ThemeMode mode) async {
    try {
      themeMode.value = mode;
      final prefs = await SharedPreferences.getInstance();
      final val = mode == ThemeMode.system
          ? 'system'
          : (mode == ThemeMode.dark ? 'dark' : 'light');
      await prefs.setString(_storageKey, val);
      print('[ThemeManager] Saved theme mode: $val');
    } catch (e) {
      print('[ThemeManager] Error saving theme mode: $e');
    }
  }
}
