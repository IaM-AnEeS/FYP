import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import '../Services/app_analytics_service.dart';
import '../Services/detection_service.dart';
import '../Services/frame_log_service.dart';
import '../Services/navigation_voice_bridge.dart';
import '../Services/voice_assistant_service.dart';

class NavigationScreen extends StatefulWidget {
  final bool autoStartDetection;

  const NavigationScreen({
    super.key,
    this.autoStartDetection = false,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen>
    with WidgetsBindingObserver {
  static const int _captureIntervalMs = 500;
  final AppAnalyticsService _analyticsService = AppAnalyticsService();
  final FrameLogService _frameLogService = FrameLogService();
  final NavigationVoiceBridge _voiceBridge = NavigationVoiceBridge.instance;

  StreamSubscription<NavigationVoiceCommand>? _voiceCommandSub;

  int _captureSession = 0;
  CameraController? _cameraController;
  Timer? _captureTimer;

  bool _isCameraReady = false;
  bool _isDetectionRunning = false;
  bool _isRequestInFlight = false;
  bool _isPermissionDenied = false;
  bool _isDisposing = false;

  String _statusText = 'Tap to start object detection';
  String _latestSentence = '';
  double _lastInferenceMs = 0;

  DateTime? _sessionStartedAt;
  int _sessionFramesProcessed = 0;
  int _sessionSuccessfulFrames = 0;
  int _sessionFailedFrames = 0;
  double _sessionInferenceTotalMs = 0;
  int _sessionInferenceSamples = 0;

  bool _isSessionValid(int session, {CameraController? controller}) {
    if (_isDisposing) return false;
    if (_captureSession != session) return false;
    if (controller != null && !identical(_cameraController, controller)) {
      return false;
    }
    return true;
  }

  Future<void> _disposeController(CameraController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {
      // Ignore disposal race exceptions.
    }
  }

  void _scheduleControllerDispose(CameraController? controller) {
    if (controller == null) return;

    if (_isDisposing || !mounted) {
      unawaited(_disposeController(controller));
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_disposeController(controller));
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _voiceBridge.setNavigationVisible(true);
    _voiceBridge.setDetectionRunning(false);
    _voiceCommandSub = _voiceBridge.commands.listen((command) {
      unawaited(_handleVoiceCommand(command));
    });

    if (widget.autoStartDetection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_startDetection());
      });
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _voiceCommandSub?.cancel();
    _voiceBridge.setNavigationVisible(false);
    _voiceBridge.setDetectionRunning(false);
    _stopDetection(setIdleMessage: false);
    super.dispose();
  }

  Future<void> _handleVoiceCommand(NavigationVoiceCommand command) async {
    if (!mounted || _isDisposing) return;

    debugPrint('[NavigationVoice] Received command: ${command.type.name}');

    switch (command.type) {
      case NavigationVoiceCommandType.startDetection:
        await _startDetection();
        break;
      case NavigationVoiceCommandType.stopDetection:
        if (_isDetectionRunning) {
          _stopDetection(statusText: 'Detection stopped by voice command.');
        }
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isDetectionRunning) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopDetection(
        statusText: 'Detection stopped. Tap to Start to run again.',
      );
    }
  }

  Future<void> _onBottomButtonPressed() async {
    if (_isDetectionRunning) {
      _stopDetection(statusText: 'Detection stopped.');
      return;
    }

    await _startDetection();
  }

  Future<void> _startDetection() async {
    if (_isDisposing) return;

    if (_isDetectionRunning) {
      debugPrint(
        '[NavigationVoice] Ignored start request because detection is already running.',
      );
      return;
    }

    final int session = ++_captureSession;
    _frameLogService.resetSession();
    _resetAnalyticsSession();
    _sessionStartedAt = DateTime.now();

    debugPrint(
      '[NavigationVoice] Starting unified object detection. session=$session',
    );

    setState(() {
      _isPermissionDenied = false;
      _statusText = 'Initialising camera...';
      _latestSentence = '';
    });

    await _initCamera(session);
  }

