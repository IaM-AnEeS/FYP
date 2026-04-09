import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../Services/voice_assistant_service.dart';

enum _VoiceSettingsCommandType {
  setPersonality,
  setSpeedPercent,
  previewVoice,
  goHome,
  unknown,
}

class _VoiceSettingsCommandIntent {
  final _VoiceSettingsCommandType type;
  final String? personality;
  final int? speedPercent;

  const _VoiceSettingsCommandIntent({
    required this.type,
    this.personality,
    this.speedPercent,
  });
}

class VoiceSettingsScreen extends StatefulWidget {
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  final VoiceAssistantService _voiceAssistant = VoiceAssistantService.instance;
  final stt.SpeechToText _localSpeech = stt.SpeechToText();

  static const double _minSpeed = 0.2;
  static const double _maxSpeed = 0.9;
  static const Duration _localCommandListenFor = Duration(seconds: 6);
  static const Duration _localCommandPauseFor = Duration(seconds: 2);

  String _selectedPersonality = 'Friendly';
  double _speed = 0.52;
  bool _loadingVoices = true;

  bool _isListeningForCommand = false;
  bool _isHandlingVoiceCommand = false;
  bool _localSpeechReady = false;

  String _voiceCommandStatus = 'Tap anywhere to speak a Voice Settings command.';
  String _lastHeardCommand = '';

  Timer? _localCommandTimeoutTimer;

  static const List<String> _homeCommands = <String>[
    'go to home',
    'go home',
    'open home',
    'open dashboard',
    'go to dashboard',
    'go to home screen',
  ];

  static const List<String> _previewCommands = <String>[
    'preview voice',
    'test voice',
    'play voice preview',
    'play preview',
  ];

  static const List<String> _calmCommands = <String>[
    'switch to calm',
    'set voice to calm',
    'set personality to calm',
    'voice calm',
    'calm',
  ];

  static const List<String> _energeticCommands = <String>[
    'switch to energetic',
    'set voice to energetic',
    'set personality to energetic',
    'voice energetic',
    'energetic',
  ];

  static const List<String> _friendlyCommands = <String>[
    'switch to friendly',
    'set voice to friendly',
    'set personality to friendly',
    'voice friendly',
    'friendly',
  ];

  static const int _speedStepPercent = 10;

