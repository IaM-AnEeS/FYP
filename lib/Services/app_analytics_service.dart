import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppAnalyticsService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  AppAnalyticsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _userActivityDailyRef =>
      _db.collection('user_activity_daily');

  CollectionReference<Map<String, dynamic>> get _detectionSessionsRef =>
      _db.collection('detection_sessions');

  Future<void> recordLoginActivity({
    required String userId,
    required String userEmail,
  }) async {
    final now = DateTime.now();
    final dateKey = _dateKey(now);
    final docId = '${userId}_$dateKey';

    try {
      await _userActivityDailyRef.doc(docId).set({
        'userId': userId,
        'userEmail': userEmail,
        'dateKey': dateKey,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'loginCount': FieldValue.increment(1),
        'detectionSessions': FieldValue.increment(0),
        'successfulSessions': FieldValue.increment(0),
        'detectionsCount': FieldValue.increment(0),
        'totalUsageSeconds': FieldValue.increment(0),
      }, SetOptions(merge: true));
    } catch (_) {
      // Never block sign-in if analytics cannot be written.
    }
  }

  Future<void> recordDetectionSession({
    required String mode,
    required DateTime startedAt,
    required DateTime endedAt,
    required int framesProcessed,
    required int successfulFrames,
    required int failedFrames,
    required int detectionsCount,
    required double averageInferenceMs,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final dateKey = _dateKey(startedAt);
    final durationSeconds = endedAt.difference(startedAt).inSeconds;
    final clampedDuration = durationSeconds < 0 ? 0 : durationSeconds;
    final isSuccessful = detectionsCount > 0 || successfulFrames > 0;

    try {
      await _detectionSessionsRef.add({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'mode': mode,
        'dateKey': dateKey,
        'startedAt': Timestamp.fromDate(startedAt),
        'endedAt': Timestamp.fromDate(endedAt),
        'durationSeconds': clampedDuration,
        'framesProcessed': framesProcessed,
        'successfulFrames': successfulFrames,
        'failedFrames': failedFrames,
        'detectionsCount': detectionsCount,
        'averageInferenceMs': averageInferenceMs,
        'isSuccessful': isSuccessful,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await _userActivityDailyRef.doc('${user.uid}_$dateKey').set({
        'userId': user.uid,
        'userEmail': user.email ?? '',
        'dateKey': dateKey,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'detectionSessions': FieldValue.increment(1),
        'successfulSessions': FieldValue.increment(isSuccessful ? 1 : 0),
        'detectionsCount': FieldValue.increment(detectionsCount),
        'totalUsageSeconds': FieldValue.increment(clampedDuration),
      }, SetOptions(merge: true));
    } catch (_) {
      // Keep detection flow running even if analytics writes fail.
    }
  }

  String _dateKey(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }
}
