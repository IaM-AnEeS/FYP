import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/detection.dart';
import '../screens/navigation_screen.dart' as nav;
import '../screens/text_reader.dart';
import '../theme/color_scheme_manager.dart';
import '../theme/theme_manager.dart';
import 'navigation_voice_bridge.dart';
import 'voice_command_parser.dart';
import 'voice_screen_access_policy.dart';

class _VoiceAssistantNavigatorObserver extends NavigatorObserver {
  void _notify(Route<dynamic>? route) {
    VoiceAssistantService.instance.onRouteChanged(route);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notify(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notify(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _notify(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notify(previousRoute);
  }
}

class _VoicePreset {
  final double pitch;
  final double speed;

  const _VoicePreset({required this.pitch, required this.speed});
}

class _TtsVoiceCandidate {
  final String name;
  final String locale;
  final Map<String, String> raw;

  const _TtsVoiceCandidate({
    required this.name,
    required this.locale,
    required this.raw,
  });

  String get searchable {
    final buffer = StringBuffer();
    buffer.write(name.toLowerCase());
    buffer.write(' ');
    buffer.write(locale.toLowerCase());
    for (final entry in raw.entries) {
      buffer.write(' ');
      buffer.write(entry.key.toLowerCase());
      buffer.write(' ');
      buffer.write(entry.value.toLowerCase());
    }
    return buffer.toString();
  }
}

enum _VoiceMode {
  idle,
  commandListening,
  speaking,
  paused,
}

class VoiceAssistantService {
  VoiceAssistantService._();

  static final VoiceAssistantService instance = VoiceAssistantService._();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static final NavigatorObserver navigatorObserver =
      _VoiceAssistantNavigatorObserver();

  static const String wakePhrase = 'hi';
  static const Duration _wakeTriggerCooldown = Duration(seconds: 2);
  static const Duration _tapTriggerCooldown = Duration(milliseconds: 900);
  static const Duration _commandModeInactivityTimeout = Duration(seconds: 10);
  static const double _wakeConfidenceThreshold = 0.45;
  static const double _wakeHighConfidencePartial = 0.88;
  static const int _maxWakePhraseWords = 3;
  static const Duration commandListenDuration = Duration(seconds: 5);
  static const Duration _postPromptDelay = Duration(milliseconds: 500);
  static const Duration _commandPauseFor = Duration(seconds: 2);

  static const String _prefVoiceEnabled = 'voice_assistant_enabled';
  static const String _prefMicAsked = 'voice_assistant_mic_asked';
  static const String _prefVoicePitch = 'voice_assistant_pitch';
  static const String _prefVoiceRate = 'voice_assistant_rate';
  static const String _prefVoiceType = 'voice_assistant_voice_type';
  static const String _prefVoicePersonality =
      'voice_assistant_voice_personality';

  static const String _voiceTypeFemale = 'Female';
  static const String _voiceTypeMale = 'Male';
  static const String _voiceTypeNeutral = 'Neutral';

  static const String _personalityCalm = 'Calm';
  static const String _personalityEnergetic = 'Energetic';
  static const String _personalityFriendly = 'Friendly';

  static const Map<String, _VoicePreset> _voicePresets = {
    _personalityCalm: _VoicePreset(pitch: 1.0, speed: 0.42),
    _personalityEnergetic: _VoicePreset(pitch: 1.0, speed: 0.62),
    _personalityFriendly: _VoicePreset(pitch: 1.0, speed: 0.52),
  };

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  final ValueNotifier<bool> assistantEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isListening = ValueNotifier<bool>(false);
  final ValueNotifier<bool> microphoneGranted = ValueNotifier<bool>(false);
  final ValueNotifier<String> assistantStateText =
      ValueNotifier<String>('Voice assistant idle');
  final ValueNotifier<String> lastHeardText = ValueNotifier<String>('');
  final ValueNotifier<String> activeRoute = ValueNotifier<String>('unknown');
  final ValueNotifier<String> selectedVoiceType =
      ValueNotifier<String>(_voiceTypeNeutral);
  final ValueNotifier<String> selectedPersonality =
      ValueNotifier<String>(_personalityFriendly);
  final ValueNotifier<String> selectedVoiceLabel =
      ValueNotifier<String>('Default device voice');
  final ValueNotifier<String> voiceSupportNote = ValueNotifier<String>(
    'Available voices depend on your Android device and TTS engine.',
  );

  bool _initialized = false;
  bool _speechReady = false;
  bool _isCommandCapture = false;
  bool _commandCaptured = false;
  bool _isSpeaking = false;
  bool _appForeground = true;
  bool _isFinalizingCommand = false;
  bool _isStartingCommandListen = false;
  bool _commandModeActive = false;
  bool _adminFlowActive = false;
  _VoiceMode _voiceMode = _VoiceMode.idle;

  double _pitch = 1.0;
  double _speechRate = 0.48;

  int _commandSessionId = 0;
  String _commandBestTranscript = '';
  DateTime? _commandWindowEndsAt;
  Timer? _commandWindowTimer;
  Timer? _wakeRearmTimer;
  Timer? _commandModeTimeoutTimer;

  List<_TtsVoiceCandidate> _availableVoices = <_TtsVoiceCandidate>[];
  _TtsVoiceCandidate? _activeVoice;

  DateTime _lastWakeDetectedAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTapTriggeredAt = DateTime.fromMillisecondsSinceEpoch(0);

  DateTime _lastDetectionAnnouncementAt =
      DateTime.fromMillisecondsSinceEpoch(0);
  String _lastDetectionSignature = '';

  double get pitch => _pitch;
  double get speechRate => _speechRate;
  String get voiceType => selectedVoiceType.value;
  String get personality => selectedPersonality.value;
  bool get hasVoicesDiscovered => _availableVoices.isNotEmpty;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!Platform.isAndroid) {
      assistantEnabled.value = false;
      assistantStateText.value =
          'Voice assistant is currently available on Android only.';
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    assistantEnabled.value = prefs.getBool(_prefVoiceEnabled) ?? true;
    _pitch = prefs.getDouble(_prefVoicePitch) ?? 1.0;
    _speechRate = prefs.getDouble(_prefVoiceRate) ?? 0.48;
    selectedVoiceType.value =
        _normalizeVoiceType(prefs.getString(_prefVoiceType));
    selectedPersonality.value =
        _normalizePersonality(prefs.getString(_prefVoicePersonality));

    await _configureTts();
    await refreshAvailableVoices();
    await _applyVoiceTypeSelection();
    await _ensureMicrophonePermissionOnFirstLaunch(prefs);
    await _initializeSpeechRecognizer();

    if (assistantEnabled.value && microphoneGranted.value && _speechReady) {
      _setIdleTapPromptState();
    } else if (!microphoneGranted.value) {
      assistantStateText.value = 'Microphone permission is required.';
    }
  }

  Future<void> _configureTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setPitch(_pitch);
    await _tts.setSpeechRate(_speechRate);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> refreshAvailableVoices() async {
    if (!Platform.isAndroid) {
      _availableVoices = <_TtsVoiceCandidate>[];
      selectedVoiceLabel.value = 'Voice selection is Android-only.';
      return;
    }

    try {
      final dynamic voicesDynamic = await _tts.getVoices;
      final List<_TtsVoiceCandidate> parsed = <_TtsVoiceCandidate>[];

      if (voicesDynamic is List) {
        for (final dynamic item in voicesDynamic) {
          if (item is Map) {
            final Map<String, String> normalized =
                <String, String>{};
            item.forEach((dynamic key, dynamic value) {
              normalized[key.toString()] = value?.toString() ?? '';
            });

            final String name = _firstNonEmpty(<String?>[
              normalized['name'],
              normalized['identifier'],
              normalized['id'],
              normalized['voice'],
            ]);

            if (name.isEmpty) continue;

            final String locale = _firstNonEmpty(<String?>[
              normalized['locale'],
              normalized['language'],
              normalized['lang'],
            ], fallback: 'en-US');

            parsed.add(
              _TtsVoiceCandidate(name: name, locale: locale, raw: normalized),
            );
          }
        }
      }

      parsed.sort((a, b) {
        final bool aEnglish = a.locale.toLowerCase().startsWith('en');
        final bool bEnglish = b.locale.toLowerCase().startsWith('en');
        if (aEnglish != bEnglish) return aEnglish ? -1 : 1;
        return a.name.compareTo(b.name);
      });

      _availableVoices = parsed;

      if (_availableVoices.isEmpty) {
        selectedVoiceLabel.value = 'Using default device voice';
      }

      voiceSupportNote.value = _buildVoiceSupportNote();
    } catch (_) {
      _availableVoices = <_TtsVoiceCandidate>[];
      selectedVoiceLabel.value = 'Using default device voice';
      voiceSupportNote.value =
          'Could not read available voices. Default device voice is being used.';
    }
  }

  Future<void> _ensureMicrophonePermissionOnFirstLaunch(
    SharedPreferences prefs,
  ) async {
    final asked = prefs.getBool(_prefMicAsked) ?? false;

    if (!asked) {
      await prefs.setBool(_prefMicAsked, true);
      await requestMicrophonePermission();
      return;
    }

    microphoneGranted.value = await Permission.microphone.isGranted;
  }

  Future<void> _initializeSpeechRecognizer() async {
    if (!microphoneGranted.value) {
      _speechReady = false;
      return;
    }

    _speechReady = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (error) {
        assistantStateText.value =
            'Speech error: ${error.errorMsg}. Tap mic to try again.';
      },
      debugLogging: false,
    );

    if (!_speechReady) {
      assistantStateText.value =
          'Speech recognition unavailable on this device.';
    }
  }

  Future<void> setForegroundActive(bool active) async {
    _appForeground = active;

    if (!active) {
      _voiceMode = _VoiceMode.paused;
      _commandModeActive = false;
      _commandModeTimeoutTimer?.cancel();
      _wakeRearmTimer?.cancel();
      _clearCommandSessionState();
      await _stopListening();
      return;
    }

    _voiceMode = _VoiceMode.idle;

    if (assistantEnabled.value && microphoneGranted.value && _speechReady) {
      if (_commandModeActive) {
        await _listenForCommand();
      } else {
        _setIdleTapPromptState();
      }
    }
  }

  Future<void> setAssistantEnabled(bool enabled) async {
    assistantEnabled.value = enabled;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefVoiceEnabled, enabled);

    if (!enabled) {
      _voiceMode = _VoiceMode.idle;
      _commandModeActive = false;
      _commandModeTimeoutTimer?.cancel();
      _wakeRearmTimer?.cancel();
      _clearCommandSessionState();
      await _stopListening();
      await _tts.stop();
      assistantStateText.value = 'Voice assistant disabled';
      return;
    }

    if (!microphoneGranted.value) {
      final granted = await requestMicrophonePermission();
      if (!granted) {
        assistantStateText.value =
            'Microphone permission denied. Enable it from system settings.';
        return;
      }
    }

    if (!_speechReady) {
      await _initializeSpeechRecognizer();
    }

    _setIdleTapPromptState();
  }

