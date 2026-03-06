import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'Services/auth_service.dart';
import 'screens/splash_screen.dart';
import 'screens/on_boarding1.dart';
import 'screens/on_boarding2.dart';
import 'screens/on_boarding3.dart';
import 'screens/sign_in.dart';
import 'screens/sign_up.dart';
import 'screens/dashboard.dart';
import 'screens/navigation_screen.dart' as nav;
import 'screens/profile.dart';
import 'screens/settings_screen.dart';
// camera_live_screen import remains; class kept as lightweight placeholder
import 'screens/camera_live_screen.dart';
import 'screens/chatbot.dart';
import 'screens/voice_setting.dart';
import 'screens/text_reader.dart';
import 'screens/forgot_password.dart';
import 'Services/session_service.dart';
import 'theme/theme.dart';
import 'theme/theme_manager.dart';
import 'theme/color_scheme_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Firebase with explicit options to support desktop/web.
    // For mobile, google-services.json (Android) and GoogleService-Info.plist (iOS)
    // provide the config. For desktop/web, we pass options programmatically.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('[MAIN] Firebase initialized successfully');
  } catch (e) {
    print('[MAIN] Firebase initialization error: $e');
  }

  // Initialize ColorSchemeManager to load saved color preference
  // and adapt to system theme brightness
  final brightness = MediaQueryData.fromView(WidgetsBinding.instance.window).platformBrightness;
  // Initialize ThemeManager first so the app has the correct theme mode
  await ThemeManager.initialize(brightness);
  print('[MAIN] ThemeManager initialized');
  await ColorSchemeManager.instance.initialize(brightness);
  print('[MAIN] ColorSchemeManager initialized');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Listen to both ThemeManager.themeMode and ColorSchemeManager.primaryColor
    // to update the entire app when either changes
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeManager.themeMode,
      builder: (context, mode, _) {
        return ValueListenableBuilder<Color>(
          valueListenable: ColorSchemeManager.primaryColor,
          builder: (context, primaryColor, __) {
            // Set status bar to transparent and adjust icon brightness per theme.
            // Respect ThemeMode.system by checking the platform brightness
            final platformBrightness = WidgetsBinding.instance.window.platformBrightness;
            final bool isDark = mode == ThemeMode.dark || (mode == ThemeMode.system && platformBrightness == Brightness.dark);

            final SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
              statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            );

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: overlayStyle,
              child: MaterialApp(
                title: 'Blindly',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.lightTheme(primaryColor),
                darkTheme: AppTheme.darkTheme(primaryColor),
                themeMode: mode,
                home: const AuthWrapper(),
                routes: {
                  '/splash': (context) => const SplashScreen(),
                  '/onboarding1': (context) => const Onboarding1(),
                  '/onboarding2': (context) => const OnBoarding2(),
                  '/onboarding3': (context) => const OnBoarding3(),
                  '/login': (context) => const SignInScreen(),
                  '/signup': (context) => const SignUpScreen(),
                  '/dashboard': (context) => DashboardScreen(),
                  '/navigation': (context) => const nav.NavigationScreen(),
                  '/detection': (context) => const CameraLiveScreen(mode: 'indoor'),
                  '/profile': (context) => const ProfileScreen(),
                  '/settings': (context) => const SettingsScreen(),
                  '/chat': (context) => const AIAssistantScreen(),
                  '/voice-settings': (context) => const VoiceSettingsScreen(),
                  '/text-reader': (context) => const TextReaderScreen(),
                  '/forgot-password': (context) => const ForgotPasswordScreen(),
                },
              ),
            );
          },
        );
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthService authService = AuthService();

    return StreamBuilder<Object?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // Show splash screen while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        // Handle connection errors
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Theme.of(context).colorScheme.error),
                  const SizedBox(height: 16),
                  Text('Connection Error', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('${snapshot.error}', textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }

        // If Firebase says user is logged in, sync local session and go to dashboard
        if (snapshot.hasData && snapshot.data != null) {
          final firebaseUser = snapshot.data as dynamic;
          // Sync local session in case it was missing (e.g. existing users)
          SessionService.isLoggedIn().then((hasSession) {
            if (!hasSession) {
              SessionService.startSession(
                userId: firebaseUser.uid ?? '',
                email: firebaseUser.email ?? '',
              );
            }
          });
          return SplashScreen(nextScreen: DashboardScreen());
        }

        // Firebase says logged out — ensure local session is cleared
        SessionService.endSession();

        // If user is not logged in, show the splash which will navigate to onboarding
        return const SplashScreen();
      },
    );
  }
}
