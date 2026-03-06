import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the app's primary color scheme with persistence.
/// Defaults to black and adapts to system theme if preferred_color is not set.
class ColorSchemeManager {
  static final ColorSchemeManager _instance = ColorSchemeManager._internal();

  factory ColorSchemeManager() {
    return _instance;
  }

  ColorSchemeManager._internal();

  static ColorSchemeManager get instance => _instance;

    // Default primary color from the attached swatch (deep blue)
    static final ValueNotifier<Color> primaryColor =
      ValueNotifier<Color>(const Color(0xFF003D73));

  static const String _storageKey = 'app_primary_color';

  /// Initialize color scheme from storage or system theme
  Future<void> initialize(Brightness systemBrightness) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedColorValue = prefs.getInt(_storageKey);

      if (savedColorValue != null) {
        // User has set a custom color, use it
        primaryColor.value = Color(savedColorValue);
      } else {
        // No saved preference, adapt to system theme
        // Default: use the provided brand blue for both light and dark
        primaryColor.value = const Color(0xFF003D73);
      }
      print('[ColorSchemeManager] Initialized with color: ${primaryColor.value.value}');
    } catch (e) {
      print('[ColorSchemeManager] Error initializing: $e');
      primaryColor.value = Colors.black;
    }
  }

  /// Update primary color and persist to storage
  static Future<void> setPrimaryColor(Color color) async {
    try {
      primaryColor.value = color;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_storageKey, color.value);
      print('[ColorSchemeManager] Primary color updated to: ${color.value}');
    } catch (e) {
      print('[ColorSchemeManager] Error saving color: $e');
    }
  }

  /// Reset to system default
  static Future<void> resetToDefault() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      primaryColor.value = Colors.black;
      print('[ColorSchemeManager] Reset to default (black)');
    } catch (e) {
      print('[ColorSchemeManager] Error resetting: $e');
    }
  }
}
