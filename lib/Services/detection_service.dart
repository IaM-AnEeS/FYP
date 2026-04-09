import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/detection_response.dart';

enum DetectionBackendMode {
  indoor,
  outdoor,
}

// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║  >>> PASTE YOUR BACKEND BASE URLS HERE <<<                              ║
// ║                                                                         ║
// ║  How to find local IP:                                                  ║
// ║    Windows  -> CMD -> ipconfig -> "IPv4 Address" under Wi-Fi           ║
// ║    macOS    -> System Settings -> Wi-Fi -> Details -> IP Address        ║
// ║    Linux    -> hostname -I                                              ║
// ║                                                                         ║
// ║  Both phone and laptop MUST be on the same Wi-Fi network.               ║
// ║  Example: 'http://192.168.1.42:8000'                                    ║
// ╚═══════════════════════════════════════════════════════════════════════════╝
const String kOutdoorBackendBaseUrl = 'http://192.168.18.19:8000';

// Indoor backend (new FastAPI). Update this one line if Indoor IP/port changes.
const String kIndoorBackendBaseUrl = 'http://192.168.18.19:8002';

// Backward compatibility for older screens still expecting this constant.
const String kBackendBaseUrl = kOutdoorBackendBaseUrl;

/// Result wrapper so the UI can show a meaningful status message.
class PredictResult {
  final DetectionResponse? response;
  final String? error; // null when successful

  PredictResult({this.response, this.error});

  bool get isSuccess => response != null;
}

class DetectionService {
  /// Timeout for each prediction request.
  static const Duration _timeout = Duration(seconds: 8);

  static String baseUrlForMode(DetectionBackendMode mode) {
    switch (mode) {
      case DetectionBackendMode.indoor:
        return kIndoorBackendBaseUrl;
      case DetectionBackendMode.outdoor:
        return kOutdoorBackendBaseUrl;
    }
  }

  static String modeLabel(DetectionBackendMode mode) {
    switch (mode) {
      case DetectionBackendMode.indoor:
        return 'indoor';
      case DetectionBackendMode.outdoor:
        return 'outdoor';
    }
  }

  /// Sends a JPEG frame to the backend and returns parsed detections.
  ///
  /// [jpegBytes] – the camera frame encoded as JPEG.
  /// Returns a [PredictResult] with either a response or a human-readable error.
  static Future<PredictResult> predict(
    Uint8List jpegBytes, {
    required DetectionBackendMode mode,
  }) async {
    final backendBaseUrl = baseUrlForMode(mode);
    final modeText = modeLabel(mode);
    final uri = Uri.parse('$backendBaseUrl/predict');

    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file', // field name expected by FastAPI
            jpegBytes,
            filename: 'frame.jpg',
            contentType: MediaType('image', 'jpeg'), // <-- MUST be set or backend gets application/octet-stream
          ),
        );

      final streamed = await request.send().timeout(_timeout);

      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        return PredictResult(
          error: 'Server error ${streamed.statusCode}: $body',
        );
      }

      final body = await streamed.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return PredictResult(response: DetectionResponse.fromJson(json));
    } on TimeoutException {
      return PredictResult(
        error: '$modeText request timed out - is the server running?',
      );
    } on SocketException {
      return PredictResult(
        error: '$modeText server unreachable - check Wi-Fi & IP',
      );
    } catch (e) {
      return PredictResult(error: 'Network error: $e');
    }
  }

  static Future<PredictResult> predictIndoor(Uint8List jpegBytes) {
    return predict(
      jpegBytes,
      mode: DetectionBackendMode.indoor,
    );
  }

  static Future<PredictResult> predictOutdoor(Uint8List jpegBytes) {
    return predict(
      jpegBytes,
      mode: DetectionBackendMode.outdoor,
    );
  }

  /// Quick connectivity check via GET /health.
  static Future<bool> healthCheck({
    DetectionBackendMode mode = DetectionBackendMode.outdoor,
  }) async {
    try {
      final backendBaseUrl = baseUrlForMode(mode);
      final response = await http
          .get(Uri.parse('$backendBaseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