  Future<void> _initCamera(int session) async {
    if (_isDisposing) return;

    final status = await Permission.camera.request();
    if (!_isSessionValid(session)) return;

    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _isPermissionDenied = true;
          _isDetectionRunning = false;
          _isCameraReady = false;
          _statusText = 'Camera permission denied';
        });
        _voiceBridge.setDetectionRunning(false);
      }
      return;
    }

    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusText = 'Camera error: $e';
        });
        _voiceBridge.setDetectionRunning(false);
      }
      return;
    }

    if (!_isSessionValid(session)) return;

    if (cameras.isEmpty) {
      if (mounted) {
        setState(() {
          _statusText = 'No cameras found on this device';
        });
        _voiceBridge.setDetectionRunning(false);
      }
      return;
    }

    final backCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _cameraController = controller;

    try {
      await controller.initialize();
    } catch (e) {
      await _disposeController(controller);
      if (identical(_cameraController, controller)) {
        _cameraController = null;
      }
      if (mounted) {
        setState(() {
          _statusText = 'Camera init error: $e';
        });
        _voiceBridge.setDetectionRunning(false);
      }
      return;
    }

    if (!mounted || !_isSessionValid(session, controller: controller)) {
      _stopDetection(setIdleMessage: false);
      return;
    }

    setState(() {
      _isCameraReady = true;
      _isDetectionRunning = true;
      _statusText = 'Connecting to server...';
    });
    _voiceBridge.setDetectionRunning(true);

    _startCapturing(session);
  }

  void _startCapturing(int session) {
    _captureTimer?.cancel();
    _captureTimer = Timer.periodic(
      const Duration(milliseconds: _captureIntervalMs),
      (_) => _captureAndDetect(session),
    );
  }

  void _stopDetection({String? statusText, bool setIdleMessage = true}) {
    _finalizeAnalyticsSession();

    _captureSession++;
    _captureTimer?.cancel();
    _captureTimer = null;
    _frameLogService.resetSession();

    final CameraController? controller = _cameraController;
    _cameraController = null;

    _isRequestInFlight = false;

    void applyState() {
      _isCameraReady = false;
      _isDetectionRunning = false;
      _lastInferenceMs = 0;

      if (statusText != null) {
        _statusText = statusText;
      } else if (setIdleMessage) {
        _statusText = 'Tap to start object detection';
      }
    }

    if (_isDisposing || !mounted) {
      applyState();
      _voiceBridge.setDetectionRunning(false);
      _scheduleControllerDispose(controller);
      return;
    }

    setState(applyState);
    _voiceBridge.setDetectionRunning(false);
    _scheduleControllerDispose(controller);
  }

  Future<void> _captureAndDetect(int session) async {
    if (!_isSessionValid(session)) return;

    if (_isRequestInFlight || !_isDetectionRunning || _isDisposing) {
      return;
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    _isRequestInFlight = true;

    try {
      XFile file;
      try {
        file = await controller.takePicture();
      } on CameraException {
        return;
      } catch (e) {
        if (_isDisposing || _cameraController == null) return;
        rethrow;
      }

      if (!_isSessionValid(session, controller: controller) || !mounted) return;

      final Uint8List bytes = await file.readAsBytes();

      if (!_isSessionValid(session, controller: controller) || !mounted) return;

      Uint8List jpegToSend = bytes;
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.width > 640) {
        final resized = img.copyResize(decoded, width: 640);
        jpegToSend = Uint8List.fromList(img.encodeJpg(resized, quality: 80));
      }

      if (!_isSessionValid(session, controller: controller) || !mounted) return;

      final result = await DetectionService.detectUnified(jpegToSend);

      if (!mounted || !_isSessionValid(session, controller: controller)) {
        return;
      }

      if (!result.isSuccess) {
        _sessionFramesProcessed += 1;
        _sessionFailedFrames += 1;
        setState(() {
          _statusText = result.error ?? 'Unknown error';
        });
      } else {
        final resp = result.response!;
        _sessionFramesProcessed += 1;
        _sessionSuccessfulFrames += 1;
        if (resp.inferenceMs != null) {
          _sessionInferenceTotalMs += resp.inferenceMs!;
          _sessionInferenceSamples += 1;
        }

        setState(() {
          _latestSentence = resp.sentence;
          _lastInferenceMs = resp.inferenceMs ?? 0;
          _statusText = 'Object detection active';
        });

        // Speak the sentence via TTS
        unawaited(
          VoiceAssistantService.instance.speakDetectionSentence(resp.sentence),
        );
      }
    } catch (e) {
      _sessionFramesProcessed += 1;
      _sessionFailedFrames += 1;

      if (mounted && !_isDisposing) {
        setState(() {
          _statusText = 'Capture error: $e';
        });
      }
    } finally {
      _isRequestInFlight = false;
    }
  }

  void _finalizeAnalyticsSession() {
    final startedAt = _sessionStartedAt;
    if (startedAt == null) {
      _resetAnalyticsSession();
      return;
    }

    final endedAt = DateTime.now();
    final averageInferenceMs = _sessionInferenceSamples <= 0
        ? 0.0
        : _sessionInferenceTotalMs / _sessionInferenceSamples;

    final framesProcessed = _sessionFramesProcessed;
    final successfulFrames = _sessionSuccessfulFrames;
    final failedFrames = _sessionFailedFrames;

    _resetAnalyticsSession();

    unawaited(
      _analyticsService.recordDetectionSession(
        mode: 'unified',
        startedAt: startedAt,
        endedAt: endedAt,
        framesProcessed: framesProcessed,
        successfulFrames: successfulFrames,
        failedFrames: failedFrames,
        detectionsCount: 0, // Not applicable for sentence-based
        averageInferenceMs: averageInferenceMs,
      ),
    );
  }

  void _resetAnalyticsSession() {
    _sessionStartedAt = null;
    _sessionFramesProcessed = 0;
    _sessionSuccessfulFrames = 0;
    _sessionFailedFrames = 0;
    _sessionInferenceTotalMs = 0;
    _sessionInferenceSamples = 0;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool running = _isDetectionRunning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Object Detection'),
        backgroundColor: theme.colorScheme.primary,
      ),
      body: Column(
        children: [
          Expanded(child: _buildLiveDetectionPanel(theme)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _onBottomButtonPressed,
                icon: Icon(
                  running
                      ? Icons.stop_circle_outlined
                      : Icons.play_arrow_rounded,
                ),
                label: Text(running ? 'Tap to Stop' : 'Tap to Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveDetectionPanel(ThemeData theme) {
    if (_isPermissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.no_photography,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              const Text(
                'Camera permission is required for object detection.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isDetectionRunning || !_isCameraReady || _cameraController == null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withAlpha((0.2 * 0xFF).round()),
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.center_focus_strong,
                size: 60,
                color: theme.colorScheme.onSurface.withAlpha((0.7 * 0xFF).round()),
              ),
              const SizedBox(height: 12),
              const Text(
                'Object Detection',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusText,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withAlpha((0.7 * 0xFF).round()),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_cameraController!),
          
          // Sentence Overlay
          Positioned(
            left: 16,
            right: 16,
            top: 20,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 300),
              opacity: _latestSentence.isNotEmpty ? 1.0 : 0.0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha((0.7 * 0xFF).round()),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withAlpha((0.4 * 0xFF).round()),
                  ),
                ),
                child: Text(
                  _latestSentence,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),

          // Status bar at bottom
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
                  fontSize: 13,
                ),
              ),
            ),
          ),

          // Loading indicator
          if (_isRequestInFlight)
            const Positioned(
              top: 10,
              right: 10,
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