  Future<bool> requestMicrophonePermission() async {
    if (!Platform.isAndroid) {
      microphoneGranted.value = false;
      return false;
    }

    final status = await Permission.microphone.request();
    microphoneGranted.value = status.isGranted;

    if (microphoneGranted.value && !_speechReady) {
      await _initializeSpeechRecognizer();
    }

    return microphoneGranted.value;
  }

  Future<void> setPitch(double value) async {
    _pitch = value.clamp(0.5, 1.8);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefVoicePitch, _pitch);
    await _tts.setPitch(_pitch);
  }

  Future<void> setSpeechRate(double value) async {
    _speechRate = value.clamp(0.2, 0.9);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefVoiceRate, _speechRate);
    await _tts.setSpeechRate(_speechRate);
  }

  Future<void> setVoiceType(String rawType) async {
    final String normalized = _normalizeVoiceType(rawType);
    selectedVoiceType.value = normalized;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefVoiceType, normalized);

    await _applyVoiceTypeSelection();
  }

  Future<void> setVoicePersonality(String rawPersonality) async {
    final String normalized = _normalizePersonality(rawPersonality);
    selectedPersonality.value = normalized;

    final _VoicePreset preset =
        _voicePresets[normalized] ?? _voicePresets[_personalityFriendly]!;

    _pitch = preset.pitch;
    _speechRate = preset.speed;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefVoicePersonality, normalized);
    await prefs.setDouble(_prefVoicePitch, _pitch);
    await prefs.setDouble(_prefVoiceRate, _speechRate);

    await _tts.setPitch(_pitch);
    await _tts.setSpeechRate(_speechRate);
  }

  Future<void> previewVoice() async {
    await speak(
      'Hello, this is your Blindly voice preview. I will use these settings across assistant speech, announcements, and text reader output.',
      resumeWakeListening: true,
      forceWhenDisabled: true,
    );
  }

  Future<void> startWakeListening() async {
    // Wake phrase loop is intentionally disabled in favor of global tap-to-command.
    if (isVoiceBlockedForCurrentScreen()) {
      await _suspendVoiceForBlockedScreen();
      return;
    }

    _voiceMode = _VoiceMode.idle;
    isListening.value = false;
    _setIdleTapPromptState();
  }

  Future<void> ensureWakeListening() async {
    if (!_canListen()) return;
    if (_commandModeActive || _isCommandCapture || _isSpeaking) return;
    _setIdleTapPromptState();
  }

  void onRouteChanged(Route<dynamic>? route) {
    final routeName = _routeName(route);

    final normalizedRoute = routeName.trim().toLowerCase();
    if (VoiceScreenAccessPolicy.isAdminRouteName(normalizedRoute)) {
      _adminFlowActive = true;
    } else if (normalizedRoute.startsWith('/')) {
      // Named non-admin routes indicate we are no longer in admin flow.
      _adminFlowActive = false;
    }

    activeRoute.value = routeName;
    unawaited(_applyScreenPolicy(routeName));
  }

  bool isVoiceBlockedForCurrentScreen({String? routeName}) {
    final resolvedRoute = routeName ?? activeRoute.value;
    if (VoiceScreenAccessPolicy.isVoiceBlocked(routeName: resolvedRoute)) {
      return true;
    }

    final normalizedRoute = resolvedRoute.trim().toLowerCase();
    if (_adminFlowActive &&
        (normalizedRoute.startsWith('materialpageroute') ||
            normalizedRoute == 'unknown')) {
      return true;
    }

    return false;
  }

  bool shouldHandleGlobalTap({required bool isLocalVoiceScreenActive}) {
    if (isLocalVoiceScreenActive) {
      return false;
    }

    if (isVoiceBlockedForCurrentScreen()) {
      return false;
    }

    return true;
  }

  Future<void> _applyScreenPolicy(String routeName) async {
    if (isVoiceBlockedForCurrentScreen(routeName: routeName)) {
      await _suspendVoiceForBlockedScreen();
      return;
    }

    if (_isSpeaking || !_canListen()) {
      return;
    }

    if (_commandModeActive) {
      await _listenForCommand();
      return;
    }

    _setIdleTapPromptState();
  }

  Future<void> _suspendVoiceForBlockedScreen() async {
    _commandModeActive = false;
    _commandModeTimeoutTimer?.cancel();
    _commandModeTimeoutTimer = null;
    _wakeRearmTimer?.cancel();
    _wakeRearmTimer = null;
    _clearCommandSessionState();
    await _stopListening();

    if (_isSpeaking) {
      try {
        await _tts.stop();
      } catch (_) {
        // Keep app stable if tts stop fails.
      }
      _isSpeaking = false;
    }

    _voiceMode = _VoiceMode.idle;
    assistantStateText.value = 'Voice assistant unavailable on this screen.';
  }

  Future<void> captureCommandNow() async {
    if (isVoiceBlockedForCurrentScreen()) {
      return;
    }

    if (!assistantEnabled.value) {
      assistantStateText.value = 'Enable voice assistant first.';
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastTapTriggeredAt) < _tapTriggerCooldown) {
      return;
    }
    _lastTapTriggeredAt = now;

    if (_isSpeaking || _isCommandCapture || _isFinalizingCommand) {
      return;
    }

    if (!microphoneGranted.value) {
      final granted = await requestMicrophonePermission();
      if (!granted) {
        await speak(
          'Microphone permission is required for voice control.',
          resumeWakeListening: false,
          forceWhenDisabled: true,
        );
        return;
      }
    }

    await _onWakePhraseDetected();
  }

  Future<void> speak(
    String text, {
    bool resumeWakeListening = true,
    bool forceWhenDisabled = false,
  }) async {
    if (text.trim().isEmpty) return;
    if (isVoiceBlockedForCurrentScreen()) return;
    if (!forceWhenDisabled && !assistantEnabled.value) return;
    if (_isSpeaking) return;

    _isSpeaking = true;
    _voiceMode = _VoiceMode.speaking;
    await _stopListening();

    assistantStateText.value = 'Speaking';

    try {
      await _applyVoiceTypeSelection();
      await _tts.speak(text);
    } catch (_) {
      // Keep app stable even if TTS fails.
    } finally {
      _isSpeaking = false;
    }

    if (resumeWakeListening && _canListen()) {
      if (_commandModeActive) {
        await _listenForCommand();
      } else {
        _setIdleTapPromptState();
      }
    }
  }

  Future<void> announceDetections({
    required String mode,
    required List<Detection> detections,
  }) async {
    if (!assistantEnabled.value || detections.isEmpty) return;
    if (_isCommandCapture || _isSpeaking) return;

    final now = DateTime.now();
    if (now.difference(_lastDetectionAnnouncementAt) <
        const Duration(seconds: 4)) {
      return;
    }

    final summary = _buildDetectionSummary(mode, detections);
    if (summary == null || summary.isEmpty) return;

    final signature = '${mode.toLowerCase()}:${summary.toLowerCase()}';
    final isDuplicate = signature == _lastDetectionSignature &&
        now.difference(_lastDetectionAnnouncementAt) <
            const Duration(seconds: 12);

    if (isDuplicate) return;

    _lastDetectionSignature = signature;
    _lastDetectionAnnouncementAt = now;

    await speak(summary);
  }

  String? _buildDetectionSummary(String mode, List<Detection> detections) {
    final sorted = List<Detection>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));

    final indoorPriority = <String>{
      'plate',
      'monitor',
      'keyboard',
      'chair',
      'table',
      'door',
      'bottle',
    };

    final outdoorPriority = <String>{
      'person',
      'boy',
      'girl',
      'car',
      'traffic light',
      'bus',
      'bicycle',
      'motorcycle',
      'truck',
    };

    final prioritySet = mode.toLowerCase() == 'indoor'
        ? indoorPriority
        : outdoorPriority;

    final selected = <String>[];

    for (final detection in sorted) {
      final label = detection.label.trim().toLowerCase();
      if (label.isEmpty) continue;
      if (!prioritySet.contains(label)) continue;
      if (selected.contains(label)) continue;
      selected.add(label);
      if (selected.length == 3) break;
    }

    if (selected.isEmpty) {
      for (final detection in sorted) {
        final label = detection.label.trim().toLowerCase();
        if (label.isEmpty || selected.contains(label)) continue;
        selected.add(label);
        if (selected.length == 2) break;
      }
    }

    if (selected.isEmpty) return null;

    if (selected.length == 1) {
      return '${selected.first} detected';
    }

    if (selected.length == 2) {
      return '${selected[0]} and ${selected[1]} detected';
    }

    return '${selected[0]}, ${selected[1]} and ${selected[2]} detected';
  }

  bool _canListen() {
    return Platform.isAndroid &&
        assistantEnabled.value &&
        microphoneGranted.value &&
        _speechReady &&
        _appForeground &&
        !isVoiceBlockedForCurrentScreen();
  }

  void _setIdleTapPromptState() {
    if (isVoiceBlockedForCurrentScreen()) {
      assistantStateText.value = 'Voice assistant unavailable on this screen.';
      return;
    }

    if (!assistantEnabled.value) {
      assistantStateText.value = 'Voice assistant disabled';
      return;
    }
    if (!microphoneGranted.value) {
      assistantStateText.value = 'Microphone permission is required.';
      return;
    }
    if (!_speechReady) {
      assistantStateText.value =
          'Speech recognition unavailable on this device.';
      return;
    }

    assistantStateText.value = 'Tap anywhere to give a voice command';
  }

  Future<void> _onWakePhraseDetected() async {
    if (_isFinalizingCommand) return;

    final now = DateTime.now();
    if (now.difference(_lastWakeDetectedAt) < _wakeTriggerCooldown) {
      debugPrint('[VoiceAssistant] Ignoring wake phrase due to cooldown.');
      return;
    }
    _lastWakeDetectedAt = now;

    debugPrint('[VoiceAssistant] Tap trigger accepted.');
    _commandModeActive = true;
    _armCommandModeTimeout();
    await _stopListening();
    await speak('What can I do for you', resumeWakeListening: false);
    await Future<void>.delayed(_postPromptDelay);
    await _listenForCommand();
  }

  Future<void> _listenForCommand() async {
    if (!_canListen()) return;
    if (_isFinalizingCommand || _isStartingCommandListen || _isSpeaking) return;

    if (!_commandModeActive) {
      _commandModeActive = true;
    }

    _wakeRearmTimer?.cancel();
    _clearCommandSessionState();
    _isCommandCapture = true;
    _voiceMode = _VoiceMode.commandListening;
    _commandCaptured = false;
    _commandBestTranscript = '';
    _commandSessionId++;
    final sessionId = _commandSessionId;
    _commandWindowEndsAt = DateTime.now().add(commandListenDuration);
    _commandWindowTimer = Timer(commandListenDuration, () {
      unawaited(_finalizeCommandListening(sessionId));
    });

    assistantStateText.value =
        'Listening for command for ${commandListenDuration.inSeconds} seconds...';

    await _startOrRestartCommandListen(sessionId);
  }

  Future<void> _startOrRestartCommandListen(int sessionId) async {
    if (!_canListen()) return;
    if (!_isCommandCapture || sessionId != _commandSessionId) return;
    if (_isFinalizingCommand || _isStartingCommandListen) return;
    if (_speech.isListening) return;

    _isStartingCommandListen = true;
    try {
      final remaining = _remainingCommandWindow();
      if (remaining <= Duration.zero) {
        _isStartingCommandListen = false;
        await _finalizeCommandListening(sessionId);
        return;
      }

      await _speech.listen(
        onResult: _onSpeechResult,
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: false,
        listenFor: remaining,
        pauseFor: _commandPauseFor,
        localeId: 'en_US',
      );

      _voiceMode = _VoiceMode.commandListening;
      isListening.value = true;
      assistantStateText.value = 'Listening for command...';
    } catch (_) {
      if (sessionId != _commandSessionId) {
        _isStartingCommandListen = false;
        return;
      }

      _isCommandCapture = false;
      _commandWindowTimer?.cancel();
      _commandWindowTimer = null;
      assistantStateText.value = 'Could not start command listening.';
      await _exitCommandModeToWake();
    } finally {
      _isStartingCommandListen = false;
    }
  }

  void _onSpeechResult(dynamic result) {
    final recognized = result.recognizedWords.trim();
    if (recognized.isEmpty) return;

    lastHeardText.value = recognized;

    if (_isCommandCapture) {
      _commandBestTranscript = recognized;
      if (result.finalResult) {
        _commandCaptured = true;
        final sessionId = _commandSessionId;
        unawaited(
          _finalizeCommandListening(
            sessionId,
            forceText: recognized,
          ),
        );
      }
      return;
    }

    final normalized = VoiceCommandParser.normalize(recognized);
    final bool isFinal = result.finalResult == true;
    final double confidence = _extractConfidence(result);

    if (_containsWakePhrase(normalized) &&
        _isWakeTriggerAccepted(
          normalized: normalized,
          isFinal: isFinal,
          confidence: confidence,
        )) {
      debugPrint(
        '[VoiceAssistant] Wake phrase candidate accepted. text="$normalized" final=$isFinal confidence=$confidence',
      );
      unawaited(_onWakePhraseDetected());
      return;
    }

    if (_containsWakePhrase(normalized)) {
      debugPrint(
        '[VoiceAssistant] Wake phrase candidate rejected. text="$normalized" final=$isFinal confidence=$confidence',
      );
    }
  }

  void _onSpeechStatus(String status) {
    isListening.value = _speech.isListening;

    if (status != 'done' && status != 'notListening') {
      return;
    }

    if (_isCommandCapture) {
      if (_isFinalizingCommand) return;

      final sessionId = _commandSessionId;
      final windowStillOpen = _remainingCommandWindow() > Duration.zero;

      if (_commandCaptured) {
        unawaited(_finalizeCommandListening(sessionId));
        return;
      }

      if (windowStillOpen) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          unawaited(_startOrRestartCommandListen(sessionId));
        });
      } else {
        unawaited(_finalizeCommandListening(sessionId));
      }
      return;
    }

    if (!_commandModeActive && !_isSpeaking && _canListen()) {
      _setIdleTapPromptState();
    }
  }

  Future<void> _handleCommand(String rawCommand) async {
    final intent = VoiceCommandParser.parse(rawCommand);
    debugPrint(
      '[VoiceAssistant] Command="${intent.rawText}" parsedAs=${intent.action.name}',
    );

    switch (intent.action) {
      case VoiceActionType.openSettings:
        await speak('Opening settings.', resumeWakeListening: false);
        navigatorKey.currentState?.pushNamed('/settings');
        break;
      case VoiceActionType.openProfile:
        await speak('Opening profile screen.', resumeWakeListening: false);
        navigatorKey.currentState?.pushNamed('/profile');
        break;
      case VoiceActionType.openAiChat:
        await speak('Opening AI chat.', resumeWakeListening: false);
        navigatorKey.currentState?.pushNamed('/chat');
        break;
      case VoiceActionType.openVoiceSettings:
        await speak('Opening voice settings.', resumeWakeListening: false);
        navigatorKey.currentState?.pushNamed('/voice-settings');
        break;
      case VoiceActionType.openTextReader:
        await speak('Opening text reader.', resumeWakeListening: false);
        if (NavigationVoiceBridge.instance.navigationVisible.value &&
            NavigationVoiceBridge.instance.detectionRunning.value) {
          NavigationVoiceBridge.instance.send(
            NavigationVoiceCommandType.stopDetection,
          );
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        _openTextReader(autoOpenCamera: intent.preferCamera);
        break;
      case VoiceActionType.openNavigation:
        await speak('Opening navigation.', resumeWakeListening: false);
        _openOrFocusNavigation(
          initialMode: 'Indoor',
          autoStartDetection: false,
        );
        break;
      case VoiceActionType.openIndoorNavigation:
        await speak('Opening indoor navigation.', resumeWakeListening: false);
        _openOrFocusNavigation(
          initialMode: 'Indoor',
          autoStartDetection: false,
        );
        break;
      case VoiceActionType.openOutdoorNavigation:
        await speak('Opening outdoor navigation.', resumeWakeListening: false);
        _openOrFocusNavigation(
          initialMode: 'Outdoor',
          autoStartDetection: false,
        );
        break;
      case VoiceActionType.setThemeLight:
        await ThemeManager.setThemeMode(ThemeMode.light);
        await speak('Changed to light theme.', resumeWakeListening: false);
        break;
      case VoiceActionType.setThemeDark:
        await ThemeManager.setThemeMode(ThemeMode.dark);
        await speak('Changed to dark theme.', resumeWakeListening: false);
        break;
      case VoiceActionType.setThemeSystem:
        await ThemeManager.setThemeMode(ThemeMode.system);
        await speak('Using system theme.', resumeWakeListening: false);
        break;
      case VoiceActionType.setColorBlack:
        await ColorSchemeManager.setPrimaryColor(Colors.black);
        await speak('Changed to black color.', resumeWakeListening: false);
        break;
      case VoiceActionType.setColorRed:
        await ColorSchemeManager.setPrimaryColor(Colors.red);
        await speak('Changed to red color.', resumeWakeListening: false);
        break;
      case VoiceActionType.setColorBlue:
        await ColorSchemeManager.setPrimaryColor(Colors.blue);
        await speak('Changed to blue color.', resumeWakeListening: false);
        break;
      case VoiceActionType.setColorGreen:
        await ColorSchemeManager.setPrimaryColor(Colors.green);
        await speak('Changed to green color.', resumeWakeListening: false);
        break;
      case VoiceActionType.setColorPurple:
        await ColorSchemeManager.setPrimaryColor(Colors.purple);
        await speak('Changed to purple color.', resumeWakeListening: false);
        break;
      case VoiceActionType.setColorOrange:
        await ColorSchemeManager.setPrimaryColor(Colors.orange);
        await speak('Changed to orange color.', resumeWakeListening: false);
        break;
      case VoiceActionType.setColorSeaGreen:
        await ColorSchemeManager.setPrimaryColor(const Color(0xFF2E8B57));
        await speak('Changed to sea green color.', resumeWakeListening: false);
        break;
      case VoiceActionType.startIndoorDetection:
        await speak('Starting indoor detection.', resumeWakeListening: false);
        _startDetectionFromVoice(isIndoor: true);
        break;
      case VoiceActionType.startOutdoorDetection:
        await speak('Starting outdoor detection.', resumeWakeListening: false);
        _startDetectionFromVoice(isIndoor: false);
        break;
      case VoiceActionType.stopDetection:
        await _stopDetectionFromVoice();
        break;
      case VoiceActionType.goHome:
        await speak('Going to home screen.', resumeWakeListening: false);
        navigatorKey.currentState
            ?.pushNamedAndRemoveUntil('/dashboard', (_) => false);
        break;
      case VoiceActionType.unknown:
        await speak(
          'I can help with settings, profile, navigation, detection, text reader, AI chat, theme changes, color changes, and going home. Please try one of the supported commands.',
          resumeWakeListening: false,
        );
        break;
    }

  }

  Future<void> _finalizeCommandListening(
    int sessionId, {
    String? forceText,
  }) async {
    if (sessionId != _commandSessionId) return;
    if (_isFinalizingCommand) return;

    _isFinalizingCommand = true;

    final transcript =
        (forceText != null && forceText.trim().isNotEmpty)
        ? forceText.trim()
        : _commandBestTranscript.trim();

    _commandWindowTimer?.cancel();
    _commandWindowTimer = null;
    _commandWindowEndsAt = null;
    _isCommandCapture = false;
    _voiceMode = _VoiceMode.idle;
    _commandCaptured = transcript.isNotEmpty;

    await _stopListening();

    if (transcript.isNotEmpty) {
      assistantStateText.value = 'Processing command...';
      await _handleCommand(transcript);
    } else {
      await speak(
        'I did not catch that. Tap again and try.',
        resumeWakeListening: false,
      );
    }

    _commandBestTranscript = '';
    _isFinalizingCommand = false;
    await _exitCommandModeToWake();
  }

  void _openNavigation({
    required String initialMode,
    required bool autoStartDetection,
  }) {
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => nav.NavigationScreen(
          initialMode: initialMode,
          autoStartDetection: autoStartDetection,
        ),
      ),
    );
  }

  void _openOrFocusNavigation({
    required String initialMode,
    required bool autoStartDetection,
  }) {
    final bridge = NavigationVoiceBridge.instance;

    final bool targetIndoor = initialMode.toLowerCase() != 'outdoor';
    final NavigationVoiceCommandType selectCommand = targetIndoor
        ? NavigationVoiceCommandType.selectIndoor
        : NavigationVoiceCommandType.selectOutdoor;
    final NavigationVoiceCommandType startCommand = targetIndoor
        ? NavigationVoiceCommandType.startIndoorDetection
        : NavigationVoiceCommandType.startOutdoorDetection;

    if (bridge.navigationVisible.value) {
      debugPrint(
        '[VoiceAssistant] Navigation already visible. Selecting $initialMode mode.',
      );
      bridge.send(selectCommand);

      if (autoStartDetection) {
        debugPrint(
          '[VoiceAssistant] Sending start detection command for $initialMode.',
        );
        bridge.send(startCommand);
      }
      return;
    }

    debugPrint(
      '[VoiceAssistant] Opening navigation screen. mode=$initialMode autoStart=$autoStartDetection',
    );
    _openNavigation(
      initialMode: initialMode,
      autoStartDetection: autoStartDetection,
    );
  }

  void _openTextReader({required bool autoOpenCamera}) {
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => TextReaderScreen(autoOpenCamera: autoOpenCamera),
      ),
    );
  }

  void _startDetectionFromVoice({required bool isIndoor}) {
    _openOrFocusNavigation(
      initialMode: isIndoor ? 'Indoor' : 'Outdoor',
      autoStartDetection: true,
    );
  }

  Future<void> _stopDetectionFromVoice() async {
    final bridge = NavigationVoiceBridge.instance;

    if (bridge.navigationVisible.value && bridge.detectionRunning.value) {
      bridge.send(NavigationVoiceCommandType.stopDetection);
      await speak('Stopping detection now.', resumeWakeListening: false);
      return;
    }

    await speak('Detection is not currently running.', resumeWakeListening: false);
  }

  bool _containsWakePhrase(String normalized) {
    final words = normalized.split(' ');
    return words.contains(wakePhrase);
  }

  double _extractConfidence(dynamic result) {
    try {
      final dynamic confidence = result.confidence;
      if (confidence is num) {
        return confidence.toDouble();
      }
    } catch (_) {
      // Some engines may not provide confidence.
    }
    return -1;
  }

  bool _isWakeTriggerAccepted({
    required String normalized,
    required bool isFinal,
    required double confidence,
  }) {
    final words = normalized
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .toList(growable: false);

    if (words.length > _maxWakePhraseWords) {
      return false;
    }

    if (confidence >= 0 && confidence < _wakeConfidenceThreshold) {
      return false;
    }

    if (!isFinal) {
      if (confidence < _wakeHighConfidencePartial) {
        return false;
      }
    }

    return true;
  }

  void _armCommandModeTimeout() {
    _commandModeTimeoutTimer?.cancel();
    if (!_commandModeActive) return;

    _commandModeTimeoutTimer = Timer(_commandModeInactivityTimeout, () {
      unawaited(_exitCommandModeToWake());
    });
  }

  Future<void> _exitCommandModeToWake() async {
    _commandModeActive = false;
    _commandModeTimeoutTimer?.cancel();
    _clearCommandSessionState();
    await _stopListening();

    if (_canListen()) {
      _setIdleTapPromptState();
    }
  }

  Duration _remainingCommandWindow() {
    final endsAt = _commandWindowEndsAt;
    if (endsAt == null) return Duration.zero;
    return endsAt.difference(DateTime.now());
  }

  String _routeName(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && name.trim().isNotEmpty) {
      return name.trim();
    }
    return route?.runtimeType.toString() ?? 'unknown';
  }

  String _normalizeVoiceType(String? raw) {
    final lower = raw?.trim().toLowerCase() ?? '';
    if (lower == 'female') return _voiceTypeFemale;
    if (lower == 'male') return _voiceTypeMale;
    return _voiceTypeNeutral;
  }

  String _normalizePersonality(String? raw) {
    final lower = raw?.trim().toLowerCase() ?? '';
    if (lower == 'calm') return _personalityCalm;
    if (lower == 'energetic') return _personalityEnergetic;
    return _personalityFriendly;
  }

  String _firstNonEmpty(List<String?> candidates, {String fallback = ''}) {
    for (final String? candidate in candidates) {
      final value = candidate?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return fallback;
  }

  Future<void> _applyVoiceTypeSelection() async {
    if (!Platform.isAndroid) return;
    if (_availableVoices.isEmpty) return;

    final _TtsVoiceCandidate selected = _pickVoiceForType(
      selectedVoiceType.value,
    );

    _activeVoice = selected;
    selectedVoiceLabel.value = '${selected.name} (${selected.locale})';

    final Map<String, String> voiceMap = <String, String>{
      'name': selected.name,
      'locale': selected.locale,
    };

    try {
      await _tts.setVoice(voiceMap);
    } catch (_) {
      selectedVoiceLabel.value = 'Using default device voice';
    }

    voiceSupportNote.value = _buildVoiceSupportNote();
  }

  _TtsVoiceCandidate _pickVoiceForType(String type) {
    final requestedType = _normalizeVoiceType(type);

    _TtsVoiceCandidate best = _availableVoices.first;
    int bestScore = -100000;

    for (final candidate in _availableVoices) {
      final score = _scoreVoiceCandidate(candidate, requestedType);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best;
  }

  int _scoreVoiceCandidate(_TtsVoiceCandidate candidate, String requestedType) {
    final text = candidate.searchable;
    int score = 0;

    if (candidate.locale.toLowerCase().startsWith('en')) {
      score += 40;
    }

    final femaleTokens = <String>[
      'female',
      'woman',
      'girl',
      'feminine',
      'samantha',
      'victoria',
      'zira',
      'hazel',
      'eva',
    ];
    final maleTokens = <String>[
      'male',
      'man',
      'boy',
      'masculine',
      'david',
      'alex',
      'fred',
      'mark',
      'tom',
    ];
    final neutralTokens = <String>[
      'neutral',
      'default',
      'google',
      'standard',
      'voice',
    ];

    int containsAny(List<String> tokens) {
      for (final token in tokens) {
        if (text.contains(token)) return 1;
      }
      return 0;
    }

    if (requestedType == _voiceTypeFemale) {
      score += containsAny(femaleTokens) * 100;
      score -= containsAny(maleTokens) * 25;
    } else if (requestedType == _voiceTypeMale) {
      score += containsAny(maleTokens) * 100;
      score -= containsAny(femaleTokens) * 25;
    } else {
      score += containsAny(neutralTokens) * 90;
      score += containsAny(femaleTokens) * 20;
      score += containsAny(maleTokens) * 20;
    }

    return score;
  }

  String _buildVoiceSupportNote() {
    if (!Platform.isAndroid) {
      return 'Voice selection is available on Android only.';
    }
    if (_availableVoices.isEmpty) {
      return 'No explicit voice list available from the TTS engine. Default voice is used.';
    }

    final selected = _activeVoice;
    if (selected == null) {
      return 'Available voices depend on your Android device and TTS engine.';
    }

    return 'Available voices depend on your Android device and TTS engine. Current voice: ${selected.name} (${selected.locale}).';
  }

  void _clearCommandSessionState() {
    _commandWindowTimer?.cancel();
    _commandWindowTimer = null;
    _commandWindowEndsAt = null;
    _isCommandCapture = false;
    _commandCaptured = false;
    _isFinalizingCommand = false;
    _isStartingCommandListen = false;
    if (_voiceMode != _VoiceMode.paused && !_isSpeaking) {
      _voiceMode = _VoiceMode.idle;
    }
    _commandBestTranscript = '';
  }

  Future<void> _stopListening() async {
    _wakeRearmTimer?.cancel();

    if (_speech.isListening) {
      try {
        await _speech.stop();
      } catch (_) {
        // Keep app stable even if stop throws.
      }
    }

    if (_voiceMode != _VoiceMode.paused && !_isSpeaking) {
      _voiceMode = _VoiceMode.idle;
    }
    isListening.value = false;
  }
}
