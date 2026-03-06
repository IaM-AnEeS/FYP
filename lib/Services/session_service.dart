import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const _keyIsLoggedIn = 'session_is_logged_in';
  static const _keyUserId = 'session_user_id';
  static const _keyUserEmail = 'session_user_email';
  static const _keyLoginTime = 'session_login_time';

  /// Called when the user successfully signs in or registers.
  static Future<void> startSession({
    required String userId,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsLoggedIn, true);
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyUserEmail, email);
    await prefs.setString(_keyLoginTime, DateTime.now().toIso8601String());
    print('[SESSION] Session started for $email at ${DateTime.now()}');
  }

  /// Called when the user explicitly logs out.
  static Future<void> endSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIsLoggedIn);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyUserEmail);
    await prefs.remove(_keyLoginTime);
    print('[SESSION] Session ended');
  }

  /// Returns true if a local session exists.
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsLoggedIn) ?? false;
  }

  /// Returns the stored user ID, or null if no session.
  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserId);
  }

  /// Returns the stored user email, or null if no session.
  static Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyUserEmail);
  }

  /// Returns when the current session started, or null if no session.
  static Future<DateTime?> getLoginTime() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLoginTime);
    return raw != null ? DateTime.tryParse(raw) : null;
  }
}
