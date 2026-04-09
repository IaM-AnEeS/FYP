import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/detection.dart';

class FrameLogService {
  static const Duration _minWriteInterval = Duration(seconds: 3);

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  DateTime? _lastWriteAt;
  String? _lastSignature;

  FrameLogService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  Future<void> logFrame({
    required String mode,
    required String backendUrl,
    required List<Detection> detections,
    required int imageWidth,
    required int imageHeight,
    required double inferenceMs,
  }) async {
    if (detections.isEmpty) return;

    final now = DateTime.now();
    final primary = _primaryDetection(detections);
    final signature = _buildSignature(mode, primary);

    if (_lastWriteAt != null &&
        now.difference(_lastWriteAt!) < _minWriteInterval &&
        signature == _lastSignature) {
      return;
    }

    _lastWriteAt = now;
    _lastSignature = signature;

    final user = _auth.currentUser;

    final payload = {
      'userId': user?.uid ?? '',
      'userEmail': user?.email ?? '',
      'mode': mode,
      'backendUrl': backendUrl,
      'frameName': primary.label,
      'distance': _distanceForDetection(primary),
      'inferenceMs': inferenceMs,
      'detectionCount': detections.length,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
      'detections': detections
          .map(
            (d) => {
              'label': d.label,
              'confidence': d.confidence,
              'distance': _distanceForDetection(d),
              'distanceCategory': d.distanceCategory,
              'estimatedDistanceMeters': d.estimatedDistanceMeters,
            },
          )
          .toList(),
      'createdAt': FieldValue.serverTimestamp(),
    };

    try {
      await _db.collection('frame_detections').add(payload);
    } catch (_) {
      // Keep live detection running even if Firestore logging fails.
    }
  }

  void resetSession() {
    _lastWriteAt = null;
    _lastSignature = null;
  }

  Detection _primaryDetection(List<Detection> detections) {
    Detection primary = detections.first;
    for (final detection in detections.skip(1)) {
      if (detection.confidence > primary.confidence) {
        primary = detection;
      }
    }
    return primary;
  }

  String _buildSignature(String mode, Detection detection) {
    return '$mode:${detection.label}:${_distanceForDetection(detection)}';
  }

  String _distanceForDetection(Detection detection) {
    final distanceLabel = detection.distanceLabel?.trim();
    if (distanceLabel != null && distanceLabel.isNotEmpty) {
      return distanceLabel;
    }

    final meters = detection.estimatedDistanceMeters;
    if (meters != null && meters.isFinite && meters > 0) {
      return '${meters.toStringAsFixed(2)} m';
    }

    final category = detection.distanceCategory?.trim();
    if (category != null && category.isNotEmpty) {
      return category;
    }

    return 'unknown';
  }
}
