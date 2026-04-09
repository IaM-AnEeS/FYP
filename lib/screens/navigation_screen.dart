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
import '../models/detection.dart';
import '../painters/detection_painter.dart';

const bool kShowNavigationDebugPanel = true;

enum NavigationMode {
  indoor,
  outdoor,
}

class NavigationScreen extends StatefulWidget {
  final String initialMode;
  final bool autoStartDetection;

  const NavigationScreen({
    super.key,
    this.initialMode = 'Indoor',
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

  late NavigationMode _selectedMode;
  NavigationMode? _activeMode;
  int _captureSession = 0;

  CameraController? _cameraController;
  Timer? _captureTimer;

  bool _isCameraReady = false;
  bool _isDetectionRunning = false;
  bool _isRequestInFlight = false;
  bool _isPermissionDenied = false;
  bool _isDisposing = false;

  List<Detection> _detections = [];
  int _imageWidth = 1;
  int _imageHeight = 1;

  String _statusText = 'Select a mode and tap to start detection';
  double _lastInferenceMs = 0;
  int _detectionCount = 0;

  DateTime? _sessionStartedAt;
  String? _sessionMode;
  int _sessionFramesProcessed = 0;
  int _sessionSuccessfulFrames = 0;
  int _sessionFailedFrames = 0;
  int _sessionDetectionsTotal = 0;
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

  String _modeTitle(NavigationMode mode) {
    return mode == NavigationMode.indoor ? 'Indoor' : 'Outdoor';
  }

  DetectionBackendMode _backendModeFor(NavigationMode mode) {
    return mode == NavigationMode.indoor
        ? DetectionBackendMode.indoor
        : DetectionBackendMode.outdoor;
  }

  String _idleStatusFor(NavigationMode mode) {
    return '${_modeTitle(mode)} mode ready. Tap to Start.';
  }

  String _permissionTextFor(NavigationMode mode) {
    return 'Camera permission is required for ${_modeTitle(mode).toLowerCase()} detection.';
  }

  String _noDetectionsStatusFor(NavigationMode mode) {
    return mode == NavigationMode.indoor
        ? 'No indoor objects detected'
        : 'No outdoor objects detected';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedMode = widget.initialMode.toLowerCase() == 'outdoor'
        ? NavigationMode.outdoor
        : NavigationMode.indoor;
    _statusText = _idleStatusFor(_selectedMode);

    _voiceBridge.setNavigationVisible(true);
    _voiceBridge.setDetectionRunning(false);
    _voiceCommandSub = _voiceBridge.commands.listen((command) {
      unawaited(_handleVoiceCommand(command));
    });

    if (widget.autoStartDetection) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_startDetectionForSelectedMode());
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
      case NavigationVoiceCommandType.selectIndoor:
        _onModeSelected(NavigationMode.indoor);
        break;
      case NavigationVoiceCommandType.selectOutdoor:
        _onModeSelected(NavigationMode.outdoor);
        break;
      case NavigationVoiceCommandType.startIndoorDetection:
        _onModeSelected(NavigationMode.indoor);
        await _startDetectionForSelectedMode();
        break;
      case NavigationVoiceCommandType.startOutdoorDetection:
        _onModeSelected(NavigationMode.outdoor);
        await _startDetectionForSelectedMode();
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

  void _onModeSelected(NavigationMode mode) {
    if (_selectedMode == mode) return;

    if (_isDetectionRunning) {
      _stopDetection(
        statusText: 'Detection stopped. Tap to Start to run again.',
      );
    }

    setState(() {
      _selectedMode = mode;
      _isPermissionDenied = false;
      _statusText = _idleStatusFor(mode);
    });
  }

  Future<void> _onBottomButtonPressed() async {
    if (_isDetectionRunning) {
      _stopDetection(statusText: 'Detection stopped.');
      return;
    }

    await _startDetectionForSelectedMode();
  }

  Future<void> _startDetectionForSelectedMode() async {
    if (_isDisposing) return;

    if (_isDetectionRunning) {
      debugPrint(
        '[NavigationVoice] Ignored start request because detection is already running.',
      );

      if (mounted) {
        setState(() {
          _statusText =
              'Detection already running in ${_modeTitle(_activeMode ?? _selectedMode)} mode.';
        });
      }
      return;
    }

    final NavigationMode modeToStart = _selectedMode;
    final int session = ++_captureSession;
    _frameLogService.resetSession();
    _resetAnalyticsSession();
    _sessionStartedAt = DateTime.now();
    _sessionMode = modeToStart == NavigationMode.indoor ? 'indoor' : 'outdoor';

    debugPrint(
      '[NavigationVoice] Starting detection for ${_modeTitle(modeToStart)} mode. session=$session',
    );

    setState(() {
      _activeMode = modeToStart;
      _isPermissionDenied = false;
      _statusText = 'Initialising camera for ${_modeTitle(modeToStart)}...';
    });

    await _initCamera(modeToStart, session);
  }

  Future<void> _initCamera(NavigationMode modeToStart, int session) async {
    if (_isDisposing) return;

    final status = await Permission.camera.request();
    if (!_isSessionValid(session) || _activeMode != modeToStart) return;

    if (!status.isGranted) {
      if (mounted) {
        setState(() {
          _isPermissionDenied = true;
          _activeMode = null;
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
          _activeMode = null;
          _statusText = 'Camera error: $e';
        });
        _voiceBridge.setDetectionRunning(false);
      }
      return;
    }

    if (!_isSessionValid(session) || _activeMode != modeToStart) return;

    if (cameras.isEmpty) {
      if (mounted) {
        setState(() {
          _activeMode = null;
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
          _activeMode = null;
          _statusText = 'Camera init error: $e';
        });
        _voiceBridge.setDetectionRunning(false);
      }
      return;
    }

    if (!mounted ||
        !_isSessionValid(session, controller: controller) ||
        _activeMode != modeToStart) {
      _stopDetection(setIdleMessage: false);
      return;
    }

    setState(() {
      _isCameraReady = true;
      _isDetectionRunning = true;
      _statusText =
          'Connecting to ${_modeTitle(modeToStart).toLowerCase()} server...';
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
      _activeMode = null;
      _detections = [];
      _detectionCount = 0;
      _lastInferenceMs = 0;

      if (statusText != null) {
        _statusText = statusText;
      } else if (setIdleMessage) {
        _statusText = _idleStatusFor(_selectedMode);
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

    final NavigationMode? activeMode = _activeMode;
    if (_isRequestInFlight ||
        !_isDetectionRunning ||
        activeMode == null ||
        _isDisposing) {
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

      final PredictResult result = activeMode == NavigationMode.indoor
          ? await DetectionService.predictIndoor(jpegToSend)
          : await DetectionService.predictOutdoor(jpegToSend);

      if (!mounted ||
          !_isSessionValid(session, controller: controller) ||
          _activeMode != activeMode) {
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
        _sessionInferenceTotalMs += resp.inferenceMs;
        _sessionInferenceSamples += 1;

        if (resp.detections.isEmpty) {
          setState(() {
            _detections = [];
            _detectionCount = 0;
            _lastInferenceMs = resp.inferenceMs;
            _statusText = _noDetectionsStatusFor(activeMode);
          });
        } else {
          _sessionDetectionsTotal += resp.detections.length;

          final modeText = activeMode == NavigationMode.indoor
              ? 'indoor'
              : 'outdoor';
          final backendUrl =
              DetectionService.baseUrlForMode(_backendModeFor(activeMode));

          unawaited(
            VoiceAssistantService.instance.announceDetections(
              mode: modeText,
              detections: resp.detections,
            ),
          );

          unawaited(
            _frameLogService.logFrame(
              mode: modeText,
              backendUrl: backendUrl,
              detections: resp.detections,
              imageWidth: resp.imageWidth,
              imageHeight: resp.imageHeight,
              inferenceMs: resp.inferenceMs,
            ),
          );

          setState(() {
            _detections = resp.detections;
            _imageWidth = resp.imageWidth;
            _imageHeight = resp.imageHeight;
            _detectionCount = resp.detections.length;
            _lastInferenceMs = resp.inferenceMs;
            _statusText =
                '${resp.detections.length} object(s) · ${resp.inferenceMs.toStringAsFixed(0)} ms';
          });
        }
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
    final mode = _sessionMode;
    if (startedAt == null || mode == null) {
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
    final detectionsCount = _sessionDetectionsTotal;

    _resetAnalyticsSession();

    unawaited(
      _analyticsService.recordDetectionSession(
        mode: mode,
        startedAt: startedAt,
        endedAt: endedAt,
        framesProcessed: framesProcessed,
        successfulFrames: successfulFrames,
        failedFrames: failedFrames,
        detectionsCount: detectionsCount,
        averageInferenceMs: averageInferenceMs,
      ),
    );
  }

  void _resetAnalyticsSession() {
    _sessionStartedAt = null;
    _sessionMode = null;
    _sessionFramesProcessed = 0;
    _sessionSuccessfulFrames = 0;
    _sessionFailedFrames = 0;
    _sessionDetectionsTotal = 0;
    _sessionInferenceTotalMs = 0;
    _sessionInferenceSamples = 0;
  }

  Widget _modeButton(NavigationMode mode) {
    final bool selected = _selectedMode == mode;
    final theme = Theme.of(context);
    return Expanded(
      child: ElevatedButton(
        onPressed: () => _onModeSelected(mode),
        style: ElevatedButton.styleFrom(
          backgroundColor: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surface.withAlpha((0.9 * 0xFF).round()),
          foregroundColor:
              selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        ),
        child: Text(_modeTitle(mode)),
      ),
    );
  }

  Widget _buildModeButtons() {
    return Row(
      children: [
        _modeButton(NavigationMode.indoor),
        const SizedBox(width: 8),
        _modeButton(NavigationMode.outdoor),
      ],
    );
  }

  Widget _buildIdlePanel(ThemeData theme, NavigationMode mode) {
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
              mode == NavigationMode.indoor
                  ? Icons.home_work_outlined
                  : Icons.navigation,
              size: 60,
              color: theme.colorScheme.onSurface.withAlpha((0.7 * 0xFF).round()),
            ),
            const SizedBox(height: 12),
            Text(
              '${_modeTitle(mode)} mode selected',
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _idleStatusFor(mode),
              style: TextStyle(
                color:
                    theme.colorScheme.onSurface.withAlpha((0.7 * 0xFF).round()),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveDetectionPanel(ThemeData theme, NavigationMode mode) {
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
              Text(
                _permissionTextFor(mode),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 15,
                ),
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
      return _buildIdlePanel(theme, mode);
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
          if (kShowNavigationDebugPanel)
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
                      'Mode: ${_modeTitle(mode)}',
                      style:
                          const TextStyle(color: Colors.greenAccent, fontSize: 11),
                    ),
                    Text(
                      'URL: ${DetectionService.baseUrlForMode(_backendModeFor(mode))}',
                      style:
                          const TextStyle(color: Colors.greenAccent, fontSize: 11),
                    ),
                    Text(
                      'Inference: ${_lastInferenceMs.toStringAsFixed(0)} ms',
                      style:
                          const TextStyle(color: Colors.greenAccent, fontSize: 11),
                    ),
                    Text(
                      'Detections: $_detectionCount',
                      style:
                          const TextStyle(color: Colors.greenAccent, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool running = _isDetectionRunning;
    final NavigationMode panelMode = _activeMode ?? _selectedMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Navigation'),
        backgroundColor: theme.colorScheme.primary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: _buildModeButtons(),
          ),
          Expanded(
            child: _buildLiveDetectionPanel(theme, panelMode),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _onBottomButtonPressed,
                icon: Icon(
                  running ? Icons.stop_circle_outlined : Icons.play_arrow_rounded,
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
}
