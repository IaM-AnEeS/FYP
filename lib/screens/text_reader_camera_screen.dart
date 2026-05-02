import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../Services/voice_assistant_service.dart';

class TextReaderCameraScreen extends StatefulWidget {
  final int countdownSeconds;
  final bool liveMode;

  const TextReaderCameraScreen({
    super.key,
    this.countdownSeconds = 5,
    this.liveMode = false,
  });

  @override
  State<TextReaderCameraScreen> createState() => _TextReaderCameraScreenState();
}

class _TextReaderCameraScreenState extends State<TextReaderCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  Timer? _countdownTimer;
  Timer? _liveScanTimer;

  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  final stt.SpeechToText _localSpeech = stt.SpeechToText();
  bool _localSpeechReady = false;
  bool _isListeningForGoBack = false;

  bool _isInitializingCamera = true;
  bool _isCameraReady = false;
  bool _isPermissionDenied = false;
  bool _isTakingPicture = false;
  bool _isDisposing = false;
  bool _hasReturnedCapture = false;

  String _statusText = 'Preparing camera...';
  String _liveRecognizedText = '';
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remainingSeconds = widget.countdownSeconds;
    unawaited(_initializeCameraAndStartFlow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposing || !_isCameraReady) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _cancelTimers();
      unawaited(_disposeCameraController());
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _cancelTimers();
    _textRecognizer.close();
    unawaited(_localSpeech.stop());
    unawaited(_disposeCameraController());
    super.dispose();
  }

  void _cancelTimers() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _liveScanTimer?.cancel();
    _liveScanTimer = null;
  }

  Future<void> _initializeCameraAndStartFlow() async {
    final PermissionStatus status = await Permission.camera.request();

    if (!mounted || _isDisposing) return;

    if (!status.isGranted) {
      setState(() {
        _isPermissionDenied = true;
        _isInitializingCamera = false;
        _statusText = 'Camera permission denied.';
      });
      return;
    }

    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } catch (_) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _isInitializingCamera = false;
        _statusText = 'Could not access the camera.';
      });
      return;
    }

    if (!mounted || _isDisposing) return;

    if (cameras.isEmpty) {
      setState(() {
        _isInitializingCamera = false;
        _statusText = 'No camera found on this device.';
      });
      return;
    }

    final CameraDescription selectedCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final CameraController controller = CameraController(
      selectedCamera,
      widget.liveMode ? ResolutionPreset.medium : ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    _cameraController = controller;

    try {
      await controller.initialize();
    } catch (_) {
      if (!mounted || _isDisposing) return;
      await _disposeCameraController();
      setState(() {
        _isInitializingCamera = false;
        _isCameraReady = false;
        _statusText = 'Could not initialize camera.';
      });
      return;
    }

    if (!mounted || _isDisposing || !identical(_cameraController, controller)) {
      await _disposeCameraController();
      return;
    }

    setState(() {
      _isInitializingCamera = false;
      _isCameraReady = true;
      _statusText = widget.liveMode
          ? 'Live Reading Active'
          : 'Auto capture in $_remainingSeconds seconds';
    });

    if (widget.liveMode) {
      _startLiveScan();
    } else {
      _startCountdown();
    }
  }

  void _startCountdown() {
    if (!_isCameraReady || _isTakingPicture) return;

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isDisposing || !_isCameraReady || _isTakingPicture) {
        timer.cancel();
        return;
      }

      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
          _statusText = 'Capturing image...';
        });
        unawaited(_takePictureAndReturn());
        return;
      }

      setState(() {
        _remainingSeconds -= 1;
        _statusText = 'Auto capture in $_remainingSeconds seconds';
      });
    });
  }

  void _startLiveScan() {
    if (!_isCameraReady || _isDisposing) return;

    _liveScanTimer?.cancel();
    _liveScanTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (!mounted || _isDisposing || !_isCameraReady) {
        timer.cancel();
        return;
      }
      unawaited(_performLiveOcr());
    });
  }

  Future<void> _performLiveOcr() async {
    if (_isTakingPicture || _isDisposing) return;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    try {
      _isTakingPicture = true;
      final XFile photo = await controller.takePicture();
      if (_isDisposing || !mounted) return;

      final InputImage inputImage = InputImage.fromFilePath(photo.path);
      final RecognizedText result = await _textRecognizer.processImage(inputImage);
      
      // Clean up the temporary photo immediately
      final file = File(photo.path);
      if (await file.exists()) {
        await file.delete();
      }

      final String text = result.text.trim();
      if (!mounted || _isDisposing) return;

      if (text.isNotEmpty) {
        setState(() {
          _liveRecognizedText = text;
        });
        // Speak using the voice assistant's specialized live OCR logic
        unawaited(VoiceAssistantService.instance.speakLiveOcrText(text));
      }
    } catch (e) {
      debugPrint('Live OCR error: $e');
    } finally {
      _isTakingPicture = false;
    }
  }

  Future<void> _handleTapForGoBack() async {
    if (_isListeningForGoBack || _isDisposing) return;

    if (!Platform.isAndroid) return;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return;

    if (!_localSpeechReady) {
      _localSpeechReady = await _localSpeech.initialize();
    }

    if (!_localSpeechReady || !mounted) return;

    setState(() {
      _isListeningForGoBack = true;
    });

    await VoiceAssistantService.instance.speak(
      'Listening. Say go back to exit.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    await _localSpeech.listen(
      onResult: (result) {
        final heard = result.recognizedWords.toLowerCase();
        if (heard.contains('go back') || heard.contains('back') || heard.contains('exit')) {
          _localSpeech.stop();
          Navigator.of(context).pop();
        }
      },
      listenFor: const Duration(seconds: 4),
      pauseFor: const Duration(seconds: 2),
    );

    await Future.delayed(const Duration(seconds: 4));
    if (mounted) {
      setState(() {
        _isListeningForGoBack = false;
      });
    }
  }

  Future<void> _disposeCameraController() async {
    final CameraController? controller = _cameraController;
    _cameraController = null;

    if (controller == null) return;

    try {
      if (controller.value.isInitialized) {
        await controller.dispose();
      }
    } catch (_) {}
  }

  Future<void> _takePictureAndReturn() async {
    if (_isTakingPicture || _hasReturnedCapture) return;

    final CameraController? controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _statusText = 'Camera is not ready for capture.';
      });
      return;
    }

    setState(() {
      _isTakingPicture = true;
    });

    try {
      final XFile photo = await controller.takePicture();

      if (!mounted || _isDisposing) return;

      _hasReturnedCapture = true;
      _cancelTimers();
      await _disposeCameraController();

      if (!mounted || _isDisposing) return;
      Navigator.of(context).pop<String>(photo.path);
    } catch (_) {
      if (!mounted || _isDisposing) return;
      setState(() {
        _isTakingPicture = false;
        _statusText = 'Capture failed. Please try again.';
      });
    }
  }

  Widget _buildBody(ThemeData theme) {
    if (_isPermissionDenied) {
      return _buildCenteredMessage(
        theme,
        title: 'Camera Permission Needed',
        message: 'Please allow camera permission to use text capture.',
      );
    }

    if (_isInitializingCamera) {
      return _buildCenteredMessage(
        theme,
        title: 'Opening Camera',
        message: _statusText,
        showLoader: true,
      );
    }

    final CameraController? controller = _cameraController;
    if (!_isCameraReady || controller == null || !controller.value.isInitialized) {
      return _buildCenteredMessage(
        theme,
        title: 'Camera Unavailable',
        message: _statusText,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(controller),
        
        // --- Header Status ---
        Positioned(
          top: 24,
          left: 16,
          right: 16,
          child: _buildStatusChip(theme),
        ),

        // --- Live OCR Result Overlay ---
        if (widget.liveMode && _liveRecognizedText.isNotEmpty)
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _liveRecognizedText,
                  style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
                ),
              ),
            ),
          ),

        // --- Countdown indicator ---
        if (!widget.liveMode && _remainingSeconds > 0)
          Center(
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white70, width: 2),
              ),
              child: Text(
                '$_remainingSeconds',
                style: const TextStyle(color: Colors.white, fontSize: 56, fontWeight: FontWeight.bold),
              ),
            ),
          ),

        // --- Listening indicator ---
        if (_isListeningForGoBack)
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mic, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('Listening for "Go Back"', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ),

        if (_isTakingPicture && !widget.liveMode)
          const Center(child: CircularProgressIndicator(color: Colors.white)),
      ],
    );
  }

  Widget _buildStatusChip(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _statusText,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildCenteredMessage(ThemeData theme, {required String title, required String message, bool showLoader = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showLoader) ...[const CircularProgressIndicator(), const SizedBox(height: 18)],
            Text(title, style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.8), height: 1.4)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.liveMode ? 'Live Reading' : 'Text Reader Camera'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            _cancelTimers();
            Navigator.of(context).pop<String>(null);
          },
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTapForGoBack,
        child: SafeArea(child: _buildBody(Theme.of(context))),
      ),
    );
  }
}

