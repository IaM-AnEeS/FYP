import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image/image.dart' as img;
import '../Services/detection_service.dart';
import '../Services/voice_assistant_service.dart';
import '../models/detection.dart';
import '../models/unified_detect_response.dart';
import '../painters/detection_painter.dart';

// ┌─────────────────────────────────────────────────────────────────────────┐
// │  Set to true to show a small debug overlay with backend URL,           │
// │  inference time, and detection count. Set false for production.        │
// └─────────────────────────────────────────────────────────────────────────┘
const bool kShowDebugPanel = true;

class ObjectDetectionScreen extends StatefulWidget {
  const ObjectDetectionScreen({super.key});

  @override
  State<ObjectDetectionScreen> createState() => _ObjectDetectionScreenState();
}

class _ObjectDetectionScreenState extends State<ObjectDetectionScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  bool _isCameraReady = false;
  bool _isPermissionDenied = false;
  bool _isDisposing = false; // guard against capture during dispose

  // Detection state
  List<Detection> _detections = [];
  int _imageWidth = 1;
  int _imageHeight = 1;

  // Request throttle — only ONE request active at a time
  bool _isRequestInFlight = false;
  Timer? _captureTimer;

  // Status text shown on screen
  String _statusText = 'Initialising camera…';

  // Debug info
  double _lastInferenceMs = 0;
  int _detectionCount = 0;

  /// How often (in ms) we capture a frame. Raise to 600–700 on slow Wi-Fi.
  static const int _captureIntervalMs = 500;

  // ─────────────────────────── LIFECYCLE ───────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);
    // Cancel timers FIRST so no new captures/speeches fire
    _captureTimer?.cancel();
    _captureTimer = null;
    // Grab ref, null the field, THEN dispose – so any in-flight
    // _captureAndDetect sees _cameraController == null and bails out.
    final ctrl = _cameraController;
    _cameraController = null;
    ctrl?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause camera when the app goes to background to free resources.
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _captureTimer?.cancel();
      _captureTimer = null;
      _cameraController?.dispose();
      _cameraController = null;
      if (mounted) setState(() => _isCameraReady = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ─────────────────────── CAMERA INIT ────────────────────────────

  Future<void> _initCamera() async {
    if (_isDisposing) return;

    // 1. Check / request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _isPermissionDenied = true;
          _statusText = 'Camera permission denied';
        });
      }
      return;
    }

    // 2. Get available cameras and pick the back one
    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (e) {
      if (mounted) setState(() => _statusText = 'Camera error: $e');
      return;
    }

    if (cameras.isEmpty) {
      if (mounted) setState(() => _statusText = 'No cameras found on this device');
      return;
    }

    final backCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    // 3. Create and initialise controller
    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.medium, // balance of quality vs upload speed
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
    } catch (e) {
      if (mounted) setState(() => _statusText = 'Camera init error: $e');
      return;
    }

    if (!mounted || _isDisposing) return;
    setState(() {
      _isCameraReady = true;
      _statusText = 'Connecting to server…';
    });

    // 4. Start periodic capture loop
    _startCapturing();
  }

  // ─────────────────── PERIODIC CAPTURE LOOP ──────────────────────

  void _startCapturing() {
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: _captureIntervalMs),
      (_) => _captureAndDetect(),
    );
  }

  Future<void> _captureAndDetect() async {
    // ── GUARD: only one request at a time ──
    if (_isRequestInFlight) return;
    if (_isDisposing) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    _isRequestInFlight = true;

    try {
      // ── Re-check after every await to avoid using a disposed controller ──

      // Take a picture
      XFile file;
      try {
        file = await controller.takePicture();
      } catch (e) {
        // CameraException thrown if controller was disposed while awaiting
        if (_isDisposing || _cameraController == null) return;
        rethrow;
      }

      if (_isDisposing || !mounted) return;

      final Uint8List bytes = await file.readAsBytes();

      if (_isDisposing || !mounted) return;

      // Optionally down-scale for faster upload (max 640px wide)
      Uint8List jpegToSend = bytes;
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.width > 640) {
        final resized = img.copyResize(decoded, width: 640);
        jpegToSend = Uint8List.fromList(img.encodeJpg(resized, quality: 80));
      }

      if (_isDisposing || !mounted) return;

      // Send to backend
      final UnifiedDetectResult result =
          await DetectionService.detectUnified(jpegToSend);

      if (!mounted || _isDisposing) return;

      if (!result.isSuccess) {
        setState(() {
          _statusText = result.error ?? 'Unknown error';
        });
      } else {
        final resp = result.response!;
        setState(() {
          _detections = resp.detections;
          _detectionCount = resp.detections.length;
          _lastInferenceMs = resp.inferenceMs ?? 0;
          
          if (resp.detections.isEmpty) {
            _statusText = 'No objects detected';
          } else {
            _statusText =
                '${resp.detections.length} object(s) · ${resp.inferenceMs?.toStringAsFixed(0) ?? "0"} ms';
          }
        });

        // Trigger smart speech via VoiceAssistantService
        unawaited(
          VoiceAssistantService.instance.speakDetectionSentence(
            resp.sentence,
            detections: resp.detections,
            imageWidth: _imageWidth,
            imageHeight: _imageHeight,
          ),
        );
      }
    } catch (e) {
      // Catch-all so the capture loop NEVER breaks.
      // Silently swallow if we're already disposing.
      if (mounted && !_isDisposing) {
        setState(() => _statusText = 'Capture error: $e');
      }
    } finally {
      _isRequestInFlight = false;
    }
  }

  // ──────────────────────────── BUILD ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Object Detection'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    // ── Permission denied ──
    if (_isPermissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.no_photography, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              const Text(
                'Camera permission is required\nfor object detection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => openAppSettings(),
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    // ── Loading / initialising ──
    if (!_isCameraReady || _cameraController == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(_statusText, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    // ── Camera ready — preview + overlay ──
    return Stack(
      fit: StackFit.expand,
      children: [
        // Live camera preview
        CameraPreview(_cameraController!),

        // Bounding-box overlay — uses LayoutBuilder so the painter knows
        // the exact pixel size of the preview widget on screen.
        LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: DetectionPainter(
                detections: _detections,
                imageWidth: _imageWidth,
                imageHeight: _imageHeight,
              ),
            );
          },
        ),

        // ── Optional debug panel (top-left) ──
        if (kShowDebugPanel)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withAlpha((0.6 * 0xFF).round()),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'URL: $kOutdoorBackendBaseUrl',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                  ),
                  Text(
                    'Inference: ${_lastInferenceMs.toStringAsFixed(0)} ms',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                  ),
                  Text(
                    'Detections: $_detectionCount',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),

        // ── Status bar at bottom ──
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Text(
              _statusText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
