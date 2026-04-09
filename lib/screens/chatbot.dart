import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../Services/gemini_service.dart';
import '../Services/voice_assistant_service.dart';
import '../models/chat_message.dart';

class AIAssistantScreen extends StatefulWidget {
  static final ValueNotifier<bool> isActive = ValueNotifier<bool>(false);

  const AIAssistantScreen({super.key});

  @override
  State<AIAssistantScreen> createState() => _AIAssistantScreenState();
}

class _AIAssistantScreenState extends State<AIAssistantScreen> {
  final GeminiService _geminiService = GeminiService();
  final VoiceAssistantService _voiceAssistant = VoiceAssistantService.instance;
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _controller = TextEditingController();
  final stt.SpeechToText _localSpeech = stt.SpeechToText();

  static const Duration _voiceListenFor = Duration(seconds: 45);
  static const Duration _voicePauseFor = Duration(seconds: 3);

  static const List<String> _goHomeCommandPhrases = <String>[
    'go home',
    'go to home',
    'go to home screen',
    'home screen',
    'open home',
  ];

  final List<ChatMessage> _messages = [
    ChatMessage(
      text:
          'Hi, I am your Blindly app assistant. Tap anywhere and speak your question. Say "go home" to return to dashboard.',
      role: ChatRole.assistant,
      createdAt: DateTime.now(),
    ),
  ];

  bool _isLoading = false;
  bool _isListeningForVoice = false;
  bool _localSpeechReady = false;
  bool _voiceCommandHandled = false;

  String _voiceStatus =
      'Tap anywhere and speak to chat with AI. Say "go home" to return.';
  String _lastSpokenText = '';

  Timer? _voiceTimeoutTimer;

  @override
  void initState() {
    super.initState();
    AIAssistantScreen.isActive.value = true;
  }

