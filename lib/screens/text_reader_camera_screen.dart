import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

class TextReaderCameraScreen extends StatefulWidget {
  final int countdownSeconds;

  const TextReaderCameraScreen({
    super.key,
    this.countdownSeconds = 5,
  });

  @override
  State<TextReaderCameraScreen> createState() => _TextReaderCameraScreenState();
}

class _TextReaderCameraScreenState extends State<TextReaderCameraScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  Timer? _countdownTimer;

  bool _isInitializingCamera = true;
  bool _isCameraReady = false;
  bool _isPermissionDenied = false;
  bool _isTakingPicture = false;
  bool _isDisposing = false;
  bool _hasReturnedCapture = false;

  String _statusText = 'Preparing camera...';
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _remainingSeconds = widget.countdownSeconds;
    unawaited(_initializeCameraAndStartCountdown());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposing || !_isCameraReady) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _cancelCountdown();
      unawaited(_disposeCameraController());
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _cancelCountdown();
    unawaited(_disposeCameraController());
    super.dispose();
  }

  Future<void> _initializeCameraAndStartCountdown() async {
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
      ResolutionPreset.high,
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
      _statusText = 'Auto capture in $_remainingSeconds seconds';
    });

    _startCountdown();
  }

  void _startCountdown() {
    if (!_isCameraReady || _isTakingPicture) return;

    _cancelCountdown();

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _isDisposing || !_isCameraReady || _isTakingPicture) {
        _cancelCountdown();
        return;
      }

      if (_remainingSeconds <= 1) {
        _cancelCountdown();
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

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  Future<void> _disposeCameraController() async {
    final CameraController? controller = _cameraController;
    _cameraController = null;

    if (controller == null) return;

    try {
      if (controller.value.isInitialized) {
        await controller.dispose();
      }
    } catch (_) {
      // Keep this screen safe during rapid navigation.
    }
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
      _cancelCountdown();
      await _disposeCameraController();

      if (!mounted || _isDisposing) return;
      Navigator.of(context).pop<String>(photo.path);
    } on CameraException {
      if (!mounted || _isDisposing) return;
      setState(() {
        _isTakingPicture = false;
        _statusText = 'Capture failed. Please try again.';
      });
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
        message:
            'Please allow camera permission to use timed text capture and try again.',
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
        Positioned(
          top: 24,
          left: 16,
          right: 16,
          child: _buildStatusChip(theme),
        ),
        if (_remainingSeconds > 0)
          Center(
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.75),
                  width: 2,
                ),
              ),
              child: Text(
                '$_remainingSeconds',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        if (_isTakingPicture)
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
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
        style: TextStyle(
          color: theme.colorScheme.onPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCenteredMessage(
    ThemeData theme, {
    required String title,
    required String message,
    bool showLoader = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showLoader) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Text Reader Camera'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () {
            _cancelCountdown();
            Navigator.of(context).pop<String>(null);
          },
        ),
      ),
      body: SafeArea(child: _buildBody(theme)),
    );
  }
}
