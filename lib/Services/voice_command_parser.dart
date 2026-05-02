enum VoiceActionType {
  openSettings,
  openProfile,
  openAiChat,
  openVoiceSettings,
  openTextReader,
  openObjectDetection,
  startObjectDetection,
  setThemeLight,
  setThemeDark,
  setThemeSystem,
  setColorBlack,
  setColorRed,
  setColorBlue,
  setColorGreen,
  setColorPurple,
  setColorOrange,
  setColorSeaGreen,
  stopDetection,
  goHome,
  unknown,
}

class VoiceCommandIntent {
  final VoiceActionType action;
  final String rawText;
  final String normalizedText;
  final bool preferCamera;

  const VoiceCommandIntent({
    required this.action,
    required this.rawText,
    required this.normalizedText,
    this.preferCamera = false,
  });

  bool get isKnown => action != VoiceActionType.unknown;
}

class VoiceCommandParser {
  static const List<String> supportedCommandExamples = [
    'open settings screen',
    'go to settings',
    'go to profile screen',
    'open profile',
    'open ai chat',
    'go to ai chat',
    'open voice settings',
    'go to voice settings',
    'change to light theme',
    'change to dark theme',
    'use system theme',
    'change to black color',
    'change to red color',
    'change to blue color',
    'change to green color',
    'change to purple color',
    'change to orange color',
    'change to sea green color',
    'open text reader',
    'start text reader',
    'open camera for text reading',
    'read text',
    'open object detection',
    'start object detection',
    'open detection',
    'start detection',
    'go to object detection',
    'stop detection',
    'open home',
    'go home',
  ];

  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static VoiceCommandIntent parse(String rawText) {
    final normalized = normalize(rawText);
    if (normalized.isEmpty) {
      return VoiceCommandIntent(
        action: VoiceActionType.unknown,
        rawText: rawText,
        normalizedText: normalized,
      );
    }

    if (_hasAny(normalized, [
      'go home',
      'open home',
      'home screen',
      'dashboard',
    ])) {
      return _intent(VoiceActionType.goHome, rawText, normalized);
    }

    if (_hasAny(normalized, [
      'go to profile',
      'open profile',
      'profile screen',
      'my profile',
    ])) {
      return _intent(VoiceActionType.openProfile, rawText, normalized);
    }

    if (_hasAny(normalized, ['light theme', 'theme light'])) {
      return _intent(VoiceActionType.setThemeLight, rawText, normalized);
    }

    if (_hasAny(normalized, ['dark theme', 'theme dark'])) {
      return _intent(VoiceActionType.setThemeDark, rawText, normalized);
    }

    if (_hasAny(normalized, [
      'system theme',
      'default theme',
      'use system',
    ])) {
      return _intent(VoiceActionType.setThemeSystem, rawText, normalized);
    }

    final mentionsColor =
        _hasWord(normalized, 'color') || _hasWord(normalized, 'colour');

    if (_hasWord(normalized, 'black') &&
        (mentionsColor ||
            _hasAny(normalized, ['change to black', 'set black', 'make black']))) {
      return _intent(VoiceActionType.setColorBlack, rawText, normalized);
    }

    if (_hasWord(normalized, 'red') &&
        (mentionsColor ||
            _hasAny(normalized, ['change to red', 'set red', 'make red']))) {
      return _intent(VoiceActionType.setColorRed, rawText, normalized);
    }

    if (_hasWord(normalized, 'blue') &&
      (mentionsColor ||
        _hasAny(normalized, ['change to blue', 'set blue', 'make blue']))) {
      return _intent(VoiceActionType.setColorBlue, rawText, normalized);
    }

    if (_hasWord(normalized, 'green') &&
      (mentionsColor ||
        _hasAny(normalized, ['change to green', 'set green', 'make green']))) {
      return _intent(VoiceActionType.setColorGreen, rawText, normalized);
    }

    if (_hasWord(normalized, 'purple') &&
      (mentionsColor ||
        _hasAny(normalized, ['change to purple', 'set purple', 'make purple']))) {
      return _intent(VoiceActionType.setColorPurple, rawText, normalized);
    }

    if (_hasWord(normalized, 'orange') &&
      (mentionsColor ||
        _hasAny(normalized, ['change to orange', 'set orange', 'make orange']))) {
      return _intent(VoiceActionType.setColorOrange, rawText, normalized);
    }

    final mentionsSeaGreen =
        _hasAny(normalized, ['sea green', 'seagreen', 'teal']);

    if (mentionsSeaGreen &&
      (mentionsColor ||
        _hasAny(normalized, ['change to sea green', 'set sea green', 'make sea green']))) {
      return _intent(VoiceActionType.setColorSeaGreen, rawText, normalized);
    }

    final mentionsTextReader = _hasAny(normalized, [
      'text reader',
      'text reading',
      'read text',
      'camera for text reading',
      'text scanner',
    ]);

    if (mentionsTextReader) {
      final preferCamera = _hasAny(normalized, [
        'camera',
        'capture',
        'take picture',
      ]);

      return _intent(
        VoiceActionType.openTextReader,
        rawText,
        normalized,
        preferCamera: preferCamera,
      );
    }

    if (_hasWord(normalized, 'stop') &&
        _hasAny(normalized, ['detection', 'detect', 'camera'])) {
      return _intent(VoiceActionType.stopDetection, rawText, normalized);
    }

    final bool mentionsDetection = _hasAny(normalized, [
      'detection',
      'detect',
      'detector',
    ]);
    final bool mentionsStartOrOpen = _hasAnyWord(normalized, [
      'start',
      'begin',
      'run',
      'open',
      'go',
    ]);

    if (mentionsDetection && mentionsStartOrOpen) {
      if (_hasWord(normalized, 'start') || _hasWord(normalized, 'run') || _hasWord(normalized, 'begin')) {
        return _intent(VoiceActionType.startObjectDetection, rawText, normalized);
      }
      return _intent(VoiceActionType.openObjectDetection, rawText, normalized);
    }

    if (_hasWord(normalized, 'open') || _hasWord(normalized, 'go')) {
      if (_hasAny(normalized, ['voice settings', 'voice setting'])) {
        return _intent(VoiceActionType.openVoiceSettings, rawText, normalized);
      }

      if (_hasWord(normalized, 'voice')) {
        return _intent(VoiceActionType.openVoiceSettings, rawText, normalized);
      }

      if (_hasAny(normalized, ['text reader', 'text reading', 'read text'])) {
        return _intent(
          VoiceActionType.openTextReader,
          rawText,
          normalized,
          preferCamera: _hasAny(normalized, ['camera', 'capture']),
        );
      }

      if (_hasAny(normalized, [
        'ai chat',
        'a i chat',
        'assistant chat',
        'chat bot',
        'chatbot',
      ])) {
        return _intent(VoiceActionType.openAiChat, rawText, normalized);
      }

      if (_hasWord(normalized, 'home')) {
        return _intent(VoiceActionType.goHome, rawText, normalized);
      }

      if (_hasWord(normalized, 'profile')) {
        return _intent(VoiceActionType.openProfile, rawText, normalized);
      }

      if (_hasAny(normalized, ['settings', 'setting'])) {
        return _intent(VoiceActionType.openSettings, rawText, normalized);
      }
    }

    return _intent(VoiceActionType.unknown, rawText, normalized);
  }

  static VoiceCommandIntent _intent(
    VoiceActionType action,
    String rawText,
    String normalized,
    {
      bool preferCamera = false,
    }
  ) {
    return VoiceCommandIntent(
      action: action,
      rawText: rawText,
      normalizedText: normalized,
      preferCamera: preferCamera,
    );
  }

  static bool _hasAny(String normalized, List<String> phrases) {
    for (final phrase in phrases) {
      if (normalized.contains(phrase)) {
        return true;
      }
    }
    return false;
  }

  static bool _hasWord(String normalized, String word) {
    final words = normalized.split(' ');
    return words.contains(word);
  }

  static bool _hasAnyWord(String normalized, List<String> words) {
    for (final word in words) {
      if (_hasWord(normalized, word)) {
        return true;
      }
    }
    return false;
  }
}
