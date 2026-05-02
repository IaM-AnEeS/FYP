import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../Services/voice_assistant_service.dart';
import 'text_reader_camera_screen.dart';

enum _TextReaderVoiceCommandType {
  openCamera,
  startLiveReading,
  readRecognizedText,
  goHome,
  goBack,
  unknown,
}

class TextReaderScreen extends StatefulWidget {
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  final bool autoOpenCamera;

  const TextReaderScreen({
    super.key,
    this.autoOpenCamera = false,
  });

  @override
  State<TextReaderScreen> createState() => _TextReaderScreenState();
}

class _TextReaderScreenState extends State<TextReaderScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );
  final VoiceAssistantService _voiceAssistant = VoiceAssistantService.instance;
  final stt.SpeechToText _localSpeech = stt.SpeechToText();

  static const Duration _localCommandListenFor = Duration(seconds: 6);
  static const Duration _localCommandPauseFor = Duration(seconds: 2);

  String? _selectedImagePath;
  String _recognizedText = '';
  String _statusMessage = 'Capture or upload an image to read text.';
  String _lastHeardCommand = '';

  bool _isProcessing = false;
  bool _autoSpeakResult = false;
  bool _hasProcessedImage = false;
  bool _isOpeningAutoCamera = false;
  bool _isListeningForCommand = false;
  bool _localSpeechReady = false;
  bool _localCommandHandled = false;

  Timer? _localCommandTimeoutTimer;

  static const List<String> _cameraCommandPhrases = <String>[
    'open camera',
    'start camera',
    'capture text',
    'read text from camera',
    'read text using camera',
    'open camera for text reading',
    'camera for text reading',
  ];

  static const List<String> _readTextCommandPhrases = <String>[
    'read the text',
    'read text',
    'speak text',
    'read recognized text',
    'speak recognized text',
    'read extracted text',
  ];

  static const List<String> _goHomeCommandPhrases = <String>[
    'go to home screen',
    'go home',
    'home screen',
    'open home',
  ];

  static const List<String> _liveReadingCommandPhrases = <String>[
    'start live reading',
    'live reading',
    'start reading text',
    'read text live',
  ];

  static const List<String> _goBackCommandPhrases = <String>[
    'go back',
    'back',
    'return',
    'close',
  ];

  @override
  void initState() {
    super.initState();
    TextReaderScreen.isActive.value = true;
    if (widget.autoOpenCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openTimedCameraFlow();
      });
    }
  }

  @override
  void dispose() {
    TextReaderScreen.isActive.value = false;
    _localCommandTimeoutTimer?.cancel();
    _localCommandTimeoutTimer = null;
    unawaited(_localSpeech.stop());
    _textRecognizer.close();
    super.dispose();
  }

  Future<void> _captureFromCamera() async {
    if (_isProcessing || _isOpeningAutoCamera || _isListeningForCommand) return;

    final granted = await _ensureCameraPermission();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Camera permission is required for text reading. Grant permission and try again.';
      });
      return;
    }

    await _pickAndRead(ImageSource.camera);
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing || _isOpeningAutoCamera || _isListeningForCommand) {
      return;
    }
    await _pickAndRead(ImageSource.gallery);
  }

  Future<bool> _ensureMicrophonePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> _ensureCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  Future<void> _pickAndRead(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 2200,
        maxHeight: 2200,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (image == null) {
        if (!mounted) return;
        setState(() {
          _statusMessage = 'No image selected.';
        });
        return;
      }

      await _runOcr(image.path);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not open image picker. Please try again.';
      });
    }
  }

  Future<void> _runOcr(String imagePath) async {
    if (!mounted) return;

    setState(() {
      _isProcessing = true;
      _selectedImagePath = imagePath;
      _recognizedText = '';
      _lastHeardCommand = '';
      _statusMessage = 'Reading text from image...';
    });

    try {
      final InputImage inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText result = await _textRecognizer.processImage(
        inputImage,
      );

      final String extracted = result.text.trim();

      if (!mounted) return;
      setState(() {
        _hasProcessedImage = true;
        _recognizedText = extracted;
        if (extracted.isEmpty) {
          _statusMessage = 'No readable text found.';
        } else {
          _statusMessage = 'Text extracted successfully.';
        }
      });

      if (extracted.isNotEmpty && _autoSpeakResult) {
        await _speakText(extracted);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasProcessedImage = true;
        _recognizedText = '';
        _statusMessage =
            'Failed to read text from this image. Try a clearer image.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _speakText(
    String text, {
    bool forceWhenDisabled = false,
  }) async {
    final String content = text.trim();
    if (content.isEmpty) return;

    final String speechPayload = content.length > 1000
        ? '${content.substring(0, 1000)}. Text truncated for speech output.'
        : content;

    await _voiceAssistant.speak(
      speechPayload,
      resumeWakeListening: false,
      forceWhenDisabled: forceWhenDisabled,
    );
  }

  Future<void> _handleScreenTapForCommand() async {
    if (_isProcessing || _isOpeningAutoCamera || _isListeningForCommand) {
      return;
    }

    if (!Platform.isAndroid) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Voice command mode for Text Reader is available on Android only.';
      });
      return;
    }

    final micGranted = await _ensureMicrophonePermission();
    if (!micGranted) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Microphone permission is required for Text Reader voice commands.';
      });
      await _voiceAssistant.speak(
        'Microphone permission is required for text reader commands.',
        resumeWakeListening: false,
        forceWhenDisabled: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isListeningForCommand = true;
      _localCommandHandled = false;
      _lastHeardCommand = '';
      _statusMessage = 'Tell me your command.';
    });

    await _voiceAssistant.speak(
      'Tell me your command.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    if (!mounted || !_isListeningForCommand) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _listenForLocalCommand();
  }

  Future<void> _listenForLocalCommand() async {
    if (!_isListeningForCommand || !mounted) return;

    if (!_localSpeechReady) {
      _localSpeechReady = await _localSpeech.initialize(
        onStatus: _onLocalSpeechStatus,
        onError: _onLocalSpeechError,
        debugLogging: false,
      );
    }

    if (!_localSpeechReady) {
      if (!mounted) return;
      setState(() {
        _isListeningForCommand = false;
        _statusMessage =
            'Voice recognition is unavailable on this device right now.';
      });
      return;
    }

    _localCommandTimeoutTimer?.cancel();
    _localCommandTimeoutTimer = Timer(
      _localCommandListenFor + const Duration(seconds: 1),
      () {
        unawaited(_finishLocalCommandListening(noCommandHeard: true));
      },
    );

    try {
      await _localSpeech.listen(
        onResult: _onLocalSpeechResult,
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        listenFor: _localCommandListenFor,
        pauseFor: _localCommandPauseFor,
        localeId: 'en_US',
      );

      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Listening for command... say open camera, read the text, or go to home screen.';
      });
    } catch (_) {
      await _finishLocalCommandListening(
        noCommandHeard: false,
        customStatus: 'Could not start voice listening. Tap and try again.',
      );
    }
  }

  void _onLocalSpeechResult(dynamic result) {
    final heardText = result.recognizedWords.trim();
    if (heardText.isEmpty || !mounted || !_isListeningForCommand) {
      return;
    }

    setState(() {
      _lastHeardCommand = heardText;
    });

    final _TextReaderVoiceCommandType command =
        _resolveLocalCommand(heardText);

    if (command != _TextReaderVoiceCommandType.unknown &&
        !_localCommandHandled) {
      _localCommandHandled = true;
      unawaited(_handleLocalCommand(command));
      return;
    }

    if (result.finalResult && !_localCommandHandled) {
      unawaited(
        _finishLocalCommandListening(
          noCommandHeard: false,
          customStatus:
              'Command not supported for Text Reader. Say open camera, read the text, or go to home screen.',
        ),
      );
    }
  }

  void _onLocalSpeechStatus(String status) {
    if (!_isListeningForCommand || _localCommandHandled) return;
    if (status == 'done' || status == 'notListening') {
      unawaited(_finishLocalCommandListening(noCommandHeard: true));
    }
  }

  void _onLocalSpeechError(dynamic error) {
    if (!_isListeningForCommand || _localCommandHandled) return;
    unawaited(
      _finishLocalCommandListening(
        noCommandHeard: false,
        customStatus: 'Could not understand command. Tap and try again.',
      ),
    );
  }

  _TextReaderVoiceCommandType _resolveLocalCommand(String rawText) {
    final String normalized = rawText
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\\s]'), ' ')
        .replaceAll(RegExp(r'\\s+'), ' ')
        .trim();

    for (final String phrase in _cameraCommandPhrases) {
      if (normalized.contains(phrase)) {
        return _TextReaderVoiceCommandType.openCamera;
      }
    }

    if (normalized.contains('camera') && normalized.contains('text')) {
      return _TextReaderVoiceCommandType.openCamera;
    }

    for (final String phrase in _readTextCommandPhrases) {
      if (normalized.contains(phrase)) {
        return _TextReaderVoiceCommandType.readRecognizedText;
      }
    }

    for (final String phrase in _liveReadingCommandPhrases) {
      if (normalized.contains(phrase)) {
        return _TextReaderVoiceCommandType.startLiveReading;
      }
    }

    for (final String phrase in _goHomeCommandPhrases) {
      if (normalized.contains(phrase)) {
        return _TextReaderVoiceCommandType.goHome;
      }
    }

    for (final String phrase in _goBackCommandPhrases) {
      if (normalized.contains(phrase)) {
        return _TextReaderVoiceCommandType.goBack;
      }
    }

    return _TextReaderVoiceCommandType.unknown;
  }

  Future<void> _handleLocalCommand(_TextReaderVoiceCommandType command) async {
    switch (command) {
      case _TextReaderVoiceCommandType.openCamera:
        await _handleLocalCameraCommand();
        return;
      case _TextReaderVoiceCommandType.startLiveReading:
        await _handleLiveReadingCommand();
        return;
      case _TextReaderVoiceCommandType.readRecognizedText:
        await _handleReadRecognizedTextCommand();
        return;
      case _TextReaderVoiceCommandType.goHome:
        await _handleGoHomeCommand();
        return;
      case _TextReaderVoiceCommandType.goBack:
        await _handleGoBackCommand();
        return;
      case _TextReaderVoiceCommandType.unknown:
        return;
    }
  }

  Future<void> _handleLocalCameraCommand() async {
    await _finishLocalCommandListening(
      noCommandHeard: false,
      customStatus: 'Opening camera for text reading...',
    );

    await _voiceAssistant.speak(
      'Opening camera for text reading.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    await _openTimedCameraFlow();
  }

  Future<void> _handleReadRecognizedTextCommand() async {
    await _finishLocalCommandListening(
      noCommandHeard: false,
      customStatus: 'Reading recognized text...',
    );

    final String extractedText = _recognizedText.trim();
    if (extractedText.isEmpty) {
      if (mounted) {
        setState(() {
          _statusMessage = 'No readable text found.';
        });
      }
      await _voiceAssistant.speak(
        'No readable text found.',
        resumeWakeListening: false,
        forceWhenDisabled: true,
      );
      return;
    }

    await _speakText(
      extractedText,
      forceWhenDisabled: true,
    );

    if (!mounted) return;
    setState(() {
      _statusMessage = 'Recognized text spoken.';
    });
  }

  Future<void> _handleGoHomeCommand() async {
    await _finishLocalCommandListening(
      noCommandHeard: false,
      customStatus: 'Going to home screen...',
    );

    await _voiceAssistant.speak(
      'Going to home screen.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (_) => false);
  }

  Future<void> _handleGoBackCommand() async {
    await _finishLocalCommandListening(
      noCommandHeard: false,
      customStatus: 'Going back...',
    );

    await _voiceAssistant.speak(
      'Going back.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _handleLiveReadingCommand() async {
    await _finishLocalCommandListening(
      noCommandHeard: false,
      customStatus: 'Starting live reading...',
    );

    await _voiceAssistant.speak(
      'Starting live reading mode.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    if (!mounted) return;
    
    await Navigator.of(context).push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/text-reader-live'),
        builder: (_) => const TextReaderCameraScreen(
          liveMode: true,
        ),
      ),
    );
  }

  Future<void> _finishLocalCommandListening({
    required bool noCommandHeard,
    String? customStatus,
  }) async {
    _localCommandTimeoutTimer?.cancel();
    _localCommandTimeoutTimer = null;

    if (_localSpeech.isListening) {
      try {
        await _localSpeech.stop();
      } catch (_) {
        // Keep the screen stable if stopping speech fails.
      }
    }

    if (!mounted) return;
    setState(() {
      _isListeningForCommand = false;

      if (customStatus != null) {
        _statusMessage = customStatus;
      } else if (noCommandHeard) {
        _statusMessage =
            'I did not catch a command. Tap anywhere and try again.';
      }
    });
  }

  Future<void> _openTimedCameraFlow() async {
    if (!Platform.isAndroid) {
      if (!mounted) return;
      setState(() {
        _statusMessage =
            'Auto camera countdown mode is currently available on Android only.';
      });
      return;
    }

    if (_isOpeningAutoCamera || _isProcessing) return;

    if (!mounted) return;
    setState(() {
      _isOpeningAutoCamera = true;
      _statusMessage = 'Opening camera for 5 second auto capture...';
    });

    try {
      final String? capturedImagePath =
          await Navigator.of(context).push<String>(
            MaterialPageRoute<String>(
              settings: const RouteSettings(name: '/text-reader-camera'),
              builder: (_) => const TextReaderCameraScreen(
                countdownSeconds: 5,
              ),
            ),
          );

      if (!mounted) return;

      if (capturedImagePath == null || capturedImagePath.trim().isEmpty) {
        setState(() {
          _statusMessage = 'Camera closed before capture.';
        });
        return;
      }

      await _runOcr(capturedImagePath);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not open the camera. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningAutoCamera = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            theme.appBarTheme.backgroundColor ?? theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: theme.colorScheme.onSurface,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Text Reader',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleScreenTapForCommand,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Capture an image of printed text, labels, signs, or documents and extract readable text.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap anywhere on this screen and say a command like open camera.',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_isProcessing ||
                                _isOpeningAutoCamera ||
                                _isListeningForCommand)
                            ? null
                            : _captureFromCamera,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Capture Image'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: (_isProcessing ||
                                _isOpeningAutoCamera ||
                                _isListeningForCommand)
                            ? null
                            : _pickFromGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Upload Image'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Speak extracted text automatically'),
                  subtitle: const Text('Optional voice output after OCR'),
                  value: _autoSpeakResult,
                  onChanged: (_isProcessing ||
                          _isOpeningAutoCamera ||
                          _isListeningForCommand)
                      ? null
                      : (value) {
                          setState(() {
                            _autoSpeakResult = value;
                          });
                        },
                ),
                const SizedBox(height: 10),
                if (_isListeningForCommand)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mic_none,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _lastHeardCommand.isEmpty
                                ? 'Listening for command...'
                                : 'Heard: $_lastHeardCommand',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_isProcessing || _isOpeningAutoCamera)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _statusMessage,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                if (_selectedImagePath != null)
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.35),
                      ),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Image.file(
                      File(_selectedImagePath!),
                      fit: BoxFit.cover,
                      height: 220,
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  'Recognized Text',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(minHeight: 180),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.dividerColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: _recognizedText.isEmpty
                      ? Text(
                          _hasProcessedImage
                              ? 'No readable text found.'
                              : 'OCR result will appear here after scanning an image.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        )
                      : SelectableText(
                          _recognizedText,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            height: 1.45,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: (_isProcessing ||
                            _isOpeningAutoCamera ||
                            _isListeningForCommand ||
                            _recognizedText.trim().isEmpty)
                        ? null
                        : () => _speakText(_recognizedText),
                    icon: const Icon(Icons.record_voice_over_outlined),
                    label: const Text('Speak Recognized Text'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
