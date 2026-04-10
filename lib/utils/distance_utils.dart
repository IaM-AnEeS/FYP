import '../models/detection.dart';
import 'dart:math' as math;

/// Utility functions for handling distance information and prioritizing
/// objects for voice feedback.

class DistanceUtils {
  /// Returns natural on-screen distance text.
  ///
  /// Priority:
  /// 1) Use backend `distanceLabel` if present.
  /// 2) Fallback to rounded meters text from `estimatedDistanceMeters`.
  /// 3) Return null if no distance information is available.
  static String? buildDisplayDistanceLabel(Detection detection) {
    final backendLabel = detection.distanceLabel?.trim();
    if (backendLabel != null && backendLabel.isNotEmpty) {
      return backendLabel;
    }

    final meters = detection.estimatedDistanceMeters;
    if (meters == null || !meters.isFinite || meters <= 0) {
      return null;
    }

    final roundedMeters = meters.round();
    final safeMeters = roundedMeters <= 0 ? 1 : roundedMeters;
    final unit = safeMeters == 1 ? 'meter' : 'meters';
    return 'about $safeMeters $unit away';
  }

  /// Calculates a priority score for an object to decide which one
  /// to speak about. Higher score = higher priority.
  ///
  /// Prioritizes:
  /// 1. Closest objects (closest = highest priority)
  /// 2. Objects in the center of the frame (lower = more centered)
  /// 3. Higher confidence objects as tiebreaker
  ///
  /// Returns null if the object has no distance information.
  static double? calculatePriorityScore(
    Detection detection,
    int imageWidth,
    int imageHeight,
  ) {
    // Only score objects with distance information
    if (detection.distanceCategory == null) return null;

    // Distance priority: "very_near" > "near" > "medium" > "far"
    final distancePriority = _getDistancePriority(detection.distanceCategory!);
    if (distancePriority == null) return null;

    // Center priority: objects in center of frame get bonus
    final centerX = imageWidth / 2;
    final centerY = imageHeight / 2;
    final objCenterX = (detection.xMin + detection.xMax) / 2;
    final objCenterY = (detection.yMin + detection.yMax) / 2;

    final distanceFromCenter = math.sqrt(
      math.pow(objCenterX - centerX, 2) + math.pow(objCenterY - centerY, 2),
    );

    // Normalize distance from center (0-1, where 0 = center)
    final maxDistance = math.sqrt(math.pow(centerX, 2) + math.pow(centerY, 2));
    final centerBonus =
        1.0 - (distanceFromCenter / maxDistance).clamp(0.0, 1.0);

    // Confidence as tiebreaker
    final confidenceBonus = detection.confidence;

    // Combine: distance is most important, center position is secondary,
    // confidence is tertiary
    final score =
        distancePriority * 1000 + centerBonus * 100 + confidenceBonus * 10;

    return score;
  }

  /// Returns numeric priority for distance categories.
  /// Higher = higher priority to speak.
  static double? _getDistancePriority(String distanceCategory) {
    return switch (distanceCategory.toLowerCase()) {
      'very_near' => 4.0,
      'near' => 3.0,
      'medium' => 2.0,
      'far' => 1.0,
      // Legacy aliases kept for backward compatibility with older payloads.
      'very_close' => 4.0,
      'close' => 3.0,
      _ => null,
    };
  }

  /// Finds the best object to announce based on priority scoring.
  /// Returns null if no objects or none have distance info.
  static Detection? selectObjectForSpeech(
    List<Detection> detections,
    int imageWidth,
    int imageHeight,
  ) {
    if (detections.isEmpty) return null;

    Detection? bestDetection;
    double? bestScore;

    for (final det in detections) {
      final score = calculatePriorityScore(det, imageWidth, imageHeight);
      if (score != null && (bestScore == null || score > bestScore)) {
        bestScore = score;
        bestDetection = det;
      }
    }

    return bestDetection;
  }

  /// Builds a human-friendly speech string from a detection.
  /// Example: "person, about 1 to 2 steps away"
  static String buildSpeechText(Detection detection) {
    final label = detection.label.trim();
    final safeLabel = label.isEmpty ? 'object' : label;
    final distanceLabel = buildDisplayDistanceLabel(detection);

    if (distanceLabel == null) {
      return '$safeLabel detected';
    }

    return '$safeLabel, $distanceLabel';
  }

  /// Generates a unique identifier for a detection state.
  /// Used to detect if the situation has significantly changed
  /// and we should speak again.
  static String generateDetectionSignature(
    List<Detection> detections,
    int imageWidth,
    int imageHeight,
  ) {
    if (detections.isEmpty) return 'empty';

    // Get the best object for speech
    final bestObj = selectObjectForSpeech(detections, imageWidth, imageHeight);
    if (bestObj == null) return 'no_distance_info';

    final distanceToken =
        buildDisplayDistanceLabel(bestObj) ??
        bestObj.distanceCategory ??
        'unknown';

    // This signature changes only when the primary label or distance meaningfully changes.
    return '${bestObj.label}:${distanceToken.toLowerCase()}';
  }
}
