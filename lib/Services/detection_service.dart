import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/unified_detect_response.dart';

// ── Legacy type aliases kept so old imports don't break at compile time. ──
// These are intentionally unused in the active flow.
enum DetectionBackendMode { indoor, outdoor }

// ╔═══════════════════════════════════════════════════════════════════════════╗
// ║  >>> PASTE YOUR BACKEND BASE URL HERE <<<                               ║
// ║                                                                         ║
// ║  How to find local IP:                                                  ║
// ║    Windows  -> CMD -> ipconfig -> "IPv4 Address" under Wi-Fi            ║
// ║    macOS    -> System Settings -> Wi-Fi -> Details -> IP Address         ║
// ║    Linux    -> hostname -I                                              ║
// ║                                                                         ║
// ║  Both phone and laptop MUST be on the same Wi-Fi network.               ║
// ║  Example: 'http://192.168.1.42:8000'                                    ║
// ╚═══════════════════════════════════════════════════════════════════════════╝
const String kDetectionBackendBaseUrl = 'http://192.168.18.19:8000';

// Backward compatibility constants — point to the same unified backend.
const String kBackendBaseUrl = kDetectionBackendBaseUrl;
const String kOutdoorBackendBaseUrl = kDetectionBackendBaseUrl;
const String kIndoorBackendBaseUrl = kDetectionBackendBaseUrl;

/// Result wrapper for the unified `/detect` endpoint.
class UnifiedDetectResult {
  final UnifiedDetectResponse? response;
  final String? error;

  UnifiedDetectResult({this.response, this.error});

  bool get isSuccess => response != null;
}

// ── Legacy PredictResult kept for compile safety of old screens. ──
class PredictResult {
  final dynamic response;
  final String? error;
  PredictResult({this.response, this.error});
  bool get isSuccess => response != null;
}

class DetectionService {
  /// Timeout for each detection request.
  static const Duration _timeout = Duration(seconds: 8);

  /// The active backend URL for the unified detection endpoint.
  static String get backendUrl => kDetectionBackendBaseUrl;

  // ── Legacy helpers kept for compile safety ──
  static String baseUrlForMode(DetectionBackendMode mode) =>
      kDetectionBackendBaseUrl;
  static String modeLabel(DetectionBackendMode mode) => 'unified';

  /// Sends a JPEG frame to the unified backend via multipart POST to `/detect`.
  ///
  /// [jpegBytes] – the camera frame encoded as JPEG.
  /// Returns a [UnifiedDetectResult] with either a response sentence or an error.
  static Future<UnifiedDetectResult> detectUnified(Uint8List jpegBytes) async {
    final uri = Uri.parse('$kDetectionBackendBaseUrl/detect');

    try {
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file', // field name expected by FastAPI UploadFile
            jpegBytes,
            filename: 'frame.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      final streamed = await request.send().timeout(_timeout);

      if (streamed.statusCode != 200) {
        final body = await streamed.stream.bytesToString();
        return UnifiedDetectResult(
          error: 'Server error ${streamed.statusCode}: $body',
        );
      }

      final body = await streamed.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final response = UnifiedDetectResponse.fromJson(json);

      if (response.sentence.isEmpty) {
        return UnifiedDetectResult(
          error: 'Backend returned empty sentence.',
        );
      }

      return UnifiedDetectResult(response: response);
    } on TimeoutException {
      return UnifiedDetectResult(
        error: 'Request timed out — is the server running?',
      );
    } on SocketException {
      return UnifiedDetectResult(
        error: 'Server unreachable — check Wi-Fi & IP',
      );
    } catch (e) {
      return UnifiedDetectResult(error: 'Network error: $e');
    }
  }

  // ── Legacy predict methods — redirect to unified for compile safety ──
  static Future<PredictResult> predict(
    Uint8List jpegBytes, {
    required DetectionBackendMode mode,
  }) async {
    final result = await detectUnified(jpegBytes);
    return PredictResult(response: result.response, error: result.error);
  }

  static Future<PredictResult> predictIndoor(Uint8List jpegBytes) async {
    final result = await detectUnified(jpegBytes);
    return PredictResult(response: result.response, error: result.error);
  }

  static Future<PredictResult> predictOutdoor(Uint8List jpegBytes) async {
    final result = await detectUnified(jpegBytes);
    return PredictResult(response: result.response, error: result.error);
  }

  /// Quick connectivity check via GET /health.
  static Future<bool> healthCheck() async {
    try {
      final response = await http
          .get(Uri.parse('$kDetectionBackendBaseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
