import '../screens/admin/admin_login_screen.dart';
import '../screens/on_boarding1.dart';
import '../screens/on_boarding2.dart';
import '../screens/on_boarding3.dart';
import '../screens/sign_in.dart';
import '../screens/sign_up.dart';

class VoiceScreenAccessPolicy {
  static const Set<String> _blockedRouteNames = <String>{
    '/onboarding1',
    '/onboarding2',
    '/onboarding3',
    '/login',
    '/signup',
    '/admin-login',
    '/admin-panel',
  };

  static bool isBlockedRouteName(String? routeName) {
    final normalized = (routeName ?? '').trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'unknown') {
      return false;
    }

    if (_blockedRouteNames.contains(normalized)) {
      return true;
    }

    // Any admin route path is blocked by default.
    if (isAdminRouteName(normalized)) {
      return true;
    }

    return false;
  }

  static bool isAdminRouteName(String? routeName) {
    final normalized = (routeName ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.startsWith('/admin');
  }

  static bool isBlockedScreenClassActive() {
    return Onboarding1.isActive.value ||
        OnBoarding2.isActive.value ||
        OnBoarding3.isActive.value ||
        SignInScreen.isActive.value ||
        SignUpScreen.isActive.value ||
      AdminLoginScreen.isActive.value;
  }

  static bool isVoiceBlocked({String? routeName}) {
    if (isBlockedScreenClassActive()) {
      return true;
    }

    if (isBlockedRouteName(routeName)) {
      return true;
    }

    return false;
  }
}