  double _clamp(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  String _normalizeCommandText(String rawText) {
    return rawText
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s%-]'), ' ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _containsAnyPhrase(String normalized, List<String> phrases) {
    for (final phrase in phrases) {
      if (normalized.contains(phrase)) {
        return true;
      }
    }
    return false;
  }

  int _clampPercentage(int value) {
    return value.clamp(0, 100).toInt();
  }

  double _sliderValueFromPercentage(int percentage) {
    final safePercent = _clampPercentage(percentage);
    final range = _maxSpeed - _minSpeed;
    return _minSpeed + (safePercent / 100.0) * range;
  }

  int _percentageFromSlider(double sliderValue) {
    final safe = _clamp(sliderValue, _minSpeed, _maxSpeed);
    final ratio = (safe - _minSpeed) / (_maxSpeed - _minSpeed);
    return _clampPercentage((ratio * 100).round());
  }

  @override
  void initState() {
    super.initState();
    VoiceSettingsScreen.isActive.value = true;
    _selectedPersonality = _voiceAssistant.personality;
    _speed = _voiceAssistant.speechRate;

    unawaited(_initializeVoiceSettings());
  }

  @override
  void dispose() {
    VoiceSettingsScreen.isActive.value = false;
    _localCommandTimeoutTimer?.cancel();
    _localCommandTimeoutTimer = null;
    unawaited(_localSpeech.stop());
    super.dispose();
  }

  Future<void> _initializeVoiceSettings() async {
    await _voiceAssistant.refreshAvailableVoices();
    await _voiceAssistant.setVoiceType('Neutral');
    if (!mounted) return;
    setState(() {
      _loadingVoices = false;
      _selectedPersonality = _voiceAssistant.personality;
      _speed = _clamp(_voiceAssistant.speechRate, _minSpeed, _maxSpeed);
    });
  }

  Future<void> _applyPersonality(String personality) async {
    await _voiceAssistant.setVoicePersonality(personality);
    if (!mounted) return;
    setState(() {
      _selectedPersonality = _voiceAssistant.personality;
      _speed = _clamp(_voiceAssistant.speechRate, _minSpeed, _maxSpeed);
    });
  }

  Future<void> _applySpeedFromPercentage(
    int percentage, {
    bool speakFeedback = false,
  }) async {
    final int safePercent = _clampPercentage(percentage);
    final double sliderValue = _clamp(
      _sliderValueFromPercentage(safePercent),
      _minSpeed,
      _maxSpeed,
    );

    if (mounted) {
      setState(() {
        _speed = sliderValue;
      });
    }

    await _voiceAssistant.setSpeechRate(sliderValue);

    if (speakFeedback) {
      await _voiceAssistant.speak(
        'Voice speed set to $safePercent percent.',
        resumeWakeListening: false,
        forceWhenDisabled: true,
      );
    }
  }

  int? _parseWordNumber(String text) {
    const units = <String, int>{
      'zero': 0,
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'eleven': 11,
      'twelve': 12,
      'thirteen': 13,
      'fourteen': 14,
      'fifteen': 15,
      'sixteen': 16,
      'seventeen': 17,
      'eighteen': 18,
      'nineteen': 19,
    };

    const tens = <String, int>{
      'twenty': 20,
      'thirty': 30,
      'forty': 40,
      'fifty': 50,
      'sixty': 60,
      'seventy': 70,
      'eighty': 80,
      'ninety': 90,
    };

    final tokens = text
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.trim().isNotEmpty)
        .toList();

    int value = 0;
    bool hasNumberToken = false;

    for (final token in tokens) {
      if (units.containsKey(token)) {
        value += units[token]!;
        hasNumberToken = true;
        continue;
      }

      if (tens.containsKey(token)) {
        value += tens[token]!;
        hasNumberToken = true;
        continue;
      }

      if (token == 'hundred') {
        if (!hasNumberToken) {
          value = 100;
          hasNumberToken = true;
        } else {
          if (value == 0) value = 1;
          value *= 100;
        }
        continue;
      }

      if (token == 'and') {
        continue;
      }

      if (hasNumberToken) {
        break;
      }
    }

    if (!hasNumberToken) return null;
    return value;
  }

  int? _extractPercentageFromCommand(String normalized) {
    final digitMatch = RegExp(r'\b(\d{1,3})\b').firstMatch(normalized);
    if (digitMatch != null) {
      return int.tryParse(digitMatch.group(1)!);
    }

    final tokens = normalized.split(' ');
    final percentIndex = tokens.indexWhere(
      (token) => token == 'percent' || token == 'percentage' || token == '%',
    );

    if (percentIndex > 0) {
      final start = (percentIndex - 5).clamp(0, percentIndex);
      final segment = tokens.sublist(start, percentIndex).join(' ');
      final parsedBeforePercent = _parseWordNumber(segment);
      if (parsedBeforePercent != null) {
        return parsedBeforePercent;
      }
    }

    return _parseWordNumber(normalized);
  }

  int? _deriveSpeedPercentageFromCommand(String normalized) {
    final int? parsedPercent = _extractPercentageFromCommand(normalized);
    if (parsedPercent != null) {
      return parsedPercent;
    }

    final int currentPercent = _percentageFromSlider(_speed);

    final bool wantsIncrease = normalized.contains('increase speed') ||
        normalized.contains('increase the speed') ||
        normalized.contains('faster') ||
        normalized.contains('speed up') ||
        normalized.contains('make it faster') ||
        normalized.contains('make voice faster');

    final bool wantsDecrease = normalized.contains('decrease speed') ||
        normalized.contains('decrease the speed') ||
        normalized.contains('slower') ||
        normalized.contains('slow down') ||
        normalized.contains('make it slower') ||
        normalized.contains('make voice slower');

    if (wantsIncrease && !wantsDecrease) {
      return currentPercent + _speedStepPercent;
    }

    if (wantsDecrease && !wantsIncrease) {
      return currentPercent - _speedStepPercent;
    }

    return null;
  }

