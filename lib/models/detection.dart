/// Represents a single detected object returned by the YOLO backend.
class Detection {
  final int classId;
  final String label;
  final double confidence;

  /// Bounding box as [x_min, y_min, x_max, y_max] in image pixel coordinates.
  final List<double> bbox;

  /// Backend distance category (e.g., "very_near", "near", "medium", "far").
  final String? distanceCategory;

  /// Human-friendly distance label (e.g., "about 1 to 2 steps away").
  final String? distanceLabel;

  /// Estimated distance in meters from backend depth estimation.
  final double? estimatedDistanceMeters;

  /// Raw depth model score from backend.
  final double? depthScore;

  Detection({
    required this.classId,
    required this.label,
    required this.confidence,
    required this.bbox,
    this.distanceCategory,
    this.distanceLabel,
    this.estimatedDistanceMeters,
    this.depthScore,
  });

  factory Detection.fromJson(Map<String, dynamic> json) {
    return Detection(
      classId: _toInt(json['class_id']),
      label: _toNullableString(json['label']) ?? 'object',
      confidence: _toDouble(json['confidence']),
      bbox: _parseBbox(json['bbox']),
      distanceCategory: _toNullableString(json['distance_category']),
      distanceLabel: _toNullableString(json['distance_label']),
      estimatedDistanceMeters: _parsePositiveDouble(
        json['estimated_distance_meters'],
      ),
      depthScore: _toNullableDouble(json['depth_score']),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value.trim()) ?? 0;
    }
    return 0;
  }

  static double _toDouble(dynamic value) {
    return _toNullableDouble(value) ?? 0.0;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value is num) {
      final parsed = value.toDouble();
      return parsed.isFinite ? parsed : null;
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed.isFinite) {
        return parsed;
      }
    }
    return null;
  }

  static String? _toNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static double? _parsePositiveDouble(dynamic value) {
    final parsed = _toNullableDouble(value);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static List<double> _parseBbox(dynamic value) {
    if (value is! List) {
      return const [0, 0, 0, 0];
    }

    final coords = <double>[];
    for (final item in value.take(4)) {
      coords.add(_toNullableDouble(item) ?? 0.0);
    }

    while (coords.length < 4) {
      coords.add(0.0);
    }

    return coords;
  }

  /// Convenience getters for readability.
  double get xMin => bbox[0];
  double get yMin => bbox[1];
  double get xMax => bbox[2];
  double get yMax => bbox[3];
  double get width => xMax - xMin;
  double get height => yMax - yMin;
}
