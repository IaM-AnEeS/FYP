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
    return DetectionResponse(
      detections: (json['detections'] as List<dynamic>)
          .map((d) => Detection.fromJson(d as Map<String, dynamic>))
          .toList(),
      imageWidth: json['image_width'] as int,
      imageHeight: json['image_height'] as int,
      inferenceMs: (json['inference_ms'] as num).toDouble(),
    );
  }
}
