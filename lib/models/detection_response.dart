import 'detection.dart';

/// Full response from the FastAPI /predict endpoint.
class DetectionResponse {
  final List<Detection> detections;
  final int imageWidth;
  final int imageHeight;
  final double inferenceMs;

  DetectionResponse({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.inferenceMs,
  });

  factory DetectionResponse.fromJson(Map<String, dynamic> json) {
    final rawDetections = json['detections'];
    final parsedDetections = rawDetections is List
        ? rawDetections
              .map((d) {
                if (d is Map<String, dynamic>) return Detection.fromJson(d);
                if (d is Map) {
                  return Detection.fromJson(Map<String, dynamic>.from(d));
                }
                return null;
              })
              .whereType<Detection>()
              .toList()
        : <Detection>[];

    return DetectionResponse(
      detections: parsedDetections,
      imageWidth: _toInt(json['image_width']),
      imageHeight: _toInt(json['image_height']),
      inferenceMs: _toDouble(json['inference_ms']),
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
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim()) ?? 0.0;
    }
    return 0.0;
  }
}
