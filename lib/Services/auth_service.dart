import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'app_analytics_service.dart';
import 'session_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AppAnalyticsService _analyticsService = AppAnalyticsService();

  static const String suspendedAccountMessage =
      'You are suspended. Please contact admin at this email: sumerahmed0077@gmail.com';

  // Register a new user
  Future<User?> registerUser(
    String name,
    String email,
    String password, {
    String? username,
    String? phone,
    String? country,
    String? gender,
    String? dateOfBirth,
  }) async {
    try {
      print('[AUTH] Starting user registration for email: $email');
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      print('[AUTH] User created successfully: ${result.user?.uid}');

      User? user = result.user;
      if (user == null) {
        print('[AUTH] ERROR: User is null after createUserWithEmailAndPassword');
        throw 'User creation returned null';
      }

      // Save extra user info in Firestore (do this in background to avoid
      // delaying the sign-up response). If Firestore isn't enabled for the
      // project the write will fail but the user account in Auth still exists.
      final userData = <String, dynamic>{
        'name': name,
        'email': email,
        'accountStatus': 'active',
        'createdAt': DateTime.now(),
        'updatedAt': DateTime.now(),
      };

      if (username != null && username.isNotEmpty) {
        userData['username'] = username;
      }
      if (phone != null && phone.isNotEmpty) {
        userData['phone'] = phone;
      }
      if (country != null && country.isNotEmpty) {
        userData['country'] = country;
      }
      if (gender != null && gender.isNotEmpty) {
        userData['gender'] = gender;
      }
      if (dateOfBirth != null && dateOfBirth.isNotEmpty) {
        userData['dateOfBirth'] = dateOfBirth;
      }

      print('[AUTH] Attempting Firestore write for user: ${user.uid}');
      _firestore
          .collection('users')
          .doc(user.uid)
          .set(userData)
          .timeout(const Duration(seconds: 5))
          .catchError((e) {
        print('[AUTH] Firestore write failed (background): $e');
      });
      print('[AUTH] Firestore write initiated (non-blocking)');

      print('[AUTH] Registration complete, returning user: ${user.email}');
      // Start local session
      await SessionService.startSession(
        userId: user.uid,
        email: user.email ?? email,
      );

      await _analyticsService.recordLoginActivity(
        userId: user.uid,
        userEmail: user.email ?? email,
      );
      return user;
    } on FirebaseAuthException catch (e) {
      print('[AUTH] FirebaseAuthException during registration: ${e.message}');
      throw e.message ?? "Registration failed";
    } catch (e) {
      print('[AUTH] Unexpected error during registration: $e');
      rethrow;
    }
  }

  // Login existing user
  Future<User?> loginUser(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = result.user;
      if (user != null) {
        await _ensureAccountIsActive(user);

        await SessionService.startSession(
          userId: user.uid,
          email: user.email ?? email,
        );

        await _analyticsService.recordLoginActivity(
          userId: user.uid,
          userEmail: user.email ?? email,
        );
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw e.message ?? "Login failed";
    }
  }

  // Logout
  Future<void> logout() async {
    await SessionService.endSession();
    await _auth.signOut();
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw e.message ?? "Failed to send password reset email";
    }
  }

  // Stream to detect auth changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Google Sign-In
  Future<User?> signInWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        serverClientId:
            '1064511627841-2uf10n2qp5erlqd3388d1q9sjssmdime.apps.googleusercontent.com',
      );

      // Force account picker every time
      await googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential result =
          await _auth.signInWithCredential(credential);
      final User? user = result.user;

      if (user != null) {
        // Save/update user data in Firestore
        final doc =
            await _firestore.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          await _firestore.collection('users').doc(user.uid).set({
            'name': user.displayName ?? '',
            'email': user.email ?? '',
            'accountStatus': 'active',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await _firestore.collection('users').doc(user.uid).set({
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        await _ensureAccountIsActive(user);

        await SessionService.startSession(
          userId: user.uid,
          email: user.email ?? '',
        );

        await _analyticsService.recordLoginActivity(
          userId: user.uid,
          userEmail: user.email ?? '',
        );
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'Google sign-in failed';
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> isCurrentUserSuspended() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final profile = await _firestore.collection('users').doc(user.uid).get();
    final data = profile.data() ?? <String, dynamic>{};
    return _isSuspendedStatus(data['accountStatus']);
  }

  Future<void> _ensureAccountIsActive(User user) async {
    final docRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await docRef.get();

    if (!userDoc.exists) {
      await docRef.set({
        'name': user.displayName ?? '',
        'email': user.email ?? '',
        'accountStatus': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    final data = userDoc.data() ?? <String, dynamic>{};
    final currentStatus = data['accountStatus'];

    if (_isSuspendedStatus(currentStatus)) {
      await SessionService.endSession();
      await _auth.signOut();
      throw suspendedAccountMessage;
    }

    if (currentStatus == null || currentStatus.toString().trim().isEmpty) {
      await docRef.set({
        'accountStatus': 'active',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  bool _isSuspendedStatus(dynamic status) {
    final normalized = status?.toString().trim().toLowerCase() ?? '';
    return normalized == 'suspended';
  }
}
