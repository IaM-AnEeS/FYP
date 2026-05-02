import 'detection.dart';

/// Response from the unified FastAPI `/detect` endpoint.
///
/// The backend returns a combined navigation-guidance sentence
/// (e.g. "Person ahead, about 2 meters. Traffic light on the right.").
class UnifiedDetectResponse {
  /// The combined navigation / detection guidance sentence.
  final String sentence;

  /// Optional list of structured detections for granular processing.
  final List<Detection> detections;

  /// Optional inference timing reported by the backend (milliseconds).
  final double? inferenceMs;

  const UnifiedDetectResponse({
    required this.sentence,
    this.detections = const [],
    this.inferenceMs,
  });

  /// Parses the JSON map returned by the backend.
  ///
  /// Expected shape:
  /// ```json
  /// {
  ///   "sentence": "...",
  ///   "detections": [...],
  ///   "inference_ms": 142.5
  /// }
  /// ```
  /// The parser is lenient — unknown keys are ignored and optional
  /// fields default gracefully.
  factory UnifiedDetectResponse.fromJson(Map<String, dynamic> json) {
    // Try several plausible key names for the sentence field.
    final sentence = _firstString(json, [
      'sentence',
      'guidance',
      'message',
      'result',
      'text',
    ]);

    final List<Detection> detections = [];
    final rawDetections = json['detections'];
    if (rawDetections is List) {
      for (final item in rawDetections) {
        if (item is Map<String, dynamic>) {
          detections.add(Detection.fromJson(item));
        }
      }
    }

    final inferenceMs = _toNullableDouble(json['inference_ms']);

    return UnifiedDetectResponse(
      sentence: sentence ?? '',
      detections: detections,
      inferenceMs: inferenceMs,
    );
  }


  /// Returns the first non-empty string value found among [keys].
  static String? _firstString(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  static double? _toNullableDouble(dynamic value) {
    if (value is num) {
      final parsed = value.toDouble();
      return parsed.isFinite ? parsed : null;
    }
    if (value is String) {
      final parsed = double.tryParse(value.trim());
      if (parsed != null && parsed.isFinite) return parsed;
    }
    return null;
  }
}
