import 'package:flutter/material.dart';

class AppTheme {
  /// Generate light theme with dynamic primary color
  static ThemeData lightTheme(Color primaryColor) {
    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      colorScheme: ColorScheme.light(
        primary: primaryColor,
        secondary: const Color(0xFFFFCA28),
        surface: Colors.white,
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: const Color(0xFF1B1B1B),
        error: const Color(0xFFD32F2F),
      ),
      textTheme: TextTheme(
        bodyLarge: const TextStyle(color: Color(0xFF1B1B1B), fontSize: 16),
        bodyMedium: const TextStyle(color: Color(0xFF1B1B1B)),
        titleLarge: TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFFFFCA28),
        foregroundColor: Color.fromARGB(255, 0, 0, 0),
      ),
    );
  }

  /// Generate dark theme with dynamic primary color
  static ThemeData darkTheme(Color primaryColor) {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryColor,
      scaffoldBackgroundColor: const Color(0xFF121212),
      colorScheme: ColorScheme.dark(
        primary: primaryColor,
        secondary: const Color(0xFFFFB300),
        surface: const Color(0xFF1E1E1E),
        onPrimary: Colors.white,
        onSecondary: Colors.black,
        onSurface: Colors.white,
        error: const Color(0xFFCF6679),
      ),
      textTheme: TextTheme(
        bodyLarge: const TextStyle(color: Colors.white, fontSize: 16),
        bodyMedium: const TextStyle(color: Colors.white70),
        titleLarge: TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFFFFB300),
        foregroundColor: Colors.black,
      ),
    );
  }
}