  @override
  void dispose() {
    AIAssistantScreen.isActive.value = false;
    _voiceTimeoutTimer?.cancel();
    _voiceTimeoutTimer = null;
    unawaited(_localSpeech.stop());
    _controller.dispose();
    _scrollController.dispose();
    _geminiService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color accentColor = theme.colorScheme.primary;

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
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.06),
              child: Icon(
                Icons.android_rounded,
                color: theme.colorScheme.onSurface,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'AI Assistant',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Text(
              'Online',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _handleScreenTapForVoiceInput,
        child: Column(
          children: [
            _buildVoiceHintCard(theme),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (_isLoading && index == _messages.length) {
                    return _buildLoadingBubble();
                  }

                  final msg = _messages[index];
                  final isUser = msg.isUser;
                  return Align(
                    alignment:
                        isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isUser ? accentColor : theme.colorScheme.surface,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(14),
                          topRight: const Radius.circular(14),
                          bottomLeft: Radius.circular(isUser ? 14 : 0),
                          bottomRight: Radius.circular(isUser ? 0 : 14),
                        ),
                      ),
                      child: Text(
                        msg.text,
                        style: TextStyle(
                          color: isUser
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSurface,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _quickButton('How do I start outdoor detection?'),
                  _quickButton('What does Text Reader do?'),
                  _quickButton('How do I change settings?'),
                ],
              ),
            ),
            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.all(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.12),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isListeningForVoice
                            ? Icons.mic
                            : FontAwesomeIcons.microphone,
                        color: accentColor,
                      ),
                      onPressed: _isListeningForVoice
                          ? null
                          : _handleScreenTapForVoiceInput,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onSubmitted: (_) => _sendMessage(),
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'Ask how to use this app...',
                          hintStyle: TextStyle(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.send_rounded, color: accentColor),
                      onPressed: _isLoading ? null : _sendMessage,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(1),
    );
  }

  Widget _buildVoiceHintCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isListeningForVoice
                ? 'Listening for your question...'
                : 'Tap anywhere to ask with voice.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _voiceStatus,
            style: theme.textTheme.bodySmall,
          ),
          if (_lastSpokenText.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Heard: "$_lastSpokenText"',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  Widget _quickButton(String text) {
    final theme = Theme.of(context);
    final Color accentColor = theme.colorScheme.primary;
    return GestureDetector(
      onTap: _isLoading ? null : () => _sendQuickMessage(text),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentColor.withValues(alpha: 0.18)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingBubble() {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomRight: Radius.circular(14),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Assistant is typing...',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendQuickMessage(String text) async {
    await _handleSendMessage(text);
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    _controller.clear();
    await _handleSendMessage(text);
  }

  Future<void> _handleScreenTapForVoiceInput() async {
    if (_isLoading || _isListeningForVoice) return;

    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      if (!mounted) return;
      setState(() {
        _voiceStatus = 'Microphone permission is required for AI voice input.';
      });
      await _voiceAssistant.speak(
        'Microphone permission is required for AI chat voice input.',
        resumeWakeListening: false,
        forceWhenDisabled: true,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isListeningForVoice = true;
      _voiceCommandHandled = false;
      _lastSpokenText = '';
      _voiceStatus =
          'Speak your AI question now. You can ask anything. Say go home to return.';
    });

    await _voiceAssistant.speak(
      'Speak your AI question now. You can ask anything. Say go home to return.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    if (!mounted || !_isListeningForVoice) return;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _listenForVoiceQuestion();
  }

  Future<void> _listenForVoiceQuestion() async {
    if (!_isListeningForVoice || !mounted) return;

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
        _isListeningForVoice = false;
        _voiceStatus = 'Voice recognition is unavailable on this device right now.';
      });
      return;
    }

    _voiceTimeoutTimer?.cancel();
    _voiceTimeoutTimer = Timer(
      _voiceListenFor + const Duration(seconds: 2),
      () {
        unawaited(_finishVoiceListening(noVoiceHeard: true));
      },
    );

    try {
      await _localSpeech.listen(
        onResult: _onLocalSpeechResult,
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        listenFor: _voiceListenFor,
        pauseFor: _voicePauseFor,
        localeId: 'en_US',
      );

      if (!mounted) return;
      setState(() {
        _voiceStatus =
            'Listening... keep speaking. Your message will send when you stop.';
      });
    } catch (_) {
      await _finishVoiceListening(
        noVoiceHeard: false,
        customStatus: 'Could not start listening. Tap and try again.',
      );
    }
  }

  void _onLocalSpeechResult(dynamic result) {
    final heardText = result.recognizedWords.trim();
    if (heardText.isEmpty || !mounted || !_isListeningForVoice) {
      return;
    }

    setState(() {
      _lastSpokenText = heardText;
    });

    if (!_voiceCommandHandled && _isGoHomeCommand(heardText)) {
      final normalized = _normalizeVoiceText(heardText);
      final shortPhrase = normalized.split(' ').length <= 5;
      if (result.finalResult || shortPhrase) {
        _voiceCommandHandled = true;
        unawaited(_handleGoHomeVoiceCommand());
        return;
      }
    }

    if (result.finalResult && !_voiceCommandHandled) {
      _voiceCommandHandled = true;
      unawaited(
        _finishVoiceListening(
          noVoiceHeard: false,
          sendRecognizedText: true,
          recognizedText: heardText,
        ),
      );
    }
  }

  void _onLocalSpeechStatus(String status) {
    if (!_isListeningForVoice || _voiceCommandHandled) return;
    if (status == 'done' || status == 'notListening') {
      unawaited(
        _finishVoiceListening(
          noVoiceHeard: _lastSpokenText.trim().isEmpty,
          sendRecognizedText: _lastSpokenText.trim().isNotEmpty,
          recognizedText: _lastSpokenText,
        ),
      );
    }
  }

  void _onLocalSpeechError(dynamic error) {
    if (!_isListeningForVoice || _voiceCommandHandled) return;
    unawaited(
      _finishVoiceListening(
        noVoiceHeard: false,
        customStatus: 'Could not understand that. Tap and try again.',
      ),
    );
  }

  Future<void> _handleGoHomeVoiceCommand() async {
    await _finishVoiceListening(
      noVoiceHeard: false,
      customStatus: 'Going home...',
    );

    await _voiceAssistant.speak(
      'Going to home screen.',
      resumeWakeListening: false,
      forceWhenDisabled: true,
    );

    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/dashboard', (_) => false);
  }

  Future<void> _finishVoiceListening({
    required bool noVoiceHeard,
    bool sendRecognizedText = false,
    String? recognizedText,
    String? customStatus,
  }) async {
    _voiceTimeoutTimer?.cancel();
    _voiceTimeoutTimer = null;

    try {
      if (_localSpeech.isListening) {
        await _localSpeech.stop();
      }
    } catch (_) {
      // Keep UX stable if stop fails.
    }

    if (!mounted) return;

    setState(() {
      _isListeningForVoice = false;
      if (customStatus != null) {
        _voiceStatus = customStatus;
      } else if (noVoiceHeard) {
        _voiceStatus = 'No voice detected. Tap and try again.';
      } else {
        _voiceStatus = 'Voice question captured.';
      }
    });

    if (!sendRecognizedText) return;

    final messageText = (recognizedText ?? _lastSpokenText).trim();
    if (messageText.isEmpty) return;

    if (_isGoHomeCommand(messageText)) {
      await _handleGoHomeVoiceCommand();
      return;
    }

    if (mounted) {
      setState(() {
        _voiceStatus = 'Sending your voice question to AI...';
      });
    }

    await _handleSendMessage(messageText);

    if (mounted) {
      setState(() {
        _voiceStatus =
            'Voice question sent. Tap anywhere to ask another question.';
      });
    }
  }

  bool _isGoHomeCommand(String rawText) {
    final normalized = _normalizeVoiceText(rawText);
    for (final phrase in _goHomeCommandPhrases) {
      if (normalized == phrase || normalized.contains(phrase)) {
        return true;
      }
    }
    return false;
  }

  String _normalizeVoiceText(String rawText) {
    return rawText
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<void> _handleSendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;

    setState(() {
      _messages.add(
        ChatMessage(
          text: trimmed,
          role: ChatRole.user,
          createdAt: DateTime.now(),
        ),
      );
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final reply = await _geminiService.sendMessage(
        userMessage: trimmed,
        history: _messages,
        currentScreen: 'AI Chat',
      );

      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            text: reply,
            role: ChatRole.assistant,
            createdAt: DateTime.now(),
          ),
        );
      });
      _speakAssistantReply(reply);
    } on GeminiServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            text: e.message,
            role: ChatRole.assistant,
            createdAt: DateTime.now(),
          ),
        );
      });
      _speakAssistantReply(e.message);
    } catch (_) {
      const fallbackMessage =
          'Something went wrong while getting help. Please try again.';
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            text: fallbackMessage,
            role: ChatRole.assistant,
            createdAt: DateTime.now(),
          ),
        );
      });
      _speakAssistantReply(fallbackMessage);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _scrollToBottom();
      }
    }
  }

  void _speakAssistantReply(String text) {
    final reply = text.trim();
    if (reply.isEmpty) return;

    unawaited(
      _voiceAssistant.speak(
        reply,
        resumeWakeListening: false,
        forceWhenDisabled: true,
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
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
            break;
          case 2:
            Navigator.pushNamed(context, '/voice-settings');
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
          activeIcon: Icon(Icons.smart_toy),
          label: 'AI Chat',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.mic_none),
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