  _VoiceSettingsCommandIntent _parseLocalVoiceCommand(String rawCommand) {
    final normalized = _normalizeCommandText(rawCommand);

    if (normalized.isEmpty) {
      return const _VoiceSettingsCommandIntent(
        type: _VoiceSettingsCommandType.unknown,
      );
    }

    if (_containsAnyPhrase(normalized, _homeCommands)) {
      return const _VoiceSettingsCommandIntent(
        type: _VoiceSettingsCommandType.goHome,
      );
    }

    if (_containsAnyPhrase(normalized, _previewCommands)) {
      return const _VoiceSettingsCommandIntent(
        type: _VoiceSettingsCommandType.previewVoice,
      );
    }

    if (_containsAnyPhrase(normalized, _calmCommands)) {
      return const _VoiceSettingsCommandIntent(
        type: _VoiceSettingsCommandType.setPersonality,
        personality: 'Calm',
      );
    }

    if (_containsAnyPhrase(normalized, _energeticCommands)) {
      return const _VoiceSettingsCommandIntent(
        type: _VoiceSettingsCommandType.setPersonality,
        personality: 'Energetic',
      );
    }

    if (_containsAnyPhrase(normalized, _friendlyCommands)) {
      return const _VoiceSettingsCommandIntent(
        type: _VoiceSettingsCommandType.setPersonality,
        personality: 'Friendly',
      );
    }

    final bool referencesSpeed = normalized.contains('speed') ||
        normalized.contains('faster') ||
        normalized.contains('slower') ||
        normalized.contains('speed up') ||
        normalized.contains('slow down') ||
        normalized.contains('increase speed') ||
        normalized.contains('decrease speed');

    if (referencesSpeed) {
      final int? parsedPercent = _deriveSpeedPercentageFromCommand(normalized);
      if (parsedPercent != null) {
        return _VoiceSettingsCommandIntent(
          type: _VoiceSettingsCommandType.setSpeedPercent,
          speedPercent: parsedPercent,
        );
      }
    }

    return const _VoiceSettingsCommandIntent(
      type: _VoiceSettingsCommandType.unknown,
    );
  }

