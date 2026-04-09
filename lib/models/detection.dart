/// Represents a single detected object returned by the YOLO backend.
class Detection {
  final int classId;
  final String label;
  final double confidence;

  /// Bounding box as [x_min, y_min, x_max, y_max] in image pixel coordinates.
  final List<double> bbox;

  /// Distance category (e.g., "close", "far", "medium").
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
      classId: json['class_id'] as int,
      label: json['label'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      bbox: (json['bbox'] as List<dynamic>)
          .map((e) => (e as num).toDouble())
          .toList(),
      distanceCategory: json['distance_category'] as String?,
      distanceLabel: json['distance_label'] as String?,
      estimatedDistanceMeters:
          (json['estimated_distance_meters'] as num?)?.toDouble(),
      depthScore: (json['depth_score'] as num?)?.toDouble(),
    );
  }

  /// Convenience getters for readability.
  double get xMin => bbox[0];
  double get yMin => bbox[1];
  double get xMax => bbox[2];
  double get yMax => bbox[3];
  double get width => xMax - xMin;
  double get height => yMax - yMin;
}