  Future<void> _startLocalVoiceCommandMode() async {
    if (_isListeningForCommand || _isHandlingVoiceCommand || _loadingVoices) {
      return;
    }

    if (!Platform.isAndroid) {
      if (!mounted) return;
      setState(() {
        _voiceCommandStatus =
            'Local voice settings commands are available on Android only.';
      });
      return;
    }

    final granted = await _voiceAssistant.requestMicrophonePermission();
    if (!granted) {
      if (!mounted) return;
      setState(() {
        _voiceCommandStatus =
            'Microphone permission is required for Voice Settings commands.';
      });
      await _voiceAssistant.speak(
        'Microphone permission is required for voice settings commands.',
        resumeWakeListening: false,
        forceWhenDisabled: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isListeningForCommand = true;
      _isHandlingVoiceCommand = false;
      _lastHeardCommand = '';
      _voiceCommandStatus = 'Tell me your voice settings command.';
    });

    await _voiceAssistant.speak(
      'Tell me your voice settings command.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    if (!mounted || !_isListeningForCommand) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _listenForLocalVoiceCommand();
  }

  Future<void> _listenForLocalVoiceCommand() async {
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
        _voiceCommandStatus =
            'Voice recognition is unavailable on this device right now.';
      });
      return;
    }

    _localCommandTimeoutTimer?.cancel();
    _localCommandTimeoutTimer = Timer(
      _localCommandListenFor + const Duration(seconds: 1),
      () {
        unawaited(_finishLocalVoiceListening(noCommandHeard: true));
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
        _voiceCommandStatus =
        'Listening... say switch to calm, set speed to 60 percent, increase speed, preview voice, or go home.';
      });
    } catch (_) {
      await _finishLocalVoiceListening(
        noCommandHeard: false,
        customStatus: 'Could not start listening. Tap and try again.',
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

    final intent = _parseLocalVoiceCommand(heardText);
    if (intent.type != _VoiceSettingsCommandType.unknown &&
        !_isHandlingVoiceCommand) {
      _isHandlingVoiceCommand = true;
      unawaited(_applyLocalVoiceCommand(intent));
      return;
    }

    if (result.finalResult && !_isHandlingVoiceCommand) {
      unawaited(
        _finishLocalVoiceListening(
          noCommandHeard: false,
          customStatus:
              'Command not recognized. Try switch to calm, set speed to 50 percent, increase speed, preview voice, or go home.',
        ),
      );
    }
  }

  void _onLocalSpeechStatus(String status) {
    if (!_isListeningForCommand || _isHandlingVoiceCommand) return;
    if (status == 'done' || status == 'notListening') {
      unawaited(_finishLocalVoiceListening(noCommandHeard: true));
    }
  }

  void _onLocalSpeechError(dynamic error) {
    if (!_isListeningForCommand || _isHandlingVoiceCommand) return;
    unawaited(
      _finishLocalVoiceListening(
        noCommandHeard: false,
        customStatus: 'Could not understand command. Tap and try again.',
      ),
    );
  }

  Future<void> _applyLocalVoiceCommand(_VoiceSettingsCommandIntent intent) async {
    await _finishLocalVoiceListening(
      noCommandHeard: false,
      customStatus: 'Applying command...',
    );

    switch (intent.type) {
      case _VoiceSettingsCommandType.setPersonality:
        final personality = intent.personality ?? 'Friendly';
        await _applyPersonality(personality);
        if (mounted) {
          setState(() {
            _voiceCommandStatus = 'Voice personality set to $personality.';
          });
        }
        await _voiceAssistant.speak(
          'Voice personality set to $personality.',
          resumeWakeListening: false,
          forceWhenDisabled: true,
        );
        break;

      case _VoiceSettingsCommandType.setSpeedPercent:
        final int requestedPercent = intent.speedPercent ?? 0;
        final int safePercent = _clampPercentage(requestedPercent);
        await _applySpeedFromPercentage(safePercent, speakFeedback: true);
        if (mounted) {
          setState(() {
            _voiceCommandStatus = 'Voice speed set to $safePercent percent.';
          });
        }
        break;

      case _VoiceSettingsCommandType.previewVoice:
        if (mounted) {
          setState(() {
            _voiceCommandStatus = 'Playing voice preview...';
          });
        }
        await _voiceAssistant.previewVoice();
        if (mounted) {
          setState(() {
            _voiceCommandStatus = 'Voice preview played.';
          });
        }
        break;

      case _VoiceSettingsCommandType.goHome:
        if (mounted) {
          setState(() {
            _voiceCommandStatus = 'Going to home screen...';
          });
        }
        await _voiceAssistant.speak(
          'Going to home screen.',
          resumeWakeListening: false,
          forceWhenDisabled: true,
        );
        if (!mounted) break;
        Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (_) => false);
        break;

      case _VoiceSettingsCommandType.unknown:
        if (mounted) {
          setState(() {
            _voiceCommandStatus =
                'Command not recognized. Tap and try again.';
          });
        }
        break;
    }

    _isHandlingVoiceCommand = false;
  }

  Future<void> _finishLocalVoiceListening({
    required bool noCommandHeard,
    String? customStatus,
  }) async {
    _localCommandTimeoutTimer?.cancel();
    _localCommandTimeoutTimer = null;

    if (_localSpeech.isListening) {
      try {
        await _localSpeech.stop();
      } catch (_) {
        // Keep screen stable if speech stop fails.
      }
    }

    if (!mounted) return;
    setState(() {
      _isListeningForCommand = false;

      if (customStatus != null) {
        _voiceCommandStatus = customStatus;
      } else if (noCommandHeard) {
        _voiceCommandStatus =
            'I did not catch a command. Tap anywhere and try again.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor:
            theme.appBarTheme.backgroundColor ?? theme.colorScheme.primary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new,
            color: theme.colorScheme.onPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Voice Settings',
          style: TextStyle(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _startLocalVoiceCommandMode,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tap anywhere on this screen and speak a voice settings command.',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isListeningForCommand
                        ? theme.colorScheme.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isListeningForCommand
                          ? theme.colorScheme.primary.withValues(alpha: 0.3)
                          : theme.dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _voiceCommandStatus,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
                        ),
                      ),
                      if (_lastHeardCommand.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Heard: $_lastHeardCommand',
                          style: TextStyle(
                            color:
                                theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      if (_isListeningForCommand) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              Icons.mic_none,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Listening for command...',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildVoiceAssistantCard(theme),
                const SizedBox(height: 20),
                _buildSectionTitle(theme, 'Voice Personality'),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  childAspectRatio: 1.55,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildPersonalityButton(
                      label: 'Calm',
                      icon: Icons.spa,
                      selected: _selectedPersonality == 'Calm',
                      onTap: () => _applyPersonality('Calm'),
                    ),
                    _buildPersonalityButton(
                      label: 'Energetic',
                      icon: Icons.bolt,
                      selected: _selectedPersonality == 'Energetic',
                      onTap: () => _applyPersonality('Energetic'),
                    ),
                    _buildPersonalityButton(
                      label: 'Friendly',
                      icon: Icons.sentiment_satisfied,
                      selected: _selectedPersonality == 'Friendly',
                      onTap: () => _applyPersonality('Friendly'),
                    ),
                  ],
                ),
                const SizedBox(height: 25),
                ValueListenableBuilder<String>(
                  valueListenable: _voiceAssistant.selectedVoiceLabel,
                  builder: (context, label, _) {
                    return Text(
                      'Selected device voice: $label',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),
                ValueListenableBuilder<String>(
                  valueListenable: _voiceAssistant.voiceSupportNote,
                  builder: (context, note, _) {
                    return Text(
                      note,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _buildSlider(
                  theme: theme,
                  label:
                      'Speed (${_percentageFromSlider(_speed)} percent)',
                  value: _speed,
                  min: _minSpeed,
                  max: _maxSpeed,
                  onChanged: (value) {
                    final clamped = _clamp(value, _minSpeed, _maxSpeed);
                    setState(() => _speed = clamped);
                    unawaited(_voiceAssistant.setSpeechRate(clamped));
                  },
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _loadingVoices
                        ? null
                        : () {
                            _voiceAssistant.previewVoice();
                          },
                    icon: const Icon(Icons.record_voice_over_outlined),
                    label: const Text('Preview Voice'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(2),
    );
  }

  Widget _buildVoiceAssistantCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Voice Assistant',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<bool>(
            valueListenable: _voiceAssistant.assistantEnabled,
            builder: (context, enabled, _) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable tap-to-command voice assistant'),
                subtitle: const Text('Android in-app assistant on screen taps'),
                value: enabled,
                onChanged: (value) {
                  _voiceAssistant.setAssistantEnabled(value);
                },
              );
            },
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _voiceAssistant.microphoneGranted,
            builder: (context, granted, _) {
              return Row(
                children: [
                  Icon(
                    granted ? Icons.mic : Icons.mic_off,
                    size: 18,
                    color: granted ? Colors.green : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      granted
                          ? 'Microphone permission granted'
                          : 'Microphone permission required',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  if (!granted)
                    TextButton(
                      onPressed: () {
                        _voiceAssistant.requestMicrophonePermission();
                      },
                      child: const Text('Grant'),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<String>(
            valueListenable: _voiceAssistant.assistantStateText,
            builder: (context, status, _) {
              return Text(
                status,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                _voiceAssistant.captureCommandNow();
              },
              icon: const Icon(Icons.record_voice_over),
              label: const Text('Listen Now'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: TextStyle(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildPersonalityButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected
              ? theme.colorScheme.primary
              : theme.dividerColor.withValues(alpha: 0.2),
          width: 1.2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlider({
    required ThemeData theme,
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: theme.colorScheme.primary,
            thumbColor: theme.colorScheme.primary,
            inactiveTrackColor: theme.colorScheme.onSurface.withValues(alpha: 0.12),
            overlayColor: theme.colorScheme.primary.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: _clamp(value, min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  BottomNavigationBar _buildBottomNav(int selectedIndex) {
    final theme = Theme.of(context);
    return BottomNavigationBar(
      backgroundColor: theme.colorScheme.surface,
      selectedItemColor: theme.colorScheme.primary,
      unselectedItemColor: theme.colorScheme.onSurface.withValues(alpha: 0.7),
      type: BottomNavigationBarType.fixed,
      currentIndex: selectedIndex,
      onTap: (index) {
        switch (index) {
          case 0:
            Navigator.pushNamed(context, '/dashboard');
            break;
          case 1:
            Navigator.pushNamed(context, '/chat');
            break;
          case 2:
            break;
          case 3:
            Navigator.pushNamed(context, '/settings');
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.smart_toy_outlined),
          label: 'AI Chat',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.mic_none),
          activeIcon: Icon(Icons.mic),
          label: 'Voice Settings',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }
}
